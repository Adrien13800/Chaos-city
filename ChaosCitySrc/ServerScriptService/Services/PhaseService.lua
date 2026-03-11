--[[
    PhaseService.lua
    Emplacement : ServerScriptService/Services/PhaseService

    LE CŒUR DU JEU — Gère le cycle des 4 phases :
    Calme (10-14min) → Alerte (2min) → Chaos (3-5min) → Résultat (1min) → boucle

    POURQUOI DANS ServerScriptService ?
    - Le serveur est le SEUL maître du temps. Si le client gérait le timer,
      un hacker pourrait accélérer ou skip les phases.
    - Le serveur décide quand chaque phase commence/finit, puis NOTIFIE
      les clients via RemoteEvent pour qu'ils affichent les effets visuels.

    ARCHITECTURE :
    - Le serveur gère : la logique des phases, les timers, le choix de la catastrophe
    - Le client gère : les effets visuels (sirènes, ciel, caméra shake, UI)
    - Communication : le serveur envoie "PhaseChanged" et "DisasterStarted" aux clients

    CONCEPT CLÉ — La boucle de jeu (Game Loop) :
    Contrairement à un jeu classique qui a un update() par frame,
    notre boucle de phase est un cycle LENT (17 min par tour).
    On utilise task.wait() pour "dormir" entre chaque seconde du countdown.
    Pendant ce temps, le reste du jeu (physique, joueurs, missions) continue normalement.
]]

-- ============================================================================
-- SERVICES ROBLOX
-- ============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ============================================================================
-- MODULES
-- ============================================================================
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

-- ============================================================================
-- REMOTE EVENTS
-- On récupère les events créés par Init.server.lua pour notifier les clients
-- ============================================================================
local remoteEvents = ReplicatedStorage.Events.RemoteEvents
local phaseChangedEvent = remoteEvents.PhaseChanged
local disasterStartedEvent = remoteEvents.DisasterStarted
local heroRankingUpdatedEvent = remoteEvents.HeroRankingUpdated

-- ============================================================================
-- ÉTAT DU SERVICE
-- Ces variables représentent l'état actuel du cycle de jeu
-- ============================================================================
local PhaseService = {}

-- La phase actuelle : "Calm", "Alert", "Chaos", "Result"
local currentPhase = "Calm"

-- Secondes restantes dans la phase actuelle (le countdown)
local timeRemaining = 0

-- Compteur de chaos : combien de chaos ce serveur a survécus d'affilée
-- Utilisé pour le système de combo/escalade
local chaosCount = 0

-- Nombre de joueurs actifs (non KO) pendant le dernier chaos
-- Utilisé pour calculer si le seuil de survie est atteint (70%)
local lastChaosSurvivalRate = 1.0

-- La catastrophe actuellement active (nil si pas en phase Chaos)
local currentDisaster = nil

-- Le score de chaque joueur pendant le chaos actuel (pour le classement Héros)
-- Format : { [Player.UserId] = score }
local chaosScores = {}

-- ============================================================================
-- FONCTIONS UTILITAIRES
-- ============================================================================

--[[
    Choisir une catastrophe aléatoire parmi celles définies dans GameConfig.

    COMMENT ÇA MARCHE (sélection pondérée) :
    Chaque catastrophe a un "Weight" (poids). Si toutes ont Weight = 1,
    elles ont la même probabilité. Si on voulait que les séismes soient
    2x plus fréquents, on mettrait Weight = 2 pour Earthquake.

    Algorithme :
    1. On additionne tous les poids → totalWeight
    2. On tire un nombre aléatoire entre 0 et totalWeight
    3. On parcourt les catastrophes en soustrayant leur poids
    4. Quand on passe en dessous de 0 → c'est celle-là qu'on choisit
]]
local function pickRandomDisaster(): string
    local disasters = GameConfig.Disasters
    local totalWeight = 0

    -- Étape 1 : calculer le poids total
    for _, config in pairs(disasters) do
        totalWeight = totalWeight + config.Weight
    end

    -- Étape 2 : tirer un nombre aléatoire
    local roll = math.random() * totalWeight

    -- Étape 3 : trouver la catastrophe correspondante
    for disasterId, config in pairs(disasters) do
        roll = roll - config.Weight
        if roll <= 0 then
            return disasterId
        end
    end

    -- Fallback (ne devrait jamais arriver)
    return "Earthquake"
end

--[[
    Choisir la durée de la phase Calme (aléatoire entre Min et Max).

    POURQUOI ALÉATOIRE ?
    Si les joueurs savaient que le chaos arrive EXACTEMENT à 12:00,
    ils pourraient optimiser parfaitement et il n'y aurait plus de surprise.
    L'aléatoire entre 10 et 14 minutes crée une tension constante :
    "Est-ce que ça va arriver maintenant ? Et maintenant ?"
]]
local function getRandomCalmDuration(): number
    local min = GameConfig.Phases.Calm.MinDuration
    local max = GameConfig.Phases.Calm.MaxDuration
    return math.random(min, max)
end

--[[
    Choisir la durée de la phase Chaos (aléatoire entre Min et Max).
    Peut être rallongée par le système de combo.
]]
local function getChaosDuration(): number
    local min = GameConfig.Phases.Chaos.MinDuration
    local max = GameConfig.Phases.Chaos.MaxDuration
    local baseDuration = math.random(min, max)

    -- Si on est dans un combo (3e chaos+), ajouter du temps
    local comboLevel = math.min(chaosCount, 4)
    local intensityScale = GameConfig.Combo.IntensityScale[comboLevel] or 1.0

    -- Le chaos dure plus longtemps avec l'escalade (max +60s au niveau 4)
    local bonusTime = (intensityScale - 1.0) * 60
    return math.floor(baseDuration + bonusTime)
end

--[[
    Notifier TOUS les clients du changement de phase.

    FireAllClients() envoie un RemoteEvent à TOUS les joueurs connectés.
    Contrairement à FireClient(player, ...) qui cible UN seul joueur.

    On envoie :
    - phaseName : le nom de la phase ("Calm", "Alert", "Chaos", "Result")
    - duration : la durée en secondes (pour que le client affiche un countdown)
    - extraData : données supplémentaires (type de catastrophe, etc.)
]]
local function notifyPhaseChange(phaseName: string, duration: number, extraData: any?)
    phaseChangedEvent:FireAllClients(phaseName, duration, extraData)
    print("[PhaseService] ══ Phase : " .. phaseName .. " (" .. duration .. "s) ══")
end

-- ============================================================================
-- LOGIQUE DES PHASES
-- ============================================================================

--[[
    PHASE 1 : CALME
    Les joueurs travaillent, socialisent, se préparent.
    Le timer est caché (les joueurs ne savent pas quand ça finit).
]]
function PhaseService._RunCalmPhase()
    currentPhase = "Calm"
    currentDisaster = nil
    chaosScores = {}

    local duration = getRandomCalmDuration()
    timeRemaining = duration

    notifyPhaseChange("Calm", duration)

    -- Countdown : on décompte seconde par seconde
    -- task.wait(1) pause ce thread pendant 1 seconde
    -- Le reste du jeu continue normalement pendant ce temps
    while timeRemaining > 0 do
        task.wait(1)
        timeRemaining = timeRemaining - 1
    end
end

--[[
    PHASE 2 : ALERTE
    Les sirènes retentissent, le ciel change de couleur.
    Les joueurs ont 2 minutes pour se préparer.

    C'est ici qu'on CHOISIT la catastrophe → le client reçoit le type
    pour changer la couleur du ciel (indice visuel pour les vétérans).
]]
function PhaseService._RunAlertPhase()
    currentPhase = "Alert"

    local duration = GameConfig.Phases.Alert.Duration
    timeRemaining = duration

    -- Choisir la catastrophe qui va frapper
    currentDisaster = pickRandomDisaster()

    -- Vérifier si c'est un combo (2 catastrophes simultanées)
    local isCombo = false
    local secondDisaster = nil

    if chaosCount >= GameConfig.Combo.ComboGuaranteedAt then
        -- 4e chaos+ : combo GARANTI
        isCombo = true
    elseif chaosCount >= GameConfig.Combo.ComboStartsAt then
        -- 3e chaos : combo POSSIBLE (50% de chance)
        isCombo = math.random() > 0.5
    end

    if isCombo then
        -- Choisir une 2e catastrophe différente de la première
        repeat
            secondDisaster = pickRandomDisaster()
        until secondDisaster ~= currentDisaster
        print("[PhaseService] COMBO ! " .. currentDisaster .. " + " .. secondDisaster)
    end

    -- Notifier les clients avec les infos de la catastrophe
    local alertData = {
        DisasterType = currentDisaster,
        DisasterName = GameConfig.Disasters[currentDisaster].DisplayName,
        SkyColor = GameConfig.Disasters[currentDisaster].SkyColor,
        IsCombo = isCombo,
        SecondDisaster = secondDisaster,
        SecondDisasterName = secondDisaster and GameConfig.Disasters[secondDisaster].DisplayName or nil,
        ComboLevel = chaosCount,
    }

    notifyPhaseChange("Alert", duration, alertData)

    -- Countdown de 2 minutes
    while timeRemaining > 0 do
        task.wait(1)
        timeRemaining = timeRemaining - 1
    end
end

--[[
    PHASE 3 : CHAOS
    La catastrophe frappe. Les multiplicateurs sont activés.
    Les joueurs gagnent des points de "Héros" pour chaque action réalisée.

    Le serveur :
    - Active les multiplicateurs de gains
    - Suit les scores des joueurs (pour le classement)
    - Gère la durée (+ bonus si combo)

    Le client (via le RemoteEvent) :
    - Déclenche les effets visuels (caméra shake, particules, destruction)
    - Affiche le multiplicateur à l'écran
]]
function PhaseService._RunChaosPhase()
    currentPhase = "Chaos"

    local duration = getChaosDuration()
    timeRemaining = duration

    -- Réinitialiser les scores de ce chaos
    chaosScores = {}
    for _, player in ipairs(Players:GetPlayers()) do
        chaosScores[player.UserId] = 0
    end

    -- Calculer le multiplicateur de base selon le niveau de combo
    local comboLevel = math.min(chaosCount, 4)
    local intensityScale = GameConfig.Combo.IntensityScale[comboLevel] or 1.0
    local baseMultiplier = 5  -- x5 de base
    if comboLevel >= GameConfig.Combo.ComboGuaranteedAt then
        baseMultiplier = GameConfig.Combo.ComboBaseMultiplier  -- x7 en combo garanti
    end

    -- Notifier les clients que le chaos commence
    local chaosData = {
        DisasterType = currentDisaster,
        DisasterName = GameConfig.Disasters[currentDisaster].DisplayName,
        BaseMultiplier = baseMultiplier,
        IntensityScale = intensityScale,
        ComboLevel = comboLevel,
    }

    notifyPhaseChange("Chaos", duration, chaosData)

    -- Envoyer aussi le DisasterStarted pour déclencher les effets spécifiques
    disasterStartedEvent:FireAllClients(currentDisaster, chaosData)

    -- Countdown du chaos
    while timeRemaining > 0 do
        task.wait(1)
        timeRemaining = timeRemaining - 1
    end

    -- Calculer le taux de survie
    -- (pour l'instant simplifié : tous les joueurs connectés sont "survivants")
    local totalPlayers = #Players:GetPlayers()
    if totalPlayers > 0 then
        lastChaosSurvivalRate = totalPlayers / totalPlayers  -- TODO: tracker les KO
    end

    -- Incrémenter le compteur de chaos
    if lastChaosSurvivalRate >= GameConfig.Combo.SurvivalThreshold then
        chaosCount = chaosCount + 1
        print("[PhaseService] Chaos survécu ! Combo streak : " .. chaosCount)
    else
        chaosCount = 1  -- Reset si trop de joueurs ont quitté
        print("[PhaseService] Combo streak reset (survie insuffisante)")
    end
end

--[[
    PHASE 4 : RÉSULTAT
    Affiche le classement "Héros du Chaos" et distribue les récompenses.
    La ville commence à se reconstruire.
]]
function PhaseService._RunResultPhase()
    currentPhase = "Result"

    local duration = GameConfig.Phases.Result.Duration
    timeRemaining = duration

    -- Construire le classement trié par score décroissant
    local ranking = {}
    for userId, score in pairs(chaosScores) do
        -- Retrouver le joueur par son UserId
        local player = Players:GetPlayerByUserId(userId)
        if player then
            table.insert(ranking, {
                Player = player,
                Name = player.Name,
                Score = score,
                UserId = userId,
            })
        end
    end

    -- Trier par score décroissant
    -- table.sort en Luau fonctionne comme Array.sort() en JS
    table.sort(ranking, function(a, b)
        return a.Score > b.Score
    end)

    -- Distribuer les récompenses
    -- On charge le DataService ici (et pas en haut du fichier) pour éviter
    -- une dépendance circulaire au moment du require()
    local DataService = require(ServerScriptService.Services.DataService)

    for rank, entry in ipairs(ranking) do
        local reward = nil

        if rank <= 5 then
            -- Top 5 : récompenses spéciales
            reward = GameConfig.Economy.HeroRewards[rank]
        else
            -- Tous les autres : récompense de participation
            reward = GameConfig.Economy.ParticipationReward
        end

        if reward and entry.Player.Parent then  -- .Parent vérifie qu'il est encore connecté
            DataService.AddCash(entry.Player, reward.Cash)
            DataService.AddChaosStars(entry.Player, reward.Stars)
            DataService.IncrementStat(entry.Player, "TotalChaoseSurvived", 1)

            if rank == 1 then
                DataService.IncrementStat(entry.Player, "TotalHeroTitles", 1)
            end
        end
    end

    -- Construire les données du classement à envoyer aux clients
    -- On n'envoie que le Top 5 (pas besoin d'envoyer 30 joueurs)
    local rankingData = {}
    for i = 1, math.min(5, #ranking) do
        table.insert(rankingData, {
            Rank = i,
            Name = ranking[i].Name,
            Score = ranking[i].Score,
        })
    end

    -- Log du classement dans la console serveur
    print("[PhaseService] ═══ Classement Héros du Chaos ═══")
    if #rankingData > 0 then
        for _, entry in ipairs(rankingData) do
            local medal = ""
            if entry.Rank == 1 then medal = "🥇 "
            elseif entry.Rank == 2 then medal = "🥈 "
            elseif entry.Rank == 3 then medal = "🥉 "
            end
            print("  " .. medal .. "#" .. entry.Rank .. " " .. entry.Name
                  .. " — Score: " .. entry.Score)
        end
    else
        print("  (Aucun score enregistré)")
    end
    print("[PhaseService] ═════════════════════════════════")

    -- Envoyer le classement à tous les clients
    local resultData = {
        Ranking = rankingData,
        ChaosCount = chaosCount,
        DisasterName = currentDisaster and GameConfig.Disasters[currentDisaster].DisplayName or "?",
    }

    notifyPhaseChange("Result", duration, resultData)
    heroRankingUpdatedEvent:FireAllClients(rankingData)

    -- Notifier le HeroService pour les titres et la statue
    local HeroService = require(ServerScriptService.Services.HeroService)
    local disasterDisplayName = currentDisaster and GameConfig.Disasters[currentDisaster].DisplayName or "?"
    HeroService.ProcessRanking(rankingData, disasterDisplayName)

    -- Countdown de 1 minute
    while timeRemaining > 0 do
        task.wait(1)
        timeRemaining = timeRemaining - 1
    end
end

-- ============================================================================
-- BOUCLE PRINCIPALE DU CYCLE
-- ============================================================================

--[[
    La boucle infinie qui enchaîne les 4 phases.

    C'est le "battement de cœur" du jeu. Tant que le serveur tourne,
    ce cycle se répète indéfiniment :
    Calme → Alerte → Chaos → Résultat → Calme → Alerte → ...

    task.spawn() lance cette boucle dans un thread séparé pour ne pas
    bloquer l'initialisation des autres services.
]]
function PhaseService._StartGameLoop()
    task.spawn(function()
        -- Petite pause au démarrage pour laisser les joueurs se connecter
        -- et pour que tous les services soient initialisés
        print("[PhaseService] Le premier cycle commence dans 10 secondes...")
        task.wait(10)

        -- Boucle infinie = le jeu tourne tant que le serveur est actif
        while true do
            PhaseService._RunCalmPhase()
            PhaseService._RunAlertPhase()
            PhaseService._RunChaosPhase()
            PhaseService._RunResultPhase()
            -- Et on reboucle → retour à la phase Calme
        end
    end)
end

-- ============================================================================
-- API PUBLIQUE
-- Ces fonctions sont utilisées par les autres services
-- ============================================================================

-- Obtenir la phase actuelle
function PhaseService.GetCurrentPhase(): string
    return currentPhase
end

-- Obtenir le temps restant dans la phase actuelle
function PhaseService.GetTimeRemaining(): number
    return timeRemaining
end

-- Obtenir la catastrophe en cours (nil si pas en phase Chaos)
function PhaseService.GetCurrentDisaster(): string?
    return currentDisaster
end

-- Obtenir le niveau de combo actuel
function PhaseService.GetComboLevel(): number
    return chaosCount
end

--[[
    Ajouter des points au score "Héros du Chaos" d'un joueur.

    Cette fonction est appelée par les autres services quand un joueur
    fait une action pendant le chaos :
    - JobService : le pompier éteint un feu → +100 points
    - JobService : le médecin réanime un joueur → +150 points
    - JobService : le livreur livre un colis → +80 points

    Les points ne sont comptés QUE pendant la phase Chaos.
]]
function PhaseService.AddChaosScore(player: Player, points: number)
    -- Sécurité : on ne peut scorer que pendant le chaos
    if currentPhase ~= "Chaos" then
        return
    end

    if not player or not player.Parent then
        return
    end

    -- Sanity check
    if type(points) ~= "number" or points <= 0 or points > 1000 then
        return
    end

    -- Initialiser le score si le joueur n'est pas encore dans la table
    if not chaosScores[player.UserId] then
        chaosScores[player.UserId] = 0
    end

    chaosScores[player.UserId] = chaosScores[player.UserId] + math.floor(points)
end

-- ============================================================================
-- INITIALISATION
-- ============================================================================
function PhaseService.Init()
    PhaseService._StartGameLoop()
    print("[PhaseService] Initialisé avec succès !")
end

return PhaseService
