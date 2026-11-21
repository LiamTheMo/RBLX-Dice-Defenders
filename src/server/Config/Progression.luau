-- Level curves. Need(level) is what it takes to go from level to level + 1; *tune*
-- marks placeholder numbers.
--   Account: total account Xp
--   Mastery: a die's mastery points; Milestones are the levels that pay a reward,
--            Rewards[level] the Rules/Rewards bundle each pays once per die
--   DieLevel: a die's level cap and the spare copies each level-up spends
local Validate = require(script.Parent.Parent.Rules.Validate)

export type Curve = { Max: number, Need: (number) -> number, Milestones: { number }?, Rewards: { [number]: any }? }

local Progression = {}

Progression.Account = table.freeze({
	Max = 50, -- *tune*
	Need = function(level: number): number
		return 100 * level -- *tune*
	end,
})

Progression.Mastery = table.freeze({
	Max = 20, -- *tune*
	Need = function(level: number): number
		return 5 * level -- *tune*
	end,
	Milestones = table.freeze({ 5, 10, 15, 20 }), -- *tune*
	Rewards = table.freeze({ -- *tune*; Lv15 Gems stand in for the not-yet-made dice skin
		[5] = table.freeze({ Gems = 20 }),
		[10] = table.freeze({ Gems = 30, Items = table.freeze({ XpTome = 1 }) }),
		[15] = table.freeze({ Gems = 50 }),
		[20] = table.freeze({ Gems = 100 }),
	}),
})

-- Die levels follow Random Dice's class-up rules (copies AND gold per step, crit damage per step):
--   Copies[l]  spare copies of the SAME die spent to go from level l to l + 1 (Max - 1 entries, every rarity).
--   Gold[c]    gold for the step at "class" c, Crit[c] the crit damage percent that step adds to the whole account.
--              c = level + Offset[rarity]: a rarer die starts further up the same Gold / Crit curves, as in Random Dice
--              (Rare starts at class 3, Unique 5, Legendary 7) - it pays the class's gold and earns the class's crit.
-- Crit and Gold are the wiki's curves (Crit exactly; Gold scaled down to this game's income) *tune*
Progression.DieLevel = table.freeze({
	Max = 12,
	Copies = table.freeze({ 1, 2, 4, 8, 15, 25, 40, 60, 90, 130, 200 }), -- *tune*
	Gold = table.freeze({
		5,
		10,
		25,
		50,
		100,
		200,
		400,
		800,
		1500,
		3000,
		6000,
		10000,
		15000,
		25000,
		40000,
		60000,
		80000,
	}),
	Crit = table.freeze({ 1, 2, 2, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5 }),
	Offset = table.freeze({ Common = 0, Rare = 2, Epic = 4, Legendary = 6, Mythic = 6, Secret = 6 }),
})

-- Gold the step from `level` to level + 1 costs a die of `rarity` (nil past the table / at Max).
function Progression.GoldCost(rarity: string, level: number): number?
	local d = Progression.DieLevel
	return d.Gold[level + (d.Offset[rarity] or 0)]
end

-- Crit damage percent that same step adds to the account.
function Progression.CritGain(rarity: string, level: number): number
	local d = Progression.DieLevel
	return d.Crit[level + (d.Offset[rarity] or 0)] or 0
end

-- Crit damage percent a die of `rarity` at `level` contributes: the sum of its steps so far.
function Progression.CritOf(rarity: string, level: number): number
	local total = 0
	for l = 1, level - 1 do
		total += Progression.CritGain(rarity, l)
	end
	return total
end

-- (level, into, need) for a running total on `curve`: level starts at 1; at Max
-- into and need are 0. A non-int or negative total reads as 0.
function Progression.Level(total: any, curve: Curve): (number, number, number)
	local into = if Validate.IsInt(total, 0, math.huge) then total else 0
	for level = 1, curve.Max - 1 do
		local need = curve.Need(level)
		if into < need then
			return level, into, need
		end
		into -= need
	end
	return curve.Max, 0, 0
end

return table.freeze(Progression)
