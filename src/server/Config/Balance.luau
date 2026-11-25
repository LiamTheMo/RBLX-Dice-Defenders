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
-- Gems per wave cleared: Random Dice co-op's card schedule x10 (a gem is worth a tenth of a card). By wave number:
-- up to 35 a plain wave pays 1 card, a mini-boss wave (w % 5 == 3) 2, a boss wave (w % 5 == 0) 3; from 36 there are no plain
-- waves: even = mini-boss, odd = boss (2 / 6 cards), doubled from 112, tripled from 500, x4 from 1001, x5 from 1501.
-- The first band whose maxWave >= w; `brute` = mini-boss wave. Formulas.WaveGems picks the column.
Balance.GemsPerCard = 10
Balance.WaveGems = table.freeze({
	table.freeze({ maxWave = 35, wave = 10, brute = 20, boss = 30 }),
	table.freeze({ maxWave = 111, wave = 0, brute = 20, boss = 60 }),
	table.freeze({ maxWave = 499, wave = 0, brute = 40, boss = 120 }),
	table.freeze({ maxWave = 1000, wave = 0, brute = 60, boss = 180 }),
	table.freeze({ maxWave = 1500, wave = 0, brute = 80, boss = 240 }),
	table.freeze({ maxWave = math.huge, wave = 0, brute = 100, boss = 300 }),
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

-- 1v1 Duel (docs/DICE_RATING.md sections 4 and 9): no wave cap and no draws; it ends at 0 lives or a surrender/forfeit.
-- Scaling from Random Dice PvP (docs/DUEL_SCALING.md): a boss ends every wave with HP BossPerRound x wave + AbsorbShare x the
-- lane's remaining mob HP (the boss absorbs them); from DeathWave mobs get tougher and faster; from BerserkWave a kill pays a
-- fixed BerserkMp and the boss is faster. All *tune* (the source's 25000 x round is on a larger HP scale than ours).
Balance.Duel = table.freeze({
	MinWavesForRewards = 3,
	BossPerRound = 300,
	AbsorbShare = 0.5,
	-- Round timer (randomdice.gg): 90 s, 10 s shorter each wave, floor 60 s. The boss comes once the mobs have spawned and
	-- the timer has run out, or earlier when both lanes are clear.
	RoundStart = 90,
	RoundStep = 10,
	RoundMin = 60,
	DeathWave = 7,
	DeathHpPerWave = 0.08,
	DeathSpeedPerWave = 0.03,
	BerserkWave = 11,
	KillMpPerWave = 10, -- kill MP = this x wave (10, then +10 per boss killed), capped at BerserkMp
	BerserkMp = 110,
	BerserkBossSpeed = 1.25,
}) -- a forfeit or surrender before this many cleared waves pays the winner nothing (win-trading guard, *tune*)

-- Net: token buckets per player and remote, and the hard-violation kick.
Balance.Remotes = table.freeze({
	Start = table.freeze({ rate = 1, burst = 2 }),
	CoopReady = table.freeze({ rate = 2, burst = 3 }),
	QueueDuel = table.freeze({ rate = 1, burst = 3 }), -- *tune*
	Surrender = table.freeze({ rate = 1, burst = 2 }), -- *tune*
	LeaveDuel = table.freeze({ rate = 1, burst = 2 }), -- *tune*
	TutorialAction = table.freeze({ rate = 2, burst = 3 }),
	Summon = table.freeze({ rate = 10, burst = 8 }),
	Merge = table.freeze({ rate = 5, burst = 8 }),
	EquipDeck = table.freeze({ rate = 1, burst = 3 }),
	TeamAction = table.freeze({ rate = 1, burst = 3 }),
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
