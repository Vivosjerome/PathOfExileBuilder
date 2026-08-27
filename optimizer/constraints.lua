-- Generic constraints on PoB stats.
-- Feasible = every min/max is met on the real PoB snapshot.
-- Impossible is only used when remaining capacity cannot cover a min
-- (resist remaining is bounded; other stats stay uncertain until the last slot).

local resist = require("optimizer.resist")

local ALIASES = {
	dps = "CombinedDPS",
	combineddps = "CombinedDPS",
	["combined-dps"] = "CombinedDPS",
	totaldps = "TotalDPS",
	fulldps = "FullDPS",
	life = "Life",
	es = "EnergyShield",
	energyshield = "EnergyShield",
	ehp = "TotalEHP",
	fire = "FireResist",
	fireres = "FireResist",
	fireresist = "FireResist",
	fireresistance = "FireResist",
	cold = "ColdResist",
	coldres = "ColdResist",
	coldresist = "ColdResist",
	lightning = "LightningResist",
	lightres = "LightningResist",
	lightningresist = "LightningResist",
	chaos = "ChaosResist",
	chaosres = "ChaosResist",
	crit = "CritChance",
	critchance = "CritChance",
	critdamage = "CritMultiplier",
	critdmg = "CritMultiplier",
	critmulti = "CritMultiplier",
	critmultiplier = "CritMultiplier",
	ward = "Ward",
	ehp = "TotalEHP",
	totaleshp = "TotalEHP",
	movespeed = "MovementSpeedMod",
	movement = "MovementSpeedMod",
	armour = "Armour",
	armor = "Armour",
	evasion = "Evasion",
	suppression = "SpellSuppressionChance",
	spellsuppression = "SpellSuppressionChance",
	mana = "Mana",
	block = "BlockChance",
	spellblock = "SpellBlockChance",
}

local RESIST_KEYS = {
	FireResist = "fire",
	ColdResist = "cold",
	LightningResist = "lightning",
}

local function canonical(key)
	if not key then
		return nil
	end
	if ALIASES[key] then
		return ALIASES[key]
	end
	local lower = string.lower(tostring(key)):gsub("[^%w]", "")
	return ALIASES[lower] or key
end

local function normalizeSpec(spec)
	spec = spec or {}
	local min, max = {}, {}
	for k, v in pairs(spec.min or {}) do
		min[canonical(k)] = tonumber(v)
	end
	for k, v in pairs(spec.max or {}) do
		max[canonical(k)] = tonumber(v)
	end
	return { min = min, max = max }
end

local function hasAny(spec)
	spec = normalizeSpec(spec)
	for _ in pairs(spec.min) do
		return true
	end
	for _ in pairs(spec.max) do
		return true
	end
	return false
end

local function statValue(stats, key)
	stats = stats or {}
	return tonumber(stats[key]) or 0
end

local function check(stats, spec)
	spec = normalizeSpec(spec)
	local failed = {}
	for key, need in pairs(spec.min) do
		if statValue(stats, key) < need then
			failed[#failed + 1] = { stat = key, op = "min", need = need, got = statValue(stats, key) }
		end
	end
	for key, cap in pairs(spec.max) do
		if statValue(stats, key) > cap then
			failed[#failed + 1] = { stat = key, op = "max", need = cap, got = statValue(stats, key) }
		end
	end
	return #failed == 0, failed
end

local function classify(stats, remainingRes, remainingCount, spec)
	spec = normalizeSpec(spec)
	stats = stats or {}
	remainingRes = remainingRes or { fire = 0, cold = 0, lightning = 0 }
	remainingCount = remainingCount or 0

	local res = resist.fromStats(stats)
	local deficit = {}
	local totalDeficit = 0
	local feasible = true
	local impossible = false

	for key, need in pairs(spec.min) do
		local got = statValue(stats, key)
		local missing = math.max(0, need - got)
		deficit[key] = missing
		if missing > 0 then
			feasible = false
			totalDeficit = totalDeficit + missing
			local elem = RESIST_KEYS[key]
			if elem then
				if got + (remainingRes[elem] or 0) < need then
					impossible = true
				end
			elseif remainingCount <= 0 then
				impossible = true
			end
		end
	end
	for key, cap in pairs(spec.max) do
		local got = statValue(stats, key)
		if got > cap then
			feasible = false
			deficit[key] = (deficit[key] or 0) + (got - cap)
			totalDeficit = totalDeficit + (got - cap)
			if remainingCount <= 0 then
				impossible = true
			end
		end
	end

	return {
		res = res,
		deficit = deficit,
		totalDeficit = totalDeficit,
		minRes = math.min(res.fire, res.cold, res.lightning),
		sumRes = res.fire + res.cold + res.lightning,
		feasible = feasible,
		near = (not feasible) and (not impossible),
		impossible = impossible,
	}
end

return {
	ALIASES = ALIASES,
	canonical = canonical,
	normalizeSpec = normalizeSpec,
	hasAny = hasAny,
	check = check,
	classify = classify,
}
