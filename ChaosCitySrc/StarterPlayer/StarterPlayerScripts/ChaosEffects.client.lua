--[[
    ChaosEffects.client.lua
    Emplacement : StarterPlayer/StarterPlayerScripts/ChaosEffects

    SCRIPT CLIENT — Gère tous les effets visuels et sonores des catastrophes.

    POURQUOI UN SCRIPT SÉPARÉ DE DataUI ?
    DataUI gère les données (cash, missions, phases).
    ChaosEffects gère le SPECTACLE (caméra, ciel, sons).
    Séparer les responsabilités = code plus propre et plus facile à débugger.

    CE QU'IL FAIT :
    - Écoute les événements PhaseChanged et DisasterStarted
    - Phase Alerte → sirène, changement progressif du ciel
    - Phase Chaos → camera shake, effets visuels selon la catastrophe
    - Phase Résultat/Calme → retour à la normale

    CONCEPT CLÉ — Lighting :
    Le service Lighting contrôle l'éclairage global du jeu :
    ambiance, couleur du ciel, brouillard, luminosité.
    Modifier ces propriétés côté client ne change l'affichage
    QUE pour ce joueur (chaque client a son propre rendu).

    CONCEPT CLÉ — TweenService :
    TweenService crée des animations fluides entre deux valeurs.
    C'est l'équivalent de CSS transitions ou de GSAP en web.
    Ex : changer la couleur du ciel de bleu à rouge en 3 secondes.
]]

-- ============================================================================
-- SERVICES ROBLOX
-- ============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

-- ============================================================================
-- RÉFÉRENCES
-- ============================================================================
local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

local events = ReplicatedStorage:WaitForChild("Events")
local remoteEvents = events:WaitForChild("RemoteEvents")
local phaseChangedEvent = remoteEvents:WaitForChild("PhaseChanged")
local disasterStartedEvent = remoteEvents:WaitForChild("DisasterStarted")

-- ============================================================================
-- ÉTAT
-- ============================================================================

-- Sauvegarder les valeurs originales du Lighting pour les restaurer après
local originalLighting = {
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    FogColor = Lighting.FogColor,
}

-- Est-ce qu'on est en train de shaker la caméra ?
local isShaking = false

-- Thread du camera shake (pour pouvoir l'arrêter)
local shakeThread = nil

-- ============================================================================
-- CAMERA SHAKE
-- ============================================================================

--[[
    Fait trembler la caméra du joueur.

    intensity : force du tremblement (1 = léger, 5 = violent)
    duration : durée en secondes (0 = infini, jusqu'à ce qu'on l'arrête)

    COMMENT ÇA MARCHE :
    On modifie le CFrame (position + rotation) de la caméra à chaque frame
    en ajoutant un petit décalage aléatoire. Le moteur de rendu recalcule
    la caméra ~60 fois par seconde, donc on obtient un tremblement fluide.

    RenderStepped : événement qui se déclenche AVANT chaque frame rendue.
    C'est le meilleur endroit pour modifier la caméra car le changement
    sera visible immédiatement dans le frame suivant.
]]
local function startCameraShake(intensity: number)
    if isShaking then return end
    isShaking = true

    shakeThread = task.spawn(function()
        local RunService = game:GetService("RunService")

        while isShaking do
            -- Générer un décalage aléatoire proportionnel à l'intensité
            local offsetX = (math.random() - 0.5) * intensity * 0.3
            local offsetY = (math.random() - 0.5) * intensity * 0.3
            local offsetZ = (math.random() - 0.5) * intensity * 0.1

            -- Appliquer le décalage au CFrame de la caméra
            --[[
                CFrame = Coordinate Frame = position + orientation dans l'espace 3D
                C'est LE concept fondamental de Roblox pour positionner les objets.

                camera.CFrame * CFrame.new(x, y, z) :
                Multiplie (combine) le CFrame actuel avec un petit décalage.
                Résultat : la caméra bouge légèrement dans une direction aléatoire.
            ]]
            camera.CFrame = camera.CFrame * CFrame.new(offsetX, offsetY, offsetZ)

            -- Attendre la prochaine frame
            RunService.RenderStepped:Wait()
        end
    end)
end

local function stopCameraShake()
    isShaking = false
end

-- ============================================================================
-- EFFETS DE CIEL / AMBIANCE
-- ============================================================================

--[[
    Changer l'ambiance du jeu progressivement (transition fluide).
    Utilise TweenService pour une transition smooth.
]]
local function tweenLighting(properties, duration: number)
    --[[
        TweenInfo définit COMMENT l'animation se comporte :
        - duration : durée en secondes
        - EasingStyle : la "courbe" de l'animation
          - Linear = vitesse constante
          - Quad = accélère puis décélère (plus naturel)
        - EasingDirection : In, Out, ou InOut
    ]]
    local tweenInfo = TweenInfo.new(
        duration,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.InOut
    )

    local tween = TweenService:Create(Lighting, tweenInfo, properties)
    tween:Play()

    return tween
end

-- Mettre l'ambiance en mode ALERTE (ciel qui change, atmosphère tendue)
local function setAlertAmbiance(skyColor: Color3)
    tweenLighting({
        Ambient = Color3.fromRGB(80, 60, 60),
        OutdoorAmbient = skyColor,
        FogEnd = 800,
        FogColor = skyColor,
    }, 5)  -- Transition de 5 secondes

    print("[ChaosEffects] Ambiance alerte activée")
end

-- Mettre l'ambiance en mode CHAOS (intense, sombre)
local function setChaosAmbiance(disasterType: string, skyColor: Color3)
    local properties = {
        Ambient = Color3.fromRGB(40, 30, 30),
        OutdoorAmbient = skyColor,
        FogEnd = 400,
        FogColor = skyColor,
    }

    -- Effets spéciaux par type de catastrophe
    if disasterType == "Blackout" then
        -- Panne générale : nuit totale
        properties.Brightness = 0
        properties.ClockTime = 0
        properties.FogEnd = 100  -- Brouillard très dense
        properties.Ambient = Color3.fromRGB(5, 5, 10)
    elseif disasterType == "Flood" then
        -- Inondation : brouillard bleu
        properties.FogEnd = 300
        properties.FogColor = Color3.fromRGB(20, 60, 120)
    elseif disasterType == "Tornado" then
        -- Tornade : ciel gris, vent
        properties.FogEnd = 250
        properties.Brightness = 0.5
    end

    tweenLighting(properties, 3)  -- Transition rapide de 3 secondes

    print("[ChaosEffects] Ambiance chaos activée : " .. disasterType)
end

-- Restaurer l'ambiance normale (après le chaos)
local function resetAmbiance()
    tweenLighting(originalLighting, 5)  -- Retour progressif en 5 secondes

    print("[ChaosEffects] Ambiance restaurée")
end

-- ============================================================================
-- ÉCOUTE DES ÉVÉNEMENTS
-- ============================================================================

-- Quand la phase change
phaseChangedEvent.OnClientEvent:Connect(function(phaseName: string, duration: number, extraData)

    if phaseName == "Alert" then
        -- Phase Alerte : changement progressif du ciel
        if extraData and extraData.SkyColor then
            setAlertAmbiance(extraData.SkyColor)
        end

    elseif phaseName == "Chaos" then
        -- Phase Chaos : effets maximum
        if extraData then
            local disasterType = extraData.DisasterType
            local skyColor = Color3.fromRGB(150, 50, 50)  -- Rouge par défaut

            if disasterType and GameConfig then
                -- Charger la config pour la couleur du ciel
                local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
                local disasterConfig = GameConfig.Disasters[disasterType]
                if disasterConfig then
                    skyColor = disasterConfig.SkyColor
                end
            end

            setChaosAmbiance(extraData.DisasterType or "Earthquake", skyColor)

            -- Démarrer le camera shake
            local shakeIntensity = 1.5  -- Intensité de base
            if extraData.IntensityScale then
                shakeIntensity = shakeIntensity * extraData.IntensityScale
            end
            startCameraShake(shakeIntensity)
        end

    elseif phaseName == "Result" then
        -- Phase Résultat : arrêter le shake, commencer le retour à la normale
        stopCameraShake()
        -- On garde l'ambiance encore un peu sombre pendant le résultat
        tweenLighting({
            Ambient = Color3.fromRGB(100, 90, 90),
            FogEnd = 600,
            Brightness = originalLighting.Brightness * 0.8,
        }, 3)

    elseif phaseName == "Calm" then
        -- Phase Calme : tout revient à la normale
        stopCameraShake()
        resetAmbiance()
    end
end)

-- Quand une catastrophe spécifique démarre (effets supplémentaires)
disasterStartedEvent.OnClientEvent:Connect(function(disasterType: string, chaosData)
    print("[ChaosEffects] Catastrophe déclenchée : " .. tostring(disasterType))

    -- Effets spécifiques selon le type
    if disasterType == "Earthquake" then
        -- Séisme : shake violent
        stopCameraShake()
        startCameraShake(3)

    elseif disasterType == "Meteors" then
        -- Météorites : shake moyen + flash lumineux
        stopCameraShake()
        startCameraShake(2)

    elseif disasterType == "Tornado" then
        -- Tornade : shake constant moyen
        stopCameraShake()
        startCameraShake(2.5)

    elseif disasterType == "AlienInvasion" then
        -- Aliens : shake léger
        stopCameraShake()
        startCameraShake(1)

    elseif disasterType == "Flood" then
        -- Inondation : shake léger
        stopCameraShake()
        startCameraShake(0.8)

    elseif disasterType == "Blackout" then
        -- Panne : pas de shake, c'est le noir qui est le danger
        stopCameraShake()
    end
end)

print("[ChaosEffects] Initialisé avec succès !")
