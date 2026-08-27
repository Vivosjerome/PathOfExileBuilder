-- Unique + generated rare flasks from PoB flask bases and Flask mods.

local Candidate = require("items.candidate")
local uniqueIndex = require("items.unique_index")
local slotsMod = require("items.slots")
local resist = require("optimizer.resist")
local affixScore = require("optimizer.affix_score")
local jewelIndex = require("jewels.index")

local function reqLevel(item)
	if item.requirements and item.requirements.level then
		return item.requirements.level
	end
	return 0
end

local function indexUniques(slotNames, characterLevel)
	slotNames = slotNames or slotsMod.FLASK_SLOTS
	characterLevel = characterLevel or 90
	local all, byId = {}, {}
	for _, src in pairs(main.uniqueDB.list) do
		if src.raw then
			local item = new("Item"):Item(src.raw, "UNIQUE", true)
			if item and item.base and item.type == "Flask" and reqLevel(item) <= characterLevel then
				uniqueIndex.maximizeRolls(item)
				build.itemsTab:AddItem(item, true)
				local cand = Candidate.unique({
					name = item.name or src.name,
					slots = slotNames,
					itemId = item.id,
					item = item,
					raw = item.raw,
					itemType = "Flask",
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

local function makeScratch(baseName, base)
	local item = new("Item"):Item()
	item.baseName = baseName
	item.base = base
	item.type = "Flask"
	item.rarity = "RARE"
	item.crafted = true
	item.affixes = data.itemMods.Flask
	item.prefixes = {}
	item.suffixes = {}
	item.implicitModLines = {}
	item.explicitModLines = {}
	return item
end

local function generateRares(slotNames, maxRares)
	slotNames = slotNames or slotsMod.FLASK_SLOTS
	maxRares = maxRares or 24
	local all, byId, seen = {}, {}, {}
	for baseName, base in pairs(data.itemBases) do
		if type(base) == "table" and base.type == "Flask" and base.subType == "Utility" and not base.hidden then
			local scratch = makeScratch(baseName, base)
			local prefixes, suffixes = {}, {}
			for modId, mod in pairs(data.itemMods.Flask) do
				if type(mod) == "table" and mod.type and mod.group and mod.weightKey
					and scratch:GetModSpawnWeight(mod) > 0 then
					local scored = affixScore.scoreMod(mod)
					local row = { id = modId, mod = mod, group = mod.group, type = mod.type, score = scored }
					if mod.type == "Prefix" then
						prefixes[#prefixes + 1] = row
					elseif mod.type == "Suffix" then
						suffixes[#suffixes + 1] = row
					end
				end
			end
			table.sort(prefixes, function(a, b) return a.score.total > b.score.total end)
			table.sort(suffixes, function(a, b) return a.score.total > b.score.total end)
			local p, s = prefixes[1], suffixes[1]
			if p and s then
				local sig = baseName .. "|" .. p.id .. "|" .. s.id
				if not seen[sig] then
					seen[sig] = true
					local raw = table.concat({
						"Rarity: RARE",
						"Optimizer Flask",
						baseName,
						"Crafted: true",
						"Prefix: {range:1}" .. p.id,
						"Suffix: {range:1}" .. s.id,
					}, "\n")
					local item = new("Item"):Item(raw, "RARE", true)
					if item and item.base then
						if item.crafted and item.Craft then
							item:Craft()
						end
						uniqueIndex.maximizeRolls(item)
						build.itemsTab:AddItem(item, true)
						local cand = Candidate.generatedRare({
							id = "genflask:" .. sig,
							name = item.name or (baseName .. " " .. (p.mod.affix or "")),
							slots = slotNames,
							itemId = item.id,
							item = item,
							raw = item.raw,
							itemType = "Flask",
							base = baseName,
							prefixes = { p.id },
							suffixes = { s.id },
						})
						cand.role = "flask"
						cand.affixScore = p.score.total + s.score.total
						cand.resist = resist.fromItem(item)
						byId[cand.id] = cand
						all[#all + 1] = cand
					end
				end
			end
		end
	end
	table.sort(all, function(a, b) return (a.affixScore or 0) > (b.affixScore or 0) end)
	if #all > maxRares then
		local kept = {}
		for i = 1, maxRares do
			kept[i] = all[i]
		end
		all = kept
		byId = {}
		for _, cand in ipairs(all) do
			byId[cand.id] = cand
		end
	end
	return { all = all, byId = byId, stats = { installed = #all } }
end

local function prepare(catalog, params)
	params = params or {}
	local slots = slotsMod.FLASK_SLOTS
	jewelIndex.ensureSlots(catalog, slots)
	local uniques = indexUniques(slots, params.characterLevel)
	local rares = generateRares(slots, params.maxRares or 24)
	local nU = jewelIndex.addCandidates(catalog, uniques)
	local nR = jewelIndex.addCandidates(catalog, rares)
	resist.buildSlotMax(catalog)
	return {
		slotNames = slots,
		uniquesInstalled = nU,
		raresInstalled = nR,
	}
end

return {
	prepare = prepare,
}
