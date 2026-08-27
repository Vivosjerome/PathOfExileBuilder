local Candidate = require("items.candidate")
local slotsMod = require("items.slots")
local cacheMod = require("optimizer.cache")
local pruning = require("optimizer.pruning")
local scorer = require("optimizer.scorer")
local resist = require("optimizer.resist")
local constraints = require("optimizer.constraints")
local oracle = require("pob-engine.oracle")

local EMPTY = Candidate.empty()

local function copyMap(src)
	local out = {}
	if not src then
		return out
	end
	for key, value in pairs(src) do
		out[key] = value
	end
	return out
end

local function usedKeys(loadout, catalog)
	local usedName, usedId = {}, {}
	for _, candId in pairs(loadout) do
		if candId and candId ~= EMPTY.id then
			usedId[candId] = true
			local cand = catalog.byId[candId]
			if cand then
				if cand.kind == "unique" and cand.name then
					usedName[cand.name] = true
				end
				if cand.name then
					usedName[cand.name] = true
				end
				if cand.effectId then
					usedId["effect:" .. cand.effectId] = true
				end
				if cand.plusVersionOf then
					usedId["effect:" .. cand.plusVersionOf] = true
				end
				if cand.nodeId then
					usedId["node:" .. tostring(cand.nodeId)] = true
				end
			end
		end
	end
	return usedName, usedId
end

local function loadoutItemIds(loadout, catalog)
	local ids = {}
	for slotName, candId in pairs(loadout) do
		local cand = catalog.byId[candId]
		if cand and cand.itemId and cand.itemId ~= 0 then
			ids[slotName] = cand.itemId
		end
	end
	return ids
end

local function slotOrderOf(catalog)
	if catalog and catalog.slotOrder and #catalog.slotOrder > 0 then
		return catalog.slotOrder
	end
	return slotsMod.GEAR_SLOTS
end

local function describeLoadout(loadout, catalog)
	local items = {}
	for _, slotName in ipairs(slotOrderOf(catalog)) do
		local candId = loadout[slotName]
		local cand = candId and catalog.byId[candId]
		if cand and cand.kind ~= "empty" then
			items[#items + 1] = {
				slot = slotName,
				name = cand.name,
				kind = cand.kind,
				base = cand.base,
				role = cand.role,
				prefixes = cand.prefixes,
				suffixes = cand.suffixes,
			}
		end
	end
	return items
end

local function fingerprint(loadout, catalog)
	local parts = {}
	for _, slotName in ipairs(slotOrderOf(catalog)) do
		parts[#parts + 1] = slotName .. "=" .. tostring(loadout[slotName] or "empty")
	end
	return table.concat(parts, "|")
end

local function log(fmt, ...)
	io.stderr:write(string.format(fmt, ...) .. "\n")
	io.stderr:flush()
end

local function scoreOf(stats, objective)
	return scorer.score(stats, objective)
end

local function isBlocked(cand, usedName, usedId)
	if usedId[cand.id] then
		return true
	end
	if cand.kind == "unique" and cand.name and usedName[cand.name] then
		return true
	end
	if (cand.kind == "support" or cand.kind == "aura") and cand.name and usedName[cand.name] then
		return true
	end
	if cand.effectId and usedId["effect:" .. cand.effectId] then
		return true
	end
	if cand.plusVersionOf and usedId["effect:" .. cand.plusVersionOf] then
		return true
	end
	if cand.nodeId and usedId["node:" .. tostring(cand.nodeId)] then
		return true
	end
	if cand.kind == "notable" and cand.name and usedName[cand.name] then
		return true
	end
	return false
end

local function remainingFor(ctx, slotName)
	local after = resist.remainingSlots(ctx.slots or slotsMod.GEAR_SLOTS, slotName)
	local remainingCount = #after
	if ctx.freezeRemaining then
		return { fire = 0, cold = 0, lightning = 0 }, 0
	end
	if not ctx.constrainRes then
		return { fire = 0, cold = 0, lightning = 0 }, remainingCount
	end
	return resist.remainingMax(ctx.catalog, after), remainingCount
end

local function attachClassif(result, ctx, slotName)
	local remaining, remainingCount = remainingFor(ctx, slotName or result.slot)
	result.remainingCount = remainingCount
	if ctx.constraints and constraints.hasAny(ctx.constraints) then
		result.classif = constraints.classify(result.stats, remaining, remainingCount, ctx.constraints)
	elseif ctx.constrainRes then
		result.classif = resist.classify(result.stats, remaining, ctx.resThreshold or 75)
	else
		local res = resist.fromStats(result.stats)
		result.classif = {
			res = res,
			deficit = {},
			totalDeficit = 0,
			minRes = math.min(res.fire, res.cold, res.lightning),
			sumRes = res.fire + res.cold + res.lightning,
			feasible = true,
			near = false,
			impossible = false,
		}
	end
	return result
end

local function considerNear(ctx, result)
	if not ctx.constrainRes or not result or not result.classif then
		return
	end
	local c = result.classif
	local remainingCount = result.remainingCount or 0
	-- Incomplete early states are "near" only because later slots *could* cap.
	-- Archive almost-complete near-misses so the report is meaningful.
	local late = remainingCount <= 2
	local close = (not c.feasible) and c.totalDeficit <= 15
	if not (late and (c.near or close)) and not close then
		return
	end
	ctx.nearArchive = ctx.nearArchive or {}
	ctx.nearArchive[#ctx.nearArchive + 1] = result
	if #ctx.nearArchive > 80 then
		table.sort(ctx.nearArchive, function(a, b)
			local ad = (a.classif and a.classif.totalDeficit) or 999
			local bd = (b.classif and b.classif.totalDeficit) or 999
			if ad ~= bd then
				return ad < bd
			end
			if a.score == b.score then
				return (a.hash or "") < (b.hash or "")
			end
			return a.score > b.score
		end)
		while #ctx.nearArchive > 40 do
			ctx.nearArchive[#ctx.nearArchive] = nil
		end
	end
end

local function applyIfNeeded(state, catalog, appliedFp)
	local fp = fingerprint(state.loadout, catalog)
	if appliedFp == fp then
		return appliedFp, build.calcsTab:GetMiscCalculator()
	end
	local calcFunc = oracle.applyState(state.loadout, catalog)
	return fp, calcFunc
end

local function evaluateSlot(state, slotName, candidate, ctx)
	ctx.metrics.generated = ctx.metrics.generated + 1
	local newLoadout = copyMap(state.loadout)
	if not candidate or candidate.kind == "empty" then
		newLoadout[slotName] = nil
	else
		newLoadout[slotName] = candidate.id
	end
	local hash = cacheMod.loadoutHash(ctx.identity, newLoadout)
	local cached = cacheMod.get(ctx.cache, hash)
	if cached then
		ctx.metrics.cacheHits = ctx.metrics.cacheHits + 1
		ctx.metrics.tested = ctx.metrics.tested + 1
		local result = {
			loadout = cached.loadout,
			score = cached.score,
			stats = cached.stats,
			hash = cached.hash,
			slot = slotName,
			itemName = cached.itemName,
			kind = cached.kind,
		}
		attachClassif(result, ctx, slotName)
		considerNear(ctx, result)
		if ctx.constrainRes and result.classif.impossible then
			ctx.metrics.prunedImpossible = (ctx.metrics.prunedImpossible or 0) + 1
			return nil
		end
		return result
	end

	local bound = pruning.upperBound(state, slotName, candidate)
	if pruning.shouldPrune(bound, ctx.bestScore) then
		ctx.metrics.pruned = ctx.metrics.pruned + 1
		return nil
	end

	local stats, err
	local kind = candidate and candidate.kind or "empty"
	if slotsMod.isSupportSlot(slotName) then
		local idx = tonumber(slotName:match("(%d+)")) or 1
		stats, err = oracle.whatIfSupport(idx, kind == "empty" and nil or candidate)
	elseif slotsMod.isAuraSlot(slotName) then
		local idx = tonumber(slotName:match("(%d+)")) or 1
		stats, err = oracle.whatIfAura(idx, kind == "empty" and nil or candidate)
	elseif slotsMod.isTreeSlot(slotName) or slotsMod.isAscendSlot(slotName) then
		if kind == "empty" or not candidate or not candidate.nodeId then
			stats, err = oracle.whatIfCurrent()
		else
			local node = build.spec.nodes[candidate.nodeId]
			build.spec:BuildAllDependsAndPaths()
			if not node or not node.path then
				ctx.metrics.invalid = ctx.metrics.invalid + 1
				return nil
			end
			local used, ascUsed = build.spec:CountAllocNodes()
			local cost = node.pathDist or 0
			if candidate.ascendancy then
				if ascUsed + cost > 8 then
					ctx.metrics.invalid = ctx.metrics.invalid + 1
					return nil
				end
			elseif used + cost > oracle.pointBudget() then
				ctx.metrics.invalid = ctx.metrics.invalid + 1
				return nil
			end
			stats, err = oracle.whatIfNotable(candidate.nodeId)
		end
	elseif not candidate or kind == "empty" then
		stats, err = oracle.whatIfItemObject(slotName, nil)
	else
		if candidate.reqLevel and candidate.reqLevel > ctx.identity.level then
			ctx.metrics.invalid = ctx.metrics.invalid + 1
			return nil
		end
		local item = candidate.item or (candidate.itemId and build.itemsTab.items[candidate.itemId])
		if not item then
			ctx.metrics.invalid = ctx.metrics.invalid + 1
			return nil
		end
		if not build.itemsTab:IsItemValidForSlot(item, slotName) then
			ctx.metrics.invalid = ctx.metrics.invalid + 1
			return nil
		end
		stats, err = oracle.whatIfItemObject(slotName, item)
	end
	ctx.metrics.pobEvals = ctx.metrics.pobEvals + 1
	if not stats then
		ctx.metrics.errors = ctx.metrics.errors + 1
		log("[optimize] eval error %s %s: %s", slotName, candidate and candidate.name or "(empty)", tostring(err))
		return nil
	end
	local result = {
		loadout = newLoadout,
		score = scoreOf(stats, ctx.objective),
		stats = stats,
		hash = hash,
		slot = slotName,
		itemName = (candidate and candidate.kind ~= "empty") and candidate.name or "(empty)",
		kind = candidate and candidate.kind or "empty",
	}
	attachClassif(result, ctx, slotName)
	cacheMod.put(ctx.cache, hash, result)
	ctx.metrics.tested = ctx.metrics.tested + 1
	considerNear(ctx, result)
	if ctx.constrainRes and result.classif.impossible then
		ctx.metrics.prunedImpossible = (ctx.metrics.prunedImpossible or 0) + 1
		return nil
	end
	if not ctx.bestScore or result.score > ctx.bestScore then
		ctx.bestScore = result.score
	end
	if result.classif.feasible then
		if not ctx.bestFeasibleScore or result.score > ctx.bestFeasibleScore then
			ctx.bestFeasibleScore = result.score
		end
	end
	if candidate and (candidate.kind == "generated_rare" or candidate.kind == "rare") then
		ctx.metrics.rareTested = (ctx.metrics.rareTested or 0) + 1
		local parentFeasible = state.classif and state.classif.feasible
		local nowFeasible = result.classif and result.classif.feasible
		local dpsGain = 0
		if state.score and state.score > 0 then
			dpsGain = (result.score - state.score) / state.score * 100
		end
		if (nowFeasible and not parentFeasible) or dpsGain >= 12 then
			ctx.discoveries = ctx.discoveries or {}
			if #ctx.discoveries < 40 then
				local reason
				if nowFeasible and not parentFeasible then
					reason = "Rare supplies missing resistances, allowing the current offensive pieces to remain equipped."
				else
					reason = string.format("Rare increased CombinedDPS by %.1f%% on this slot.", dpsGain)
				end
				ctx.discoveries[#ctx.discoveries + 1] = {
					slot = slotName,
					rare = candidate.name,
					base = candidate.base,
					role = candidate.role,
					dpsGainPct = dpsGain,
					before = state.score,
					after = result.score,
					resBefore = state.classif and resist.formatRes(state.classif.res) or nil,
					resAfter = result.classif and resist.formatRes(result.classif.res) or nil,
					reason = reason,
				}
			end
		end
	elseif candidate and candidate.kind == "unique" then
		ctx.metrics.uniqueTested = (ctx.metrics.uniqueTested or 0) + 1
	end
	return result
end

local function byDpsThenHash(a, b)
	if a.score == b.score then
		return a.hash < b.hash
	end
	return a.score > b.score
end

local function byResThenDps(a, b)
	local ac = a.classif or {}
	local bc = b.classif or {}
	if (ac.minRes or 0) ~= (bc.minRes or 0) then
		return (ac.minRes or 0) > (bc.minRes or 0)
	end
	if (ac.sumRes or 0) ~= (bc.sumRes or 0) then
		return (ac.sumRes or 0) > (bc.sumRes or 0)
	end
	return byDpsThenHash(a, b)
end

local function byDeficitThenDps(a, b)
	local ac = a.classif or {}
	local bc = b.classif or {}
	if (ac.totalDeficit or 0) ~= (bc.totalDeficit or 0) then
		return (ac.totalDeficit or 0) < (bc.totalDeficit or 0)
	end
	if (ac.minRes or 0) ~= (bc.minRes or 0) then
		return (ac.minRes or 0) > (bc.minRes or 0)
	end
	return byDpsThenHash(a, b)
end

local function copyList(src)
	local out = {}
	for i, v in ipairs(src) do
		out[i] = v
	end
	return out
end

local function takeUnique(src, dest, seen, limit)
	for _, result in ipairs(src) do
		if #dest >= limit then
			return
		end
		if result.hash and not seen[result.hash] then
			seen[result.hash] = true
			dest[#dest + 1] = result
		end
	end
end

local function keepTop(results, beamSize, ctx)
	beamSize = beamSize or 100
	if not ctx or not ctx.constrainRes then
		table.sort(results, byDpsThenHash)
		local kept = {}
		local seen = {}
		for _, result in ipairs(results) do
			if not seen[result.hash] then
				seen[result.hash] = true
				kept[#kept + 1] = result
				if #kept >= beamSize then
					break
				end
			end
		end
		return kept
	end

	-- Quotas so high-DPS uncapped states cannot occupy the whole beam.
	-- 1. already feasible, best CombinedDPS
	-- 2. almost valid / still cappable, smallest deficit then DPS
	-- 3. still-cappable high DPS (damage path)
	-- 4. defensive seeds (high minRes / sumRes)
	local feasible, near = {}, {}
	local seenAll = {}
	for _, result in ipairs(results) do
		if result.hash and not seenAll[result.hash] then
			seenAll[result.hash] = true
			local c = result.classif
			if c and c.feasible then
				feasible[#feasible + 1] = result
			elseif not c or not c.impossible then
				near[#near + 1] = result
			end
		end
	end
	table.sort(feasible, byDpsThenHash)
	local nearByDps = copyList(near)
	local nearByDeficit = copyList(near)
	local nearByRes = copyList(near)
	table.sort(nearByDps, byDpsThenHash)
	table.sort(nearByDeficit, byDeficitThenDps)
	table.sort(nearByRes, byResThenDps)

	local nValid, nAlmost, nDpsNear, nRes
	if #feasible == 0 then
		nValid = 0
		nAlmost = math.floor(beamSize * 0.35)
		nDpsNear = math.floor(beamSize * 0.40)
		nRes = beamSize - nAlmost - nDpsNear
	else
		nValid = math.min(#feasible, math.floor(beamSize * 0.45))
		nAlmost = math.floor(beamSize * 0.25)
		nDpsNear = math.floor(beamSize * 0.15)
		nRes = beamSize - nValid - nAlmost - nDpsNear
	end

	local kept = {}
	local seen = {}
	takeUnique(feasible, kept, seen, nValid)
	takeUnique(nearByDeficit, kept, seen, #kept + nAlmost)
	takeUnique(nearByDps, kept, seen, #kept + nDpsNear)
	takeUnique(nearByRes, kept, seen, #kept + nRes)
	takeUnique(feasible, kept, seen, beamSize)
	takeUnique(nearByDps, kept, seen, beamSize)
	takeUnique(nearByDeficit, kept, seen, beamSize)
	takeUnique(nearByRes, kept, seen, beamSize)

	if ctx.metrics then
		local f, n = 0, 0
		for _, r in ipairs(kept) do
			if r.classif and r.classif.feasible then
				f = f + 1
			elseif r.classif and r.classif.near then
				n = n + 1
			end
		end
		ctx.metrics.feasibleKept = f
		ctx.metrics.nearKept = n
	end
	return kept
end

local function expandSlot(beam, slotName, catalog, ctx)
	local slotCandidates = catalog.bySlot[slotName] or {}
	local available = #slotCandidates + 1
	local remaining, remainingCount = remainingFor(ctx, slotName)
	local nUnique, nRare = 0, 0
	for _, cand in ipairs(slotCandidates) do
		if cand.kind == "unique" then
			nUnique = nUnique + 1
		else
			nRare = nRare + 1
		end
	end
	log("--------------------------------")
	log("%s optimization", slotName)
	log("")
	log("Candidates available: %d uniques + %d rares + empty", nUnique, nRare)
	log("Beam states: %d", #beam)
	if ctx.constrainRes then
		log("Slots still after this one: %d", remainingCount)
		log("Max remaining res F/C/L: +%d / +%d / +%d", remaining.fire, remaining.cold, remaining.lightning)
	end

	local nextResults = {}
	local appliedFp = nil
	local started = os.clock()

	for _, state in ipairs(beam) do
		appliedFp = applyIfNeeded(state, catalog, appliedFp)
		local usedName, usedId = usedKeys(state.loadout, catalog)

		local emptyResult = evaluateSlot(state, slotName, EMPTY, ctx)
		if emptyResult then
			nextResults[#nextResults + 1] = emptyResult
		end

		for _, cand in ipairs(slotCandidates) do
			if isBlocked(cand, usedName, usedId) then
				ctx.metrics.duplicates = ctx.metrics.duplicates + 1
			else
				local result = evaluateSlot(state, slotName, cand, ctx)
				if result then
					nextResults[#nextResults + 1] = result
				end
			end
		end
	end

	local elapsed = os.clock() - started
	local kept = keepTop(nextResults, ctx.beamSize, ctx)
	ctx.metrics.eliminatedBeam = ctx.metrics.eliminatedBeam + math.max(0, #nextResults - #kept)

	local best = kept[1]
	local bestFeasible
	for _, r in ipairs(kept) do
		if r.classif and r.classif.feasible then
			bestFeasible = r
			break
		end
	end
	local improvement = 0
	if ctx.baselineScore and ctx.baselineScore > 0 and best then
		improvement = (best.score - ctx.baselineScore) / ctx.baselineScore * 100
	end
	log("")
	log("Generated this step: %d", #nextResults)
	log("Kept: %d  (feasible %d, near %d)", #kept, ctx.metrics.feasibleKept or 0, ctx.metrics.nearKept or 0)
	log("Pruned impossible (cumulative): %d", ctx.metrics.prunedImpossible or 0)
	if best then
		local c = best.classif
		log("Best in beam: %s  DPS %.1f  res %s", best.itemName, best.score, c and resist.formatRes(c.res) or "?")
		log("Improvement vs baseline: %+.2f%%", improvement)
	end
	if bestFeasible then
		log("Best feasible: %s  DPS %.1f  res %s", bestFeasible.itemName, bestFeasible.score, resist.formatRes(bestFeasible.classif.res))
	end
	log("Step time: %.2fs", elapsed)
	log("")

	return kept
end

local function run(params)
	params = params or {}
	local catalog = params.catalog
	local slots = params.slots or slotsMod.GEAR_SLOTS
	local ctx = {
		identity = params.identity,
		objective = params.objective or "MAX_DPS",
		beamSize = params.beamSize or 100,
		cache = params.cache,
		metrics = params.metrics or pruning.new(),
		baselineScore = params.baselineScore or 0,
		bestScore = params.baselineScore or 0,
		bestFeasibleScore = nil,
		constrainRes = params.constrainRes,
		resThreshold = params.resThreshold or 75,
		constraints = params.constraints,
		catalog = catalog,
		slots = slots,
		nearArchive = {},
		discoveries = {},
	}

	local beam = {
		{
			loadout = {},
			score = params.baselineScore or 0,
			stats = params.baselineStats,
			hash = cacheMod.loadoutHash(ctx.identity, {}),
			itemName = "(baseline)",
			kind = "empty",
		},
	}
	cacheMod.put(ctx.cache, beam[1].hash, beam[1])

	for _, slotName in ipairs(slots) do
		beam = expandSlot(beam, slotName, catalog, ctx)
		if params.onAfterSlot then
			params.onAfterSlot(slotName, beam, ctx)
		end
		if #beam == 0 then
			log("[optimize] beam emptied at %s", slotName)
			break
		end
	end
	return beam, ctx
end

return {
	run = run,
	keepTop = keepTop,
	describeLoadout = describeLoadout,
	evaluateSlot = evaluateSlot,
	applyIfNeeded = applyIfNeeded,
	usedKeys = usedKeys,
	isBlocked = isBlocked,
	EMPTY = EMPTY,
}
