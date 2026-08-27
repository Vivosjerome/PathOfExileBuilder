-- Heuristic ranking of PoB explicit mods. NEVER used as the final DPS score.
-- Every spawnable mod is eligible; this only orders generation.

local TAG_WEIGHT = {
	caster_damage = 14,
	damage = 7,
	caster = 9,
	speed = 12,
	critical = 12,
	life = 5,
	energy_shield = 4,
	mana = 3,
	resistance = 8,
	elemental = 3,
	cold = 5,
	fire = 2,
	lightning = 2,
	attribute = 3,
	resource = 2,
	chaos = 1,
}

local LINE_RULES = {
	{ pattern = "[Ss]pell [Dd]amage", weight = 1.6, bucket = "offense" },
	{ pattern = "[Cc]ast [Ss]peed", weight = 1.7, bucket = "offense" },
	{ pattern = "[Cc]ritical [Ss]trike [Mm]ultiplier", weight = 1.6, bucket = "offense" },
	{ pattern = "[Ss]pell [Cc]ritical", weight = 1.5, bucket = "offense" },
	{ pattern = "[Cc]ritical [Ss]trike [Cc]hance", weight = 1.3, bucket = "offense" },
	{ pattern = "[Cc]old [Dd]amage", weight = 1.5, bucket = "offense" },
	{ pattern = "[Ff]ire [Dd]amage", weight = 0.9, bucket = "offense" },
	{ pattern = "[Ll]ightning [Dd]amage", weight = 0.9, bucket = "offense" },
	{ pattern = "[Ee]lemental [Dd]amage", weight = 1.2, bucket = "offense" },
	{ pattern = "[Pp]enetration", weight = 1.4, bucket = "offense" },
	{ pattern = "maximum Life", weight = 1.1, bucket = "life" },
	{ pattern = "maximum Energy Shield", weight = 1.0, bucket = "es" },
	{ pattern = "maximum Mana", weight = 0.7, bucket = "defense" },
	{ pattern = "Fire Resistance", weight = 1.3, bucket = "resist" },
	{ pattern = "Cold Resistance", weight = 1.3, bucket = "resist" },
	{ pattern = "Lightning Resistance", weight = 1.3, bucket = "resist" },
	{ pattern = "all Elemental Resistances", weight = 1.8, bucket = "resist" },
	{ pattern = "to Intelligence", weight = 0.8, bucket = "attr" },
	{ pattern = "to Dexterity", weight = 0.5, bucket = "attr" },
	{ pattern = "to Strength", weight = 0.5, bucket = "attr" },
	{ pattern = "to all Attributes", weight = 1.0, bucket = "attr" },
}

local function maxNumber(text)
	local best = 0
	for n in string.gmatch(text or "", "%-?%d+%.?%d*") do
		local v = math.abs(tonumber(n) or 0)
		if v > best then
			best = v
		end
	end
	return best
end

local function scoreText(text)
	text = text or ""
	local offense, defense, resist, life, es = 0, 0, 0, 0, 0
	local matched = false
	local mag = maxNumber(text)
	for _, rule in ipairs(LINE_RULES) do
		if text:find(rule.pattern) then
			matched = true
			local add = mag * rule.weight
			if rule.bucket == "offense" then
				offense = offense + add
			elseif rule.bucket == "resist" then
				resist = resist + add
				defense = defense + add * 0.5
			elseif rule.bucket == "life" then
				life = life + add
				defense = defense + add
			elseif rule.bucket == "es" then
				es = es + add
				defense = defense + add
			else
				defense = defense + add * 0.6
			end
		end
	end
	if not matched and mag > 0 then
		-- Unknown line: keep it discoverable instead of scoring 0.
		offense = offense + mag * 0.08
	end
	return {
		offense = offense,
		defense = defense,
		resist = resist,
		life = life,
		es = es,
		total = offense + defense + resist * 0.35,
	}
end

local function scoreTags(tags)
	local n = 0
	for _, tag in ipairs(tags or {}) do
		n = n + (TAG_WEIGHT[tag] or 1)
	end
	return n
end

local function scoreMod(mod)
	if not mod then
		return { offense = 0, defense = 0, resist = 0, life = 0, es = 0, total = 0, tags = 0 }
	end
	local lines = {}
	for _, line in ipairs(mod) do
		if type(line) == "string" then
			lines[#lines + 1] = line
		end
	end
	local acc = { offense = 0, defense = 0, resist = 0, life = 0, es = 0, total = 0 }
	for _, line in ipairs(lines) do
		local s = scoreText(line)
		acc.offense = acc.offense + s.offense
		acc.defense = acc.defense + s.defense
		acc.resist = acc.resist + s.resist
		acc.life = acc.life + s.life
		acc.es = acc.es + s.es
	end
	local tagScore = scoreTags(mod.modTags)
	acc.offense = acc.offense + tagScore * 0.35
	acc.total = acc.offense + acc.defense + acc.resist * 0.35 + tagScore * 0.15
	acc.tags = tagScore
	acc.lines = lines
	if acc.total <= 0 then
		acc.total = 1
	end
	return acc
end

local function hasTag(mod, want)
	for _, tag in ipairs(mod.modTags or {}) do
		if tag == want then
			return true
		end
	end
	return false
end

local function lineMatches(mod, pattern)
	for _, line in ipairs(mod) do
		if type(line) == "string" and line:find(pattern) then
			return true
		end
	end
	return false
end

return {
	scoreText = scoreText,
	scoreMod = scoreMod,
	scoreTags = scoreTags,
	hasTag = hasTag,
	lineMatches = lineMatches,
}
