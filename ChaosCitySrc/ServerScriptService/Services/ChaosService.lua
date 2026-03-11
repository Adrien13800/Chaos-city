--[[
    ChaosService.lua
    Emplacement : ServerScriptService/Services/ChaosService

    REND LES CATASTROPHES RÉELLES DANS LE MONDE 3D.
    C'est la pièce qui connecte tout : PhaseService décide QUAND,
    ChaosService décide QUOI et OÙ.

    CE QU'IL FAIT :
    - Écoute les changements de phase du PhaseService
    - Phase Alerte → prépare la catastrophe (pré-calcul des zones)
    - Phase Chaos → spawn les zones de danger et les zones de mission
    - Phase Résultat → nettoie tout, lance la reconstruction
    - Gère le KO des joueurs qui touchent les zones de danger
    - Crée les zones où les joueurs peuvent compléter leurs missions chaos

    ARCHITECTURE 3D :
    Le ChaosService crée des Parts temporaires dans le Workspace :
    - "DangerZones" : zones rouges qui blessent/KO les joueurs au contact
    - "MissionZones" : zones vertes où les joueurs complètent leurs missions chaos
    - Ces Parts sont créées au début du chaos et détruites à la fin

    IMPORTANT — PERFORMANCES :
    Chaque Part ajoutée au Workspace coûte en performance (réseau + rendu).
    On limite le nombre de zones actives simultanées pour ne pas faire
    crasher les mobiles. Max ~20 danger zones + ~15 mission zones par chaos.
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
-- SERVICES INTERNES (chargés dans Init)
-- ============================================================================
local DataService = nil
local PhaseService = nil
local JobService = nil
local EconomyService = nil

-- ============================================================================
-- REMOTE EVENTS
-- ============================================================================
local remoteEvents = ReplicatedStorage.Events.RemoteEvents
local phaseChangedEvent = remoteEvents.PhaseChanged
local disasterStartedEvent = remoteEvents.DisasterStarted

-- ============================================================================
-- ÉTAT DU SERVICE
-- ============================================================================
local ChaosService = {}

-- Dossier temporaire dans Workspace pour les objets du chaos
local chaosFolder = nil

-- Liste des zones de danger actives (pour les nettoyer après)
local activeDangerZones = {}

-- Liste des zones de mission actives
local activeMissionZones = {}

-- Joueurs actuellement KO
-- Format : { [Player.UserId] = true }
local knockedOutPlayers = {}

-- Connexions d'événements actives (pour les déconnecter au nettoyage)
local activeConnections = {}

-- ============================================================================
-- CONSTANTES
-- ============================================================================
local MAX_DANGER_ZONES = 20
local MAX_MISSION_ZONES = 15
local KO_DURATION = 30          -- Secondes avant de réapparaître automatiquement
local DANGER_ZONE_DAMAGE = 25   -- Dégâts par contact avec une zone de danger
local DANGER_ZONE_COOLDOWN = 3  -- Secondes entre chaque hit de dégâts

-- Cooldown de dégâts par joueur (pour ne pas spam les dégâts)
local damageCooldowns = {}

-- ============================================================================
-- FONCTIONS UTILITAIRES
-- ============================================================================

--[[
    Trouver des positions valides pour placer les zones de chaos.

    On cherche des positions sur la Baseplate (ou le terrain) où il y a
    de la place pour poser une zone. On utilise un Raycast vers le bas
    pour trouver le sol.

    RAYCAST (Lancer de rayon) :
    C'est comme tirer un laser invisible depuis un point dans une direction.
    Si le laser touche quelque chose (le sol, un mur), on récupère le point
    d'impact. C'est la technique standard pour placer des objets au sol.
]]
local function getRandomPositionOnMap(): Vector3
    -- Zone de jeu : un carré autour du centre de la map
    -- Ajuste ces valeurs selon la taille de ta ville
    local mapSize = 200  -- 200 studs dans chaque direction depuis le centre

    local randomX = math.random(-mapSize, mapSize)
    local randomZ = math.random(-mapSize, mapSize)

    -- Raycast vers le bas pour trouver le sol
    local rayOrigin = Vector3.new(randomX, 100, randomZ)
    local rayDirection = Vector3.new(0, -200, 0)  -- 200 studs vers le bas

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    -- Exclure le dossier chaos pour ne pas toucher nos propres zones
    if chaosFolder then
        raycastParams.FilterDescendantsInstances = {chaosFolder}
    end

    local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    if result then
        -- On a touché le sol → position valide
        return result.Position + Vector3.new(0, 2, 0)  -- +2 pour être juste au-dessus du sol
    else
        -- Pas de sol trouvé → position par défaut
        return Vector3.new(randomX, 5, randomZ)
    end
end

--[[
    Créer une zone de danger (Part rouge semi-transparente).
    Les joueurs qui la touchent prennent des dégâts ou sont KO.
]]
local function createDangerZone(position: Vector3, size: Vector3?, disasterType: string)
    local zone = Instance.new("Part")
    zone.Name = "DangerZone_" .. disasterType
    zone.Size = size or Vector3.new(15, 8, 15)  -- Taille par défaut
    zone.Position = position
    zone.Anchored = true
    zone.CanCollide = false
    zone.Transparency = 0.6
    zone.Material = Enum.Material.Neon  -- Effet lumineux

    -- Couleur selon le type de catastrophe
    if disasterType == "Earthquake" then
        zone.BrickColor = BrickColor.new("Dark orange")
    elseif disasterType == "Flood" then
        zone.BrickColor = BrickColor.new("Bright blue")
        zone.Size = Vector3.new(25, 3, 25)  -- L'eau est plus étalée et basse
    elseif disasterType == "Meteors" then
        zone.BrickColor = BrickColor.new("Bright red")
        zone.Size = Vector3.new(10, 10, 10)  -- Cratères plus petits mais intenses
    elseif disasterType == "AlienInvasion" then
        zone.BrickColor = BrickColor.new("Lime green")
    elseif disasterType == "Tornado" then
        zone.BrickColor = BrickColor.new("Medium stone grey")
        zone.Size = Vector3.new(12, 20, 12)  -- Haut et étroit
    elseif disasterType == "Blackout" then
        zone.BrickColor = BrickColor.new("Really black")
        zone.Transparency = 0.8  -- Presque invisible (c'est le noir qui est le danger)
    end

    zone.Parent = chaosFolder
    table.insert(activeDangerZones, zone)

    -- Connecter la détection de collision
    local connection = zone.Touched:Connect(function(hit)
        local character = hit.Parent
        local player = Players:GetPlayerFromCharacter(character)

        if player and not knockedOutPlayers[player.UserId] then
            -- Vérifier le cooldown de dégâts
            local cooldownKey = player.UserId
            if damageCooldowns[cooldownKey] and
               tick() - damageCooldowns[cooldownKey] < DANGER_ZONE_COOLDOWN then
                return
            end
            damageCooldowns[cooldownKey] = tick()

            -- Appliquer les dégâts via l'Humanoid
            --[[
                L'Humanoid est le composant qui gère la "vie" d'un personnage Roblox.
                Chaque personnage a un Humanoid avec :
                - Health : points de vie actuels (défaut = 100)
                - MaxHealth : points de vie max (défaut = 100)
                - :TakeDamage(amount) : retire des PV

                Quand Health atteint 0, le personnage meurt et réapparaît.
                On gère ça nous-même avec le système KO à la place.
            ]]
            local humanoid = character:FindFirstChild("Humanoid")
            if humanoid then
                humanoid:TakeDamage(DANGER_ZONE_DAMAGE)

                if humanoid.Health <= 0 then
                    -- Le joueur est KO !
                    ChaosService._KnockOutPlayer(player)
                end
            end
        end
    end)

    table.insert(activeConnections, connection)

    return zone
end

--[[
    Créer une zone de mission (Part verte semi-transparente).
    Les joueurs qui la touchent complètent leur mission chaos active.
]]
local function createMissionZone(position: Vector3, missionType: string)
    local zone = Instance.new("Part")
    zone.Name = "MissionZone_" .. missionType
    zone.Size = Vector3.new(8, 6, 8)
    zone.Position = position
    zone.Anchored = true
    zone.CanCollide = false
    zone.Transparency = 0.5
    zone.Material = Enum.Material.Neon
    zone.BrickColor = BrickColor.new("Bright green")

    -- Ajouter un attribut pour identifier le type de mission
    zone:SetAttribute("MissionType", missionType)

    -- Ajouter un effet visuel : un BillboardGui avec du texte flottant
    --[[
        BillboardGui : un panneau UI qui flotte dans le monde 3D.
        Il fait toujours face à la caméra du joueur (comme un panneau publicitaire).
        Parfait pour afficher "MISSION" au-dessus d'une zone.
    ]]
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 5, 0)  -- 5 studs au-dessus de la Part
    billboard.AlwaysOnTop = true
    billboard.Parent = zone

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "MISSION"
    label.TextColor3 = Color3.fromRGB(0, 255, 100)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard

    zone.Parent = chaosFolder
    table.insert(activeMissionZones, zone)

    -- Connecter la détection : quand un joueur touche la zone, compléter sa mission
    local connection = zone.Touched:Connect(function(hit)
        local character = hit.Parent
        local player = Players:GetPlayerFromCharacter(character)

        if player and not knockedOutPlayers[player.UserId] then
            -- Déléguer la complétion au JobService
            JobService.CompleteMission(player)

            -- Détruire la zone après utilisation (une mission = une zone)
            zone:Destroy()

            -- Créer une nouvelle zone de mission ailleurs (pour le prochain joueur/mission)
            task.delay(3, function()
                if PhaseService.GetCurrentPhase() == "Chaos" and chaosFolder then
                    local newPos = getRandomPositionOnMap()
                    createMissionZone(newPos, missionType)
                end
            end)
        end
    end)

    table.insert(activeConnections, connection)

    return zone
end

-- ============================================================================
-- GESTION DU KO (Knock Out)
-- ============================================================================

--[[
    Mettre un joueur KO.
    - Il ne peut plus bouger pendant KO_DURATION secondes
    - Un médecin peut le réanimer plus tôt (futur)
    - Il perd son multiplicateur actif mais PAS son argent
]]
function ChaosService._KnockOutPlayer(player: Player)
    if knockedOutPlayers[player.UserId] then
        return  -- Déjà KO
    end

    knockedOutPlayers[player.UserId] = true

    print("[ChaosService] " .. player.Name .. " est KO !")

    -- Respawn après KO_DURATION secondes
    task.delay(KO_DURATION, function()
        if player.Parent then
            ChaosService._RevivePlayer(player)
        end
    end)
end

--[[
    Réanimer un joueur (fin du KO ou réanimation par un médecin).
]]
function ChaosService._RevivePlayer(player: Player)
    if not knockedOutPlayers[player.UserId] then
        return  -- Pas KO
    end

    knockedOutPlayers[player.UserId] = nil

    -- Restaurer la vie
    local character = player.Character
    if character then
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.Health = humanoid.MaxHealth
        end
    end

    print("[ChaosService] " .. player.Name .. " est réanimé !")

    -- Réassigner une mission si toujours en chaos
    if PhaseService.GetCurrentPhase() == "Chaos" then
        task.delay(2, function()
            if player.Parent then
                JobService.AssignMission(player)
            end
        end)
    end
end

-- ============================================================================
-- LOGIQUE DES CATASTROPHES
-- ============================================================================

--[[
    Spawner les zones de danger selon le type de catastrophe.
    Chaque catastrophe a un pattern de zones différent.
]]
function ChaosService._SpawnDisaster(disasterType: string)
    local config = GameConfig.Disasters[disasterType]
    if not config then return end

    local numDangerZones = math.floor(MAX_DANGER_ZONES * (config.BuildingDestructionPercent + 0.3))
    numDangerZones = math.clamp(numDangerZones, 5, MAX_DANGER_ZONES)

    print("[ChaosService] Spawn de " .. numDangerZones .. " zones de danger ("
          .. config.DisplayName .. ")")

    -- Spawner les zones de danger
    for i = 1, numDangerZones do
        local position = getRandomPositionOnMap()

        -- Varier la taille selon la catastrophe
        local size = nil  -- Utilise la taille par défaut de createDangerZone

        createDangerZone(position, size, disasterType)

        -- Petit délai entre chaque spawn pour un effet progressif
        -- (les zones apparaissent une par une, pas toutes d'un coup)
        task.wait(0.3)
    end

    -- Spawner les zones de mission
    local numMissionZones = math.clamp(MAX_MISSION_ZONES, 8, MAX_MISSION_ZONES)

    print("[ChaosService] Spawn de " .. numMissionZones .. " zones de mission")

    for i = 1, numMissionZones do
        local position = getRandomPositionOnMap()
        createMissionZone(position, disasterType)
        task.wait(0.2)
    end
end

--[[
    Spawner des zones de danger supplémentaires pendant le chaos.
    Simule le fait que la catastrophe s'intensifie au fil du temps.
]]
function ChaosService._SpawnProgressiveThreats(disasterType: string, duration: number)
    task.spawn(function()
        -- Toutes les 15 secondes, ajouter 2-3 nouvelles zones de danger
        local elapsed = 0
        while elapsed < duration and PhaseService.GetCurrentPhase() == "Chaos" do
            task.wait(15)
            elapsed = elapsed + 15

            if PhaseService.GetCurrentPhase() ~= "Chaos" then
                break
            end

            -- Ajouter 2-3 nouvelles zones
            local newZones = math.random(2, 3)
            for i = 1, newZones do
                if #activeDangerZones < MAX_DANGER_ZONES * 2 then
                    local pos = getRandomPositionOnMap()
                    createDangerZone(pos, nil, disasterType)
                end
            end

            print("[ChaosService] +" .. newZones .. " zones de danger (intensification)")
        end
    end)
end

-- ============================================================================
-- NETTOYAGE (après le chaos)
-- ============================================================================

--[[
    Supprimer toutes les zones de chaos et réinitialiser l'état.
    Appelé quand la phase Chaos se termine.
]]
function ChaosService._Cleanup()
    -- Déconnecter tous les événements
    for _, connection in ipairs(activeConnections) do
        connection:Disconnect()
    end
    activeConnections = {}

    -- Détruire toutes les zones de danger
    for _, zone in ipairs(activeDangerZones) do
        if zone and zone.Parent then
            zone:Destroy()
        end
    end
    activeDangerZones = {}

    -- Détruire toutes les zones de mission
    for _, zone in ipairs(activeMissionZones) do
        if zone and zone.Parent then
            zone:Destroy()
        end
    end
    activeMissionZones = {}

    -- Réanimer tous les joueurs encore KO
    for userId, _ in pairs(knockedOutPlayers) do
        local player = Players:GetPlayerByUserId(userId)
        if player then
            ChaosService._RevivePlayer(player)
        end
    end
    knockedOutPlayers = {}

    -- Réinitialiser les cooldowns de dégâts
    damageCooldowns = {}

    -- Appliquer les frais d'entretien des véhicules à tous les joueurs
    for _, player in ipairs(Players:GetPlayers()) do
        EconomyService.ApplyVehicleRepairCosts(player)
    end

    print("[ChaosService] Nettoyage terminé — la ville se reconstruit")
end

-- ============================================================================
-- ÉCOUTE DES CHANGEMENTS DE PHASE
-- ============================================================================

--[[
    Le ChaosService écoute le PhaseService pour savoir quand agir.

    On utilise une approche simple : vérifier périodiquement la phase actuelle
    et réagir aux transitions. C'est plus robuste qu'un système d'événements
    car même si on rate un événement, la boucle rattrapera.
]]
function ChaosService._StartPhaseWatcher()
    task.spawn(function()
        local lastPhase = ""

        while true do
            task.wait(1)

            local currentPhase = PhaseService.GetCurrentPhase()

            -- Détecter un changement de phase
            if currentPhase ~= lastPhase then

                if currentPhase == "Alert" then
                    -- Préparer le chaos (créer le dossier)
                    if not chaosFolder or not chaosFolder.Parent then
                        chaosFolder = Instance.new("Folder")
                        chaosFolder.Name = "ActiveChaos"
                        chaosFolder.Parent = workspace
                    end
                    print("[ChaosService] Alerte ! Préparation du chaos...")

                elseif currentPhase == "Chaos" then
                    -- LE CHAOS COMMENCE !
                    local disasterType = PhaseService.GetCurrentDisaster()
                    if disasterType then
                        print("[ChaosService] >>> "
                              .. GameConfig.Disasters[disasterType].DisplayName
                              .. " EN COURS ! <<<")

                        -- Spawner la catastrophe
                        ChaosService._SpawnDisaster(disasterType)

                        -- Lancer l'intensification progressive
                        local timeRemaining = PhaseService.GetTimeRemaining()
                        ChaosService._SpawnProgressiveThreats(disasterType, timeRemaining)
                    end

                elseif currentPhase == "Result" then
                    -- Le chaos est terminé → nettoyage
                    ChaosService._Cleanup()

                elseif currentPhase == "Calm" then
                    -- Double sécurité : s'assurer que tout est nettoyé
                    if chaosFolder and chaosFolder.Parent then
                        chaosFolder:Destroy()
                        chaosFolder = nil
                    end
                end

                lastPhase = currentPhase
            end
        end
    end)
end

-- ============================================================================
-- API PUBLIQUE
-- ============================================================================

-- Vérifier si un joueur est KO
function ChaosService.IsPlayerKnockedOut(player: Player): boolean
    return knockedOutPlayers[player.UserId] == true
end

-- Réanimer un joueur (utilisé par le médecin via JobService)
function ChaosService.RevivePlayer(player: Player)
    ChaosService._RevivePlayer(player)
end

-- Obtenir le nombre de zones de danger actives
function ChaosService.GetActiveDangerZoneCount(): number
    return #activeDangerZones
end

-- ============================================================================
-- INITIALISATION
-- ============================================================================
function ChaosService.Init()
    DataService = require(ServerScriptService.Services.DataService)
    PhaseService = require(ServerScriptService.Services.PhaseService)
    JobService = require(ServerScriptService.Services.JobService)
    EconomyService = require(ServerScriptService.Services.EconomyService)

    -- Nettoyer quand un joueur quitte
    Players.PlayerRemoving:Connect(function(player)
        knockedOutPlayers[player.UserId] = nil
        damageCooldowns[player.UserId] = nil
    end)

    -- Démarrer la surveillance des phases
    ChaosService._StartPhaseWatcher()

    print("[ChaosService] Initialisé avec succès !")
end

return ChaosService
