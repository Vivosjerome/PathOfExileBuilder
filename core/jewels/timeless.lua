-- Timeless unique jewels from PoB uniqueDB, socketed in classic jewel slots.
-- Seeds/conquerors come from the unique variants PoB already stores.

local Candidate = require("items.candidate")
local uniqueIndex = require("items.unique_index")
local resist = require("optimizer.resist")
local jewelIndex = require("jewels.index")

local function reqLevel(item)
	if item.requirements and item.requirements.level then
		return item.requirements.level
	end
	return 0
end

local function isTimeless(item)
	if not item or item.type ~= "Jewel" or not item.base then
		return false
	end
	return item.base.subType == "Timeless" or item.baseName == "Timeless Jewel"
end

local function index(slotNames, characterLevel)
	local all, byId = {}, {}
	for _, src in pairs(main.uniqueDB.list) do
		if src.base then
			local item = new("Item"):Item(src.raw, "UNIQUE", true)
			if item and isTimeless(item) and reqLevel(item) <= (characterLevel or 90) then
				uniqueIndex.maximizeRolls(item)
				build.itemsTab:AddItem(item, true)
				local cand = Candidate.unique({
					name = item.name or src.name,
					slots = slotNames,
					itemId = item.id,
					item = item,
					raw = item.raw,
					itemType = "Jewel",
					reqLevel = reqLevel(item),
				})
				cand.base = item.baseName
				cand.resist = resist.fromItem(item)
				byId[cand.id] = cand
				all[#all + 1] = cand
			end
		end
	end
	table.sort(all, function(a, b) return a.name < b.name end)
	return { all = all, byId = byId, stats = { installed = #all } }
end

local function prepare(catalog, slotNames, params)
	params = params or {}
	if not slotNames or #slotNames == 0 then
		return { installed = 0 }
	end
	jewelIndex.ensureSlots(catalog, slotNames)
	local set = index(slotNames, params.characterLevel)
	local added = jewelIndex.addCandidates(catalog, set)
	resist.buildSlotMax(catalog)
	return { installed = added, stats = set.stats }
end

return {
	prepare = prepare,
	index = index,
}
