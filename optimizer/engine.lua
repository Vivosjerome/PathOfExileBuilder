local slotsMod = require("items.slots")
local uniqueIndex = require("items.unique_index")
local rareGenerator = require("items.rare_generator")
local jewelIndex = require("jewels.index")
local clusterIndex = require("jewels.cluster")
local timelessIndex = require("jewels.timeless")
local flaskIndex = require("flasks.index")
local gemIndex = require("gems.index")
local treeIndex = require("tree.index")
local cacheMod = require("optimizer.cache")
local pruning = require("optimizer.pruning")
local scorer = require("optimizer.scorer")
local resist = require("optimizer.resist")
local constraintsMod = require("optimizer.constraints")
local beam = require("optimizer.beam")
local mutations = require("optimizer.mutations")
local oracle = require("pob-engine.oracle")

local UNCONSTRAINED_DPS = 482651.55
local BENCHMARK_B_DPS = 96974.903302893
local UNCONSTRAINED_GEAR = {
	{ slot = "Helmet", name = "Malachai's Awakening" },
	{ slot = "Gloves", name = "Facebreaker" },
	{ slot = "Boots", name = "Annihilation's Approach" },
	{ slot = "Body Armour", name = "Pragmatism" },
	{ slot = "Amulet", name = "Marylene's Fallacy" },
	{ slot = "Ring 1", name = "Original Sin" },
	{ slot = "Ring 2", name = "Ixchel's Temptation" },
	{ slot = "Belt", name = "Bound Fate" },
	{ slot = "Weapon 1", name = "Divinarius" },
	{ slot = "Weapon 2", name = "Replica Nebulis" },
}

local function log(fmt, ...)
	io.stderr:write(string.format(fmt, ...) .. "\n")
	io.stderr:flush()
end

local function pct(n)
	return string.format("%+.2f%%", n)
end

local function findCandidate(catalog, slotName, namePrefix)
	for _, cand in ipairs(catalog.bySlot[slotName] or {}) do
		if cand.name and (cand.name:sub(1, #namePrefix) == namePrefix or cand.name:find(namePrefix, 1, true)) then
			return cand
		end
	end
	return nil
end

local function summarizeState(state, catalog, baselineScore)
	local improvement = 0
	if baselineScore and baselineScore > 0 and state.score then
		improvement = (state.score - baselineScore) / baselineScore * 100
	end
	local classif = state.classif
	if not classif and state.stats then
		classif = resist.classify(state.stats, { fire = 0, cold = 0, lightning = 0 }, 75)
	end
	local items = beam.describeLoadout(state.loadout or {}, catalog)
	local rareCount, uniqueCount = 0, 0
	for _, it in ipairs(items) do
		if it.kind == "unique" then
			uniqueCount = uniqueCount + 1
		elseif it.kind == "generated_rare" or it.kind == "rare" then
			rareCount = rareCount + 1
		end
	end
	local stats = state.stats or {}
	return {
		score = state.score,
		hash = state.hash,
		improvementPct = improvement,
		items = items,
		stats = stats,
		res = classif and classif.res or resist.fromStats(stats),
		resText = classif and resist.formatRes(classif.res) or nil,
		feasible = classif and classif.feasible or false,
		near = classif and classif.near or false,
		deficit = classif and classif.deficit or nil,
		totalDeficit = classif and classif.totalDeficit or 0,
		life = stats.Life or stats.LifeUnreserved,
		energyShield = stats.EnergyShield,
		rareCount = rareCount,
		uniqueCount = uniqueCount,
	}
end

local function probeUnconstrained(catalog)
	local ids = {}
	local missing = {}
	for _, spec in ipairs(UNCONSTRAINED_GEAR) do
		local cand = findCandidate(catalog, spec.slot, spec.name)
		if cand then
			ids[spec.slot] = cand.itemId
		else
			missing[#missing + 1] = spec.slot .. "=" .. spec.name
		end
	end
	if #missing > 0 then
		log("Unconstrained probe missing: %s", table.concat(missing, ", "))
	end
	oracle.applyLoadout(ids)
	local inspected = oracle.inspect()
	local res = resist.fromStats(inspected.stats)
	local feasible = resist.isFeasible(res, 75)
	log("--------------------------------")
	log("Unconstrained best-build probe")
	log("CombinedDPS: %.4f", inspected.stats.CombinedDPS or 0)
	log("Fire / Cold / Lightning: %s", resist.formatRes(res))
	log("Valid 75/75/75: %s", feasible and "yes" or "NO")
	if not feasible then
		local d = resist.deficit(res, 75)
		log("Deficit: Fire %d  Cold %d  Lightning %d", d.fire, d.cold, d.lightning)
		log("Invalid because at least one elemental resist is below 75.")
	end
	log("")
	return {
		score = inspected.stats.CombinedDPS or 0,
		stats = inspected.stats,
		res = res,
		feasible = feasible,
		items = inspected.items,
		hash = inspected.hash,
		deficit = resist.deficit(res, 75),
	}
end

local function pickBestFeasible(states)
	for _, state in ipairs(states or {}) do
		if state.classif and state.classif.feasible then
			return state
		end
	end
	return nil
end

local function topList(states, n, catalog, baselineScore, predicate)
	local out = {}
	for _, state in ipairs(states or {}) do
		if not predicate or predicate(state) then
			out[#out + 1] = summarizeState(state, catalog, baselineScore)
			if #out >= n then
				break
			end
		end
	end
	return out
end

local function countKinds(items)
	local rare, unique = 0, 0
	for _, it in ipairs(items or {}) do
		if it.kind == "unique" then
			unique = unique + 1
		elseif it.kind == "generated_rare" or it.kind == "rare" then
			rare = rare + 1
		end
	end
	return rare, unique
end

local function rareValueReport(topRows)
	local bases, affixes, bySlot = {}, {}, {}
	for _, row in ipairs(topRows or {}) do
		for _, it in ipairs(row.items or {}) do
			if it.kind == "generated_rare" or it.kind == "rare" then
				local slot = it.slot or "?"
				bySlot[slot] = bySlot[slot] or {}
				local base = it.base or it.name or "?"
				bases[base] = (bases[base] or 0) + 1
				bySlot[slot][base] = (bySlot[slot][base] or 0) + 1
				for _, id in ipairs(it.prefixes or {}) do
					affixes[id] = (affixes[id] or 0) + 1
				end
				for _, id in ipairs(it.suffixes or {}) do
					affixes[id] = (affixes[id] or 0) + 1
				end
			end
		end
	end
	local function rank(map, n)
		local list = {}
		for name, count in pairs(map) do
			list[#list + 1] = { name = name, count = count }
		end
		table.sort(list, function(a, b)
			if a.count == b.count then
				return a.name < b.name
			end
			return a.count > b.count
		end)
		local out = {}
		for i = 1, math.min(n or 12, #list) do
			out[i] = list[i]
		end
		return out
	end
	local slots = {}
	for slot, map in pairs(bySlot) do
		slots[#slots + 1] = { slot = slot, bases = rank(map, 8) }
	end
	table.sort(slots, function(a, b) return a.slot < b.slot end)
	return {
		bases = rank(bases, 15),
		affixes = rank(affixes, 20),
		bySlot = slots,
	}
end

local function splitComplete(verified, catalog, loadout)
	local gear, jewels, flasks = {}, {}, {}
	for _, it in ipairs(verified.items or {}) do
		if slotsMod.isFlaskSlot(it.slot) then
			flasks[#flasks + 1] = it
		elseif slotsMod.isJewelSlot(it.slot) then
			jewels[#jewels + 1] = it
		else
			gear[#gear + 1] = it
		end
	end
	local gems, supports, auras = {}, {}, {}
	for _, gem in ipairs(verified.gems or {}) do
		gems[#gems + 1] = {
			group = gem.group,
			name = gem.name,
			level = gem.level,
			quality = gem.quality,
			support = gem.support and true or false,
		}
		if gem.support then
			supports[#supports + 1] = gem.name
		elseif gem.group and tostring(gem.group):match("^__opt_aura_") then
			auras[#auras + 1] = gem.name
		end
	end
	local treeNames, ascendNames = {}, {}
	for _, row in ipairs(verified.notables or {}) do
		treeNames[#treeNames + 1] = row.name
	end
	for _, row in ipairs(verified.ascendancyNodes or {}) do
		ascendNames[#ascendNames + 1] = row.name
	end
	local stats = verified.stats or {}
	return {
		gear = gear,
		jewels = jewels,
		flasks = flasks,
		gems = gems,
		supports = supports,
		auras = auras,
		tree = treeNames,
		ascendancy = verified.ascendancy,
		ascendancyNotables = ascendNames,
		pointsUsed = verified.pointsUsed,
		passiveCount = verified.passiveCount,
		critChance = stats.CritChance or stats.PreEffectiveCritChance,
		critMultiplier = stats.CritMultiplier,
		loadout = loadout,
	}
end

local function compactItems(items)
	local out = {}
	for _, it in ipairs(items or {}) do
		out[#out + 1] = {
			slot = it.slot,
			name = it.name,
			kind = it.kind,
			base = it.base,
		}
	end
	return out
end

local function run(params)
	params = params or {}
	local started = os.clock()
	local className = params.class or "Witch"
	local ascendancy = params.ascendancy or "Elementalist"
	local level = tonumber(params.level) or 90
	local skill = params.skill or "Winter Orb"
	local objective = params.objective or "MAX_DPS"
	local beamSize = tonumber(params.beamSize) or 100
	local slots = params.slots or slotsMod.GEAR_SLOTS
	local constrainRes = params.constrainRes
	if constrainRes == nil then
		constrainRes = true
	end
	local includeRares = params.includeRares
	if includeRares == nil then
		includeRares = constrainRes
	end
	local includeJewels = params.includeJewels == true
	local includeGems = params.includeGems == true
	local includeFlasks = params.includeFlasks == true
	local includeTree = params.includeTree == true
	local includeAscendancy = params.includeAscendancy == true
	local includeCluster = params.includeCluster == true
	local includeTimeless = params.includeTimeless == true
	local resThreshold = params.resThreshold or 75
	local constraintSpec = params.constraints
	if (not constraintSpec or not constraintsMod.hasAny(constraintSpec)) and constrainRes then
		constraintSpec = {
			min = {
				FireResist = resThreshold,
				ColdResist = resThreshold,
				LightningResist = resThreshold,
			},
		}
	end
	local product = params.product == true
	local benchmarkId = "product"
	if not product then
		benchmarkId = "A"
		if constrainRes and includeRares then
			benchmarkId = "C"
		elseif constrainRes then
			benchmarkId = "B"
		end
	end

	log("Optimization started")
	log("")
	log("Skill: %s", skill)
	log("Class: %s", className)
	log("Ascendancy: %s", ascendancy)
	log("Level: %d", level)
	log("Objective: %s", objective)
	log("Beam size: %d", beamSize)
	log("Resist constraint: %s", constrainRes and "on" or "none")
	log("Rares: %s", includeRares and "generated from PoB Explicit mods" or "off")
	log("Jewels: %s", includeJewels and "classic + unique tree sockets" or "off")
	log("Gems/supports: %s", includeGems and "on" or "off")
	log("Flasks: %s", includeFlasks and "on" or "off")
	log("Tree: %s", includeTree and "on" or "off")
	log("Ascendancy: %s", includeAscendancy and "on" or "off")
	log("Cluster jewels: %s", includeCluster and "on" or "off")
	log("Timeless jewels: %s", includeTimeless and "on" or "off")
	if product then
		log("Mode: product")
	else
		log("Regression benchmark: %s", benchmarkId)
		log("Frozen A: %.0f DPS   Frozen B: %.0f DPS", UNCONSTRAINED_DPS, BENCHMARK_B_DPS)
	end
	log("")

	local created, err = oracle.create({
		class = className,
		ascendancy = ascendancy,
		level = level,
		skill = skill,
		skillLevel = params.skillLevel or 20,
		skillQuality = params.skillQuality or 20,
		config = params.config,
	})
	if not created then
		return nil, err
	end

	local baselineStats = created.stats
	local baselineScore = scorer.score(baselineStats, objective)
	log("Naked baseline CombinedDPS: %.4f", baselineScore)
	log("Naked resists: %s", resist.formatRes(resist.fromStats(baselineStats)))
	log("")

	log("Indexing uniques...")
	local catalog = uniqueIndex.indexUniques(level)
	log("Uniques installed: %d", catalog.stats.installed)
	local rareStats
	if includeRares then
		log("Generating rares from PoB affix data...")
		local generated = rareGenerator.generate({
			characterLevel = level,
			itemLevel = 100,
			maxBasesPerSlot = params.maxBasesPerSlot or 8,
			maxRaresPerSlot = params.maxRaresPerSlot or 40,
			slots = slots,
		})
		rareGenerator.install(catalog, generated)
		rareStats = generated.stats
		log("Rares crafted: %d  installed: %d  failed: %d  bases: %d",
			rareStats.crafted or 0, rareStats.installed or 0, rareStats.failed or 0, rareStats.basesSelected or 0)
	end
	for _, slotName in ipairs(slots) do
		local m = catalog.maxResBySlot and catalog.maxResBySlot[slotName]
		local nU, nR = 0, 0
		for _, cand in ipairs(catalog.bySlot[slotName] or {}) do
			if cand.kind == "unique" then nU = nU + 1 else nR = nR + 1 end
		end
		log("  %s: %d uniques + %d rares  max res F/C/L %s", slotName, nU, nR,
			m and resist.formatRes(m) or "?")
	end
	log("")

	local unconstrainedProbe = probeUnconstrained(catalog)

	local jewelPrep, clusterPrep, flaskPrep, gemPrep, treePrep
	local classicJewelSlots = {}
	if includeJewels or includeTimeless then
		log("Allocating nearest classic jewel sockets...")
		jewelPrep = jewelIndex.prepare(catalog, {
			characterLevel = level,
			includeRares = includeRares,
			maxSockets = params.maxJewelSockets or 3,
			maxPoints = params.maxJewelPathPoints or 24,
			maxRares = params.maxJewelRares or 40,
			itemLevel = 100,
		})
		classicJewelSlots = jewelPrep.slotNames or {}
		oracle.clearGearSlots()
		oracle.recalc()
		log("Jewel sockets allocated: %d  points spent: %d",
			#(jewelPrep.sockets or {}), jewelPrep.pointsSpent or 0)
		for _, sock in ipairs(jewelPrep.sockets or {}) do
			log("  %s  node %d  path cost %d", sock.slotName, sock.id, sock.pathCost or 0)
		end
		log("Unique jewels: %d  rare jewels: %d",
			jewelPrep.uniquesInstalled or 0, jewelPrep.raresInstalled or 0)
	end
	if includeTimeless and #classicJewelSlots > 0 then
		local tl = timelessIndex.prepare(catalog, classicJewelSlots, { characterLevel = level })
		log("Timeless jewels indexed: %d", tl.installed or 0)
	end
	if includeCluster then
		log("Allocating large cluster sockets...")
		clusterPrep = clusterIndex.prepare(catalog, {
			characterLevel = level,
			maxSockets = 2,
			maxPoints = 28,
			maxRares = 24,
		})
		log("Cluster sockets: %d  uniques %d  crafts %d  points %d",
			#(clusterPrep.sockets or {}), clusterPrep.uniquesInstalled or 0,
			clusterPrep.raresInstalled or 0, clusterPrep.pointsSpent or 0)
	end
	local baseSockets = {}
	for _, prep in ipairs({ jewelPrep, clusterPrep }) do
		if prep then
			for _, sock in ipairs(prep.sockets or {}) do
				baseSockets[#baseSockets + 1] = sock.id
			end
		end
	end
	oracle.setTreeBaseSockets(baseSockets)

	if includeFlasks then
		flaskPrep = flaskIndex.prepare(catalog, { characterLevel = level, maxRares = 24 })
		log("Flasks: %d uniques + %d rares", flaskPrep.uniquesInstalled or 0, flaskPrep.raresInstalled or 0)
	end
	if includeGems then
		jewelIndex.ensureSlots(catalog, slotsMod.SUPPORT_SLOTS)
		jewelIndex.ensureSlots(catalog, slotsMod.AURA_SLOTS)
		local supports = gemIndex.indexSupports(slotsMod.SUPPORT_SLOTS)
		local auras = gemIndex.indexAuras(slotsMod.AURA_SLOTS)
		jewelIndex.addCandidates(catalog, supports)
		jewelIndex.addCandidates(catalog, auras)
		gemPrep = { supports = supports.stats.installed, auras = auras.stats.installed }
		log("Supports: %d  auras/curses: %d", gemPrep.supports, gemPrep.auras)
	end
	if includeTree or includeAscendancy then
		treePrep = treeIndex.prepare(catalog, {
			includeTree = includeTree,
			includeAscendancy = includeAscendancy,
			treePicks = 8,
			ascendPicks = 4,
		})
		log("Tree notables/keystones: %d  ascendancy notables: %d",
			treePrep.treeCount or 0, treePrep.ascendCount or 0)
	end

	local searchSlots = {}
	if includeAscendancy and treePrep then
		for _, name in ipairs(treePrep.ascendSlots or {}) do
			searchSlots[#searchSlots + 1] = name
		end
	end
	for _, name in ipairs(slotsMod.GEAR_SLOTS) do
		searchSlots[#searchSlots + 1] = name
	end
	if includeFlasks then
		for _, name in ipairs(slotsMod.FLASK_SLOTS) do
			searchSlots[#searchSlots + 1] = name
		end
	end
	if includeGems then
		for _, name in ipairs(slotsMod.SUPPORT_SLOTS) do
			searchSlots[#searchSlots + 1] = name
		end
		for _, name in ipairs(slotsMod.AURA_SLOTS) do
			searchSlots[#searchSlots + 1] = name
		end
	end
	if includeTree and treePrep then
		for _, name in ipairs(treePrep.treeSlots or {}) do
			searchSlots[#searchSlots + 1] = name
		end
	end
	if includeJewels or includeTimeless then
		for _, name in ipairs(classicJewelSlots) do
			searchSlots[#searchSlots + 1] = name
		end
	end
	if includeCluster and clusterPrep then
		for _, name in ipairs(clusterPrep.slotNames or {}) do
			searchSlots[#searchSlots + 1] = name
		end
	end
	slots = searchSlots
	catalog.slotOrder = slots
	resist.buildSlotMax(catalog)
	oracle.clearGearSlots()
	oracle.recalc()
	log("Search slots: %d", #slots)
	log("")

	local cache = cacheMod.new()
	local metrics = pruning.new()
	local identity = {
		class = className,
		ascendancy = ascendancy,
		level = level,
		skill = skill,
		skillLevel = params.skillLevel or 20,
		skillQuality = params.skillQuality or 20,
	}

	local lastPreJewelSlot
	for i, name in ipairs(slots) do
		if slotsMod.isJewelSlot(name) then
			if i > 1 then
				lastPreJewelSlot = slots[i - 1]
			end
			break
		end
	end

	local beforeJewelsState
	local states, ctx = beam.run({
		catalog = catalog,
		slots = slots,
		identity = identity,
		objective = objective,
		beamSize = beamSize,
		cache = cache,
		metrics = metrics,
		baselineScore = baselineScore,
		baselineStats = baselineStats,
		constrainRes = constrainRes,
		resThreshold = resThreshold,
		constraints = constraintSpec,
		onAfterSlot = function(slotName, beamStates)
			if lastPreJewelSlot and slotName == lastPreJewelSlot then
				beforeJewelsState = pickBestFeasible(beamStates) or beamStates[1]
			end
		end,
	})

	states = mutations.run(states, catalog, {
		identity = identity,
		objective = objective,
		beamSize = beamSize,
		cache = cache,
		metrics = metrics,
		baselineScore = baselineScore,
		bestScore = ctx.bestScore,
		bestFeasibleScore = ctx.bestFeasibleScore,
		mutationRounds = params.mutationRounds or 2,
		mutationTop = params.mutationTop or 5,
		slots = slots,
		constrainRes = constrainRes,
		resThreshold = resThreshold,
		constraints = constraintSpec,
		catalog = catalog,
		freezeRemaining = true,
		nearArchive = ctx.nearArchive,
		discoveries = ctx.discoveries,
	})

	local elapsed = os.clock() - started
	local bestFeasible = pickBestFeasible(states)
	local best = bestFeasible or states[1]
	if best then
		oracle.applyState(best.loadout, catalog)
	end
	local verified = oracle.inspect()
	local verifiedScore = scorer.score(verified.stats, objective)
	local verifiedRes = resist.fromStats(verified.stats)
	local verifiedFeasible = false
	if constraintSpec and constraintsMod.hasAny(constraintSpec) then
		verifiedFeasible = constraintsMod.check(verified.stats, constraintSpec)
	else
		verifiedFeasible = resist.isFeasible(verifiedRes, resThreshold)
	end

	local topN = tonumber(params.topN) or 20
	local validTop = topList(states, topN, catalog, baselineScore, function(s)
		return s.classif and s.classif.feasible
	end)
	local nearSource = ctx.nearArchive or {}
	table.sort(nearSource, function(a, b)
		if a.score == b.score then
			local ad = (a.classif and a.classif.totalDeficit) or 999
			local bd = (b.classif and b.classif.totalDeficit) or 999
			if ad ~= bd then
				return ad < bd
			end
			return (a.hash or "") < (b.hash or "")
		end
		return a.score > b.score
	end)
	local nearTop = topList(nearSource, topN, catalog, baselineScore, function(s)
		return s.classif and not s.classif.feasible and (s.classif.totalDeficit or 999) <= 15
	end)

	local constrainedDps = bestFeasible and bestFeasible.score or 0
	local beforeJewelsSummary = beforeJewelsState and summarizeState(beforeJewelsState, catalog, baselineScore) or nil
	local afterJewelsSummary = best and summarizeState(best, catalog, baselineScore) or nil
	local jewelGainPct = 0
	if beforeJewelsSummary and afterJewelsSummary and (beforeJewelsSummary.score or 0) > 0 then
		jewelGainPct = (afterJewelsSummary.score - beforeJewelsSummary.score) / beforeJewelsSummary.score * 100
	end
	local dpsLossVsA = 0
	if UNCONSTRAINED_DPS > 0 and constrainedDps > 0 then
		dpsLossVsA = (UNCONSTRAINED_DPS - constrainedDps) / UNCONSTRAINED_DPS * 100
	end
	local gainVsB = 0
	local recoveredVsGap = 0
	if BENCHMARK_B_DPS > 0 and constrainedDps > 0 then
		gainVsB = (constrainedDps - BENCHMARK_B_DPS) / BENCHMARK_B_DPS * 100
	end
	local gapAB = UNCONSTRAINED_DPS - BENCHMARK_B_DPS
	if gapAB > 0 and constrainedDps > 0 then
		recoveredVsGap = (constrainedDps - BENCHMARK_B_DPS) / gapAB * 100
	end
	local evals = metrics.pobEvals
	local perSecond = elapsed > 0 and (evals / elapsed) or 0
	local pobDiffPct = 0
	if constrainedDps > 0 then
		pobDiffPct = math.abs(verifiedScore - constrainedDps) / constrainedDps * 100
	end

	local validCount = 0
	for _, state in ipairs(states or {}) do
		if state.classif and state.classif.feasible then
			validCount = validCount + 1
		end
	end
	local nearCount = 0
	for _, state in ipairs(nearSource) do
		if state.classif and not state.classif.feasible and (state.classif.totalDeficit or 999) <= 15 then
			nearCount = nearCount + 1
		end
	end
	local mixedCount = 0
	for _, row in ipairs(validTop) do
		if (row.rareCount or 0) > 0 and (row.uniqueCount or 0) > 0 then
			mixedCount = mixedCount + 1
		end
	end
	local rareReport = rareValueReport(validTop)
	local discoveries = ctx.discoveries or {}

	log("--------------------------------")
	if product or benchmarkId == "product" then
		log("SEARCH COMPLETE")
		log("Best score: %.0f", constrainedDps)
		log("Objective: %s", objective)
	elseif benchmarkId == "C" then
		log("BENCHMARK C — uniques + rares + 75/75/75")
		log("Benchmark A: %.0f DPS", UNCONSTRAINED_DPS)
		log("Benchmark B: %.0f DPS", BENCHMARK_B_DPS)
		log("Benchmark C: %.0f DPS", constrainedDps)
		log("Gain vs B: %+.2f%%", gainVsB)
		log("DPS recovered thanks to rares: %.2f%% of A→B gap", recoveredVsGap)
	elseif benchmarkId == "B" then
		log("BENCHMARK B — uniques + 75/75/75")
		log("Unconstrained (A): %.0f DPS", UNCONSTRAINED_DPS)
		log("75%% Resistance (B): %.0f DPS", constrainedDps)
		log("DPS loss: %.2f%%", dpsLossVsA)
	else
		log("BENCHMARK A — uniques, no resist constraint")
		log("Best CombinedDPS: %.0f", constrainedDps)
	end
	log("Build remains valid: %s", verifiedFeasible and "yes" or "NO")
	log("Verified PoB DPS: %.4f  res %s  diff %.4f%%", verifiedScore, resist.formatRes(verifiedRes), pobDiffPct)
	local complete = splitComplete(verified, catalog, best and best.loadout)
	if product or includeGems or includeFlasks or includeTree or includeAscendancy or includeCluster or includeTimeless then
		local vs = verified.stats or {}
		log("")
		log("COMPLETE BUILD")
		log("CombinedDPS: %.4f", verifiedScore)
		log("Life / ES: %d / %d", math.floor(vs.Life or 0), math.floor(vs.EnergyShield or 0))
		log("Res F/C/L: %s", resist.formatRes(verifiedRes))
		log("Crit: %.2f%%  x%.2f", (complete.critChance or 0), (complete.critMultiplier or 0))
		log("Gear:")
		for _, it in ipairs(complete.gear) do
			log("  %s: %s", it.slot, it.name)
		end
		log("Gems/supports:")
		if #complete.gems == 0 then
			log("  (none)")
		end
		for _, gem in ipairs(complete.gems) do
			log("  %s%s %d/%d", gem.support and "[support] " or "", gem.name or "?", gem.level or 0, gem.quality or 0)
		end
		log("Flasks:")
		if #complete.flasks == 0 then
			log("  (none)")
		end
		for _, it in ipairs(complete.flasks) do
			log("  %s: %s", it.slot, it.name)
		end
		log("Tree notables/keystones (%d passives, %d points):", complete.passiveCount or 0, complete.pointsUsed or 0)
		if #complete.tree == 0 then
			log("  (class start / sockets only)")
		end
		for _, name in ipairs(complete.tree) do
			log("  %s", name)
		end
		log("Ascendancy: %s", complete.ascendancy or "?")
		for _, name in ipairs(complete.ascendancyNotables) do
			log("  %s", name)
		end
		log("Jewels:")
		if #complete.jewels == 0 then
			log("  (none)")
		end
		for _, it in ipairs(complete.jewels) do
			log("  %s: %s", it.slot, it.name)
		end
		log("Builds tested: %d  PoB evals: %d  time: %.2fs  PoB delta: %.4f%%",
			metrics.tested or 0, evals, elapsed, pobDiffPct)
	end
	if includeJewels then
		log("")
		log("JEWELS — before / after")
		if beforeJewelsSummary then
			log("Before jewels (gear only, sockets allocated, empty): %.4f  res %s",
				beforeJewelsSummary.score or 0, beforeJewelsSummary.resText or resist.formatRes(beforeJewelsSummary.res))
			for _, it in ipairs(beforeJewelsSummary.items or {}) do
				if not slotsMod.isJewelSlot(it.slot) then
					log("  %s: [%s] %s", it.slot, it.kind or "?", it.name)
				end
			end
		else
			log("Before jewels: (not captured)")
		end
		log("After jewels: %.4f  res %s  (%+.2f%% vs gear-only)",
			constrainedDps, resist.formatRes(verifiedRes), jewelGainPct)
		local jewelCount = 0
		for _, it in ipairs(afterJewelsSummary and afterJewelsSummary.items or {}) do
			if slotsMod.isJewelSlot(it.slot) then
				jewelCount = jewelCount + 1
				log("  %s: [%s] %s%s", it.slot, it.kind or "?", it.name,
					it.role and ("  (" .. it.role .. ")") or "")
			end
		end
		if jewelCount == 0 then
			log("  (no jewels equipped — empty sockets won)")
		end
		if jewelPrep then
			log("Sockets: %d classic  %d points%s%s",
				#(jewelPrep.sockets or {}), jewelPrep.pointsSpent or 0,
				includeCluster and "  cluster on" or "",
				includeTimeless and "  timeless on" or "")
		end
	end
	log("PoB evaluations: %d", evals)
	log("Pruned impossible: %d", metrics.prunedImpossible or 0)
	log("Removed outside beam: %d", metrics.eliminatedBeam or 0)
	log("Valid builds in final beam: %d", validCount)
	log("Near-feasible archived (deficit<=15): %d", nearCount)
	log("Runtime: %.2fs", elapsed)
	log("")
	log("VALID BUILDS")
	for i, row in ipairs(validTop) do
		log("#%d  DPS: %.0f  res %s  Life %d  ES %d  rares %d  uniques %d",
			i, row.score or 0, row.resText or resist.formatRes(row.res),
			math.floor(row.life or 0), math.floor(row.energyShield or 0),
			row.rareCount or 0, row.uniqueCount or 0)
		for _, it in ipairs(row.items or {}) do
			log("  %s: [%s] %s", it.slot, it.kind or "?", it.name)
		end
		log("")
	end
	log("NEAR-FEASIBLE")
	for i, row in ipairs(nearTop) do
		log("#%d  DPS: %.0f  res %s  deficit %d", i, row.score or 0, row.resText or "?", row.totalDeficit or 0)
		for _, it in ipairs(row.items or {}) do
			log("  %s: [%s] %s", it.slot, it.kind or "?", it.name)
		end
		log("")
	end
	if includeRares then
		log("MOST VALUABLE RARE BASES")
		for _, row in ipairs(rareReport.bases) do
			log("  %s  (%d)", row.name, row.count)
		end
		log("")
		log("MOST VALUABLE AFFIXES")
		for _, row in ipairs(rareReport.affixes) do
			log("  %s  (%d)", row.name, row.count)
		end
		log("")
		log("DISCOVERY")
		if #discoveries == 0 then
			log("  (none recorded)")
		end
		for i, d in ipairs(discoveries) do
			if i > 12 then
				break
			end
			log("  %s  %s", d.slot, d.rare or "?")
			log("    %+0.1f%% CombinedDPS  (%.0f → %.0f)", d.dpsGainPct or 0, d.before or 0, d.after or 0)
			log("    %s", d.reason or "")
		end
		log("")
	end

	local snapshot = {
		benchmark = benchmarkId,
		combinedDPS = constrainedDps,
		resists = verifiedRes,
		comparison = {
			unconstrainedDps = UNCONSTRAINED_DPS,
			benchmarkBDps = BENCHMARK_B_DPS,
			constrainedDps = constrainedDps,
			dpsLossVsAPct = dpsLossVsA,
			gainVsBPct = gainVsB,
			rareRecoveryOfGapPct = recoveredVsGap,
			valid = verifiedFeasible,
			verifiedPobDifferencePct = pobDiffPct,
		},
		bestItems = compactItems(best and summarizeState(best, catalog, baselineScore).items or {}),
		metrics = {
			candidatesGenerated = metrics.generated,
			candidatesTested = metrics.tested,
			pobEvaluations = metrics.pobEvals,
			calculationsPerSecond = perSecond,
			seconds = elapsed,
			cacheHits = cache.hits,
			prunedImpossible = metrics.prunedImpossible or 0,
			eliminatedFromBeam = metrics.eliminatedBeam,
			errors = metrics.errors,
			validBuilds = validCount,
			nearFeasibleBuilds = nearCount,
			rareCandidatesGenerated = rareStats and rareStats.installed or 0,
			uniqueCandidatesGenerated = catalog.stats.installed or 0,
			mixedCandidates = mixedCount,
			uniqueTested = metrics.uniqueTested or 0,
			rareTested = metrics.rareTested or 0,
		},
		jewels = includeJewels and {
			before = beforeJewelsSummary and {
				score = beforeJewelsSummary.score,
				res = beforeJewelsSummary.res,
				items = compactItems(beforeJewelsSummary.items),
			} or nil,
			after = afterJewelsSummary and {
				score = afterJewelsSummary.score,
				res = afterJewelsSummary.res,
				items = compactItems(afterJewelsSummary.items),
			} or nil,
			gainPct = jewelGainPct,
			sockets = jewelPrep and jewelPrep.sockets or {},
			pointsSpent = jewelPrep and jewelPrep.pointsSpent or 0,
			uniquesIndexed = catalog.stats.jewelUniques or 0,
			raresIndexed = catalog.stats.jewelRares or 0,
		} or nil,
		complete = complete,
	}

	return {
		benchmark = benchmarkId,
		snapshot = snapshot,
		comparison = snapshot.comparison,
		unconstrainedProbe = unconstrainedProbe,
		baseline = {
			score = baselineScore,
			stats = baselineStats,
			hash = created.hash,
			res = resist.fromStats(baselineStats),
		},
		best = best and summarizeState(best, catalog, baselineScore) or nil,
		verified = {
			score = verifiedScore,
			stats = verified.stats,
			items = verified.items,
			gems = verified.gems,
			notables = verified.notables,
			ascendancyNodes = verified.ascendancyNodes,
			pointsUsed = verified.pointsUsed,
			hash = verified.hash,
			res = verifiedRes,
			feasible = verifiedFeasible,
		},
		top = validTop,
		topValid = validTop,
		topNear = nearTop,
		rareReport = rareReport,
		discoveries = discoveries,
		jewels = snapshot.jewels,
		complete = complete,
		metrics = {
			candidatesGenerated = metrics.generated,
			candidatesTested = metrics.tested,
			pobEvaluations = metrics.pobEvals,
			cacheHits = cache.hits,
			cacheMisses = cache.misses,
			cacheHitRate = cacheMod.hitRate(cache),
			invalid = metrics.invalid,
			duplicatesSkipped = metrics.duplicates,
			errors = metrics.errors,
			pruned = metrics.pruned,
			prunedImpossible = metrics.prunedImpossible or 0,
			eliminatedFromBeam = metrics.eliminatedBeam,
			validBuilds = validCount,
			nearFeasibleBuilds = nearCount,
			feasibleInFinalBeam = metrics.feasibleKept or 0,
			nearInFinalBeam = metrics.nearKept or 0,
			calculationsPerSecond = perSecond,
			seconds = elapsed,
			uniquesIndexed = catalog.stats.installed,
			raresIndexed = rareStats and rareStats.installed or 0,
			raresCrafted = rareStats and rareStats.crafted or 0,
			raresFailed = rareStats and rareStats.failed or 0,
			jewelUniquesIndexed = catalog.stats.jewelUniques or 0,
			jewelRaresIndexed = catalog.stats.jewelRares or 0,
			includeJewels = includeJewels,
			uniqueTested = metrics.uniqueTested or 0,
			rareTested = metrics.rareTested or 0,
			mixedTopValid = mixedCount,
			beamSize = beamSize,
			slots = slots,
			resThreshold = resThreshold,
			constrainRes = constrainRes,
			includeRares = includeRares,
		},
		identity = identity,
		objective = objective,
	}
end

return {
	run = run,
	UNCONSTRAINED_DPS = UNCONSTRAINED_DPS,
	BENCHMARK_B_DPS = BENCHMARK_B_DPS,
}
