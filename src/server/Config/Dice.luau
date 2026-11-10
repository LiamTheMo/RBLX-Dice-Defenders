-- Fixed MVP deck (docs/DICE_CATALOG.md Common table). Data-driven perks:
--   vsKind[kind]        damage multiplier against one enemy kind
--   vsArmored           damage multiplier against armored enemies
--   shots/shotMul       projectiles per attack and per-shot damage multiplier
--   procEvery/procFlat  every Nth hit of a die instance adds flat damage
local Dice = {}

Dice.Deck = table.freeze({ "C01", "C02", "C03", "C04", "C05" })

Dice.Types = table.freeze({
	C01 = table.freeze({ name = "Pebble", base = 16, rate = 1.00, vsKind = table.freeze({ Grunt = 1.05 }) }),
	C02 = table.freeze({ name = "Needle", base = 9, rate = 1.75, procEvery = 6, procFlat = 8 }),
	C03 = table.freeze({ name = "Hammer", base = 30, rate = 0.55, vsArmored = 1.12 }),
	C04 = table.freeze({ name = "Twinshot", base = 10, rate = 0.95, shots = 2, shotMul = 0.7 }),
	-- shortcut: Longshot's +25% range perk is moot under global targeting; replacement perk TBD.
	C05 = table.freeze({
		name = "Longshot",
		base = 22,
		rate = 0.72,
		vsKind = table.freeze({ Boss = 0.9 }),
	}),
})

return table.freeze(Dice)
