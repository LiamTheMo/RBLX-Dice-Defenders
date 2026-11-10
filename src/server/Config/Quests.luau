-- Quest catalog (docs/MVP.md). Ids are never reused: they key saved claim flags.
--   Stat   = profile stat that drives progress (RunsPlayed, BestWave, TrialCleared)
--   Daily  = true: progress is today's kill count (Daily.Kills) and resets each UTC day
local function quest(fields)
	return table.freeze(fields)
end

local List = table.freeze({
	quest({ Id = "S1", Name = "First Steps", Desc = "Finish a Trial run", Goal = 1, Gold = 50, Stat = "RunsPlayed" }),
	quest({ Id = "S2", Name = "Wave Five", Desc = "Clear wave 5", Goal = 5, Gold = 100, Stat = "BestWave" }),
	quest({
		Id = "S3",
		Name = "Verdant Victor",
		Desc = "Clear the Verdant Trial",
		Goal = 1,
		Gold = 250,
		Stat = "TrialCleared",
	}),
	quest({ Id = "D1", Name = "Pest Control", Desc = "Defeat 150 enemies today", Goal = 150, Gold = 100, Daily = true }),
})

local ById = {}
for _, q in List do
	ById[q.Id] = q
end

return table.freeze({ List = List, ById = table.freeze(ById) })
