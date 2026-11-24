--!strict
-- 3D route portals (rulings R9, Assets/Models/Dice/_vfx/portal): pooled MeshParts driven by one Fx.Run loop per
-- portal. Rim static, three vortex layers spin, Core scale pulse, Glow pulse (the only fading part). Neon only
-- on Core and Glow. Palette is keyed by ROLE ("spawn" = route start, "exit" = route end, "summon" = the Goblin King
-- portal: same structure in deep blue-gray, grown in and out by setScale).
-- Mesh parts load asynchronously (Fx.Warm), so missing layers are borrowed lazily from the update loop.

local Fx = require(script.Parent.FxLib)

local PortalFx = {}

export type Role = "spawn" | "exit" | "summon"
export type Portal = { destroy: () -> (), setScale: (scale: number) -> () }

type Layer = {
	mesh: string,
	offset: number, -- studs forward along the normal (negative = behind the face)
	size: Vector3?, -- overrides the mesh's native size (flattened backing disc)
	spin: number, -- deg/s, 0 = static
	neon: boolean,
	colors: { spawn: Color3, exit: Color3, summon: Color3 },
}

local function hex(s: string): Color3
	return Color3.fromHex(s)
end

local LAYERS: { Layer } = {
	{
		mesh = "Portal_Rim",
		offset = 0,
		spin = 0,
		neon = false,
		colors = { spawn = hex("#4a4256"), exit = hex("#4a2a2e"), summon = hex("#3d4a5c") },
	},
	{
		mesh = "Portal_VortexOuter",
		offset = 0,
		spin = 40,
		neon = false,
		colors = { spawn = hex("#3a3048"), exit = hex("#3a1e24"), summon = hex("#2c3544") },
	},
	{
		mesh = "Portal_VortexMid",
		offset = 0.06,
		spin = 70,
		neon = false,
		colors = { spawn = hex("#6a5a82"), exit = hex("#7a2f3a"), summon = hex("#4f5f76") },
	},
	{
		mesh = "Portal_VortexInner",
		offset = 0.12,
		spin = 110,
		neon = false,
		colors = { spawn = hex("#8a74ac"), exit = hex("#a04050"), summon = hex("#6b7f99") },
	},
	{
		mesh = "Portal_Core",
		offset = 0.17,
		spin = 0,
		neon = true,
		colors = { spawn = hex("#b9a2e8"), exit = hex("#d9606e"), summon = hex("#a9bdd6") },
	},
	{
		-- Dark opaque backing so the ground never shows through the vortex blade gaps (flattened Fx_Orb, ~2.95 studs).
		mesh = "Fx_Orb",
		offset = -0.06,
		size = Vector3.new(2.95, 2.95, 0.05),
		spin = 0,
		neon = false,
		colors = { spawn = hex("#241d30"), exit = hex("#241216"), summon = hex("#1c2330") },
	},
	{
		mesh = "Portal_Glow",
		offset = 0,
		spin = 0,
		neon = true,
		colors = { spawn = hex("#7a62b0"), exit = hex("#b0404e"), summon = hex("#6b7f99") },
	},
}
local CORE = 5
local BACKING = 6
local GLOW = 7
local LEAN = math.rad(65) -- elevation of the face normal above the horizon (disc plane 25 deg from horizontal)

local PERIOD = { spawn = 1.6, exit = 2.2, summon = 1.6 }
-- Spin sign -1 about Z yields counter-clockwise seen from the front for the spawn portal. layers.json says +1 is
-- CCW, but the Luau CFrame.Angles convention differs; do not "fix" this.
local SPIN_SIGN = { spawn = -1, exit = 1, summon = -1 }
local CORE_SCALE = { spawn = 1, exit = 1.2, summon = 1 } -- exit core is 0.6 vs 0.5 studs
local REDUCED_CORE_PERIOD = 3

-- position: portal centre; cameraPos: the board camera. The face looks toward the camera but is leaned back to a
-- fixed elevation (LEAN) so the vortex reads from the top-down view instead of edge-on.
function PortalFx.Spawn(
	parent: Instance,
	position: Vector3,
	cameraPos: Vector3,
	role: Role,
	reducedMotion: () -> boolean
): Portal
	local parts: { MeshPart? } = {}
	local missing = #LAYERS
	local startClock = os.clock()
	local done = false
	local grow = 1 -- overall scale (the summon portal opens and closes with it)
	local handle: Fx.Handle? = nil
	local toCam = cameraPos - position
	local flat = Vector3.new(toCam.X, 0, toCam.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local normal = flat * math.cos(LEAN) + Vector3.yAxis * math.sin(LEAN)
	local base = CFrame.lookAt(position, position + normal)

	local function place(index: number, spinRad: number, scale: number, transparency: number?)
		local part = parts[index]
		if part == nil then
			return
		end
		local layer = LAYERS[index]
		local cf = base * CFrame.new(0, 0, -layer.offset) * CFrame.Angles(0, 0, spinRad * SPIN_SIGN[role])
		part.CFrame = cf
		part.Size = (layer.size or Fx.Meshes[layer.mesh].Size) * scale * grow
		if transparency then
			part.Transparency = transparency
		end
	end

	local function acquire()
		for i, layer in LAYERS do
			if parts[i] == nil then
				local part = Fx.Part(layer.mesh, {
					Color = layer.colors[role],
					Material = if layer.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
					Transparency = if i == GLOW then 0.6 else 0,
					CFrame = base,
				})
				if part then
					parts[i] = part
					part.Parent = parent
					missing -= 1
				end
			end
		end
	end

	local function frame(t: number, still: boolean)
		local period = PERIOD[role]
		for i, layer in LAYERS do
			if layer.spin ~= 0 then
				place(i, if still then 0 else math.rad(layer.spin) * t, 1, nil)
			end
		end
		place(1, 0, 1, nil)
		place(BACKING, 0, 1, nil)
		-- Core: smooth 1 -> 1.25 pulse (slow 3 s in reduced motion).
		local corePeriod = if still then REDUCED_CORE_PERIOD else period
		local s = 0.5 - 0.5 * math.cos(2 * math.pi * t / corePeriod)
		place(CORE, 0, CORE_SCALE[role] * (1 + 0.25 * s), nil)
		-- Glow: spawn pulses outward (ease-out), exit inward (ease-in); fades 0.5 <-> 0.75.
		if still then
			place(GLOW, 0, 1.025, 0.62)
		else
			local u = (t / period) % 1
			if role ~= "exit" then
				local e = 1 - (1 - u) * (1 - u)
				place(GLOW, 0, 0.95 + 0.15 * e, 0.5 + 0.25 * u)
			else
				place(GLOW, 0, 1.1 - 0.15 * u * u, 0.75 - 0.25 * u)
			end
		end
	end

	local function release()
		if done then
			return
		end
		done = true
		for i, part in parts do
			Fx.Release(part)
			parts[i] = nil
		end
	end

	acquire()
	frame(0, reducedMotion())
	handle = Fx.Run(function(_dt: number): boolean
		if done then
			return true
		end
		if missing > 0 then
			acquire()
		end
		frame(os.clock() - startClock, reducedMotion())
		return false
	end, release)
	-- Fx.Run returns nil at the global cap: the portal stays as a static prop.

	return {
		setScale = function(scale: number)
			grow = scale
			if not done then
				frame(os.clock() - startClock, reducedMotion())
			end
		end,
		destroy = function()
			if handle then
				handle.cancel() -- runs release()
			end
			release()
		end,
	}
end

return PortalFx
