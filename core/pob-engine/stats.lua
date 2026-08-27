-- Extract a stable subset of PoB actor.output for scoring and tests.

local catalog = require("build.stats_catalog")

local STAT_KEYS = catalog.keys()
local seenKeys = {}
for _, key in ipairs(STAT_KEYS) do
	seenKeys[key] = true
end
for _, extra in ipairs({ "HitSpeed", "LifeUnreserved", "ManaUnreserved" }) do
	if not seenKeys[extra] then
		STAT_KEYS[#STAT_KEYS + 1] = extra
		seenKeys[extra] = true
	end
end

local function snapshot(output)
	local stats = {}
	if not output then
		return stats
	end
	for _, key in ipairs(STAT_KEYS) do
		local value = output[key]
		if type(value) == "number" then
			stats[key] = value
		end
	end
	return stats
end

local function diff(reference, actual, epsilon)
	epsilon = epsilon or 0
	local rows = {}
	local maxAbs = 0
	local maxPct = 0
	local keys = {}
	local seen = {}
	for _, key in ipairs(STAT_KEYS) do
		keys[#keys + 1] = key
		seen[key] = true
	end
	for key in pairs(reference or {}) do
		if not seen[key] then
			keys[#keys + 1] = key
			seen[key] = true
		end
	end
	for key in pairs(actual or {}) do
		if not seen[key] then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local a = (reference and reference[key]) or 0
		local b = (actual and actual[key]) or 0
		if type(a) == "number" and type(b) == "number" then
			local abs = math.abs(a - b)
			local pct = 0
			if a ~= 0 then
				pct = abs / math.abs(a) * 100
			elseif b ~= 0 then
				pct = 100
			end
			if abs > epsilon then
				rows[#rows + 1] = {
					stat = key,
					reference = a,
					actual = b,
					abs = abs,
					pct = pct,
				}
				if abs > maxAbs then
					maxAbs = abs
				end
				if pct > maxPct then
					maxPct = pct
				end
			end
		end
	end
	return {
		ok = #rows == 0,
		maxAbs = maxAbs,
		maxPct = maxPct,
		differences = rows,
	}
end

return {
	KEYS = STAT_KEYS,
	snapshot = snapshot,
	diff = diff,
}
