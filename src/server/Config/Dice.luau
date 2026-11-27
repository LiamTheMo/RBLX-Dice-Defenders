-- Dice.Deck is the starter deck (docs/DICE_CATALOG.md Common table); a match plays
-- the profile's own Deck. Stats follow docs/DICE_REBALANCE_PROPOSAL.md: per-pip DPS (base x shots x rate) is
-- ~150 Common / ~580 Rare / ~3100 Epic / ~19000 Legendary at level 1 (base x shots x rate); Progression.DamageMul
-- makes every die x6 at its top level. Simulated reach (tools/balance_sim.py, real Match with abilities, levels and crit):
-- starter Commons lv1 ~15, Rares top ~50-58, Epic+Rare mix top ~77, Legendary/Mythic mix top ~90-95. Data-driven perks:
--   vsKind[kind]        damage multiplier against one enemy kind
--   vsArmored           damage multiplier against armored enemies
--   shots              projectiles per attack, each using the die's base damage
--   spread             with shots > 1: aim every shot at a different enemy when enough are alive
--   targeting          "Strongest": aim at the highest-HP enemy instead of the front one
--   procEvery/procFlat  every Nth hit of a die instance adds flat damage
--   slow/slowDuration/slowChance  hit slows an enemy by `slow` (fraction); chance defaults to 1
--   freezeEvery/freezeFor         every Nth hit freezes a non-boss enemy for freezeFor seconds
--   chainEvery/chainCount/chainMul  every Nth attack also hits chainCount other enemies for chainMul of the hit
--   cascade {front, second, third}  every hit damages the front enemy and the next two behind it for these fractions
--   poison {dps, duration, maxStacks}  stacking damage over time per die; spreads to the nearest enemy on death
--   burn {dps, duration}, detonate {every, radius}  Emberstorm: burn, and a timer that cashes in every burn
--   mirror              on summon/merge the die takes the highest pip count on the board
--   pull {every, count, back, bossSlow, bossSlowFor}  timer: pulls enemies back along the path
--   rift {...}          Chrono timer: slow rift, every Nth also rewinds (docs/DICE_REBALANCE_PROPOSAL.md)
--   forge {every, gap}  merges next to this die keep the dragged die's type; every Nth also spawns a free die
--   pierce              shots also hit the next `pierce` enemies behind the target
--   wyrmfire {every, duration, pct, bossPct}  timer: lane-wide % max-HP burn
--   aura                {base, perPip, perTier}: attack-speed bonus (fraction) to the 4 orthogonal neighbours,
--                       base + perPip x (pip - 1) + perTier x (tier - 1); a die's total is capped by Balance.AuraCap
--   singularity         Astral: with exactly one on the board, x damage and a crit chance
local Dice = {}

Dice.Deck = table.freeze({ "C01", "C02", "C03", "C04", "C05" })

-- Bag display: how a die picks its target unless its entry sets `targeting`. Every die is "Front" for now.
Dice.DefaultTargeting = "Front"

local function frozen(t)
	return table.freeze(t)
end

Dice.Types = table.freeze({
	C01 = frozen({
		name = "Pebble",
		rarity = "Common",
		base = 150,
		rate = 1.00,
		vsKind = frozen({ Grunt = 1.05 }),
		description = "Deals bonus damage to Grunts.",
	}),
	C02 = frozen({
		name = "Needle",
		rarity = "Common",
		base = 85,
		rate = 1.75,
		procEvery = 6,
		procFlat = 75,
		description = "Fast attacks. Every few hits adds flat bonus damage.",
	}),
	C03 = frozen({
		name = "Hammer",
		rarity = "Common",
		base = 285,
		rate = 0.55,
		vsArmored = 1.12,
		description = "Slow, heavy hits that deal bonus damage to armored enemies.",
	}),
	C04 = frozen({
		name = "Twinshot",
		rarity = "Common",
		base = 65,
		rate = 0.95,
		shots = 2,
		description = "Fires one shot at the front enemy and one at a random living enemy.",
	}),
	C05 = frozen({
		name = "Longshot",
		rarity = "Common",
		base = 210,
		rate = 0.72,
		targeting = "Strongest",
		description = "Aims at the enemy with the most health; no boss penalty.",
	}),
	C06 = frozen({
		name = "Chill",
		rarity = "Common",
		base = 135,
		rate = 1.00,
		slow = 0.15,
		slowDuration = 1.5,
		description = "Hits slow enemies for a short time.",
	}),
	C07 = frozen({
		name = "Spark",
		rarity = "Common",
		base = 115,
		rate = 1.15,
		chainEvery = 4,
		chainCount = 1,
		chainMul = 0.6,
		description = "Every few attacks chain to more enemies for 60% of the hit.",
	}),
	R01 = frozen({
		name = "Frost",
		rarity = "Rare",
		base = 620,
		rate = 1.00,
		slow = 0.25,
		slowDuration = 2.5,
		slowChance = 0.20,
		freezeEvery = 8,
		freezeFor = 0.6,
		description = "Hits can slow enemies, and every few hits freeze a normal enemy for 0.6 s.",
	}),
	R02 = frozen({
		name = "Arc",
		rarity = "Rare",
		base = 620,
		rate = 0.90,
		cascade = frozen({ 0.9, 0.4, 0.2 }),
		description = "Every hit strikes the front enemy for 90% of its damage, the enemy behind it for 40% and a third for 20%.",
	}),
	R03 = frozen({
		name = "Volley",
		rarity = "Rare",
		base = 185,
		rate = 1.15,
		shots = 3,
		spread = true,
		description = "Fires several bolts per attack, each at a different enemy when possible.",
	}),
	R04 = frozen({
		name = "Venom",
		rarity = "Rare",
		base = 560,
		rate = 0.85,
		poison = frozen({ dps = 75, duration = 4, maxStacks = 4 }),
		description = "Hits stack poison. A poisoned enemy that dies passes it on.",
	}),
	R05 = frozen({
		name = "Beacon",
		rarity = "Rare",
		base = 710,
		rate = 0.85,
		aura = frozen({ base = 0.06, perPip = 0.01, perTier = 0.01 }),
		description = "Boosts the attack speed of the dice next to it, up and down and side to side.",
	}),
	E01 = frozen({
		name = "Emberstorm",
		rarity = "Epic",
		base = 3950,
		rate = 0.75,
		burn = frozen({ dps = 375, duration = 3 }),
		detonate = frozen({ every = 6, radius = 10 }),
		description = "Hits burn enemies. Every few seconds all burns cash in at once and spread nearby.",
	}),
	E02 = frozen({
		name = "Mirror",
		rarity = "Epic",
		base = 3100,
		rate = 1.00,
		mirror = true,
		description = "On summon or merge, copies the highest pip count on the board.",
	}),
	E03 = frozen({
		name = "Gravity",
		rarity = "Epic",
		base = 4600,
		rate = 0.70,
		pull = frozen({ every = 7, count = 5, back = 0.12, bossSlow = 0.35, bossSlowFor = 1.5 }),
		description = "Every few seconds pulls enemies back along the lane. Bosses are slowed instead.",
	}),
	L01 = frozen({
		name = "Chrono",
		rarity = "Legendary",
		base = 22500,
		rate = 0.85,
		rift = frozen({
			every = 10,
			radius = 18,
			slow = 0.60,
			bossSlow = 0.30,
			duration = 4,
			rewindEvery = 3,
			rewind = 0.15,
			maxRewinds = 3,
		}),
		description = "Time Rifts slow nearby enemies, and every few rifts also rewind them. Bosses are only slowed.",
	}),
	L02 = frozen({
		name = "Forge",
		rarity = "Legendary",
		base = 25500,
		rate = 0.75,
		forge = frozen({ every = 4, gap = 5 }),
		description = "Merges next to Forge keep the dragged die's type. Every few merges also spawn a free pip-1 die.",
	}),
	M01 = frozen({
		name = "Astral",
		rarity = "Mythic",
		base = 13500,
		rate = 0.80,
		singularity = frozen({ damage = 5, critChance = 10, critDamage = 2 }),
		description = "Singularity: With exactly one Astral on your board, it deals 5× damage. 10% of those hits deal 10× damage.",
	}),
	S01 = frozen({
		name = "Wyvern",
		rarity = "Secret",
		base = 29000,
		rate = 0.80,
		pierce = 3,
		wyrmfire = frozen({ every = 12, duration = 6, pct = 0.004, bossPct = 0.001 }),
		description = "Shots pierce enemies behind the target. Every few seconds Wyrmfire burns the whole lane for a share of max health (bosses far less).",
	}),
})

-- Designed dice (docs/NEW_DICE_ART_PROMPT.md) with no art and no ability code yet. Deliberately NOT in Dice.Types:
-- Roll, Bot, Claims and the profile schema iterate Types, so a die there can be rolled before the client can draw it.
-- Per-pip DPS at level 1 (base x shots x rate) is the comment on each row. To release one: build its art, add the rule in
-- Rules/Abilities (+ a DiceClasses scale), move its entry into Types, and add Display + DiceAssets rows. Rule tables
-- (wager, root, splash, mark, killMp, pctHit, tether, mint, surge, growth, link, relay, vault, eclipse, doom) are
-- the intended data shape, read by nothing yet; mint every/mp are *tune* placeholders.
Dice.Pending = table.freeze({
	C08 = frozen({ -- 150
		name = "Anvil",
		rarity = "Common",
		base = 273,
		rate = 0.55,
		vsKind = frozen({ Brute = 1.6, Boss = 1.6 }),
		description = "Slow, heavy hits that deal 60% more damage to Brutes and Bosses.",
	}),
	C09 = frozen({ -- 150 average
		name = "Wager",
		rarity = "Common",
		base = 150,
		rate = 1.00,
		wager = frozen({ min = 0.4, max = 2.6 }),
		description = "Every hit rolls between 40% and 260% of its damage, 100% on average.",
	}),
	C10 = frozen({ -- 130
		name = "Shackle",
		rarity = "Common",
		base = 130,
		rate = 1.00,
		root = frozen({ chance = 0.08, duration = 1.5, oncePerEnemy = true }),
		description = "Hits have a small chance to root a normal enemy for 1.5 s, once per enemy.",
	}),
	C11 = frozen({ -- 145
		name = "Blast",
		rarity = "Common",
		base = 145,
		rate = 1.00,
		splash = frozen({ radius = 8, mul = 0.5 }),
		description = "Hits splash enemies within 8 studs for 50% of the damage.",
	}),
	R06 = frozen({ -- 500
		name = "Hex",
		rarity = "Rare",
		base = 500,
		rate = 1.00,
		mark = frozen({ perStack = 0.08, maxStacks = 3, bossMul = 0.5 }),
		description = "Hits mark an enemy: it takes +8% damage from every die per stack, up to 3 stacks (bosses half).",
	}),
	R07 = frozen({ -- 500
		name = "Tithe",
		rarity = "Rare",
		base = 500,
		rate = 1.00,
		killMp = 0.25,
		description = "Enemies it kills pay 25% more MP.",
	}),
	E11 = frozen({ -- 2800
		name = "Reaper",
		rarity = "Epic",
		base = 2800,
		rate = 1.00,
		pctHit = frozen({ every = 4, pct = 0.03, bossMul = 0.25 }),
		description = "Every 4th hit deals 3% of the enemy's current health (a quarter of that on bosses).",
	}),
	E12 = frozen({ -- 2900
		name = "Tether",
		rarity = "Epic",
		base = 2900,
		rate = 1.00,
		tether = frozen({ count = 3, share = 0.3 }),
		description = "Marks 3 enemies; damage dealt to one is shared with the others at 30%.",
	}),
	E13 = frozen({ -- 2900
		name = "Mint",
		rarity = "Epic",
		base = 2900,
		rate = 1.00,
		mint = frozen({ every = 10, mp = 10, maxPerBoard = 3 }),
		description = "Pays MP on a timer. At most 3 Mints per board.",
	}),
	E14 = frozen({ -- 2700
		name = "Surge",
		rarity = "Epic",
		base = 2700,
		rate = 1.00,
		surge = frozen({ every = 8, duration = 6, speed = 0.5 }),
		description = "Every 8 s a random die on the board gets +50% attack speed for 6 s.",
	}),
	L07 = frozen({ -- 16000
		name = "Sunder",
		rarity = "Legendary",
		base = 16000,
		rate = 1.00,
		pctHit = frozen({ every = 5, pct = 0.02, bossPct = 0.005 }),
		description = "Every 5th hit deals 2% of the enemy's current health (0.5% on bosses).",
	}),
	L08 = frozen({ -- 13000 at the start of a match
		name = "Overgrowth",
		rarity = "Legendary",
		base = 13000,
		rate = 1.00,
		growth = frozen({ perWave = 0.02, max = 2.0 }),
		description = "+2% damage for every wave cleared this match, up to +200%.",
	}),
	L09 = frozen({ -- 17000
		name = "Nexus",
		rarity = "Legendary",
		base = 17000,
		rate = 1.00,
		link = frozen({ count = 6, bossLinked = false, bruteShare = 0.5 }),
		description = "Links 6 enemies and shares damage between them. Bosses are never linked; Brutes share half.",
	}),
	L10 = frozen({ -- 16000
		name = "Prism",
		rarity = "Legendary",
		base = 16000,
		rate = 1.00,
		relay = frozen({ every = 12, eclipseGap = 10 }),
		description = "Every 12 s re-triggers the timer abilities of adjacent dice (Eclipse at most once per 10 s).",
	}),
	L11 = frozen({ -- 16000
		name = "Vault",
		rarity = "Legendary",
		base = 16000,
		rate = 1.00,
		vault = frozen({ interest = 0.05, powerUpDiscount = 0.15 }),
		description = "+5% MP interest, and Power Up costs 15% less.",
	}),
	M02 = frozen({ -- 8500
		name = "Eclipse",
		rarity = "Mythic",
		base = 8500,
		rate = 1.00,
		eclipse = frozen({ every = 15, duration = 5, bonus = 0.5, bossBonus = 0.25 }),
		description = "Every 15 s, for 5 s, all enemies take +50% damage (+25% on bosses).",
	}),
	S02 = frozen({ -- 19000
		name = "Doomsday",
		rarity = "Secret",
		base = 19000,
		rate = 1.00,
		doom = frozen({ every = 30, pct = 0.10, bossPct = 0.025 }),
		description = "Every 30 s deals 10% of current health to every enemy (2.5% on bosses).",
	}),
})

return table.freeze(Dice)
