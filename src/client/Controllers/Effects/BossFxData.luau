--!strict
-- Pure (Roblox-light) tables and maths behind BossFx: boss palettes, per-hook live-part budgets, particle counts per
-- quality tier, spiral / confetti motion. Kept apart so tests/luau can check palettes, budgets and curves headless.

local BossFxData = {}

local hex = Color3.fromHex

BossFxData.Palette = table.freeze({
	GoblinKing = table.freeze({
		Gold = hex("#FFC933"),
		Slate = hex("#3d4a5c"), -- the summon portal: base, glow and dark core of the map portal structure
		SlateGlow = hex("#6b7f99"),
		SlateCore = hex("#1c2330"),
	}),
	CursedKing = table.freeze({
		Violet = hex("#9B30FF"),
		Stone = hex("#6E6A78"),
		Light = hex("#D9A8FF"),
		Dust = hex("#B8B2A6"),
	}),
	CourtJester = table.freeze({
		Pink = hex("#FF40D0"),
		Purple = hex("#8A3FD0"),
		Gold = hex("#FFD23F"),
		White = hex("#FFFFFF"),
	}),
})

-- Most mesh/plain parts one hook keeps alive at full quality. Boss total (hooks that overlap) must stay <= 40.
BossFxData.Budget = table.freeze({
	GoblinKing = table.freeze({ Windup = 7, Cast = 7 }), -- Cast: the 7-layer PortalFx portal
	CursedKing = table.freeze({ Windup = 5, Cast = 11, Locks = 24 }), -- Locks: 6 dice x (ring + 2 chains + plate)
	CourtJester = table.freeze({ Windup = 13, Cast = 15, Impact = 10 }),
})
BossFxData.MaxLive = 40

-- The portal grows in exactly like a die appearing on the board (BoardView: MIN_DIE_SCALE 0.001, EXPAND_TIME 0.25 s,
-- 1 - (1 - min) * (1 - t)^2) and shrinks closed with the same curve reversed.
BossFxData.PortalGrow = table.freeze({ Min = 0.001, Seconds = 0.25 })

-- Portal scale `age` seconds after it opened, open for `open` seconds, then closing: 0.001..1..0.001.
function BossFxData.PortalScale(age: number, open: number): number
	local g = BossFxData.PortalGrow
	local function curve(t: number): number
		t = math.clamp(t / g.Seconds, 0, 1)
		return 1 - (1 - g.Min) * (1 - t) ^ 2
	end
	return math.min(curve(age), curve(open + g.Seconds - age))
end

-- Seconds the Windup effect runs: until the cast frame, kept sane when the clocks disagree.
function BossFxData.WindupSeconds(castAt: number, now: number): number
	return math.clamp(castAt - now, 0.2, 2)
end

-- Particle count for a hook: none in reduced motion, half on the Low tier (phones).
function BossFxData.Count(full: number, low: boolean, reduced: boolean): number
	if reduced then
		return 0
	end
	return if low then math.ceil(full / 2) else full
end

-- Offset of particle k of n on a rising spiral at time u (0..1 of the effect): turns = full turns by u = 1, each
-- particle climbs 0..height on its own phase and wraps, radius tightens slightly.
function BossFxData.Spiral(
	k: number,
	n: number,
	u: number,
	radius: number,
	height: number,
	turns: number
): (number, number, number)
	local phase = k / n
	local a = (turns * u + phase) * 2 * math.pi
	local r = radius * (1 - 0.25 * u)
	return math.cos(a) * r, ((u * 1.5 + phase) % 1) * height, math.sin(a) * r
end

-- Ballistic confetti: position after t seconds from launch velocity (vx, vy, vz) under gravity g.
function BossFxData.Ballistic(vx: number, vy: number, vz: number, t: number, g: number): (number, number, number)
	return vx * t, vy * t - 0.5 * g * t * t, vz * t
end

return table.freeze(BossFxData)
