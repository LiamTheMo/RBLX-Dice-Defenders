-- All tunable numbers (docs/MVP.md). Server-only; clients never see this module.
local Balance = {}

Balance.BoardCells = 15 -- 5 x 3, row-major
Balance.StartMP = 100 -- exactly four summons: 10 + 20 + 30 + 40
Balance.StartLives = 3
Balance.TrialWave = 10 -- clearing this wave counts as a Trial clear (the run itself is endless)
Balance.MaxAlive = 90
Balance.FirstWaveDelay = 4 -- seconds after Start
Balance.WaveGap = 4 -- seconds after a wave is cleared
Balance.MaxAttacksPerTick = 2
Balance.MaxStep = 0.25 -- largest dt Match.Step simulates at once
Balance.TickHz = 10

Balance.SummonCost = table.freeze({ base = 10, step = 10 }) -- MP: base + step * summons so far
-- Run reward (*tune*): per wave cleared.
Balance.Reward = table.freeze({ goldPerWave = 5, xpPerWave = 10, fragmentsPerWave = 1 })

-- Enemy HP (*tune*): base * (1 + growth)^(w - 1) * hpMul; a boss has bossPerWave * (w - bossOffset).
Balance.EnemyHp = table.freeze({ base = 80, growth = 0.08, bossPerWave = 1200, bossOffset = 3 })
-- Kill MP (*tune*): the first band whose maxWave >= w; Brute pays x5, Boss x10.
Balance.KillMp = table.freeze({
	table.freeze({ maxWave = 5, mp = 10 }),
	table.freeze({ maxWave = 10, mp = 20 }),
	table.freeze({ maxWave = 15, mp = 30 }),
	table.freeze({ maxWave = 20, mp = 40 }),
	table.freeze({ maxWave = math.huge, mp = 50 }),
})
Balance.BruteMpMul = 5
Balance.BossMpMul = 10

-- Net: token buckets per player and remote, and the hard-violation kick.
Balance.Remotes = table.freeze({
	Start = table.freeze({ rate = 1, burst = 2 }),
	Summon = table.freeze({ rate = 5, burst = 8 }),
	Merge = table.freeze({ rate = 5, burst = 8 }),
	EquipDeck = table.freeze({ rate = 1, burst = 3 }),
	ClaimQuest = table.freeze({ rate = 2, burst = 4 }),
	RedeemCode = table.freeze({ rate = 1, burst = 3 }),
	SaveSettings = table.freeze({ rate = 0.5, burst = 3 }), -- *tune*
	BagAction = table.freeze({ rate = 3, burst = 6 }), -- *tune*
	Roll = table.freeze({ rate = 1, burst = 2 }), -- *tune*
	Buy = table.freeze({ rate = 1, burst = 3 }), -- *tune*
	UpgradeDie = table.freeze({ rate = 2, burst = 4 }), -- *tune*
})
Balance.KickThreshold = 20
Balance.LogInterval = 5 -- seconds between violation log lines per player

-- Redeem guessing limiter (Rules/Redeem): failures beyond `freeFailures` lock the
-- player for lockSeconds, doubling per further failure up to maxLockSeconds; the
-- kickFailures-th failure of a session kicks.
Balance.Redeem = table.freeze({ freeFailures = 5, lockSeconds = 15, maxLockSeconds = 600, kickFailures = 50 })

return table.freeze(Balance)
