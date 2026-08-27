-- Generate legal max-roll rares from PoB Explicit mods + item bases.
-- Combinations are ranked, not enumerated. Final DPS always comes from PoB.

local Candidate = require("items.candidate")
local uniqueIndex = require("items.unique_index")
local resist = require("optimizer.resist")
local affixScore = require("optimizer.affix_score")

local SKIP_TYPES = {
	Flask = true,
	Jewel = true,
	Tincture = true,
	Graft = true,
	["Fishing Rod"] = true,
	Trinket = true,
}

local function tagFingerprint(tags)
	local keys = {}
	for key in pairs(tags or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

local function makeScratch(baseName, base)
	local item = new("Item"):Item()
	item.baseName = baseName
	item.base = base
	item.type = base.type
	item.rarity = "RARE"
	item.crafted = true
	item.affixes = data.itemMods.Item
	item.prefixes = {}
	item.suffixes = {}
	item.implicitModLines = {}
	item.explicitModLines = {}
	return item
end

local function compatibleMods(scratch, itemLevel, cache, fp)
	if cache[fp] then
		return cache[fp]
	end
	local prefixes, suffixes = {}, {}
	local explicit = data.itemMods.Explicit
	for modId, mod in pairs(explicit) do
		if type(mod) == "table" and mod.type and mod.group and mod.weightKey and (mod.level or 0) <= itemLevel
			and not scratch:CheckIfModIsDelve(mod)
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
	local out = {
		prefixes = bestPerGroup(prefixes),
		suffixes = bestPerGroup(suffixes),
	}
	cache[fp] = out
	return out
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

local function addImplicits(item)
	if not item.base or not item.base.implicit then
		return
	end
	if item.implicitModLines and #item.implicitModLines > 0 then
		return
	end
	item.implicitModLines = item.implicitModLines or {}
	local implicitIndex = 1
	for line in item.base.implicit:gmatch("[^\n]+") do
		item.implicitModLines[#item.implicitModLines + 1] = {
			line = line,
			modTags = item.base.implicitModTypes and item.base.implicitModTypes[implicitIndex] or {},
		}
		implicitIndex = implicitIndex + 1
	end
end

local function implicitLines(base)
	local lines = {}
	if not base or not base.implicit then
		return lines
	end
	for line in base.implicit:gmatch("[^\n]+") do
		lines[#lines + 1] = line
	end
	return lines
end

local function craftRare(baseName, base, prefixIds, suffixIds, title)
	local lines = {
		"Rarity: RARE",
		title or "Optimizer Rare",
		baseName,
		"Crafted: true",
	}
	if base.type ~= "Amulet" and base.type ~= "Belt" and base.type ~= "Ring" then
		lines[#lines + 1] = "Quality: 20"
	end
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
	if item.crafted then
		addImplicits(item)
		item:Craft()
	end
	uniqueIndex.maximizeRolls(item)
	if item.quality then
		item.quality = 20
		if item.NormaliseQuality then
			item:NormaliseQuality()
		end
	end
	if item.BuildModList then
		item:BuildModList()
	end
	return item, raw
end

local function scoreBase(baseName, base)
	local s = affixScore.scoreText(base.implicit or "")
	local total = s.total
	if base.armour then
		total = total + (base.armour.EnergyShieldBaseMax or 0) * 0.12
		total = total + (base.armour.EvasionBaseMax or 0) * 0.02
		total = total + (base.armour.ArmourBaseMax or 0) * 0.02
	end
	if base.weapon then
		total = total + (base.weapon.CritChanceBase or 0)
	end
	local tags = base.tags or {}
	if tags.wand or tags.sceptre or tags.staff or tags.dagger then
		total = total + 25
	end
	if tags.wand_can_roll_caster_modifiers then
		total = total + 18
	end
	if tags.int_armour or tags.str_int_armour or tags.dex_int_armour then
		total = total + 12
	end
	if tags.focus then
		total = total + 10
	end
	total = total + ((base.req and base.req.level) or 0) * 0.12
	return total
end

local function slotForBase(base)
	return uniqueIndex.slotsForItem({ base = base, type = base.type })
end

local function selectBases(characterLevel, maxPerSlot, slotFilter)
	maxPerSlot = maxPerSlot or 8
	local wanted = {}
	if slotFilter then
		for _, name in ipairs(slotFilter) do
			wanted[name] = true
		end
	end
	local bySlot = {}
	for _, slotName in ipairs(require("items.slots").GEAR_SLOTS) do
		if not slotFilter or wanted[slotName] then
			bySlot[slotName] = {}
		end
	end
	for baseName, base in pairs(data.itemBases) do
		if type(base) == "table" and base.type and not SKIP_TYPES[base.type] and not base.hidden then
			local req = (base.req and base.req.level) or 0
			if req <= characterLevel then
				local slots = slotForBase(base)
				if #slots > 0 then
					local row = {
						name = baseName,
						base = base,
						score = scoreBase(baseName, base),
					}
					for _, slotName in ipairs(slots) do
						if bySlot[slotName] then
							bySlot[slotName][#bySlot[slotName] + 1] = row
						end
					end
				end
			end
		end
	end
	local selected = {}
	for slotName, list in pairs(bySlot) do
		table.sort(list, function(a, b)
			if a.score == b.score then
				return a.name < b.name
			end
			return a.score > b.score
		end)
		local kept, seen = {}, {}
		for _, row in ipairs(list) do
			if not seen[row.name] then
				seen[row.name] = true
				kept[#kept + 1] = row
				if #kept >= maxPerSlot then
					break
				end
			end
		end
		selected[slotName] = kept
	end
	return selected
end

local function templatesFor(pool)
	local prefixes = copy(pool.prefixes)
	local suffixes = copy(pool.suffixes)
	sortBy(prefixes, function(r) return r.score.offense end)
	sortBy(suffixes, function(r) return r.score.offense end)
	local pDef = copy(pool.prefixes)
	local sRes = copy(pool.suffixes)
	local pLife = copy(pool.prefixes)
	local pEs = copy(pool.prefixes)
	sortBy(pDef, function(r) return r.score.defense end)
	sortBy(sRes, function(r) return r.score.resist end)
	sortBy(pLife, function(r) return r.score.life end)
	sortBy(pEs, function(r) return r.score.es end)

	local function coldish(row)
		return affixScore.hasTag(row.mod, "cold") or affixScore.lineMatches(row.mod, "[Cc]old")
	end
	local function critish(row)
		return affixScore.hasTag(row.mod, "critical") or affixScore.lineMatches(row.mod, "[Cc]ritical")
	end
	local function speedish(row)
		return affixScore.hasTag(row.mod, "speed") or affixScore.lineMatches(row.mod, "[Ss]peed")
	end

	local plans = {}

	local function plan(name, buildFn)
		plans[#plans + 1] = { name = name, build = buildFn }
	end

	plan("offense", function()
		local used = {}
		return pick(prefixes, 3, used), pick(suffixes, 3, used)
	end)
	plan("hybrid", function()
		local used = {}
		local p = pick(prefixes, 2, used)
		local extra = pick(pLife, 1, used)
		for _, row in ipairs(extra) do p[#p + 1] = row end
		local s = pick(sRes, 2, used)
		local off = pick(suffixes, 1, used)
		for _, row in ipairs(off) do s[#s + 1] = row end
		return p, s
	end)
	plan("cap", function()
		local used = {}
		local p = pick(pLife, 1, used)
		local more = pick(prefixes, 2, used)
		for _, row in ipairs(more) do p[#p + 1] = row end
		return p, pick(sRes, 3, used)
	end)
	plan("cold", function()
		local used = {}
		local p = pick(prefixes, 3, used, coldish)
		if #p < 3 then
			for _, row in ipairs(pick(prefixes, 3 - #p, used)) do p[#p + 1] = row end
		end
		local s = pick(suffixes, 3, used, coldish)
		if #s < 3 then
			for _, row in ipairs(pick(suffixes, 3 - #s, used)) do s[#s + 1] = row end
		end
		return p, s
	end)
	plan("crit", function()
		local used = {}
		local p = pick(prefixes, 3, used, critish)
		if #p < 3 then
			for _, row in ipairs(pick(prefixes, 3 - #p, used)) do p[#p + 1] = row end
		end
		local s = pick(suffixes, 3, used, critish)
		if #s < 3 then
			for _, row in ipairs(pick(suffixes, 3 - #s, used)) do s[#s + 1] = row end
		end
		return p, s
	end)
	plan("speed", function()
		local used = {}
		local p = pick(prefixes, 3, used)
		local s = pick(suffixes, 3, used, speedish)
		if #s < 3 then
			for _, row in ipairs(pick(suffixes, 3 - #s, used)) do s[#s + 1] = row end
		end
		return p, s
	end)
	plan("discovery", function()
		local used = {}
		-- Skip the obvious top-3 so unexpected PoB mods can enter the beam.
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
		return skipTop(pRank, 3, 3, used), skipTop(sRank, 3, 3, used)
	end)
	plan("es", function()
		local used = {}
		local p = pick(pEs, 2, used)
		if #p < 2 then
			for _, row in ipairs(pick(pLife, 2 - #p, used)) do p[#p + 1] = row end
		end
		for _, row in ipairs(pick(prefixes, 3 - #p, used)) do p[#p + 1] = row end
		return p, pick(sRes, 3, used)
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

local function trimSlot(cands, limit)
	if #cands <= limit then
		return cands
	end
	local cap, offense, rest = {}, {}, {}
	for _, cand in ipairs(cands) do
		if cand.role == "cap" then
			cap[#cap + 1] = cand
		elseif cand.role == "offense" or cand.role == "cold" or cand.role == "crit" then
			offense[#offense + 1] = cand
		else
			rest[#rest + 1] = cand
		end
	end
	local function byScore(a, b)
		return (a.affixScore or 0) > (b.affixScore or 0)
	end
	table.sort(cap, byScore)
	table.sort(offense, byScore)
	table.sort(rest, byScore)
	local kept, seen = {}, {}
	local function take(src, n)
		for _, cand in ipairs(src) do
			if #kept >= limit then
				return
			end
			if not seen[cand.id] then
				seen[cand.id] = true
				kept[#kept + 1] = cand
				n = n - 1
				if n <= 0 then
					return
				end
			end
		end
	end
	take(cap, 8)
	take(offense, 14)
	take(rest, limit)
	take(cands, limit)
	return kept
end

local function generate(params)
	params = params or {}
	local characterLevel = params.characterLevel or 90
	local itemLevel = params.itemLevel or 100
	local maxBases = params.maxBasesPerSlot or 8
	local maxRares = params.maxRaresPerSlot or 40
	local basesBySlot = selectBases(characterLevel, maxBases, params.slots)
	local modCache = {}
	local bySlot = {}
	local all = {}
	local seenSig = {}
	local crafted = 0
	local failed = 0

	local function addCandidate(slotName, cand)
		bySlot[slotName] = bySlot[slotName] or {}
		bySlot[slotName][#bySlot[slotName] + 1] = cand
		all[#all + 1] = cand
	end

	-- Deduplicate bases across slots (Ring 1/2 share).
	local craftedBases = {}
	for slotName, bases in pairs(basesBySlot) do
		for _, baseRow in ipairs(bases) do
			craftedBases[baseRow.name] = craftedBases[baseRow.name] or baseRow
		end
	end

	for baseName, baseRow in pairs(craftedBases) do
		local base = baseRow.base
		local scratch = makeScratch(baseName, base)
		local fp = tagFingerprint(base.tags)
		local pool = compatibleMods(scratch, itemLevel, modCache, fp)
		if #pool.prefixes > 0 and #pool.suffixes > 0 then
			for _, plan in ipairs(templatesFor(pool)) do
				local prefixRows, suffixRows = plan.build()
				if #prefixRows > 0 and #suffixRows > 0 then
					local prefixIds = idsOf(prefixRows)
					local suffixIds = idsOf(suffixRows)
					local sig = signature(baseName, prefixIds, suffixIds)
					if not seenSig[sig] then
						seenSig[sig] = true
						local title = "Rare " .. plan.name
							local item, raw = craftRare(baseName, base, prefixIds, suffixIds, title)
							if not item then
								failed = failed + 1
							else
								crafted = crafted + 1
								build.itemsTab:AddItem(item, true)
								local slots = uniqueIndex.slotsForItem(item)
								local cand = Candidate.generatedRare({
									id = "genrare:" .. sig,
									name = item.name or (title .. " " .. baseName),
									slots = slots,
									itemId = item.id,
									item = item,
									raw = raw,
									itemType = item.type,
									reqLevel = (item.requirements and item.requirements.level) or 0,
									affixes = {
										prefixes = prefixIds,
										suffixes = suffixIds,
										implicits = implicitLines(base),
									},
								})
							cand.base = baseName
							cand.prefixes = prefixIds
							cand.suffixes = suffixIds
							cand.implicits = implicitLines(base)
							cand.influences = {}
							cand.rolls = 1
							cand.role = plan.name
							cand.affixScore = comboScore(prefixRows, suffixRows) + baseRow.score
							cand.resist = resist.fromItem(item)
							for _, slotName in ipairs(slots) do
								addCandidate(slotName, cand)
							end
						end
					end
				end
			end
		end
	end

	local trimmed = {}
	local installed = 0
	for slotName, list in pairs(bySlot) do
		trimmed[slotName] = trimSlot(list, maxRares)
		installed = installed + #trimmed[slotName]
	end

	-- Unique by id after trim (rings counted twice).
	local unique = {}
	local byId = {}
	for _, list in pairs(trimmed) do
		for _, cand in ipairs(list) do
			if not byId[cand.id] then
				byId[cand.id] = cand
				unique[#unique + 1] = cand
			end
		end
	end

	return {
		bySlot = trimmed,
		byId = byId,
		all = unique,
		stats = {
			crafted = crafted,
			failed = failed,
			installed = #unique,
			slotEntries = installed,
			basesSelected = (function()
				local n = 0
				for _ in pairs(craftedBases) do n = n + 1 end
				return n
			end)(),
		},
	}
end

local function install(catalog, generated)
	generated = generated or {}
	local added = 0
	for _, cand in ipairs(generated.all or {}) do
		if not catalog.byId[cand.id] then
			catalog.byId[cand.id] = cand
			catalog.all[#catalog.all + 1] = cand
			added = added + 1
		end
		for _, slotName in ipairs(cand.slots or {}) do
			if catalog.bySlot[slotName] then
				local list = catalog.bySlot[slotName]
				local exists = false
				for _, prev in ipairs(list) do
					if prev.id == cand.id then
						exists = true
						break
					end
				end
				if not exists then
					list[#list + 1] = cand
				end
			end
		end
	end
	catalog.stats = catalog.stats or {}
	catalog.stats.raresInstalled = (catalog.stats.raresInstalled or 0) + added
	resist.buildSlotMax(catalog)
	return catalog
end

return {
	generate = generate,
	install = install,
	craftRare = craftRare,
}
