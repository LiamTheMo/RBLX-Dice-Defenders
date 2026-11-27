--!strict
-- Layer tables for the seven Common dice (C01-C07), transcribed from Assets/Models/Dice/Common/vfx/C0N_layers.json.
-- Sizes are for a 5-stud die; Projectiles multiplies them by Fx.Scale(dieSize). Times are seconds from the hit.
-- Mesh keys are FxMeshes keys. `uniform` layers (orbs) set Size = one * size; the rest multiply the mesh's authored
-- Size by `size` (rings: final diameter, stars/flashes: scale factor).

local Fx = require(script.Parent.FxLib)

local E = Fx.Easing

export type Orient = "camera" | "ground" | "fanBack" | "fanFwd"

export type Core = {
	mesh: string,
	color: Color3,
	material: Enum.Material,
	uniform: boolean?,
	size: number,
	layer: string, -- tier layer: "projectile" | "support"
	fadeIn: number?, -- start transparency, ramps to 0 over the first quarter of the flight
}

export type TrailDef = {
	color: Color3,
	width: number,
	lifetime: number,
	length: number?, -- MaxLength in studs at D=5
	emission: number,
	transparency: number,
	from: number, -- fraction of the flight where the trail turns on
}

export type Hit = {
	mesh: string,
	color: Color3,
	material: Enum.Material,
	uniform: boolean?,
	size: number,
	layer: string, -- "flash" | "ring" | "support"
	orient: Orient,
	boost: number?, -- size multiplier when the hit record carries Boosted (server flag)
	sizeKeys: { Fx.Key },
	transKeys: { Fx.Key },
	dur: number, -- last transparency key: the part is released then
}

export type Style = {
	name: string,
	speed: number,
	cores: { Core },
	trail: TrailDef?,
	hits: { Hit },
	duration: number,
	limiter: Fx.Limiter,
}

local MAX_SHOTS = 40

local function key(t: number, v: number, ease: Fx.Easing?): Fx.Key
	return { t = t, v = v, ease = ease }
end

local function hit(def: {
	mesh: string,
	color: string,
	material: Enum.Material?,
	uniform: boolean?,
	size: number,
	layer: string,
	orient: Orient,
	boost: number?,
	sizeKeys: { Fx.Key },
	transKeys: { Fx.Key },
}): Hit
	return {
		mesh = def.mesh,
		color = Color3.fromHex(def.color),
		material = def.material or Enum.Material.Neon,
		uniform = def.uniform,
		size = def.size,
		layer = def.layer,
		orient = def.orient,
		boost = def.boost,
		sizeKeys = def.sizeKeys,
		transKeys = def.transKeys,
		dur = def.transKeys[#def.transKeys].t,
	}
end

local function core(mesh: string, hex: string, size: number, opts: { [string]: any }?): Core
	local o = opts or {}
	return {
		mesh = mesh,
		color = Color3.fromHex(hex),
		material = o.material or Enum.Material.Neon,
		uniform = o.uniform,
		size = size,
		layer = o.layer or "projectile",
		fadeIn = o.fadeIn,
	}
end

local function style(name: string, speed: number, cores: { Core }, trail: TrailDef?, hits: { Hit }): Style
	local duration = 0
	for _, h in hits do
		duration = math.max(duration, h.dur)
	end
	return {
		name = name,
		speed = speed,
		cores = cores,
		trail = trail,
		hits = hits,
		duration = duration,
		limiter = Fx.Limiter(MAX_SHOTS),
	}
end

local function trail(
	hex: string,
	width: number,
	lifetime: number,
	length: number?,
	emission: number,
	transparency: number,
	from: number
): TrailDef
	return {
		color = Color3.fromHex(hex),
		width = width,
		lifetime = lifetime,
		length = length,
		emission = emission,
		transparency = transparency,
		from = from,
	}
end

local ORB = "Fx_Orb"
local PLASTIC = Enum.Material.SmoothPlastic

-- Burst hump shared by the Hammer and Spark flashes.
local function hump(peak: number, peakAt: number, endAt: number): { Fx.Key }
	return { key(0, 0), key(peakAt, peak), key(endAt, 0) }
end

local Styles: { [string]: Style } = {
	-- C01: matte pebble, no trail; flash and a ground ring.
	C01 = style("Pebble", 140, { core(ORB, "#BEBEBE", 1.2, { uniform = true, material = PLASTIC }) }, nil, {
		hit({
			mesh = ORB,
			color = "#D9D9D9",
			uniform = true,
			size = 1.2,
			layer = "flash",
			orient = "camera",
			sizeKeys = { key(0, 1), key(0.06, 1.3) },
			transKeys = { key(0, 0), key(0.06, 1) },
		}),
		hit({
			mesh = "Fx_Ring",
			color = "#8F8F8F",
			material = PLASTIC,
			size = 4.2,
			layer = "ring",
			orient = "ground",
			sizeKeys = { key(0, 0.2), key(0.1, 1, E.quadOut), key(0.3, 1) },
			transKeys = { key(0, 0), key(0.1, 0.65), key(0.3, 1, E.quadOut) },
		}),
	}),
	-- C02: silver dot, trail from 25% of the flight, 4-point sparkle (x1.25 on the sixth-hit flag), no ring.
	C02 = style(
		"Needle",
		170,
		{ core(ORB, "#FFFFFF", 1.1, { uniform = true }) },
		trail("#BFBFBF", 1.1, 0.13, 7, 0.6, 0.6, 0.25),
		{
			hit({
				mesh = "Needle_Flash",
				color = "#FFFFFF",
				size = 1,
				layer = "flash",
				orient = "camera",
				boost = 1.25,
				sizeKeys = { key(0, 0.8), key(0.06, 1, E.quadOut), key(0.3, 1) },
				transKeys = { key(0, 0), key(0.1, 0), key(0.3, 1, E.quadOut) },
			}),
		}
	),
	-- C03: amber hammer, long trail, 3-spike burst fanning forward, pale hub; no ring.
	C03 = style(
		"Hammer",
		145,
		{ core(ORB, "#FFC34D", 1.3, { uniform = true }) },
		trail("#FFD079", 1.3, 0.12, 5.5, 0.8, 0.65, 0),
		{
			hit({
				mesh = "Hammer_FlashSpikes",
				color = "#FFC34D",
				size = 1,
				layer = "flash",
				orient = "fanBack",
				sizeKeys = hump(1.1, 0.08, 0.3),
				transKeys = { key(0, 0), key(0.1, 0.7), key(0.3, 1, E.quadOut) },
			}),
			hit({
				mesh = ORB,
				color = "#FFE9B0",
				uniform = true,
				size = 0.7,
				layer = "support",
				orient = "camera",
				sizeKeys = hump(1.1, 0.08, 0.3),
				transKeys = { key(0, 0), key(0.1, 0.7), key(0.3, 1, E.quadOut) },
			}),
		}
	),
	-- C04: one ivory core per shot record (the server sends two, Lane +-1), short trail, 3-prong flash.
	C04 = style(
		"Twinshot",
		155,
		{ core(ORB, "#FFF8E8", 0.45, { uniform = true, fadeIn = 0.4 }) },
		trail("#FFF8E8", 0.35, 0.12, 1, 0.5, 0.5, 0),
		{
			hit({
				mesh = "Twinshot_Flash",
				color = "#FFF8E8",
				size = 1,
				layer = "flash",
				orient = "fanFwd",
				sizeKeys = { key(0, 0.6), key(0.1, 1, E.quadOut), key(0.3, 0.8) },
				transKeys = { key(0, 0), key(0.3, 1) },
			}),
		}
	),
	-- C05: small green orb with a white core, no trail; round flash and a thin ground ring.
	C05 = style(
		"Longshot",
		165,
		{
			core(ORB, "#66FF33", 0.5, { uniform = true }),
			core(ORB, "#FFFFFF", 0.25, { uniform = true, layer = "support" }),
		},
		nil,
		{
			hit({
				mesh = ORB,
				color = "#66FF33",
				uniform = true,
				size = 1,
				layer = "flash",
				orient = "camera",
				sizeKeys = { key(0, 1), key(0.1, 1.6) },
				transKeys = { key(0, 0), key(0.1, 1, E.quadOut) },
			}),
			hit({
				mesh = "Fx_Ring",
				color = "#66FF33",
				size = 2.4,
				layer = "ring",
				orient = "ground",
				sizeKeys = { key(0, 0.5), key(0.3, 1, E.quadOut) },
				transKeys = { key(0, 0), key(0.3, 1) },
			}),
		}
	),
	-- C06: cyan orb with a trail, 4-point flash; the slow ring lives in Projectiles' marker code.
	C06 = style(
		"Chill",
		150,
		{
			core(ORB, "#6CE0FF", 0.5, { uniform = true }),
			core(ORB, "#E8FFFF", 0.25, { uniform = true, layer = "support" }),
		},
		trail("#6CE0FF", 0.4, 0.15, 3.5, 0.8, 0.4, 0),
		{
			hit({
				mesh = "Fx_Star4",
				color = "#E8FFFF",
				size = 1,
				layer = "flash",
				orient = "camera",
				sizeKeys = { key(0, 0.5), key(0.06, 1.1), key(0.1, 0.8) },
				transKeys = { key(0, 0), key(0.05, 0.75), key(0.1, 1) },
			}),
		}
	),
	-- C07: yellow icosphere, no trail (sheet default off); 8-point flash + white hub (x1.4) and a ground ring (x1.15).
	C07 = style("Spark", 160, { core("Spark_Core", "#FFF066", 0.5, { uniform = true }) }, nil, {
		hit({
			mesh = "Fx_Star8",
			color = "#FFF066",
			size = 1,
			layer = "flash",
			orient = "camera",
			boost = 1.4,
			sizeKeys = hump(1, 0.045, 0.3),
			transKeys = { key(0, 0), key(0.1, 1, E.quadOut) },
		}),
		hit({
			mesh = "Spark_Core",
			color = "#FFFFFF",
			size = 0.7,
			layer = "support",
			orient = "camera",
			boost = 1.4,
			sizeKeys = hump(1, 0.045, 0.3),
			transKeys = { key(0, 0), key(0.1, 1, E.quadOut) },
		}),
		hit({
			mesh = "Fx_Ring",
			color = "#FFD700",
			size = 1.6,
			layer = "ring",
			orient = "ground",
			boost = 1.15,
			sizeKeys = { key(0, 0.2), key(0.1, 1, E.quadOut), key(0.3, 1) },
			transKeys = { key(0, 0.4), key(0.3, 1, E.quadOut) },
		}),
	}),
}

return Styles
