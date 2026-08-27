# Path of Exile Build Optimizer

Moteur d’optimisation de builds Path of Exile. **Path of Building Community** est la seule source de vérité : chaque candidat est scoré par le vrai PoB, pas par une formule maison.

Interface locale : classe, skill, objectif (DPS, vie, ES, crit…), contraintes min/max, dimensions de recherche.

## Prérequis

- [LuaJIT](https://luajit.org/) (place `luajit.exe` dans `tools/luajit/`)
- Python 3 (pour l’UI)
- Git, avec sous-modules

```powershell
git clone --recurse-submodules https://github.com/Vivosjerome/PathOfExileBuilder.git
cd PathOfExileBuilder
```

Si le clone a déjà été fait sans sous-modules :

```powershell
git submodule update --init --recursive
```

PoB Community est le sous-module `vendor/PathOfBuilding` (branche `dev`).

## Interface

```powershell
.\scripts\run-worker.ps1 ui
```

Ouvre [http://127.0.0.1:8765/](http://127.0.0.1:8765/). Le worker PoB reste en mémoire ; le journal de recherche est streamé en direct.

## Interface en ligne

Repo **public** + Pages source **GitHub Actions**. L’optimiseur :

[https://vivosjerome.github.io/PathOfExileBuilder/app/](https://vivosjerome.github.io/PathOfExileBuilder/app/)

« Lancer sur GitHub » crée une issue `[optimize]` (compte propriétaire). Actions exécute LuaJIT + PoB. **Test rapide** = dry-run (quelques secondes). Décoche pour une vraie recherche (20–50 min).

Pages est gratuit seulement si le repo est public. Un repo privé demande GitHub Pro.

## Ligne de commande

```powershell
# Univers PoB, sans recherche
.\scripts\run-worker.ps1 generate -DryRun

# Recherche complète (exemple Winter Orb)
.\scripts\run-worker.ps1 generate -Definition examples\winter-orb.json

# Régressions figées A/B/C/D
.\scripts\run-worker.ps1 regress
```

## BuildDefinition

Voir `examples/winter-orb.json` et `core/build/definition.lua`.

**Objectifs :** `MAX_DPS`, `MAX_FULL_DPS`, `MAX_LIFE`, `MAX_ES`, `MAX_EHP`, `MAX_CRIT`, `MAX_CRIT_MULTI`, `MAX_ARMOUR`, `MAX_EVASION`, `MAX_SUPPRESSION`, `MAX_BLOCK`, …

**Contraintes :** n’importe quel champ PoB (`Life`, `EnergyShield`, `FireResist`, `CritChance`, `CritMultiplier`, `SpellSuppressionChance`, …) en `min` / `max`.

**Recherche :** gear, rares, jewels, gems, flasks, tree, ascendancy, cluster, timeless.

## Régressions

Snapshots figés dans `docs/benchmarks/` — ne pas les écraser.

| ID | Contenu | CombinedDPS |
|----|---------|-------------|
| A | Uniques, sans contrainte de res | 482 652 |
| B | Uniques, 75/75/75 | 96 975 |
| C | Uniques + rares, 75/75/75 | 197 640 |
| D | Uniques + rares + jewels, 75/75/75 | 246 276 |

## Architecture

```
ui/                 interface locale
scripts/            worker LuaJIT + serveur UI
core/build          BuildDefinition, catalogue de stats
core/catalog        univers PoB
core/pob-engine     oracle PoB (LuaJIT / HeadlessWrapper)
optimizer/          beam, mutations, contraintes, scoring
vendor/PathOfBuilding   sous-module PoB Community
docs/benchmarks     A / B / C / D figés
```
