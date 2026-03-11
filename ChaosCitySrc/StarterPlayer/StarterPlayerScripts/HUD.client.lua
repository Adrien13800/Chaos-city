--[[
    HUD.client.lua
    Emplacement : StarterPlayer/StarterPlayerScripts/HUD

    CRÉE TOUTE L'INTERFACE JOUEUR (UI) PAR CODE.

    Pourquoi créer l'UI par code plutôt que dans Studio ?
    - Plus facile à versionner et modifier
    - Pas besoin de naviguer dans l'arborescence Studio
    - On peut réutiliser des fonctions pour créer des éléments similaires

    STRUCTURE DE L'UI ROBLOX :
    ScreenGui           ← Le "canvas" plein écran (comme <body> en HTML)
    └── Frame           ← Un rectangle (comme <div>)
        ├── TextLabel   ← Du texte (comme <p> ou <span>)
        ├── TextButton  ← Un bouton cliquable
        └── ImageLabel  ← Une image

    SYSTÈME DE POSITIONNEMENT — UDim2 :
    UDim2.new(scaleX, offsetX, scaleY, offsetY)
    - scale = pourcentage (0 à 1) de la taille du parent
    - offset = pixels fixes en plus

    Exemples :
    UDim2.new(0.5, 0, 0.5, 0)  → centré (50% x, 50% y)
    UDim2.new(1, 0, 0, 50)     → 100% de largeur, 50px de haut
    UDim2.new(0, 200, 0, 40)   → 200px de large, 40px de haut

    AnchorPoint :
    Définit le point d'ancrage de l'élément (comme transform-origin en CSS).
    Vector2.new(0.5, 0) → le haut-centre est le point de référence
]]

-- ============================================================================
-- SERVICES
-- ============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- ============================================================================
-- MODULES
-- ============================================================================
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

-- ============================================================================
-- REMOTE EVENTS
-- ============================================================================
local events = ReplicatedStorage:WaitForChild("Events")
local remoteEvents = events:WaitForChild("RemoteEvents")
local remoteFunctions = events:WaitForChild("RemoteFunctions")

local cashUpdatedEvent = remoteEvents:WaitForChild("CashUpdated")
local chaosStarsUpdatedEvent = remoteEvents:WaitForChild("ChaosStarsUpdated")
local phaseChangedEvent = remoteEvents:WaitForChild("PhaseChanged")
local disasterStartedEvent = remoteEvents:WaitForChild("DisasterStarted")
local heroRankingUpdatedEvent = remoteEvents:WaitForChild("HeroRankingUpdated")
local missionAssignedEvent = remoteEvents:WaitForChild("MissionAssigned")
local missionCompletedEvent = remoteEvents:WaitForChild("MissionCompleted")
local jobLevelUpEvent = remoteEvents:WaitForChild("JobLevelUp")
local jobChangedEvent = remoteEvents:WaitForChild("JobChanged")
local getPlayerDataFunc = remoteFunctions:WaitForChild("GetPlayerData")

-- ============================================================================
-- COULEURS ET STYLE
-- ============================================================================
local COLORS = {
    Background = Color3.fromRGB(20, 20, 30),
    BackgroundLight = Color3.fromRGB(35, 35, 50),
    Text = Color3.fromRGB(255, 255, 255),
    TextDim = Color3.fromRGB(180, 180, 200),
    Cash = Color3.fromRGB(255, 215, 0),        -- Or
    Stars = Color3.fromRGB(200, 130, 255),      -- Violet clair
    Calm = Color3.fromRGB(80, 200, 120),        -- Vert
    Alert = Color3.fromRGB(255, 180, 0),        -- Orange
    Chaos = Color3.fromRGB(255, 50, 50),        -- Rouge
    Result = Color3.fromRGB(100, 150, 255),     -- Bleu
    Mission = Color3.fromRGB(0, 200, 150),      -- Turquoise
    Success = Color3.fromRGB(50, 255, 100),     -- Vert vif
}

-- ============================================================================
-- FONCTIONS UTILITAIRES UI
-- ============================================================================

-- Crée un coin arrondi sur un élément
local function addCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 8)
    corner.Parent = parent
    return corner
end

-- Crée un contour sur un élément
local function addStroke(parent, color, thickness)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or Color3.fromRGB(60, 60, 80)
    stroke.Thickness = thickness or 1
    stroke.Parent = parent
    return stroke
end

-- Crée du padding intérieur
local function addPadding(parent, pixels)
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, pixels)
    padding.PaddingBottom = UDim.new(0, pixels)
    padding.PaddingLeft = UDim.new(0, pixels)
    padding.PaddingRight = UDim.new(0, pixels)
    padding.Parent = parent
    return padding
end

-- Animation fluide d'un changement de propriété
local function tweenProperty(object, properties, duration)
    local tween = TweenService:Create(
        object,
        TweenInfo.new(duration or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        properties
    )
    tween:Play()
    return tween
end

-- Formater un nombre avec séparateur de milliers
local function formatNumber(n)
    local formatted = tostring(math.floor(n))
    -- Ajouter des virgules : 1000000 → 1,000,000
    local result = ""
    local count = 0
    for i = #formatted, 1, -1 do
        count = count + 1
        result = string.sub(formatted, i, i) .. result
        if count % 3 == 0 and i > 1 then
            result = "," .. result
        end
    end
    return result
end

-- Formater un temps en MM:SS
local function formatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%d:%02d", mins, secs)
end

-- ============================================================================
-- CRÉATION DU SCREENGUI
-- ============================================================================

--[[
    ScreenGui est le conteneur principal de toute l'UI.
    ResetOnSpawn = false → l'UI persiste quand le joueur meurt/réapparaît.
    Si c'était true, l'UI serait détruite et recréée à chaque respawn.
]]
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ChaosCityHUD"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ============================================================================
-- BARRE DU HAUT — Cash + Étoiles + Métier
-- ============================================================================
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 50)
topBar.Position = UDim2.new(0, 0, 0, 10)
topBar.BackgroundTransparency = 1  -- Pas de fond pour la barre elle-même
topBar.Parent = screenGui

-- ── Cash ──
local cashFrame = Instance.new("Frame")
cashFrame.Name = "CashFrame"
cashFrame.Size = UDim2.new(0, 180, 0, 40)
cashFrame.Position = UDim2.new(0, 15, 0, 0)
cashFrame.BackgroundColor3 = COLORS.Background
cashFrame.BackgroundTransparency = 0.3
cashFrame.Parent = topBar
addCorner(cashFrame, 10)
addStroke(cashFrame, COLORS.Cash, 1)

local cashLabel = Instance.new("TextLabel")
cashLabel.Name = "CashLabel"
cashLabel.Size = UDim2.new(1, 0, 1, 0)
cashLabel.BackgroundTransparency = 1
cashLabel.Text = "$ 0"
cashLabel.TextColor3 = COLORS.Cash
cashLabel.Font = Enum.Font.GothamBold
cashLabel.TextSize = 20
cashLabel.Parent = cashFrame

-- ── Étoiles de Chaos ──
local starsFrame = Instance.new("Frame")
starsFrame.Name = "StarsFrame"
starsFrame.Size = UDim2.new(0, 140, 0, 40)
starsFrame.Position = UDim2.new(0, 210, 0, 0)
starsFrame.BackgroundColor3 = COLORS.Background
starsFrame.BackgroundTransparency = 0.3
starsFrame.Parent = topBar
addCorner(starsFrame, 10)
addStroke(starsFrame, COLORS.Stars, 1)

local starsLabel = Instance.new("TextLabel")
starsLabel.Name = "StarsLabel"
starsLabel.Size = UDim2.new(1, 0, 1, 0)
starsLabel.BackgroundTransparency = 1
starsLabel.Text = "0"
starsLabel.TextColor3 = COLORS.Stars
starsLabel.Font = Enum.Font.GothamBold
starsLabel.TextSize = 20
starsLabel.Parent = starsFrame

-- ── Métier actuel ──
local jobFrame = Instance.new("Frame")
jobFrame.Name = "JobFrame"
jobFrame.Size = UDim2.new(0, 180, 0, 40)
jobFrame.Position = UDim2.new(0, 365, 0, 0)
jobFrame.BackgroundColor3 = COLORS.Background
jobFrame.BackgroundTransparency = 0.3
jobFrame.Parent = topBar
addCorner(jobFrame, 10)
addStroke(jobFrame, Color3.fromRGB(100, 100, 120), 1)

local jobLabel = Instance.new("TextLabel")
jobLabel.Name = "JobLabel"
jobLabel.Size = UDim2.new(1, 0, 1, 0)
jobLabel.BackgroundTransparency = 1
jobLabel.Text = "Civil"
jobLabel.TextColor3 = COLORS.Text
jobLabel.Font = Enum.Font.GothamBold
jobLabel.TextSize = 18
jobLabel.Parent = jobFrame

-- ============================================================================
-- INDICATEUR DE PHASE — Centre haut
-- ============================================================================
local phaseFrame = Instance.new("Frame")
phaseFrame.Name = "PhaseFrame"
phaseFrame.Size = UDim2.new(0, 300, 0, 60)
phaseFrame.Position = UDim2.new(0.5, 0, 0, 10)
phaseFrame.AnchorPoint = Vector2.new(0.5, 0)  -- Centré horizontalement
phaseFrame.BackgroundColor3 = COLORS.Background
phaseFrame.BackgroundTransparency = 0.2
phaseFrame.Parent = screenGui
addCorner(phaseFrame, 12)
addStroke(phaseFrame, COLORS.Calm, 2)

-- Nom de la phase
local phaseNameLabel = Instance.new("TextLabel")
phaseNameLabel.Name = "PhaseName"
phaseNameLabel.Size = UDim2.new(1, 0, 0.5, 0)
phaseNameLabel.Position = UDim2.new(0, 0, 0, 2)
phaseNameLabel.BackgroundTransparency = 1
phaseNameLabel.Text = "CALME"
phaseNameLabel.TextColor3 = COLORS.Calm
phaseNameLabel.Font = Enum.Font.GothamBold
phaseNameLabel.TextSize = 22
phaseNameLabel.Parent = phaseFrame

-- Timer de la phase
local phaseTimerLabel = Instance.new("TextLabel")
phaseTimerLabel.Name = "PhaseTimer"
phaseTimerLabel.Size = UDim2.new(1, 0, 0.5, 0)
phaseTimerLabel.Position = UDim2.new(0, 0, 0.5, -2)
phaseTimerLabel.BackgroundTransparency = 1
phaseTimerLabel.Text = "--:--"
phaseTimerLabel.TextColor3 = COLORS.TextDim
phaseTimerLabel.Font = Enum.Font.GothamMedium
phaseTimerLabel.TextSize = 18
phaseTimerLabel.Parent = phaseFrame

-- ============================================================================
-- PANNEAU DE MISSION — Bas de l'écran
-- ============================================================================
local missionFrame = Instance.new("Frame")
missionFrame.Name = "MissionFrame"
missionFrame.Size = UDim2.new(0, 400, 0, 70)
missionFrame.Position = UDim2.new(0.5, 0, 1, -90)
missionFrame.AnchorPoint = Vector2.new(0.5, 0)
missionFrame.BackgroundColor3 = COLORS.Background
missionFrame.BackgroundTransparency = 0.2
missionFrame.Visible = false  -- Caché par défaut (visible quand une mission est active)
missionFrame.Parent = screenGui
addCorner(missionFrame, 12)
addStroke(missionFrame, COLORS.Mission, 2)
addPadding(missionFrame, 10)

-- Titre "MISSION"
local missionTitle = Instance.new("TextLabel")
missionTitle.Name = "MissionTitle"
missionTitle.Size = UDim2.new(1, 0, 0, 18)
missionTitle.Position = UDim2.new(0, 0, 0, 0)
missionTitle.BackgroundTransparency = 1
missionTitle.Text = "MISSION"
missionTitle.TextColor3 = COLORS.Mission
missionTitle.Font = Enum.Font.GothamBold
missionTitle.TextSize = 14
missionTitle.TextXAlignment = Enum.TextXAlignment.Left
missionTitle.Parent = missionFrame

-- Description de la mission
local missionDescription = Instance.new("TextLabel")
missionDescription.Name = "MissionDescription"
missionDescription.Size = UDim2.new(1, 0, 0, 22)
missionDescription.Position = UDim2.new(0, 0, 0, 22)
missionDescription.BackgroundTransparency = 1
missionDescription.Text = ""
missionDescription.TextColor3 = COLORS.Text
missionDescription.Font = Enum.Font.GothamMedium
missionDescription.TextSize = 16
missionDescription.TextXAlignment = Enum.TextXAlignment.Left
missionDescription.TextTruncate = Enum.TextTruncate.AtEnd
missionDescription.Parent = missionFrame

-- ============================================================================
-- POPUP DE RÉCOMPENSE — Centre de l'écran (apparaît brièvement)
-- ============================================================================
local rewardPopup = Instance.new("Frame")
rewardPopup.Name = "RewardPopup"
rewardPopup.Size = UDim2.new(0, 350, 0, 80)
rewardPopup.Position = UDim2.new(0.5, 0, 0.3, 0)
rewardPopup.AnchorPoint = Vector2.new(0.5, 0.5)
rewardPopup.BackgroundColor3 = COLORS.Background
rewardPopup.BackgroundTransparency = 0.15
rewardPopup.Visible = false
rewardPopup.Parent = screenGui
addCorner(rewardPopup, 12)
addStroke(rewardPopup, COLORS.Success, 2)

local rewardText = Instance.new("TextLabel")
rewardText.Name = "RewardText"
rewardText.Size = UDim2.new(1, 0, 0.5, 0)
rewardText.Position = UDim2.new(0, 0, 0, 5)
rewardText.BackgroundTransparency = 1
rewardText.Text = "MISSION TERMINÉE !"
rewardText.TextColor3 = COLORS.Success
rewardText.Font = Enum.Font.GothamBold
rewardText.TextSize = 20
rewardText.Parent = rewardPopup

local rewardDetails = Instance.new("TextLabel")
rewardDetails.Name = "RewardDetails"
rewardDetails.Size = UDim2.new(1, 0, 0.5, 0)
rewardDetails.Position = UDim2.new(0, 0, 0.5, -5)
rewardDetails.BackgroundTransparency = 1
rewardDetails.Text = "+$0 | +0 XP"
rewardDetails.TextColor3 = COLORS.Cash
rewardDetails.Font = Enum.Font.GothamMedium
rewardDetails.TextSize = 18
rewardDetails.Parent = rewardPopup

-- ============================================================================
-- ALERTE CHAOS — Grande bannière en haut (pendant l'alerte/chaos)
-- ============================================================================
local chaosBanner = Instance.new("Frame")
chaosBanner.Name = "ChaosBanner"
chaosBanner.Size = UDim2.new(0.6, 0, 0, 45)
chaosBanner.Position = UDim2.new(0.5, 0, 0, 80)
chaosBanner.AnchorPoint = Vector2.new(0.5, 0)
chaosBanner.BackgroundColor3 = COLORS.Chaos
chaosBanner.BackgroundTransparency = 0.2
chaosBanner.Visible = false
chaosBanner.Parent = screenGui
addCorner(chaosBanner, 8)

local chaosBannerText = Instance.new("TextLabel")
chaosBannerText.Name = "BannerText"
chaosBannerText.Size = UDim2.new(1, 0, 1, 0)
chaosBannerText.BackgroundTransparency = 1
chaosBannerText.Text = ""
chaosBannerText.TextColor3 = COLORS.Text
chaosBannerText.Font = Enum.Font.GothamBold
chaosBannerText.TextSize = 22
chaosBannerText.Parent = chaosBanner

-- ============================================================================
-- CLASSEMENT HÉROS — Panneau latéral droit (phase Résultat)
-- ============================================================================
local heroFrame = Instance.new("Frame")
heroFrame.Name = "HeroFrame"
heroFrame.Size = UDim2.new(0, 280, 0, 250)
heroFrame.Position = UDim2.new(1, -295, 0.5, 0)
heroFrame.AnchorPoint = Vector2.new(0, 0.5)
heroFrame.BackgroundColor3 = COLORS.Background
heroFrame.BackgroundTransparency = 0.15
heroFrame.Visible = false
heroFrame.Parent = screenGui
addCorner(heroFrame, 12)
addStroke(heroFrame, COLORS.Cash, 2)
addPadding(heroFrame, 12)

local heroTitle = Instance.new("TextLabel")
heroTitle.Name = "HeroTitle"
heroTitle.Size = UDim2.new(1, 0, 0, 30)
heroTitle.BackgroundTransparency = 1
heroTitle.Text = "HÉROS DU CHAOS"
heroTitle.TextColor3 = COLORS.Cash
heroTitle.Font = Enum.Font.GothamBold
heroTitle.TextSize = 18
heroTitle.Parent = heroFrame

-- Conteneur pour les lignes du classement
local heroList = Instance.new("Frame")
heroList.Name = "HeroList"
heroList.Size = UDim2.new(1, 0, 1, -35)
heroList.Position = UDim2.new(0, 0, 0, 35)
heroList.BackgroundTransparency = 1
heroList.Parent = heroFrame

local heroListLayout = Instance.new("UIListLayout")
heroListLayout.SortOrder = Enum.SortOrder.LayoutOrder
heroListLayout.Padding = UDim.new(0, 5)
heroListLayout.Parent = heroList

-- ============================================================================
-- LEVEL UP POPUP
-- ============================================================================
local levelUpPopup = Instance.new("Frame")
levelUpPopup.Name = "LevelUpPopup"
levelUpPopup.Size = UDim2.new(0, 350, 0, 60)
levelUpPopup.Position = UDim2.new(0.5, 0, 0.2, 0)
levelUpPopup.AnchorPoint = Vector2.new(0.5, 0.5)
levelUpPopup.BackgroundColor3 = Color3.fromRGB(30, 20, 50)
levelUpPopup.BackgroundTransparency = 0.15
levelUpPopup.Visible = false
levelUpPopup.Parent = screenGui
addCorner(levelUpPopup, 12)
addStroke(levelUpPopup, COLORS.Stars, 2)

local levelUpText = Instance.new("TextLabel")
levelUpText.Name = "LevelUpText"
levelUpText.Size = UDim2.new(1, 0, 1, 0)
levelUpText.BackgroundTransparency = 1
levelUpText.Text = "LEVEL UP !"
levelUpText.TextColor3 = COLORS.Stars
levelUpText.Font = Enum.Font.GothamBold
levelUpText.TextSize = 24
levelUpText.Parent = levelUpPopup

-- ============================================================================
-- TIMER LOCAL — Compte à rebours côté client
-- ============================================================================
local currentPhaseDuration = 0
local phaseStartTime = 0

task.spawn(function()
    while true do
        task.wait(0.5)
        if currentPhaseDuration > 0 and phaseStartTime > 0 then
            local elapsed = tick() - phaseStartTime
            local remaining = math.max(0, currentPhaseDuration - elapsed)
            phaseTimerLabel.Text = formatTime(math.ceil(remaining))
        end
    end
end)

-- ============================================================================
-- FONCTIONS DE MISE À JOUR
-- ============================================================================

local function updateCash(amount)
    cashLabel.Text = "$ " .. formatNumber(amount)
    -- Petit effet de flash quand le cash change
    tweenProperty(cashLabel, {TextColor3 = Color3.fromRGB(255, 255, 255)}, 0.1)
    task.delay(0.15, function()
        tweenProperty(cashLabel, {TextColor3 = COLORS.Cash}, 0.3)
    end)
end

local function updateStars(amount)
    starsLabel.Text = tostring(amount) .. " "
end

local function updateJob(jobId)
    local jobConfig = GameConfig.Jobs[jobId]
    if jobConfig then
        jobLabel.Text = jobConfig.DisplayName
        addStroke(jobFrame, jobConfig.Color, 1)
    end
end

local function updatePhase(phaseName, duration, extraData)
    currentPhaseDuration = duration
    phaseStartTime = tick()

    local phaseStroke = phaseFrame:FindFirstChildOfClass("UIStroke")

    if phaseName == "Calm" then
        phaseNameLabel.Text = "CALME"
        phaseNameLabel.TextColor3 = COLORS.Calm
        if phaseStroke then phaseStroke.Color = COLORS.Calm end
        chaosBanner.Visible = false
        heroFrame.Visible = false

    elseif phaseName == "Alert" then
        phaseNameLabel.Text = "ALERTE"
        phaseNameLabel.TextColor3 = COLORS.Alert
        if phaseStroke then phaseStroke.Color = COLORS.Alert end

        -- Afficher la bannière d'alerte
        chaosBanner.Visible = true
        chaosBanner.BackgroundColor3 = COLORS.Alert
        if extraData and extraData.DisasterName then
            chaosBannerText.Text = "CATASTROPHE IMMINENTE : " .. extraData.DisasterName
            if extraData.IsCombo then
                chaosBannerText.Text = "COMBO : " .. extraData.DisasterName
                    .. " + " .. tostring(extraData.SecondDisasterName)
            end
        else
            chaosBannerText.Text = "QUELQUE CHOSE ARRIVE..."
        end

    elseif phaseName == "Chaos" then
        phaseNameLabel.Text = "CHAOS"
        phaseNameLabel.TextColor3 = COLORS.Chaos
        if phaseStroke then phaseStroke.Color = COLORS.Chaos end

        -- Bannière chaos
        chaosBanner.Visible = true
        chaosBanner.BackgroundColor3 = COLORS.Chaos
        if extraData then
            local multi = extraData.BaseMultiplier or 5
            chaosBannerText.Text = "CHAOS ACTIF — Multiplicateur x" .. multi
        end

    elseif phaseName == "Result" then
        phaseNameLabel.Text = "RÉSULTAT"
        phaseNameLabel.TextColor3 = COLORS.Result
        if phaseStroke then phaseStroke.Color = COLORS.Result end
        chaosBanner.Visible = false

        -- Afficher le classement
        if extraData and extraData.Ranking then
            showHeroRanking(extraData.Ranking)
        end
    end
end

local function showMission(missionInfo)
    missionFrame.Visible = true
    missionDescription.Text = missionInfo.Description

    if missionInfo.IsChaos then
        missionTitle.Text = "MISSION CHAOS"
        missionTitle.TextColor3 = COLORS.Chaos
        local stroke = missionFrame:FindFirstChildOfClass("UIStroke")
        if stroke then stroke.Color = COLORS.Chaos end
    else
        missionTitle.Text = "MISSION"
        missionTitle.TextColor3 = COLORS.Mission
        local stroke = missionFrame:FindFirstChildOfClass("UIStroke")
        if stroke then stroke.Color = COLORS.Mission end
    end
end

local function showReward(result)
    rewardPopup.Visible = true

    local details = "+$" .. formatNumber(result.CashEarned) .. "  |  +" .. result.XPEarned .. " XP"
    if result.IsChaos and result.ChaosScoreEarned > 0 then
        details = details .. "  |  +" .. result.ChaosScoreEarned .. " pts"
    end
    rewardDetails.Text = details

    -- Animer : apparition → attente → disparition
    rewardPopup.BackgroundTransparency = 0.15
    task.delay(2.5, function()
        tweenProperty(rewardPopup, {BackgroundTransparency = 1}, 0.5)
        tweenProperty(rewardText, {TextTransparency = 1}, 0.5)
        tweenProperty(rewardDetails, {TextTransparency = 1}, 0.5)
        task.delay(0.6, function()
            rewardPopup.Visible = false
            -- Réinitialiser pour la prochaine fois
            rewardText.TextTransparency = 0
            rewardDetails.TextTransparency = 0
            rewardPopup.BackgroundTransparency = 0.15
        end)
    end)
end

-- Afficher le classement Héros du Chaos
function showHeroRanking(ranking)
    heroFrame.Visible = true

    -- Nettoyer les anciennes entrées
    for _, child in ipairs(heroList:GetChildren()) do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    -- Créer les lignes du classement
    local medals = {"#1", "#2", "#3", "#4", "#5"}
    local medalColors = {
        COLORS.Cash,                       -- Or
        Color3.fromRGB(200, 200, 210),     -- Argent
        Color3.fromRGB(205, 127, 50),      -- Bronze
        COLORS.TextDim,
        COLORS.TextDim,
    }

    for i, entry in ipairs(ranking) do
        local line = Instance.new("TextLabel")
        line.Name = "Rank" .. i
        line.Size = UDim2.new(1, 0, 0, 35)
        line.BackgroundColor3 = COLORS.BackgroundLight
        line.BackgroundTransparency = 0.5
        line.Text = "  " .. medals[i] .. "  " .. entry.Name .. "  —  " .. entry.Score .. " pts"
        line.TextColor3 = medalColors[i] or COLORS.TextDim
        line.Font = Enum.Font.GothamBold
        line.TextSize = 15
        line.TextXAlignment = Enum.TextXAlignment.Left
        line.LayoutOrder = i
        line.Parent = heroList
        addCorner(line, 6)
    end

    -- Cacher après la phase résultat
    task.delay(GameConfig.Phases.Result.Duration, function()
        heroFrame.Visible = false
    end)
end

local function showLevelUp(jobId, newLevel)
    local jobConfig = GameConfig.Jobs[jobId]
    local jobName = jobConfig and jobConfig.DisplayName or jobId

    levelUpText.Text = "LEVEL UP ! " .. jobName .. " Nv." .. newLevel
    levelUpPopup.Visible = true

    -- Disparition après 3 secondes
    task.delay(3, function()
        tweenProperty(levelUpPopup, {BackgroundTransparency = 1}, 0.5)
        tweenProperty(levelUpText, {TextTransparency = 1}, 0.5)
        task.delay(0.6, function()
            levelUpPopup.Visible = false
            levelUpText.TextTransparency = 0
            levelUpPopup.BackgroundTransparency = 0.15
        end)
    end)
end

-- ============================================================================
-- CONNEXION AUX REMOTE EVENTS
-- ============================================================================

cashUpdatedEvent.OnClientEvent:Connect(function(newCash)
    updateCash(newCash)
end)

chaosStarsUpdatedEvent.OnClientEvent:Connect(function(newStars)
    updateStars(newStars)
end)

phaseChangedEvent.OnClientEvent:Connect(function(phaseName, duration, extraData)
    updatePhase(phaseName, duration, extraData)
end)

missionAssignedEvent.OnClientEvent:Connect(function(missionInfo)
    showMission(missionInfo)
end)

missionCompletedEvent.OnClientEvent:Connect(function(result)
    missionFrame.Visible = false
    showReward(result)
    updateCash(result.NewCash)
end)

heroRankingUpdatedEvent.OnClientEvent:Connect(function(ranking)
    showHeroRanking(ranking)
end)

jobLevelUpEvent.OnClientEvent:Connect(function(jobId, newLevel)
    showLevelUp(jobId, newLevel)
end)

jobChangedEvent.OnClientEvent:Connect(function(newJobId)
    updateJob(newJobId)
end)

-- ============================================================================
-- INITIALISATION — Charger les données initiales
-- ============================================================================
task.wait(2)

local myData = getPlayerDataFunc:InvokeServer()
if myData then
    updateCash(myData.Cash)
    updateStars(myData.ChaosStars)
    updateJob(myData.CurrentJob)
end

print("[HUD] Interface joueur initialisée !")
