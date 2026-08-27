local hashLib = require("pob-engine.hash")

local function newCache()
	return {
		store = {},
		hits = 0,
		misses = 0,
	}
end

local function get(cache, key)
	local value = cache.store[key]
	if value ~= nil then
		cache.hits = cache.hits + 1
		return value, true
	end
	cache.misses = cache.misses + 1
	return nil, false
end

local function put(cache, key, value)
	cache.store[key] = value
	return value
end

local function size(cache)
	local n = 0
	for _ in pairs(cache.store) do
		n = n + 1
	end
	return n
end

local function hitRate(cache)
	local total = cache.hits + cache.misses
	if total == 0 then
		return 0
	end
	return cache.hits / total
end

local function loadoutHash(identity, loadout)
	return hashLib.digest({
		class = identity.class,
		ascendancy = identity.ascendancy,
		level = identity.level,
		skill = identity.skill,
		skillLevel = identity.skillLevel,
		skillQuality = identity.skillQuality,
		items = loadout or {},
	})
end

return {
	new = newCache,
	get = get,
	put = put,
	size = size,
	hitRate = hitRate,
	loadoutHash = loadoutHash,
}
