# Necrocraft — Code Changes Changelog

## Skeleton CTD Fix & Undead-System Refactor

A crash-to-desktop was traced to the runtime mesh replacer, and fixing it properly required reworking undead classification and minion tracking. See `WIKI.md` → *Architecture & Maintenance Notes* for the full design.

### The `"no Animation class!"` CTD (`utility.lua`)

- **Root cause:** `skeletonReplacer()` set `object.mesh = ...` on `skeleton_weak` and every creature sharing the vanilla skeleton mesh, at runtime, on `initialized`. Mutating an animated creature's base mesh desyncs references already saved with the original mesh — on load such a reference enters simulation with no animation attachment, and the engine responds with the fatal `Actor Animation problem with "<id>". This actor has no Animation class!` handler, which calls `ExitProcess` (hard CTD). This produced the `skeleton_weak00000000` crash.
- **Fix:** removed `skeletonReplacer` and all runtime creature-mesh mutation (both the original mesh-swap and an interim reference-swap approach). `ashPitReplacer` is kept — it only rewrites static furniture meshes, which are animation-free and safe. Visual unification of world skeletons is dropped; if wanted it belongs in a load-ordered patch `.esp` that edits `MODL`, never in runtime Lua.

### Classification by id, not mesh (`undead.lua`)

- **`getType` now keys on object id, not `object.mesh`.** The previous `meshToType` reverse-lookup (see *Performance & GC Optimizations* below) required the mesh mutation above to make foreign skeletons classify; keying on id severs that dependency. `idToType` is built once per load by `undead.buildRegistry()` from: explicit anchor ids (+ a mesh-seeding pass that reproduces the old same-mesh reach), plus explicit registrations for the raised `NC_` creatures whose meshes do **not** match a vanilla anchor (`NC_bonewolf` = `r\UnDeadWolf_2.nif`, `NC_zombie` = `OAAB\r\zombieFresh.nif`) and so previously classified as `nil`.
- **`undead.registerType(id, type)`** is exposed as a public extension point for compatibility patches.

### Minion tracking (`undead.lua`, `main.lua`, `magic/onTick.lua`, `quests.lua`)

- **Replaced the typed global buckets** (`tes3.player.data.necroCraft.minions[type][id]`) with a two-store model: a flat, self-pruning membership index `minionIndex[refId] = type`, plus the authoritative per-reference record `reference.data.necroCraft.isMinion/.minionType`. This fixes the old buckets' nil-index hazards (e.g. missing `lich`/`lichKing` buckets), the unbounded leak (index entries are pruned as they go stale), and the `startswith("NC_")` id-prefix heuristic in `isRaisedByPlayer` (now a data lookup).
- **Per-reference data uses the supported `tes3reference.data` API, gated on `supportsLuaData`** — never `reference.itemData` (an item structure). The index exists specifically so membership can be answered by an id lookup without `reference.data` allocating a Variables attachment on every creature scanned; `.data` is only read on references the index already confirms are minions.
- **`markMinion` writes both stores atomically** (or neither, if the reference cannot hold lua data).
- New API: `markMinion`, `unmarkMinion`, `isMinion`, `getMinionType`, `forEachMinion`, `getRefData`. Callers updated: `onDeath` (gates on `isMinion` instead of `getType`, avoiding a `.data` allocation on every wild-undead death), `triggerGuards`, `callMinion`, and the Daris Adram quest reassignment.
- **`onSpellTick` guarded against `nil` type** (`if not utype then return end`) so an unclassified raise target can no longer crash `string.startswith`.

### Lossless save migration (`undead.lua`, `main.lua`)

- Pre-refactor saves are migrated in two phases so no standing minion is lost: **eager** (`migrateLegacyMinions`, on load, ports minions in active cells) and **lazy** (`migrateReferenceIfLegacy`, on `mobileActivated`, ports each minion as its cell loads). The legacy `minions` table is deleted only once every bucket is drained; entries for never-revisited cells linger harmlessly and migrate if those cells are ever loaded.

---

## Bug Fixes

### `magic/edit.lua`

- **Typo in effect ID (line 71):** `tes3.effect.callGreaterBonewalkerBonewalker` → `tes3.effect.callGreaterBonewalker`. The duplicated "Bonewalker" suffix caused the field to resolve to `nil`, silently breaking enchantment replacement for Summon Greater Bonewalker when `editSummonUndeadEffects` was enabled.
- **Double `id.id` indexing (lines 154, 157):** `id.id.spell.callGreaterBonewalker` / `id.id.spell.callBonelord` → `id.spell.callGreaterBonewalker` / `id.spell.callBonelord`. `id.id` evaluated to `nil`, throwing a Lua error and crashing `playerSummonUndead()` for players who had Greater Bonewalker or Bonelord summon spells with `replaceSummonUndeadSpells` enabled.
- **Dead player guard (lines 88–89):** Two empty `if/then/end` branches that never skipped the player during NPC iteration were replaced with a proper `if/elseif` guard.

### `aiAction.lua`

- **`restoreCombat` used string instead of reference (line 154):** `actor = actor.object.id` overwrote the reference variable with a string ID before passing it to `startCombat`, which expects a reference object. After a necromancer's cast routine temporarily stopped their combat, hostile actors were never properly re-engaged.
- **Spell fired three times per cast (lines 178–197):** `tes3.cast` / `mwscript.explodeSpell` was scheduled at 0.4s, 0.5s, and 0.6s timers. All three fired, hitting the target three times. The redundant 0.4s and 0.5s timer blocks were removed, keeping only the 0.6s cast.

### `main.lua` (Bug Fixes)

- **`fightCastiong` typo (lines 560, 562):** `fightCastiong` → `fightCasting`. The field set in `aiAction.cast` is `fightCasting`. Because of the typo the `onCombatStart` guard never fired, allowing NPCs to be re-engaged by other combatants during the casting window and breaking the cast routine.

---

## Performance & GC Optimizations

### `magic/onTick.lua`

- **`diseasesTable` moved to module level:** An 18-element table was being allocated inside `onTick.spreadDisease` on every spell tick. Moved to a module-level upvalue so it is created once at load time.

### `undead.lua`

- **`getType` O(n) → O(1):** Replaced the `undeadTable` + `pairs()` loop (iterating 11 entries with mesh string comparison on every call) with a `meshToType` reverse lookup table populated once in `undead.init`. `getType` now resolves in O(1).

### `main.lua` (Performance)

- **`bookGetText` event handler leak:** `event.register("bookGetText", onBookRead)` in the active skill branch was missing a prior `event.unregister`. On each game load in that state, a new handler was stacked. Added the corresponding `unregister` call before re-registering.
- **`onCalcHitChance` — removed `tes3.isAffectedBy{}` table allocation:** Replaced `tes3.isAffectedBy{reference = e.target, effect = tes3.effect.feintDeath}` with a direct `e.target.data.necroCraft and e.target.data.necroCraft.feintDeath` check. Avoids a table allocation and a C++ boundary crossing on every attack. Consistent with how `onSpellResist` already handled the same check.
- **`onDamage` — same `tes3.isAffectedBy{}` replacement** as above.
- **`onSpellTick` restructured:** Previously called `pileToRaised`/`corpseToRaised` (4+ string operations each) on every single spell tick regardless of effect ID. Restructured to gate on `effectId` first — raise effects (666–668) and vanilla summon effects (107–110) are now handled in separate branches with early returns. For all other effect IDs (the vast majority of spell ticks), the function returns immediately after three integer comparisons.

### `utility.lua`

- **Duplicate line in `ashPitReplacer`:** `nc_ashpit_r_01` was being replaced twice. The second call was corrected to `nc_ashpit_r_02` / `in_redoran_ashpit_02`.

---

## `mwscript` → `tes3` API Modernisation

All uses of the deprecated `mwscript` library were replaced with their modern `tes3` equivalents.

| `mwscript` function | Replacement | Files affected |
| --- | --- | --- |
| `mwscript.addSpell` | `tes3.addSpell` | `main.lua`, `lichdom.lua`, `magic/edit.lua`, `magic/onTick.lua` |
| `mwscript.getDistance` | `ref.position:distance(other.position)` | `aiAction.lua` (×8), `main.lua` |
| `mwscript.stopCombat` | `mobile:stopCombat()` | `aiAction.lua`, `quests.lua` |
| `mwscript.startCombat` | `mobile:startCombat(targetMobile)` | `aiAction.lua`, `main.lua` |
| `mwscript.explodeSpell` | `tes3.cast{reference=caster, target=caster, spell=spell}` | `aiAction.lua` |
| `mwscript.playSound` | `tes3.playSound` | `main.lua` |
| `mwscript.addTopic` | `tes3.addTopic` | `main.lua` |
| `mwscript.disable` | `ref = tes3.getReference(id); if ref then ref:disable() end` | `quests.lua` |
| `mwscript.addToLevItem` | `tes3leveledItem:insert(item, level)` | `main.lua` |
| `mwscript.hasItemEquipped` | `tes3actor:hasItemEquipped(item)` | `lichdom.lua` |

---

## Logging

Replaced all `mwse.log(...)` calls with `mwse.Logger.new()` per-file loggers, following the modern MWSE logging pattern. Each file that had log output now declares `local log = mwse.Logger.new()` at the top. All loggers in a mod share the same level setting automatically.

| File | Calls replaced | Level assigned |
| --- | --- | --- |
| `main.lua` | ESP active/inactive startup messages | `log:info` |
| `aiAction.lua` | "No valid spell found" warnings (×4) | `log:warn` |
| `utility.lua` | Minion dump in `logMinions` | `log:debug` |
| `magic/edit.lua` | Config flag reporting at init | `log:debug` |

The mod-wide log level is now exposed in the MCM (Settings category) via `settings:createLogLevelOptions`. The selected level is saved to config as `logLevel` (default `mwse.logLevel.info`) and applied on startup in the `modConfigReady` handler.

---

## Bug Fixes (Second Pass)

### `magic/effects.lua`

- **Wrong `onTick` handler name for Spread Disease:** `effects.onTick.onSpreadDisease` → `effects.onTick.spreadDisease`. The `on` prefix doesn't exist on the function in `onTick.lua`. The callback resolved to `nil`, silently disabling the entire Spread Disease mechanic.

### `quests.lua`

- **Nil crash on load for out-of-cell references:** `tes3.getReference(id):disable()` crashes if the reference is in an unloaded cell (returns `nil`). Added nil guards for both `nc_sc_theranasload` and `nc_chest_vsl_dest`.

### `main.lua`

- **`tes3.isAffectedBy` passed `.mobile` instead of reference (line 211):** `reference = activationRef.mobile` (a `tes3mobileActor`) → `reference = activationRef`. Every other call site passes the reference directly.
- **`corpsePreparationGlobal` nil guard:** `corpsePreparationGlobal.value == 1` could crash if the global doesn't exist. Added `corpsePreparationGlobal and` guard.

### `undead.lua` (Bug Fixes)

- **Nil crash in `handleFollow` when caster left the cell:** After resolving a string caster ID with `tes3.getReference`, the result was never checked before accessing `.id` on the next line. Added `if not caster then return end`.

### `soulGem.lua`

- **`countEmpty` zero check used Lua falsy test:** `if not soulGemLib.countEmpty{...}` — in Lua, `0` is truthy so `not 0` is `false`. The guard never fired when count was 0, allowing soul capture without an empty gem. Fixed to `if not emptyCount or emptyCount == 0`.
- **`onMenuInventorySelect` nil crash:** `block:findChild(...)` can return `nil` for non-item UI blocks (separators etc.). `item.text` would crash. Added `if item and` guard.

### `crafting/recipes.lua`

- **Wolf `craftCallback` passed wrong data to event:** The wolf recipe's `craftCallback` triggered `Necrocraft:CorpsePrepared` with `params.reference` (a raw `tes3reference`) instead of `data` (the full crafting framework table). The handler in `corpsePreparation.lua` expects `eventData.reference`, which would be nil on a raw reference, causing a crash when preparing a wolf corpse. Fixed to match the humanoid callback pattern.

### `lichdom.lua`

- **`phylactery.container` field path typo:** `tes3.player.data.necroCraft.container` → `tes3.player.data.necroCraft.phylactery.container`. The `elseif` branch in `updateContainer` that clears phylactery data when the item is removed from the container always evaluated to false, making it impossible to unset the phylactery.
- **`tes3.getObject` used instead of `tes3.getReference` for phylactery container:** `tes3.getObject` returns the base object (static default inventory), not the specific placed container reference the player filled with items. Changed to `tes3.getReference`. Also added a nil guard, and corrected downstream `tes3.removeItem` and `tes3.cast` calls to pass the reference directly instead of `container.id`.

### `magic/onTick.lua` (Bug Fixes)

- **Shadowed `local effect` declaration:** `local effect = params.effect` was immediately shadowed by a second `local effect` declaration three lines later. The first was dead code (callers never pass `effect`). Removed.
- **`local cell` unused in `raiseUndead`:** `tes3.getPlayerCell()` was called and stored in a local that was never used — each inner raise function defines its own `local cell`. Removed.
- **`"swamp fever"` duplicated in `diseasesTable`:** Appeared at indices 1 and 5, giving it double probability compared to all other diseases. Removed the duplicate.

---

## `spells:add` / `spells:remove` → `tes3.addSpell` / `tes3.removeSpell`

All direct spell list mutations in `magic/edit.lua` were replaced with the MWSE API equivalents. Key differences:

- **`actor =` instead of `reference =`** — the targets here are base NPC objects (from `tes3.getObject` / `tes3.iterateObjects`), not live references. The `actor` parameter is the correct one for base actor manipulation.
- **`updateGUI = false`** — all replacements are init-time batch operations. Passing `updateGUI = false` avoids a redundant GUI refresh on every individual call.
- **String IDs passed directly** — `tes3.getObject()` wrappers removed since both APIs accept spell ID strings natively.
- **`---@cast` / `--[[@as]]` annotations** — added to help the Lua language server narrow the broad `tes3object` return type of `tes3.iterateObjects` and `tes3.getObject` to the correct specific types (`tes3npc`, `tes3spell`), resolving type warnings without any runtime cost.

### Functions updated in `magic/edit.lua`

| Function | Changes |
| --- | --- |
| `edit.summonUndead` | All `npc.spells:add` → `tes3.addSpell{actor=npc, ...}`, all `npc.spells:remove` → `tes3.removeSpell{actor=npc, ...}` |
| `edit.playerSummonUndead` | `tes3.mobilePlayer.object.spells:remove` → `tes3.removeSpell{reference=tes3.mobilePlayer, ...}` (uses `reference =` since the player is a live actor) |
| `addFirstTierNecroSpells` | All `actor.spells:add(tes3.getObject(...))` → `tes3.addSpell{actor=actor, spell=..., updateGUI=false}` |
| `addSecondTierNecroSpells` | Same as above |
| `addThirdTierNecroSpells` | Same as above |
| `edit.necromancers` | All `npc.spells:add` / `npc.spells:remove` → `tes3.addSpell` / `tes3.removeSpell` with `actor=npc` |
