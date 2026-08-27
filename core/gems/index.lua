-- Legal support and aura gems from PoB data. Eligibility is skill-type based.

local Candidate = require("items.candidate")
local slotsMod = require("items.slots")
local affixScore = require("optimizer.affix_score")

local function gemLevel(gem)
	local n = gem.naturalMaxLevel or 20
	if n >= 20 then
		return 20
	end
	return n
end

local function effectStatsText(granted)
	if not granted then
		return ""
	end
	local parts = {}
	if type(granted.statDescriptionScope) == "string" then
		parts[#parts + 1] = granted.statDescriptionScope
	end
	if granted.baseFlags then
		for k in pairs(granted.baseFlags) do
			parts[#parts + 1] = tostring(k)
		end
	end
	for _, line in ipairs(granted) do
		if type(line) == "string" then
			parts[#parts + 1] = line
		end
	end
	if granted.constantStats then
		for _, row in ipairs(granted.constantStats) do
			if type(row[1]) == "string" then
				parts[#parts + 1] = row[1]
			end
		end
	end
	return table.concat(parts, "\n")
end

local function mainActiveSkill()
	local env = build.calcsTab and build.calcsTab.mainEnv
	return env and env.player and env.player.mainSkill
end

local function indexSupports(slotNames)
	slotNames = slotNames or slotsMod.SUPPORT_SLOTS
	local active = mainActiveSkill()
	local all, byId = {}, {}
	if not active or not calcLib or not calcLib.canGrantedEffectSupportActiveSkill then
		return { all = all, byId = byId, stats = { installed = 0 } }
	end
	for gemId, gem in pairs(data.gems) do
		local granted = gem.grantedEffect
		if granted and granted.support
			and not granted.hideFromGemList
			and not granted.unsupported
			and not (granted.legacy and granted.plusVersionOf)
			and calcLib.canGrantedEffectSupportActiveSkill(granted, active) then
			local scored = affixScore.scoreText(effectStatsText(granted) .. " " .. (gem.name or "") .. " " .. (gem.tagString or ""))
			local cand = Candidate.support({
				id = "support:" .. gemId,
				name = gem.name,
				slots = slotNames,
				gemData = gem,
				gemId = gemId,
				effectId = gem.grantedEffectId,
				plusVersionOf = granted.plusVersionOf,
				level = gemLevel(gem),
				quality = 20,
			})
			cand.affixScore = scored.total
			byId[cand.id] = cand
			all[#all + 1] = cand
		end
	end
	table.sort(all, function(a, b)
		if (a.affixScore or 0) == (b.affixScore or 0) then
			return a.name < b.name
		end
		return (a.affixScore or 0) > (b.affixScore or 0)
	end)
	if #all > 64 then
		local kept, newById = {}, {}
		for i = 1, 64 do
			kept[i] = all[i]
			newById[all[i].id] = all[i]
		end
		all, byId = kept, newById
	end
	return {
		all = all,
		byId = byId,
		stats = { installed = #all },
	}
end

local function hasSkillType(granted, typeName)
	if not granted or not granted.skillTypes or not SkillType then
		return false
	end
	local want = SkillType[typeName]
	if not want then
		return false
	end
	return granted.skillTypes[want] and true or false
end

local function indexAuras(slotNames)
	slotNames = slotNames or slotsMod.AURA_SLOTS
	local all, byId = {}, {}
	for gemId, gem in pairs(data.gems) do
		local granted = gem.grantedEffect
		if granted and not granted.support and not granted.hideFromGemList and not granted.unsupported
			and gem.tags and gem.tags.grants_active_skill then
			local isAura = hasSkillType(granted, "Aura") or hasSkillType(granted, "Hex")
				or hasSkillType(granted, "AppliesCurse") or (gem.tags and gem.tags.aura)
			if isAura then
				local scored = affixScore.scoreText(effectStatsText(granted) .. " " .. (gem.name or ""))
				local cand = Candidate.aura({
					id = "aura:" .. gemId,
					name = gem.name,
					slots = slotNames,
					gemData = gem,
					gemId = gemId,
					effectId = gem.grantedEffectId,
					level = gemLevel(gem),
					quality = 20,
				})
				cand.affixScore = scored.total
				byId[cand.id] = cand
				all[#all + 1] = cand
			end
		end
	end
	table.sort(all, function(a, b)
		if (a.affixScore or 0) == (b.affixScore or 0) then
			return a.name < b.name
		end
		return (a.affixScore or 0) > (b.affixScore or 0)
	end)
	if #all > 32 then
		local kept, newById = {}, {}
		for i = 1, 32 do
			kept[i] = all[i]
			newById[all[i].id] = all[i]
		end
		all, byId = kept, newById
	end
	return {
		all = all,
		byId = byId,
		stats = { installed = #all },
	}
end

return {
	indexSupports = indexSupports,
	indexAuras = indexAuras,
}
