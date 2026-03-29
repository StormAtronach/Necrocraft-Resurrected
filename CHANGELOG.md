# Necrocraft — Code Changes Changelog

## Bug Fixes

### `magic/edit.lua`

- **Typo in effect ID (line 71):** `tes3.effect.callGreaterBonewalkerBonewalker` → `tes3.effect.callGreaterBonewalker`. The duplicated "Bonewalker" suffix caused the field to resolve to `nil`, silently breaking enchantment replacement for Summon Greater Bonewalker when `editSummonUndeadEffects` was enabled.
- **Double `id.id` indexing (lines 154, 157):** `id.id.spell.callGreaterBonewalker` / `id.id.spell.callBonelord` → `id.spell.callGreaterBonewalker` / `id.spell.callBonelord`. `id.id` evaluated to `nil`, throwing a Lua error and crashing `playerSummonUndead()` for players who had Greater Bonewalker or Bonelord summon spells with `replaceSummonUndeadSpells` enabled.
- **Dead player guard (lines 88–89):** Two empty `if/then/end` branches that never skipped the player during NPC iteration were replaced with a proper `if/elseif` guard.

### `aiAction.lua`

- **`restoreCombat` used string instead of reference (line 154):** `actor = actor.object.id` overwrote the reference variable with a string ID before passing it to `startCombat`, which expects a reference object. After a necromancer's cast routine temporarily stopped their combat, hostile actors were never properly re-engaged.
- **Spell fired three times per cast (lines 178–197):** `tes3.cast` / `mwscript.explodeSpell` was scheduled at 0.4s, 0.5s, and 0.6s timers. All three fired, hitting the target three times. The redundant 0.4s and 0.5s timer blocks were removed, keeping only the 0.6s cast.

### `main.lua`

- **`fightCastiong` typo (lines 560, 562):** `fightCastiong` → `fightCasting`. The field set in `aiAction.cast` is `fightCasting`. Because of the typo the `onCombatStart` guard never fired, allowing NPCs to be re-engaged by other combatants during the casting window and breaking the cast routine.

---

## Performance & GC Optimizations

### `magic/onTick.lua`

- **`diseasesTable` moved to module level:** An 18-element table was being allocated inside `onTick.spreadDisease` on every spell tick. Moved to a module-level upvalue so it is created once at load time.

### `undead.lua`

- **`getType` O(n) → O(1):** Replaced the `undeadTable` + `pairs()` loop (iterating 11 entries with mesh string comparison on every call) with a `meshToType` reverse lookup table populated once in `undead.init`. `getType` now resolves in O(1).

### `main.lua`

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
|---|---|---|
| `mwscript.addSpell` | `tes3.addSpell` | `main.lua`, `lichdom.lua`, `magic/edit.lua`, `magic/onTick.lua` |
| `mwscript.getDistance` | `ref.position:distance(other.position)` | `aiAction.lua` (×8), `main.lua` |
| `mwscript.stopCombat` | `mobile:stopCombat()` | `aiAction.lua`, `quests.lua` |
| `mwscript.startCombat` | `mobile:startCombat(targetMobile)` | `aiAction.lua`, `main.lua` |
| `mwscript.explodeSpell` | `tes3.cast{reference=caster, target=caster, spell=spell}` | `aiAction.lua` |
| `mwscript.playSound` | `tes3.playSound` | `main.lua` |
| `mwscript.addTopic` | `tes3.addTopic` | `main.lua` |
| `mwscript.disable` | `tes3.getReference(id):disable()` | `quests.lua` |
| `mwscript.addToLevItem` | `tes3leveledItem:insert(item, level)` | `main.lua` |
| `mwscript.hasItemEquipped` | `tes3actor:hasItemEquipped(item)` | `lichdom.lua` |
