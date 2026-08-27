-- Search dimensions of a complete PoE build.

local DIMENSIONS = {
	{
		id = "gear",
		label = "Items (uniques + rares)",
		implemented = true,
		default = true,
	},
	{
		id = "jewels",
		label = "Jewels (classic + unique tree sockets)",
		implemented = true,
		default = false,
	},
	{
		id = "gems",
		label = "Skill gems and supports",
		implemented = true,
		default = false,
	},
	{
		id = "flasks",
		label = "Flasks",
		implemented = true,
		default = false,
	},
	{
		id = "tree",
		label = "Passive tree",
		implemented = true,
		default = false,
	},
	{
		id = "ascendancy",
		label = "Ascendancy notables (within the chosen ascendancy)",
		implemented = true,
		default = false,
	},
	{
		id = "cluster",
		label = "Cluster jewels",
		implemented = true,
		default = false,
	},
	{
		id = "timeless",
		label = "Timeless jewels",
		implemented = true,
		default = false,
	},
}

local function plan(search)
	search = search or {}
	local active, deferred = {}, {}
	for _, dim in ipairs(DIMENSIONS) do
		local wanted = search[dim.id]
		if wanted == nil then
			wanted = dim.default
		end
		if wanted then
			if dim.implemented then
				active[#active + 1] = dim
			else
				deferred[#deferred + 1] = dim
			end
		end
	end
	return {
		all = DIMENSIONS,
		active = active,
		deferred = deferred,
	}
end

return {
	DIMENSIONS = DIMENSIONS,
	plan = plan,
}
