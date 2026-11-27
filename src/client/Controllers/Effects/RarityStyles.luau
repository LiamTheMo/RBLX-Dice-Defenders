-- Data for the Rare/Epic/Legendary/Mythic dice effects (R01-R05, E01-E03, L01-L02, M01). Every size is
-- authored for a 5-stud die (rulings R1): RarityEffects multiplies by k = dieSize / 5. Numbers come from the
-- layer tables in Assets/Models/Dice/<Rarity>/vfx/<ID>_layers.json (the sheet wins over the README).
-- Mesh keys are the FxMeshes names. Colour hexes are the layer tables' colours; secondary tints the importer
-- could not carry are tweened in Luau (colours = {start, mid, end} across the layer's duration).
--
-- Layer fields (impact, all optional unless noted):
--   role      "flash" | "ring" | "shard" | "support" (quality tier gate: Low keeps only "flash")
--   mesh      FxMeshes key (required)
--   orient    "camera" (stand toward the camera at the hit point) | "yaw" (upright, turn toward the camera)
--             | "ground" (flat on the board) | "upright" (base on the board)
--   full      uniform multiplier of the mesh's base size at fraction 1 (number) or per-axis (Vector3)
--   scale     curve seconds -> fraction of full; scaleY overrides the vertical axis (vertical-only growth)
--   opacity   curve seconds -> opacity (Transparency = 1 - opacity); omitted = opaque (fade by shrinking)
--   dur       seconds the layer lives
--   pivotUp   studs from the authored pivot (board / base) up to the mesh's bounding-box centre, at fraction 1
--   spin      radians per second about the vertical / normal axis (not under reduced motion)
--   lift      studs above the board for orient = "ground" (orders stacked flat layers without z-fighting)
--   roll      "random": random spin about the normal, re-rolled at reroll seconds
--   when      name of a condition on the shot (see RarityEffects.conditions)
--   count/delay/motion/align: pooled particle layers (shards): motion(i, u, ctx) returns a world position
local ProjectileFlight = require(game:GetService("ReplicatedStorage").Shared.ProjectileFlight)
local FxCore = require(script.Parent.FxCore)

local Ease = FxCore.Easing
local TAU = math.pi * 2

local RarityStyles = {}

local function curve(...)
	local keys = {}
	for _, key in { ... } do
		table.insert(keys, { t = key[1], v = key[2], ease = if key[3] then Ease[key[3]] else nil })
	end
	return keys
end

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

-- Outward / inward fan around the hit point. ctx: ground, hit, k, n (count), seed.
local function radial(r0: number, r1: number, h0: number, h1: number, arc: number?, ease: string?)
	local shape = Ease[ease or "quadOut"]
	return function(i: number, u: number, ctx, _n: number?)
		local angle = ctx.seed + i * 2.39996
		local e = shape(u)
		local radius = (r0 + (r1 - r0) * e) * ctx.k
		local height = (h0 + (h1 - h0) * u + (arc or 0) * 4 * u * (1 - u)) * ctx.k
		return ctx.ground + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
	end
end
RarityStyles.radial = radial

-- Orbit about the hit point (preview "spiral"): radius shrinks 25%, rises `height` per cycle, `turns` turns per layer.
local function spiral(radius: number, height: number, turns: number, lift: number)
	return function(i: number, u: number, ctx, n: number?)
		local phase = i / (n or 1)
		local angle = (turns * u + phase) * TAU
		local r = radius * (1 - 0.25 * u)
		local rise = ((1.5 * u + phase) % 1) * height + lift
		return ctx.ground + Vector3.new(math.cos(angle) * r, rise, math.sin(angle) * r) * ctx.k
	end
end

-- Sparks thrown from the hit (preview "ballistic"): 12-24 outward (z x0.55), 8-14 up, gravity g. Per-spark values
-- come from the index and ctx.seed, so the position is a pure function of (i, u) as drawItem requires.
local function ballistic(g: number, dur: number, lift: number)
	return function(i: number, u: number, ctx, _n: number?)
		local angle = ctx.seed + i * 2.39996
		local speed = 12 + 12 * ((i * 0.618) % 1)
		local up = 8 + 6 * ((i * 0.382 + 0.3) % 1)
		local t = u * dur
		local offset =
			Vector3.new(math.cos(angle) * speed * t, up * t - 0.5 * g * t * t, math.sin(angle) * speed * 0.55 * t)
		return ctx.ground + (offset + Vector3.new(0, lift, 0)) * ctx.k
	end
end

-- Impact layers shared by several dice ---------------------------------------------------------------------

-- color: one Color3, or a list lerped over the layer's life (bright core -> coloured tips). start: scale at t = 0.
local function star(
	mesh: string,
	size: number,
	color: Color3 | { Color3 },
	popAt: number,
	dur: number,
	start: number?,
	extra
)
	local layer = {
		role = "flash",
		mesh = mesh,
		orient = "camera",
		full = size,
		scale = curve({ 0, start or 0.4 }, { popAt, 1, "quadOut" }, { dur, 0 }),
		colors = if typeof(color) == "table" then color else { color },
		dur = dur,
	}
	for key, value in extra or {} do
		layer[key] = value
	end
	return layer
end

-- Profiles ---------------------------------------------------------------------------------------------------
-- core: the flying projectile. aim = "orb" (position only) | "z" (long axis Z along travel, tip +Z)
--       | "nz" (same axis, tip -Z, no flip; spin = rad/s about travel; heart = counter-spinning copy)
--       | "y" (long axis Y along travel) | "flat" (flat arrow, thin axis toward the camera) | "camera".
-- ribbons: extra meshes behind the core, High tier only: { mesh, color, x, back, len = curve(progress -> Z factor) }.
-- trails: Trail ribbons on the core (colors start/end, width and length in studs at D=5).

local Profiles = {}

Profiles.R01 = {
	core = {
		mesh = "Fx_Diamond",
		aim = "y",
		size = Vector3.new(0.6, 1.6, 0.55),
		color = hex("7FEFFF"),
	},
	trails = {
		{
			c0 = hex("00D9FF"),
			c1 = hex("7FEFFF"),
			width = 0.5,
			length = 2.9,
			life = 0.2,
			light = 0.8,
			transparency = 0.3,
		},
	},
	impact = {
		{
			role = "flash",
			mesh = "Frost_Burst",
			orient = "upright",
			full = 1,
			scale = curve({ 0, 0 }, { 0.1, 1, "quadOut" }, { 0.3, 0, "quadIn" }),
			colors = { hex("EFFFFF"), hex("7FEFFF"), hex("00D9FF") },
			dur = 0.3,
			pivotUp = 1.0478,
		},
		{
			role = "ring",
			mesh = "Fx_Ring",
			orient = "ground",
			full = 3.2,
			scale = curve({ 0, 0.2 }, { 0.1, 1, "quadOut" }, { 0.3, 1 }),
			opacity = curve({ 0, 1 }, { 0.3, 0, "quadOut" }),
			colors = { hex("00D9FF") },
			dur = 0.3,
		},
	},
	status = {
		flake = { mesh = "Frost_Snowflake", color = hex("EFFFFF"), size = 0.9, above = 0.8, spin = math.rad(20) },
		ring = { mesh = "Fx_Ring", color = hex("7FEFFF"), diameter = 2.4, transparency = 0.5 },
	},
}

Profiles.R02 = {
	core = { mesh = "Fx_Orb", aim = "orb", size = 0.6, color = hex("F8E6FF"), shrink = 0.08 },
	trails = {
		{
			c0 = hex("D77BFF"),
			c1 = hex("9A40FF"),
			width = 0.5,
			length = 2.4,
			life = 0.2,
			light = 1,
			transparency = 0.2,
		},
	},
	impact = {
		star("Fx_Star8", 1.4, hex("D77BFF"), 0.03, 0.1, 0),
		{
			role = "ring",
			mesh = "Arc_Ring",
			orient = "ground",
			full = 3.0 / 0.992,
			scale = curve({ 0, 0.5 }, { 0.1, 0.9, "quadOut" }, { 0.3, 1 }),
			opacity = curve({ 0, 1 }, { 0.3, 0 }),
			colors = { hex("9A40FF") },
			dur = 0.3,
		},
		{
			role = "shard",
			mesh = "Arc_Bolt",
			orient = "camera",
			full = 2.5,
			scale = curve({ 0, 0.3 }, { 0.04, 1 }, { 0.15, 1 }),
			opacity = curve({ 0, 0 }, { 0.035, 1 }, { 0.15, 0, "quadOut" }),
			colors = { hex("D77BFF") },
			dur = 0.15,
			roll = "random",
			reroll = 0.1,
			startPivot = 0.5, -- the mesh runs +X from the pivot: centre sits half a length along
		},
	},
	chain = { color = hex("D77BFF"), core = hex("F8E6FF"), width = 0.25, coreWidth = 0.1, dur = 0.2, max = 3 },
}

Profiles.R03 = {
	core = {
		mesh = "Volley_Bolt",
		aim = "flat",
		size = Vector3.new(0.45, 0.15, 0.9),
		color = hex("FFF6F6"),
		fadeIn = 0.05, -- fraction of travel
		xTrail = true,
	},
	trails = {
		{ c0 = hex("FF3B3B"), c1 = hex("B7192A"), width = 0.3, length = 2.0, life = 0.15, light = 0.8 },
	},
	impact = {
		star("Volley_Flash", 1, hex("FFF6F6"), 0.06, 0.13, nil, { when = "laneZero" }),
		{
			role = "ring",
			mesh = "Volley_Ring",
			orient = "ground",
			full = 3.0,
			scale = curve({ 0, 0.2 }, { 0.1, 1, "quadOut" }, { 0.3, 1 }),
			opacity = curve({ 0, 1 }, { 0.1, 1 }, { 0.3, 0 }),
			colors = { hex("FF7A7A"), hex("FF3B3B"), hex("B7192A") },
			dur = 0.3,
			when = "laneZero",
		},
	},
	supportLoad = 0.75, -- support layers only borrow while Fx.Live() is under this share of the global cap
}

Profiles.R04 = {
	core = {
		mesh = "Venom_Droplet",
		aim = "z",
		size = Vector3.new(0.7, 0.7, 1.0),
		color = hex("B7FF3A"),
		scale = curve({ 0, 0.8 }, { 0.25, 0.85 }, { 0.75, 1 }, { 1, 1.4 }),
		scaleByProgress = true,
		fadeOut = 0.9, -- opacity 1 until this fraction of travel, then 0 at the hit
	},
	trails = {
		{ c0 = hex("55D20A"), c1 = hex("2B6E00"), width = 0.5, length = 2.2, life = 0.2, light = 0.7 },
	},
	impact = {
		{
			role = "flash",
			mesh = "Venom_Splash",
			orient = "upright",
			full = 1,
			scale = curve({ 0, 0.6 }, { 0.05, 1, "quadOut" }, { 0.1, 0.2 }),
			colors = { hex("E8FFB4"), hex("B7FF3A") },
			dur = 0.1,
			pivotUp = 0.9,
		},
		{
			role = "ring",
			mesh = "Venom_Ring",
			orient = "ground",
			full = 2.6,
			scale = curve({ 0, 0.2 }, { 0.1, 1, "quadOut" }, { 0.3, 1 }),
			opacity = curve({ 0, 0 }, { 0.1, 0.45 }, { 0.3, 0 }),
			colors = { hex("55D20A"), hex("B7FF3A") },
			dur = 0.3,
		},
		{
			role = "shard",
			mesh = "Venom_Droplet",
			orient = "ground",
			count = 4,
			full = 0.3,
			scale = curve({ 0, 1 }, { 0.3, 0 }),
			colors = { hex("B7FF3A") },
			dur = 0.3,
			motion = radial(0.1, 0.9, 0.1, 0.1, 1.0, "quadOut"),
			align = "z",
		},
	},
	status = {
		bubbles = {
			mesh = "Fx_Orb",
			color = hex("B7FF3A"),
			count = 3,
			cycle = 0.3,
			rise = 1.5,
			sizes = { 0.45, 0.3, 0.2 },
		},
	},
}

Profiles.R05 = {
	core = { mesh = "Fx_Orb", aim = "orb", size = 0.6, color = hex("FFF08A"), shrink = 0.075 },
	trails = {
		{ c0 = hex("FFC400"), c1 = hex("FF9A00"), width = 0.4, length = 1.8, life = 0.15, light = 0.9 },
	},
	impact = {
		star("Fx_Star5", 1.3, hex("FFC400"), 0.05, 0.1),
		{
			role = "ring",
			mesh = "Beacon_Ring",
			orient = "ground",
			full = 3.0 / 0.992,
			scale = curve({ 0, 0.2 }, { 0.1, 0.85, "quadOut" }, { 0.3, 1 }),
			opacity = curve({ 0, 0 }, { 0.045, 1 }, { 0.3, 0, "quadOut" }),
			colors = { hex("FFC400"), hex("FF9A00"), hex("6B4A00") },
			dur = 0.3,
		},
	},
	-- One ring per real buffed neighbour (attack.SupportCells). The README link line is not built.
	neighbor = {
		role = "support",
		orient = "ground",
		mesh = "Beacon_Ring",
		full = 5.6 / 0.992,
		scale = curve({ 0, 0.536 }, { 0.1, 0.9, "quadOut" }, { 0.3, 1 }),
		opacity = curve({ 0, 0.6 }, { 0.05, 0.6 }, { 0.3, 0, "quadOut" }),
		colors = { hex("FFC400"), hex("6B4A00") },
		dur = 0.3,
	},
}

Profiles.E01 = {
	core = {
		mesh = "Emberstorm_Core",
		aim = "z",
		size = Vector3.new(0.6125, 0.6125, 0.7826),
		color = hex("FFE680"),
		spin = 1.5,
	},
	trails = {
		{ c0 = hex("FFD33A"), c1 = hex("FF4A00"), width = 0.6, length = 2.5, life = 0.25, light = 0.8 },
	},
	followers = { mesh = "Fx_Spark", count = 3, scale = 2, color = hex("FFD33A"), cycle = 0.3 },
	impact = {
		star("Fx_Star6", 3.0, { hex("FFF7A3"), hex("FFD33A") }, 0.06, 0.15),
		{
			role = "ring",
			mesh = "Emberstorm_Ring",
			orient = "ground",
			full = 4.8,
			scale = curve({ 0, 0 }, { 0.1, 0.625, "quadOut" }, { 0.3, 1, "quadOut" }),
			opacity = curve({ 0, 1 }, { 0.1, 0.5 }, { 0.3, 0 }),
			colors = { hex("FF8A00") },
			dur = 0.3,
		},
		{
			role = "shard", -- the burst: only on a confirmed detonation
			mesh = "Emberstorm_Burst",
			orient = "upright",
			full = 1,
			scale = curve({ 0, 0.3 }, { 0.1, 1, "quadOut" }, { 0.3, 0, "quadIn" }),
			scaleY = curve({ 0, 0.3 }, { 0.1, 1.1, "quadOut" }, { 0.3, 0, "quadIn" }),
			blast = true, -- scaled by the real blast radius (attack.BlastRadius / 1.75) when the server sends one
			colors = { hex("FFD33A"), hex("FF8A00") },
			dur = 0.3,
			pivotUp = 1.3364,
			spin = 1.2,
			when = "detonated",
		},
		{
			role = "shard",
			mesh = "Emberstorm_Ember",
			orient = "ground",
			count = 5,
			full = 1.5,
			scale = curve({ 0, 1 }, { 0.4, 0 }),
			colors = { hex("FF8A00") },
			dur = 0.4,
			motion = radial(0.2, 1.1, 0.2, 2.2, 0, "quadOut"),
		},
	},
}

Profiles.E02 = {
	core = { mesh = "Fx_Orb", aim = "orb", size = 0.5, color = hex("AFFFFF"), hold = 0.05 },
	trails = {
		{ c0 = hex("00FFE6"), c1 = hex("AFFFFF"), width = 0.5, length = 1.5, life = 0.15, light = 1 },
	},
	impact = {
		star("Mirror_Flash", 1, { hex("AFFFFF"), hex("00FFE6") }, 0.06, 0.15),
		{
			role = "ring",
			mesh = "Mirror_Ring",
			orient = "ground",
			full = 6.0,
			scale = curve({ 0, 0.2 }, { 0.1, 1, "quadOut" }, { 0.3, 1 }),
			opacity = curve({ 0, 0.9 }, { 0.1, 0.9 }, { 0.3, 0 }),
			colors = { hex("00BDAA") },
			dur = 0.3,
		},
		{
			role = "shard",
			mesh = "Fx_Diamond",
			orient = "ground",
			count = 2,
			full = 0.5,
			scale = curve({ 0, 1 }, { 0.2, 0 }),
			colors = { hex("E6FFFF") },
			dur = 0.2,
			motion = radial(0.3, 1.25, 0, 0.3, 0, "quadOut"),
			align = "y",
			at = "hit",
		},
		{
			role = "shard", -- shimmer along the link; only with the copy event
			mesh = "Fx_Spark",
			orient = "ground",
			count = 3,
			full = 1.2,
			scale = curve({ 0, 1 }, { 0.2, 0 }),
			colors = { hex("E6FFFF") },
			dur = 0.2,
			delay = 0.1,
			motion = function(i, _u, ctx, n)
				local shot = ctx.shot
				local along = shot.from:Lerp(shot.center, i / (n + 1))
				return along + Vector3.new(0, 0.3 + 0.15 * math.sin(i * 2.1), 0)
			end,
			when = "copied",
		},
	},
	link = { color = hex("00BDAA"), width = 0.5, curve = 0.7, draw = 0.06, dur = 0.3 },
}

Profiles.E03 = {
	core = { mesh = "Fx_Orb", aim = "orb", size = 0.7, color = hex("7A3BFF") },
	trails = {
		{ c0 = hex("C67AFF"), c1 = hex("3A0C7A"), width = 0.7, length = 3.0, life = 0.25, light = 0.8 },
	},
	impact = {
		star("Fx_Star5", 3.0, { hex("F5E8FF"), hex("C67AFF") }, 0.06, 0.1),
		{
			role = "ring",
			mesh = "Gravity_Ring",
			orient = "ground",
			full = 3.0,
			scale = curve({ 0, 0.2 }, { 0.1, 1, "quadOut" }, { 0.3, 1.2 }),
			opacity = curve({ 0, 1 }, { 0.1, 1 }, { 0.3, 0 }),
			colors = { hex("C67AFF") },
			dur = 0.3,
		},
		{
			role = "ring",
			mesh = "Gravity_Ring",
			orient = "ground",
			full = 5.0,
			scale = curve({ 0, 0.2 }, { 0.1, 1, "quadOut" }, { 0.3, 1.2 }),
			opacity = curve({ 0, 1 }, { 0.1, 1 }, { 0.3, 0 }),
			colors = { hex("7A3BFF") },
			dur = 0.3,
		},
		{
			role = "shard",
			mesh = "Fx_Diamond",
			orient = "ground",
			count = 3,
			full = 0.3,
			scale = curve({ 0, 1 }, { 0.25, 0 }),
			colors = { hex("7A3BFF") },
			dur = 0.25,
			delay = 0.05,
			motion = radial(2.6, 1.2, 0.5, 0.9, 0, "quadOut"),
			tumble = true,
		},
	},
	status = {
		vortex = { mesh = "Gravity_Vortex", color = hex("7A3BFF"), spinTurn = math.rad(720), spinEase = 0.3 },
	},
}

-- L01 Chrono: layers from Legendary/vfx/L01_layers.json, timings from the tested preview (_LM/vfx_preview/L01.luau).
-- No windup phase exists in the game, so the preview's windup Hands + 4 sparks are not built (Hands play at impact).
-- High tier: core + heart + 3 ribbons in flight; Low: core only. Hit: 12 parts (flash, rays, ring, ticks, glow, hands, 6 sparks).
Profiles.L01 = {
	core = {
		mesh = "Chrono_Core",
		aim = "nz", -- tip along -Z (travel), no FLIP
		size = Vector3.new(1, 0.866, 1.7),
		color = hex("00FFF6"),
		scale = curve({ 0, 0.6 }, { 0.06, 1, "quadOut" }),
		spin = 4,
		heart = { color = hex("E6FFFF"), scale = 0.55 }, -- same mesh, counter-spin
	},
	trails = {},
	ribbons = {
		{ mesh = "Chrono_Streak", color = hex("00C4BA"), back = 0.9, len = curve({ 0, 0.4 }, { 0.25, 1 }) },
		{
			mesh = "Chrono_StreakFlank",
			color = hex("007F7A"),
			x = -0.85,
			back = 1.2,
			len = curve({ 0, 0.4 }, { 0.25, 1 }),
		},
		{
			mesh = "Chrono_StreakFlank",
			color = hex("007F7A"),
			x = 0.85,
			back = 1.2,
			len = curve({ 0, 0.4 }, { 0.25, 1 }),
		},
	},
	impact = {
		star("Fx_Star8", 4.5, hex("E6FFFF"), 0.06, 0.1, 0.4),
		star("Fx_Star4", 8.0, hex("00FFF6"), 0.06, 0.08, 0.3, { role = "ring" }),
		{
			role = "ring",
			mesh = "Chrono_Ring",
			orient = "ground",
			full = 10.8,
			scale = curve({ 0, 1 / 3 }, { 0.3, 1, "quadOut" }),
			opacity = curve({ 0, 1 }, { 0.1, 0.23 }, { 0.3, 0.03 }),
			colors = { hex("00FFF6") },
			dur = 0.3,
		},
		{
			role = "ring",
			mesh = "Chrono_Ticks",
			orient = "ground",
			full = 10.8,
			scale = curve({ 0, 1 / 3 }, { 0.3, 1, "quadOut" }),
			opacity = curve({ 0, 1 }, { 0.1, 0.5 }, { 0.3, 0.5 }),
			colors = { hex("E6FFFF") },
			dur = 0.3,
			lift = 0.02,
		},
		{
			role = "ring",
			mesh = "Chrono_GroundGlow",
			orient = "ground",
			full = 11,
			scale = curve({ 0, 7 / 11 }, { 0.3, 1 }),
			opacity = curve({ 0, 0.55 }, { 0.3, 0 }),
			colors = { hex("00C4BA") },
			dur = 0.3,
			lift = -0.03,
		},
		{
			role = "ring",
			mesh = "Chrono_Hands",
			orient = "ground",
			full = 1,
			scale = curve({ 0, 0.3 }, { 0.07, 0.69 }, { 0.3, 0 }),
			colors = { hex("FFE9A8") },
			dur = 0.3,
			spin = 3, -- preview: 6 rad/s decaying to 1
			lift = 0.2,
		},
		{
			role = "shard",
			mesh = "Fx_Star4",
			orient = "ground",
			count = 6,
			full = 0.8,
			scale = curve({ 0, 1 }, { 0.4, 0.3 }),
			colors = { hex("E6FFFF"), hex("00FFF6") },
			alternate = true,
			dur = 0.4,
			motion = spiral(4.2, 3, 2, 0.8),
		},
	},
	-- Support aura under each buffed ally: Ring + Ticks (2 parts), diameter in studs (not scaled by the die).
	aura = {
		mesh = "Chrono_Ring",
		ticks = "Chrono_Ticks",
		color = hex("00C4BA"),
		tickColor = hex("E6FFFF"),
		diameter = 5.4,
		exit = 0.2,
	},
}

-- L02 Forge: Legendary/vfx/L02_layers.json + _LM/vfx_preview/L02.luau. The anvil and sparks stay gated on a confirmed
-- forge event (owner rule: effects only from server-confirmed events) although layers.json lists them unconditionally.
Profiles.L02 = {
	core = {
		mesh = "Forge_Core",
		aim = "nz",
		size = Vector3.new(1.5, 1, 2.2),
		color = hex("FF8A00"),
		scale = curve({ 0, 0.6 }, { 0.06, 1, "quadOut" }),
		spin = 4,
	},
	trails = {},
	ribbons = {
		{
			mesh = "Forge_Streaks",
			color = hex("FFD34D"),
			back = 1.1,
			len = curve({ 0, 1.2 / 6.5 }, { 0.25, 3.5 / 6.5 }, { 0.75, 1 }),
		},
	},
	impact = {
		star("Fx_Star8", 5.4, hex("FFF7B2"), 0.06, 0.1, 1.8 / 5.4),
		star("Fx_Star6", 5.9, hex("FFD34D"), 0.075, 0.1, 0.33, { role = "ring", delay = 0.015 }),
		{
			role = "ring",
			mesh = "Forge_Ring",
			orient = "ground",
			full = 12,
			scale = curve({ 0, 0.5 }, { 0.1, 0.9, "quadOut" }, { 0.3, 1 }),
			opacity = curve({ 0, 1 }, { 0.1, 0.6 }, { 0.3, 0.1 }),
			colors = { hex("FF8A00") },
			dur = 0.3,
		},
		{
			role = "ring",
			mesh = "Forge_RingRim",
			orient = "ground",
			full = 12,
			scale = curve({ 0, 0.5 }, { 0.1, 0.9, "quadOut" }, { 0.3, 1 }),
			opacity = curve({ 0, 1 }, { 0.1, 0.6 }, { 0.3, 0.1 }),
			colors = { hex("FFD34D") },
			dur = 0.3,
			lift = 0.01,
		},
		{
			role = "ring",
			mesh = "Forge_GroundGlow",
			orient = "ground",
			full = 10,
			scale = curve({ 0, 0.7 }, { 0.1, 0.9, "quadOut" }, { 0.3, 1 }),
			opacity = curve({ 0, 0.65 }, { 0.1, 0.45 }, { 0.3, 0 }),
			colors = { hex("FF8A00") },
			dur = 0.3,
			lift = -0.03,
		},
		{
			role = "support", -- the anvil: only with a confirmed forge event (attack.TransformedCell)
			mesh = "Forge_Anvil",
			orient = "upright",
			full = 1,
			scale = curve({ 0, 0.35 }, { 0.06, 1 }, { 0.1, 1.31 }, { 0.3, 0.55 }),
			opacity = curve({ 0, 0.6 }, { 0.1, 1 }, { 0.3, 0.13 }),
			colors = { hex("FFF7B2"), hex("FFD34D"), hex("FF8A00") },
			dur = 0.3,
			pivotUp = 1.05,
			when = "forged",
		},
		{
			role = "support",
			mesh = "Fx_Spark",
			orient = "ground",
			count = 6,
			full = 12,
			scale = curve({ 0, 1 }, { 0.25, 0.6 }, { 0.35, 0 }),
			opacity = curve({ 0, 1 }, { 0.15, 0.5 }, { 0.35, 0 }),
			colors = { hex("FFD34D"), hex("FF8A00") },
			alternate = true,
			dur = 0.35,
			motion = ballistic(22, 0.35, 2.3),
			align = "y",
			when = "forged",
		},
	},
}

-- M01 Astral: Mythic/vfx/M01_layers.json + _LM/vfx_preview/M01.luau. Differences: the windup DieSparkle has no hook
-- (dropped); 6 orbit sparks instead of 7 to keep the hit at 12 parts; Low tier keeps the comet (no per-tier core mesh).
Profiles.M01 = {
	core = {
		mesh = "Astral_Comet",
		aim = "z", -- head at mesh +Z: the FLIP branch
		size = Vector3.new(1.8, 1.8, 4.94),
		color = Color3.new(1, 1, 1),
		scale = curve({ 0, 0.5 }, { 0.06, 1 }),
		twinkle = 0.1,
	},
	trails = {
		{
			c0 = hex("B967FF"),
			c1 = hex("5E6BFF"),
			width = 1.2,
			length = 5.2,
			life = 0.3,
			light = 0.8,
			transparency = 0.2,
		},
	},
	impact = {
		star("Fx_Star8", 4.0, Color3.new(1, 1, 1), 0.03, 0.05, 0.4, {
			opacity = curve({ 0, 0.95 }, { 0.015, 0.45 }, { 0.025, 0.2 }, { 0.046, 0 }),
			critical = 1.22,
		}),
		{
			role = "ring",
			mesh = "Astral_Ring",
			orient = "ground",
			full = 10.8,
			scale = curve({ 0, 0.97 / 1.8 }, { 0.1, 1.52 / 1.8, "quadOut" }, { 0.3, 1 }),
			opacity = curve({ 0, 0.15 }, { 0.015, 0.55 }, { 0.04, 0.7 }, { 0.1, 0.53 }, { 0.3, 0.1 }),
			colors = { hex("B967FF") },
			dur = 0.3,
		},
		{
			role = "ring", -- rim: same mesh, X/Z x1.04, Y x1.25
			mesh = "Astral_Ring",
			orient = "ground",
			full = Vector3.new(10.8 * 1.04, 10.8 * 1.25, 10.8 * 1.04),
			scale = curve({ 0, 0.97 / 1.8 }, { 0.1, 1.52 / 1.8, "quadOut" }, { 0.3, 1 }),
			opacity = curve({ 0, 0.15 }, { 0.015, 0.55 }, { 0.04, 0.7 }, { 0.1, 0.53 }, { 0.3, 0.1 }),
			colors = { hex("F7B6FF") },
			dur = 0.3,
			lift = 0.01,
		},
		{
			role = "ring",
			mesh = "Astral_GroundGlow",
			orient = "ground",
			full = 8,
			scale = curve({ 0, 0.75 }, { 0.1, 0.915, "quadOut" }, { 0.3, 1 }),
			opacity = curve({ 0, 0.6 }, { 0.1, 0.45 }, { 0.3, 0.05 }),
			colors = { hex("B967FF") },
			dur = 0.3,
			lift = -0.03,
		},
		{
			role = "support", -- billboard to the camera; shrinks instead of fading
			mesh = "Astral_Constellation",
			orient = "yaw",
			full = 1,
			scale = curve({ 0, 0 }, { 0.06, 0 }, { 0.06, 0.7 }, { 0.16, 1, "quadOut" }, { 0.3, 0 }),
			colors = { hex("82E9FF") },
			dur = 0.3,
			pivotUp = 1.2,
		},
		{
			role = "support", -- dropped first when the pool is at its cap
			mesh = "Astral_RayCrown",
			orient = "upright",
			full = 1,
			scale = curve({ 0, 1 }, { 0.3, 1 }, { 0.4, 0 }),
			scaleY = curve({ 0, 0 }, { 0.06, 0 }, { 0.3, 1, "quadOut" }, { 0.4, 0 }),
			colors = { hex("B967FF") },
			dur = 0.4,
			pivotUp = 3.0,
		},
		{
			role = "shard",
			mesh = "Fx_Star4",
			orient = "ground",
			count = 6,
			full = 0.7,
			scale = curve({ 0, 0 }, { 0.06, 1, "quadOut" }, { 0.3, 0 }),
			colors = { Color3.new(1, 1, 1), hex("F7B6FF") },
			alternate = true,
			dur = 0.3,
			motion = spiral(3.5, 2.5, 1, 0.5),
		},
	},
	supportLoad = 0.75, -- constellation / ray crown only borrow while Fx.Live() is under this share of the cap
}

RarityStyles.Profiles = Profiles
RarityStyles.curve = curve

-- name / shape / main / streak / ring / accent / flash colours keep the old style table's public shape.
local function style(
	profile: string,
	name: string,
	shape: string,
	color: string,
	streak: string,
	ring: string,
	accent: string,
	flash: string
)
	return {
		name = name,
		detail = shape,
		color = hex(color),
		streak = hex(streak),
		glow = hex(ring),
		accent = hex(accent),
		burstColor = hex(flash),
		profile = Profiles[profile],
		pool = {},
		speed = ProjectileFlight.DefaultSpeed,
		size = 0.19,
	}
end

RarityStyles.Styles = {
	R01 = style("R01", "Frost", "Crystal", "7FEFFF", "00D9FF", "00D9FF", "0A6FBF", "EFFFFF"),
	R02 = style("R02", "Arc", "Orb", "D77BFF", "D77BFF", "9A40FF", "4A0FB9", "F8E6FF"),
	R03 = style("R03", "Volley", "Bolt", "FF7A7A", "FF3B3B", "FF3B3B", "B7192A", "FFF6F6"),
	R04 = style("R04", "Venom", "Orb", "55D20A", "B7FF3A", "55D20A", "2B6E00", "E8FFB4"),
	R05 = style("R05", "Beacon", "Orb", "FFC400", "FF9A00", "FFC400", "6B4A00", "FFF08A"),
	E01 = style("E01", "Emberstorm", "Ember", "FFD33A", "FF8A00", "FF8A00", "FF4A00", "FFF7A3"),
	E02 = style("E02", "Mirror", "Orb", "00FFE6", "E6FFFF", "00BDAA", "007D75", "AFFFFF"),
	E03 = style("E03", "Gravity", "Orb", "7A3BFF", "C67AFF", "C67AFF", "3A0C7A", "F5E8FF"),
	L01 = style("L01", "Chrono", "Diamond", "00FFF6", "00C4BD", "00C4BD", "007F7A", "E6FFFF"),
	L02 = style("L02", "Forge", "Diamond", "FFD34D", "FF8A00", "FF8A00", "C24B00", "FFF7B2"),
	M01 = style("M01", "Astral", "Star", "F7B6FF", "5E6BFF", "B967FF", "1B0D4A", "FFFFFF"),
}

return RarityStyles
