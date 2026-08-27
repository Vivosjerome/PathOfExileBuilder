local Candidate = require("items.candidate")
local slotsMod = require("items.slots")
local resist = require("optimizer.resist")

local EMPTY = Candidate.empty()

local function maximizeRolls(item)
	local function bump(lines)
		if not lines then
			return
		end
		for _, line in ipairs(lines) do
			if line.line and line.line:find("%(%-?[%d%.]+%-%-?[%d%.]+%)") then
				line.range = 1
			end
		end
	end
	bump(item.explicitModLines)
	bump(item.implicitModLines)
	bump(item.enchantModLines)
	bump(item.scourgeModLines)
	bump(item.crucibleModLines)
	if item.BuildModList then
		item:BuildModList()
	end
end

local function slotsForItem(item)
	if not item or not item.base then
		return {}
	end
	local itemType = item.type
	if itemType == "Ring" then
		return { "Ring 1", "Ring 2" }
	end
	if itemType == "Shield" or itemType == "Quiver" then
		return { "Weapon 2" }
	end
	if item.base.weapon then
		local info = data.weaponTypeInfo and data.weaponTypeInfo[itemType]
		if info and info.oneHand then
			return { "Weapon 1", "Weapon 2" }
		end
		return { "Weapon 1" }
	end
	for _, slotName in ipairs(slotsMod.GEAR_SLOTS) do
		if itemType == slotName then
			return { slotName }
		end
	end
	return {}
end

local function reqLevel(item)
	if item.requirements and item.requirements.level then
		return item.requirements.level
	end
	return 0
end

local function indexUniques(characterLevel)
	characterLevel = characterLevel or (build and build.characterLevel) or 90
	local bySlot = {}
	for _, slotName in ipairs(slotsMod.GEAR_SLOTS) do
		bySlot[slotName] = {}
	end
	local byId = { [EMPTY.id] = EMPTY }
	local all = {}
	local skippedNoBase = 0
	local skippedNoSlot = 0
	local skippedLevel = 0

	for _, src in pairs(main.uniqueDB.list) do
		if not src.base then
			skippedNoBase = skippedNoBase + 1
		else
			local item = new("Item"):Item(src.raw, "UNIQUE", true)
			if not item.base then
				skippedNoBase = skippedNoBase + 1
			else
				maximizeRolls(item)
				local compatible = slotsForItem(item)
				if #compatible == 0 then
					skippedNoSlot = skippedNoSlot + 1
				elseif reqLevel(item) > characterLevel then
					skippedLevel = skippedLevel + 1
				else
					build.itemsTab:AddItem(item, true)
					local cand = Candidate.unique({
						name = item.name or src.name,
						slots = compatible,
						itemId = item.id,
						item = item,
						raw = item.raw,
						itemType = item.type,
						reqLevel = reqLevel(item),
					})
					cand.resist = resist.fromItem(item)
					byId[cand.id] = cand
					all[#all + 1] = cand
					for _, slotName in ipairs(compatible) do
						if bySlot[slotName] then
							bySlot[slotName][#bySlot[slotName] + 1] = cand
						end
					end
				end
			end
		end
	end

	for _, slotName in ipairs(slotsMod.GEAR_SLOTS) do
		table.sort(bySlot[slotName], function(a, b)
			return a.name < b.name
		end)
	end
	table.sort(all, function(a, b)
		return a.name < b.name
	end)

	EMPTY.resist = { fire = 0, cold = 0, lightning = 0 }
	local slotOrder = {}
	for _, slotName in ipairs(slotsMod.GEAR_SLOTS) do
		slotOrder[#slotOrder + 1] = slotName
	end
	local catalog = {
		bySlot = bySlot,
		byId = byId,
		all = all,
		empty = EMPTY,
		slotOrder = slotOrder,
		stats = {
			installed = #all,
			skippedNoBase = skippedNoBase,
			skippedNoSlot = skippedNoSlot,
			skippedLevel = skippedLevel,
		},
	}
	resist.buildSlotMax(catalog)
	return catalog
end

return {
	EMPTY = EMPTY,
	indexUniques = indexUniques,
	slotsForItem = slotsForItem,
	maximizeRolls = maximizeRolls,
}
