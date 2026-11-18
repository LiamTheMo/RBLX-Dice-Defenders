local Projectiles = {}

local MAX_SHOTS = 40
local SIZE_SCALE = 3.5 -- Common attack VFX at the gameplay camera distance.
local DOT_COLOR = Color3.fromRGB(190, 190, 190)
local FLASH_COLOR = Color3.fromRGB(222, 222, 222)
local RING_ROTATION = CFrame.Angles(0, math.pi / 2, 0)
local FADE_SECONDS = 0.30
local pools = { C01 = {}, C02 = {} }

-- Elapsed seconds, diameter in studs, and opacity from the Blender impact keys.
local RING = {
	{ 0, 0.26, 1 },
	{ 0.05, 0.48, 0.86 },
	{ 0.10, 0.62, 0.58 },
	{ 0.20, 0.72, 0.24 },
	{ FADE_SECONDS, 0.75, 0 },
}

local function stopTrail(shot)
	if shot.trail then
		shot.trail.Enabled = false
		shot.trail:Clear()
	end
end

local function release(shot)
	stopTrail(shot)
	shot.dot.Parent = nil
	shot.effect.Parent = nil
	shot.target = nil
	shot.parent = nil
end

local function borrow(dieType: string)
	local shots = pools[dieType]
	for _, shot in shots do
		if shot.parent == nil then
			return shot
		end
	end
	if #shots >= MAX_SHOTS then
		return nil
	end
	local needle = dieType == "C02"
	local dot = Instance.new("Part")
	dot.Name = if needle then "NeedleProjectile" else "PebbleProjectile"
	dot.Shape = Enum.PartType.Ball
	dot.Material = if needle then Enum.Material.Neon else Enum.Material.SmoothPlastic
	dot.Anchored = true
	dot.CastShadow = false
	dot.CanCollide = false
	dot.CanQuery = false
	dot.CanTouch = false
	local template = if needle then script.Parent.NeedleFlash else script.Parent.PebbleRing
	local shot = { dot = dot, effect = template:Clone(), needle = needle }
	shot.effect.Size *= SIZE_SCALE
	shot.impactRadius = math.max(template.Size.X, template.Size.Y, template.Size.Z) * SIZE_SCALE / 2
	if needle then
		local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
		local halfWidth = Vector3.yAxis * (0.057 * SIZE_SCALE)
		top.Position, bottom.Position = halfWidth, -halfWidth
		top.Parent, bottom.Parent = dot, dot
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = top, bottom
		trail.FaceCamera = true
		trail.Lifetime = 0.075
		trail.MaxLength = 1.5 * SIZE_SCALE
		trail.LightEmission = 0.25
		trail.Color = ColorSequence.new(Color3.fromRGB(191, 191, 191))
		trail.Transparency = NumberSequence.new(0.38, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Enabled = false
		trail.Parent = dot
		shot.trail = trail
	else
		shot.effect.Color = DOT_COLOR
	end
	table.insert(shots, shot)
	return shot
end

function Projectiles.Fire(
	parent: Folder,
	from: Vector3,
	center: Vector3,
	target: BasePart,
	attack,
	reducedMotion: boolean
)
	local shot = borrow(attack.Type)
	if shot == nil then
		return
	end
	shot.parent, shot.target = parent, target
	shot.from, shot.center = from, center
	shot.halfSize = target.Size.X / 2
	shot.reducedMotion = reducedMotion
	shot.flight = if reducedMotion then 0 else (center - from).Magnitude / (if shot.needle then 170 else 140)
	shot.elapsed = 0
	shot.impact = nil
	shot.dot.Transparency = 0
	if shot.needle then
		shot.effect.Color = if attack.Boosted and not reducedMotion
			then Color3.new(1, 1, 1)
			else Color3.fromRGB(217, 217, 230)
		shot.strength = if reducedMotion then 0.42 elseif attack.Boosted then 1 else 0.80
	end
	if not reducedMotion then
		shot.dot.Color = if shot.needle then Color3.fromRGB(217, 217, 230) else DOT_COLOR
		shot.dot.Size = Vector3.one * SIZE_SCALE * (if shot.needle then 0.18 else 0.22)
		shot.dot.Position = from
		shot.dot.Parent = parent
		if shot.trail then
			shot.trail.Enabled = true
		end
	end
end

local function pebbleImpact(shot, age: number, facing: CFrame)
	if not shot.reducedMotion and age < RING[2][1] then
		local fade = age / RING[2][1]
		shot.dot.Position = shot.impact
		shot.dot.Size = Vector3.one * SIZE_SCALE * (0.25 - 0.15 * fade)
		shot.dot.Color = FLASH_COLOR
		shot.dot.Transparency = fade
	else
		shot.dot.Parent = nil
	end
	for i = 2, #RING do
		local right = RING[i]
		if age < right[1] then
			local left = RING[i - 1]
			local t = (age - left[1]) / (right[1] - left[1])
			local diameter = if shot.reducedMotion then 0.48 else left[2] + (right[2] - left[2]) * t
			local opacity = left[3] + (right[3] - left[3]) * t
			shot.effect.Size = Vector3.new(0.06, diameter, diameter) * SIZE_SCALE
			shot.effect.Transparency = 1 - opacity * (if shot.reducedMotion then 0.65 else 1)
			shot.effect.CFrame = facing * RING_ROTATION
			break
		end
	end
end

local function advance(shot, dt: number, cameraPosition: Vector3)
	shot.elapsed += dt
	if shot.impact == nil then
		if shot.target.Parent then
			shot.center = shot.target.Position
		end
		-- Anchor to the camera-facing surface so the impact stays visible.
		local view = (cameraPosition - shot.center).Unit
		local axis = math.max(math.abs(view.X), math.abs(view.Y), math.abs(view.Z))
		-- Keep the full camera-facing impact above the struck face, including on oblique hits.
		local offset = 0.10 + shot.impactRadius * math.sqrt(math.max(0, 1 - axis * axis)) / axis
		local surface = shot.center + view * (shot.halfSize / axis + offset)
		if shot.elapsed < shot.flight then
			shot.dot.Position = shot.from:Lerp(surface, shot.elapsed / shot.flight)
			return
		end
		shot.impact = surface
		if shot.needle then
			stopTrail(shot)
			shot.dot.Parent = nil
		end
	end

	local age = shot.elapsed - shot.flight
	if age >= FADE_SECONDS then
		release(shot)
		return
	end
	local facing = CFrame.lookAt(shot.impact, cameraPosition)
	if shot.needle then
		local t = 1 - age / FADE_SECONDS
		shot.effect.Transparency = 1 - shot.strength * t * (0.5 + 0.5 * t)
		shot.effect:PivotTo(facing)
	else
		pebbleImpact(shot, age, facing)
	end
	shot.effect.Parent = shot.parent
end

function Projectiles.Step(dt: number)
	local camera = workspace.CurrentCamera
	if camera then
		for _, shots in pools do
			for _, shot in shots do
				if shot.parent then
					advance(shot, dt, camera.CFrame.Position)
				end
			end
		end
	end
end

function Projectiles.Clear()
	for _, shots in pools do
		for _, shot in shots do
			release(shot)
		end
	end
end

return Projectiles
