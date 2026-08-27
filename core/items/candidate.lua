-- ItemCandidate: one interface for unique / rare / generated rare.
-- Beam search never branches on kind; it only needs id, name, slot fit, and a PoB Item.

local Candidate = {}

function Candidate.unique(fields)
	return {
		kind = "unique",
		id = fields.id or ("unique:" .. fields.name),
		name = fields.name,
		slots = fields.slots,
		itemId = fields.itemId,
		item = fields.item,
		raw = fields.raw,
		itemType = fields.itemType,
		reqLevel = fields.reqLevel or 0,
	}
end

function Candidate.rare(fields)
	return {
		kind = "rare",
		id = fields.id or ("rare:" .. (fields.name or "unnamed")),
		name = fields.name,
		slots = fields.slots,
		itemId = fields.itemId,
		item = fields.item,
		raw = fields.raw,
		itemType = fields.itemType,
		reqLevel = fields.reqLevel or 0,
		affixes = fields.affixes,
		base = fields.base,
		prefixes = fields.prefixes,
		suffixes = fields.suffixes,
		implicits = fields.implicits,
		influences = fields.influences,
		rolls = fields.rolls or 1,
	}
end

function Candidate.generatedRare(fields)
	local cand = Candidate.rare(fields)
	cand.kind = "generated_rare"
	cand.id = fields.id or ("genrare:" .. (fields.name or "unnamed"))
	return cand
end

function Candidate.support(fields)
	return {
		kind = "support",
		id = fields.id or ("support:" .. (fields.name or "unnamed")),
		name = fields.name,
		slots = fields.slots,
		gemData = fields.gemData,
		gemId = fields.gemId,
		effectId = fields.effectId,
		plusVersionOf = fields.plusVersionOf,
		level = fields.level or 20,
		quality = fields.quality or 20,
		reqLevel = fields.reqLevel or 0,
	}
end

function Candidate.aura(fields)
	local cand = Candidate.support(fields)
	cand.kind = "aura"
	cand.id = fields.id or ("aura:" .. (fields.name or "unnamed"))
	return cand
end

function Candidate.notable(fields)
	return {
		kind = "notable",
		id = fields.id or ("node:" .. tostring(fields.nodeId)),
		name = fields.name,
		slots = fields.slots,
		nodeId = fields.nodeId,
		ascendancy = fields.ascendancy,
		isKeystone = fields.isKeystone and true or false,
		isSocket = fields.isSocket and true or false,
		reqLevel = 0,
	}
end

function Candidate.empty()
	return {
		kind = "empty",
		id = "empty",
		name = "(empty)",
		slots = nil,
		itemId = 0,
		item = nil,
		raw = nil,
		itemType = nil,
		reqLevel = 0,
	}
end

function Candidate.fitsSlot(candidate, slotName)
	if not candidate or candidate.kind == "empty" then
		return true
	end
	if not candidate.slots then
		return false
	end
	for _, name in ipairs(candidate.slots) do
		if name == slotName then
			return true
		end
	end
	return false
end

return Candidate
