-- Objective adapters. PoB output is the only source of numeric truth.

local OBJECTIVES = {
	MAX_DPS = function(output)
		return output.CombinedDPS or output.TotalDPS or 0
	end,
	MAX_TOTAL_DPS = function(output)
		return output.TotalDPS or 0
	end,
	MAX_FULL_DPS = function(output)
		return output.FullDPS or output.CombinedDPS or 0
	end,
	MAX_LIFE = function(output)
		return output.Life or 0
	end,
	MAX_ES = function(output)
		return output.EnergyShield or 0
	end,
	MAX_EHP = function(output)
		return output.TotalEHP or 0
	end,
	MAX_ARMOUR = function(output)
		return output.Armour or 0
	end,
	MAX_EVASION = function(output)
		return output.Evasion or 0
	end,
	MAX_SUPPRESSION = function(output)
		return output.SpellSuppressionChance or 0
	end,
	MAX_CRIT = function(output)
		return output.CritChance or 0
	end,
	MAX_CRIT_MULTI = function(output)
		return output.CritMultiplier or 0
	end,
	MAX_BLOCK = function(output)
		return output.BlockChance or 0
	end,
	MAX_SPELL_BLOCK = function(output)
		return output.SpellBlockChance or 0
	end,
	MAX_WARD = function(output)
		return output.Ward or 0
	end,
	MAX_MANA = function(output)
		return output.Mana or 0
	end,
}

local function score(output, objective)
	output = output or {}
	objective = objective or "MAX_DPS"
	local fn = OBJECTIVES[objective]
	if fn then
		return fn(output)
	end
	local key = objective
	if type(key) == "string" and key:sub(1, 4) == "MAX_" then
		key = key:sub(5)
	end
	return tonumber(output[key]) or 0
end

return {
	OBJECTIVES = OBJECTIVES,
	score = score,
}
