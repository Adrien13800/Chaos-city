--[[
    JobService.lua
    Emplacement : ServerScriptService/Services/JobService

    GÈRE TOUT CE QUI CONCERNE LES MÉTIERS :
    - Changement de métier (quand le joueur entre dans une zone)
    - Attribution de missions (calme et chaos)
    - Complétion de missions → cash, XP, score chaos
    - Multiplicateurs pendant le chaos

    ARCHITECTURE CLIENT/SERVEUR POUR LES MISSIONS :

    Le flow d'une mission :
    1. Le SERVEUR assigne une mission au joueur (choisie aléatoirement selon son métier/niveau)
    2. Le SERVEUR envoie "MissionAssigned" au CLIENT (pour afficher l'UI de la mission)
    3. Le JOUEUR se déplace vers la zone de mission et interagit (touche une Part/zone)
    4. Le CLIENT envoie "MissionAction" au SERVEUR ("j'ai touché la zone de mission")
    5. Le SERVEUR vérifie (anti-triche) et valide → cash + XP + score
    6. Le SERVEUR envoie "MissionCompleted" au CLIENT (pour afficher la récompense)
    7. Après un court délai, le SERVEUR assigne une nouvelle mission → retour à l'étape 1

    POURQUOI LE SERVEUR ASSIGNE LES MISSIONS (et pas le client) ?
    Si le client choisissait ses propres missions, un hacker pourrait
    toujours choisir la mission la plus rentable ou se la compléter instantanément.

    SYSTÈME DE ZONES DE MÉTIER :
    Dans Roblox Studio, tu placeras des Parts (blocs 3D) invisibles dans la ville.
    Quand un joueur TOUCHE cette Part, ça déclenche un changement de métier.
    Par exemple : une Part à la caserne → devenir Pompier.

    Comment ça marche techniquement :
    - On crée un dossier "JobZones" dans Workspace
    - Chaque Part dans ce dossier a un attribut "JobId" (ex: "Firefighter")
    - Le script détecte quand un joueur touche la Part → changement de métier
    - Tout est vérifié côté SERVEUR (le client envoie juste "je veux changer")
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

--[[
    Pour MissionsConfig, on vérifie d'abord si le dossier Config existe.
    Si tu n'as pas encore créé le dossier "Config" dans ReplicatedStorage
    dans Studio, le require échouera. On utilise FindFirstChild pour être safe.
]]
local configFolder = ReplicatedStorage:FindFirstChild("Config")
local MissionsConfig = nil
if configFolder and configFolder:FindFirstChild("MissionsConfig") then
    MissionsConfig = require(configFolder.MissionsConfig)
else
    warn("[JobService] MissionsConfig non trouvé ! Les missions ne fonctionneront pas.")
end

-- ============================================================================
-- SERVICES INTERNES (chargés à la demande pour éviter les dépendances circulaires)
-- ============================================================================
local DataService = nil             -- Chargé dans Init()
local PhaseService = nil            -- Chargé dans Init()
local MonetizationService = nil     -- Chargé à la demande (initialisé après JobService)

-- ============================================================================
-- REMOTE EVENTS
-- ============================================================================
local remoteEvents = ReplicatedStorage.Events.RemoteEvents
local missionAssignedEvent = remoteEvents.MissionAssigned
local missionCompletedEvent = remoteEvents.MissionCompleted
local requestJobChangeEvent = remoteEvents.RequestJobChange
local cashUpdatedEvent = remoteEvents.CashUpdated
local chaosStarsUpdatedEvent = remoteEvents.ChaosStarsUpdated
local jobLevelUpEvent = remoteEvents.JobLevelUp

-- ============================================================================
-- ÉTAT DU SERVICE
-- ============================================================================
local JobService = {}

-- Mission active de chaque joueur
-- Format : { [Player.UserId] = { MissionData = {...}, StartTime = tick(), Completed = false } }
local activeMissions = {}

-- Cooldown entre deux missions (pour éviter le spam)
-- Format : { [Player.UserId] = tick() }
local missionCooldowns = {}

-- Délai entre deux missions (en secondes)
local MISSION_COOLDOWN = 3

-- ============================================================================
-- FONCTIONS UTILITAIRES
-- ============================================================================

--[[
    Choisir une mission aléatoire adaptée au métier et au niveau du joueur.

    Logique :
    1. On regarde la phase actuelle (Calm ou Chaos)
    2. On récupère les missions du métier pour cette phase
    3. On filtre celles que le joueur peut faire (MinLevel)
    4. On en choisit une au hasard
]]
local function pickMission(jobId: string, playerLevel: number, isChaos: boolean)
    if not MissionsConfig then
        return nil
    end

    local jobMissions = MissionsConfig[jobId]
    if not jobMissions then
        return nil
    end

    -- Choisir la liste de missions selon la phase
    local missionList = isChaos and jobMissions.Chaos or jobMissions.Calm
    if not missionList or #missionList == 0 then
        return nil
    end

    -- Filtrer par niveau minimum
    local available = {}
    for _, mission in ipairs(missionList) do
        if playerLevel >= mission.MinLevel then
            table.insert(available, mission)
        end
    end

    if #available == 0 then
        return nil
    end

    -- Choisir aléatoirement parmi les missions disponibles
    return available[math.random(#available)]
end

--[[
    Calculer la récompense d'une mission en tenant compte des multiplicateurs.

    Pendant le chaos :
    - La récompense de base est multipliée par le multiplicateur du métier
    - Un joueur avec le VIP gamepass (futur) aura +10% sur la base uniquement

    ANTI-TRICHE : cette fonction tourne UNIQUEMENT côté serveur.
    Même si un hacker modifie les RemoteEvents, le calcul se fait ici.
]]
local function calculateReward(mission, jobId: string, isChaos: boolean, playerLevel: number)
    local baseReward = mission.BaseReward
    local xpReward = mission.XPReward
    local chaosScore = mission.ChaosScoreReward or 0

    -- Bonus de niveau : +5% par niveau au-dessus de 1
    -- Un Pompier Nv.5 gagne 20% de plus qu'un Pompier Nv.1
    local levelBonus = 1 + ((playerLevel - 1) * 0.05)
    baseReward = math.floor(baseReward * levelBonus)

    -- Multiplicateur chaos
    if isChaos then
        local jobConfig = GameConfig.Jobs[jobId]
        if jobConfig then
            baseReward = math.floor(baseReward * jobConfig.ChaosMultiplierBase)
        end
    end

    return {
        Cash = baseReward,
        XP = xpReward,
        ChaosScore = chaosScore,
    }
end

-- ============================================================================
-- GESTION DES MISSIONS
-- ============================================================================

--[[
    Assigner une nouvelle mission à un joueur.
    Appelé automatiquement après la complétion d'une mission ou quand il change de métier.
]]
function JobService.AssignMission(player: Player)
    if not player or not player.Parent then return end

    local data = DataService.GetData(player)
    if not data then return end

    local jobId = data.CurrentJob
    local jobLevel = DataService.GetJobLevel(player, jobId)

    -- Vérifier si on est en phase chaos
    local isChaos = PhaseService.GetCurrentPhase() == "Chaos"

    -- Choisir une mission
    local mission = pickMission(jobId, jobLevel, isChaos)
    if not mission then
        return
    end

    -- Stocker la mission active
    activeMissions[player.UserId] = {
        MissionData = mission,
        StartTime = tick(),  -- tick() = timestamp haute précision (pour vérifier la durée)
        Completed = false,
        IsChaos = isChaos,
        JobId = jobId,
    }

    -- Envoyer la mission au client pour l'affichage
    missionAssignedEvent:FireClient(player, {
        Id = mission.Id,
        Description = mission.Description,
        Duration = mission.Duration,
        JobId = jobId,
        IsChaos = isChaos,
    })

    print("[JobService] Mission assignée à " .. player.Name .. " : " .. mission.Description)
end

--[[
    Compléter la mission active d'un joueur.
    Appelé quand le joueur interagit avec la zone de mission.

    VÉRIFICATIONS ANTI-TRICHE :
    1. Le joueur a-t-il une mission active ?
    2. La mission n'est-elle pas déjà complétée ?
    3. Le temps minimum est-il respecté ? (un hacker ne peut pas compléter en 0.1s)
    4. Le joueur est-il en cooldown ?
]]
function JobService.CompleteMission(player: Player)
    if not player or not player.Parent then return end

    local active = activeMissions[player.UserId]
    if not active or active.Completed then
        return  -- Pas de mission active ou déjà complétée
    end

    -- Anti-triche : vérifier qu'un minimum de temps s'est écoulé
    -- On exige au moins 3 secondes (un humain ne peut pas finir plus vite)
    local elapsed = tick() - active.StartTime
    if elapsed < 3 then
        warn("[JobService] Complétion suspecte de " .. player.Name
             .. " (" .. string.format("%.1f", elapsed) .. "s) — ignoré")
        return
    end

    -- Vérifier le cooldown
    local lastCompletion = missionCooldowns[player.UserId] or 0
    if tick() - lastCompletion < MISSION_COOLDOWN then
        return  -- En cooldown, ignorer
    end

    -- Marquer comme complétée
    active.Completed = true
    missionCooldowns[player.UserId] = tick()

    -- Calculer les récompenses
    local data = DataService.GetData(player)
    if not data then return end

    local playerLevel = DataService.GetJobLevel(player, active.JobId)
    local rewards = calculateReward(active.MissionData, active.JobId, active.IsChaos, playerLevel)

    -- Appliquer les multiplicateurs Gamepasses/Boosts
    MonetizationService = MonetizationService or require(ServerScriptService.Services.MonetizationService)
    local cashMultiplier = MonetizationService.GetCashMultiplier(player)  -- x2 si VIP
    local xpMultiplier = MonetizationService.GetXPMultiplier(player)     -- x2 si boost actif
    rewards.Cash = math.floor(rewards.Cash * cashMultiplier)
    rewards.XP = math.floor(rewards.XP * xpMultiplier)

    -- Distribuer les récompenses via DataService (vérifié et sécurisé)
    DataService.AddCash(player, rewards.Cash)
    DataService.AddJobXP(player, active.JobId, rewards.XP)
    DataService.IncrementStat(player, "TotalMissionsCompleted", 1)

    -- Ajouter le score chaos si en phase chaos
    if active.IsChaos and rewards.ChaosScore > 0 then
        PhaseService.AddChaosScore(player, rewards.ChaosScore)
    end

    -- Notifier le client
    local updatedData = DataService.GetData(player)
    cashUpdatedEvent:FireClient(player, updatedData.Cash)

    missionCompletedEvent:FireClient(player, {
        MissionId = active.MissionData.Id,
        CashEarned = rewards.Cash,
        XPEarned = rewards.XP,
        ChaosScoreEarned = rewards.ChaosScore,
        IsChaos = active.IsChaos,
        NewCash = updatedData.Cash,
    })

    print("[JobService] " .. player.Name .. " a complété : "
          .. active.MissionData.Description
          .. " | +$" .. rewards.Cash .. " | +" .. rewards.XP .. " XP")

    -- Nettoyer la mission active
    activeMissions[player.UserId] = nil

    -- Assigner une nouvelle mission après le cooldown
    task.delay(MISSION_COOLDOWN, function()
        if player.Parent then  -- Vérifier qu'il est encore connecté
            JobService.AssignMission(player)
        end
    end)
end

-- ============================================================================
-- CHANGEMENT DE MÉTIER
-- ============================================================================

--[[
    Changer le métier d'un joueur.
    Appelé quand le joueur entre dans une zone de métier (caserne, hôpital, etc.)

    Le changement :
    - Annule la mission en cours (s'il en avait une)
    - Change le métier dans le DataStore
    - Assigne immédiatement une nouvelle mission du nouveau métier
]]
function JobService.ChangeJob(player: Player, newJobId: string)
    if not player or not player.Parent then return end

    -- Vérifier que le métier existe
    if not GameConfig.Jobs[newJobId] then
        warn("[JobService] Métier inconnu : " .. tostring(newJobId))
        return
    end

    local data = DataService.GetData(player)
    if not data then return end

    -- Si c'est déjà son métier, ne rien faire
    if data.CurrentJob == newJobId then
        return
    end

    -- Changer le métier dans les données
    DataService.SetCurrentJob(player, newJobId)

    -- Notifier le client pour mettre à jour le HUD
    remoteEvents.JobChanged:FireClient(player, newJobId)

    -- Annuler la mission en cours
    activeMissions[player.UserId] = nil

    -- Assigner une mission du nouveau métier
    task.delay(1, function()
        if player.Parent then
            JobService.AssignMission(player)
        end
    end)

    print("[JobService] " .. player.Name .. " est passé au métier : "
          .. GameConfig.Jobs[newJobId].DisplayName)
end

-- ============================================================================
-- ZONES DE CHANGEMENT DE MÉTIER (TouchParts dans Workspace)
-- ============================================================================

--[[
    COMMENT ÇA MARCHE DANS ROBLOX STUDIO :

    1. Tu crées un dossier "JobZones" dans Workspace
    2. Dedans, tu places des Parts (blocs 3D) aux endroits de la ville
       où les joueurs peuvent changer de métier
    3. Chaque Part doit avoir un ATTRIBUT personnalisé nommé "JobId"
       avec la valeur du métier (ex: "Firefighter", "Medic", etc.)

    COMMENT CRÉER UN ATTRIBUT DANS STUDIO :
    - Sélectionne la Part dans l'Explorer
    - Dans le panneau Properties, scroll tout en bas
    - Clique sur "Add Attribute"
    - Name : "JobId"
    - Type : "String"
    - Value : "Firefighter" (ou le métier voulu)

    COMMENT RENDRE LA PART INVISIBLE (zone de détection) :
    - Properties → Transparency = 1 (invisible)
    - Properties → CanCollide = false (les joueurs passent à travers)
    - Properties → Anchored = true (elle ne bouge pas)

    Le script ci-dessous surveille automatiquement toutes les Parts
    dans le dossier "JobZones" et connecte les événements de collision.
]]
local function setupJobZones()
    -- Chercher le dossier JobZones dans Workspace
    local jobZonesFolder = workspace:FindFirstChild("JobZones")

    if not jobZonesFolder then
        -- Créer le dossier s'il n'existe pas (pour le premier test)
        jobZonesFolder = Instance.new("Folder")
        jobZonesFolder.Name = "JobZones"
        jobZonesFolder.Parent = workspace
        print("[JobService] Dossier 'JobZones' créé dans Workspace")
        print("[JobService] Place des Parts dedans avec un attribut 'JobId' pour les zones de métier")
        return
    end

    -- Connecter chaque Part du dossier
    for _, part in ipairs(jobZonesFolder:GetChildren()) do
        if part:IsA("BasePart") then
            local jobId = part:GetAttribute("JobId")

            if jobId and GameConfig.Jobs[jobId] then
                -- Quand un personnage TOUCHE cette Part
                part.Touched:Connect(function(hit)
                    --[[
                        "hit" est la Part du personnage qui a touché la zone.
                        Un personnage Roblox est composé de plusieurs Parts
                        (Head, Torso, LeftArm, etc.) regroupées dans un Model.
                        Le Model a le même nom que le joueur.

                        hit.Parent = le Model du personnage
                        Players:GetPlayerFromCharacter(model) = retrouver le Player
                    ]]
                    local character = hit.Parent
                    local player = Players:GetPlayerFromCharacter(character)

                    if player then
                        -- Anti-spam : vérifier un cooldown de changement
                        local cooldownKey = "jobchange_" .. player.UserId
                        if not missionCooldowns[cooldownKey] or
                           tick() - missionCooldowns[cooldownKey] > 5 then
                            missionCooldowns[cooldownKey] = tick()
                            JobService.ChangeJob(player, jobId)
                        end
                    end
                end)

                print("[JobService] Zone de métier connectée : "
                      .. part.Name .. " → " .. GameConfig.Jobs[jobId].DisplayName)
            else
                warn("[JobService] La Part '" .. part.Name
                     .. "' n'a pas d'attribut 'JobId' valide")
            end
        end
    end
end

-- ============================================================================
-- ÉCOUTER LES CHANGEMENTS DE PHASE
-- Quand la phase change, on réassigne les missions appropriées
-- ============================================================================
local function onPhaseChanged()
    --[[
        Écouter le RemoteEvent PhaseChanged côté serveur.

        ATTENDS — un RemoteEvent n'est pas juste Client ↔ Serveur ?
        En fait, on pourrait aussi utiliser un BindableEvent (serveur ↔ serveur),
        mais pour simplifier, le PhaseService envoie déjà PhaseChanged à tous
        les clients. Ici, on utilise une approche différente : on vérifie
        périodiquement la phase actuelle après chaque mission.

        ALTERNATIVE PROPRE (pour plus tard) : créer un système de signaux
        interne (pattern Observer) pour que les services communiquent entre eux
        sans passer par les RemoteEvents.
    ]]
end

-- ============================================================================
-- ÉCOUTER LES ACTIONS DES JOUEURS (RemoteEvents Client → Serveur)
-- ============================================================================
local function setupRemoteListeners()
    -- Quand un joueur demande à changer de métier via l'UI (futur bouton)
    requestJobChangeEvent.OnServerEvent:Connect(function(player, requestedJobId)
        --[[
            OnServerEvent : l'inverse de OnClientEvent.
            Quand le client fait RequestJobChange:FireServer("Firefighter"),
            cette fonction s'exécute sur le serveur.

            SÉCURITÉ : le premier paramètre est TOUJOURS le player.
            Roblox l'injecte automatiquement → un hacker ne peut PAS
            se faire passer pour un autre joueur.
        ]]

        -- Valider le type (anti-triche : le client pourrait envoyer n'importe quoi)
        if type(requestedJobId) ~= "string" then
            return
        end

        -- Vérifier que le métier existe
        if not GameConfig.Jobs[requestedJobId] then
            return
        end

        JobService.ChangeJob(player, requestedJobId)
    end)

    -- Quand un joueur signale qu'il a complété une action de mission
    remoteEvents.MissionAction.OnServerEvent:Connect(function(player, actionType)
        --[[
            Pour l'instant, on a un seul type d'action : "complete".
            Plus tard, on pourra ajouter d'autres types :
            - "interact" : le joueur a touché la zone de mission
            - "cancel" : le joueur annule sa mission
            - "progress" : mise à jour de progression (ex: 3/5 PNJs soignés)
        ]]
        if type(actionType) ~= "string" then
            return
        end

        if actionType == "complete" then
            JobService.CompleteMission(player)
        end
    end)
end

-- ============================================================================
-- INITIALISATION
-- ============================================================================
function JobService.Init()
    -- Charger les services internes (maintenant que Init.server.lua les a initialisés)
    DataService = require(ServerScriptService.Services.DataService)
    PhaseService = require(ServerScriptService.Services.PhaseService)

    -- Configurer les zones de métier dans le Workspace
    setupJobZones()

    -- Écouter les RemoteEvents des clients
    setupRemoteListeners()

    -- Assigner une première mission à chaque joueur déjà connecté
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            -- Attendre que les données soient chargées
            local attempts = 0
            while not DataService.GetData(player) and attempts < 10 do
                task.wait(1)
                attempts = attempts + 1
            end
            if DataService.GetData(player) then
                JobService.AssignMission(player)
            end
        end)
    end

    -- Assigner une mission aux futurs joueurs quand ils rejoignent
    Players.PlayerAdded:Connect(function(player)
        -- Attendre que les données soient chargées par DataService
        task.spawn(function()
            local attempts = 0
            while not DataService.GetData(player) and attempts < 10 do
                task.wait(1)
                attempts = attempts + 1
            end
            if player.Parent and DataService.GetData(player) then
                JobService.AssignMission(player)
            end
        end)
    end)

    -- Nettoyer quand un joueur quitte
    Players.PlayerRemoving:Connect(function(player)
        activeMissions[player.UserId] = nil
        missionCooldowns[player.UserId] = nil
    end)

    print("[JobService] Initialisé avec succès !")
end

return JobService
