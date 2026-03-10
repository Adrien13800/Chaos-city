--[[
    DataService.lua
    Emplacement : ServerScriptService/Services/DataService

    LE SCRIPT LE PLUS IMPORTANT DU JEU.
    Gère le chargement, la sauvegarde et la protection des données joueur.

    POURQUOI DANS ServerScriptService ?
    - Ce script manipule les DataStores (base de données Roblox)
    - Les DataStores ne sont accessibles QUE depuis le serveur
    - Si ce code était côté client, un hacker pourrait se donner de l'argent infini
    - Règle absolue : TOUT ce qui touche à l'argent/XP/inventaire = SERVEUR

    CONCEPTS CLÉS POUR UN DEV VENANT DE PYTHON/JS :

    1. pcall() = try/catch de Lua
       En Lua, il n'y a pas de try/catch. On utilise pcall (protected call) :
       local success, result = pcall(function() ... end)
       - success = true/false (est-ce que la fonction a crashé ?)
       - result = la valeur retournée OU le message d'erreur

    2. DataStoreService
       C'est la "base de données" de Roblox. Chaque joueur a une clé unique
       (son UserId). On peut stocker jusqu'à 4MB par clé. Les données sont
       persistées sur les serveurs de Roblox (pas sur ta machine).
       LIMITES : ~60 requêtes/minute pour GetAsync/SetAsync. C'est pourquoi
       on garde les données EN MÉMOIRE (dans un cache) et on ne sauvegarde
       que périodiquement ou quand le joueur quitte.

    3. Le pattern "Cache en mémoire"
       - Joueur rejoint → on CHARGE depuis DataStore → on stocke dans une table Lua
       - Pendant le jeu → on modifie UNIQUEMENT la table Lua (instantané, 0 latence)
       - Joueur quitte → on SAUVEGARDE la table Lua dans le DataStore
       - Sauvegarde auto toutes les 5 min (au cas où le serveur crash)

    4. BindToClose()
       Quand le serveur Roblox s'arrête (maintenance, crash, mise à jour),
       cette fonction nous donne ~30 secondes pour sauvegarder tous les joueurs.
       CRITIQUE : sans ça, les joueurs perdraient leur progression à chaque
       redémarrage serveur.
]]

-- ============================================================================
-- SERVICES ROBLOX
-- "game:GetService()" est l'équivalent d'un import/require dans Roblox
-- Chaque service est un singleton global fourni par le moteur
-- ============================================================================
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

-- ============================================================================
-- MODULES LOCAUX
-- On charge nos propres modules depuis ReplicatedStorage
-- ============================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerData = require(ReplicatedStorage.Modules.PlayerData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

-- ============================================================================
-- INITIALISATION DU DATASTORE
-- ============================================================================

--[[
    On crée un DataStore nommé "ChaosCityPlayerData".
    Pense à ça comme une "table" dans une base de données SQL.
    Chaque joueur aura une entrée identifiée par "Player_[UserId]".

    IMPORTANT : En Studio (mode test), les DataStores fonctionnent UNIQUEMENT
    si tu actives "Enable Studio Access to API Services" dans :
    Game Settings → Security → Enable Studio Access to API Services
]]
local playerDataStore = DataStoreService:GetDataStore("ChaosCityPlayerData")

-- ============================================================================
-- CACHE EN MÉMOIRE
-- Cette table contient les données de TOUS les joueurs actuellement connectés
-- Format : { [Player.UserId] = { Cash = ..., JobLevels = ..., ... } }
-- ============================================================================
local playerCache = {}

-- Flag pour savoir si un joueur est en cours de chargement (éviter les doublons)
local loadingPlayers = {}

-- ============================================================================
-- MODULE PRINCIPAL
-- ============================================================================
local DataService = {}

-- ============================================================================
-- CHARGEMENT DES DONNÉES
-- Appelé quand un joueur rejoint le serveur
-- ============================================================================
function DataService.LoadPlayerData(player: Player)
    -- Sécurité : éviter de charger deux fois si le joueur rejoint très vite
    if loadingPlayers[player.UserId] then
        return
    end
    loadingPlayers[player.UserId] = true

    -- La clé unique du joueur dans le DataStore
    local key = "Player_" .. player.UserId

    -- Tentative de chargement avec retry
    -- On essaie 3 fois car les DataStores peuvent avoir des erreurs réseau temporaires
    local data = nil
    local success = false
    local errorMessage = ""

    for attempt = 1, 3 do
        -- pcall = try/catch : protège contre les erreurs réseau
        local ok, result = pcall(function()
            return playerDataStore:GetAsync(key)
        end)

        if ok then
            -- GetAsync a réussi
            data = result  -- result peut être nil si c'est un NOUVEAU joueur
            success = true
            break  -- On sort de la boucle, pas besoin de réessayer
        else
            -- Erreur réseau ou DataStore temporairement indisponible
            errorMessage = result
            warn("[DataService] Tentative " .. attempt .. "/3 échouée pour "
                 .. player.Name .. " : " .. tostring(result))

            if attempt < 3 then
                -- Attendre avant de réessayer (backoff exponentiel simplifié)
                task.wait(2 ^ attempt)  -- 2s, 4s
            end
        end
    end

    -- Vérifier que le joueur est toujours connecté (il a pu quitter pendant le chargement)
    if not player.Parent then
        loadingPlayers[player.UserId] = nil
        return
    end

    if success then
        if data then
            -- Joueur EXISTANT : on a trouvé ses données
            -- On s'assure que la structure est à jour (migration)
            data = DataService._MigrateData(data)
            print("[DataService] Données chargées pour " .. player.Name
                  .. " | Cash: $" .. data.Cash .. " | Métier: " .. data.CurrentJob)
        else
            -- NOUVEAU joueur : aucune donnée trouvée, on crée depuis le template
            data = PlayerData.CreateNew()
            print("[DataService] Nouveau joueur ! Données initialisées pour " .. player.Name)
        end

        -- Stocker dans le cache mémoire
        playerCache[player.UserId] = data
    else
        -- Échec TOTAL après 3 tentatives
        -- CHOIX DE DESIGN CRITIQUE : que faire ?
        -- Option A : Kicker le joueur (safe, pas de corruption de données)
        -- Option B : Lui donner des données temporaires (risque de perte)
        -- On choisit A car perdre des données est PIRE qu'un kick
        warn("[DataService] ÉCHEC TOTAL pour " .. player.Name .. " : " .. errorMessage)
        player:Kick("Impossible de charger tes données. Réessaie dans quelques instants.")
    end

    loadingPlayers[player.UserId] = nil
end

-- ============================================================================
-- SAUVEGARDE DES DONNÉES
-- Appelé quand un joueur quitte ou périodiquement
-- ============================================================================
function DataService.SavePlayerData(player: Player)
    local data = playerCache[player.UserId]

    -- Rien à sauvegarder si les données n'ont jamais été chargées
    if not data then
        return false
    end

    local key = "Player_" .. player.UserId

    -- Mettre à jour le timestamp de dernière sauvegarde
    data.LastSave = os.time()

    -- Sauvegarde avec retry (même logique que le chargement)
    for attempt = 1, 3 do
        local ok, err = pcall(function()
            playerDataStore:SetAsync(key, data)
        end)

        if ok then
            print("[DataService] Sauvegarde réussie pour " .. player.Name)
            return true
        else
            warn("[DataService] Erreur sauvegarde (tentative " .. attempt .. "/3) pour "
                 .. player.Name .. " : " .. tostring(err))
            if attempt < 3 then
                task.wait(2 ^ attempt)
            end
        end
    end

    -- Si on arrive ici, les 3 tentatives ont échoué
    warn("[DataService] ÉCHEC SAUVEGARDE pour " .. player.Name .. " après 3 tentatives !")
    return false
end

-- ============================================================================
-- ACCÈS AUX DONNÉES (GETTERS)
-- Les autres services utilisent ces fonctions pour lire les données
-- ============================================================================

-- Récupérer toutes les données d'un joueur
function DataService.GetData(player: Player)
    return playerCache[player.UserId]
end

-- Récupérer le cash d'un joueur
function DataService.GetCash(player: Player): number
    local data = playerCache[player.UserId]
    return data and data.Cash or 0
end

-- Récupérer les étoiles de chaos d'un joueur
function DataService.GetChaosStars(player: Player): number
    local data = playerCache[player.UserId]
    return data and data.ChaosStars or 0
end

-- Récupérer le niveau d'un métier spécifique
function DataService.GetJobLevel(player: Player, jobId: string): number
    local data = playerCache[player.UserId]
    if data and data.JobLevels[jobId] then
        return data.JobLevels[jobId].Level
    end
    return 1
end

-- ============================================================================
-- MODIFICATION DES DONNÉES (SETTERS)
-- TOUTES les modifications passent par ici → point de contrôle unique
-- Ça permet d'ajouter facilement des logs, de l'anti-triche, etc.
-- ============================================================================

-- Ajouter du cash (gains de mission, récompenses)
function DataService.AddCash(player: Player, amount: number): boolean
    local data = playerCache[player.UserId]
    if not data then return false end

    -- SANITY CHECK côté serveur : le montant doit être positif et raisonnable
    -- Un hacker qui envoie un RemoteEvent avec amount = 999999999 sera bloqué ici
    if type(amount) ~= "number" or amount <= 0 or amount > 50000 then
        warn("[DataService] Tentative d'ajout suspect : " .. player.Name
             .. " a essayé d'ajouter $" .. tostring(amount))
        return false
    end

    data.Cash = data.Cash + math.floor(amount)  -- math.floor pour éviter les décimales
    data.Stats.TotalCashEarned = data.Stats.TotalCashEarned + math.floor(amount)

    -- Notifier le client pour mettre à jour l'UI (on créera cet event plus tard)
    -- ReplicatedStorage.Events.RemoteEvents.CashUpdated:FireClient(player, data.Cash)

    return true
end

-- Retirer du cash (achats, frais)
function DataService.RemoveCash(player: Player, amount: number): boolean
    local data = playerCache[player.UserId]
    if not data then return false end

    if type(amount) ~= "number" or amount <= 0 then
        return false
    end

    -- Vérifier que le joueur a assez d'argent
    if data.Cash < amount then
        return false  -- Pas assez de cash → la transaction est refusée
    end

    data.Cash = data.Cash - math.floor(amount)
    return true
end

-- Ajouter des Étoiles de Chaos
function DataService.AddChaosStars(player: Player, amount: number): boolean
    local data = playerCache[player.UserId]
    if not data then return false end

    if type(amount) ~= "number" or amount <= 0 or amount > 100 then
        return false
    end

    data.ChaosStars = data.ChaosStars + math.floor(amount)
    return true
end

-- Ajouter de l'XP à un métier
function DataService.AddJobXP(player: Player, jobId: string, xpAmount: number): boolean
    local data = playerCache[player.UserId]
    if not data then return false end

    -- Vérifier que le métier existe dans la config
    if not GameConfig.Jobs[jobId] then
        warn("[DataService] Métier inconnu : " .. tostring(jobId))
        return false
    end

    if type(xpAmount) ~= "number" or xpAmount <= 0 or xpAmount > 5000 then
        return false
    end

    local jobData = data.JobLevels[jobId]
    if not jobData then return false end

    -- Ajouter l'XP
    jobData.XP = jobData.XP + math.floor(xpAmount)

    -- Vérifier si le joueur monte de niveau
    local maxLevel = GameConfig.Jobs[jobId].MaxLevel
    while jobData.Level < maxLevel do
        local xpNeeded = GameConfig.JobXPRequirements[jobData.Level + 1]
        if xpNeeded and jobData.XP >= xpNeeded then
            jobData.Level = jobData.Level + 1
            print("[DataService] " .. player.Name .. " est maintenant "
                  .. GameConfig.Jobs[jobId].DisplayName .. " Niveau " .. jobData.Level .. " !")
            -- TODO : Notifier le client (popup de level up)
        else
            break  -- Pas assez d'XP pour le prochain niveau
        end
    end

    return true
end

-- Changer le métier actif d'un joueur
function DataService.SetCurrentJob(player: Player, jobId: string): boolean
    local data = playerCache[player.UserId]
    if not data then return false end

    -- Vérifier que le métier existe
    if not GameConfig.Jobs[jobId] then
        return false
    end

    data.CurrentJob = jobId
    print("[DataService] " .. player.Name .. " est maintenant "
          .. GameConfig.Jobs[jobId].DisplayName)
    return true
end

-- Incrémenter un compteur de statistique
function DataService.IncrementStat(player: Player, statName: string, amount: number)
    local data = playerCache[player.UserId]
    if not data or not data.Stats[statName] then return end

    amount = amount or 1
    data.Stats[statName] = data.Stats[statName] + amount
end

-- ============================================================================
-- MIGRATION DE DONNÉES
-- Quand on ajoute de nouveaux champs au Template, les anciens joueurs
-- n'auront pas ces champs. Cette fonction les ajoute automatiquement.
-- C'est l'équivalent d'une "migration de base de données" en SQL.
-- ============================================================================
function DataService._MigrateData(data)
    local template = PlayerData.Template

    -- Parcourir le template et ajouter les champs manquants
    for key, defaultValue in pairs(template) do
        if data[key] == nil then
            -- Ce champ n'existait pas dans les données sauvegardées
            -- On l'ajoute avec la valeur par défaut
            data[key] = PlayerData.DeepCopy(defaultValue)
            print("[DataService] Migration : ajout du champ '" .. key .. "'")
        elseif type(defaultValue) == "table" and type(data[key]) == "table" then
            -- Pour les sous-tables (JobLevels, Stats, etc.), on vérifie aussi en profondeur
            for subKey, subDefault in pairs(defaultValue) do
                if data[key][subKey] == nil then
                    data[key][subKey] = PlayerData.DeepCopy(subDefault)
                    print("[DataService] Migration : ajout du champ '"
                          .. key .. "." .. subKey .. "'")
                end
            end
        end
    end

    return data
end

-- ============================================================================
-- SAUVEGARDE AUTOMATIQUE
-- Sauvegarde tous les joueurs connectés à intervalle régulier
-- ============================================================================
function DataService._StartAutoSave()
    --[[
        task.spawn() crée un nouveau "thread" (coroutine) qui s'exécute en parallèle.

        DIFFÉRENCE AVEC JS/PYTHON :
        - JS utiliserait setInterval() → en Luau, on fait une boucle infinie avec task.wait()
        - Ce n'est PAS un vrai thread OS, c'est une coroutine Lua (coopérative, pas préemptive)
        - task.wait() "pause" cette coroutine et laisse le reste du jeu tourner
    ]]
    task.spawn(function()
        while true do
            task.wait(GameConfig.Server.AutoSaveInterval)

            print("[DataService] Sauvegarde automatique en cours...")
            local count = 0

            for _, player in ipairs(Players:GetPlayers()) do
                if playerCache[player.UserId] then
                    DataService.SavePlayerData(player)
                    count = count + 1
                    -- Petite pause entre chaque sauvegarde pour ne pas surcharger le DataStore
                    task.wait(0.5)
                end
            end

            print("[DataService] Sauvegarde auto terminée : " .. count .. " joueur(s)")
        end
    end)
end

-- ============================================================================
-- ÉVÉNEMENTS DE CONNEXION/DÉCONNEXION
-- ============================================================================
function DataService.Init()
    -- ── Connecter la RemoteFunction GetPlayerData ──
    --[[
        OnServerInvoke est le "handler" côté serveur d'une RemoteFunction.
        Quand le client fait GetPlayerData:InvokeServer(), cette fonction
        s'exécute sur le serveur et retourne le résultat au client.

        SÉCURITÉ : on envoie une COPIE des données, pas la référence directe.
        Si on envoyait la référence, un hacker pourrait potentiellement
        la modifier côté client (même si c'est peu probable en Luau,
        c'est une bonne pratique défensive).
    ]]
    local getPlayerDataFunc = ReplicatedStorage.Events.RemoteFunctions.GetPlayerData
    getPlayerDataFunc.OnServerInvoke = function(player)
        local data = playerCache[player.UserId]
        if not data then
            return nil
        end
        -- Retourner une copie pour la sécurité
        return PlayerData.DeepCopy(data)
    end
    -- Quand un joueur REJOINT le serveur
    Players.PlayerAdded:Connect(function(player)
        DataService.LoadPlayerData(player)
    end)

    -- Quand un joueur QUITTE le serveur
    Players.PlayerRemoving:Connect(function(player)
        DataService.SavePlayerData(player)
        -- Nettoyer le cache pour libérer la mémoire
        playerCache[player.UserId] = nil
    end)

    --[[
        BindToClose : appelé quand le SERVEUR s'arrête

        CRITIQUE : Sans ça, si Roblox redémarre le serveur (maintenance, mise à jour,
        ou si le dernier joueur quitte), les données en mémoire seraient PERDUES.

        On a environ 30 secondes pour tout sauvegarder.
        On utilise task.spawn pour sauvegarder tous les joueurs EN PARALLÈLE
        (au lieu d'un par un séquentiellement).
    ]]
    game:BindToClose(function()
        print("[DataService] Serveur en arrêt — sauvegarde d'urgence !")

        -- Créer une tâche de sauvegarde pour chaque joueur en parallèle
        local threads = {}
        for _, player in ipairs(Players:GetPlayers()) do
            local thread = task.spawn(function()
                DataService.SavePlayerData(player)
            end)
            table.insert(threads, thread)
        end

        -- Attendre que toutes les sauvegardes soient terminées (max 28s de sécurité)
        -- En pratique, une sauvegarde prend < 1 seconde
        task.wait(3)

        print("[DataService] Sauvegarde d'urgence terminée.")
    end)

    -- Gérer les joueurs déjà connectés (cas rare : si le script charge après un joueur)
    for _, player in ipairs(Players:GetPlayers()) do
        if not playerCache[player.UserId] and not loadingPlayers[player.UserId] then
            task.spawn(function()
                DataService.LoadPlayerData(player)
            end)
        end
    end

    -- Démarrer la sauvegarde automatique
    DataService._StartAutoSave()

    print("[DataService] Initialisé avec succès !")
end

return DataService
