-- Enemy kinds. speed in studs/s (before the per-wave multiplier); hpMul folds in the
-- boss multiplier; energy is the kill reward; lives is the cost of a breach.
local Enemies = {}

Enemies.Kinds = table.freeze({
	Grunt = table.freeze({ hpMul = 1, speed = 6, armored = false, energy = 3, lives = 1 }),
	Runner = table.freeze({ hpMul = 0.70, speed = 9, armored = false, energy = 3, lives = 1 }),
	Brute = table.freeze({ hpMul = 3.0, speed = 4, armored = true, energy = 5, lives = 1 }),
	Boss = table.freeze({ hpMul = 12, speed = 3, armored = false, energy = 30, lives = 5 }), -- Thorn Warden
})

return table.freeze(Enemies)
