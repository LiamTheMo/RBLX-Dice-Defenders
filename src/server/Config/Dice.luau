-- Dice.Deck is the starter deck (docs/DICE_CATALOG.md Common table); a match plays
-- the profile's own Deck. Stats follow docs/DICE_REBALANCE_PROPOSAL.md: per-pip DPS (base x shots x rate) is
-- ~300 Common / ~1000 Rare / ~3300 Epic / ~13000 Legendary, so a full-rarity deck reaches about wave 20 / 30 / 40 / 80
-- against Config/CoopWaves (tools/balance_sim.py; abilities are not in the sim). Data-driven perks:
--   vsKind[kind]        damage multiplier against one enemy kind
--   vsArmored           damage multiplier against armored enemies
--   shots              projectiles per attack, each using the die's base damage
--   spread             with shots > 1: aim every shot at a different enemy when enough are alive
--   targeting          "Strongest": aim at the highest-HP enemy instead of the front one
--   procEvery/procFlat  every Nth hit of a die instance adds flat damage
--   slow/slowDuration/slowChance  hit slows an enemy by `slow` (fraction); chance defaults to 1
--   freezeEvery/freezeFor         every Nth hit freezes a non-boss enemy for freezeFor seconds
--   chainEvery/chainCount/chainMul  every Nth attack also hits chainCount other enemies for chainMul of the hit
--   poison {dps, duration, maxStacks}  stacking damage over time per die; spreads to the nearest enemy on death
--   burn {dps, duration}, detonate {every, radius}  Emberstorm: burn, and a timer that cashes in every burn
--   mirror {duration}   on summon/merge copies the perk set of the best adjacent die for that long
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
		base = 300,
		rate = 1.00,
		vsKind = frozen({ Grunt = 1.05 }),
	}),
	C02 = frozen({ name = "Needle", rarity = "Common", base = 170, rate = 1.75, procEvery = 6, procFlat = 150 }),
	C03 = frozen({ name = "Hammer", rarity = "Common", base = 570, rate = 0.55, vsArmored = 1.12 }),
	C04 = frozen({
		name = "Twinshot",
		rarity = "Common",
		base = 130,
		rate = 0.95,
		shots = 2,
		description = "Fires one shot at the front enemy and one at a random living enemy.",
	}),
	C05 = frozen({
		name = "Longshot",
		rarity = "Common",
		base = 420,
		rate = 0.72,
		targeting = "Strongest",
		description = "Sniper: always aims at the enemy with the most health.",
	}),
	C06 = frozen({
		name = "Chill",
		rarity = "Common",
		base = 270,
		rate = 1.00,
		slow = 0.15,
		slowDuration = 1.5,
		description = "Hits slow enemies by 15% for 1.5 seconds.",
	}),
	C07 = frozen({
		name = "Spark",
		rarity = "Common",
		base = 230,
		rate = 1.15,
		procEvery = 4,
		procFlat = 95,
		description = "Every fourth hit deals 95 extra damage.",
	}),
	R01 = frozen({
		name = "Frost",
		rarity = "Rare",
		base = 750,
		rate = 1.00,
		slow = 0.25,
		slowDuration = 2.5,
		slowChance = 0.20,
		freezeEvery = 8,
		freezeFor = 0.6,
		description = "20% chance to slow 25% for 2.5 s. Every 8th hit freezes a normal enemy for 0.6 s.",
	}),
	R02 = frozen({
		name = "Arc",
		rarity = "Rare",
		base = 750,
		rate = 0.90,
		chainEvery = 4,
		chainCount = 2,
		chainMul = 0.6,
		description = "Every 4th attack chains to 2 more enemies for 60% damage.",
	}),
	R03 = frozen({
		name = "Volley",
		rarity = "Rare",
		base = 225,
		rate = 1.15,
		shots = 3,
		spread = true,
		description = "Three bolts per attack, each at a different enemy when possible.",
	}),
	R04 = frozen({
		name = "Venom",
		rarity = "Rare",
		base = 675,
		rate = 0.85,
		poison = frozen({ dps = 90, duration = 4, maxStacks = 4 }),
		description = "Hits stack poison (90/s for 4 s, up to 4). A poisoned enemy that dies passes it on.",
	}),
	R05 = frozen({
		name = "Beacon",
		rarity = "Rare",
		base = 855,
		rate = 0.85,
		aura = frozen({ base = 0.06, perPip = 0.01, perTier = 0.01 }),
	}),
	E01 = frozen({
		name = "Emberstorm",
		rarity = "Epic",
		base = 4200,
		rate = 0.75,
		burn = frozen({ dps = 400, duration = 3 }),
		detonate = frozen({ every = 6, radius = 10 }),
		description = "Hits burn (400/s for 3 s). Every 6 s all burns cash in at once and spread nearby.",
	}),
	E02 = frozen({
		name = "Mirror",
		rarity = "Epic",
		base = 3300,
		rate = 1.00,
		mirror = frozen({ duration = 10 }),
		description = "On summon or merge, copies the ability of the best adjacent die for 10 s.",
	}),
	E03 = frozen({
		name = "Gravity",
		rarity = "Epic",
		base = 4900,
		rate = 0.70,
		pull = frozen({ every = 7, count = 5, back = 0.12, bossSlow = 0.35, bossSlowFor = 1.5 }),
		description = "Every 7 s pulls up to 5 enemies back 12% of the lane. Bosses are slowed instead.",
	}),
	L01 = frozen({
		name = "Chrono",
		rarity = "Legendary",
		base = 27500,
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
		description = "Every 10 s a Time Rift slows enemies 60% for 4 s; every 3rd also rewinds them. Bosses are only slowed.",
	}),
	L02 = frozen({
		name = "Forge",
		rarity = "Legendary",
		base = 31200,
		rate = 0.75,
		forge = frozen({ every = 4, gap = 5 }),
		description = "Merges next to Forge keep the dragged die's type. Every 4th also spawns a free pip-1 die.",
	}),
	M01 = frozen({
		name = "Astral",
		rarity = "Mythic",
		base = 34900,
		rate = 0.80,
		singularity = frozen({ damage = 5, critChance = 10, critDamage = 2 }),
		description = "Singularity: With exactly one Astral on your board, it deals 5× damage. 10% of those hits deal 10× damage.",
	}),
	S01 = frozen({
		name = "Dragon",
		rarity = "Secret",
		base = 40500,
		rate = 0.80,
		pierce = 3,
		wyrmfire = frozen({ every = 12, duration = 6, pct = 0.004, bossPct = 0.001 }),
		description = "Shots pierce 3 more enemies. Every 12 s Wyrmfire burns the whole lane for 0.4% max health per second.",
	}),
})

return table.freeze(Dice)
