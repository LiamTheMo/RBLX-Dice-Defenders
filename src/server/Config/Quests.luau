-- Quest catalog (docs/_archive/MVP.md). Ids are never reused: they key saved claim flags.
--   Stat   = profile stat that drives progress (RunsPlayed, BestWave, TrialCleared)
--   Daily  = true: progress is today's kill count (Daily.Kills) and resets each UTC day
--   Weekly = "Kills" | "Runs": progress is this week's Weekly[counter]; resets each Monday 00:00 UTC
--   Reward = Rules/Rewards bundle paid once (once per day or week for Daily and Weekly) *tune*
local function quest(fields)
	table.freeze(fields.Reward)
	return table.freeze(fields)
end

local List = table.freeze({
	quest({
		Id = "S1",
		Name = "First Steps",
		Desc = "Finish a Trial run",
		Goal = 1,
		Stat = "RunsPlayed",
		Reward = { Gold = 50, Gems = 10 },
	}),
	quest({
		Id = "S2",
		Name = "Wave Five",
		Desc = "Clear wave 5",
		Goal = 5,
		Stat = "BestWave",
		Reward = { Gold = 100, Gems = 20 },
	}),
	quest({
		Id = "S3",
		Name = "Verdant Victor",
		Desc = "Clear the Verdant Trial",
		Goal = 1,
		Stat = "TrialCleared",
		Reward = { Gold = 250, Gems = 50 },
	}),
	quest({
		Id = "D1",
		Name = "Pest Control",
		Desc = "Defeat 150 enemies today",
		Goal = 150,
		Daily = true,
		Reward = { Gold = 100, Gems = 10 },
	}),
	quest({
		Id = "W1",
		Name = "Weed Out",
		Desc = "Defeat 1000 enemies this week",
		Goal = 1000,
		Weekly = "Kills",
		Reward = { Gold = 200, Gems = 30 },
	}),
	quest({
		Id = "W2",
		Name = "Regular",
		Desc = "Finish 10 runs this week",
		Goal = 10,
		Weekly = "Runs",
		Reward = { Gold = 300, Gems = 30 },
	}),
})

local ById = {}
for _, q in List do
	ById[q.Id] = q
end

return table.freeze({ List = List, ById = table.freeze(ById) })
