# Chaos City — Architecture Roblox Studio

## Structure de l'Explorer (arborescence Roblox Studio)

```
game
├── ServerScriptService/          ← CODE SERVEUR (invisible pour le client, sécurisé)
│   ├── Services/
│   │   ├── DataService.lua       ← Sauvegarde/chargement des données joueur (DataStore)
│   │   ├── PhaseService.lua      ← Gestion du cycle Calme → Alerte → Chaos → Résultat
│   │   ├── JobService.lua        ← Logique des métiers, missions, XP
│   │   ├── ChaosService.lua      ← Logique des catastrophes, dégâts, spawns
│   │   ├── EconomyService.lua    ← Transactions, anti-triche, money sinks
│   │   └── HeroService.lua       ← Classement Héros du Chaos, scores, récompenses
│   └── Init.server.lua           ← Point d'entrée : démarre tous les services
│
├── ReplicatedStorage/            ← PARTAGÉ entre serveur ET client (config, events, modules utilitaires)
│   ├── Modules/
│   │   ├── PlayerData.lua        ← Structure de données d'un joueur (template)
│   │   └── GameConfig.lua        ← Constantes du jeu (durées, prix, multiplicateurs)
│   ├── Events/
│   │   ├── RemoteEvents/         ← Communication Serveur → Client (notifications, UI updates)
│   │   └── RemoteFunctions/      ← Client demande au Serveur (ex: "quel est mon solde ?")
│   └── Config/                   ← Tables de configuration (métiers, catastrophes, items)
│
├── StarterPlayer/
│   └── StarterPlayerScripts/     ← CODE CLIENT (s'exécute sur la machine du joueur)
│       ├── PhaseUI.client.lua    ← Affiche le timer, les alertes, le classement
│       ├── JobUI.client.lua      ← Interface des missions de métier
│       └── ChaosEffects.client.lua ← Effets visuels des catastrophes (caméra shake, particules)
│
├── ServerStorage/                ← SERVEUR UNIQUEMENT, stocke les assets lourds
│   ├── ChaosModels/              ← Modèles 3D des catastrophes (météorites, vaisseaux alien...)
│   ├── BuildingModels/           ← Bâtiments destructibles (versions intacte/détruite)
│   └── Tools/                    ← Outils des métiers (lance incendie, kit médical...)
│
└── Workspace/                    ← LE MONDE 3D (la carte de la ville)
    ├── Map/                      ← Tous les bâtiments et le décor de la ville
    ├── SpawnPoints/              ← Points d'apparition des joueurs
    └── ChaosZones/               ← Zones marquées pour les effets de catastrophe
```

## Pourquoi cette organisation ?

### ServerScriptService (SSS)
- Le code ici tourne UNIQUEMENT sur le serveur Roblox
- Les joueurs ne peuvent JAMAIS voir ni modifier ce code
- C'est là qu'on met TOUTE la logique critique : argent, XP, dégâts, sauvegardes
- Règle d'or : si un hacker ne doit pas pouvoir tricher → ça va dans SSS

### ReplicatedStorage (RS)
- Le contenu est copié (répliqué) sur TOUS les clients automatiquement
- Parfait pour : les configurations partagées, les RemoteEvents, les modules utilitaires
- ATTENTION : ne jamais mettre de logique sensible ici (un hacker peut lire ce code)

### StarterPlayerScripts (SPS)
- Le code ici s'exécute sur la machine de CHAQUE joueur quand il rejoint
- Parfait pour : l'interface (UI), les effets visuels, les sons, le camera shake
- JAMAIS de logique de gain d'argent ou de vérification ici

### ServerStorage (SS)
- Comme SSS mais pour les ASSETS (modèles 3D, outils) pas pour les scripts
- Invisible pour les clients → on peut y stocker les modèles de catastrophe
  sans que le client les télécharge avant qu'on les clone dans le Workspace

### Workspace
- Le monde 3D visible et physique
- Tout ce qui est ici est rendu et simulé par le moteur physique
