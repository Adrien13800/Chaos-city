--[[
    EconomyService.lua
    Emplacement : ServerScriptService/Services/EconomyService

    GÈRE TOUTE L'ÉCONOMIE DU JEU :
    - Achats (logements, véhicules, outils, consommables)
    - Vérification des conditions d'achat (assez d'argent ? bon niveau ?)
    - Frais d'entretien des véhicules après le chaos
    - Money sinks (mécanismes anti-inflation)

    SÉCURITÉ :
    Toute transaction passe par le SERVEUR. Le client envoie une demande
    d'achat via RemoteEvent, le serveur vérifie tout et valide (ou refuse).
    Un hacker ne peut JAMAIS se donner un item sans que le serveur l'approuve.

    FLOW D'UN ACHAT :
    1. Le client clique sur "Acheter" dans le shop → envoie RequestPurchase au serveur
    2. Le serveur vérifie : a-t-il assez d'argent ? le niveau requis ? pas déjà possédé ?
    3. Si OK → retire l'argent, ajoute l'item à l'inventaire, notifie le client
    4. Si refusé → envoie un message d'erreur au client
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

local configFolder = ReplicatedStorage:FindFirstChild("Config")
local ShopConfig = nil
if configFolder and configFolder:FindFirstChild("ShopConfig") then
    ShopConfig = require(configFolder.ShopConfig)
else
    warn("[EconomyService] ShopConfig non trouvé !")
end

-- ============================================================================
-- SERVICES INTERNES
-- ============================================================================
local DataService = nil  -- Chargé dans Init()

-- ============================================================================
-- REMOTE EVENTS
-- ============================================================================
local remoteEvents = ReplicatedStorage.Events.RemoteEvents
local requestPurchaseEvent = remoteEvents.RequestPurchase
local cashUpdatedEvent = remoteEvents.CashUpdated

-- ============================================================================
-- MODULE PRINCIPAL
-- ============================================================================
local EconomyService = {}

-- ============================================================================
-- ACHAT DE LOGEMENT
-- Un seul logement à la fois. Acheter un meilleur = upgrade automatique.
-- ============================================================================
function EconomyService.PurchaseHousing(player: Player, housingId: string): (boolean, string)
    if not ShopConfig then return false, "Shop indisponible" end

    local data = DataService.GetData(player)
    if not data then return false, "Données non chargées" end

    -- Vérifier que le logement existe dans le shop
    local housingInfo = ShopConfig.Housing[housingId]
    if not housingInfo then
        return false, "Logement inconnu"
    end

    -- Vérifier si le joueur possède déjà ce logement
    if data.Housing.OwnedType == housingId then
        return false, "Tu possèdes déjà ce logement !"
    end

    -- Vérifier si le joueur essaie d'acheter un logement inférieur
    -- (on ne downgrade pas, ce serait une perte d'argent)
    local currentHousing = ShopConfig.Housing[data.Housing.OwnedType]
    if currentHousing and housingInfo.Order <= currentHousing.Order then
        return false, "Tu as déjà un logement supérieur !"
    end

    -- Vérifier le cash
    if data.Cash < housingInfo.Price then
        return false, "Pas assez d'argent ! Il te faut $" .. housingInfo.Price
    end

    -- Transaction : retirer l'argent et attribuer le logement
    local success = DataService.RemoveCash(player, housingInfo.Price)
    if not success then
        return false, "Erreur lors du paiement"
    end

    -- Mettre à jour le logement
    data.Housing.OwnedType = housingId

    -- Notifier le client
    cashUpdatedEvent:FireClient(player, data.Cash)

    print("[EconomyService] " .. player.Name .. " a acheté : "
          .. housingInfo.DisplayName .. " pour $" .. housingInfo.Price)

    return true, "Félicitations ! Tu as acheté : " .. housingInfo.DisplayName
end

-- ============================================================================
-- ACHAT DE VÉHICULE
-- Un joueur peut posséder plusieurs véhicules.
-- ============================================================================
function EconomyService.PurchaseVehicle(player: Player, vehicleId: string): (boolean, string)
    if not ShopConfig then return false, "Shop indisponible" end

    local data = DataService.GetData(player)
    if not data then return false, "Données non chargées" end

    local vehicleInfo = ShopConfig.Vehicles[vehicleId]
    if not vehicleInfo then
        return false, "Véhicule inconnu"
    end

    -- Vérifier si le joueur possède déjà ce véhicule
    if data.Inventory[vehicleId] then
        return false, "Tu possèdes déjà ce véhicule !"
    end

    -- Vérifier le cash
    if data.Cash < vehicleInfo.Price then
        return false, "Pas assez d'argent ! Il te faut $" .. vehicleInfo.Price
    end

    -- Transaction
    local success = DataService.RemoveCash(player, vehicleInfo.Price)
    if not success then
        return false, "Erreur lors du paiement"
    end

    -- Ajouter le véhicule à l'inventaire (1 = possédé, on pourra ajouter un état plus tard)
    data.Inventory[vehicleId] = 1

    cashUpdatedEvent:FireClient(player, data.Cash)

    print("[EconomyService] " .. player.Name .. " a acheté : "
          .. vehicleInfo.DisplayName .. " pour $" .. vehicleInfo.Price)

    return true, "Félicitations ! Tu as acheté : " .. vehicleInfo.DisplayName
end

-- ============================================================================
-- ACHAT D'OUTIL DE MÉTIER
-- Vérifie que le joueur a le bon métier et le bon niveau.
-- ============================================================================
function EconomyService.PurchaseTool(player: Player, toolId: string): (boolean, string)
    if not ShopConfig then return false, "Shop indisponible" end

    local data = DataService.GetData(player)
    if not data then return false, "Données non chargées" end

    local toolInfo = ShopConfig.Tools[toolId]
    if not toolInfo then
        return false, "Outil inconnu"
    end

    -- Vérifier si déjà possédé
    if data.Inventory[toolId] then
        return false, "Tu possèdes déjà cet outil !"
    end

    -- Vérifier le niveau de métier requis
    local jobLevel = DataService.GetJobLevel(player, toolInfo.RequiredJob)
    if jobLevel < toolInfo.RequiredLevel then
        local jobName = GameConfig.Jobs[toolInfo.RequiredJob].DisplayName
        return false, "Tu dois être " .. jobName .. " Nv." .. toolInfo.RequiredLevel .. " !"
    end

    -- Vérifier le cash
    if data.Cash < toolInfo.Price then
        return false, "Pas assez d'argent ! Il te faut $" .. toolInfo.Price
    end

    -- Transaction
    local success = DataService.RemoveCash(player, toolInfo.Price)
    if not success then
        return false, "Erreur lors du paiement"
    end

    data.Inventory[toolId] = 1

    cashUpdatedEvent:FireClient(player, data.Cash)

    print("[EconomyService] " .. player.Name .. " a acheté : "
          .. toolInfo.DisplayName .. " pour $" .. toolInfo.Price)

    return true, "Félicitations ! Tu as acheté : " .. toolInfo.DisplayName
end

-- ============================================================================
-- ACHAT DE CONSOMMABLE
-- Peut être acheté plusieurs fois (jusqu'au MaxStack).
-- ============================================================================
function EconomyService.PurchaseConsumable(player: Player, consumableId: string): (boolean, string)
    if not ShopConfig then return false, "Shop indisponible" end

    local data = DataService.GetData(player)
    if not data then return false, "Données non chargées" end

    local consumableInfo = ShopConfig.Consumables[consumableId]
    if not consumableInfo then
        return false, "Consommable inconnu"
    end

    -- Vérifier le stack max
    local currentAmount = data.Inventory[consumableId] or 0
    if currentAmount >= consumableInfo.MaxStack then
        return false, "Tu en as déjà le maximum (" .. consumableInfo.MaxStack .. ") !"
    end

    -- Vérifier le cash
    if data.Cash < consumableInfo.Price then
        return false, "Pas assez d'argent ! Il te faut $" .. consumableInfo.Price
    end

    -- Transaction
    local success = DataService.RemoveCash(player, consumableInfo.Price)
    if not success then
        return false, "Erreur lors du paiement"
    end

    data.Inventory[consumableId] = currentAmount + 1

    cashUpdatedEvent:FireClient(player, data.Cash)

    print("[EconomyService] " .. player.Name .. " a acheté : "
          .. consumableInfo.DisplayName .. " (x" .. data.Inventory[consumableId] .. ")")

    return true, consumableInfo.DisplayName .. " acheté ! (x" .. data.Inventory[consumableId] .. ")"
end

-- ============================================================================
-- UTILISER UN CONSOMMABLE
-- Retire 1 du stack quand le joueur utilise l'item.
-- ============================================================================
function EconomyService.UseConsumable(player: Player, consumableId: string): (boolean, string)
    local data = DataService.GetData(player)
    if not data then return false, "Données non chargées" end

    local currentAmount = data.Inventory[consumableId] or 0
    if currentAmount <= 0 then
        return false, "Tu n'as pas cet item !"
    end

    -- Retirer 1 du stack
    data.Inventory[consumableId] = currentAmount - 1

    -- Si le stack est vide, nettoyer l'entrée
    if data.Inventory[consumableId] <= 0 then
        data.Inventory[consumableId] = nil
    end

    print("[EconomyService] " .. player.Name .. " a utilisé : " .. consumableId
          .. " (reste : " .. (data.Inventory[consumableId] or 0) .. ")")

    return true, "Item utilisé !"
end

-- ============================================================================
-- FRAIS D'ENTRETIEN DES VÉHICULES (après chaque chaos)
-- Les véhicules endommagés coûtent de l'argent à réparer.
-- C'est un "money sink" pour éviter l'hyperinflation.
-- ============================================================================
function EconomyService.ApplyVehicleRepairCosts(player: Player)
    if not ShopConfig then return end

    local data = DataService.GetData(player)
    if not data then return end

    local totalRepairCost = 0

    -- Parcourir l'inventaire et trouver les véhicules
    for itemId, quantity in pairs(data.Inventory) do
        local vehicleInfo = ShopConfig.Vehicles[itemId]
        if vehicleInfo and vehicleInfo.RepairCost > 0 then
            totalRepairCost = totalRepairCost + vehicleInfo.RepairCost
        end
    end

    if totalRepairCost > 0 then
        -- Le joueur paie ce qu'il peut (s'il n'a pas assez, il paie tout ce qu'il a)
        local actualCost = math.min(totalRepairCost, data.Cash)

        if actualCost > 0 then
            DataService.RemoveCash(player, actualCost)
            cashUpdatedEvent:FireClient(player, data.Cash)

            print("[EconomyService] " .. player.Name
                  .. " a payé $" .. actualCost .. " en frais d'entretien véhicule")
        end
    end
end

-- ============================================================================
-- ROUTEUR D'ACHAT PRINCIPAL
-- Le client envoie { Category = "Housing", ItemId = "Villa" }
-- Cette fonction redirige vers la bonne fonction d'achat.
-- ============================================================================
function EconomyService.ProcessPurchase(player: Player, category: string, itemId: string): (boolean, string)
    -- Sanity checks anti-triche
    if type(category) ~= "string" or type(itemId) ~= "string" then
        return false, "Requête invalide"
    end

    if category == "Housing" then
        return EconomyService.PurchaseHousing(player, itemId)
    elseif category == "Vehicles" then
        return EconomyService.PurchaseVehicle(player, itemId)
    elseif category == "Tools" then
        return EconomyService.PurchaseTool(player, itemId)
    elseif category == "Consumables" then
        return EconomyService.PurchaseConsumable(player, itemId)
    else
        return false, "Catégorie inconnue : " .. category
    end
end

-- ============================================================================
-- ÉCOUTER LES DEMANDES D'ACHAT DES CLIENTS
-- ============================================================================
local function setupRemoteListeners()
    --[[
        Quand le client envoie RequestPurchase:FireServer(purchaseData),
        on reçoit ici la demande et on la traite.

        Format attendu de purchaseData :
        { Category = "Housing", ItemId = "Villa" }

        SÉCURITÉ : on ne fait JAMAIS confiance aux données du client.
        On vérifie tout : types, existence de l'item, cash suffisant, etc.
    ]]
    requestPurchaseEvent.OnServerEvent:Connect(function(player, purchaseData)
        -- Valider le format de la requête
        if type(purchaseData) ~= "table" then
            warn("[EconomyService] Requête invalide de " .. player.Name)
            return
        end

        local category = purchaseData.Category
        local itemId = purchaseData.ItemId

        if type(category) ~= "string" or type(itemId) ~= "string" then
            warn("[EconomyService] Données invalides de " .. player.Name)
            return
        end

        -- Anti-spam : max 1 achat par seconde
        local cooldownKey = "purchase_" .. player.UserId
        if EconomyService._purchaseCooldowns[cooldownKey] and
           tick() - EconomyService._purchaseCooldowns[cooldownKey] < 1 then
            return
        end
        EconomyService._purchaseCooldowns[cooldownKey] = tick()

        -- Traiter l'achat
        local success, message = EconomyService.ProcessPurchase(player, category, itemId)

        -- Envoyer le résultat au client
        -- On réutilise MissionCompleted temporairement pour les notifications
        -- TODO : Créer un RemoteEvent dédié "PurchaseResult"
        if success then
            print("[EconomyService] Achat réussi : " .. message)
        else
            print("[EconomyService] Achat refusé pour " .. player.Name .. " : " .. message)
        end
    end)
end

-- Table de cooldowns pour les achats
EconomyService._purchaseCooldowns = {}

-- ============================================================================
-- INITIALISATION
-- ============================================================================
function EconomyService.Init()
    DataService = require(ServerScriptService.Services.DataService)

    setupRemoteListeners()

    -- Nettoyer les cooldowns quand un joueur quitte
    Players.PlayerRemoving:Connect(function(player)
        EconomyService._purchaseCooldowns["purchase_" .. player.UserId] = nil
    end)

    print("[EconomyService] Initialisé avec succès !")
end

return EconomyService
