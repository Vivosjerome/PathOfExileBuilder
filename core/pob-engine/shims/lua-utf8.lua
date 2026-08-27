-- Minimal lua-utf8 shim for headless PoB (luautf8-compatible subset).
-- Calc path mostly uses ASCII; character iteration is UTF-8 aware.

local utf8 = {}

local function charLen(byte)
	if byte < 0x80 then
		return 1
	elseif byte < 0xE0 then
		return 2
	elseif byte < 0xF0 then
		return 3
	end
	return 4
end

local function offsetAt(s, index)
	if index < 1 then
		return 1
	end
	local i = 1
	local n = #s
	local seen = 1
	while i <= n do
		if seen == index then
			return i
		end
		i = i + charLen(s:byte(i))
		seen = seen + 1
	end
	return n + 1
end

local function nextByte(s, byteIndex, dir)
	byteIndex = byteIndex or 1
	dir = dir or 1
	if dir >= 0 then
		if byteIndex < 1 then
			byteIndex = 1
		end
		if byteIndex > #s then
			return nil
		end
		local steps = dir
		local i = byteIndex
		while steps > 0 and i <= #s do
			i = i + charLen(s:byte(i) or 0)
			steps = steps - 1
		end
		if i > #s + 1 then
			return nil
		end
		return i
	end
	local i = 1
	local prev = 1
	while i < byteIndex do
		prev = i
		i = i + charLen(s:byte(i) or 0)
	end
	if dir == -1 then
		if byteIndex <= 1 then
			return nil
		end
		return prev
	end
	return prev
end

function utf8.len(s)
	local i = 1
	local n = 0
	while i <= #s do
		i = i + charLen(s:byte(i))
		n = n + 1
	end
	return n
end

function utf8.sub(s, i, j)
	i = i or 1
	j = j or -1
	local len = utf8.len(s)
	if i < 0 then
		i = len + i + 1
	end
	if j < 0 then
		j = len + j + 1
	end
	if i < 1 then
		i = 1
	end
	if j > len then
		j = len
	end
	if j < i then
		return ""
	end
	local a = offsetAt(s, i)
	local b = offsetAt(s, j + 1) - 1
	return s:sub(a, b)
end

function utf8.reverse(s)
	local parts = {}
	local i = 1
	while i <= #s do
		local len = charLen(s:byte(i))
		parts[#parts + 1] = s:sub(i, i + len - 1)
		i = i + len
	end
	for a = 1, math.floor(#parts / 2) do
		local b = #parts - a + 1
		parts[a], parts[b] = parts[b], parts[a]
	end
	return table.concat(parts)
end

function utf8.gsub(s, pattern, repl, n)
	return string.gsub(s, pattern, repl, n)
end

function utf8.find(s, pattern, init, plain)
	return string.find(s, pattern, init, plain)
end

function utf8.match(s, pattern, init)
	return string.match(s, pattern, init)
end

function utf8.gmatch(s, pattern)
	return string.gmatch(s, pattern)
end

function utf8.next(s, i, j)
	return nextByte(s, i, j)
end

return utf8
