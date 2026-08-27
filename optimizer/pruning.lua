local function newMetrics()
	return {
		generated = 0,
		tested = 0,
		pobEvals = 0,
		cacheHits = 0,
		invalid = 0,
		duplicates = 0,
		errors = 0,
		pruned = 0,
		prunedImpossible = 0,
		eliminatedBeam = 0,
		feasibleKept = 0,
		nearKept = 0,
	}
end

-- Conservative bound: never prune unless a proven upper bound is below the best.
-- This phase returns +inf so nothing is dropped by branch-and-bound.
local function upperBound()
	return math.huge
end

local function shouldPrune(bound, bestScore)
	if bound == nil or bound == math.huge then
		return false
	end
	if bestScore == nil then
		return false
	end
	return bound < bestScore
end

return {
	new = newMetrics,
	upperBound = upperBound,
	shouldPrune = shouldPrune,
}
