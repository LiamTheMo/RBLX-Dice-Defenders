-- Play first-time milestones (docs/MVP.md): claimable once when BestWave >= Wave.
-- Only waves the Trial has (Balance.Waves) are Reachable; the others are never
-- claimable but keep real rewards for display. Ids key saved flags: never reuse.
-- Rewards are Rules/Rewards bundles *tune*.
local Balance = require(script.Parent.Balance)

local function milestone(id: string, wave: number, reward)
	return table.freeze({ Id = id, Wave = wave, Reachable = wave <= Balance.Waves, Reward = table.freeze(reward) })
end

local List = table.freeze({
	milestone("P10", 10, { Gems = 50, Items = table.freeze({ XpTome = 1 }) }),
	milestone("P20", 20, { Gold = 100, Dice = table.freeze({ R01 = 1 }) }),
	milestone("P30", 30, { Gold = 300, Items = table.freeze({ XpTome = 2 }) }),
	milestone("P40", 40, { Gems = 60 }),
	milestone("P50", 50, { Gold = 500, Dice = table.freeze({ E01 = 1 }) }),
	milestone("P100", 100, { Gold = 800, Gems = 200, Dice = table.freeze({ L01 = 1 }) }),
})

local ById = {}
for _, m in List do
	ById[m.Id] = m
end

return table.freeze({ List = List, ById = table.freeze(ById) })
