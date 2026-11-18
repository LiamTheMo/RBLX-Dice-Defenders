local Projectiles = {}

local MAX_SHOTS = 40
local SIZE_SCALE = 3.5 -- Common attack VFX at the gameplay camera distance.
local DOT_COLOR = Color3.fromRGB(190, 190, 190)
local FLASH_COLOR = Color3.fromRGB(222, 222, 222)
local RING_ROTATION = CFrame.Angles(0, math.pi / 2, 0)
local FADE_SECONDS = 0.30
local TWINSHOT_GLINT_SECONDS = 0.04
local SILVER = Color3.fromRGB(217, 217, 230)
local IVORY = Color3.fromRGB(255, 248, 232)
local styles = {
	C01 = { name = "Pebble", effect = script.Parent.PebbleRing, color = DOT_COLOR, speed = 140, size = 0.22, pool = {} },
	C02 = {
		name = "Needle",
		effect = script.Parent.NeedleFlash,
		color = SILVER,
		speed = 170,
		size = 0.18,
		pool = {},
		streak = Color3.fromRGB(191, 191, 191),
	},
	C04 = {
		name = "Twinshot",
		effect = script.Parent.TwinshotFlash,
		color = IVORY,
		speed = 155,
		size = 0.20,
		pool = {},
		streak = IVORY,
		shortStreak = true,
	},
}

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

local function borrow(style)
	local shots = style.pool
	for _, shot in shots do
		if shot.parent == nil then
			return shot
		end
	end
	if #shots >= MAX_SHOTS then
		return nil
	end
	local dot = Instance.new("Part")
	dot.Name = style.name .. "Projectile"
	dot.Shape = Enum.PartType.Ball
	dot.Material = if style.streak then Enum.Material.Neon else Enum.Material.SmoothPlastic
	dot.Anchored = true
	dot.CastShadow = false
	dot.CanCollide = false
	dot.CanQuery = false
	dot.CanTouch = false
	local template = style.effect
	local shot = { dot = dot, effect = template:Clone() }
	shot.effect.Size *= SIZE_SCALE
	local pivot = template.PivotOffset
	shot.effect.PivotOffset = pivot.Rotation + pivot.Position * SIZE_SCALE
	shot.impactRadius = (math.max(template.Size.X, template.Size.Y, template.Size.Z) / 2 + pivot.Position.Magnitude)
		* SIZE_SCALE
	if style.streak then
		local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
		local halfWidth = Vector3.yAxis * SIZE_SCALE * (if style.shortStreak then 0.035 else 0.057)
		top.Position, bottom.Position = halfWidth, -halfWidth
		top.Parent, bottom.Parent = dot, dot
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = top, bottom
		trail.FaceCamera = true
		trail.Lifetime = if style.shortStreak then 0.045 else 0.075
		trail.MaxLength = (if style.shortStreak then 0.72 else 1.5) * SIZE_SCALE
		trail.LightEmission = if style.shortStreak then 0.10 else 0.25
		trail.Color = ColorSequence.new(style.streak)
		trail.Transparency = if style.shortStreak
			then NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.52),
				NumberSequenceKeypoint.new(0.5, 1),
				NumberSequenceKeypoint.new(1, 1),
			})
			else NumberSequence.new(0.38, 1)
		trail.WidthScale = if style.shortStreak
			then NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 0),
			})
			else NumberSequence.new(1, 0)
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
	local style = styles[attack.Type]
	local shot = borrow(style)
	if shot == nil then
		return
	end
	shot.parent, shot.target = parent, target
	shot.from, shot.center = from, center
	shot.halfSize = target.Size.X / 2
	shot.reducedMotion = reducedMotion
	shot.flight = if reducedMotion then 0 else (center - from).Magnitude / style.speed
	shot.elapsed = 0
	shot.impact = nil
	local camera = workspace.CurrentCamera
	local up = if camera then camera.CFrame.UpVector else Vector3.yAxis
	local lane = up * ((attack.Lane or 0) * 0.22 * SIZE_SCALE)
	shot.from += lane
	shot.hitOffset = if attack.SharedTarget then lane else Vector3.zero
	shot.twinshot = attack.Type == "C04"
	shot.dot.Transparency = if shot.twinshot then 0.12 else 0
	if attack.Type == "C02" then
		shot.effect.Color = if attack.Boosted and not reducedMotion then Color3.new(1, 1, 1) else SILVER
	end
	shot.strength = if reducedMotion then 0.42 elseif attack.Boosted then 1 else 0.80
	if not reducedMotion then
		shot.dot.Color = style.color
		shot.dot.Size = Vector3.one * SIZE_SCALE * style.size
		shot.dot.Position = shot.from
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
		local radius = shot.impactRadius + shot.hitOffset.Magnitude
		local offset = 0.10 + radius * math.sqrt(math.max(0, 1 - axis * axis)) / axis
		local surface = shot.center + view * (shot.halfSize / axis + offset) + shot.hitOffset
		if shot.elapsed < shot.flight then
			shot.dot.Position = shot.from:Lerp(surface, shot.elapsed / shot.flight)
			return
		end
		shot.impact = surface
		if shot.trail then
			stopTrail(shot)
			if not shot.twinshot then
				shot.dot.Parent = nil
			end
		end
	end

	local age = shot.elapsed - shot.flight
	if age >= FADE_SECONDS then
		release(shot)
		return
	end
	local facing = CFrame.lookAt(shot.impact, cameraPosition)
	if shot.trail then
		local t = 1 - age / FADE_SECONDS
		shot.effect.Transparency = 1 - shot.strength * t * (if shot.twinshot then 1 else 0.5 + 0.5 * t)
		if shot.twinshot then
			if not shot.reducedMotion and age < TWINSHOT_GLINT_SECONDS then
				shot.dot.Position = shot.impact
				shot.dot.Transparency = 0.12 + 0.88 * age / TWINSHOT_GLINT_SECONDS
			else
				shot.dot.Parent = nil
			end
			local direction = facing:VectorToObjectSpace(shot.impact - shot.from)
			facing *= CFrame.Angles(0, 0, math.atan2(direction.Y, direction.X))
		end
		shot.effect:PivotTo(facing)
	else
		pebbleImpact(shot, age, facing)
	end
	shot.effect.Parent = shot.parent
end

function Projectiles.Step(dt: number)
	local camera = workspace.CurrentCamera
	if camera then
		for _, style in styles do
			for _, shot in style.pool do
				if shot.parent then
					advance(shot, dt, camera.CFrame.Position)
				end
			end
		end
	end
end

function Projectiles.Clear()
	for _, style in styles do
		for _, shot in style.pool do
			release(shot)
		end
	end
end

return Projectiles
