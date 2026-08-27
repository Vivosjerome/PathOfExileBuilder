-- Stats a player can maximize or constrain. Keys are PoB mainOutput fields.

local STATS = {
	{ key = "CombinedDPS", group = "offence", label = "DPS combiné", unit = "dps", maximize = true },
	{ key = "TotalDPS", group = "offence", label = "DPS du skill", unit = "dps", maximize = true },
	{ key = "FullDPS", group = "offence", label = "Full DPS", unit = "dps", maximize = true },
	{ key = "FullDotDPS", group = "offence", label = "DPS DoT", unit = "dps", maximize = true },
	{ key = "AverageDamage", group = "offence", label = "Dégâts moyens", unit = "number", maximize = true },
	{ key = "AverageHit", group = "offence", label = "Hit moyen", unit = "number", maximize = true },
	{ key = "Speed", group = "offence", label = "Vitesse d'attaque / cast", unit = "number", maximize = true },
	{ key = "HitChance", group = "offence", label = "Chance de toucher", unit = "percent", maximize = true },
	{ key = "CritChance", group = "offence", label = "Chance de crit", unit = "percent", maximize = true },
	{ key = "PreEffectiveCritChance", group = "offence", label = "Crit avant effective", unit = "percent" },
	{ key = "CritMultiplier", group = "offence", label = "Multiplicateur de crit", unit = "multiplier", maximize = true, hint = "× — ex. 5.5" },

	{ key = "Life", group = "defence", label = "Vie", unit = "number", maximize = true },
	{ key = "LifeUnreserved", group = "defence", label = "Vie non réservée", unit = "number", maximize = true },
	{ key = "EnergyShield", group = "defence", label = "Energy Shield", unit = "number", maximize = true },
	{ key = "Ward", group = "defence", label = "Ward", unit = "number", maximize = true },
	{ key = "Mana", group = "defence", label = "Mana", unit = "number", maximize = true },
	{ key = "ManaUnreserved", group = "defence", label = "Mana non réservée", unit = "number" },
	{ key = "TotalEHP", group = "defence", label = "EHP total", unit = "number", maximize = true },
	{ key = "Armour", group = "defence", label = "Armure", unit = "number", maximize = true },
	{ key = "Evasion", group = "defence", label = "Evasion", unit = "number", maximize = true },
	{ key = "SpellSuppressionChance", group = "defence", label = "Spell suppression", unit = "percent", maximize = true },
	{ key = "BlockChance", group = "defence", label = "Block", unit = "percent", maximize = true },
	{ key = "SpellBlockChance", group = "defence", label = "Spell block", unit = "percent", maximize = true },
	{ key = "AttackDodgeChance", group = "defence", label = "Dodge attaque", unit = "percent", maximize = true },
	{ key = "SpellDodgeChance", group = "defence", label = "Dodge spell", unit = "percent", maximize = true },
	{ key = "EvadeChance", group = "defence", label = "Evade", unit = "percent", maximize = true },

	{ key = "FireResist", group = "resist", label = "Résistance feu", unit = "percent" },
	{ key = "ColdResist", group = "resist", label = "Résistance froid", unit = "percent" },
	{ key = "LightningResist", group = "resist", label = "Résistance foudre", unit = "percent" },
	{ key = "ChaosResist", group = "resist", label = "Résistance chaos", unit = "percent" },
	{ key = "FireResistOverCap", group = "resist", label = "Feu overcap", unit = "percent" },
	{ key = "ColdResistOverCap", group = "resist", label = "Froid overcap", unit = "percent" },
	{ key = "LightningResistOverCap", group = "resist", label = "Foudre overcap", unit = "percent" },
	{ key = "ChaosResistOverCap", group = "resist", label = "Chaos overcap", unit = "percent" },

	{ key = "LifeRegenRecovery", group = "recovery", label = "Regen vie", unit = "number", maximize = true },
	{ key = "EnergyShieldRegenRecovery", group = "recovery", label = "Regen ES", unit = "number", maximize = true },
	{ key = "ManaRegenRecovery", group = "recovery", label = "Regen mana", unit = "number", maximize = true },
	{ key = "NetLifeRegen", group = "recovery", label = "Regen vie nette", unit = "number", maximize = true },
	{ key = "MovementSpeedMod", group = "recovery", label = "Vitesse de déplacement", unit = "multiplier", maximize = true, hint = "1.4 = +40%" },
}

local GROUPS = {
	{ id = "offence", label = "Offensif" },
	{ id = "defence", label = "Défensif" },
	{ id = "resist", label = "Résistances" },
	{ id = "recovery", label = "Récupération" },
}

local OBJECTIVES = {
	{ id = "MAX_DPS", stat = "CombinedDPS", label = "Maximiser le DPS combiné" },
	{ id = "MAX_FULL_DPS", stat = "FullDPS", label = "Maximiser le Full DPS" },
	{ id = "MAX_TOTAL_DPS", stat = "TotalDPS", label = "Maximiser le DPS du skill" },
	{ id = "MAX_LIFE", stat = "Life", label = "Maximiser la vie" },
	{ id = "MAX_ES", stat = "EnergyShield", label = "Maximiser l'Energy Shield" },
	{ id = "MAX_EHP", stat = "TotalEHP", label = "Maximiser l'EHP" },
	{ id = "MAX_CRIT", stat = "CritChance", label = "Maximiser la chance de crit" },
	{ id = "MAX_CRIT_MULTI", stat = "CritMultiplier", label = "Maximiser le multiplicateur de crit" },
	{ id = "MAX_ARMOUR", stat = "Armour", label = "Maximiser l'armure" },
	{ id = "MAX_EVASION", stat = "Evasion", label = "Maximiser l'evasion" },
	{ id = "MAX_SUPPRESSION", stat = "SpellSuppressionChance", label = "Maximiser la suppression" },
	{ id = "MAX_BLOCK", stat = "BlockChance", label = "Maximiser le block" },
	{ id = "MAX_SPELL_BLOCK", stat = "SpellBlockChance", label = "Maximiser le spell block" },
	{ id = "MAX_WARD", stat = "Ward", label = "Maximiser le ward" },
	{ id = "MAX_MANA", stat = "Mana", label = "Maximiser le mana" },
}

local PRESETS = {
	{
		id = "res75",
		label = "Res 75 / 75 / 75",
		min = { FireResist = 75, ColdResist = 75, LightningResist = 75 },
	},
	{
		id = "res75chaos",
		label = "Res 75 + chaos 0",
		min = { FireResist = 75, ColdResist = 75, LightningResist = 75, ChaosResist = 0 },
	},
	{
		id = "crit100",
		label = "Crit 100%",
		min = { CritChance = 100 },
	},
	{
		id = "critmulti5",
		label = "Crit multi ×5",
		min = { CritMultiplier = 5 },
	},
	{
		id = "life4k",
		label = "Vie 4 000",
		min = { Life = 4000 },
	},
	{
		id = "es2k",
		label = "ES 2 000",
		min = { EnergyShield = 2000 },
	},
	{
		id = "ehp15k",
		label = "EHP 15 000",
		min = { TotalEHP = 15000 },
	},
	{
		id = "suppress100",
		label = "Suppression 100%",
		min = { SpellSuppressionChance = 100 },
	},
	{
		id = "block75",
		label = "Block 75%",
		min = { BlockChance = 75 },
	},
	{
		id = "hit95",
		label = "Hit 95%",
		min = { HitChance = 95 },
	},
}

local byKey = {}
for _, row in ipairs(STATS) do
	byKey[row.key] = row
end

local function keys()
	local out = {}
	for i, row in ipairs(STATS) do
		out[i] = row.key
	end
	return out
end

local function has(key)
	return byKey[key] ~= nil
end

return {
	STATS = STATS,
	GROUPS = GROUPS,
	OBJECTIVES = OBJECTIVES,
	PRESETS = PRESETS,
	byKey = byKey,
	keys = keys,
	has = has,
}
