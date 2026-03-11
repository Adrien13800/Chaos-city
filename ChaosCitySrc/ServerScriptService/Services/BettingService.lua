--[[
    BettingService.lua
    Emplacement : ServerScriptService/Services/BettingService

    SYSTÈME DE PARIS — Le Bookmaker.

    COMMENT ÇA MARCHE :
    1. Pendant la phase Calme, les joueurs peuvent parier sur la prochaine catastrophe
    2. Ils choisissent un type de catastrophe + un montant
    3. Quand la phase Alerte révèle la catastrophe, les paris sont "verrouillés"
    4. Après le chaos (phase Résultat), les gagnants reçoivent leurs gains

    COTES (ODDS) :
    Comme il y a 6 catastrophes équiprobables, la cote juste serait x6.
    On met x5 pour que la maison (le jeu) ait un léger avantage → money sink.

    SÉCURITÉ :
    - Mise minimum : $100 (éviter le spam)
    - Mise maximum : $5000 (éviter qu'un joueur devienne milliardaire d'un coup)
    - Un seul pari actif par joueur à la fois
    - L'argent est retiré au moment du pari (pas quand on perd)
    - Les paris sont fermés pendant l'Alerte et le Chaos

    ZONE DU BOOKMAKER :
    Comme les zones de métier, on place une Part dans le Workspace
    avec un attribut "Bookmaker" = true. Quand un joueur la touche,
    il peut ouvrir l'interface de paris.
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
local PhaseService = nil

-- ============================================================================
-- REMOTE EVENTS
-- ============================================================================
local remoteEvents = ReplicatedStorage.Events.RemoteEvents
local placeBetEvent = remoteEvents.PlaceBet
local cashUpdatedEvent = remoteEvents.CashUpdated

-- ============================================================================
-- ÉTAT
-- ============================================================================
local BettingService = {}

-- Paris actifs
-- Format : { [Player.UserId] = { DisasterType = "Earthquake", Amount = 500 } }
local activeBets = {}

-- Est-ce que les paris sont ouverts ?
local betsOpen = false

-- Constantes
local MIN_BET = 100
local MAX_BET = 5000
local PAYOUT_MULTIPLIER = 5  -- Cote x5 (sur 6 catastrophes possibles)

-- ============================================================================
-- PLACER UN PARI
-- ============================================================================

function BettingService.PlaceBet(player: Player, disasterType: string, amount: number): (boolean, string)
    -- Vérifier que les paris sont ouverts
    if not betsOpen then
        return false, "Les paris sont fermés !"
    end

    -- Vérifier que le joueur n'a pas déjà un pari
    if activeBets[player.UserId] then
        return false, "Tu as déjà un pari en cours !"
    end

    -- Valider le type de catastrophe
    if type(disasterType) ~= "string" or not GameConfig.Disasters[disasterType] then
        return false, "Catastrophe inconnue !"
    end

    -- Valider le montant
    if type(amount) ~= "number" then
        return false, "Montant invalide !"
    end

    amount = math.floor(amount)

    if amount < MIN_BET then
        return false, "Mise minimum : $" .. MIN_BET
    end

    if amount > MAX_BET then
        return false, "Mise maximum : $" .. MAX_BET
    end

    -- Vérifier que le joueur a assez d'argent
    local data = DataService.GetData(player)
    if not data or data.Cash < amount then
        return false, "Pas assez d'argent !"
    end

    -- Retirer l'argent immédiatement (l'argent est "misé")
    local success = DataService.RemoveCash(player, amount)
    if not success then
        return false, "Erreur de paiement"
    end

    -- Enregistrer le pari
    activeBets[player.UserId] = {
        DisasterType = disasterType,
        Amount = amount,
        PlayerName = player.Name,
    }

    -- Mettre à jour le HUD du joueur
    cashUpdatedEvent:FireClient(player, DataService.GetCash(player))

    local disasterName = GameConfig.Disasters[disasterType].DisplayName
    print("[BettingService] " .. player.Name .. " parie $" .. amount
          .. " sur : " .. disasterName)

    return true, "Pari placé : $" .. amount .. " sur " .. disasterName .. " (cote x" .. PAYOUT_MULTIPLIER .. ")"
end

-- ============================================================================
-- RÉSOUDRE LES PARIS (après le chaos)
-- ============================================================================

function BettingService.ResolveBets(actualDisaster: string)
    if not actualDisaster then return end

    local actualName = GameConfig.Disasters[actualDisaster] and
                       GameConfig.Disasters[actualDisaster].DisplayName or actualDisaster

    print("[BettingService] ═══ Résolution des paris ═══")
    print("[BettingService] Catastrophe réelle : " .. actualName)

    local winnersCount = 0
    local losersCount = 0

    for userId, bet in pairs(activeBets) do
        local player = Players:GetPlayerByUserId(userId)

        if player and player.Parent then
            if bet.DisasterType == actualDisaster then
                -- GAGNANT ! Paye = mise x PAYOUT_MULTIPLIER
                local winnings = bet.Amount * PAYOUT_MULTIPLIER
                DataService.AddCash(player, winnings)
                cashUpdatedEvent:FireClient(player, DataService.GetCash(player))

                winnersCount = winnersCount + 1
                print("[BettingService]   GAGNANT : " .. bet.PlayerName
                      .. " gagne $" .. winnings .. " !")
            else
                -- PERDANT — l'argent a déjà été retiré au moment du pari
                losersCount = losersCount
                local betName = GameConfig.Disasters[bet.DisasterType] and
                                GameConfig.Disasters[bet.DisasterType].DisplayName or bet.DisasterType
                losersCount = losersCount + 1
                print("[BettingService]   Perdu : " .. bet.PlayerName
                      .. " avait parié sur " .. betName)
            end
        end
    end

    print("[BettingService] " .. winnersCount .. " gagnant(s), "
          .. losersCount .. " perdant(s)")
    print("[BettingService] ═══════════════════════════")

    -- Réinitialiser tous les paris
    activeBets = {}
end

-- ============================================================================
-- GESTION DU CYCLE (ouvrir/fermer les paris)
-- ============================================================================

function BettingService._StartPhaseWatcher()
    task.spawn(function()
        local lastPhase = ""

        while true do
            task.wait(1)

            PhaseService = PhaseService or require(ServerScriptService.Services.PhaseService)
            local currentPhase = PhaseService.GetCurrentPhase()

            if currentPhase ~= lastPhase then
                if currentPhase == "Calm" then
                    -- Phase Calme → ouvrir les paris
                    betsOpen = true
                    print("[BettingService] Les paris sont OUVERTS !")

                elseif currentPhase == "Alert" then
                    -- Phase Alerte → fermer les paris (plus de nouveaux paris)
                    betsOpen = false
                    local betCount = 0
                    for _ in pairs(activeBets) do betCount = betCount + 1 end
                    print("[BettingService] Les paris sont FERMÉS ! ("
                          .. betCount .. " pari(s) en jeu)")

                elseif currentPhase == "Result" then
                    -- Phase Résultat → résoudre les paris
                    local disaster = PhaseService.GetCurrentDisaster()
                    if disaster then
                        BettingService.ResolveBets(disaster)
                    end
                end

                lastPhase = currentPhase
            end
        end
    end)
end

-- ============================================================================
-- ÉCOUTER LES DEMANDES DE PARIS DES CLIENTS
-- ============================================================================

local function setupRemoteListeners()
    placeBetEvent.OnServerEvent:Connect(function(player, betData)
        -- Valider le format
        if type(betData) ~= "table" then
            return
        end

        local disasterType = betData.DisasterType
        local amount = betData.Amount

        if type(disasterType) ~= "string" or type(amount) ~= "number" then
            return
        end

        local success, message = BettingService.PlaceBet(player, disasterType, amount)

        -- Pour l'instant on log le résultat
        -- TODO : envoyer le message au client via un RemoteEvent dédié
        if not success then
            print("[BettingService] Refusé pour " .. player.Name .. " : " .. message)
        end
    end)
end

-- ============================================================================
-- API PUBLIQUE
-- ============================================================================

-- Vérifier si les paris sont ouverts
function BettingService.AreBetsOpen(): boolean
    return betsOpen
end

-- Obtenir le pari actif d'un joueur
function BettingService.GetPlayerBet(player: Player)
    return activeBets[player.UserId]
end

-- ============================================================================
-- INITIALISATION
-- ============================================================================
function BettingService.Init()
    DataService = require(ServerScriptService.Services.DataService)
    PhaseService = require(ServerScriptService.Services.PhaseService)

    setupRemoteListeners()

    -- Nettoyer quand un joueur quitte (rembourser le pari)
    Players.PlayerRemoving:Connect(function(player)
        local bet = activeBets[player.UserId]
        if bet then
            -- Rembourser le joueur qui quitte (pour ne pas perdre injustement)
            DataService.AddCash(player, bet.Amount)
            activeBets[player.UserId] = nil
            print("[BettingService] Pari remboursé pour " .. player.Name .. " (déconnexion)")
        end
    end)

    BettingService._StartPhaseWatcher()

    print("[BettingService] Initialisé avec succès !")
end

return BettingService
