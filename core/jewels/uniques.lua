-- Unique classic jewels (Cobalt / Viridian / Crimson / Prismatic and similar).
-- Cluster, Timeless, Abyss, and Charm jewels are skipped.

local Candidate = require("items.candidate")
local uniqueIndex = require("items.unique_index")
local resist = require("optimizer.resist")

local SKIP_SUBTYPE = {
	Cluster = true,
	Timeless = true,
	Abyss = true,
	Charm = true,
}

local function isClassicUniqueJewel(item)
	if not item or item.type ~= "Jewel" or not item.base then
		return false
	end
	if item.clusterJewel then
		return false
	end
	local sub = item.base.subType
	if sub and SKIP_SUBTYPE[sub] then
		return false
	end
	local baseName = item.baseName or ""
	if baseName:find("Cluster", 1, true) or baseName == "Timeless Jewel" then
		return false
	end
	return true
end

local function reqLevel(item)
	if item.requirements and item.requirements.level then
		return item.requirements.level
	end
	return 0
end

local function index(slotNames, characterLevel)
	slotNames = slotNames or {}
	characterLevel = characterLevel or (build and build.characterLevel) or 90
	local all, byId = {}, {}
	local skippedSubtype, skippedLevel, skippedNoBase = 0, 0, 0
	if #slotNames == 0 then
		return {
			all = all,
			byId = byId,
			stats = {
				installed = 0,
				skippedSubtype = 0,
				skippedLevel = 0,
				skippedNoBase = 0,
			},
		}
	end

	for _, src in pairs(main.uniqueDB.list) do
		if not src.base then
			skippedNoBase = skippedNoBase + 1
		else
			local item = new("Item"):Item(src.raw, "UNIQUE", true)
			if not item or not item.base then
				skippedNoBase = skippedNoBase + 1
			elseif not isClassicUniqueJewel(item) then
				skippedSubtype = skippedSubtype + 1
			elseif reqLevel(item) > characterLevel then
				skippedLevel = skippedLevel + 1
			else
				uniqueIndex.maximizeRolls(item)
				build.itemsTab:AddItem(item, true)
				local cand = Candidate.unique({
					name = item.name or src.name,
					slots = slotNames,
					itemId = item.id,
					item = item,
					raw = item.raw,
					itemType = item.type,
					reqLevel = reqLevel(item),
				})
				cand.base = item.baseName
				cand.resist = resist.fromItem(item)
				byId[cand.id] = cand
				all[#all + 1] = cand
			end
		end
	end

	table.sort(all, function(a, b)
		return a.name < b.name
	end)
	return {
		all = all,
		byId = byId,
		stats = {
			installed = #all,
			skippedSubtype = skippedSubtype,
			skippedLevel = skippedLevel,
			skippedNoBase = skippedNoBase,
		},
	}
end

return {
	isClassicUniqueJewel = isClassicUniqueJewel,
	index = index,
}
