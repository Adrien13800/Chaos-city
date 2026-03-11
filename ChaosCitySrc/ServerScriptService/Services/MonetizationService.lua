--[[
    MonetizationService.lua
    Emplacement : ServerScriptService/Services/MonetizationService

    GÈRE TOUS LES ACHATS ROBUX (Gamepasses + Developer Products).

    CONCEPTS CLÉS :

    1. MarketplaceService
       Le service Roblox qui gère les transactions Robux.
       - :UserOwnsGamePassAsync(userId, passId) → vérifie si un joueur possède un pass
       - :PromptGamePassPurchase(player, passId) → ouvre la fenêtre d'achat
       - :PromptProductPurchase(player, productId) → ouvre la fenêtre d'achat
       - .ProcessReceipt → callback serveur déclenché après chaque achat de DevProduct

    2. Gamepasses vs Developer Products
       - Gamepass : achat UNIQUE, permanent (ex: VIP). On vérifie une fois au login.
       - DevProduct : achat RÉPÉTABLE (ex: +5000 Cash). ProcessReceipt gère chaque achat.

    3. ProcessReceipt — LE PLUS IMPORTANT
       C'est le callback que Roblox appelle CHAQUE FOIS qu'un joueur achète un DevProduct.
       On DOIT retourner Enum.ProductPurchaseDecision.PurchaseGranted pour confirmer
       que le joueur a bien reçu ce qu'il a payé. Si on retourne NotProcessedYet,
       Roblox réessaiera plus tard (ex: si le serveur crash pendant l'achat).
       → TOUJOURS donner le produit AVANT de retourner PurchaseGranted.

    SÉCURITÉ :
    - Toutes les vérifications sont côté serveur
    - On ne fait JAMAIS confiance au client pour dire "j'ai un gamepass"
    - ProcessReceipt est appelé par Roblox lui-même, pas par le client
]]

-- ============================================================================
-- SERVICES ROBLOX
-- ============================================================================
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ============================================================================
-- SERVICES INTERNES
-- ============================================================================
local DataService = nil
local ChaosService = nil

-- ============================================================================
-- REMOTE EVENTS
-- ============================================================================
local remoteEvents = ReplicatedStorage.Events.RemoteEvents
local cashUpdatedEvent = remoteEvents.CashUpdated
local chaosStarsUpdatedEvent = remoteEvents.ChaosStarsUpdated

-- ============================================================================
-- IDS DES GAMEPASSES (depuis create.roblox.com)
-- ============================================================================
local GAMEPASS_IDS = {
    VIP              = 1745164663,   -- VIP Chaos City (399 R$)
    RadioPerso       = 1744560809,   -- Radio Perso (149 R$)
    PackDeco         = 1747041219,   -- Pack Déco+ (249 R$)
    MultiMetier      = 1745362682,   -- Multi-Métier Express (199 R$)
    DoubleInventory  = 1745400670,   -- Double Inventaire (149 R$)
}

-- ============================================================================
-- IDS DES DEVELOPER PRODUCTS (depuis create.roblox.com)
-- ============================================================================
local PRODUCT_IDS = {
    [3554124927] = "Cash5000",        -- +$5 000 Cash (49 R$)
    [3554125252] = "Cash25000",       -- +$25 000 Cash (199 R$)
    [3554125471] = "ChaosStars10",    -- +10 Chaos Stars (99 R$)
    [3554125762] = "InstantRespawn",  -- Respawn Immédiat (29 R$)
    [3554125969] = "XPBoost30",       -- Boost XP x2 - 30 min (149 R$)
}

-- ============================================================================
-- MODULE
-- ============================================================================
local MonetizationService = {}

-- Cache des gamepasses possédés par joueur (pour éviter de re-vérifier à chaque frame)
-- Format : { [Player.UserId] = { VIP = true, DoubleInventory = true, ... } }
local gamepassCache = {}

-- ============================================================================
-- VÉRIFICATION DES GAMEPASSES
-- ============================================================================

--[[
    Vérifie si un joueur possède un gamepass spécifique.
    Utilise un cache en mémoire pour ne pas spammer l'API Roblox.
]]
function MonetizationService.PlayerOwnsGamepass(player: Player, passName: string): boolean
    local cache = gamepassCache[player.UserId]
    if cache then
        return cache[passName] == true
    end
    return false
end

--[[
    Charge tous les gamepasses d'un joueur au moment du login.
    Appelé une seule fois par joueur (dans PlayerAdded).
]]
function MonetizationService._LoadGamepasses(player: Player)
    local cache = {}

    for passName, passId in pairs(GAMEPASS_IDS) do
        local success, ownsPass = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
        end)

        if success and ownsPass then
            cache[passName] = true
            print("[MonetizationService] " .. player.Name .. " possède le pass : " .. passName)
        end
    end

    gamepassCache[player.UserId] = cache

    -- Sauvegarder dans les données joueur (pour référence)
    local data = DataService.GetData(player)
    if data then
        local ownedList = {}
        for passName, _ in pairs(cache) do
            table.insert(ownedList, passName)
        end
        data.OwnedGamepasses = ownedList
    end

    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    print("[MonetizationService] " .. player.Name .. " : " .. count .. " gamepass(es) chargé(s)")
end

-- ============================================================================
-- TRAITEMENT DES ACHATS DE DEVELOPER PRODUCTS
-- ============================================================================

--[[
    ProcessReceipt est le callback CRITIQUE de la monétisation.
    Roblox l'appelle à chaque achat de DevProduct.

    RÈGLES :
    - Donner le produit au joueur
    - Retourner PurchaseGranted SEULEMENT si le produit a bien été donné
    - Si erreur → retourner NotProcessedYet (Roblox réessaiera)
]]
local function processReceipt(receiptInfo)
    -- Trouver le joueur qui a acheté
    local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
    if not player then
        -- Le joueur s'est déconnecté → Roblox réessaiera au prochain login
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    -- Identifier le produit acheté
    local productName = PRODUCT_IDS[receiptInfo.ProductId]
    if not productName then
        warn("[MonetizationService] Produit inconnu : " .. tostring(receiptInfo.ProductId))
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    -- Vérifier que les données du joueur sont chargées
    local data = DataService.GetData(player)
    if not data then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    print("[MonetizationService] Achat de " .. player.Name .. " : " .. productName)

    -- ── +$5 000 Cash ──
    if productName == "Cash5000" then
        DataService.AddCash(player, 5000)
        cashUpdatedEvent:FireClient(player, DataService.GetCash(player))
        print("[MonetizationService] +$5 000 pour " .. player.Name)

    -- ── +$25 000 Cash ──
    elseif productName == "Cash25000" then
        DataService.AddCash(player, 25000)
        cashUpdatedEvent:FireClient(player, DataService.GetCash(player))
        print("[MonetizationService] +$25 000 pour " .. player.Name)

    -- ── +10 Chaos Stars ──
    elseif productName == "ChaosStars10" then
        DataService.AddChaosStars(player, 10)
        chaosStarsUpdatedEvent:FireClient(player, DataService.GetChaosStars(player))
        print("[MonetizationService] +10 Chaos Stars pour " .. player.Name)

    -- ── Respawn Immédiat ──
    elseif productName == "InstantRespawn" then
        if ChaosService.IsPlayerKnockedOut(player) then
            ChaosService.RevivePlayer(player)
            print("[MonetizationService] Respawn immédiat pour " .. player.Name)
        else
            -- Le joueur n'est pas KO → on lui rembourse en cash ($500 de compensation)
            DataService.AddCash(player, 500)
            cashUpdatedEvent:FireClient(player, DataService.GetCash(player))
            print("[MonetizationService] " .. player.Name
                  .. " n'est pas KO → compensation $500")
        end

    -- ── Boost XP x2 (30 min) ──
    elseif productName == "XPBoost30" then
        data.XPBoostExpiry = os.time() + (30 * 60)  -- 30 minutes à partir de maintenant
        print("[MonetizationService] Boost XP x2 activé pour " .. player.Name
              .. " (expire dans 30 min)")

    else
        warn("[MonetizationService] Produit non géré : " .. productName)
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    -- Achat réussi → confirmer à Roblox
    return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ============================================================================
-- ÉCOUTER LES ACHATS DE GAMEPASSES EN JEU
-- ============================================================================

--[[
    Quand un joueur achète un Gamepass PENDANT qu'il joue (pas depuis la page du jeu),
    on met à jour le cache immédiatement sans attendre le prochain login.
]]
local function setupGamepassPurchaseListener()
    MarketplaceService.PromptGamePassPurchaseFinished:Connect(
        function(player, passId, wasPurchased)
            if not wasPurchased then return end

            -- Trouver le nom du pass
            for passName, id in pairs(GAMEPASS_IDS) do
                if id == passId then
                    if not gamepassCache[player.UserId] then
                        gamepassCache[player.UserId] = {}
                    end
                    gamepassCache[player.UserId][passName] = true
                    print("[MonetizationService] " .. player.Name
                          .. " vient d'acheter le pass : " .. passName .. " !")
                    break
                end
            end
        end
    )
end

-- ============================================================================
-- API PUBLIQUE
-- ============================================================================

-- Vérifie si le joueur est VIP (double les récompenses Cash des missions)
function MonetizationService.IsVIP(player: Player): boolean
    return MonetizationService.PlayerOwnsGamepass(player, "VIP")
end

-- Vérifie si le joueur a le pass Multi-Métier (changement de job sans zone)
function MonetizationService.HasMultiMetier(player: Player): boolean
    return MonetizationService.PlayerOwnsGamepass(player, "MultiMetier")
end

-- Vérifie si le joueur a le pass Double Inventaire
function MonetizationService.HasDoubleInventory(player: Player): boolean
    return MonetizationService.PlayerOwnsGamepass(player, "DoubleInventory")
end

-- Vérifie si le joueur a le pass Pack Déco+
function MonetizationService.HasPackDeco(player: Player): boolean
    return MonetizationService.PlayerOwnsGamepass(player, "PackDeco")
end

-- Vérifie si le joueur a le pass Radio Perso
function MonetizationService.HasRadioPerso(player: Player): boolean
    return MonetizationService.PlayerOwnsGamepass(player, "RadioPerso")
end

-- Vérifie si le joueur a un boost XP actif
function MonetizationService.HasXPBoost(player: Player): boolean
    local data = DataService.GetData(player)
    if not data then return false end
    return data.XPBoostExpiry > os.time()
end

-- Retourne le multiplicateur de Cash (1 = normal, 2 = VIP)
function MonetizationService.GetCashMultiplier(player: Player): number
    if MonetizationService.IsVIP(player) then
        return 2
    end
    return 1
end

-- Retourne le multiplicateur d'XP (1 = normal, 2 = boost actif)
function MonetizationService.GetXPMultiplier(player: Player): number
    if MonetizationService.HasXPBoost(player) then
        return 2
    end
    return 1
end

-- Retourne la capacité max d'inventaire (5 = normal, 10 = double inventaire)
function MonetizationService.GetMaxStack(player: Player): number
    if MonetizationService.HasDoubleInventory(player) then
        return 10
    end
    return 5
end

-- Retourne les IDs des gamepasses (pour que le client puisse ouvrir les prompts d'achat)
function MonetizationService.GetGamepassIDs()
    return GAMEPASS_IDS
end

-- Retourne les IDs des developer products
function MonetizationService.GetProductIDs()
    -- Retourner un mapping nom → id (inverse de PRODUCT_IDS)
    local result = {}
    for id, name in pairs(PRODUCT_IDS) do
        result[name] = id
    end
    return result
end

-- ============================================================================
-- INITIALISATION
-- ============================================================================
function MonetizationService.Init()
    DataService = require(ServerScriptService.Services.DataService)
    ChaosService = require(ServerScriptService.Services.ChaosService)

    -- Enregistrer le callback ProcessReceipt (UN SEUL par jeu !)
    MarketplaceService.ProcessReceipt = processReceipt

    -- Écouter les achats de gamepasses en jeu
    setupGamepassPurchaseListener()

    -- Charger les gamepasses des joueurs déjà connectés
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            MonetizationService._LoadGamepasses(player)
        end)
    end

    -- Charger les gamepasses pour chaque nouveau joueur
    Players.PlayerAdded:Connect(function(player)
        -- Attendre que les données soient chargées par DataService
        task.wait(2)
        MonetizationService._LoadGamepasses(player)
    end)

    -- Nettoyer le cache quand un joueur quitte
    Players.PlayerRemoving:Connect(function(player)
        gamepassCache[player.UserId] = nil
    end)

    print("[MonetizationService] Initialisé avec succès !")
    print("[MonetizationService] Gamepasses : " .. tostring(5) .. " | DevProducts : " .. tostring(5))
end

return MonetizationService
