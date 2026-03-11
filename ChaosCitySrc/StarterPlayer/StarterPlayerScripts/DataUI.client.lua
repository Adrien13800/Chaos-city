--[[
    DataUI.client.lua
    Emplacement : StarterPlayer/StarterPlayerScripts/DataUI

    SCRIPT CLIENT — Premier test de communication avec le serveur.

    CE QU'IL FAIT :
    - Quand le joueur rejoint, il demande ses données au serveur (via RemoteFunction)
    - Il écoute les mises à jour de cash envoyées par le serveur (via RemoteEvent)
    - Pour l'instant, il affiche les infos dans la console (Output)
    - Plus tard, on remplacera les print() par de vrais éléments d'UI (ScreenGui)

    POURQUOI ".client.lua" ?
    Ce code s'exécute sur la machine du JOUEUR, pas sur le serveur.
    Il n'a accès qu'aux données que le serveur lui envoie explicitement.

    POURQUOI DANS StarterPlayerScripts ?
    Tout script placé ici est AUTOMATIQUEMENT copié dans chaque joueur
    qui rejoint. C'est l'endroit standard pour les scripts client permanents
    (qui tournent pendant toute la session du joueur).

    ALTERNATIVE : StarterCharacterScripts
    Les scripts dans StarterCharacterScripts sont copiés à chaque RESPAWN.
    Utile pour les scripts liés au personnage (animations custom, etc.)
    mais PAS pour l'UI ou les données persistantes.
]]

-- ============================================================================
-- SERVICES ROBLOX (côté client)
-- ============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================================
-- RÉCUPÉRER LE JOUEUR LOCAL
-- ============================================================================
--[[
    Players.LocalPlayer est une propriété spéciale qui n'existe QUE côté client.
    Elle retourne le joueur qui exécute ce script.
    Sur le serveur, LocalPlayer n'existe PAS (le serveur gère tous les joueurs).
]]
local localPlayer = Players.LocalPlayer

-- ============================================================================
-- RÉFÉRENCES AUX REMOTE EVENTS/FUNCTIONS
-- ============================================================================
--[[
    WaitForChild() vs FindFirstChild() :

    FindFirstChild("X") → retourne X immédiatement ou nil si pas trouvé
    WaitForChild("X")   → ATTEND que X existe, puis le retourne
    WaitForChild("X", 10) → attend max 10 secondes, puis retourne nil si pas trouvé

    POURQUOI WaitForChild ICI ?
    Le client charge plus vite que le serveur. Ce script peut s'exécuter
    AVANT que Init.server.lua ait créé les RemoteEvents.
    WaitForChild attend patiemment que le serveur les crée.
]]
local events = ReplicatedStorage:WaitForChild("Events")
local remoteEvents = events:WaitForChild("RemoteEvents")
local remoteFunctions = events:WaitForChild("RemoteFunctions")

-- Remote Events
local cashUpdatedEvent = remoteEvents:WaitForChild("CashUpdated")
local chaosStarsUpdatedEvent = remoteEvents:WaitForChild("ChaosStarsUpdated")
local phaseChangedEvent = remoteEvents:WaitForChild("PhaseChanged")
local disasterStartedEvent = remoteEvents:WaitForChild("DisasterStarted")
local heroRankingEvent = remoteEvents:WaitForChild("HeroRankingUpdated")
local missionAssignedEvent = remoteEvents:WaitForChild("MissionAssigned")
local missionCompletedEvent = remoteEvents:WaitForChild("MissionCompleted")
local jobLevelUpEvent = remoteEvents:WaitForChild("JobLevelUp")

-- Remote Functions
local getPlayerDataFunc = remoteFunctions:WaitForChild("GetPlayerData")

-- ============================================================================
-- DEMANDER LES DONNÉES INITIALES AU SERVEUR
-- ============================================================================
--[[
    InvokeServer() envoie une requête au serveur et ATTEND la réponse.
    C'est comme un appel API HTTP en JS : await fetch("/api/player-data")

    ATTENTION : InvokeServer() est BLOQUANT (yield).
    Le script est mis en pause jusqu'à ce que le serveur réponde.
    Ne JAMAIS appeler ça dans une boucle rapide.
]]

-- On attend un peu que le DataService ait le temps de charger nos données
task.wait(2)

local myData = getPlayerDataFunc:InvokeServer()

if myData then
    print("══════════════════════════════════════")
    print("   Bienvenue dans CHAOS CITY !")
    print("   Cash : $" .. myData.Cash)
    print("   Étoiles : " .. myData.ChaosStars .. " ★")
    print("   Métier : " .. myData.CurrentJob)
    print("══════════════════════════════════════")
else
    warn("Impossible de récupérer les données. Reconnecte-toi.")
end

-- ============================================================================
-- ÉCOUTER LES MISES À JOUR EN TEMPS RÉEL
-- ============================================================================
--[[
    OnClientEvent est l'équivalent d'un addEventListener en JS.
    Quand le serveur fait FireClient(player, newCash), la fonction ci-dessous
    s'exécute automatiquement côté client.
]]

-- Quand le serveur nous notifie que notre cash a changé
cashUpdatedEvent.OnClientEvent:Connect(function(newCash: number)
    print("[UI] Cash mis à jour : $" .. newCash)
    -- TODO : Mettre à jour l'élément d'UI TextLabel avec le nouveau montant
end)

-- Quand le serveur nous notifie que nos étoiles ont changé
chaosStarsUpdatedEvent.OnClientEvent:Connect(function(newStars: number)
    print("[UI] Étoiles de Chaos : " .. newStars .. " ★")
end)

-- Quand la phase de jeu change
phaseChangedEvent.OnClientEvent:Connect(function(phaseName: string, duration: number, extraData: any?)
    print("[UI] ═══════════════════════════════════")

    if phaseName == "Calm" then
        print("[UI] PHASE : CALME — Travaillez et préparez-vous !")
        print("[UI] Durée : " .. duration .. "s")

    elseif phaseName == "Alert" then
        print("[UI] ⚠ PHASE : ALERTE — QUELQUE CHOSE ARRIVE...")
        print("[UI] Durée : " .. duration .. "s")
        if extraData then
            print("[UI] Catastrophe détectée : " .. tostring(extraData.DisasterName))
            if extraData.IsCombo then
                print("[UI] COMBO ! " .. tostring(extraData.DisasterName) .. " + " .. tostring(extraData.SecondDisasterName))
            end
        end

    elseif phaseName == "Chaos" then
        print("[UI] PHASE : CHAOS — SURVIVEZ ET TRAVAILLEZ !")
        print("[UI] Durée : " .. duration .. "s")
        if extraData then
            print("[UI] Multiplicateur de base : x" .. tostring(extraData.BaseMultiplier))
            print("[UI] Intensité : x" .. tostring(extraData.IntensityScale))
        end

    elseif phaseName == "Result" then
        print("[UI] PHASE : RÉSULTAT")
        if extraData then
            print("[UI] Catastrophe survécue : " .. tostring(extraData.DisasterName))
            print("[UI] Combo streak : " .. tostring(extraData.ChaosCount))
            if extraData.Ranking and #extraData.Ranking > 0 then
                print("[UI] ═══ HÉROS DU CHAOS ═══")
                for _, entry in ipairs(extraData.Ranking) do
                    print("[UI]   #" .. entry.Rank .. " " .. entry.Name .. " — " .. entry.Score .. " pts")
                end
            else
                print("[UI] (Aucun héros cette fois)")
            end
        end
    end

    print("[UI] ═══════════════════════════════════")
end)

-- Quand une catastrophe démarre (effets visuels spécifiques)
disasterStartedEvent.OnClientEvent:Connect(function(disasterType: string, chaosData)
    print("[UI] >>> CATASTROPHE : " .. disasterType .. " <<<")
    -- TODO : C'est ici qu'on déclenchera les effets visuels spécifiques :
    -- Earthquake → camera shake
    -- Flood → montée des eaux
    -- Meteors → boules de feu dans le ciel
    -- AlienInvasion → vaisseau + lumière verte
    -- Tornado → entonnoir + vent
    -- Blackout → nuit totale
end)

-- Quand le classement Héros est envoyé après un chaos
heroRankingEvent.OnClientEvent:Connect(function(ranking)
    if ranking and #ranking > 0 then
        print("[UI] >>> CLASSEMENT FINAL <<<")
        for _, entry in ipairs(ranking) do
            print("[UI]   #" .. entry.Rank .. " " .. entry.Name .. " — " .. entry.Score .. " pts")
        end
    end
end)

-- Quand une mission est assignée
missionAssignedEvent.OnClientEvent:Connect(function(missionInfo)
    print("[UI] ── NOUVELLE MISSION ──")
    print("[UI] " .. tostring(missionInfo.Description))
    print("[UI] Temps : " .. tostring(missionInfo.Duration) .. "s")
    if missionInfo.IsChaos then
        print("[UI] MISSION DE CHAOS — Multiplicateurs actifs !")
    end
    -- TODO : Afficher la mission dans un panel UI à l'écran
    -- TODO : Afficher un marqueur sur la minimap vers la zone de mission
end)

-- Quand une mission est complétée
missionCompletedEvent.OnClientEvent:Connect(function(result)
    print("[UI] ── MISSION COMPLÉTÉE ! ──")
    print("[UI] +$" .. tostring(result.CashEarned) .. " | +" .. tostring(result.XPEarned) .. " XP")
    if result.IsChaos and result.ChaosScoreEarned > 0 then
        print("[UI] +" .. tostring(result.ChaosScoreEarned) .. " pts Héros du Chaos !")
    end
    print("[UI] Cash total : $" .. tostring(result.NewCash))
    -- TODO : Afficher un popup de récompense avec animation
end)

-- Quand on monte de niveau dans un métier
jobLevelUpEvent.OnClientEvent:Connect(function(jobId: string, newLevel: number)
    print("[UI] LEVEL UP ! " .. jobId .. " → Niveau " .. newLevel .. " !")
    -- TODO : Afficher une popup de level up avec effets
end)
