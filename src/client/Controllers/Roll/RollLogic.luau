--!strict
-- Roll menu logic: pure, no Instances. Display only; the server decides nothing here.

local RollLogic = {}

-- Display order, top to bottom, and the roll chain's step order: each step rolls only if every earlier one failed.
RollLogic.ORDER = { "Secret", "Mythic", "Legendary", "Epic", "Rare", "Common" }

-- Trailing zeros trimmed, at most `places` decimals (default 4, so configured step chances show exactly): 0.01 -> "0.01%".
function RollLogic.pctText(n: number, places: number?): string
	local s = string.format(`%.{places or 4}f`, n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s .. "%"
end

-- odds = step chances in percent. Rows show each step chance as set; Common (the remainder, no step of its own)
-- shows the chance of reaching it: the product of every earlier step failing.
function RollLogic.oddsRows(odds: { [string]: number }): { { Rarity: string, Pct: number, Text: string } }
	local rows, reach = {}, 100
	for i, rarity in RollLogic.ORDER do
		local step = odds[rarity]
		if rarity == "Common" and step == nil then
			rows[i] = { Rarity = rarity, Pct = reach, Text = RollLogic.pctText(reach, 2) }
		else
			step = step or 0
			rows[i] = { Rarity = rarity, Pct = step, Text = RollLogic.pctText(step) }
			reach *= 1 - step / 100
		end
	end
	return rows
end

function RollLogic.pityFraction(count: number, max: number): number
	if max <= 0 then
		return 0
	end
	return math.clamp(count / max, 0, 1)
end

function RollLogic.canAfford(gems: number?, price: number): boolean
	return gems ~= nil and gems >= price
end

return RollLogic
