-- Generate legal max-roll rare jewels from PoB jewel affixes.
-- Classic jewels are 2 prefix + 2 suffix, not the 3+3 gear pool.

local Candidate = require("items.candidate")
local uniqueIndex = require("items.unique_index")
local resist = require("optimizer.resist")
local affixScore = require("optimizer.affix_score")

local CLASSIC_BASES = {
	"Cobalt Jewel",
	"Viridian Jewel",
	"Crimson Jewel",
	"Prismatic Jewel",
}

local function makeScratch(baseName, base)
	local item = new("Item"):Item()
	item.baseName = baseName
	item.base = base
	item.type = base.type
	item.rarity = "RARE"
	item.crafted = true
	item.affixes = data.itemMods.Jewel
	item.prefixes = {}
	item.suffixes = {}
	item.implicitModLines = {}
	item.explicitModLines = {}
	return item
end

local function compatibleMods(scratch, itemLevel)
	local prefixes, suffixes = {}, {}
	local jewelMods = data.itemMods.Jewel
	for modId, mod in pairs(jewelMods) do
		if type(mod) == "table" and mod.type and mod.group and mod.weightKey
			and (mod.level or 0) <= itemLevel
			and (not scratch.CheckIfModIsDelve or not scratch:CheckIfModIsDelve(mod))
			and scratch:GetModSpawnWeight(mod) > 0 then
			local scored = affixScore.scoreMod(mod)
			local row = {
				id = modId,
				mod = mod,
				group = mod.group,
				type = mod.type,
				level = mod.level or 0,
				score = scored,
			}
			if mod.type == "Prefix" then
				prefixes[#prefixes + 1] = row
			elseif mod.type == "Suffix" then
				suffixes[#suffixes + 1] = row
			end
		end
	end
	local function bestPerGroup(list)
		local best = {}
		for _, row in ipairs(list) do
			local prev = best[row.group]
			if not prev or row.level > prev.level or (row.level == prev.level and row.score.total > prev.score.total) then
				best[row.group] = row
			end
		end
		local out = {}
		for _, row in pairs(best) do
			out[#out + 1] = row
		end
		return out
	end
	return {
		prefixes = bestPerGroup(prefixes),
		suffixes = bestPerGroup(suffixes),
	}
end

local function sortBy(list, getter)
	table.sort(list, function(a, b)
		local sa, sb = getter(a), getter(b)
		if sa == sb then
			return a.id < b.id
		end
		return sa > sb
	end)
	return list
end

local function copy(list)
	local out = {}
	for i, v in ipairs(list) do
		out[i] = v
	end
	return out
end

local function pick(ranked, n, used, pred)
	local out = {}
	for _, row in ipairs(ranked) do
		if not used[row.group] and (not pred or pred(row)) then
			used[row.group] = true
			out[#out + 1] = row
			if #out >= n then
				break
			end
		end
	end
	return out
end

local function idsOf(rows)
	local ids = {}
	for _, row in ipairs(rows) do
		ids[#ids + 1] = row.id
	end
	return ids
end

local function signature(baseName, prefixIds, suffixIds)
	local p = copy(prefixIds)
	local s = copy(suffixIds)
	table.sort(p)
	table.sort(s)
	return baseName .. "|" .. table.concat(p, "+") .. "|" .. table.concat(s, "+")
end

local function craftJewel(baseName, prefixIds, suffixIds, title)
	local lines = {
		"Rarity: RARE",
		title or "Optimizer Jewel",
		baseName,
		"Crafted: true",
	}
	for _, id in ipairs(prefixIds) do
		lines[#lines + 1] = "Prefix: {range:1}" .. id
	end
	for _, id in ipairs(suffixIds) do
		lines[#lines + 1] = "Suffix: {range:1}" .. id
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
	return item, raw
end

local function templatesFor(pool)
	local prefixes = copy(pool.prefixes)
	local suffixes = copy(pool.suffixes)
	sortBy(prefixes, function(r) return r.score.offense end)
	sortBy(suffixes, function(r) return r.score.offense end)
	local sRes = copy(pool.suffixes)
	local pLife = copy(pool.prefixes)
	sortBy(sRes, function(r) return r.score.resist end)
	sortBy(pLife, function(r) return r.score.life end)

	local function coldish(row)
		return affixScore.hasTag(row.mod, "cold") or affixScore.lineMatches(row.mod, "[Cc]old")
	end
	local function critish(row)
		return affixScore.hasTag(row.mod, "critical") or affixScore.lineMatches(row.mod, "[Cc]ritical")
	end
	local function speedish(row)
		return affixScore.hasTag(row.mod, "speed") or affixScore.lineMatches(row.mod, "[Ss]peed")
	end
	local function casterish(row)
		return affixScore.hasTag(row.mod, "caster")
			or affixScore.hasTag(row.mod, "caster_damage")
			or affixScore.lineMatches(row.mod, "[Ss]pell")
	end

	local plans = {}
	local function plan(name, buildFn)
		plans[#plans + 1] = { name = name, build = buildFn }
	end

	plan("offense", function()
		local used = {}
		local p = pick(prefixes, 2, used, casterish)
		if #p < 2 then
			for _, row in ipairs(pick(prefixes, 2 - #p, used)) do p[#p + 1] = row end
		end
		local s = pick(suffixes, 2, used, casterish)
		if #s < 2 then
			for _, row in ipairs(pick(suffixes, 2 - #s, used)) do s[#s + 1] = row end
		end
		return p, s
	end)
	plan("hybrid", function()
		local used = {}
		local p = pick(prefixes, 1, used, casterish)
		for _, row in ipairs(pick(pLife, 1, used)) do p[#p + 1] = row end
		if #p < 2 then
			for _, row in ipairs(pick(prefixes, 2 - #p, used)) do p[#p + 1] = row end
		end
		local s = pick(sRes, 1, used)
		for _, row in ipairs(pick(suffixes, 1, used, casterish)) do s[#s + 1] = row end
		if #s < 2 then
			for _, row in ipairs(pick(suffixes, 2 - #s, used)) do s[#s + 1] = row end
		end
		return p, s
	end)
	plan("cap", function()
		local used = {}
		local p = pick(prefixes, 2, used, casterish)
		if #p < 2 then
			for _, row in ipairs(pick(prefixes, 2 - #p, used)) do p[#p + 1] = row end
		end
		return p, pick(sRes, 2, used)
	end)
	plan("cold", function()
		local used = {}
		local p = pick(prefixes, 2, used, coldish)
		if #p < 2 then
			for _, row in ipairs(pick(prefixes, 2 - #p, used)) do p[#p + 1] = row end
		end
		local s = pick(suffixes, 2, used, coldish)
		if #s < 2 then
			for _, row in ipairs(pick(suffixes, 2 - #s, used)) do s[#s + 1] = row end
		end
		return p, s
	end)
	plan("crit", function()
		local used = {}
		local p = pick(prefixes, 2, used, critish)
		if #p < 2 then
			for _, row in ipairs(pick(prefixes, 2 - #p, used)) do p[#p + 1] = row end
		end
		local s = pick(suffixes, 2, used, critish)
		if #s < 2 then
			for _, row in ipairs(pick(suffixes, 2 - #s, used)) do s[#s + 1] = row end
		end
		return p, s
	end)
	plan("speed", function()
		local used = {}
		local p = pick(prefixes, 2, used, casterish)
		if #p < 2 then
			for _, row in ipairs(pick(prefixes, 2 - #p, used)) do p[#p + 1] = row end
		end
		local s = pick(suffixes, 2, used, speedish)
		if #s < 2 then
			for _, row in ipairs(pick(suffixes, 2 - #s, used)) do s[#s + 1] = row end
		end
		return p, s
	end)
	plan("discovery", function()
		local used = {}
		local pRank, sRank = copy(prefixes), copy(suffixes)
		sortBy(pRank, function(r) return r.score.total end)
		sortBy(sRank, function(r) return r.score.total end)
		local function skipTop(list, skip, n, usedGroups)
			local out, seen = {}, 0
			for _, row in ipairs(list) do
				if not usedGroups[row.group] then
					seen = seen + 1
					if seen > skip then
						usedGroups[row.group] = true
						out[#out + 1] = row
						if #out >= n then
							break
						end
					end
				end
			end
			return out
		end
		return skipTop(pRank, 2, 2, used), skipTop(sRank, 2, 2, used)
	end)

	return plans
end

local function comboScore(prefixRows, suffixRows)
	local s = 0
	for _, row in ipairs(prefixRows) do
		s = s + row.score.total
	end
	for _, row in ipairs(suffixRows) do
		s = s + row.score.total
	end
	return s
end

local function generate(params)
	params = params or {}
	local slotNames = params.slots or {}
	local itemLevel = params.itemLevel or 100
	local maxRares = params.maxRares or 40
	local all, byId = {}, {}
	local seenSig = {}
	local crafted, failed = 0, 0
	if #slotNames == 0 then
		return {
			all = all,
			byId = byId,
			stats = { crafted = 0, failed = 0, installed = 0 },
		}
	end

	for _, baseName in ipairs(CLASSIC_BASES) do
		local base = data.itemBases[baseName]
		if type(base) == "table" then
			local scratch = makeScratch(baseName, base)
			local pool = compatibleMods(scratch, itemLevel)
			if #pool.prefixes > 0 and #pool.suffixes > 0 then
				for _, plan in ipairs(templatesFor(pool)) do
					local prefixRows, suffixRows = plan.build()
					if #prefixRows > 0 and #suffixRows > 0 then
						local prefixIds = idsOf(prefixRows)
						local suffixIds = idsOf(suffixRows)
						local sig = signature(baseName, prefixIds, suffixIds)
						if not seenSig[sig] then
							seenSig[sig] = true
							crafted = crafted + 1
							local title = baseName .. " " .. plan.name
							local item = craftJewel(baseName, prefixIds, suffixIds, title)
							if not item then
								failed = failed + 1
							else
								build.itemsTab:AddItem(item, true)
								local cand = Candidate.generatedRare({
									id = "genjewel:" .. sig,
									name = item.name or title,
									slots = slotNames,
									itemId = item.id,
									item = item,
									raw = item.raw,
									itemType = item.type,
									base = baseName,
									prefixes = prefixIds,
									suffixes = suffixIds,
								})
								cand.role = plan.name
								cand.affixScore = comboScore(prefixRows, suffixRows)
								cand.resist = resist.fromItem(item)
								byId[cand.id] = cand
								all[#all + 1] = cand
							end
						end
					end
				end
			end
		end
	end

	table.sort(all, function(a, b)
		return (a.affixScore or 0) > (b.affixScore or 0)
	end)
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

	return {
		all = all,
		byId = byId,
		stats = {
			crafted = crafted,
			failed = failed,
			installed = #all,
		},
	}
end

return {
	CLASSIC_BASES = CLASSIC_BASES,
	generate = generate,
}
