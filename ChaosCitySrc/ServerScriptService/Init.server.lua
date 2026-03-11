--[[
    Init.server.lua
    Emplacement : ServerScriptService/Init

    POINT D'ENTRÉE DU SERVEUR.
    C'est le premier script qui s'exécute quand le serveur démarre.

    POURQUOI ".server.lua" ?
    - Dans Roblox, le suffixe du fichier détermine OÙ il s'exécute :
      - .server.lua → s'exécute sur le SERVEUR uniquement
      - .client.lua → s'exécute sur le CLIENT uniquement
      - .lua (sans suffixe) → c'est un MODULE (require-able des deux côtés)
    - Même si ce fichier est dans ServerScriptService (déjà serveur-only),
      le suffixe .server est une bonne pratique pour la clarté.

    CE QUE FAIT CE SCRIPT :
    1. Crée les RemoteEvents nécessaires à la communication Client ↔ Serveur
    2. Initialise tous les services dans le bon ordre
]]

-- ============================================================================
-- SERVICES ROBLOX
-- ============================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ============================================================================
-- ÉTAPE 1 : CRÉER LES REMOTEEVENTS
-- ============================================================================
--[[
    CONCEPT CLÉ — RemoteEvent et RemoteFunction :

    Sur Roblox, le serveur et le client sont des processus SÉPARÉS.
    Ils ne partagent PAS la même mémoire. Pour communiquer :

    RemoteEvent (unidirectionnel) :
    - Serveur → Client : "FireClient(player, ...)" — ex: "ton cash a changé"
    - Client → Serveur : "FireServer(...)" — ex: "je veux acheter cet item"
    → Utilisé pour les NOTIFICATIONS (pas besoin de réponse)

    RemoteFunction (bidirectionnel) :
    - Client → Serveur → Client : le client demande, le serveur répond
    → Utilisé quand le client a BESOIN d'une réponse (ex: "quel est mon solde ?")

    SÉCURITÉ :
    - JAMAIS faire confiance aux données envoyées par le client via RemoteEvent
    - Toujours vérifier côté serveur (le client peut être hacké)

    POURQUOI LES CRÉER ICI (côté serveur) ?
    - Le serveur doit créer les RemoteEvents AVANT que les clients essaient de s'y connecter
    - Si un client essaie de se connecter à un RemoteEvent qui n'existe pas encore → erreur
]]

-- Créer le dossier pour les RemoteEvents s'il n'existe pas
local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
    eventsFolder = Instance.new("Folder")
    eventsFolder.Name = "Events"
    eventsFolder.Parent = ReplicatedStorage
end

local remoteEventsFolder = eventsFolder:FindFirstChild("RemoteEvents")
if not remoteEventsFolder then
    remoteEventsFolder = Instance.new("Folder")
    remoteEventsFolder.Name = "RemoteEvents"
    remoteEventsFolder.Parent = eventsFolder
end

local remoteFunctionsFolder = eventsFolder:FindFirstChild("RemoteFunctions")
if not remoteFunctionsFolder then
    remoteFunctionsFolder = Instance.new("Folder")
    remoteFunctionsFolder.Name = "RemoteFunctions"
    remoteFunctionsFolder.Parent = eventsFolder
end

-- Fonction utilitaire : crée un RemoteEvent s'il n'existe pas déjà
local function createRemoteEvent(name: string)
    if not remoteEventsFolder:FindFirstChild(name) then
        local event = Instance.new("RemoteEvent")
        event.Name = name
        event.Parent = remoteEventsFolder
    end
end

-- Fonction utilitaire : crée une RemoteFunction si elle n'existe pas déjà
local function createRemoteFunction(name: string)
    if not remoteFunctionsFolder:FindFirstChild(name) then
        local func = Instance.new("RemoteFunction")
        func.Name = name
        func.Parent = remoteFunctionsFolder
    end
end

-- ── Remote Events (Serveur → Client) ──
createRemoteEvent("CashUpdated")         -- Notifier le client que son cash a changé
createRemoteEvent("ChaosStarsUpdated")   -- Notifier le client que ses étoiles ont changé
createRemoteEvent("PhaseChanged")        -- Notifier tous les clients du changement de phase
createRemoteEvent("DisasterStarted")     -- Notifier le type de catastrophe qui commence
createRemoteEvent("HeroRankingUpdated")  -- Envoyer le classement Héros du Chaos
createRemoteEvent("JobLevelUp")          -- Notifier le client d'un level up de métier
createRemoteEvent("MissionAssigned")     -- Assigner une nouvelle mission au client
createRemoteEvent("MissionCompleted")    -- Confirmer qu'une mission est terminée

-- ── Remote Events (Client → Serveur) ──
createRemoteEvent("RequestJobChange")    -- Le client demande à changer de métier
createRemoteEvent("RequestPurchase")     -- Le client demande à acheter un item
createRemoteEvent("MissionAction")       -- Le client signale une action de mission
createRemoteEvent("PlaceBet")            -- Le client place un pari au bookmaker

-- ── Remote Functions (Client ↔ Serveur) ──
createRemoteFunction("GetPlayerData")    -- Le client demande ses données actuelles

print("[Init] RemoteEvents et RemoteFunctions créés.")

-- ============================================================================
-- ÉTAPE 2 : INITIALISER LES SERVICES
-- ============================================================================
--[[
    ORDRE D'INITIALISATION IMPORTANT :
    1. DataService EN PREMIER (les autres services en dépendent)
    2. Les autres services ensuite (ordre flexible)

    On utilise require() pour charger chaque module service.
    require() en Luau fonctionne comme import en Python/JS :
    - Il exécute le fichier UNE SEULE FOIS
    - Il retourne la valeur que le module a retournée (return DataService)
    - Les appels suivants à require() retournent le même résultat (cache)
]]

-- Charger et initialiser le DataService
local DataService = require(ServerScriptService.Services.DataService)
DataService.Init()

-- Charger et initialiser le PhaseService (cycle Calme/Alerte/Chaos/Résultat)
local PhaseService = require(ServerScriptService.Services.PhaseService)
PhaseService.Init()

-- Charger et initialiser le JobService (métiers, missions, XP)
local JobService = require(ServerScriptService.Services.JobService)
JobService.Init()

-- Charger et initialiser l'EconomyService (achats, transactions, money sinks)
local EconomyService = require(ServerScriptService.Services.EconomyService)
EconomyService.Init()

-- Les prochains services seront initialisés ici au fur et à mesure :
-- local ChaosService = require(ServerScriptService.Services.ChaosService)
-- ChaosService.Init()

print("═══════════════════════════════════════")
print("   CHAOS CITY — Serveur démarré !")
print("═══════════════════════════════════════")
