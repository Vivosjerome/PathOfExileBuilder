# Rapport technique — PoB Auto Build Optimizer

Analyse du moteur Path of Building Community (`vendor/PathOfBuilding`, branche `dev`) et architecture proposée pour l’optimizer.

PoB n’était **pas** présent dans le workspace au départ. Il a été cloné depuis :

https://github.com/PathOfBuildingCommunity/PathOfBuilding

Licence : MIT. Les formules ne sont **pas** réécrites. PoB est la source de vérité.

---

## 1. Architecture actuelle de PoB

Path of Building n’est pas un calculateur avec une API HTTP. C’est une application Lua (LuaJIT) avec UI SimpleGraphic.

```
vendor/PathOfBuilding/
  src/                  code + data de jeu
    Launch.lua          entrée GUI
    HeadlessWrapper.lua entrée headless (tests / automation)
    Modules/            moteur (Build, Calcs, Data, ModParser…)
    Classes/            objets métier + UI (Item, PassiveSpec, *Tab)
    Data/               uniques, gems, mods, bases, ModCache
    TreeData/           arbres passifs par version (latest = 3_29)
  runtime/lua/          libs (dkjson, xml, sha1, base64)
  spec/                 tests busted (utilisent HeadlessWrapper)
```

Deux modes dans `Modules/Main.lua` :

- `LIST` — liste de builds
- `BUILD` — un build chargé

Un build en mémoire n’est **pas** un JSON plat. C’est un graphe d’objets :

```
build
  spec          PassiveSpec (arbre alloué)
  itemsTab      items + item sets + slots
  skillsTab     socket groups + gems
  configTab     enemy / charges / conditions
  calcsTab      moteur + output
  characterLevel
  mainSocketGroup
```

Persistance : XML `<PathOfBuilding>` (sections `Build`, `Tree`, `Items`, `Skills`, `Config`, …).

Chaîne de chargement :

```
HeadlessWrapper / Launch:OnInit
  → Main:Init  (Data, ModCache, tree, uniqueDB)
  → SetMode("BUILD", xml)
  → Build:Init
      LoadDB → tabs → calcsTab:BuildOutput()
```

Recalc : n’importe quelle mutation pose `build.buildFlag = true`. Le frame suivant (`runCallback("OnFrame")`) appelle `calcsTab:BuildOutput()`.

---

## 2. Emplacement du moteur PoB

Fichiers clés :

| Fichier | Rôle |
|---|---|
| `src/Modules/Calcs.lua` | Orchestration, FullDPS, `getMiscCalculator` |
| `src/Modules/CalcSetup.lua` | `calcs.initEnv` — assemble mods tree/items/gems/config |
| `src/Modules/CalcPerform.lua` | `calcs.perform` — pipeline 10 étapes |
| `src/Modules/CalcOffence.lua` | `calcs.offence` — hit, crit, ailments, DPS |
| `src/Modules/CalcDefence.lua` | `calcs.defence` — life/ES/res/EHP |
| `src/Modules/CalcTools.lua` | `(1 + INC/100) * MORE` |
| `src/Modules/CalcTriggers.lua` | skills trigger |
| `src/Modules/CalcMirages.lua` | mirage / clones |
| `src/Modules/ModParser.lua` | texte d’affixe → mods |
| `src/Classes/ModDB.lua` | stockage / évaluation des mods |
| `src/Classes/CalcsTab.lua` | `BuildOutput()` côté UI |

Pipeline exact :

```
calcs.buildOutput(build, "MAIN")
  calcs.initEnv(build, "MAIN")
  calcs.perform(env)
    doActorLifeMana
    calcs.defence(env, player)
    calcs.offence(env, player, mainSkill)
  calcs.calcFullDPS(...)
→ env.player.output
```

Trois métriques DPS **différentes** (ne pas les confondre) :

| Champ | Signification |
|---|---|
| `TotalDPS` | Hit DPS du **main skill** uniquement |
| `CombinedDPS` | Hit + DoT/ailments/cull/mirage de ce skill |
| `FullDPS` | Somme des skills marqués `includeInFullDPS` |

Objectif `Maximum DPS` → scorer **`CombinedDPS`** par défaut (ou `FullDPS` si auras/heralds/triggers doivent compter). Configurable via `score(build)`.

API de what-if interne (idéale pour l’optimizer) :

```lua
local calcFunc, baseOutput = calcs.getMiscCalculator(build)
local newOutput = calcFunc({ repSlotName = "Helmet", repItem = item })
local treeOutput = calcFunc({ addNodes = { [node] = true } })
```

C’est ce que le Compare tab utilise. Ça évite de reparser tout le XML à chaque candidat.

---

## 3. Système de données des items

| Source | Contenu |
|---|---|
| `src/Data/Uniques/*.lua` | ~1330 uniques (texte PoE brut) |
| `src/Data/Bases/*.lua` | bases d’armes/armures |
| `src/Data/ModExplicit.lua` | prefixes/suffixes rares |
| `src/Data/ModJewel*.lua` | mods jewels / abyss / cluster |
| `src/Data/ModCorrupted.lua`, `ModEldritch.lua`, … | pools spéciaux |
| `src/Data/Rares.lua` | templates rares UI |
| `src/Data/ClusterJewels.lua` | cluster jewels |
| `src/Classes/Item.lua` | parse du copier-coller PoE |
| `src/Classes/ItemsTab.lua` | slots + équipement |
| `main.uniqueDB` | DB runtime après parse |

Slots :

```
Weapon 1, Weapon 2, Helmet, Body Armour, Gloves, Boots,
Amulet, Ring 1, Ring 2, Belt, Flask 1..5, Jewel <nodeId>
```

Équiper un item :

```lua
local item = new("Item"):Item(rawText)
build.itemsTab:AddItem(item, true)           -- noAutoEquip
build.itemsTab:EquipItemInSet(item, setId)
-- ou : build.itemsTab.slots["Helmet"]:SetSelItemId(item.id)
build.buildFlag = true
runCallback("OnFrame")
```

What-if sans muter le build :

```lua
calcFunc({ repSlotName = "Weapon 1", repItem = item })
```

Un unique “faible” sur le papier **ne doit jamais être exclu a priori**. Seul `calcFunc` décide. Le pruning rapide ne peut qu’ordonner, pas éliminer de façon définitive, sauf upper bound **conservateur**.

---

## 4. Système des gems

| Source | Contenu |
|---|---|
| `src/Data/Gems.lua` | ~822 variantes (transfigured inclus) |
| `src/Data/Skills/act_*.lua` | skills actifs |
| `src/Data/Skills/sup_*.lua` | supports |
| `src/Classes/SkillsTab.lua` | socket groups |

Winter Orb :

- `grantedEffectId` = `WinterOrb`
- `gameId` = `Metadata/Items/Gems/SkillGemWinterOrb`
- Channeling spell cold, parties `Channelling` / `Idle`, stages

Socket group :

```lua
{
  enabled = true,
  includeInFullDPS = true,
  slot = "Body Armour",
  mainActiveSkill = 1,
  gemList = {
    { nameSpec = "Winter Orb", level = 20, quality = 20, enabled = true },
    { nameSpec = "Spell Echo", level = 20, quality = 20, enabled = true },
  }
}
build.skillsTab:ProcessSocketGroup(group)
table.insert(build.skillsTab.socketGroupList, group)
build.mainSocketGroup = 1
```

Compatibilité support : `calcLib.canGrantedEffectSupportActiveSkill` dans `CalcTools.lua`. Le moteur PoB ignore les supports incompatibles ; on peut aussi préfiltrer.

---

## 5. Système du passive tree

| Source | Contenu |
|---|---|
| `src/TreeData/3_29/tree.lua` | arbre live |
| `src/Classes/PassiveTree.lua` | data statique |
| `src/Classes/PassiveSpec.lua` | allocation du build |
| `src/GameVersions.lua` | versions d’arbre |

Classes (après remap 0-index) :

```
0 Scion, 1 Marauder, 2 Ranger, 3 Witch, 4 Duelist, 5 Templar, 6 Shadow
```

Witch ascendancies : `0` none, `1` Occultist, `2` Elementalist, `3` Necromancer.

API :

```lua
build.spec:SelectClass(3)
build.spec:SelectAscendClass(2)   -- Elementalist
build.spec:AllocNode(node)
build.spec:DeallocNode(node)
build.spec:ImportFromNodeList(nil, classId, ascendId, 0, nodeIds, {}, {})
```

Jewels : `spec.jewels[socketNodeId] = itemId` puis `BuildClusterJewelGraphs()`.

L’arbre est un graphe : on n’énumère pas 2^N nodes. Recherche par chemins, keystones, clusters, puis mutations locales.

---

## 6. Création d’un build

Headless :

```lua
newBuild()
build.characterLevel = 90
build.spec:SelectClass(classId)
build.spec:SelectAscendClass(ascendId)
-- gems, items, tree, config
build.configTab.input.enemyIsBoss = "Pinnacle"
build.configTab.input.usePowerCharges = true
build.configTab:BuildModList()
build.buildFlag = true
runCallback("OnFrame")
```

Ou `loadBuildFromXML(xml, name)`.

Config minimale pour DPS comparable :

- `enemyIsBoss` = `Pinnacle` (Guardian/Pinnacle, resists ~40%)
- charges power/frenzy/endurance
- conditions skill-specific (chill/shock pour Elementalist, stages Winter Orb)

Sans config, le DPS n’est **pas** comparable d’un run à l’autre.

---

## 7. Modification d’un build

| Cible | Mutation persistante | What-if rapide |
|---|---|---|
| Item slot | `EquipItemInSet` / `SetSelItemId` | `repSlotName` + `repItem` |
| Arbre | `AllocNode` / `ImportFromNodeList` | `addNodes` / `removeNodes` |
| Gems | muter `gemList` + `ProcessSocketGroup` | plus lourd ; souvent mutation réelle |
| Level | `build.characterLevel` | — |
| Config | `configTab.input[k] = v` + `BuildModList` | — |

Après mutation persistante : `build.buildFlag = true` puis `OnFrame`.

Pour des millions d’essais d’items, **rester sur `getMiscCalculator`**. XML round-trip à chaque candidat = trop lent.

---

## 8. Calcul DPS

```lua
build.calcsTab:BuildOutput()
-- ou
local env = build.calcs.buildOutput(build, "MAIN")
```

Hit DPS (`CalcOffence`) :

```
TotalDPS = AverageDamage * (HitSpeed or Speed) * dpsMultiplier * quantityMultiplier
```

`CombinedDPS` ajoute DoTs, poison, ignite, bleed, impale, culling, reservation multiplier.

Winter Orb a un `hitTimeOverride` dépendant des stages (`WinterOrbStageAfterFirst`). La config `skillStageCount` du gem doit être fixée (sinon le DPS “max” n’est pas le max).

**Interdit** : `DPS = base * multiplier` maison. Toujours `output.*` de PoB.

---

## 9. Récupération des statistiques

Après calc :

```
build.calcsTab.mainOutput          -- alias de mainEnv.player.output
build.calcsTab.mainEnv.player.output
```

Champs utilisés par l’optimizer :

```
CombinedDPS, TotalDPS, FullDPS, AverageDamage, Speed, HitSpeed,
PreEffectiveCritChance, CritChance, CritMultiplier,
Life, EnergyShield, Mana,
FireResist, ColdResist, LightningResist, ChaosResist,
Armour, Evasion, SpellSuppressionChance,
BlockChance, SpellBlockChance
```

Métadonnées sidebar : `Modules/BuildDisplayStats.lua`.

Tests officiels PoB : `spec/System/TestBuilds_spec.lua` compare `mainOutput[key]` à une référence. Même principe pour notre validation (écart 0%).

---

## 10. Parallélisation

Contraintes dures :

- **Un état Lua n’est pas thread-safe.** `build`, `GlobalCache`, `modLib.parseModCache` sont globaux.
- `GlobalCache` stocke des références d’`env` entiers. Inutilisable entre threads.
- Startup PoB = plusieurs secondes + RAM importante (data + ModCache).

Stratégie :

```
N process LuaJIT longue durée  (workers configurables)
    chacun : HeadlessWrapper chargé une fois
    chacun : boucle candidats → calcFunc / BuildOutput
    cache disque partagé (SQLite / fichiers hash)
```

Pas de thread dans un même Lua. Pas de process par candidat (le startup tuerait le throughput).

Ordre de grandeur visé :

| Mode | Débit attendu (ordre) |
|---|---|
| XML load + BuildOutput | ~1–10 / s / worker |
| Mutation + OnFrame | ~10–50 / s |
| `getMiscCalculator` item swap | ~50–300 / s |

Les millions de configs passent par **pruning + what-if**, pas par des millions de `loadBuildFromXML`.

---

## 11. Points difficiles

1. **Pas d’API oracle stable** dans ce checkout (`src/API/` absent). On wrappe HeadlessWrapper nous-mêmes.
2. **Config** : un oubli (boss, charges, stages) fausse tout le ranking.
3. **Main skill** : `mainSocketGroup` + `mainActiveSkill` doivent être explicites.
4. **TotalDPS vs CombinedDPS vs FullDPS** : mauvais choix = mauvais “meilleur build”.
5. **Triggers / mirages / minions** : dépendent de `GlobalCache` et de l’ordre des skills.
6. **Mods non parsés** : `parseMod` peut renvoyer nil → stats silencieusement perdues. Logger les lignes `extra`.
7. **Rares** : l’espace d’affixes est combinatoire. Génération guidée par tags du skill (cold, spell, channel), pas énumération naïve.
8. **Uniques à interaction** : un unique peut activer conversion / keystone / skill granted. Interdit de scorer un unique hors contexte.
9. **Arbre** : points disponibles = level + quests. Il faut un budget de points, pas un graphe illimité.
10. **LuaJIT Windows** : le clone git n’embarque pas `luajit.exe` (seulement `runtime/lua`). Il faut un LuaJIT local ou WSL. CI PoB utilise l’image `pathofbuilding-tests`.
11. **Import codes** : Inflate/Deflate nécessaires pour les pastebins ; le XML direct fonctionne sans.
12. **Upper bound Branch & Bound** : un bound trop agressif élimine des interactions. Si incertain → **garder**.

---

## 12. Architecture proposée pour l’optimizer

Décision structurante : **l’optimizer tourne dans le process LuaJIT de PoB**. Un host externe (plus tard UI) ne fait que piloter des workers via JSON-RPC stdin/stdout.

IPC à chaque candidat = trop lent pour viser des millions d’évaluations.

```
/core
    pob-engine          worker JSON-RPC + oracle Lua (wrappe PoB)
    build-model         character / slots / gems / tree (vues)
    items               index uniques + generateurs rares
    gems                index skills / supports
    passive-tree        graphe + scoring de chemins
/optimizer
    candidate-generator
    beam-search
    branch-bound
    genetic
    hill-climbing
    scorer              score(output, objective)
    mutations
    pruning             heuristique SEULEMENT (jamais verdict final)
/cache
    build-cache         hash → PoBResult
/data                   extraits / indexes générés depuis PoB Data
/ui                     plus tard, après moteur fonctionnel
/tests
    pob-validation      même output que PoB, écart 0%
    optimizer-tests
    benchmark
```

### Flux d’optimisation

```
Input: class, ascendancy, skill, level, objective
        ↓
Baseline (naked + skill + config standard) → PoB stats
        ↓
Phase beam par slot (ordre = impact estimé, pas hardcodé)
        ↓
  generate candidates (uniques + rares guidés)
        ↓
  prune léger (requirements, tags absurdes)
        ↓
  PoB calcFunc (repItem)  ← source de vérité
        ↓
  keep beam_size meilleurs (ex. 500)
        ↓
Mutations locales (item, jewel, support, passif)
        ↓
Stop: runtime / no-improvement / max calcs
        ↓
Top 100 + meilleur + explainer vs baseline
```

### Scoring

```lua
score(output, objective)
  MAX_DPS        → CombinedDPS  (contraintes res optionnelles)
  MAX_EHP        → TotalEHP
  MAX_DPS_EHP    → CombinedDPS * f(EHP)
```

Les contraintes (75% res elemental) sont des **filtres** ou des pénalités, pas un second calculateur.

### Hash de cache

SHA-1 (déjà dans `runtime/lua/sha1`) sur :

- class, ascendancy, level, tree version
- nodes alloués triés
- items par slot (raw canonique)
- gems (id, level, quality, enabled)
- config pertinente

`cache[hash] = output`. Jamais recalculer un build identique.

### Phases de dev (cette règle est la roadmap)

| Phase | Livrable | Statut |
|---|---|---|
| 0 | Analyse + ce rapport | fait |
| 1 | Oracle PoB headless : create / mutate / get_stats / hash | **fait** — round-trip 0%, ~42 calc/s |
| 2 | Validation : output oracle == output PoB (0%) | **fait** pour round-trip XML |
| 3 | Benchmark calcs/s + cache | **partiel** — 42 recalc/s, cache disque pas encore |
| 4 | Beam search 1 skill, uniques only, 1 slot puis N slots | |
| 5 | Générateur rares guidé par affixes | |
| 6 | Supports + auras | |
| 7 | Arbre passif | |
| 8 | Multi-run / mutations / top 100 | |
| 9 | UI progression | |

Pas d’UI complète avant un moteur qui bat un baseline avec de vrais calculs PoB.

---

## Décisions figées

- PoE 1, data tree `3_29`
- PoB Community `dev` = oracle
- Premier skill cible : Winter Orb / Witch / Elementalist / 90
- Premier objectif : Maximum CombinedDPS
- Config de référence : enemy `Pinnacle`, charges ON
- Optimizer in-process LuaJIT ; workers = process, pas threads
- Le score rapide ne tranche jamais le résultat final

---

## Phase 1 — résultats mesurés

Baseline réel, calculé par PoB (pas une formule maison) :

```
Witch / Elementalist / 90 / Winter Orb 20/20
arbre : 2 nodes (start + ascendancy start)
items : aucun
config : enemyIsBoss=Pinnacle, charges ON

CombinedDPS = 1206.04
Life        = 1125
Fire/Cold/Lightning resist = -60
hash        = 31632a4d001c259ba3620ab8f59f078a72064bf7
```

Validation XML export → reload : **écart 0%**, hash identique.

Benchmark : 50 `BuildOutput` complets en 1.20 s → **~42 calculs/s** après ~5 s de startup. Le what-if `getMiscCalculator` sera plus rapide (phase 4).

### Adaptations runtime (pas des formules)

1. `Main.lua:342` sur `dev` utilisait `count += 1`, invalide en LuaJIT. Corrigé en `count = count + 1` (bug du 26/08/2026, hors moteur de calcul).
2. Module `lua-utf8` (C) absent du clone git. Shim UTF-8 dans `core/pob-engine/shims/lua-utf8.lua`.
3. PoB consomme `arg[1]` comme lien d’import. Le worker sauvegarde argv **avant** `HeadlessWrapper`.
4. LuaJIT Windows : `tools/luajit/luajit.exe` (binaire communautaire). Le clone PoB n’embarque pas l’interpréteur.
