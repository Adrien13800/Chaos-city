--[[
    ShopConfig.lua
    Emplacement : ReplicatedStorage/Config/ShopConfig

    Définit tous les items achetables dans le jeu.
    Séparé de GameConfig pour garder les fichiers lisibles.

    CATÉGORIES D'ITEMS :
    - Housing : maisons/appartements (un seul à la fois, upgrade possible)
    - Vehicles : véhicules (un seul actif à la fois)
    - Tools : outils de métier (améliorations permanentes)
    - Consumables : consommables (kits de survie, lampes — s'utilisent et disparaissent)

    POURQUOI ICI ?
    Le client a besoin de ces données pour afficher les prix dans le shop UI.
    Le serveur en a besoin pour vérifier les achats. Aucune logique sensible.
]]

local ShopConfig = {}

-- ============================================================================
-- LOGEMENTS
-- Un joueur ne peut posséder QU'UN SEUL logement.
-- Acheter un meilleur logement = upgrade (pas besoin de vendre l'ancien).
-- ============================================================================
ShopConfig.Housing = {
    SmallApartment = {
        DisplayName = "Petit Appartement",
        Description = "Un studio modeste mais confortable.",
        Price = 5000,
        Order = 1,  -- Ordre d'affichage dans le shop
    },
    MediumHouse = {
        DisplayName = "Maison Moyenne",
        Description = "Une maison avec jardin. De quoi recevoir des amis !",
        Price = 25000,
        Order = 2,
    },
    Villa = {
        DisplayName = "Villa de Luxe",
        Description = "La plus belle propriété de la ville. Piscine incluse.",
        Price = 100000,
        Order = 3,
    },
}

-- ============================================================================
-- VÉHICULES
-- Un joueur peut posséder plusieurs véhicules.
-- Les véhicules ont un coût d'entretien quand ils sont endommagés pendant le chaos.
-- ============================================================================
ShopConfig.Vehicles = {
    Bicycle = {
        DisplayName = "Vélo",
        Description = "Pas cher, pas de frais d'entretien.",
        Price = 500,
        Speed = 1.3,        -- Multiplicateur de vitesse (1.0 = marche)
        RepairCost = 0,     -- Gratuit à réparer
        Order = 1,
    },
    Scooter = {
        DisplayName = "Scooter",
        Description = "Rapide et pratique pour les livraisons.",
        Price = 2000,
        Speed = 1.6,
        RepairCost = 200,
        Order = 2,
    },
    Car = {
        DisplayName = "Voiture",
        Description = "Véhicule classique. Fiable et solide.",
        Price = 8000,
        Speed = 2.0,
        RepairCost = 500,
        Order = 3,
    },
    SportsCar = {
        DisplayName = "Voiture de Sport",
        Description = "Vitesse maximale. Attention aux météorites.",
        Price = 30000,
        Speed = 2.5,
        RepairCost = 2000,
        Order = 4,
    },
    Truck = {
        DisplayName = "Camion",
        Description = "Lent mais résistant aux catastrophes. Idéal pour les livraisons.",
        Price = 15000,
        Speed = 1.4,
        RepairCost = 800,
        Order = 5,
    },
}

-- ============================================================================
-- OUTILS DE MÉTIER
-- Chaque métier a des outils améliorables (Nv.1 gratuit → Nv.5 max).
-- L'outil améliore l'efficacité des missions (+vitesse ou +récompense).
-- ============================================================================
ShopConfig.Tools = {
    -- Pompier
    FireExtinguisher2 = {
        DisplayName = "Lance à Incendie Nv.2",
        Description = "Éteint les feux 20% plus vite.",
        Price = 1000,
        RequiredJob = "Firefighter",
        RequiredLevel = 2,
        Bonus = 1.2,  -- +20% efficacité
        Order = 1,
    },
    FireExtinguisher3 = {
        DisplayName = "Lance à Incendie Nv.3",
        Description = "Éteint les feux 40% plus vite.",
        Price = 3000,
        RequiredJob = "Firefighter",
        RequiredLevel = 4,
        Bonus = 1.4,
        Order = 2,
    },
    FireExtinguisher5 = {
        DisplayName = "Lance à Incendie LÉGENDAIRE",
        Description = "La plus puissante. Effet visuel unique.",
        Price = 15000,
        RequiredJob = "Firefighter",
        RequiredLevel = 8,
        Bonus = 1.8,
        Order = 3,
    },
    -- Médecin
    MedKit2 = {
        DisplayName = "Kit Médical Nv.2",
        Description = "Soigne 20% plus vite.",
        Price = 1000,
        RequiredJob = "Medic",
        RequiredLevel = 2,
        Bonus = 1.2,
        Order = 1,
    },
    MedKit3 = {
        DisplayName = "Kit Médical Nv.3",
        Description = "Soigne 40% plus vite.",
        Price = 3000,
        RequiredJob = "Medic",
        RequiredLevel = 4,
        Bonus = 1.4,
        Order = 2,
    },
    MedKit5 = {
        DisplayName = "Kit Médical LÉGENDAIRE",
        Description = "Réanimation instantanée. Effet visuel unique.",
        Price = 15000,
        RequiredJob = "Medic",
        RequiredLevel = 8,
        Bonus = 1.8,
        Order = 3,
    },
    -- Bandit
    Lockpick2 = {
        DisplayName = "Crochet Nv.2",
        Description = "Ouvre les serrures 20% plus vite.",
        Price = 1000,
        RequiredJob = "Bandit",
        RequiredLevel = 2,
        Bonus = 1.2,
        Order = 1,
    },
    Lockpick3 = {
        DisplayName = "Crochet Nv.3",
        Description = "Ouvre les serrures 40% plus vite.",
        Price = 3000,
        RequiredJob = "Bandit",
        RequiredLevel = 4,
        Bonus = 1.4,
        Order = 2,
    },
    Lockpick5 = {
        DisplayName = "Passe-Partout LÉGENDAIRE",
        Description = "Ouvre tout. Effet visuel unique.",
        Price = 15000,
        RequiredJob = "Bandit",
        RequiredLevel = 8,
        Bonus = 1.8,
        Order = 3,
    },
}

-- ============================================================================
-- CONSOMMABLES
-- Items à usage unique. Disparaissent après utilisation.
-- Les joueurs doivent les racheter → money sink anti-inflation.
-- ============================================================================
ShopConfig.Consumables = {
    SurvivalKit = {
        DisplayName = "Kit de Survie",
        Description = "Réduit les dégâts pendant le chaos pendant 60s.",
        Price = 500,
        MaxStack = 5,   -- Maximum possédable en même temps
        Order = 1,
    },
    Flashlight = {
        DisplayName = "Lampe Torche",
        Description = "Indispensable pendant les Pannes Générales. Durée : 1 chaos.",
        Price = 300,
        MaxStack = 3,
        Order = 2,
    },
    SpeedBoost = {
        DisplayName = "Boisson Énergétique",
        Description = "Vitesse +30% pendant 120s. Parfait pour fuir ou livrer.",
        Price = 400,
        MaxStack = 5,
        Order = 3,
    },
    Shield = {
        DisplayName = "Gilet de Protection",
        Description = "Absorbe 1 coup fatal pendant le chaos. Usage unique.",
        Price = 1500,
        MaxStack = 2,
        Order = 4,
    },
}

return ShopConfig
