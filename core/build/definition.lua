-- BuildDefinition: user request for the PoE Build Optimizer.
-- This is the product contract. Search, UI, and CLI all speak this shape.

local scorer = require("optimizer.scorer")
local statsCatalog = require("build.stats_catalog")

local OBJECTIVES = {
	MAX_DPS = true,
	MAX_TOTAL_DPS = true,
	MAX_FULL_DPS = true,
	MAX_LIFE = true,
	MAX_ES = true,
	MAX_EHP = true,
	MAX_ARMOUR = true,
	MAX_EVASION = true,
	MAX_SUPPRESSION = true,
	MAX_CRIT = true,
	MAX_CRIT_MULTI = true,
	MAX_BLOCK = true,
	MAX_SPELL_BLOCK = true,
	MAX_WARD = true,
	MAX_MANA = true,
}

local OBJECTIVE_ALIASES = {
	dps = "MAX_DPS",
	["combined-dps"] = "MAX_DPS",
	combineddps = "MAX_DPS",
	life = "MAX_LIFE",
	es = "MAX_ES",
	ehp = "MAX_EHP",
	defence = "MAX_EHP",
	defense = "MAX_EHP",
	armour = "MAX_ARMOUR",
	armor = "MAX_ARMOUR",
	evasion = "MAX_EVASION",
	suppression = "MAX_SUPPRESSION",
	crit = "MAX_CRIT",
	critmulti = "MAX_CRIT_MULTI",
	critmultiplier = "MAX_CRIT_MULTI",
	block = "MAX_BLOCK",
	spellblock = "MAX_SPELL_BLOCK",
	ward = "MAX_WARD",
	mana = "MAX_MANA",
}

local function copy(src)
	local out = {}
	for k, v in pairs(src or {}) do
		out[k] = v
	end
	return out
end

local function resolveObjective(name)
	if not name or name == "" then
		return "MAX_DPS"
	end
	if OBJECTIVES[name] then
		return name
	end
	local lower = string.lower(tostring(name))
	if OBJECTIVE_ALIASES[lower] then
		return OBJECTIVE_ALIASES[lower]
	end
	if statsCatalog.has(name) then
		return name
	end
	local stripped = tostring(name):gsub("^MAX_", "")
	if statsCatalog.has(stripped) then
		return name
	end
	return name
end

local function normalizeSkill(skill)
	if type(skill) == "string" then
		return { name = skill, level = 20, quality = 20, supports = {} }
	end
	skill = skill or {}
	return {
		name = skill.name or skill.skill or "Winter Orb",
		level = tonumber(skill.level or skill.skillLevel) or 20,
		quality = tonumber(skill.quality or skill.skillQuality) or 20,
		supports = skill.supports or {},
		slot = skill.slot or "Body Armour",
		stages = skill.stages or skill.skillStageCount or 10,
	}
end

local function normalizeSearch(search)
	search = search or {}
	local out = {
		gear = search.gear ~= false,
		rares = search.rares ~= false,
		jewels = search.jewels == true,
		gems = search.gems == true or search.supports == true,
		flasks = search.flasks == true,
		tree = search.tree == true,
		ascendancy = search.ascendancy == true,
		cluster = search.cluster == true,
		timeless = search.timeless == true,
		beamSize = tonumber(search.beamSize) or 100,
		mutationRounds = tonumber(search.mutationRounds) or 2,
		mutationTop = tonumber(search.mutationTop) or 5,
		dryRun = search.dryRun == true,
		slots = search.slots,
		maxRaresPerSlot = search.maxRaresPerSlot,
		maxBasesPerSlot = search.maxBasesPerSlot,
		maxJewelSockets = tonumber(search.maxJewelSockets) or 3,
		maxJewelPathPoints = tonumber(search.maxJewelPathPoints) or 24,
		maxJewelRares = tonumber(search.maxJewelRares) or 40,
	}
	return out
end

local function normalizeConstraints(raw)
	raw = raw or {}
	local min = copy(raw.min or raw.minimum)
	local max = copy(raw.max or raw.maximum)
	-- Shorthand: { FireResist = 75 } means min
	for k, v in pairs(raw) do
		if k ~= "min" and k ~= "max" and k ~= "minimum" and k ~= "maximum" and type(v) == "number" then
			if min[k] == nil then
				min[k] = v
			end
		end
	end
	return { min = min, max = max }
end

local function normalize(raw)
	raw = raw or {}
	local skill = normalizeSkill(raw.skill or raw.skillName)
	local def = {
		class = raw.class or "Witch",
		ascendancy = raw.ascendancy or "Elementalist",
		level = tonumber(raw.level) or 90,
		skill = skill,
		objective = resolveObjective(raw.objective or raw.maximize),
		constraints = normalizeConstraints(raw.constraints),
		search = normalizeSearch(raw.search),
		config = copy(raw.config),
		topN = tonumber(raw.topN) or 20,
	}
	local obj = def.objective
	local objKey = type(obj) == "string" and obj:gsub("^MAX_", "") or obj
	if not OBJECTIVES[obj] and not scorer.OBJECTIVES[obj] and not statsCatalog.has(obj) and not statsCatalog.has(objKey) then
		return nil, "unknown objective: " .. tostring(obj)
	end
	return def
end

-- Defaults matching the product: max CombinedDPS with 75/75/75, gear+rares.
local function defaults()
	return normalize({
		class = "Witch",
		ascendancy = "Elementalist",
		level = 90,
		skill = { name = "Winter Orb", level = 20, quality = 20 },
		objective = "MAX_DPS",
		constraints = {
			min = {
				FireResist = 75,
				ColdResist = 75,
				LightningResist = 75,
			},
		},
		search = {
			gear = true,
			rares = true,
			jewels = false,
			gems = false,
			flasks = false,
			tree = false,
			beamSize = 100,
		},
	})
end

local function toEngineParams(def)
	def = def or defaults()
	local min = def.constraints.min or {}
	local hasMin = false
	for _ in pairs(min) do
		hasMin = true
		break
	end
	local hasMax = false
	for _ in pairs(def.constraints.max or {}) do
		hasMax = true
		break
	end
	return {
		class = def.class,
		ascendancy = def.ascendancy,
		level = def.level,
		skill = def.skill.name,
		skillLevel = def.skill.level,
		skillQuality = def.skill.quality,
		objective = def.objective,
		beamSize = def.search.beamSize,
		slots = def.search.slots,
		includeRares = def.search.rares,
		constrainRes = hasMin or hasMax,
		resThreshold = min.FireResist or min.ColdResist or min.LightningResist or 75,
		constraints = def.constraints,
		config = def.config,
		topN = def.topN,
		mutationRounds = def.search.mutationRounds,
		mutationTop = def.search.mutationTop,
		maxRaresPerSlot = def.search.maxRaresPerSlot,
		maxBasesPerSlot = def.search.maxBasesPerSlot,
		includeJewels = def.search.jewels == true,
		includeGems = def.search.gems == true,
		includeFlasks = def.search.flasks == true,
		includeTree = def.search.tree == true,
		includeAscendancy = def.search.ascendancy == true,
		includeCluster = def.search.cluster == true,
		includeTimeless = def.search.timeless == true,
		maxJewelSockets = def.search.maxJewelSockets,
		maxJewelPathPoints = def.search.maxJewelPathPoints,
		maxJewelRares = def.search.maxJewelRares,
		product = true,
	}
end

return {
	OBJECTIVES = OBJECTIVES,
	normalize = normalize,
	defaults = defaults,
	toEngineParams = toEngineParams,
	resolveObjective = resolveObjective,
}
