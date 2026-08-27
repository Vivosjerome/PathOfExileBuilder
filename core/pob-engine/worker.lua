-- Path of Building headless JSON worker.
-- Must be launched with cwd = vendor/PathOfBuilding/src
-- Save argv before PoB Main.lua consumes arg[1] as an import link.

local cliArgs = { [0] = arg and arg[0] }
for i, value in ipairs(arg or {}) do
	cliArgs[i] = value
end

dofile("HeadlessWrapper.lua")

if __mainObject__.promptMsg then
	io.stderr:write("PoB startup failed: " .. tostring(__mainObject__.promptMsg) .. "\n")
	os.exit(1)
end

local workerDir = (cliArgs[0] or ""):gsub("\\", "/"):match("^(.*)/") or "."
package.path = workerDir .. "/../?.lua;" .. workerDir .. "/../?/init.lua;"
	.. workerDir .. "/../../?.lua;" .. workerDir .. "/../../?/init.lua;"
	.. (package.path or "")

local dkjson = require("dkjson")
local oracle = require("pob-engine.oracle")
local stats = require("pob-engine.stats")

local function encode(value)
	return dkjson.encode(value, { indent = false })
end

local function reply(ok, result, err, id)
	local payload = {
		ok = ok and true or false,
		id = id,
		result = result,
		error = err,
	}
	io.stdout:write(encode(payload) .. "\n")
	io.stdout:flush()
end

local handlers = {}

function handlers.ping(_, id)
	reply(true, { pong = true, pob = true }, nil, id)
end

function handlers.new_build(params, id)
	local result, err = oracle.create(params or {})
	if not result then
		reply(false, nil, err, id)
		return
	end
	reply(true, result, nil, id)
end

function handlers.get_stats(_, id)
	reply(true, oracle.getStats(), nil, id)
end

function handlers.inspect(_, id)
	reply(true, oracle.inspect(), nil, id)
end

function handlers.get_hash(_, id)
	reply(true, { hash = oracle.hash() }, nil, id)
end

function handlers.export_xml(_, id)
	reply(true, { xml = oracle.exportXml() }, nil, id)
end

function handlers.load_xml(params, id)
	local result, err = oracle.loadXml(params and params.xml, params and params.name)
	if not result then
		reply(false, nil, err, id)
		return
	end
	reply(true, result, nil, id)
end

function handlers.set_item(params, id)
	local result, err = oracle.equipRaw(params and params.slot, params and (params.raw or params.text))
	if not result then
		reply(false, nil, err, id)
		return
	end
	reply(true, result, nil, id)
end

function handlers.whatif_item(params, id)
	local result, err = oracle.whatIfItem(params and params.slot, params and (params.raw or params.text))
	if not result then
		reply(false, nil, err, id)
		return
	end
	reply(true, result, nil, id)
end

function handlers.set_tree(params, id)
	local result, err = oracle.setNodes(params and params.nodes)
	if not result then
		reply(false, nil, err, id)
		return
	end
	reply(true, result, nil, id)
end

function handlers.universe(_, id)
	local created, err = oracle.create({
		class = "Witch",
		ascendancy = "Elementalist",
		level = 90,
		skill = "Winter Orb",
	})
	if not created then
		reply(false, nil, err, id)
		return
	end
	local universe = require("catalog.universe")
	reply(true, universe.snapshot(), nil, id)
end

function handlers.schema(_, id)
	local universe = require("catalog.universe")
	local catalog = require("build.stats_catalog")
	local dimensions = require("optimizer.dimensions")
	local definition = require("build.definition")
	local classes = universe.classes()
	if #classes == 0 then
		local _, err = oracle.create({
			class = "Witch",
			ascendancy = "Elementalist",
			level = 90,
			skill = "Winter Orb",
		})
		if err then
			reply(false, nil, err, id)
			return
		end
		classes = universe.classes()
	end
	reply(true, {
		classes = classes,
		skills = universe.skills(),
		stats = catalog.STATS,
		groups = catalog.GROUPS,
		objectives = catalog.OBJECTIVES,
		presets = catalog.PRESETS,
		dimensions = dimensions.DIMENSIONS,
		defaults = definition.defaults(),
	}, nil, id)
end

function handlers.generate(params, id)
	local product = require("optimizer.product")
	local result, err = product.generate(params or {})
	if not result then
		reply(false, nil, err, id)
		return
	end
	reply(true, result, nil, id)
end

function handlers.validate_roundtrip(_, id)
	local first = oracle.inspect()
	local xml = oracle.exportXml()
	local second, err = oracle.loadXml(xml, "roundtrip")
	if not second then
		reply(false, nil, err, id)
		return
	end
	local comparison = stats.diff(first.stats, second.stats, 1e-6)
	reply(true, {
		hashBefore = first.hash,
		hashAfter = second.hash,
		comparison = comparison,
	}, nil, id)
end

local function handleRequest(request)
	local method = request.method
	local id = request.id
	local handler = handlers[method]
	if not handler then
		reply(false, nil, "unknown method: " .. tostring(method), id)
		return
	end
	local ok, err = pcall(handler, request.params or request, id)
	if not ok then
		reply(false, nil, tostring(err), id)
	end
end

local function runRpc()
	io.stdout:setvbuf("line")
	for line in io.stdin:lines() do
		if line == "shutdown" or line == '{"method":"shutdown"}' then
			reply(true, { shutdown = true }, nil, nil)
			return
		end
		local request, pos, decodeErr = dkjson.decode(line)
		if not request then
			reply(false, nil, "invalid json: " .. tostring(decodeErr), nil)
		else
			handleRequest(request)
		end
	end
end

local function runEvaluate(params)
	local result, err = oracle.create(params)
	if not result then
		reply(false, nil, err, "evaluate")
		os.exit(1)
	end
	reply(true, result, nil, "evaluate")
end

local function runBench(n)
	n = tonumber(n) or 100
	local created, err = oracle.create({
		class = "Witch",
		ascendancy = "Elementalist",
		level = 90,
		skill = "Winter Orb",
	})
	if not created then
		reply(false, nil, err, "bench")
		os.exit(1)
	end
	local started = os.clock()
	for i = 1, n do
		oracle.recalc()
	end
	local elapsed = os.clock() - started
	reply(true, {
		calculations = n,
		seconds = elapsed,
		perSecond = elapsed > 0 and (n / elapsed) or 0,
		baseline = created.stats,
		hash = created.hash,
	}, nil, "bench")
end

local mode = cliArgs[1] or "rpc"
if mode == "rpc" then
	runRpc()
elseif mode == "evaluate" then
	local skillName = table.concat({ select(5, unpack(cliArgs)) }, " ")
	if skillName == "" then
		skillName = "Winter Orb"
	end
	runEvaluate({
		class = cliArgs[2] or "Witch",
		ascendancy = cliArgs[3] or "Elementalist",
		level = tonumber(cliArgs[4]) or 90,
		skill = skillName,
	})
elseif mode == "bench" then
	runBench(cliArgs[2])
elseif mode == "validate" then
	local created, err = oracle.create({
		class = "Witch",
		ascendancy = "Elementalist",
		level = 90,
		skill = "Winter Orb",
	})
	if not created then
		reply(false, nil, err, "validate")
		os.exit(1)
	end
	handlers.validate_roundtrip({}, "validate")
	if not stats.diff(created.stats, oracle.getStats(), 1e-6).ok then
		os.exit(1)
	end
elseif mode == "optimize" then
	local engine = require("optimizer.engine")
	local slots = nil
	local includeRares = true
	local constrainRes = true
	if cliArgs[6] == "helmet" then
		slots = { "Helmet" }
	elseif cliArgs[6] == "free" then
		constrainRes = false
		includeRares = false
	elseif cliArgs[6] == "uniques" then
		includeRares = false
	elseif cliArgs[6] == "rares" or cliArgs[6] == nil then
		includeRares = true
	end
	local result, err = engine.run({
		class = cliArgs[2] or "Witch",
		ascendancy = cliArgs[3] or "Elementalist",
		level = tonumber(cliArgs[4]) or 90,
		skill = "Winter Orb",
		beamSize = tonumber(cliArgs[5]) or 100,
		slots = slots,
		constrainRes = constrainRes,
		includeRares = includeRares,
	})
	if not result then
		reply(false, nil, err, "optimize")
		os.exit(1)
	end
	local reportPath = workerDir .. "/../../.cache/optimize-result.json"
	local reportFile = io.open(reportPath, "w")
	if reportFile then
		reportFile:write(encode(result))
		reportFile:close()
		io.stderr:write("Wrote " .. reportPath .. "\n")
	end
	reply(true, result, nil, "optimize")
elseif mode == "generate" then
	local product = require("optimizer.product")
	local def = {}
	local defPath = cliArgs[2]
	if defPath and defPath ~= "-" and defPath ~= "dry" then
		local f = io.open(defPath, "r")
		if not f then
			reply(false, nil, "cannot read definition: " .. tostring(defPath), "generate")
			os.exit(1)
		end
		local body = f:read("*a")
		f:close()
		def = dkjson.decode(body) or {}
	end
	for i = 2, #cliArgs do
		if cliArgs[i] == "dry" then
			def.search = def.search or {}
			def.search.dryRun = true
		end
	end
	local result, err = product.generate(def)
	if not result then
		reply(false, nil, err, "generate")
		os.exit(1)
	end
	local reportPath = workerDir .. "/../../.cache/generate-result.json"
	local reportFile = io.open(reportPath, "w")
	if reportFile then
		reportFile:write(encode(result))
		reportFile:close()
		io.stderr:write("Wrote " .. reportPath .. "\n")
	end
	reply(true, result, nil, "generate")
elseif mode == "regress" then
	local expected = require("tests.regression.expected")
	local root = workerDir .. "/../.."
	local failed = {}
	for _, row in ipairs(expected.BENCHMARKS) do
		local path = root .. "/" .. row.file
		local f = io.open(path, "r")
		if not f then
			failed[#failed + 1] = row.id .. " missing file " .. row.file
		else
			local body = f:read("*a")
			f:close()
			local snap = dkjson.decode(body)
			local got = snap and (snap.combinedDPS or (snap.comparison and snap.comparison.constrainedDps))
			if not got then
				failed[#failed + 1] = row.id .. " has no combinedDPS"
			elseif math.abs(got - row.dps) > (row.epsilon or 1) then
				failed[#failed + 1] = string.format("%s DPS %.4f != frozen %.4f", row.id, got, row.dps)
			else
				io.stderr:write(string.format("OK %s  %.0f CombinedDPS  (%s)\n", row.id, got, row.label))
			end
		end
	end
	if #failed > 0 then
		reply(false, { failures = failed }, table.concat(failed, "; "), "regress")
		os.exit(1)
	end
	reply(true, { ok = true, benchmarks = expected.BENCHMARKS }, nil, "regress")
else
	io.stderr:write("usage: worker.lua rpc|evaluate|bench|validate|optimize|generate|regress\n")
	os.exit(2)
end
