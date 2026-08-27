-- Complete build state the search mutates.
-- Gear is implemented. Jewels / gems / flasks / tree are stored so later
-- dimensions plug into the same object instead of a new model.

local slotsMod = require("items.slots")

local function emptyGear()
	local gear = {}
	for _, slot in ipairs(slotsMod.GEAR_SLOTS) do
		gear[slot] = nil
	end
	return gear
end

local function new(def)
	def = def or {}
	return {
		class = def.class,
		ascendancy = def.ascendancy,
		level = def.level,
		skill = def.skill,
		gear = emptyGear(),
		jewels = {},
		flasks = { nil, nil, nil, nil, nil },
		gems = {
			groups = {},
		},
		tree = {
			nodes = {},
			masteries = {},
			pointsUsed = 0,
		},
		config = def.config or {},
	}
end

local function fromLoadout(def, loadout)
	local state = new(def)
	local slotsMod = require("items.slots")
	for slot, candId in pairs(loadout or {}) do
		if slotsMod.isJewelSlot(slot) then
			state.jewels[slot] = candId
		else
			state.gear[slot] = candId
		end
	end
	return state
end

return {
	new = new,
	fromLoadout = fromLoadout,
	emptyGear = emptyGear,
}
