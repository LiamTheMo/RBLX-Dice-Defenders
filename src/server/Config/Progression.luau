-- Level curves. Need(level) is what it takes to go from level to level + 1; *tune*
-- marks placeholder numbers.
--   Account: total account Xp
--   Mastery: a die's mastery points; Milestones are the levels that pay a reward,
--            Rewards[level] the Rules/Rewards bundle each pays once per die
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
