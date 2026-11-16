-- Enemy kinds. speed in studs/s (before the per-wave multiplier); hpMul scales the
-- Formulas.EnemyHp curve (the Boss has its own formula); lives is the cost of a breach.
local Enemies = {}

Enemies.Kinds = table.freeze({
	Grunt = table.freeze({ hpMul = 1, speed = 6, armored = false, lives = 1 }),
	Runner = table.freeze({ hpMul = 0.5, speed = 9, armored = false, lives = 1 }),
	Brute = table.freeze({ hpMul = 10, speed = 16 / 3, armored = true, lives = 2 }), -- the big mini-boss
	Boss = table.freeze({ speed = 3, armored = false, lives = 2 }), -- Thorn Warden
})

return table.freeze(Enemies)
