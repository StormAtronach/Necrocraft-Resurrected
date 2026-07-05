local undead = {}

local function requiresTwoHands(item)
	if item.objectType == tes3.objectType.armor then
		if item.slot == tes3.armorSlot.shield then
			return true
		end
	elseif item.objectType == tes3.objectType.weapon then
		if item.isTwoHanded or item.weaponType == tes3.weaponType.marksmanBow or item.weaponType == tes3.weaponType.marksmanCrossbow then
			return true
		end
	end
end

-- ---------------------------------------------------------------------------
-- Classification (architecture #1): undead type is keyed by object ID, not by
-- mesh path. The old design read meshToType[object.mesh], which forced the mod
-- to rewrite base creature meshes at runtime so foreign skeletons would classify
-- -- and that runtime mesh mutation is what desynced saved references and caused
-- the "no Animation class!" CTD. Here the live lookup is a stable id->type table,
-- immune to mesh changes. The vanilla-skeleton-mesh reach is preserved by a
-- one-time seeding pass that resolves same-mesh creatures into concrete IDs.
-- ---------------------------------------------------------------------------
local idToType = {}

local function registerType(id, utype)
	if type(id) ~= "string" then
		if not id then return end
		id = id.id
	end
	idToType[id:lower()] = utype
end
undead.registerType = registerType

-- Anchors: (objectId, type). Each is registered by id AND its mesh is used to seed
-- every other creature sharing that mesh (see buildRegistry) -- this reproduces the
-- exact reach of the original meshToType, which keyed one entry per anchor mesh.
local registryAnchors = {
	{ "skeleton",           "skeleton"          },
	{ "NC_skeleton_weak",   "skeletonCripple"   },
	{ "NC_skeleton_war",    "skeleton"          },
	{ "NC_bonespider",      "bonespider"        },
	{ "bonelord",           "bonelord"          },
	{ "NC_boneoverlord",    "boneoverlord"      },
	{ "lich",               "lich"              },
	{ "lich_barilzar",      "lichKing"          },
	{ "AB_Und_Zombie",      "zombie"            },
	{ "bonewalker",         "bonewalker"        },
	{ "Bonewalker_Greater", "greaterBonewalker" },
	{ "BM_wolf_skeleton",   "bonewolf"          },
}

-- Explicit id->type registrations for the creatures the mod actually raises. Mesh
-- seeding alone is not enough for these: NC_bonewolf (r\UnDeadWolf_2.nif) and
-- NC_zombie (OAAB\r\zombieFresh.nif) use meshes their vanilla anchors do not share,
-- so without this they classify as nil. Declaring them by id makes classification
-- robust and independent of whatever mesh two mods happen to ship (which is the
-- whole point of an id registry). No mesh seeding: these name specific creatures.
local registryExplicit = {
	{ "NC_bonewalker",  "bonewalker"        },
	{ "NC_BonewalkerG", "greaterBonewalker" },
	{ "NC_bonewolf",    "bonewolf"          },
	{ "NC_zombie",      "zombie"            },
	{ "NC_bonelord",    "bonelord"          },
}

undead.buildRegistry = function()
	idToType = {}
	local seedMeshes = {} -- mesh(lower) -> type
	for _, anchor in ipairs(registryAnchors) do
		local obj = tes3.getObject(anchor[1])
		if obj then
			registerType(anchor[1], anchor[2])
			if obj.mesh then
				seedMeshes[obj.mesh:lower()] = anchor[2]
			end
		end
	end
	-- The Creatures/undeads "Decayed Skeleton" (third-party, may be absent).
	registerType("skeleton_weak", "skeletonCripple")
	-- Explicit registrations for the raised NC_ creatures (id-only, no mesh seeding).
	for _, entry in ipairs(registryExplicit) do
		registerType(entry[1], entry[2])
	end
	-- Seed: any creature sharing an anchor mesh inherits that type, resolved once
	-- and stored by ID so the live lookup never touches a mesh string again.
	-- Explicit entries above are already set, so the ==nil guard below preserves them.
	for creature in tes3.iterateObjects(tes3.objectType.creature) do ---@cast creature tes3creature
		local mesh = creature.mesh and creature.mesh:lower()
		local seeded = mesh and seedMeshes[mesh]
		if seeded and idToType[creature.id:lower()] == nil then
			registerType(creature.id, seeded)
		end
	end
end

undead.getType = function(object)
	if not object then return nil end
	local base = object.baseObject or object
	local key = idToType[base.id:lower()]
	if not key then return nil end
	if key == "skeleton" then
		local level = object.level or base.level or 0
		return level >= 10 and "skeletonChampion" or "skeletonWarrior"
	end
	return key
end

-- ---------------------------------------------------------------------------
-- Minion tracking (architecture #4). State is kept in two synced places:
--
--   * Per-reference: reference.data.necroCraft.isMinion / .minionType -- the
--     authoritative record, travels and serializes with the reference. Written
--     and read through the supported tes3reference.data API, never itemData
--     (which is an item structure; a creature only stores lua data because MWSE
--     backs .data with a Variables attachment, an internal detail we don't rely
--     on). Every write is gated on supportsLuaData.
--
--   * Player-side: tes3.player.data.necroCraft.minionIndex[refId] = type -- a
--     flat, self-pruning membership index. This exists because you cannot ask
--     "is this arbitrary creature a minion?" from per-reference data without
--     tes3reference.data allocating a Variables attachment on every creature you
--     test. The index answers membership from a plain id lookup, so .data is only
--     ever read on references the index already confirms are minions.
-- ---------------------------------------------------------------------------

-- Returns the reference's necroCraft data table, or nil if it cannot hold data.
-- create=true creates the .necroCraft subtable. NOTE: reading tes3reference.data
-- itself allocates the reference's lua-data attachment on first access, so only
-- call this on references the minionIndex has already confirmed are minions (which
-- therefore already have their data), or when intentionally writing (create=true).
undead.getRefData = function(reference, create)
	if not reference or not reference.supportsLuaData then return nil end
	local data = reference.data
	if not data then return nil end
	if create then
		data.necroCraft = data.necroCraft or {}
	end
	return data.necroCraft
end

local function minionIndex(create)
	local pd = tes3.player.data.necroCraft
	if create then
		-- The player reference always supports lua data, so the index store can always
		-- be created. Guaranteeing it here is what lets markMinion write both stores
		-- atomically (see below) instead of silently orphaning a ref.data marker.
		if not pd then
			tes3.player.data.necroCraft = {}
			pd = tes3.player.data.necroCraft
		end
		pd.minionIndex = pd.minionIndex or {}
	end
	if not pd then return nil end
	return pd.minionIndex
end

local function isIndexed(reference)
	if not reference then return false end
	local index = minionIndex(false)
	return index ~= nil and index[reference.id] ~= nil
end

undead.markMinion = function(reference, utype)
	-- Both stores are written or neither is. The gating precondition is whether the
	-- reference can hold lua data at all: if getRefData fails we must NOT write the
	-- index, or isMinion (index-gated) would report a minion whose per-reference
	-- record does not exist. The index store itself is always creatable (player data).
	local nc = undead.getRefData(reference, true)
	if not nc then
		mwse.log("NecroCraft: cannot track minion, reference has no lua data: %s",
			reference and reference.id or "<nil>")
		return false
	end
	nc.isMinion = true
	nc.minionType = utype
	minionIndex(true)[reference.id] = utype or true
	return true
end

undead.unmarkMinion = function(reference)
	if not reference then return end
	-- Only touch .data if the reference was actually tracked, so we never allocate
	-- a lua-data attachment on a non-minion just to clear nothing.
	local wasIndexed = isIndexed(reference)
	local index = minionIndex(false)
	if index then index[reference.id] = nil end
	if wasIndexed then
		local nc = undead.getRefData(reference, false)
		if nc then
			nc.isMinion = nil
			nc.minionType = nil
		end
	end
end

undead.isMinion = function(reference)
	if not isIndexed(reference) then return false end -- cheap gate: no .data on non-minions
	local nc = undead.getRefData(reference, false)    -- indexed => data already exists
	if nc == nil then return true end                 -- data lost/absent: trust the index
	return nc.isMinion == true                         -- per-reference record is authoritative
end

undead.getMinionType = function(reference)
	if not isIndexed(reference) then return nil end
	local nc = undead.getRefData(reference, false)
	return (nc and nc.minionType) or minionIndex(false)[reference.id]
end

-- Iterate the player's tracked minions. fn(reference, type); return truthy to stop.
-- Resolves each indexed id; loaded-but-no-longer-a-minion entries are pruned,
-- unloaded ones are kept for a later pass. Dead minions are skipped.
undead.forEachMinion = function(fn, filterType)
	local index = minionIndex(false)
	if not index then return end
	for refId, utype in pairs(index) do
		if not filterType or utype == filterType then
			local ref = tes3.getReference(refId)
			if ref then
				if undead.isMinion(ref) then
					if not (ref.mobile and ref.mobile.isDead) then
						if fn(ref, undead.getMinionType(ref) or utype) then return end
					end
				else
					index[refId] = nil -- stale: reference is no longer a minion
				end
			end
		end
	end
end

undead.handleFollow = function(caster, raised)
	caster = caster.id and caster or tes3.getReference(caster)
	if not caster then return end
	local casterType = undead.getMinionType(caster)
	if caster == tes3.player or casterType == "bonelord" or casterType == "boneoverlord" then
		raised.mobile.fight = 0
		local utype = undead.getType(raised.object)
		tes3.setAIFollow{reference=raised, target=tes3.player}
		undead.markMinion(raised, utype)
	else
		tes3.setAIFollow{reference=raised, target=caster}
	end
end

undead.isReadyToBeRaised = function(ref)
	if not ( ref and ref.mobile and ref.object and ref.object.baseObject) then
		return false
	end
	local id = ref.object.baseObject.id
	if not string.startswith(id, "NC_skeleton") and not string.startswith(id, "NC_bone") then
		return false
	end
	if ref.data.necroCraft and ref.data.necroCraft.isBeingRaised then
		return false
	end
	return string.endswith(id, "_corpse") or string.endswith(id, "_pile")
end

undead.miscToPile = function(ref)
	if not ref then return false end
	local id = ref.id
	if not string.startswith(id, "NC_skeleton") and not string.startswith(id, "NC_bone") then return false end
	if not string.endswith(id, "_misc") then return false end
	return tes3.getObject(string.gsub(id, "_misc", "_pile"))
end

undead.pileToMisc = function(ref)
	if not ref or not ref.mobile or not ref.object or not ref.object.baseObject then return false end
	local id = ref.object.baseObject.id
	if not string.startswith(id, "NC_skeleton") and not string.startswith(id, "NC_bone") then return false end
	if not string.endswith(id, "_pile") then return false end
	return tes3.getObject(string.gsub(id, "_pile", "_misc" ))
end

undead.pileToRaised = function(ref)
	if not ref or not ref.mobile or not ref.object or not ref.object.baseObject then return false end
	local id = ref.object.baseObject.id
	if not string.startswith(id, "NC_skeleton") and not string.startswith(id, "NC_bone") then return false end
	if not string.endswith(id, "_pile") then return false end
	return tes3.getObject(string.sub(id, 1, -6))
end

undead.corpseToRaised = function(ref)
	if not ref or not ref.mobile or not ref.object or not ref.object.baseObject then return false end
	local id = ref.object.baseObject.id
	if not string.startswith(id, "NC_") then return false end
	if not string.endswith(id, "_corpse") then return false end
	return tes3.getObject(string.sub(id, 1, -8))
end

local skeletonCrippleVariants = {
	NC_skeleton_weak = true,
	NC_skeleton_weak_pile = true
}

undead.skeletonCrippleDrop = function(reference)
	if not reference.object or not reference.object.baseObject or not skeletonCrippleVariants[reference.object.baseObject.id] then
		return
	end
	timer.start{
		duration = 0.1,
		callback = function()
			for _, stack in pairs(reference.object.inventory) do
				if requiresTwoHands(stack.object) then
					tes3.dropItem{reference = reference, item = stack.object, count = stack.count}
				end
			end
		end
	}
end

undead.skeletonChampRestore = function(reference)
	if reference.object.baseObject.id ~= "NC_skeleton_champ" then
		return
	end
	local restorationChance = 75
	if math.random(1, 100) <= restorationChance then
		tes3.modStatistic{reference = reference, name = "health", current = 150, limit = true}
		tes3.modStatistic{reference = reference, name = "fatigue", current = -1001}
		timer.start{
			duration = 3,
			callback = function()
				tes3.modStatistic{reference = reference, name = "fatigue", current = 5000, limit = true}
			end
		}
	end
end

undead.isRaisedByPlayer = function(reference)
	if not (reference and reference.mobile and reference.object and reference.object.baseObject) then
		return
	end
	if reference.mobile.isDead then
		return
	end
	if not undead.isMinion(reference) then -- index-gated: no .data alloc on non-minions
		return
	end
	-- reference is a tracked minion, so its .data already exists (no new allocation)
	local nc = undead.getRefData(reference, false)
	if nc and nc.isBeingRaised then
		return
	end
	return true
end

-- Best-effort one-time migration of pre-refactor saves: the legacy global tables
-- stored minion ids in typed buckets. Re-mark any that are currently loaded, then
-- drop the legacy table. Minions in unloaded cells are not reachable here and will
-- re-register the next time they are raised/followed.
-- Consume one reference's entry (if any) from the legacy minion table and re-mark it
-- under the new system. Safe to call on every reference; no-ops once the table is gone.
-- This is the lazy half of migration: references in cells loaded after the update are
-- caught here as their mobiles activate (wired in main.lua), so nothing is lost.
undead.migrateReferenceIfLegacy = function(reference)
	local pd = tes3.player.data.necroCraft
	local legacy = pd and pd.minions
	if not legacy or not reference then return end
	local id = reference.id
	for utype, set in pairs(legacy) do
		if set[id] then
			undead.markMinion(reference, utype)
			set[id] = nil
		end
	end
	-- Drop the legacy table only once every bucket is empty (every reachable minion
	-- migrated). Entries for minions in never-visited cells linger harmlessly until
	-- (and if) those cells are ever loaded.
	for _, set in pairs(legacy) do
		if next(set) then return end
	end
	pd.minions = nil
	mwse.log("NecroCraft: legacy minion table fully migrated.")
end

-- Eager half of migration: migrate minions in currently-loaded cells immediately on
-- load, so they are tracked from the first frame. The table is NOT deleted here --
-- migrateReferenceIfLegacy deletes it once fully drained, so minions still in unloaded
-- cells survive and migrate lazily when their cell loads.
undead.migrateLegacyMinions = function()
	local legacy = tes3.player.data.necroCraft.minions
	if not legacy then return end
	for _, cell in ipairs(tes3.getActiveCells() or {}) do
		for ref in cell:iterateReferences(tes3.objectType.creature) do
			undead.migrateReferenceIfLegacy(ref)
		end
	end
end

undead.init = function()
	if tes3.player.data.necroCraft == nil then
		tes3.player.data.necroCraft = {}
	end
	undead.buildRegistry()
	undead.migrateLegacyMinions()
end

return undead
