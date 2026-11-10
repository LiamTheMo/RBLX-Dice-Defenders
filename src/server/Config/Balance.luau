-- All tunable numbers (docs/MVP.md). Server-only; clients never see this module.
local Balance = {}

Balance.BoardCells = 15 -- 5 x 3, row-major
Balance.StartEnergy = 20
Balance.StartLives = 20
Balance.Waves = 10
Balance.BossWave = 10
Balance.MaxAlive = 90
Balance.FirstWaveDelay = 4 -- seconds after Start
Balance.WaveGap = 4 -- seconds after a wave is cleared
Balance.BaseRange = 20 -- studs
Balance.MaxAttacksPerTick = 2
Balance.MaxStep = 0.25 -- largest dt Match.Step simulates at once
Balance.TickHz = 10

Balance.SummonCost = table.freeze({ base = 10, growth = 1.085, min = 10, max = 250 })
Balance.Reward = table.freeze({ gold = 50, goldPerWave = 3 })

-- Net: token buckets per player and remote, and the hard-violation kick.
Balance.Remotes = table.freeze({
	Start = table.freeze({ rate = 1, burst = 2 }),
	Summon = table.freeze({ rate = 5, burst = 8 }),
	Merge = table.freeze({ rate = 5, burst = 8 }),
})
Balance.KickThreshold = 20
Balance.LogInterval = 5 -- seconds between violation log lines per player

return table.freeze(Balance)
