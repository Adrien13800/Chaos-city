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
phaseChangedEvent.OnClientEvent:Connect(function(phaseName: string, duration: number)
    print("[UI] === PHASE : " .. phaseName .. " (" .. duration .. "s) ===")

    -- TODO : Déclencher les effets visuels selon la phase
    -- if phaseName == "Alert" then → sirènes, changement de ciel
    -- if phaseName == "Chaos" then → camera shake, particules
    -- if phaseName == "Result" then → afficher le classement
end)

-- Quand on monte de niveau dans un métier
jobLevelUpEvent.OnClientEvent:Connect(function(jobId: string, newLevel: number)
    print("[UI] LEVEL UP ! " .. jobId .. " → Niveau " .. newLevel .. " !")
    -- TODO : Afficher une popup de level up avec effets
end)
