-- Snapshot of everything Path of Building currently knows.
-- The optimizer must not keep a second approximate database.

local function count(tbl)
	local n = 0
	if not tbl then
		return 0
	end
	for _ in pairs(tbl) do
		n = n + 1
	end
	return n
end

local function classes()
	local out = {}
	if not (build and build.spec and build.spec.tree and build.spec.tree.classes) then
		return out
	end
	for _, class in pairs(build.spec.tree.classes) do
		local asc = {}
		for _, a in pairs(class.classes or {}) do
			if a.name and a.name ~= "None" then
				asc[#asc + 1] = a.name
			end
		end
		table.sort(asc)
		out[#out + 1] = { name = class.name, ascendancies = asc }
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

local function skills()
	local out, seen = {}, {}
	if not (data and data.gems) then
		return out
	end
	for gemId, gem in pairs(data.gems) do
		local granted = gem.grantedEffect
		if granted and not granted.support and not granted.hideFromGemList and not granted.unsupported
			and gem.tags and gem.tags.grants_active_skill and gem.name and not seen[gem.name] then
			seen[gem.name] = true
			out[#out + 1] = {
				name = gem.name,
				id = gemId,
			}
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

local function snapshot()
	local gems, supports, flaskBases, jewelBases = 0, 0, 0, 0
	if data and data.gems then
		for _, gem in pairs(data.gems) do
			if gem.grantedEffectId or gem.name then
				if gem.tags and gem.tags.support then
					supports = supports + 1
				else
					gems = gems + 1
				end
			end
		end
	end
	if data and data.itemBases then
		for _, base in pairs(data.itemBases) do
			if type(base) == "table" then
				if base.type == "Flask" then
					flaskBases = flaskBases + 1
				elseif base.type == "Jewel" then
					jewelBases = jewelBases + 1
				end
			end
		end
	end
	local treeNodes = 0
	if build and build.spec and build.spec.tree and build.spec.tree.nodes then
		treeNodes = count(build.spec.tree.nodes)
	end
	local uniques = 0
	if main and main.uniqueDB and main.uniqueDB.list then
		uniques = count(main.uniqueDB.list)
	end
	return {
		source = "PathOfBuilding",
		uniques = uniques,
		bases = data and count(data.itemBases) or 0,
		explicitMods = data and data.itemMods and count(data.itemMods.Explicit) or 0,
		activeGems = gems,
		supportGems = supports,
		flaskBases = flaskBases,
		jewelBases = jewelBases,
		treeNodes = treeNodes,
		classes = classes(),
		skills = skills(),
	}
end

return {
	snapshot = snapshot,
	classes = classes,
	skills = skills,
}
