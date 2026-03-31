# Necrocraft Resurrected — Wiki

## Overview

**Necrocraft Resurrected** is a comprehensive necromancy overhaul mod for *The Elder Scrolls III: Morrowind*, powered by MWSE-Lua. It reimagines necromancy as a deep gameplay system: you harvest bones from corpses, assemble undead servants at a workbench, raise them with spells learned from grimoires, and command growing armies of minions. The mod adds a custom skill, dozens of new spells, questlines with named necromancers, a soul gem system, and a full Lichdom path for the player.

**Requirements:** MWSE, MagickaExpanded, CraftingFramework, Skills Module, OAAB Data.

---

## Core Systems

### Corpse Preparation (Custom Skill)

Corpse Preparation is a new skill registered through the *Skills Module* framework. It gates access to crafting and determines how effectively you harvest bones.

**Skill governs:**
- Which minion types you can assemble (each recipe has a minimum skill requirement)
- Bone harvest quality — higher skill + Intelligence + Luck + Fatigue = better chance to recover complete bones instead of fragments
- Experience is gained by harvesting corpses, preparing them, and assembling bone piles

**Experience gain** is scaled by the MCM setting "Experience Gain" (default 50).

---

### Corpse Interaction

When you open a corpse's inventory, the standard "Take All" button is replaced with a cycling context button. Pressing **Left Alt** cycles through available actions:

| Action | What it does |
|---|---|
| **Dispose of Corpse** | Deletes the corpse cleanly |
| **Harvest Bones** | Strips bones from the corpse based on its type; awards skill XP; triggers a bounty |
| **Prepare Corpse** | Opens the CraftingFramework menu to convert the body into a raiseable undead form |

Available actions depend on corpse type:
- **NPC / Bonewalker / Greater Bonewalker** corpses offer all three options
- **Wolf** corpses only offer Dispose and Prepare (no bone harvest)
- **Skeletons** and other undead offer Dispose and Harvest only

Preparing a corpse costs a soul gem (for Bonewalker/Greater Bonewalker variants) and transfers the corpse's existing data (resurrection count, name) to the prepared form. The original corpse is disposed after crafting completes.

---

### Bone Harvesting

Harvesting a corpse yields skeletal components. The result is probabilistic:

```
success = (Intelligence/5 + Luck/10 + CorpsePreparation) × (CurrentFatigue / BaseFatigue)
```

Compared against random thresholds:
- **High roll (×75):** complete bone recovered
- **Medium roll (×50):** complete bone recovered (only if it has no broken version)
- **Low roll (×25):** broken fragments recovered instead (e.g., skull jaw + skullcap instead of a full skull)

**Bone fragments** can be reassembled into complete bones at the workbench if your skill is ≥ 5.

---

### Bone Assembly (Crafting)

Complete bone piles are assembled using the CraftingFramework workbench. Each recipe produces a `_misc` item (an inert bone pile) that can later be animated with the appropriate raise spell.

#### Skeleton Recipes

| Minion | Skill Req. | Key Materials |
|---|---|---|
| Skeleton Cripple | 10 | Broken skull, torso (broken), 1 arm, 1 bone, 2 legs, pelvis |
| Skeleton Warrior | 40 | Full skull, torso, 2 arms, 2 legs, pelvis |
| Skeleton Champion | 70 | Full skull, torso, 2 arms, 2 legs, pelvis |

#### Bone Construct Recipes

| Minion | Skill Req. | Key Materials |
|---|---|---|
| Bonespider | 5 | 1 skull, 4 arm upper bones, 2 arm bones |
| Bonelord | 50 | 1 broken skull, 4 arms, 1 soul gem (lesser) |
| Boneoverlord | 95 | 3 broken skulls, 4 arms, 3 soul gems, 8 bones |

#### Bone Part Assembly Recipes (Skill 5+)

Fragments can be re-assembled into functional parts:
- Left/Right Arm: hand + wrist + 1 bone
- Left/Right Leg: foot + shin + 1 bone
- Full Skull: skullcap + jaw
- Ribcage Torso: 2× broken torso

---

## Minion Types

All player-raised minions follow the player and are tracked in `tes3.player.data.necroCraft.minions`.

### Skeletons

| Type | Description | Special |
|---|---|---|
| **Skeleton Cripple** | Weakest skeleton. Cannot use two-handed weapons or shields. | Drops incompatible equipment on raise |
| **Skeleton Warrior** | Standard skeleton. Full weapon and shield use. | — |
| **Skeleton Champion** | Strongest skeleton. Requires a black soul to raise. | 75% chance to self-restore 150 HP when destroyed |

### Bone Constructs

| Type | Description | Special |
|---|---|---|
| **Bonespider** | Weakest bone construct, multi-limbed spider form. | Good starter construct |
| **Bonelord** | Heavily enchanted. Immune to normal weapons. | Can raise skeletal minions during combat (AI) |
| **Boneoverlord** | More powerful Bonelord variant. | Can mass-raise all nearby skeletal minions during combat (AI) |

### Flesh Undead (from Corpse Preparation)

| Type | Description | Notes |
|---|---|---|
| **Zombie** | Basic animated humanoid, melee only | Lowest corpse preparation requirement (5) |
| **Bonewalker** | Melee + weak drain spells | Requires 1 lesser soul gem to prepare |
| **Greater Bonewalker** | Stronger, more potent spells | Requires 1 grand soul gem to prepare; skill 45 |
| **Bone Wolf** | Animated wolf skeleton | Skill 50; prepared from wolf corpses |

---

## Spells

Spells are learned from **Grimoires** (books found in the world or from necromancer NPCs). All spells use the MagickaExpanded framework.

### Raise Spells

These are targeted spells cast on prepared bone piles or corpses. The effect's **magnitude** is the maximum creature level you can raise. Raising high-level undead (level 8+) requires consuming a black soul gem.

| Spell | Effect | Magnitude | Raises |
|---|---|---|---|
| Raise Skeleton Cripple | Raise Skeleton | 3 | Cripple pile |
| Raise Skeleton Warrior | Raise Skeleton | 7 | Warrior pile |
| Raise Skeleton Champion | Raise Skeleton | 10 | Champion pile |
| Raise Bonespider | Raise Bone Construct | 3 | Bonespider pile |
| Raise Bonelord | Raise Bone Construct | 8 | Bonelord pile |
| Raise Boneoverlord | Raise Bone Construct | 20 | Boneoverlord pile |
| Simple Reanimation | Raise Corpse | 5 | Bonewalker/Zombie corpse |
| Greater Reanimation | Raise Corpse | 8 | Greater Bonewalker corpse |
| Multifold Reanimation | Raise Corpse | 25 | Any prepared corpse |

A **Resurrection Count** is tracked per minion — each time it dies and is re-prepared/re-raised, the count increments, which adds to its effective level for raise checks.

### Call Spells (Teleport Minion)

Each minion type has a corresponding **Summon** spell. Unlike vanilla summons, these do not create new creatures — they teleport an existing raised minion from anywhere in the world to the caster's location. The minion must already exist and not be actively following the caster.

Available for: Skeleton Cripple, Skeleton Warrior, Skeleton Champion, Bonespider, Bonelord, Boneoverlord, Bonewalker, Greater Bonewalker.

Teleporting counts as necromantic practice and triggers a **bounty**.

### Mass Spells (NPC-only)

Used by powerful necromancer NPCs in combat:

| Spell | Effect |
|---|---|
| **Mass Reanimation** | Raises all nearby corpses and bone piles (level cap 50) in a radius |
| **Mass Skeletal** | Raises all nearby skeletal bone piles (level cap 50) in a radius |

### Utility & Offensive Spells

| Spell | Description |
|---|---|
| **Black Soul Trap** | Traps the soul of a sentient (conscious) being in a black soul gem |
| **Corrupt Soulgem** | Area-of-effect enchantment that converts normal soul gems into black ones |
| **Commune with Dead** | Opens a dialogue with a soul trapped in a black soul gem in your inventory |
| **Spread Disease** | Infects a target with a random common disease (resisted by disease resistance) |
| **Feint Death** (Self) | Puts the caster in a cataleptic state — appears dead, fully paralyzed but invulnerable |
| **Touch of Feint Death** | Same effect applied to a touched target |
| **Conceal Undead** | Makes the target appear as a living humanoid; for liches, temporarily reverts skeleton appearance |
| **Death Pact** (Raven's Bargain) | Constant enchantment effect — on lethal hit, consumes a trapped black soul to restore health |
| **Dark Ritual** | The Lichdom spell — bonds your soul to a phylactery item |
| **Goris's Souldrinker** | Drains Health, Magicka, and Fatigue while applying Soul Trap |
| **Touch of Pain / Touch of Agony** | Touch-range combined health+fatigue damage |
| **Pain / Agony** | Targeted combined health+fatigue damage |
| **Heart Attack** | 120-point drain health in 1 second |
| **Convulsion** | 180-point drain fatigue over 3 seconds |

---

## Soul Gem System

The mod adds special **Black Soul Gems** (Azura's Black Soulgem variant: `NC_SoulGem_AzuraB`) alongside the vanilla `AB_Misc_SoulGemBlack`.

**Black souls** are required for:
- Raising Skeleton Champions, Bonelords, Boneoverlords, and any creature of level 8+
- Lichdom resurrection
- Certain quest objectives

**Commune with Dead** allows you to start a dialogue with a soul trapped in a black gem without releasing or destroying the gem.

The `captureSoul` function checks for available empty black soul gems before trapping; if none are available, the operation silently fails.

---

## Necromancer AI

Necromancer NPCs use the `aiAction` module. When in combat, they can:

1. **Raise nearby corpses** — converts dead NPCs/creatures within 500 units into prepared corpses, then casts a raise spell
2. **Raise bone piles** — targets any pile within 200 units with an appropriate raise spell based on what spells they have
3. **Prepare and raise skeletons** — converts dead creatures into skeleton piles, then raises them
4. **Mass raise** (powerful necromancers) — converts all nearby dead and raises everything at once

During casting, the NPC temporarily drops its fight value to 0 and stops combat to avoid interrupting the cast, then resumes hostility after the spell resolves.

---

## Summon Undead Overhaul (MCM Options)

Two optional settings change how vanilla Summon Undead spells work:

### Edit Summon Undead Effects
When enabled, vanilla summon undead spells on enchantments are replaced with the mod's **Call** variants (teleport instead of create). NPCs who are necromancers cast their summon spells once per day (creating one new minion with no time limit rather than temporary summoning).

### Replace Summon Undead Spells
When enabled:
- **Necromancers** (config whitelist) keep both their summon and call spells
- **Summon Teachers** (Mages Guild trainers) get only the call variant — they teach it but don't use it
- **Everyone else** has their undead summons replaced with Daedra equivalents:
  - Skeleton / Bonewalker → Scamp
  - Greater Bonewalker → Clanfear
  - Bonelord → Flame Atronach

---

## Lichdom

Lichdom is an advanced questline-gated transformation. The path to becoming a lich is deliberately obscure — clues are hidden in quests, spells, and thematic artifacts.

### The Process (High-Level)

1. Obtain the **Death Pact** enchantment (constant effect on an item) — this item becomes your **phylactery**
2. Cast **Darkest of Rituals** (250 magicka cost, multi-effect damage) while the phylactery is in your inventory — this bonds your soul to the item and marks it
3. Place the phylactery inside a **container** — the game tracks that container's location as your resurrection point
4. On death, instead of a normal death screen: your corpse is created at your location, your body shrinks invisible, controls lock, and the `playerResurrection` function fires

### Resurrection Mechanics

When you die as a lich:
1. A copy of your corpse spawns (using your current race/appearance, or a skeleton version if already transformed)
2. Your inventory is transferred to the corpse
3. You teleport to the phylactery container's stored cell and position
4. If the container holds `NC_skeleton_champ_misc` + a black soul gem:
   - A warrior bone pile is placed, the Lich Resurrection spell is cast, and after the animation you complete the transformation
   - Your race changes to **Skeleton Race** (permanent appearance change)
   - You gain: Immune to Frost, Immune to Poison, Immune to Disease, 50% Resist Magicka, 50% Resist Shock, 50% Resist Normal Weapons, and lich-specific passive abilities
5. If the materials are absent, you die permanently

### Conceal Undead & Lich Appearance

While transformed, you appear as a skeleton to all NPCs (causing panic/hostility). Casting **Conceal Undead** temporarily reverts your appearance to your original race for the spell's duration, setting `NC_Lichdom` global to -1 and calling `changeRaceBack()`. When it expires, your skeleton form returns.

---

## Quests

The mod adds questlines connected to named necromancers across Vvardenfell. Quest journal IDs use the prefix `NC_Help`.

| NPC | Journal ID | Summary |
|---|---|---|
| **Sharn gra-Muzgob** | NC_HelpSharn | Involves trapping the soul of Llevule Andrano. Completing her Mages Guild quest (MG_Sharn_Necro) unlocks necromancy spells for her to teach |
| **Daris Adram** | NC_HelpAdram | Requires you to bring 2 skeleton warriors and 2 bonewalkers following you in the same cell |
| **Treras Dres** | NC_HelpDres | Involves soul gems; rewards 5 levels of Corpse Preparation skill on completion |
| **Milyn Faram** | NC_HelpFaram | Involves experimenting on Vedelea Othril with a feint death enchantment |
| **Tirer Belvayn** | NC_HelpBelvayn | Uses a **Dwemer Telescope** to observe the "Shade of the Revenant" — a periodic night event (every 8 days). The telescope can only be used once per 12-hour period, only at night, and only when no enemies are nearby |
| **Telura Ulver** | NC_HelpUlver | Offers an alternative ending to the vanilla Mages Guild quest "Kill Necromancer Telura Ulver". Completion moves mages to the Imperial Cult shrine and triggers a skeleton prank event |
| **Sorkvild the Raven** | NC_HelpSorkvildT | Involves Sorkvild's unique items |
| **Delvam Andarys** | NC_HelpDelvam | Involves a chest (nc_chest_vsl_dest) that is hidden until the quest begins |
| **Goris the Maggot King** | NC_HelpGoris | Involves hunting down a former associate named Bakarak |

### The Shade of the Revenant

An in-game event tracked via the Rest/Wait menu — a label shows how many days until the next Shade appears (every 8 days). On Shade night, using the Dwemer Telescope in any location except Sorkvild's Tower advances the Belvayn quest.

---

## Necromancer NPCs

The following named NPCs are recognized as necromancers. They receive raise spells scaled to their level and can use them in combat. NPCs below level 10 receive Tier 1 spells; below 20 receive Tier 2; level 20+ receive Tier 3.

**Explicitly configured:**
Sharn gra-Muzgob, Dedaenc, Daris Adram, Treras Dres, Tirer Belvayn, Milyn Faram, Koffutto Gilgar, Sorkvild the Raven, Goris the Maggot King, Delvam Andarys, Telura Ulver

**Auto-detected:** All NPCs with the `Necromancer` class are automatically added to the necromancer list on game load.

**Summon Teachers** (know and sell call spells, but won't cast them): Heem-La, Malven Romori, Ferise Varo, Uleni Heleran.

---

## MCM Settings

| Setting | Default | Description |
|---|---|---|
| Enable Mod | true | Master toggle |
| Preserve Tooltip | true | Shows the original corpse name on a raised minion's tooltip |
| Edit Summon Undead Effects | true | Converts summon undead spells to call/once-daily mechanics |
| Replace Summon Undead Spells | true | Replaces undead summons on non-necromancer NPCs with Daedra equivalents |
| Bounty Value | 1500 | Gold bounty for being caught practicing necromancy |
| Experience Gain | 50 | Multiplier for Corpse Preparation skill progression |
| Necromancers list | (see above) | Editable list of NPC IDs that keep undead spells |
| Summon Teachers list | (see above) | Editable list of NPC IDs that teach but don't use undead spells |

---

## Grimoires (Spell Tomes)

Spells cannot be bought from merchants in the traditional sense — they are learned from **grimoires** (books). Known grimoire IDs:

| Grimoire | Teaches |
|---|---|
| nc_bk_corpse1 | Simple Reanimation |
| nc_bk_corpse2 | Greater Reanimation |
| nc_bk_corpse3 | Multifold Reanimation |
| nc_bk_skeleton_cr | Raise Skeleton Cripple |
| nc_bk_skeleton_war | Raise Skeleton Warrior |
| nc_bk_skeleton_ch | Raise Skeleton Champion |
| nc_bk_bonespider | Raise Bonespider |
| nc_bk_bonelord | Raise Bonelord |
| nc_bk_boneoverlord | Raise Boneoverlord |
| nc_bk_BlackSoulTrap1/2 | Black Soul Trap |
| nc_bk_spread_disease | Spread Disease |
| T_Bk_MysteriesOfTheWormTR | Darkest of Rituals (Lichdom) |

---

## Dependencies & Framework Notes

- **MagickaExpanded** — All custom spell effects and spell registration
- **CraftingFramework** — Bone pile and corpse preparation menus
- **Skills Module** — Corpse Preparation custom skill (`NC:CorpsePreparation`)
- **OAAB Data** — Provides the `AB_Misc_Bone*` bone part items used in all assembly recipes
