--[[
    HeroService.lua
    Emplacement : ServerScriptService/Services/HeroService

    GÈRE LE SYSTÈME DE "HÉROS DU CHAOS" :
    - Affiche un titre au-dessus de la tête du #1 (visible par tous les joueurs)
    - Crée une statue du héros sur la place centrale (pendant 1 cycle)
    - Gère les titres permanents pour les vétérans

    CONCEPT CLÉ — BillboardGui au-dessus de la tête :
    Chaque personnage Roblox a une "Head" (Part).
    On peut attacher un BillboardGui à la Head pour afficher du texte
    flottant au-dessus du joueur, visible par tous.
    C'est la technique standard pour les noms, titres, grades, etc.

    CONCEPT CLÉ — Statue :
    On "clone" l'apparence du personnage du héros pour créer une statue.
    La statue est un Model figé (pas d'Humanoid actif) placé à une
    position fixe dans la ville.
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
-- SERVICES INTERNES
-- ============================================================================
local DataService = nil

-- ============================================================================
-- REMOTE EVENTS
-- ============================================================================
local remoteEvents = ReplicatedStorage.Events.RemoteEvents
local heroRankingUpdatedEvent = remoteEvents.HeroRankingUpdated

-- ============================================================================
-- ÉTAT
-- ============================================================================
local HeroService = {}

-- Le héros actuel (#1 du dernier chaos)
local currentHero = {
    UserId = nil,
    Name = "",
    DisasterName = "",
    Score = 0,
}

-- La statue actuelle dans le Workspace (pour la détruire au prochain cycle)
local currentStatue = nil

-- Les titres affichés au-dessus des têtes (pour les nettoyer)
-- Format : { [Player.UserId] = BillboardGui }
local activeTitles = {}

-- Position de la statue (place centrale de la ville)
-- Modifie ces coordonnées pour correspondre à ta map
local STATUE_POSITION = Vector3.new(0, 5, 0)

-- ============================================================================
-- TITRE AU-DESSUS DE LA TÊTE
-- ============================================================================

--[[
    Afficher un titre au-dessus de la tête d'un joueur.
    Visible par TOUS les joueurs du serveur.

    Le titre est attaché au personnage (Character), pas au Player.
    Si le joueur meurt et réapparaît, il faut rattacher le titre.
]]
function HeroService._SetPlayerTitle(player: Player, title: string, color: Color3)
    -- Supprimer l'ancien titre s'il existe
    HeroService._RemovePlayerTitle(player)

    local character = player.Character
    if not character then return end

    local head = character:FindFirstChild("Head")
    if not head then return end

    -- Créer le BillboardGui
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "HeroTitle"
    billboard.Size = UDim2.new(0, 250, 0, 40)
    billboard.StudsOffset = Vector3.new(0, 3, 0)  -- Au-dessus du nom par défaut
    billboard.AlwaysOnTop = true
    billboard.Parent = head

    -- Le texte du titre
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = title
    label.TextColor3 = color or Color3.fromRGB(255, 215, 0)
    label.TextStrokeTransparency = 0.5
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard

    activeTitles[player.UserId] = billboard

    print("[HeroService] Titre affiché pour " .. player.Name .. " : " .. title)
end

-- Supprimer le titre d'un joueur
function HeroService._RemovePlayerTitle(player: Player)
    local billboard = activeTitles[player.UserId]
    if billboard and billboard.Parent then
        billboard:Destroy()
    end
    activeTitles[player.UserId] = nil
end

-- Supprimer TOUS les titres temporaires
function HeroService._ClearAllTitles()
    for userId, billboard in pairs(activeTitles) do
        if billboard and billboard.Parent then
            billboard:Destroy()
        end
    end
    activeTitles = {}
end

-- ============================================================================
-- STATUE DU HÉROS
-- ============================================================================

--[[
    Créer une statue du héros #1 sur la place centrale.

    On ne peut pas "cloner" l'apparence d'un joueur facilement car
    les accessoires/vêtements sont chargés dynamiquement.

    À la place, on crée un piédestal simple avec le nom du héros.
    Plus tard, on pourra utiliser HumanoidDescription pour copier
    l'apparence exacte.
]]
function HeroService._CreateStatue(heroName: string, disasterName: string, score: number)
    -- Supprimer l'ancienne statue
    HeroService._RemoveStatue()

    -- Chercher le point de statue dans la map
    local statuePoint = workspace:FindFirstChild("StatuePoint")
    local position = statuePoint and statuePoint.Position or STATUE_POSITION

    -- Créer le modèle de la statue
    local statueModel = Instance.new("Model")
    statueModel.Name = "HeroStatue"

    -- Piédestal
    local pedestal = Instance.new("Part")
    pedestal.Name = "Pedestal"
    pedestal.Size = Vector3.new(6, 4, 6)
    pedestal.Position = position
    pedestal.Anchored = true
    pedestal.CanCollide = true
    pedestal.Material = Enum.Material.Marble
    pedestal.BrickColor = BrickColor.new("Institutional white")
    pedestal.Parent = statueModel

    -- Colonne sur le piédestal
    local column = Instance.new("Part")
    column.Name = "Column"
    column.Size = Vector3.new(3, 8, 3)
    column.Position = position + Vector3.new(0, 6, 0)
    column.Anchored = true
    column.CanCollide = true
    column.Material = Enum.Material.Marble
    column.BrickColor = BrickColor.new("Gold")
    column.Parent = statueModel

    -- Étoile dorée au sommet
    local star = Instance.new("Part")
    star.Name = "Star"
    star.Shape = Enum.PartType.Ball
    star.Size = Vector3.new(3, 3, 3)
    star.Position = position + Vector3.new(0, 11.5, 0)
    star.Anchored = true
    star.CanCollide = false
    star.Material = Enum.Material.Neon
    star.BrickColor = BrickColor.new("Bright yellow")
    star.Parent = statueModel

    -- Panneau avec le nom du héros
    local nameBillboard = Instance.new("BillboardGui")
    nameBillboard.Size = UDim2.new(0, 300, 0, 80)
    nameBillboard.StudsOffset = Vector3.new(0, 10, 0)
    nameBillboard.AlwaysOnTop = true
    nameBillboard.Parent = pedestal

    -- Nom du héros
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = heroName
    nameLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    nameLabel.TextStrokeTransparency = 0.3
    nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = nameBillboard

    -- Sous-titre (catastrophe + score)
    local subtitleLabel = Instance.new("TextLabel")
    subtitleLabel.Size = UDim2.new(1, 0, 0.4, 0)
    subtitleLabel.Position = UDim2.new(0, 0, 0.55, 0)
    subtitleLabel.BackgroundTransparency = 1
    subtitleLabel.Text = "Héros : " .. disasterName .. " | " .. score .. " pts"
    subtitleLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
    subtitleLabel.TextStrokeTransparency = 0.5
    subtitleLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    subtitleLabel.TextScaled = true
    subtitleLabel.Font = Enum.Font.GothamMedium
    subtitleLabel.Parent = nameBillboard

    -- Effet lumineux autour de la statue
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 215, 0)
    light.Brightness = 2
    light.Range = 20
    light.Parent = star

    statueModel.Parent = workspace
    currentStatue = statueModel

    print("[HeroService] Statue créée pour " .. heroName .. " !")
end

-- Supprimer la statue actuelle
function HeroService._RemoveStatue()
    if currentStatue and currentStatue.Parent then
        currentStatue:Destroy()
    end
    currentStatue = nil
end

-- ============================================================================
-- TRAITEMENT DU CLASSEMENT APRÈS UN CHAOS
-- ============================================================================

--[[
    Appelé par le PhaseService (via l'écoute du cycle).
    Reçoit le classement et applique les récompenses visuelles.
]]
function HeroService.ProcessRanking(ranking, disasterName: string)
    -- Nettoyer les titres du cycle précédent
    HeroService._ClearAllTitles()

    if not ranking or #ranking == 0 then
        return
    end

    -- Le #1 reçoit le titre et la statue
    local hero = ranking[1]
    local heroPlayer = nil

    -- Retrouver le Player à partir du nom
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name == hero.Name then
            heroPlayer = player
            break
        end
    end

    if heroPlayer then
        -- Titre au-dessus de la tête
        local title = "Héros : " .. disasterName
        HeroService._SetPlayerTitle(heroPlayer, title, Color3.fromRGB(255, 215, 0))

        -- Mettre à jour le héros actuel
        currentHero = {
            UserId = heroPlayer.UserId,
            Name = hero.Name,
            DisasterName = disasterName,
            Score = hero.Score,
        }

        -- Créer la statue
        HeroService._CreateStatue(hero.Name, disasterName, hero.Score)

        -- Si le joueur meurt et réapparaît, rattacher le titre
        heroPlayer.CharacterAdded:Connect(function()
            task.wait(1)  -- Attendre que le personnage soit complètement chargé
            if activeTitles[heroPlayer.UserId] then
                -- Le titre a été détruit avec l'ancien personnage, le recréer
                local titleText = "Héros : " .. disasterName
                HeroService._SetPlayerTitle(heroPlayer, titleText, Color3.fromRGB(255, 215, 0))
            end
        end)
    end

    -- Titres pour le Top 2-5 (plus discrets, en argent)
    for i = 2, math.min(5, #ranking) do
        local entry = ranking[i]
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Name == entry.Name then
                HeroService._SetPlayerTitle(
                    player,
                    "Top " .. i .. " Chaos",
                    Color3.fromRGB(180, 180, 200)
                )
                break
            end
        end
    end
end

-- ============================================================================
-- ÉCOUTE DU CYCLE DE PHASES
-- ============================================================================
function HeroService._StartPhaseWatcher()
    task.spawn(function()
        local lastPhase = ""

        while true do
            task.wait(1)

            -- On importe PhaseService ici pour éviter la dépendance circulaire
            local PhaseService = require(ServerScriptService.Services.PhaseService)
            local currentPhase = PhaseService.GetCurrentPhase()

            if currentPhase ~= lastPhase then
                if currentPhase == "Calm" then
                    -- Nouveau cycle calme → supprimer les titres et la statue
                    -- (le héros garde son titre pendant le résultat + la phase calme suivante)
                    -- On les supprime au PROCHAIN résultat via ProcessRanking
                end

                lastPhase = currentPhase
            end
        end
    end)
end

-- ============================================================================
-- API PUBLIQUE
-- ============================================================================

-- Obtenir le héros actuel
function HeroService.GetCurrentHero()
    return currentHero
end

-- ============================================================================
-- INITIALISATION
-- ============================================================================
function HeroService.Init()
    DataService = require(ServerScriptService.Services.DataService)

    -- Nettoyer quand un joueur quitte
    Players.PlayerRemoving:Connect(function(player)
        HeroService._RemovePlayerTitle(player)
    end)

    -- Démarrer la surveillance des phases
    HeroService._StartPhaseWatcher()

    print("[HeroService] Initialisé avec succès !")
end

return HeroService
