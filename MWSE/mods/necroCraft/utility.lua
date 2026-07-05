-- Utility functions

local utility = {}

utility.getNecromanticSpellBonus = function (spell, shade)
	if not spell then return 0 end
    for _, effect in ipairs(spell.effects) do
        -- Spells with corrupt soulgem effects do not work at all without the Shade of the Revenant
        if not shade then
            if effect.id == 670 then
                return -99999999
            end
        -- Necromantic spells are easier to cast during the Shade of the Revenant
        elseif effect.id > 656 and effect.id < 674 then
            if shade then
                return spell.magickaCost*0.6
            end
        end
    end
	return 0
end

utility.isShade = function()
    if tes3.worldController.daysPassed.value%8 ~= 0 then
        return false
    end
	return (tes3.worldController.hour.value <= 6 or tes3.worldController.hour.value >= 21)
end

utility.safeDelete = function(reference)
    reference:disable()
    timer.delayOneFrame(function()
        reference:delete()
    end)
end

utility.disposeCorpse = function(reference)
	local controlPressed = tes3.worldController.inputController:isKeyDown(tes3.scanCode.lCtrl)
	if not tes3.hasCodePatchFeature(107) or not controlPressed then
		local inventory =  reference.object.inventory
		for _, stack in pairs(inventory) do
			local item = stack.object.id
			tes3.transferItem{from = reference, to = tes3.mobilePlayer, count = stack.count, item = item, limitCapacity=false}
		end
	end
	utility.safeDelete(reference)
end

utility.logMinions = function()
	-- Reads the flat per-player index maintained by undead.markMinion/unmarkMinion.
	-- Kept dependency-free (utility must not require undead) so this stays a debug helper.
	local pd = tes3.player.data.necroCraft
	local index = pd and pd.minionIndex
	mwse.log("\nMINIONS:")
	if not index then return end
	for minionId, utype in pairs(index) do
		mwse.log("%s: %s", tostring(utype), minionId)
	end
end


utility.replace = function(old, newRef, cell)
	local new = tes3.createReference{object = newRef, position=old.position, orientation=old.orientation, cell=cell}
	new.scale = old.scale
	new.stackSize = old.stackSize
	if old.data and old.data.necroCraft then
		new.data.necroCraft = old.data.necroCraft
		new.data.necroCraft.isBeingRaised = nil
	end

	local owner = tes3.getOwner(old)

	if owner then
		tes3.setOwner({
			reference = new,
			owner = owner,
		})
	end

	if old.object.inventory then
		for _, stack in pairs(old.object.inventory) do
			tes3.transferItem{from=old, to=new, item=stack.object, count=stack.count, playSound=false}
		end
	end
	utility.safeDelete(old)
	return new
end

utility.placeInFront = function(reference, object, distance)
	local vec = tes3vector3.new(0,1,0)
	local mat = reference.sceneNode.worldTransform.rotation
	local position = reference.position + (mat * vec * distance)
	return tes3.createReference{object = object, count = 1, position = position, orientation = {0,0,0}, cell = tes3.getPlayerCell()}
end

local function applyReplacer(params)
	local object = params.object
	local mesh = params.mesh
	local replacer = params.replacer
	if type(object) == "string" then
		object = tes3.getObject(object)
	end
	if not mesh then
		if type(replacer) == "string" then
			replacer = tes3.getObject(replacer)
		end
		mesh = replacer.mesh
	end
	object.mesh = mesh
end

utility.ashPitReplacer = function()
	applyReplacer({object = "nc_ashpit_01", replacer = "in_velothi_ashpit_01"})
	applyReplacer({object = "nc_ashpit_02", replacer = "in_velothi_ashpit_02"})
	applyReplacer({object = "nc_ashpit_r_01", replacer = "in_redoran_ashpit_01"})
	applyReplacer({object = "nc_ashpit_r_02", replacer = "in_redoran_ashpit_02"})
end

-- NOTE (architecture #2/#3): world skeletons are no longer visually unified with
-- Necrocraft's meshes. The former mechanisms -- a runtime base-mesh mutation
-- (skeletonReplacer) and its later replacement, a live reference swap -- are both
-- gone. The mesh mutation was the direct cause of the "no Animation class!" CTD,
-- and neither is needed for behaviour: undead.getType classifies skeletons by ID
-- now, so harvesting/raising work on the untouched creatures. If the cosmetic
-- unification is wanted back, it belongs in a load-ordered patch .esp that edits
-- the creatures' MODL, not in runtime Lua.

return utility
