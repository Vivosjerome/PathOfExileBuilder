-- Install classic unique + rare jewels into the existing item catalog
-- as extra beam slots named "Jewel <nodeId>".

local sockets = require("jewels.sockets")
local uniques = require("jewels.uniques")
local rares = require("jewels.rares")
local resist = require("optimizer.resist")

local function ensureSlots(catalog, slotNames)
	catalog.slotOrder = catalog.slotOrder or {}
	catalog.bySlot = catalog.bySlot or {}
	local seen = {}
	for _, name in ipairs(catalog.slotOrder) do
		seen[name] = true
	end
	for _, name in ipairs(slotNames or {}) do
		catalog.bySlot[name] = catalog.bySlot[name] or {}
		if not seen[name] then
			catalog.slotOrder[#catalog.slotOrder + 1] = name
			seen[name] = true
		end
	end
end

local function addCandidates(catalog, generated)
	local added = 0
	for _, cand in ipairs(generated.all or {}) do
		if not catalog.byId[cand.id] then
			catalog.byId[cand.id] = cand
			catalog.all[#catalog.all + 1] = cand
			added = added + 1
		end
		for _, slotName in ipairs(cand.slots or {}) do
			local list = catalog.bySlot[slotName]
			if list then
				local exists = false
				for _, prev in ipairs(list) do
					if prev.id == cand.id then
						exists = true
						break
					end
				end
				if not exists then
					list[#list + 1] = cand
				end
			end
		end
	end
	return added
end

local function prepare(catalog, params)
	params = params or {}
	local allocated = sockets.allocateNearest({
		maxSockets = params.maxSockets or 3,
		maxPoints = params.maxPoints or 24,
	})
	if #allocated.slotNames == 0 then
		return allocated
	end
	ensureSlots(catalog, allocated.slotNames)

	local uniqueSet = uniques.index(allocated.slotNames, params.characterLevel)
	allocated.uniqueStats = uniqueSet.stats
	allocated.uniquesInstalled = addCandidates(catalog, uniqueSet)

	if params.includeRares ~= false then
		local rareSet = rares.generate({
			slots = allocated.slotNames,
			itemLevel = params.itemLevel or 100,
			maxRares = params.maxRares or 40,
		})
		allocated.rareStats = rareSet.stats
		allocated.raresInstalled = addCandidates(catalog, rareSet)
	else
		allocated.rareStats = { crafted = 0, failed = 0, installed = 0 }
		allocated.raresInstalled = 0
	end

	catalog.stats = catalog.stats or {}
	catalog.stats.jewelUniques = uniqueSet.stats.installed
	catalog.stats.jewelRares = (allocated.rareStats and allocated.rareStats.installed) or 0
	resist.buildSlotMax(catalog)
	return allocated
end

return {
	ensureSlots = ensureSlots,
	addCandidates = addCandidates,
	prepare = prepare,
}
