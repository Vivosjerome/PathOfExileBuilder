-- Tree notables / keystones and ascendancy notables from the live PoB tree.

local Candidate = require("items.candidate")
local slotsMod = require("items.slots")
local jewelIndex = require("jewels.index")
local affixScore = require("optimizer.affix_score")

local function nodeText(node)
	local parts = { node.name or "" }
	if node.sd then
		for _, line in ipairs(node.sd) do
			parts[#parts + 1] = line
		end
	end
	return table.concat(parts, "\n")
end

local function indexMainTree(slotNames)
	slotNames = slotNames or slotsMod.treeSlotNames(8)
	local spec = build.spec
	spec:BuildAllDependsAndPaths()
	local all, byId = {}, {}
	for _, node in pairs(spec.nodes) do
		if node and not node.ascendancyName
			and (node.isNotable or node.isKeystone)
			and node.type ~= "Mastery"
			and node.type ~= "ClassStart"
			and node.type ~= "AscendClassStart" then
			local scored = affixScore.scoreText(nodeText(node))
			local cand = Candidate.notable({
				id = "node:" .. tostring(node.id),
				name = node.name or ("Node " .. node.id),
				slots = slotNames,
				nodeId = node.id,
				isKeystone = node.isKeystone,
			})
			cand.affixScore = scored.total
			byId[cand.id] = cand
			all[#all + 1] = cand
		end
	end
	table.sort(all, function(a, b)
		if (a.affixScore or 0) == (b.affixScore or 0) then
			return (a.name or "") < (b.name or "")
		end
		return (a.affixScore or 0) > (b.affixScore or 0)
	end)
	if #all > 60 then
		local kept, newById = {}, {}
		for i = 1, 60 do
			kept[i] = all[i]
			newById[all[i].id] = all[i]
		end
		all, byId = kept, newById
	end
	return { all = all, byId = byId, stats = { installed = #all } }
end

local function indexAscendancy(slotNames)
	slotNames = slotNames or slotsMod.ascendSlotNames(4)
	local spec = build.spec
	local name = spec.curAscendClassName
	local all, byId = {}, {}
	if not name or name == "" or name == "None" then
		return { all = all, byId = byId, stats = { installed = 0 } }
	end
	spec:BuildAllDependsAndPaths()
	for _, node in pairs(spec.nodes) do
		if node and node.ascendancyName == name and node.isNotable then
			local scored = affixScore.scoreText(nodeText(node))
			local cand = Candidate.notable({
				id = "ascend:" .. tostring(node.id),
				name = node.name or ("Ascend " .. node.id),
				slots = slotNames,
				nodeId = node.id,
				ascendancy = name,
			})
			cand.affixScore = scored.total
			byId[cand.id] = cand
			all[#all + 1] = cand
		end
	end
	table.sort(all, function(a, b)
		if (a.affixScore or 0) == (b.affixScore or 0) then
			return (a.name or "") < (b.name or "")
		end
		return (a.affixScore or 0) > (b.affixScore or 0)
	end)
	return { all = all, byId = byId, stats = { installed = #all } }
end

local function prepare(catalog, params)
	params = params or {}
	local treeSlots = slotsMod.treeSlotNames(params.treePicks or 8)
	local ascSlots = slotsMod.ascendSlotNames(params.ascendPicks or 4)
	local treeSet, ascSet
	if params.includeTree ~= false then
		jewelIndex.ensureSlots(catalog, treeSlots)
		treeSet = indexMainTree(treeSlots)
		jewelIndex.addCandidates(catalog, treeSet)
	end
	if params.includeAscendancy ~= false then
		jewelIndex.ensureSlots(catalog, ascSlots)
		ascSet = indexAscendancy(ascSlots)
		jewelIndex.addCandidates(catalog, ascSet)
	end
	return {
		treeSlots = treeSlots,
		ascendSlots = ascSlots,
		treeCount = treeSet and treeSet.stats.installed or 0,
		ascendCount = ascSet and ascSet.stats.installed or 0,
	}
end

return {
	prepare = prepare,
	indexMainTree = indexMainTree,
	indexAscendancy = indexAscendancy,
}
