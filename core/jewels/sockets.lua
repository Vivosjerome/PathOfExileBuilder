-- Allocate the cheapest classic tree jewel sockets from the current start.
-- Cluster / expansion sockets are left for a later dimension.

local function isClassicSocket(node)
	return node
		and node.type == "Socket"
		and not node.expansionJewel
		and not node.charmSocket
end

local function slotNameFor(nodeId)
	return "Jewel " .. tostring(nodeId)
end

local function pointsUsed(spec)
	local used = spec:CountAllocNodes()
	return used
end

local function isLargeExpansion(node)
	return node
		and node.type == "Socket"
		and node.expansionJewel
		and node.expansionJewel.size == 2
		and not node.expansionJewel.parent
		and not node.charmSocket
end

local function cheapestUnallocated(spec, pred)
	local best
	for _, node in pairs(spec.nodes) do
		if pred(node) and not node.alloc and node.path and node.pathDist
			and node.pathDist > 0 and node.pathDist < 1000 then
			if not best
				or node.pathDist < best.pathDist
				or (node.pathDist == best.pathDist and node.id < best.id) then
				best = node
			end
		end
	end
	return best
end

local function allocateWith(pred, params)
	params = params or {}
	local spec = build.spec
	local maxSockets = tonumber(params.maxSockets) or 3
	local maxPoints = tonumber(params.maxPoints) or 24
	local beforePoints = pointsUsed(spec)
	local sockets = {}
	local slotNames = {}

	spec:BuildAllDependsAndPaths()
	for _ = 1, maxSockets do
		spec:BuildAllDependsAndPaths()
		local node = cheapestUnallocated(spec, pred)
		if not node then
			break
		end
		local cost = node.pathDist
		if #sockets > 0 and (pointsUsed(spec) - beforePoints) + cost > maxPoints then
			break
		end
		if #sockets == 0 and cost > maxPoints then
			break
		end
		spec:AllocNode(node)
		local info = {
			id = node.id,
			name = node.name or ("Socket " .. node.id),
			slotName = slotNameFor(node.id),
			pathCost = cost,
			expansion = node.expansionJewel and true or false,
		}
		sockets[#sockets + 1] = info
		slotNames[#slotNames + 1] = info.slotName
	end

	if build.itemsTab and build.itemsTab.UpdateSockets then
		build.itemsTab:UpdateSockets()
	end
	if build.itemsTab and build.itemsTab.PopulateSlots then
		build.itemsTab:PopulateSlots()
	end

	return {
		sockets = sockets,
		slotNames = slotNames,
		pointsBefore = beforePoints,
		pointsAfter = pointsUsed(spec),
		pointsSpent = pointsUsed(spec) - beforePoints,
	}
end

local function allocateNearest(params)
	return allocateWith(isClassicSocket, params)
end

local function allocateNearestLarge(params)
	params = params or {}
	params.maxSockets = params.maxSockets or 2
	params.maxPoints = params.maxPoints or 28
	return allocateWith(isLargeExpansion, params)
end

return {
	isClassicSocket = isClassicSocket,
	isLargeExpansion = isLargeExpansion,
	slotNameFor = slotNameFor,
	allocateNearest = allocateNearest,
	allocateNearestLarge = allocateNearestLarge,
}
