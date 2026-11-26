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
-- waves: even = mini-boss, odd = boss (2 / 6 cards). The first band whose maxWave >= w; `brute` = mini-boss wave.
-- Formulas.WaveGems then multiplies by the Challenge Tier's GemMul (owner: the cards become gems, 10 gems per card).
Balance.GemsPerCard = 10
Balance.WaveGems = table.freeze({
	table.freeze({ maxWave = 35, wave = 10, brute = 20, boss = 30 }),
	table.freeze({ maxWave = math.huge, wave = 0, brute = 20, boss = 60 }),
})
-- Challenge Tiers: `from` is the first wave of the tier. GemMul is the owner's (1, 2, 3, 4, 5). The owner gave no numbers for
-- the monster HP / movement speed jump or the shorter boss skill cooldowns, so those factors are neutral 1.0: TODO-owner.
-- Nothing reads HpMul / SpeedMul / CooldownMul yet.
Balance.ChallengeTiers = table.freeze({
	table.freeze({ from = 1, GemMul = 1, HpMul = 1.0, SpeedMul = 1.0, CooldownMul = 1.0 }),
	table.freeze({ from = 112, GemMul = 2, HpMul = 1.0, SpeedMul = 1.0, CooldownMul = 1.0 }), -- Tier 1 (112-499)
	table.freeze({ from = 500, GemMul = 3, HpMul = 1.0, SpeedMul = 1.0, CooldownMul = 1.0 }), -- Tier 2 (500-1000)
	table.freeze({ from = 1001, GemMul = 4, HpMul = 1.0, SpeedMul = 1.0, CooldownMul = 1.0 }), -- Tier 3 (1001-1500)
	table.freeze({ from = 1501, GemMul = 5, HpMul = 1.0, SpeedMul = 1.0, CooldownMul = 1.0 }), -- Max tier (1501+)
})
Balance.MaxRunWaves = 5000 -- anti-abuse cap on the waves a run may report (Quests.SettleRun)

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
-- fixed BerserkMp and the boss is faster. (25000 x round and the 40 s floor are the owner's Random Dice spec).
Balance.Duel = table.freeze({
	MinWavesForRewards = 3,
	BossPerRound = 25000,
	AbsorbShare = 0.5,
	-- Round timer (randomdice.gg): 90 s, 10 s shorter each wave, floor 40 s. The boss comes once the mobs have spawned and
	-- the timer has run out, or earlier when both lanes are clear.
	RoundStart = 90,
	RoundStep = 10,
	RoundMin = 40,
	DeathWave = 7,
	DeathHpPerWave = 0.08,
	DeathSpeedPerWave = 0.03,
	BerserkWave = 11,
	KillMpPerWave = 10, -- kill SP = min(BerserkMp, this x wave) (owner spec)
	BerserkMp = 110, -- the SP cap
	BossKillMul = 2, -- a boss pays this x the wave's regular-kill SP (max 220); Co-op keeps Balance.BossMpMul
	BerserkBossSpeed = 1.25,
}) -- a forfeit or surrender before this many cleared waves pays the winner nothing (win-trading guard, *tune*)

-- Duel XP and Gems (same Rewards path as Solo/Co-op; Gold stays Rating's streak Gold). Per wave cleared the winner earns
-- Formulas.RewardXp / RewardGems (the Solo payout), counting at most MaxWaves waves (long stalls cannot farm). The loser gets
-- LossXpFactor of the XP and LossGemFactor of the Gems; a bot match multiplies both by BotFactor. An early forfeit pays none. *tune*
Balance.DuelReward = table.freeze({ MaxWaves = 20, LossXpFactor = 0.4, LossGemFactor = 0, BotFactor = 0.5 })

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
