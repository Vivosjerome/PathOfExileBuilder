local sha1 = require("sha1")

local encodeValue

local function sortedKeys(map)
	local keys = {}
	for key in pairs(map) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

encodeValue = function(value)
	local valueType = type(value)
	if valueType == "table" then
		local parts = { "{" }
		for i, key in ipairs(sortedKeys(value)) do
			if i > 1 then
				parts[#parts + 1] = ","
			end
			parts[#parts + 1] = tostring(key)
			parts[#parts + 1] = "="
			parts[#parts + 1] = encodeValue(value[key])
		end
		parts[#parts + 1] = "}"
		return table.concat(parts)
	elseif valueType == "boolean" then
		return value and "true" or "false"
	elseif value == nil then
		return "nil"
	end
	return tostring(value)
end

local function digest(payload)
	return sha1.sha1(encodeValue(payload))
end

return {
	canonical = encodeValue,
	digest = digest,
}
