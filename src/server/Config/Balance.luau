-- All tunable numbers (docs/MVP.md). Server-only; clients never see this module.
local Balance = {}

Balance.BoardCells = 15 -- 5 x 3, row-major
Balance.StartMP = 100 -- exactly four summons: 10 + 20 + 30 + 40
Balance.StartLives = 20
Balance.Waves = 10
Balance.BossWave = 10
Balance.MaxAlive = 90
Balance.FirstWaveDelay = 4 -- seconds after Start
Balance.WaveGap = 4 -- seconds after a wave is cleared
Balance.MaxAttacksPerTick = 2
Balance.MaxStep = 0.25 -- largest dt Match.Step simulates at once
Balance.TickHz = 10

Balance.SummonCost = table.freeze({ base = 10, step = 10 }) -- MP: base + step * summons so far
-- Run reward (*tune*): per wave cleared, plus a bonus for a win.
Balance.Reward = table.freeze({
	goldPerWave = 5,
	goldWin = 30,
	xpPerWave = 10,
	xpWin = 40,
	fragmentsPerWave = 1,
	fragmentsWin = 5,
})

-- Net: token buckets per player and remote, and the hard-violation kick.
Balance.Remotes = table.freeze({
	Start = table.freeze({ rate = 1, burst = 2 }),
	Summon = table.freeze({ rate = 5, burst = 8 }),
	Merge = table.freeze({ rate = 5, burst = 8 }),
	EquipDeck = table.freeze({ rate = 1, burst = 3 }),
	ClaimQuest = table.freeze({ rate = 2, burst = 4 }),
	RedeemCode = table.freeze({ rate = 1, burst = 3 }),
	SaveSettings = table.freeze({ rate = 0.5, burst = 3 }), -- *tune*
})
Balance.KickThreshold = 20
Balance.LogInterval = 5 -- seconds between violation log lines per player

-- Redeem guessing limiter (Rules/Redeem): failures beyond `freeFailures` lock the
-- player for lockSeconds, doubling per further failure up to maxLockSeconds; the
-- kickFailures-th failure of a session kicks.
Balance.Redeem = table.freeze({ freeFailures = 5, lockSeconds = 15, maxLockSeconds = 600, kickFailures = 50 })

return table.freeze(Balance)
