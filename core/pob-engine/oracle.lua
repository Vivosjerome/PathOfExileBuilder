local stats = require("pob-engine.stats")
local hashLib = require("pob-engine.hash")

local oracle = {}

local DEFAULT_CONFIG = {
	enemyIsBoss = "Pinnacle",
	usePowerCharges = true,
	useFrenzyCharges = true,
	useEnduranceCharges = true,
}

local function recalc()
	build.buildFlag = true
	runCallback("OnFrame")
end

local function fail(message)
	return nil, message
end

function oracle.recalc()
	recalc()
end

function oracle.resolveClass(className)
	local tree = build.spec.tree
	local classId = tree.classNameMap[className]
	if not classId then
		return fail("unknown class: " .. tostring(className))
	end
	return classId, tree.classes[classId]
end

function oracle.resolveAscendancy(className, ascendancyName)
	local classId, classOrErr = oracle.resolveClass(className)
	if not classId then
		return nil, classOrErr
	end
	local class = classOrErr
	if not ascendancyName or ascendancyName == "" or ascendancyName == "None" then
		return classId, 0
	end
	for ascendClassId, ascendClass in pairs(class.classes) do
		if ascendClass.name == ascendancyName or ascendClass.id == ascendancyName then
			return classId, ascendClassId
		end
	end
	return fail("unknown ascendancy '" .. tostring(ascendancyName) .. "' for " .. className)
end

function oracle.applyConfig(config)
	config = config or {}
	for key, value in pairs(DEFAULT_CONFIG) do
		if config[key] == nil then
			build.configTab.input[key] = value
		end
	end
	for key, value in pairs(config) do
		build.configTab.input[key] = value
	end
	build.configTab:BuildModList()
end

local function gemInstance(spec)
	if type(spec) == "string" then
		spec = { name = spec }
	end
	return {
		nameSpec = spec.name or spec.nameSpec,
		gemId = spec.gemId,
		skillId = spec.skillId,
		level = spec.level or 20,
		quality = spec.quality or 20,
		enabled = spec.enabled ~= false,
		enableGlobal1 = spec.enableGlobal1 ~= false,
		enableGlobal2 = spec.enableGlobal2 == true,
		count = spec.count or 1,
		skillPart = spec.skillPart,
		skillPartCalcs = spec.skillPartCalcs or spec.skillPart,
		skillStageCount = spec.skillStageCount,
		skillStageCountCalcs = spec.skillStageCountCalcs or spec.skillStageCount,
	}
end

function oracle.setMainSkill(skillName, options)
	options = options or {}
	if not skillName or skillName == "" then
		return fail("skill name required")
	end
	local group = {
		enabled = true,
		includeInFullDPS = true,
		label = skillName,
		slot = options.slot or "Body Armour",
		mainActiveSkill = 1,
		mainActiveSkillCalcs = 1,
		gemList = {},
	}
	group.gemList[1] = gemInstance({
		name = skillName,
		level = options.skillLevel or 20,
		quality = options.skillQuality or 20,
		skillPart = options.skillPart,
		skillStageCount = options.skillStageCount or 10,
	})
	for _, support in ipairs(options.supports or {}) do
		group.gemList[#group.gemList + 1] = gemInstance(support)
	end
	while #build.skillsTab.socketGroupList > 0 do
		table.remove(build.skillsTab.socketGroupList)
	end
	build.skillsTab:ProcessSocketGroup(group)
	if group.gemList[1].errMsg then
		return fail(group.gemList[1].errMsg)
	end
	local skillLevel = options.skillLevel or 20
	local skillQuality = options.skillQuality or 20
	group.gemList[1].level = skillLevel
	group.gemList[1].quality = skillQuality
	build.skillsTab:ProcessSocketGroup(group)
	table.insert(build.skillsTab.socketGroupList, group)
	build.mainSocketGroup = 1
	return group
end

function oracle.create(params)
	params = params or {}
	newBuild()
	local className = params.class or params.className
	local ascendancyName = params.ascendancy or params.ascendClassName
	if not className then
		return fail("class is required")
	end
	local classId, ascendClassId = oracle.resolveAscendancy(className, ascendancyName)
	if not classId then
		return nil, ascendClassId
	end
	build.characterLevelAutoMode = false
	build.characterLevel = tonumber(params.level) or 90
	if build.controls and build.controls.characterLevel then
		build.controls.characterLevel:SetText(tostring(build.characterLevel))
	end
	if build.controls and build.controls.levelScalingButton then
		build.controls.levelScalingButton.label = "Manual"
	end
	build.spec:SelectClass(classId)
	build.spec:SelectAscendClass(ascendClassId)
	if params.skill then
		local group, err = oracle.setMainSkill(params.skill, params)
		if not group then
			return nil, err
		end
	end
	oracle.applyConfig(params.config)
	recalc()
	return oracle.inspect()
end

function oracle.inspect()
	local spec = build.spec
	local output = build.calcsTab.mainOutput
	local gems = {}
	for gi, grp in ipairs(build.skillsTab.socketGroupList) do
		for _, gem in ipairs(grp.gemList or {}) do
			gems[#gems + 1] = {
				group = grp.label,
				name = gem.nameSpec,
				skillId = gem.skillId,
				level = gem.level,
				quality = gem.quality,
				enabled = gem.enabled,
				error = gem.errMsg,
				support = gem.gemData and gem.gemData.grantedEffect and gem.gemData.grantedEffect.support or nil,
			}
		end
	end
	local items = {}
	for _, slot in ipairs(build.itemsTab.orderedSlots) do
		local itemId = slot.selItemId
		if itemId and itemId ~= 0 then
			local item = build.itemsTab.items[itemId]
			if item then
				items[#items + 1] = {
					slot = slot.slotName,
					name = item.name,
					base = item.baseName or (item.base and item.base.name),
					rarity = item.rarity,
				}
			end
		end
	end
	local nodeIds = {}
	for nodeId in pairs(spec.allocNodes) do
		nodeIds[#nodeIds + 1] = nodeId
	end
	table.sort(nodeIds)
	local notables, ascendancyNodes = {}, {}
	for nodeId, node in pairs(spec.allocNodes) do
		if node.isNotable or node.isKeystone then
			local row = { id = nodeId, name = node.name, keystone = node.isKeystone and true or false }
			if node.ascendancyName then
				ascendancyNodes[#ascendancyNodes + 1] = row
			else
				notables[#notables + 1] = row
			end
		end
	end
	table.sort(notables, function(a, b) return (a.name or "") < (b.name or "") end)
	table.sort(ascendancyNodes, function(a, b) return (a.name or "") < (b.name or "") end)
	return {
		class = spec.curClassName,
		ascendancy = spec.curAscendClassName,
		level = build.characterLevel,
		treeVersion = spec.treeVersion,
		passiveCount = #nodeIds,
		pointsUsed = select(1, spec:CountAllocNodes()),
		nodes = nodeIds,
		notables = notables,
		ascendancyNodes = ascendancyNodes,
		mainSkill = (build.skillsTab.socketGroupList[build.mainSocketGroup] and build.skillsTab.socketGroupList[build.mainSocketGroup].label) or nil,
		gems = gems,
		items = items,
		stats = stats.snapshot(output),
		hash = oracle.hash(),
	}
end

function oracle.exportXml()
	return build:SaveDB("optimizer-memory")
end

function oracle.loadXml(xmlText, name)
	if not xmlText or xmlText == "" then
		return fail("xml is required")
	end
	loadBuildFromXML(xmlText, name or "Imported")
	return oracle.inspect()
end

function oracle.equipRaw(slotName, rawText)
	if not slotName or not rawText then
		return fail("slot and item text are required")
	end
	local item = new("Item"):Item(rawText)
	if not item.base then
		return fail("unrecognised item (no base matched)")
	end
	if item.BuildModList then
		item:BuildModList()
	end
	local slot = build.itemsTab.slots[slotName]
	if not slot then
		return fail("unknown slot: " .. slotName)
	end
	build.itemsTab:AddItem(item, true)
	if not build.itemsTab:IsItemValidForSlot(item, slotName) then
		return fail("item is not valid for slot " .. slotName)
	end
	slot:SetSelItemId(item.id)
	build.itemsTab:PopulateSlots()
	recalc()
	return {
		slot = slotName,
		name = item.name,
		id = item.id,
		stats = stats.snapshot(build.calcsTab.mainOutput),
	}
end

function oracle.whatIfItem(slotName, rawText)
	local item = new("Item"):Item(rawText)
	if not item.base then
		return fail("unrecognised item (no base matched)")
	end
	if item.BuildModList then
		item:BuildModList()
	end
	local calcFunc = build.calcsTab:GetMiscCalculator()
	if not calcFunc then
		return fail("calculator is not ready; create a build first")
	end
	local output = calcFunc({ repSlotName = slotName, repItem = item }, false)
	return {
		slot = slotName,
		name = item.name,
		stats = stats.snapshot(output),
	}
end

function oracle.setNodes(nodeIds)
	local spec = build.spec
	spec:ImportFromNodeList(nil, spec.curClassId, spec.curAscendClassId, spec.curSecondaryAscendClassId or 0, nodeIds or {}, {}, {})
	recalc()
	return oracle.inspect()
end

function oracle.hash()
	local spec = build.spec
	local nodeIds = {}
	for nodeId in pairs(spec.allocNodes) do
		nodeIds[#nodeIds + 1] = nodeId
	end
	table.sort(nodeIds)
	local items = {}
	for _, slot in ipairs(build.itemsTab.orderedSlots) do
		local itemId = slot.selItemId
		if itemId and itemId ~= 0 and build.itemsTab.items[itemId] then
			items[slot.slotName] = build.itemsTab.items[itemId].raw or ""
		end
	end
	local gems = {}
	for gi, group in ipairs(build.skillsTab.socketGroupList) do
		local list = {}
		for _, gem in ipairs(group.gemList) do
			list[#list + 1] = {
				name = gem.nameSpec,
				skillId = gem.skillId,
				level = gem.level,
				quality = gem.quality,
				enabled = gem.enabled,
			}
		end
		gems[gi] = {
			slot = group.slot,
			enabled = group.enabled,
			main = group.mainActiveSkill,
			gems = list,
		}
	end
	return hashLib.digest({
		class = spec.curClassName,
		ascendancy = spec.curAscendClassName,
		level = build.characterLevel,
		treeVersion = spec.treeVersion,
		nodes = nodeIds,
		items = items,
		gems = gems,
		mainSocketGroup = build.mainSocketGroup,
		enemyIsBoss = build.configTab.input.enemyIsBoss,
		usePowerCharges = build.configTab.input.usePowerCharges,
		useFrenzyCharges = build.configTab.input.useFrenzyCharges,
		useEnduranceCharges = build.configTab.input.useEnduranceCharges,
	})
end

function oracle.getStats()
	return stats.snapshot(build.calcsTab.mainOutput)
end

function oracle.refreshCalculator()
	recalc()
	return build.calcsTab:GetMiscCalculator()
end

local GEAR_SLOTS = {
	"Helmet", "Gloves", "Boots", "Body Armour",
	"Amulet", "Ring 1", "Ring 2", "Belt",
	"Weapon 1", "Weapon 2",
}

function oracle.clearGearSlots()
	for _, slotName in ipairs(GEAR_SLOTS) do
		local slot = build.itemsTab.slots[slotName]
		if slot then
			slot:SetSelItemId(0)
		end
	end
	for i = 1, 5 do
		local slot = build.itemsTab.slots["Flask " .. i]
		if slot then
			slot:SetSelItemId(0)
			slot.active = false
		end
	end
	for nodeId, slot in pairs(build.itemsTab.sockets or {}) do
		if slot and build.spec.allocNodes[nodeId] then
			slot:SetSelItemId(0)
		end
	end
end

function oracle.applyLoadout(slotToItemId)
	oracle.clearGearSlots()
	slotToItemId = slotToItemId or {}
	local applied = {}
	for _, slotName in ipairs(GEAR_SLOTS) do
		local itemId = slotToItemId[slotName]
		if itemId and itemId ~= 0 then
			local slot = build.itemsTab.slots[slotName]
			local item = build.itemsTab.items[itemId]
			if slot and item and build.itemsTab:IsItemValidForSlot(item, slotName) then
				slot:SetSelItemId(itemId)
			end
		end
		applied[slotName] = true
	end
	for slotName, itemId in pairs(slotToItemId) do
		if not applied[slotName] and itemId and itemId ~= 0 then
			local slot = build.itemsTab.slots[slotName]
			local item = build.itemsTab.items[itemId]
			if slot and item and build.itemsTab:IsItemValidForSlot(item, slotName) then
				slot:SetSelItemId(itemId)
			end
		end
	end
	if build.itemsTab.UpdateSockets then
		build.itemsTab:UpdateSockets()
	end
	build.itemsTab:PopulateSlots()
	for i = 1, 5 do
		local slot = build.itemsTab.slots["Flask " .. i]
		if slot then
			slot.active = true
			if build.itemsTab.activeItemSet and build.itemsTab.activeItemSet[slot.slotName] then
				build.itemsTab.activeItemSet[slot.slotName].active = true
			end
		end
	end
	if build.spec.BuildClusterJewelGraphs then
		build.spec:BuildClusterJewelGraphs()
	end
	return oracle.refreshCalculator()
end

function oracle.whatIfItemObject(slotName, item)
	if slotName and slotName:match("^Flask ") then
		local slot = build.itemsTab.slots[slotName]
		if slot then
			slot.active = true
		end
	end
	local calcFunc = build.calcsTab:GetMiscCalculator()
	if not calcFunc then
		return fail("calculator is not ready; create a build first")
	end
	local ok, output = pcall(calcFunc, { repSlotName = slotName, repItem = item }, false)
	if not ok then
		return nil, tostring(output)
	end
	return stats.snapshot(output)
end

oracle.treeBaseSockets = {}

function oracle.setTreeBaseSockets(ids)
	oracle.treeBaseSockets = ids or {}
end

function oracle.pointBudget()
	return (build.characterLevel - 1) + 23 + 1
end

function oracle.pointsUsed()
	return build.spec:CountAllocNodes()
end

function oracle.restoreTreeBase()
	local spec = build.spec
	spec:ResetNodes()
	spec:BuildAllDependsAndPaths()
	for _, id in ipairs(oracle.treeBaseSockets or {}) do
		local node = spec.nodes[id]
		spec:BuildAllDependsAndPaths()
		if node and not node.alloc and node.path then
			spec:AllocNode(node)
		end
	end
end

local function makeGemInst(cand)
	return {
		nameSpec = cand.name,
		gemId = cand.gemId,
		gemData = cand.gemData,
		skillId = cand.effectId,
		level = cand.level or 20,
		quality = cand.quality or 20,
		enabled = true,
		enableGlobal1 = true,
		enableGlobal2 = true,
		count = 1,
	}
end

function oracle.applyNodes(loadout, catalog)
	local hasPicks = false
	for slotName in pairs(loadout or {}) do
		if slotName:match("^Ascendancy ") or slotName:match("^Tree ") then
			hasPicks = true
			break
		end
	end
	if not hasPicks and #(oracle.treeBaseSockets or {}) == 0 then
		return
	end
	oracle.restoreTreeBase()
	local order = {}
	for slotName in pairs(loadout or {}) do
		if slotName:match("^Ascendancy ") or slotName:match("^Tree ") then
			order[#order + 1] = slotName
		end
	end
	table.sort(order)
	for _, slotName in ipairs(order) do
		local cand = catalog and catalog.byId and catalog.byId[loadout[slotName]]
		if cand and cand.nodeId then
			local node = build.spec.nodes[cand.nodeId]
			build.spec:BuildAllDependsAndPaths()
			if node and not node.alloc and node.path then
				build.spec:AllocNode(node)
			end
		end
	end
end

function oracle.applyGems(loadout, catalog)
	local group = build.skillsTab.socketGroupList[build.mainSocketGroup]
	if not group then
		return
	end
	local active = group.gemList[1]
	group.gemList = { active }
	for i = 1, 5 do
		local cand = catalog and catalog.byId and catalog.byId[loadout["Support " .. i]]
		if cand and cand.kind == "support" then
			group.gemList[#group.gemList + 1] = makeGemInst(cand)
		end
	end
	build.skillsTab:ProcessSocketGroup(group)

	local kept = {}
	for _, g in ipairs(build.skillsTab.socketGroupList) do
		if not (g.label and tostring(g.label):match("^__opt_aura_")) then
			kept[#kept + 1] = g
		end
	end
	while #build.skillsTab.socketGroupList > 0 do
		table.remove(build.skillsTab.socketGroupList)
	end
	for _, g in ipairs(kept) do
		table.insert(build.skillsTab.socketGroupList, g)
	end
	for i = 1, 2 do
		local cand = catalog and catalog.byId and catalog.byId[loadout["Aura " .. i]]
		if cand and cand.kind == "aura" then
			local ag = {
				label = "__opt_aura_" .. i,
				enabled = true,
				includeInFullDPS = false,
				slot = nil,
				gemList = { makeGemInst(cand) },
			}
			build.skillsTab:ProcessSocketGroup(ag)
			table.insert(build.skillsTab.socketGroupList, ag)
		end
	end
end

function oracle.applyState(loadout, catalog)
	loadout = loadout or {}
	catalog = catalog or { byId = {} }
	oracle.applyNodes(loadout, catalog)
	local ids = {}
	for slotName, candId in pairs(loadout) do
		local cand = catalog.byId[candId]
		if cand and cand.itemId and cand.itemId ~= 0 then
			ids[slotName] = cand.itemId
		end
	end
	oracle.applyLoadout(ids)
	oracle.applyGems(loadout, catalog)
	return oracle.refreshCalculator()
end

function oracle.whatIfCurrent()
	local calcFunc = build.calcsTab:GetMiscCalculator()
	if not calcFunc then
		return fail("calculator is not ready")
	end
	local ok, output = pcall(calcFunc, nil, false)
	if not ok then
		return nil, tostring(output)
	end
	return stats.snapshot(output)
end

function oracle.whatIfSupport(index, cand)
	local group = build.skillsTab.socketGroupList[build.mainSocketGroup]
	if not group then
		return fail("no main skill group")
	end
	local saved = {}
	for i, gem in ipairs(group.gemList) do
		saved[i] = gem
	end
	local idx = (tonumber(index) or 1) + 1
	if not cand then
		if idx <= #group.gemList then
			table.remove(group.gemList, idx)
		end
	else
		local pos = idx
		if pos > #group.gemList + 1 then
			pos = #group.gemList + 1
		end
		if pos < 2 then
			pos = 2
		end
		group.gemList[pos] = makeGemInst(cand)
	end
	build.skillsTab:ProcessSocketGroup(group)
	local snap, err = oracle.whatIfCurrent()
	group.gemList = {}
	for i, gem in ipairs(saved) do
		group.gemList[i] = gem
	end
	build.skillsTab:ProcessSocketGroup(group)
	return snap, err
end

function oracle.whatIfAura(index, cand)
	local label = "__opt_aura_" .. tostring(index)
	local saved
	local savedPos
	for i, g in ipairs(build.skillsTab.socketGroupList) do
		if g.label == label then
			saved = g
			savedPos = i
			table.remove(build.skillsTab.socketGroupList, i)
			break
		end
	end
	if cand then
		local ag = {
			label = label,
			enabled = true,
			includeInFullDPS = false,
			slot = nil,
			gemList = { makeGemInst(cand) },
		}
		build.skillsTab:ProcessSocketGroup(ag)
		table.insert(build.skillsTab.socketGroupList, ag)
	end
	local snap, err = oracle.whatIfCurrent()
	for i, g in ipairs(build.skillsTab.socketGroupList) do
		if g.label == label then
			table.remove(build.skillsTab.socketGroupList, i)
			break
		end
	end
	if saved then
		table.insert(build.skillsTab.socketGroupList, savedPos or (#build.skillsTab.socketGroupList + 1), saved)
	end
	return snap, err
end

function oracle.whatIfNotable(nodeId)
	local spec = build.spec
	local node = spec.nodes[nodeId]
	if not node then
		return fail("unknown node " .. tostring(nodeId))
	end
	spec:BuildAllDependsAndPaths()
	if node.alloc then
		return oracle.whatIfCurrent()
	end
	if not node.path then
		return fail("unreachable")
	end
	local add = {}
	for _, pathNode in ipairs(node.path) do
		if not pathNode.alloc then
			add[pathNode] = true
		end
	end
	local calcFunc = build.calcsTab:GetMiscCalculator()
	local ok, output = pcall(calcFunc, { addNodes = add }, false)
	if not ok then
		return nil, tostring(output)
	end
	return stats.snapshot(output)
end

return oracle
