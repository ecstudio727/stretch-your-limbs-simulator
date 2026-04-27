--!strict
-- Util.lua
-- Small shared helpers.

local Util = {}

function Util.deepCopy<T>(t: T): T
	if type(t) ~= "table" then return t end
	local copy = {}
	for k, v in pairs(t :: any) do
		copy[k] = Util.deepCopy(v)
	end
	return copy :: any
end

function Util.formatNumber(n: number): string
	-- 12345 -> "12,345"
	local s = tostring(math.floor(n))
	local formatted = s
	while true do
		local replaced
		formatted, replaced = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then break end
	end
	return formatted
end

function Util.horizontalDistance(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

return Util
