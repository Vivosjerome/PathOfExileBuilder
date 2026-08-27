-- Cluster jewels from PoB cluster jewel skills + JewelCluster notables.
-- Unique clusters included. Nested medium/small crafts are left as socketed uniques.

local Candidate = require("items.candidate")
local uniqueIndex = require("items.unique_index")
local resist = require("optimizer.resist")
local affixScore = require("optimizer.affix_score")
local sockets = require("jewels.sockets")
local jewelIndex = require("jewels.index")

local UNAVAILABLE = {
	affliction_strength = true,
	affliction_dexterity = true,
	affliction_intelligence = true,
}

local function reqLevel(item)
	if item.requirements and item.requirements.level then
		return item.requirements.level
	end
	return 0
end

local function indexUniques(slotNames, characterLevel)
	local all, byId = {}, {}
	for _, src in pairs(main.uniqueDB.list) do
		if src.base and src.type == "Jewel" then
			local item = new("Item"):Item(src.raw, "UNIQUE", true)
			if item and item.base and (item.clusterJewel or (item.base.subType == "Cluster"))
				and reqLevel(item) <= (characterLevel or 90) then
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

local function craftLarge(skillId, skill, notableIds, title)
	local lines = {
		"Rarity: RARE",
		title or "Optimizer Cluster",
		"Large Cluster Jewel",
		"Crafted: true",
		"Adds 12 Passive Skills",
		"2 Added Passive Skills are Jewel Sockets",
	}
	if skill.enchant then
		for _, line in ipairs(skill.enchant) do
			lines[#lines + 1] = line
		end
	end
	for _, id in ipairs(notableIds) do
		lines[#lines + 1] = "Prefix: {range:1}" .. id
	end
	local raw = table.concat(lines, "\n")
	local item = new("Item"):Item(raw, "RARE", true)
	if not item or not item.base then
		return nil
	end
	if item.crafted and item.Craft then
		item:Craft()
	end
	uniqueIndex.maximizeRolls(item)
	if item.BuildModList then
		item:BuildModList()
	end
	return item
end

local function generateRares(slotNames, maxRares)
	maxRares = maxRares or 24
	local jewel = data.clusterJewels and data.clusterJewels.jewels and data.clusterJewels.jewels["Large Cluster Jewel"]
	if not jewel then
		return { all = {}, byId = {}, stats = { installed = 0 } }
	end
	local base = data.itemBases["Large Cluster Jewel"]
	local all, byId = {}, {}
	for skillId, skill in pairs(jewel.skills) do
		if not UNAVAILABLE[skillId] then
			local scratch = new("Item"):Item()
			scratch.baseName = "Large Cluster Jewel"
			local baseCopy = {}
			for k, v in pairs(base or {}) do
				baseCopy[k] = v
			end
			if type(base and base.tags) == "table" then
				local tags = {}
				for k, v in pairs(base.tags) do
					tags[k] = v
				end
				if skill.tag then
					tags[skill.tag] = true
				end
				baseCopy.tags = tags
			end
			scratch.base = baseCopy
			scratch.type = "Jewel"
			scratch.rarity = "RARE"
			scratch.clusterJewel = jewel
			scratch.clusterJewelSkill = skillId
			scratch.affixes = data.itemMods.JewelCluster
			local notables = {}
			for modId, mod in pairs(data.itemMods.JewelCluster) do
				if type(mod) == "table" and (mod.type == "Prefix" or mod.type == "Suffix")
					and mod.group and mod.weightKey
					and scratch:GetModSpawnWeight(mod) > 0 then
					local scored = affixScore.scoreMod(mod)
					notables[#notables + 1] = { id = modId, group = mod.group, score = scored, type = mod.type }
				end
			end
			table.sort(notables, function(a, b) return a.score.total > b.score.total end)
			local used, ids = {}, {}
			for _, row in ipairs(notables) do
				if not used[row.group] then
					used[row.group] = true
					ids[#ids + 1] = row.id
					if #ids >= 2 then
						break
					end
				end
			end
			if #ids > 0 then
				local item = craftLarge(skillId, skill, ids, "Cluster " .. (skill.name or skillId))
				if item then
					build.itemsTab:AddItem(item, true)
					local cand = Candidate.generatedRare({
						id = "cluster:" .. skillId .. ":" .. table.concat(ids, "+"),
						name = item.name or ("Large Cluster " .. skill.name),
						slots = slotNames,
						itemId = item.id,
						item = item,
						raw = item.raw,
						itemType = "Jewel",
						base = "Large Cluster Jewel",
						prefixes = ids,
					})
					cand.role = skill.name
					cand.resist = resist.fromItem(item)
					byId[cand.id] = cand
					all[#all + 1] = cand
				end
			end
		end
	end
	table.sort(all, function(a, b)
		if (a.affixScore or 0) == (b.affixScore or 0) then
			return a.name < b.name
		end
		return (a.affixScore or 0) > (b.affixScore or 0)
	end)
	if #all > maxRares then
		local kept, newById = {}, {}
		for i = 1, maxRares do
			kept[i] = all[i]
			newById[all[i].id] = all[i]
		end
		all, byId = kept, newById
	end
	return { all = all, byId = byId, stats = { installed = #all } }
end

local function prepare(catalog, params)
	params = params or {}
	local allocated = sockets.allocateNearestLarge({
		maxSockets = params.maxSockets or 2,
		maxPoints = params.maxPoints or 28,
	})
	if #allocated.slotNames == 0 then
		return allocated
	end
	jewelIndex.ensureSlots(catalog, allocated.slotNames)
	local uniqueSet = indexUniques(allocated.slotNames, params.characterLevel)
	allocated.uniquesInstalled = jewelIndex.addCandidates(catalog, uniqueSet)
	local rareSet = generateRares(allocated.slotNames, params.maxRares or 24)
	allocated.raresInstalled = jewelIndex.addCandidates(catalog, rareSet)
	resist.buildSlotMax(catalog)
	return allocated
end

return {
	prepare = prepare,
}
