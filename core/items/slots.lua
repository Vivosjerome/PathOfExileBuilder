-- Gear slots searched in this phase. Jewel sockets are appended at runtime
-- as "Jewel <nodeId>" once the tree allocates them.

local GEAR_SLOTS = {
	"Helmet",
	"Gloves",
	"Boots",
	"Body Armour",
	"Amulet",
	"Ring 1",
	"Ring 2",
	"Belt",
	"Weapon 1",
	"Weapon 2",
}

local function isGearSlot(slotName)
	for _, name in ipairs(GEAR_SLOTS) do
		if name == slotName then
			return true
		end
	end
	return false
end

local FLASK_SLOTS = {
	"Flask 1", "Flask 2", "Flask 3", "Flask 4", "Flask 5",
}

local SUPPORT_SLOTS = {
	"Support 1", "Support 2", "Support 3", "Support 4", "Support 5",
}

local AURA_SLOTS = {
	"Aura 1", "Aura 2",
}

local function isJewelSlot(slotName)
	return type(slotName) == "string" and slotName:match("^Jewel ") ~= nil
end

local function isFlaskSlot(slotName)
	return type(slotName) == "string" and slotName:match("^Flask ") ~= nil
end

local function isSupportSlot(slotName)
	return type(slotName) == "string" and slotName:match("^Support ") ~= nil
end

local function isAuraSlot(slotName)
	return type(slotName) == "string" and slotName:match("^Aura ") ~= nil
end

local function isTreeSlot(slotName)
	return type(slotName) == "string" and slotName:match("^Tree ") ~= nil
end

local function isAscendSlot(slotName)
	return type(slotName) == "string" and slotName:match("^Ascendancy ") ~= nil
end

local function treeSlotNames(n)
	n = n or 8
	local out = {}
	for i = 1, n do
		out[i] = "Tree " .. i
	end
	return out
end

local function ascendSlotNames(n)
	n = n or 4
	local out = {}
	for i = 1, n do
		out[i] = "Ascendancy " .. i
	end
	return out
end

local function copy(list)
	local out = {}
	for i, name in ipairs(list or GEAR_SLOTS) do
		out[i] = name
	end
	return out
end

local function append(list, extra)
	local out = copy(list)
	for _, name in ipairs(extra or {}) do
		out[#out + 1] = name
	end
	return out
end

return {
	GEAR_SLOTS = GEAR_SLOTS,
	FLASK_SLOTS = FLASK_SLOTS,
	SUPPORT_SLOTS = SUPPORT_SLOTS,
	AURA_SLOTS = AURA_SLOTS,
	isGearSlot = isGearSlot,
	isJewelSlot = isJewelSlot,
	isFlaskSlot = isFlaskSlot,
	isSupportSlot = isSupportSlot,
	isAuraSlot = isAuraSlot,
	isTreeSlot = isTreeSlot,
	isAscendSlot = isAscendSlot,
	treeSlotNames = treeSlotNames,
	ascendSlotNames = ascendSlotNames,
	copy = copy,
	append = append,
}
