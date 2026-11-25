-- Enemy kinds. speed in studs/s (before the per-wave multiplier); lives is the cost of a breach. hpMul is only
-- for Goblin King summons (Match.summonHp); queued Brute and Boss HP comes from CoopWaves.
local Enemies = {}

Enemies.Kinds = table.freeze({
	Grunt = table.freeze({ hpMul = 1, speed = 6, armored = false, lives = 1 }),
	Runner = table.freeze({ hpMul = 0.5, speed = 9, armored = false, lives = 1 }),
	Brute = table.freeze({ speed = 16 / 3, armored = true, lives = 2 }), -- the big mini-boss
	Boss = table.freeze({ speed = 3, armored = false, lives = 2 }), -- Thorn Warden
})

return table.freeze(Enemies)
