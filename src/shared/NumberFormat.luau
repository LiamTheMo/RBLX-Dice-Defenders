-- Compact numbers for the UI: up to 2 decimals with a letter suffix, trailing zeros dropped (34900 -> "34.9k", 3150 ->
-- "3.15k", 27920 -> "27.92k"). Below 1000 the number is shown as is (up to 2 decimals).
local NumberFormat = {}

local SUFFIXES = { "", "k", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trim(value: number): string
	local text = string.format("%.2f", value)
	text = text:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
	return text
end

function NumberFormat.Compact(n: number): string
	if n ~= n or n == math.huge or n == -math.huge then
		return "-"
	end
	local sign = if n < 0 then "-" else ""
	n = math.abs(n)
	local tier = 0
	while n >= 1000 and tier < #SUFFIXES - 1 do
		n /= 1000
		tier += 1
	end
	if tonumber(string.format("%.2f", n)) :: number >= 1000 and tier < #SUFFIXES - 1 then -- 999.999k rounds up to 1M
		n /= 1000
		tier += 1
	end
	return sign .. trim(n) .. SUFFIXES[tier + 1]
end

return NumberFormat
