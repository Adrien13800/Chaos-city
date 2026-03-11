--[[
    GameConfig.lua
    Emplacement : ReplicatedStorage/Modules/GameConfig

    POURQUOI ICI ? Ce module est dans ReplicatedStorage car le serveur ET le client
    ont besoin d'accéder aux mêmes constantes. Par exemple, le client a besoin de
    connaître les durées des phases pour afficher le timer, et le serveur a besoin
    des mêmes valeurs pour gérer la logique du cycle.

    SÉCURITÉ : Ce fichier ne contient QUE des constantes. Aucune logique de jeu.
    Même si un hacker lit ces valeurs, il ne peut rien en faire car toute la
    logique est côté serveur.
]]

local GameConfig = {}

-- ============================================================================
-- PHASES DU CYCLE
-- ============================================================================
GameConfig.Phases = {
    Calm = {
        MinDuration = 600,   -- 10 minutes en secondes
        MaxDuration = 840,   -- 14 minutes en secondes
    },
    Alert = {
        Duration = 120,      -- 2 minutes
    },
    Chaos = {
        MinDuration = 180,   -- 3 minutes
        MaxDuration = 300,   -- 5 minutes
    },
    Result = {
        Duration = 60,       -- 1 minute
    },
}

-- ============================================================================
-- MÉTIERS
-- ============================================================================
GameConfig.Jobs = {
    Firefighter = {
        DisplayName = "Pompier",
        MaxLevel = 10,
        BasePayPerMission = 150,     -- $ par mission en phase calme
        ChaosMultiplierBase = 5,     -- Multiplicateur de base pendant le chaos
        ChaosMultiplierHeroic = 10,  -- Multiplicateur pour les actions héroïques
        Color = Color3.fromRGB(255, 69, 0),  -- Orange-rouge pour l'UI
    },
    Medic = {
        DisplayName = "Médecin",
        MaxLevel = 10,
        BasePayPerMission = 140,
        ChaosMultiplierBase = 5,
        ChaosMultiplierHeroic = 10,
        Color = Color3.fromRGB(0, 200, 83),
    },
    Delivery = {
        DisplayName = "Livreur",
        MaxLevel = 10,
        BasePayPerMission = 130,
        ChaosMultiplierBase = 4,
        ChaosMultiplierHeroic = 8,
        Color = Color3.fromRGB(255, 193, 7),
    },
    Engineer = {
        DisplayName = "Ingénieur",
        MaxLevel = 10,
        BasePayPerMission = 140,
        ChaosMultiplierBase = 4,
        ChaosMultiplierHeroic = 8,
        Color = Color3.fromRGB(33, 150, 243),
    },
    Police = {
        DisplayName = "Policier",
        MaxLevel = 10,
        BasePayPerMission = 135,
        ChaosMultiplierBase = 4,
        ChaosMultiplierHeroic = 8,
        Color = Color3.fromRGB(63, 81, 181),
    },
    Civilian = {
        DisplayName = "Civil",
        MaxLevel = 10,
        BasePayPerMission = 100,     -- -30% par rapport aux métiers spécialisés
        ChaosMultiplierBase = 3,
        ChaosMultiplierHeroic = 5,
        Color = Color3.fromRGB(158, 158, 158),
    },
    Bandit = {
        DisplayName = "Bandit",
        MaxLevel = 10,
        BasePayPerMission = 90,      -- Paye faible en phase calme (risqué, discret)
        ChaosMultiplierBase = 6,     -- x6 en chaos (le plus haut après Pompier/Médecin)
        ChaosMultiplierHeroic = 12,  -- x12 pour les pillages héroïques — HIGH RISK HIGH REWARD
        Color = Color3.fromRGB(120, 20, 160),  -- Violet sombre
    },
}

-- ============================================================================
-- XP DE MÉTIER
-- XP nécessaire pour passer au niveau suivant
-- ============================================================================
GameConfig.JobXPRequirements = {
    [1] = 0,       -- Niveau 1 = départ
    [2] = 500,
    [3] = 1200,
    [4] = 2500,
    [5] = 5000,
    [6] = 8000,
    [7] = 12000,
    [8] = 18000,
    [9] = 25000,
    [10] = 35000,
}

-- ============================================================================
-- ÉCONOMIE
-- ============================================================================
GameConfig.Economy = {
    -- Récompenses de classement Héros du Chaos
    HeroRewards = {
        [1] = { Cash = 1000, Stars = 5 },   -- #1
        [2] = { Cash = 500,  Stars = 2 },    -- #2
        [3] = { Cash = 500,  Stars = 2 },    -- #3
        [4] = { Cash = 500,  Stars = 2 },    -- #4
        [5] = { Cash = 500,  Stars = 2 },    -- #5
    },
    ParticipationReward = { Cash = 200, Stars = 1 },

    -- Coût de base des items
    Prices = {
        SmallApartment = 5000,
        MediumHouse = 25000,
        Villa = 100000,
        BasicVehicle = 2000,
        PremiumVehicle = 30000,
        SurvivalKit = 500,
    },
}

-- ============================================================================
-- CATASTROPHES
-- ============================================================================
GameConfig.Disasters = {
    Earthquake = {
        DisplayName = "Séisme",
        SkyColor = Color3.fromRGB(180, 60, 60),      -- Rouge
        BuildingDestructionPercent = 0.4,              -- 40% des petits bâtiments
        Weight = 1,  -- Poids pour la sélection aléatoire (tous égaux = équiprobable)
    },
    Flood = {
        DisplayName = "Inondation",
        SkyColor = Color3.fromRGB(20, 60, 120),       -- Bleu foncé
        BuildingDestructionPercent = 0.2,
        Weight = 1,
    },
    Meteors = {
        DisplayName = "Pluie de Météorites",
        SkyColor = Color3.fromRGB(200, 100, 0),       -- Orange
        BuildingDestructionPercent = 0.3,
        Weight = 1,
    },
    AlienInvasion = {
        DisplayName = "Invasion Alien",
        SkyColor = Color3.fromRGB(0, 180, 60),        -- Vert
        BuildingDestructionPercent = 0.0,              -- Pas de destruction, mais "infection"
        Weight = 1,
    },
    Tornado = {
        DisplayName = "Tornade",
        SkyColor = Color3.fromRGB(80, 80, 80),        -- Gris sombre
        BuildingDestructionPercent = 0.25,
        Weight = 1,
    },
    Blackout = {
        DisplayName = "Panne Générale",
        SkyColor = Color3.fromRGB(10, 10, 20),        -- Quasi-noir
        BuildingDestructionPercent = 0.0,
        Weight = 1,
    },
}

-- ============================================================================
-- COMBO SYSTEM
-- ============================================================================
GameConfig.Combo = {
    -- Seuil de survie pour déclencher l'escalade
    SurvivalThreshold = 0.7,  -- 70% des joueurs doivent être actifs

    -- Bonus d'intensité par chaos consécutif
    IntensityScale = {
        [1] = 1.0,    -- 1er chaos : normal
        [2] = 1.2,    -- 2e chaos : +20%
        [3] = 1.5,    -- 3e chaos : +50%, combo possible
        [4] = 2.0,    -- 4e+ : combo garanti, multiplicateur base x7
    },

    -- À partir de quel chaos les combos (2 catastrophes) sont possibles
    ComboStartsAt = 3,
    ComboGuaranteedAt = 4,

    -- Multiplicateur de base amélioré pendant les combos
    ComboBaseMultiplier = 7,
}

-- ============================================================================
-- SERVEUR
-- ============================================================================
GameConfig.Server = {
    MaxPlayers = 30,
    AutoSaveInterval = 300,  -- Sauvegarde auto toutes les 5 minutes (en secondes)
}

return GameConfig
