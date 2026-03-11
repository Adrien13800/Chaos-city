--[[
    MissionsConfig.lua
    Emplacement : ReplicatedStorage/Config/MissionsConfig

    Définit toutes les missions disponibles pour chaque métier.
    Séparé de GameConfig pour garder les fichiers lisibles.

    CHAQUE MISSION A :
    - Id : identifiant unique
    - Description : texte affiché au joueur
    - Duration : temps max pour compléter la mission (en secondes)
    - BaseReward : cash gagné en phase Calme
    - XPReward : XP de métier gagné
    - ChaosScoreReward : points "Héros du Chaos" gagnés (uniquement pendant la phase Chaos)
    - MinLevel : niveau minimum du métier requis pour recevoir cette mission
    - Type : "calm" (phase calme uniquement), "chaos" (chaos uniquement), "both" (les deux)

    POURQUOI ICI (ReplicatedStorage/Config) ?
    Le client a besoin de ces données pour afficher les descriptions de missions.
    Le serveur en a besoin pour la logique. Aucune donnée sensible ici.
]]

local MissionsConfig = {}

-- ============================================================================
-- MISSIONS POMPIER (Firefighter)
-- Phase calme : petits feux, inspections
-- Phase chaos : incendies massifs, sauvetages héroïques
-- ============================================================================
MissionsConfig.Firefighter = {
    Calm = {
        {
            Id = "FF_INSPECT",
            Description = "Inspecter un bâtiment pour vérifier la sécurité incendie",
            Duration = 30,
            BaseReward = 100,
            XPReward = 30,
            MinLevel = 1,
        },
        {
            Id = "FF_SMALL_FIRE",
            Description = "Éteindre un petit feu dans un bâtiment",
            Duration = 45,
            BaseReward = 150,
            XPReward = 50,
            MinLevel = 1,
        },
        {
            Id = "FF_RESCUE_CAT",
            Description = "Sauver un chat coincé sur un toit",
            Duration = 40,
            BaseReward = 120,
            XPReward = 40,
            MinLevel = 2,
        },
        {
            Id = "FF_HYDRANT_CHECK",
            Description = "Vérifier les bouches d'incendie du quartier",
            Duration = 60,
            BaseReward = 180,
            XPReward = 60,
            MinLevel = 3,
        },
    },
    Chaos = {
        {
            Id = "FF_MASSIVE_FIRE",
            Description = "Éteindre un incendie majeur !",
            Duration = 60,
            BaseReward = 200,
            XPReward = 100,
            ChaosScoreReward = 100,
            MinLevel = 1,
        },
        {
            Id = "FF_RESCUE_NPC",
            Description = "Sauver un PNJ piégé sous les décombres !",
            Duration = 45,
            BaseReward = 250,
            XPReward = 120,
            ChaosScoreReward = 150,
            MinLevel = 2,
        },
        {
            Id = "FF_RESCUE_PLAYER",
            Description = "Escorter un joueur blessé vers un abri !",
            Duration = 50,
            BaseReward = 300,
            XPReward = 150,
            ChaosScoreReward = 200,
            MinLevel = 5,
        },
    },
}

-- ============================================================================
-- MISSIONS MÉDECIN (Medic)
-- Phase calme : soins de routine
-- Phase chaos : réanimation, hôpitaux de campagne
-- ============================================================================
MissionsConfig.Medic = {
    Calm = {
        {
            Id = "MD_HEAL_NPC",
            Description = "Soigner un PNJ malade à la clinique",
            Duration = 30,
            BaseReward = 100,
            XPReward = 30,
            MinLevel = 1,
        },
        {
            Id = "MD_DELIVER_MEDS",
            Description = "Livrer des médicaments à un patient",
            Duration = 50,
            BaseReward = 140,
            XPReward = 45,
            MinLevel = 1,
        },
        {
            Id = "MD_CHECKUP",
            Description = "Faire un bilan de santé à un PNJ",
            Duration = 35,
            BaseReward = 120,
            XPReward = 35,
            MinLevel = 2,
        },
        {
            Id = "MD_AMBULANCE",
            Description = "Conduire l'ambulance vers un patient urgent",
            Duration = 60,
            BaseReward = 200,
            XPReward = 70,
            MinLevel = 4,
        },
    },
    Chaos = {
        {
            Id = "MD_REVIVE_PLAYER",
            Description = "Réanimer un joueur KO !",
            Duration = 15,
            BaseReward = 300,
            XPReward = 130,
            ChaosScoreReward = 200,
            MinLevel = 1,
        },
        {
            Id = "MD_FIELD_HOSPITAL",
            Description = "Installer un hôpital de campagne !",
            Duration = 45,
            BaseReward = 250,
            XPReward = 100,
            ChaosScoreReward = 150,
            MinLevel = 3,
        },
        {
            Id = "MD_MASS_HEAL",
            Description = "Soigner tous les blessés dans une zone !",
            Duration = 60,
            BaseReward = 350,
            XPReward = 160,
            ChaosScoreReward = 250,
            MinLevel = 7,
        },
    },
}

-- ============================================================================
-- MISSIONS LIVREUR (Delivery)
-- Phase calme : livraisons classiques
-- Phase chaos : livraisons sous le danger = high risk, high reward
-- ============================================================================
MissionsConfig.Delivery = {
    Calm = {
        {
            Id = "DL_PACKAGE",
            Description = "Livrer un colis au point de dépôt",
            Duration = 45,
            BaseReward = 130,
            XPReward = 35,
            MinLevel = 1,
        },
        {
            Id = "DL_FOOD",
            Description = "Livrer une commande de nourriture",
            Duration = 40,
            BaseReward = 120,
            XPReward = 30,
            MinLevel = 1,
        },
        {
            Id = "DL_EXPRESS",
            Description = "Livraison express ! Dépêche-toi !",
            Duration = 25,
            BaseReward = 180,
            XPReward = 55,
            MinLevel = 3,
        },
        {
            Id = "DL_BULK",
            Description = "Livrer un gros chargement en camion",
            Duration = 70,
            BaseReward = 220,
            XPReward = 65,
            MinLevel = 5,
        },
    },
    Chaos = {
        {
            Id = "DL_EMERGENCY_SUPPLY",
            Description = "Livrer des supplies d'urgence à un abri !",
            Duration = 50,
            BaseReward = 250,
            XPReward = 110,
            ChaosScoreReward = 120,
            MinLevel = 1,
        },
        {
            Id = "DL_DANGER_DELIVERY",
            Description = "Livrer à travers une zone de catastrophe !",
            Duration = 40,
            BaseReward = 300,
            XPReward = 130,
            ChaosScoreReward = 180,
            MinLevel = 3,
        },
        {
            Id = "DL_HERO_RUN",
            Description = "Traverser la ville entière sous le chaos !",
            Duration = 60,
            BaseReward = 400,
            XPReward = 170,
            ChaosScoreReward = 250,
            MinLevel = 7,
        },
    },
}

-- ============================================================================
-- MISSIONS INGÉNIEUR (Engineer)
-- Phase calme : maintenance de la ville
-- Phase chaos : réparations critiques pour accélérer la reconstruction
-- ============================================================================
MissionsConfig.Engineer = {
    Calm = {
        {
            Id = "EN_FIX_LAMP",
            Description = "Réparer un lampadaire en panne",
            Duration = 30,
            BaseReward = 110,
            XPReward = 30,
            MinLevel = 1,
        },
        {
            Id = "EN_WIRING",
            Description = "Refaire le câblage d'un bâtiment",
            Duration = 50,
            BaseReward = 160,
            XPReward = 50,
            MinLevel = 2,
        },
        {
            Id = "EN_GENERATOR",
            Description = "Entretenir un générateur de la ville",
            Duration = 45,
            BaseReward = 150,
            XPReward = 45,
            MinLevel = 3,
        },
        {
            Id = "EN_UPGRADE",
            Description = "Améliorer un système électrique du quartier",
            Duration = 70,
            BaseReward = 220,
            XPReward = 70,
            MinLevel = 5,
        },
    },
    Chaos = {
        {
            Id = "EN_FIX_ROAD",
            Description = "Réparer une route effondrée !",
            Duration = 45,
            BaseReward = 250,
            XPReward = 110,
            ChaosScoreReward = 130,
            MinLevel = 1,
        },
        {
            Id = "EN_RESTORE_POWER",
            Description = "Rétablir l'électricité dans un quartier !",
            Duration = 50,
            BaseReward = 280,
            XPReward = 120,
            ChaosScoreReward = 160,
            MinLevel = 3,
        },
        {
            Id = "EN_FIX_BRIDGE",
            Description = "Réparer un pont critique pour les évacuations !",
            Duration = 60,
            BaseReward = 350,
            XPReward = 160,
            ChaosScoreReward = 220,
            MinLevel = 6,
        },
    },
}

-- ============================================================================
-- MISSIONS POLICIER (Police)
-- Phase calme : patrouilles, escortes
-- Phase chaos : évacuation, maintien de l'ordre
-- ============================================================================
MissionsConfig.Police = {
    Calm = {
        {
            Id = "PL_PATROL",
            Description = "Patrouiller dans un quartier de la ville",
            Duration = 45,
            BaseReward = 120,
            XPReward = 35,
            MinLevel = 1,
        },
        {
            Id = "PL_ESCORT_NPC",
            Description = "Escorter un PNJ jusqu'à sa destination",
            Duration = 50,
            BaseReward = 135,
            XPReward = 40,
            MinLevel = 1,
        },
        {
            Id = "PL_TRAFFIC",
            Description = "Diriger la circulation à un carrefour",
            Duration = 40,
            BaseReward = 110,
            XPReward = 30,
            MinLevel = 2,
        },
        {
            Id = "PL_INVESTIGATE",
            Description = "Enquêter sur un incident signalé",
            Duration = 60,
            BaseReward = 190,
            XPReward = 60,
            MinLevel = 4,
        },
    },
    Chaos = {
        {
            Id = "PL_EVACUATE",
            Description = "Escorter des civils vers un abri !",
            Duration = 50,
            BaseReward = 250,
            XPReward = 100,
            ChaosScoreReward = 140,
            MinLevel = 1,
        },
        {
            Id = "PL_SECURE_ZONE",
            Description = "Sécuriser une zone dangereuse !",
            Duration = 45,
            BaseReward = 280,
            XPReward = 120,
            ChaosScoreReward = 170,
            MinLevel = 3,
        },
        {
            Id = "PL_RESCUE_OP",
            Description = "Coordonner une opération de sauvetage massive !",
            Duration = 60,
            BaseReward = 350,
            XPReward = 160,
            ChaosScoreReward = 230,
            MinLevel = 6,
        },
    },
}

-- ============================================================================
-- MISSIONS CIVIL (Civilian)
-- Missions moins payées (-30%) mais accessibles à tous
-- Phase chaos : aide générale
-- ============================================================================
MissionsConfig.Civilian = {
    Calm = {
        {
            Id = "CV_HELP_SHOP",
            Description = "Aider un commerçant à ranger sa boutique",
            Duration = 30,
            BaseReward = 70,
            XPReward = 20,
            MinLevel = 1,
        },
        {
            Id = "CV_CLEAN_STREET",
            Description = "Nettoyer les rues du quartier",
            Duration = 40,
            BaseReward = 80,
            XPReward = 25,
            MinLevel = 1,
        },
        {
            Id = "CV_CARRY_BOXES",
            Description = "Transporter des cartons pour un déménagement",
            Duration = 45,
            BaseReward = 90,
            XPReward = 30,
            MinLevel = 2,
        },
    },
    Chaos = {
        {
            Id = "CV_HELP_ANYONE",
            Description = "Aider les secours autour de toi !",
            Duration = 40,
            BaseReward = 150,
            XPReward = 60,
            ChaosScoreReward = 80,
            MinLevel = 1,
        },
        {
            Id = "CV_COLLECT_SUPPLIES",
            Description = "Ramasser des provisions dans les décombres !",
            Duration = 50,
            BaseReward = 180,
            XPReward = 75,
            ChaosScoreReward = 100,
            MinLevel = 3,
        },
    },
}

-- ============================================================================
-- MISSIONS BANDIT (Bandit)
-- Le métier "vilain" — paye faible en calme, paye MASSIVE en chaos
-- Phase calme : petits larcins discrets, pickpocket
-- Phase chaos : pillage, vol de supplies, profiter du désordre
--
-- DESIGN : le Bandit est l'opposé du Policier.
-- Ses missions chaos ne donnent PAS de ChaosScore "Héros"
-- (sauver les gens ≠ piller), mais il gagne un ChaosScore "Infâme"
-- qui compte quand même pour le classement (les vilains aussi peuvent
-- être #1 — "Pilleur le plus efficace du chaos").
-- Ça crée un dilemme social : le Héros #1 est-il un sauveur ou un pilleur ?
-- ============================================================================
MissionsConfig.Bandit = {
    Calm = {
        {
            Id = "BD_PICKPOCKET",
            Description = "Faire les poches d'un PNJ distrait",
            Duration = 20,
            BaseReward = 80,
            XPReward = 25,
            MinLevel = 1,
        },
        {
            Id = "BD_SHOPLIFTING",
            Description = "Voler discrètement dans une boutique",
            Duration = 35,
            BaseReward = 110,
            XPReward = 35,
            MinLevel = 1,
        },
        {
            Id = "BD_SCAM_NPC",
            Description = "Arnaquer un PNJ avec un faux produit",
            Duration = 40,
            BaseReward = 130,
            XPReward = 45,
            MinLevel = 2,
        },
        {
            Id = "BD_BREAK_IN",
            Description = "Cambrioler une maison vide",
            Duration = 55,
            BaseReward = 200,
            XPReward = 65,
            MinLevel = 4,
        },
        {
            Id = "BD_HEIST_PREP",
            Description = "Préparer un gros coup pour le prochain chaos",
            Duration = 60,
            BaseReward = 160,
            XPReward = 70,
            MinLevel = 6,
        },
    },
    Chaos = {
        {
            Id = "BD_LOOT_BUILDING",
            Description = "Piller un bâtiment endommagé !",
            Duration = 35,
            BaseReward = 300,
            XPReward = 110,
            ChaosScoreReward = 120,
            MinLevel = 1,
        },
        {
            Id = "BD_STEAL_SUPPLIES",
            Description = "Voler les caisses de ravitaillement d'urgence !",
            Duration = 40,
            BaseReward = 400,
            XPReward = 140,
            ChaosScoreReward = 180,
            MinLevel = 3,
        },
        {
            Id = "BD_SAFE_CRACK",
            Description = "Forcer le coffre-fort d'une banque fissurée par le chaos !",
            Duration = 50,
            BaseReward = 600,
            XPReward = 180,
            ChaosScoreReward = 250,
            MinLevel = 5,
        },
        {
            Id = "BD_MASTER_HEIST",
            Description = "LE GROS COUP — Piller le convoi d'évacuation !",
            Duration = 60,
            BaseReward = 800,
            XPReward = 220,
            ChaosScoreReward = 350,
            MinLevel = 8,
        },
    },
}

return MissionsConfig
