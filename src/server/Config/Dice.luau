-- Dice.Deck is the starter deck (docs/DICE_CATALOG.md Common table); a match plays
-- the profile's own Deck. Data-driven perks:
--   vsKind[kind]        damage multiplier against one enemy kind
--   vsArmored           damage multiplier against armored enemies
--   shots              projectiles per attack, each using the die's base damage
--   procEvery/procFlat  every Nth hit of a die instance adds flat damage
--   aura                {base, perPip, perTier}: attack-speed bonus (fraction) to the 4 orthogonal neighbours,
--                       base + perPip x (pip - 1) + perTier x (tier - 1); a die's total is capped by Balance.AuraCap
-- Rare/Epic/Legendary are stat-only (no catalog ability): base x rate ~ 19 / 21 / 25 DPS, over every Common
-- at every pip and enemy kind, perks included (Hammer vs armored, Needle's proc).
local Dice = {}

Dice.Deck = table.freeze({ "C01", "C02", "C03", "C04", "C05" })

Dice.Types = table.freeze({
	C01 = table.freeze({
		name = "Pebble",
		rarity = "Common",
		base = 16,
		rate = 1.00,
		vsKind = table.freeze({ Grunt = 1.05 }),
	}),
	C02 = table.freeze({ name = "Needle", rarity = "Common", base = 9, rate = 1.75, procEvery = 6, procFlat = 8 }),
	C03 = table.freeze({ name = "Hammer", rarity = "Common", base = 30, rate = 0.55, vsArmored = 1.12 }),
	C04 = table.freeze({
		name = "Twinshot",
		rarity = "Common",
		base = 6,
		rate = 0.95,
		shots = 2,
		description = "Fires one shot at the front enemy and one at a random living enemy.",
	}),
	-- shortcut: Longshot's +25% range perk is moot under global targeting; replacement perk TBD.
	C05 = table.freeze({
		name = "Longshot",
		rarity = "Common",
		base = 22,
		rate = 0.72,
		vsKind = table.freeze({ Boss = 0.9 }),
	}),
	C06 = table.freeze({
		name = "Chill",
		rarity = "Common",
		base = 14,
		rate = 1.00,
		slow = 0.15,
		slowDuration = 1.5,
		description = "Hits slow enemies by 15% for 1.5 seconds.",
	}),
	C07 = table.freeze({
		name = "Spark",
		rarity = "Common",
		base = 12,
		rate = 1.15,
		procEvery = 4,
		procFlat = 5,
		description = "Every fourth hit deals 5 extra damage.",
	}),
	R01 = table.freeze({ name = "Frost", rarity = "Rare", base = 19, rate = 1.00 }),
	R02 = table.freeze({ name = "Arc", rarity = "Rare", base = 21, rate = 0.90 }),
	R03 = table.freeze({ name = "Volley", rarity = "Rare", base = 17, rate = 1.15 }),
	R04 = table.freeze({ name = "Venom", rarity = "Rare", base = 23, rate = 0.85 }),
	R05 = table.freeze({
		name = "Beacon",
		rarity = "Rare",
		base = 23,
		rate = 0.85,
		aura = table.freeze({ base = 0.06, perPip = 0.01, perTier = 0.01 }),
	}),
	R06 = table.freeze({ name = "Wind", rarity = "Rare", base = 15, rate = 1.30 }),
	R07 = table.freeze({ name = "Rock", rarity = "Rare", base = 26, rate = 0.75 }),
	E01 = table.freeze({ name = "Emberstorm", rarity = "Epic", base = 28, rate = 0.75 }),
	E03 = table.freeze({ name = "Mirror", rarity = "Epic", base = 21, rate = 1.00 }),
	E05 = table.freeze({ name = "Gravity", rarity = "Epic", base = 30, rate = 0.70 }),
	E06 = table.freeze({ name = "Ice", rarity = "Epic", base = 22, rate = 0.95 }),
	E07 = table.freeze({ name = "Leaf", rarity = "Epic", base = 24, rate = 0.88 }),
	E08 = table.freeze({ name = "Lightning", rarity = "Epic", base = 20, rate = 1.05 }),
	E09 = table.freeze({ name = "Water", rarity = "Epic", base = 26, rate = 0.80 }),
	E10 = table.freeze({ name = "Shadow", rarity = "Epic", base = 30, rate = 0.70 }),
	L01 = table.freeze({ name = "Chrono", rarity = "Legendary", base = 30, rate = 0.85 }),
	L02 = table.freeze({ name = "Forge", rarity = "Legendary", base = 34, rate = 0.75 }),
	L04 = table.freeze({ name = "Sun", rarity = "Legendary", base = 32, rate = 0.80 }),
	L05 = table.freeze({ name = "Fire", rarity = "Legendary", base = 34, rate = 0.75 }),
	L06 = table.freeze({
		name = "Light",
		rarity = "Legendary",
		base = 28,
		rate = 0.90,
		aura = table.freeze({ base = 0.08, perPip = 0.015, perTier = 0.015 }),
	}),
	M01 = table.freeze({
		name = "Astral",
		rarity = "Mythic",
		base = 140,
		rate = 0.80,
		singularity = table.freeze({ damage = 5, critChance = 10, critDamage = 2 }),
		description = "Singularity: With exactly one Astral on your board, it deals 5× damage. 10% of those hits deal 10× damage.",
	}),
	S01 = table.freeze({ name = "Dragon", rarity = "Secret", base = 36, rate = 0.80 }),
})

return table.freeze(Dice)
