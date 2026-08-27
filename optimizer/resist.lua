-- Elemental resistance helpers for constrained search.
-- Chaos is ignored in this phase. Bounds overestimate remaining res so we never
-- prune a branch that could still cap.

local ELEMENTS = { "fire", "cold", "lightning" }
local STAT_KEY = {
	fire = "FireResist",
	cold = "ColdResist",
	lightning = "LightningResist",
}
local MOD_NAMES = {
	FireResist = "fire",
	ColdResist = "cold",
	LightningResist = "lightning",
	ElementalResist = "all",
}

local DEFAULT_THRESHOLD = 75

local function max0(n)
	if not n or n < 0 then
		return 0
	end
	return n
end

local function addModValue(out, name, value)
	if not value then
		return
	end
	local dest = MOD_NAMES[name]
	if dest == "all" then
		out.fire = out.fire + value
		out.cold = out.cold + value
		out.lightning = out.lightning + value
	elseif dest then
		out[dest] = out[dest] + value
	end
end

local function absorbModList(out, modList)
	if not modList then
		return
	end
	for _, mod in ipairs(modList) do
		if type(mod) == "table" and mod.type == "BASE" and mod.name then
			addModValue(out, mod.name, tonumber(mod.value) or 0)
		end
	end
end

local function absorbLines(out, lines)
	if not lines then
		return
	end
	for _, line in ipairs(lines) do
		if line.modList then
			absorbModList(out, line.modList)
		end
	end
end

local function fromItem(item)
	local out = { fire = 0, cold = 0, lightning = 0 }
	if not item then
		return out
	end
	absorbModList(out, item.baseModList)
	absorbLines(out, item.explicitModLines)
	absorbLines(out, item.implicitModLines)
	absorbLines(out, item.enchantModLines)
	absorbLines(out, item.scourgeModLines)
	return out
end

local function fromStats(stats)
	stats = stats or {}
	return {
		fire = stats.FireResist or 0,
		cold = stats.ColdResist or 0,
		lightning = stats.LightningResist or 0,
	}
end

local function deficit(res, threshold)
	threshold = threshold or DEFAULT_THRESHOLD
	return {
		fire = math.max(0, threshold - (res.fire or 0)),
		cold = math.max(0, threshold - (res.cold or 0)),
		lightning = math.max(0, threshold - (res.lightning or 0)),
	}
end

local function totalDeficit(def)
	return (def.fire or 0) + (def.cold or 0) + (def.lightning or 0)
end

local function isFeasible(res, threshold)
	threshold = threshold or DEFAULT_THRESHOLD
	return (res.fire or 0) >= threshold
		and (res.cold or 0) >= threshold
		and (res.lightning or 0) >= threshold
end

local function remainingSlots(slotOrder, currentSlot)
	local out = {}
	local found = false
	for _, slotName in ipairs(slotOrder or {}) do
		if found then
			out[#out + 1] = slotName
		elseif slotName == currentSlot then
			found = true
		end
	end
	return out
end

local function remainingMax(catalog, slotNames)
	local out = { fire = 0, cold = 0, lightning = 0 }
	if not catalog or not catalog.maxResBySlot then
		return out
	end
	for _, slotName in ipairs(slotNames or {}) do
		local m = catalog.maxResBySlot[slotName]
		if m then
			out.fire = out.fire + max0(m.fire)
			out.cold = out.cold + max0(m.cold)
			out.lightning = out.lightning + max0(m.lightning)
		end
	end
	return out
end

-- True if remaining slots could still cover every elemental deficit.
-- Overestimates capacity (independent max per slot/element) on purpose.
local function canStillCap(res, remaining, threshold)
	threshold = threshold or DEFAULT_THRESHOLD
	remaining = remaining or { fire = 0, cold = 0, lightning = 0 }
	return (res.fire or 0) + (remaining.fire or 0) >= threshold
		and (res.cold or 0) + (remaining.cold or 0) >= threshold
		and (res.lightning or 0) + (remaining.lightning or 0) >= threshold
end

local function classify(stats, remaining, threshold)
	threshold = threshold or DEFAULT_THRESHOLD
	local res = fromStats(stats)
	local def = deficit(res, threshold)
	local feasible = isFeasible(res, threshold)
	local capPossible = canStillCap(res, remaining, threshold)
	return {
		res = res,
		deficit = def,
		totalDeficit = totalDeficit(def),
		minRes = math.min(res.fire, res.cold, res.lightning),
		sumRes = res.fire + res.cold + res.lightning,
		feasible = feasible,
		near = (not feasible) and capPossible,
		impossible = not capPossible,
	}
end

local function buildSlotMax(catalog)
	local maxRes = {}
	for slotName, cands in pairs(catalog.bySlot or {}) do
		local m = { fire = 0, cold = 0, lightning = 0 }
		for _, cand in ipairs(cands) do
			local r = cand.resist or { fire = 0, cold = 0, lightning = 0 }
			if (r.fire or 0) > m.fire then m.fire = r.fire end
			if (r.cold or 0) > m.cold then m.cold = r.cold end
			if (r.lightning or 0) > m.lightning then m.lightning = r.lightning end
		end
		maxRes[slotName] = m
	end
	catalog.maxResBySlot = maxRes
	return maxRes
end

local function formatRes(res)
	res = res or {}
	return string.format("%d / %d / %d",
		math.floor((res.fire or 0) + 0.5),
		math.floor((res.cold or 0) + 0.5),
		math.floor((res.lightning or 0) + 0.5))
end

return {
	ELEMENTS = ELEMENTS,
	STAT_KEY = STAT_KEY,
	DEFAULT_THRESHOLD = DEFAULT_THRESHOLD,
	fromItem = fromItem,
	fromStats = fromStats,
	deficit = deficit,
	totalDeficit = totalDeficit,
	isFeasible = isFeasible,
	remainingSlots = remainingSlots,
	remainingMax = remainingMax,
	canStillCap = canStillCap,
	classify = classify,
	buildSlotMax = buildSlotMax,
	formatRes = formatRes,
}
