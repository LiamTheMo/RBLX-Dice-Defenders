-- All tunable numbers (docs/MVP.md). Server-only; clients never see this module.
local Balance = {}

Balance.BoardCells = 15 -- 5 x 3, row-major
Balance.StartMP = 100 -- exactly four summons: 10 + 20 + 30 + 40
Balance.StartLives = 3
Balance.TrialWave = 10 -- clearing this wave counts as a Trial clear (the run itself is endless)
Balance.MaxAlive = 90
Balance.FirstWaveDelay = 4 -- seconds after Start
Balance.WaveGap = 4 -- seconds after a wave is cleared
-- Attacks one die may fire per Match.Step. A Step covers at most MaxStep s, so this must be at least
-- MaxStep x the fastest die (highest rate x 7 pips x (1 + AuraCap)); Needle 1.75 x 7 x 1.3 x 0.25 s = 4.0. Spec-checked.
Balance.MaxAttacksPerTick = 8
Balance.MaxStep = 0.25 -- largest dt Match.Step simulates at once
Balance.TickHz = 10

-- Attacks per second = Dice rate x PipRate[pip] (each pip is its own shooter); per-hit damage has no pip term (*tune*).
Balance.PipRate = table.freeze({ 1, 2, 3, 4, 5, 6, 7 })
-- In-match Power Up per die type (Rules/Match.TryPowerUp): tier 1..Max, Costs[tier] MP buys tier + 1, each tier adds
-- DamagePerTier of the base hit damage to every die of that type. Match-only, never persisted (*tune*).
Balance.PowerUp = table.freeze({ Max = 5, Costs = table.freeze({ 100, 200, 400, 700 }), DamagePerTier = 0.10 })
-- Most attack-speed bonus (fraction) one die receives from adjacent aura dice combined (Dice `aura`) (*tune*).
Balance.AuraCap = 0.30

Balance.SummonCost = table.freeze({ base = 10, step = 10 }) -- MP: base + step * summons so far
-- Run reward (*tune*): per wave cleared.
Balance.Reward = table.freeze({ goldPerWave = 5, xpPerWave = 10, fragmentsPerWave = 1 })
-- Gems per wave cleared: Random Dice co-op's card schedule (1 a wave, 2 on a mini-boss wave, 3 on a boss
-- wave; 2 and 6 after wave 45). The first band whose maxWave >= w; a wave with both pays `boss`.
Balance.WaveGems = table.freeze({
	table.freeze({ maxWave = 45, wave = 1, brute = 2, boss = 3 }),
	table.freeze({ maxWave = math.huge, wave = 2, brute = 6, boss = 6 }),
})

-- Enemy HP (*tune*): base * growth * ease * hpMul. growth multiplies (1 + rate) for each wave after the
-- first, at the rate of the band the wave is in; the steep band is the Commons wall (docs/MVP.md "Waves");
-- ease = min(1, easeFrom + (1 - easeFrom) * (w - 1) / easeWaves).
Balance.EnemyHp = table.freeze({
	base = 275,
	growth = table.freeze({
		table.freeze({ toWave = 10, rate = 0.07 }),
		table.freeze({ toWave = 15, rate = 0.26 }),
		table.freeze({ toWave = math.huge, rate = 0.07 }),
	}),
	easeFrom = 0.4,
	easeWaves = 3,
})
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
	CoopReady = table.freeze({ rate = 2, burst = 3 }),
	TutorialAction = table.freeze({ rate = 2, burst = 3 }),
	Summon = table.freeze({ rate = 10, burst = 8 }),
	Merge = table.freeze({ rate = 5, burst = 8 }),
	EquipDeck = table.freeze({ rate = 1, burst = 3 }),
	ClaimQuest = table.freeze({ rate = 2, burst = 4 }),
	RedeemCode = table.freeze({ rate = 1, burst = 3 }),
	SaveSettings = table.freeze({ rate = 0.5, burst = 3 }), -- *tune*
	BagAction = table.freeze({ rate = 3, burst = 6 }), -- *tune*
	Roll = table.freeze({ rate = 1, burst = 2 }), -- *tune*
	Buy = table.freeze({ rate = 1, burst = 3 }), -- *tune*
	UpgradeDie = table.freeze({ rate = 2, burst = 4 }), -- *tune*
	PowerUp = table.freeze({ rate = 2, burst = 4 }), -- *tune*
	AdminAction = table.freeze({ rate = 1, burst = 2 }),
})
Balance.KickThreshold = 20
Balance.LogInterval = 5 -- seconds between violation log lines per player

-- Redeem guessing limiter (Rules/Redeem): failures beyond `freeFailures` lock the
-- player for lockSeconds, doubling per further failure up to maxLockSeconds; the
-- kickFailures-th failure of a session kicks.
Balance.Redeem = table.freeze({ freeFailures = 5, lockSeconds = 15, maxLockSeconds = 600, kickFailures = 50 })

return table.freeze(Balance)
