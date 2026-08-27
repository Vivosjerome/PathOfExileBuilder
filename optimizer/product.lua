-- Product facade: BuildDefinition → complete-build search.
-- PoB is the only scoring oracle. Unimplemented dimensions are indexed,
-- reported, and skipped rather than faked.

local definition = require("build.definition")
local universe = require("catalog.universe")
local dimensions = require("optimizer.dimensions")
local engine = require("optimizer.engine")
local oracle = require("pob-engine.oracle")

local function log(fmt, ...)
	io.stderr:write(string.format(fmt, ...) .. "\n")
	io.stderr:flush()
end

local function generate(raw)
	local def, err = definition.normalize(raw)
	if not def then
		return nil, err
	end
	local plan = dimensions.plan(def.search)
	local created, createErr = oracle.create({
		class = def.class,
		ascendancy = def.ascendancy,
		level = def.level,
		skill = def.skill.name,
		skillLevel = def.skill.level,
		skillQuality = def.skill.quality,
		config = def.config,
	})
	if not created then
		return nil, createErr
	end
	local catalog = universe.snapshot()

	log("PoE Build Optimizer")
	log("Class: %s", def.class)
	log("Ascendancy: %s", def.ascendancy)
	log("Level: %d", def.level)
	log("Skill: %s %d/%d", def.skill.name, def.skill.level, def.skill.quality)
	log("Objective: %s", def.objective)
	log("PoB universe: %d uniques, %d bases, %d explicit mods, %d gems, %d supports, %d flask bases, %d jewel bases, %d tree nodes",
		catalog.uniques, catalog.bases, catalog.explicitMods, catalog.activeGems,
		catalog.supportGems, catalog.flaskBases, catalog.jewelBases, catalog.treeNodes)
	log("Active dimensions:")
	for _, dim in ipairs(plan.active) do
		log("  - %s", dim.label)
	end
	if #plan.deferred > 0 then
		log("Deferred (indexed, not searched yet):")
		for _, dim in ipairs(plan.deferred) do
			log("  - %s", dim.label)
		end
	end
	log("")

	if def.search.dryRun then
		return {
			ok = true,
			dryRun = true,
			definition = def,
			universe = catalog,
			dimensions = plan,
		}
	end

	if not def.search.gear then
		return nil, "gear search is required in this version"
	end

	local engineResult, engineErr = engine.run(definition.toEngineParams(def))
	if not engineResult then
		return nil, engineErr
	end

	return {
		ok = true,
		dryRun = false,
		definition = def,
		universe = catalog,
		dimensions = {
			active = (function()
				local names = {}
				for _, d in ipairs(plan.active) do names[#names + 1] = d.id end
				return names
			end)(),
			deferred = (function()
				local names = {}
				for _, d in ipairs(plan.deferred) do names[#names + 1] = d.id end
				return names
			end)(),
		},
		best = engineResult.best,
		verified = engineResult.verified,
		top = engineResult.topValid or engineResult.top,
		topNear = engineResult.topNear,
		metrics = engineResult.metrics,
		discoveries = engineResult.discoveries,
		rareReport = engineResult.rareReport,
		jewels = engineResult.jewels,
		complete = engineResult.complete,
	}
end

return {
	generate = generate,
}
