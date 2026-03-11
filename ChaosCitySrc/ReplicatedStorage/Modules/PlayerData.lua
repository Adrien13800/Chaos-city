--[[
    PlayerData.lua
    Emplacement : ReplicatedStorage/Modules/PlayerData

    Ce module définit le TEMPLATE (modèle) des données d'un joueur.
    C'est la "structure" de ce qu'on sauvegarde dans le DataStore.

    POURQUOI ICI ? Le serveur utilise ce template pour créer les données d'un
    nouveau joueur, et le client pourrait en avoir besoin pour connaître les
    valeurs par défaut (affichage UI). Aucune logique sensible ici.

    CONCEPT CLÉ — "Deep Copy" :
    En Lua/Luau, les tables sont passées par RÉFÉRENCE (comme les objets en JS).
    Si on faisait `local data = PlayerData.Template`, tous les joueurs partageraient
    la MÊME table en mémoire. On utilise donc une fonction DeepCopy pour créer
    une copie indépendante pour chaque joueur.
]]

local PlayerData = {}

-- ============================================================================
-- TEMPLATE DE DONNÉES JOUEUR
-- Structure complète de ce qui est sauvegardé par joueur
-- ============================================================================
PlayerData.Template = {
    -- Économie
    Cash = 1000,          -- Argent de départ (permet d'acheter un premier outil)
    ChaosStars = 0,       -- Étoiles de Chaos (monnaie de prestige)

    -- Métier actuel
    CurrentJob = "Civilian",  -- Le métier actif en ce moment

    -- Niveaux de métier (chaque métier a son propre niveau et XP)
    -- On stocke TOUS les métiers même si le joueur n'en a utilisé qu'un seul
    -- → permet de changer de métier sans perdre sa progression
    JobLevels = {
        Firefighter = { Level = 1, XP = 0 },
        Medic       = { Level = 1, XP = 0 },
        Delivery    = { Level = 1, XP = 0 },
        Engineer    = { Level = 1, XP = 0 },
        Police      = { Level = 1, XP = 0 },
        Civilian    = { Level = 1, XP = 0 },
        Bandit      = { Level = 1, XP = 0 },
    },

    -- Statistiques globales (pour le profil / achievements futurs)
    Stats = {
        TotalChaoseSurvived = 0,    -- Nombre total de chaos survécus
        TotalHeroTitles = 0,        -- Nombre de fois #1 au classement
        TotalMissionsCompleted = 0, -- Missions de métier complétées
        TotalCashEarned = 0,        -- Cash total gagné (lifetime)
        BestComboSurvived = 0,      -- Plus long enchaînement de chaos survécus
    },

    -- Inventaire (outils et consommables possédés)
    Inventory = {
        -- Format : { ItemId = quantité }
        -- Exemple : { SurvivalKit = 2, Flashlight = 1 }
    },

    -- Propriétés immobilières
    Housing = {
        OwnedType = "None",   -- "None", "SmallApartment", "MediumHouse", "Villa"
        Furniture = {},        -- Liste des meubles placés (pour une future implémentation)
    },

    -- Métadonnées
    JoinDate = 0,          -- Timestamp de la première connexion (os.time())
    LastSave = 0,          -- Timestamp de la dernière sauvegarde
    DataVersion = 1,       -- Version du schéma (pour les migrations futures)
}

-- ============================================================================
-- DEEP COPY
-- Crée une copie complète et indépendante d'une table (récursif)
-- ============================================================================
function PlayerData.DeepCopy(original)
    -- Si ce n'est pas une table, retourne directement la valeur
    -- (les nombres, strings, booleans sont déjà copiés par valeur en Lua)
    if type(original) ~= "table" then
        return original
    end

    local copy = {}
    for key, value in pairs(original) do
        -- Appel récursif : si une valeur est elle-même une table,
        -- on la copie aussi en profondeur
        copy[key] = PlayerData.DeepCopy(value)
    end

    return copy
end

-- ============================================================================
-- CRÉER DE NOUVELLES DONNÉES JOUEUR
-- Retourne une copie fraîche du template pour un nouveau joueur
-- ============================================================================
function PlayerData.CreateNew()
    local data = PlayerData.DeepCopy(PlayerData.Template)
    data.JoinDate = os.time()  -- Enregistre le moment de la première connexion
    data.LastSave = os.time()
    return data
end

return PlayerData
