local slotsMod = require("items.slots")
local beam = require("optimizer.beam")
local Candidate = require("items.candidate")

local EMPTY = Candidate.empty()

local function log(fmt, ...)
	io.stderr:write(string.format(fmt, ...) .. "\n")
	io.stderr:flush()
end

local function run(states, catalog, ctx)
	local rounds = ctx.mutationRounds or 2
	local topN = math.min(ctx.mutationTop or 5, #states)
	if topN == 0 then
		return states
	end
	log("--------------------------------")
	log("Local mutations")
	log("States: %d  rounds: %d", topN, rounds)

	local pool = {}
	for i = 1, #states do
		pool[#pool + 1] = states[i]
	end

	for round = 1, rounds do
		local improved = false
		local beforeBest = 0
		if ctx.constrainRes then
			for _, r in ipairs(pool) do
				if r.classif and r.classif.feasible and r.score > beforeBest then
					beforeBest = r.score
				end
			end
		else
			beforeBest = pool[1] and pool[1].score or 0
		end
		log("Mutation round %d  current best: %.4f", round, beforeBest)
		for i = 1, topN do
			local state = pool[i]
			if state then
				local appliedFp = nil
				appliedFp = beam.applyIfNeeded(state, catalog, appliedFp)
				local usedName, usedId = beam.usedKeys(state.loadout, catalog)
				for _, slotName in ipairs(ctx.slots or slotsMod.GEAR_SLOTS) do
					local emptyResult = beam.evaluateSlot(state, slotName, EMPTY, ctx)
					if emptyResult then
						pool[#pool + 1] = emptyResult
					end
					for _, cand in ipairs(catalog.bySlot[slotName] or {}) do
						if beam.isBlocked(cand, usedName, usedId) then
							ctx.metrics.duplicates = ctx.metrics.duplicates + 1
						else
							local result = beam.evaluateSlot(state, slotName, cand, ctx)
							if result then
								pool[#pool + 1] = result
							end
						end
					end
				end
			end
		end
		pool = beam.keepTop(pool, math.max(ctx.beamSize, topN), ctx)
		topN = math.min(topN, #pool)
		local bestFeasible = 0
		for _, r in ipairs(pool) do
			if r.classif and r.classif.feasible and r.score > bestFeasible then
				bestFeasible = r.score
			end
		end
		local newBest = pool[1] and pool[1].score or 0
		if ctx.constrainRes then
			if bestFeasible > beforeBest + 1e-6 then
				improved = true
				log("  new best feasible: %.4f", bestFeasible)
			end
			beforeBest = math.max(beforeBest, bestFeasible)
		elseif newBest > beforeBest + 1e-6 then
			improved = true
			log("  new best: %.4f (%s)", newBest, pool[1].itemName or "?")
			beforeBest = newBest
		end
		if not improved then
			log("  no improvement, stop")
			break
		end
	end
	return pool
end

return {
	run = run,
}
