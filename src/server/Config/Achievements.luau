-- Achievements (docs/_archive/MVP.md): claimable once when the derived Stat reaches Goal.
--   Stat  = RunsPlayed | TrialCleared | Kills (Stats.Kills) | Level (account level)
--           | DiceOwned (different dice owned); Rules/Claims derives the progress
--   Badge = Quest Log sprite key (QuestSprites) for display
-- Ids key saved flags: never reuse. Rewards are Rules/Rewards bundles *tune*.
local function achievement(fields)
	table.freeze(fields.Reward)
	return table.freeze(fields)
end

local List = table.freeze({
	achievement({
		Id = "A1",
		Name = "Trailblazer",
		Desc = "Finish your first run.",
		Goal = 1,
		Stat = "RunsPlayed",
		Badge = "BadgeTower",
		Reward = { Gems = 20 },
	}),
	achievement({
		Id = "A2",
		Name = "Verdant Champion",
		Desc = "Clear the Verdant Trial.",
		Goal = 1,
		Stat = "TrialCleared",
		Badge = "BadgeKing",
		Reward = { Gems = 100, Cosmetics = table.freeze({ SproutCap = true }) },
	}),
	achievement({
		Id = "A3",
		Name = "Thorn in Their Side",
		Desc = "Defeat 1,000 enemies.",
		Goal = 1000,
		Stat = "Kills",
		Badge = "BadgeBattle",
		Reward = { Gems = 50 },
	}),
	achievement({
		Id = "A4",
		Name = "Rising Star",
		Desc = "Reach account level 5.",
		Goal = 5,
		Stat = "Level",
		Badge = "BadgeXp",
		Reward = { Gems = 50, Cosmetics = table.freeze({ ThornDice = true }) },
	}),
	achievement({
		Id = "A5",
		Name = "Dice Collector",
		Desc = "Own 8 different dice.",
		Goal = 8,
		Stat = "DiceOwned",
		Badge = "BadgeRoyal",
		Reward = { Gems = 50, Cosmetics = table.freeze({ FireflyTrail = true }) },
	}),
})

local ById = {}
for _, a in List do
	ById[a.Id] = a
end

return table.freeze({ List = List, ById = table.freeze(ById) })
