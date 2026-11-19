local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Layout)
local DiceVisuals = require(script.Parent.Parent.Dice.Visuals)

local CommonProjectiles = {}

local MAX_SHOTS = 40
local SIZE_SCALE = 3.5
local FADE_SECONDS = 0.30
local WHITE = Color3.new(1, 1, 1)
local TAU = math.pi * 2
local styles = {
	C01 = {
		name = "Pebble",
		color = Color3.fromHex("#BEBEBE"),
		speed = 140,
		size = 0.20,
		flash = 0.08,
		ring = Color3.fromHex("#8F8F8F"),
		pool = {},
	},
	C02 = {
		name = "Needle",
		color = Color3.fromHex("#D9D9E6"),
		speed = 170,
		size = 0.18,
		flash = 0.12,
		trail = true,
		rays = 4,
		pool = {},
	},
	C03 = {
		name = "Hammer",
		color = Color3.fromHex("#FFC34D"),
		speed = 145,
		size = 0.22,
		flash = 0.22,
		rays = 3,
		pool = {},
	},
	C04 = {
		name = "Twinshot",
		color = Color3.fromHex("#FFF8E8"),
		speed = 155,
		size = 0.20,
		flash = 0.13,
		trail = true,
		rays = 2,
		pool = {},
	},
	C05 = {
		name = "Longshot",
		color = Color3.fromHex("#66FF33"),
		speed = 165,
		size = 0.16,
		flash = 0.10,
		ring = Color3.fromHex("#66FF33"),
		pool = {},
	},
	C06 = {
		name = "Chill",
		color = Color3.fromHex("#A8ECFF"),
		speed = 150,
		size = 0.20,
		flash = 0.17,
		trail = true,
		rays = 6,
		pool = {},
	},
	C07 = {
		name = "Spark",
		color = Color3.fromHex("#FFF066"),
		speed = 160,
		size = 0.20,
		flash = 0.14,
		trail = true,
		rays = 8,
		ring = Color3.fromHex("#FFD700"),
		pool = {},
	},
}
local slowMarkers = {}

local function piece(name: string, color: Color3, wedge: boolean?)
	local p = if wedge then Instance.new("WedgePart") else Instance.new("Part")
	p.Name = name
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CastShadow = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function ring(adornee: BasePart, name: string, color: Color3)
	local rim = Instance.new("CylinderHandleAdornment")
	rim.Name = name
	rim.Adornee = adornee
	rim.Color3 = color
	rim.Height = 0.05
	rim.Parent = adornee
	return rim
end

local function showRing(rim: CylinderHandleAdornment, radius: number, opacity: number)
	rim.Radius = radius
	rim.InnerRadius = radius * 0.84
	rim.Transparency = 1 - opacity
end

local function stopTrail(shot)
	if shot.trail then
		shot.trail.Enabled = false
		shot.trail:Clear()
	end
end

local function release(shot)
	stopTrail(shot)
	shot.dot.Parent = nil
	shot.flash.Parent = nil
	shot.parent, shot.target = nil, nil
end

local function borrow(style)
	for _, shot in style.pool do
		if not shot.parent then
			return shot
		end
	end
	if #style.pool >= MAX_SHOTS then
		return nil
	end

	local dot = piece(style.name .. "Projectile", style.color)
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.one * SIZE_SCALE * style.size
	if style.name == "Pebble" then
		dot.Material = Enum.Material.SmoothPlastic
	end
	local flash = piece(style.name .. "Impact", style.color)
	flash.Shape = Enum.PartType.Ball
	local shot = { dot = dot, flash = flash, style = style, rays = {} }
	if style.ring then
		shot.ring = ring(flash, style.name .. "Ring", style.ring)
	end
	for i = 1, style.rays or 0 do
		local ray = piece(style.name .. "Ray", style.color, style.name == "Hammer")
		ray.Parent = flash
		shot.rays[i] = ray
	end
	if style.trail then
		local width = Vector3.yAxis * SIZE_SCALE * 0.035
		local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
		top.Position, bottom.Position = width, -width
		top.Parent, bottom.Parent = dot, dot
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = top, bottom
		trail.FaceCamera = true
		trail.Lifetime = 0.055
		trail.MaxLength = 0.9 * SIZE_SCALE
		trail.LightEmission = 0.2
		trail.Color = ColorSequence.new(style.color)
		trail.Transparency = NumberSequence.new(0.38, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Enabled = false
		trail.Parent = dot
		shot.trail = trail
	end
	table.insert(style.pool, shot)
	return shot
end

function CommonProjectiles.Fire(parent: Folder, enemy, attack, reducedMotion: boolean): boolean
	local style = styles[attack.Type]
	if not style or attack.Distance == nil then
		return false
	end
	local shot = borrow(style)
	if not shot then
		return true
	end
	-- The die stands on a 0.4-stud pad, with a quarter stud between its top and the launch.
	local from = Layout.CellPosition(attack.Cell) + Vector3.yAxis * (DiceVisuals.Size(attack.Type) + 0.65 - Layout.Y)
	local center = Layout.PositionAt(attack.Distance) + Vector3.yAxis * enemy.lift
	local camera = workspace.CurrentCamera
	local up = if camera then camera.CFrame.UpVector else Vector3.yAxis
	local lane = up * ((attack.Lane or 0) * 0.22 * SIZE_SCALE)
	shot.parent, shot.target = parent, enemy.part
	shot.from, shot.center = from + lane, center
	shot.hitOffset = if attack.SharedTarget then lane else Vector3.zero
	shot.halfSize = enemy.lift
	shot.reducedMotion = reducedMotion
	shot.slowed = attack.Slowed
	shot.boosted = attack.Boosted and not reducedMotion
	shot.flight = if reducedMotion then 0 else (center - from).Magnitude / style.speed
	shot.elapsed = 0
	shot.impact = nil
	if not reducedMotion then
		shot.dot.Position = shot.from
		shot.dot.Parent = parent
		if shot.trail then
			shot.trail.Enabled = true
		end
	end
	return true
end

local function startSlowMarker(target: BasePart, reducedMotion: boolean)
	local marker = slowMarkers[target]
	if not marker then
		local rim = ring(target, "ChillSlowMarker", Color3.fromHex("#2FB4FF"))
		rim.CFrame = CFrame.new(0, -target.Size.Y / 2 + 0.04, 0) * CFrame.Angles(math.pi / 2, 0, 0)
		marker = { rim = rim }
		slowMarkers[target] = marker
	end
	marker.age = 0
	marker.reducedMotion = reducedMotion
end

local function advance(shot, dt: number, cameraPosition: Vector3)
	shot.elapsed += dt
	if not shot.impact then
		if shot.target.Parent then
			shot.center = shot.target.Position
		end
		local view = (cameraPosition - shot.center).Unit
		local axis = math.max(math.abs(view.X), math.abs(view.Y), math.abs(view.Z))
		local surface = shot.center + view * (shot.halfSize / axis + 0.45) + shot.hitOffset
		if shot.elapsed < shot.flight then
			shot.dot.Position = shot.from:Lerp(surface, shot.elapsed / shot.flight)
			return
		end
		shot.impact = CFrame.lookAt(surface, cameraPosition)
		stopTrail(shot)
		shot.dot.Parent = nil
		if shot.slowed and shot.target.Parent then
			startSlowMarker(shot.target, shot.reducedMotion)
		end
	end

	local age = shot.elapsed - shot.flight
	if age >= FADE_SECONDS then
		release(shot)
		return
	end
	local style = shot.style
	local strength = if shot.reducedMotion then 0.42 elseif shot.boosted then 1 else 0.85
	local progress = math.min(age / style.flash, 1)
	local motion = if shot.reducedMotion then 0.5 else progress
	local opacity = strength * (1 - progress) ^ 2
	local size = style.size * SIZE_SCALE * (0.82 + motion * 0.65)
	local color = if shot.boosted then style.color:Lerp(WHITE, 0.54) else style.color
	shot.flash.CFrame = shot.impact
	shot.flash.Size = Vector3.one * size
	shot.flash.Color = color
	shot.flash.Transparency = 1 - opacity
	if shot.ring then
		local ringProgress = if shot.reducedMotion then 0.5 else age / FADE_SECONDS
		local radius = (0.23 + ringProgress * 0.72) * (if shot.boosted then 1.4 else 1)
		showRing(shot.ring, radius, strength * (1 - age / FADE_SECONDS))
	end
	local flight = shot.impact:VectorToObjectSpace(shot.impact.Position - shot.from)
	local facing = if style.name == "Twinshot" then math.atan2(flight.Y, flight.X) - math.pi / 2 else 0
	for i, ray in shot.rays do
		ray.Color = color
		ray.Size = Vector3.new(0.10, size * 0.68, 0.11)
		ray.CFrame = shot.impact * CFrame.Angles(0, 0, facing + TAU * i / #shot.rays) * CFrame.new(0, size * 0.58, 0)
		ray.Transparency = 1 - opacity
	end
	shot.flash.Parent = shot.parent
end

function CommonProjectiles.Step(dt: number)
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
	for target, marker in slowMarkers do
		marker.age += dt
		if not target.Parent or marker.age >= FADE_SECONDS then
			marker.rim:Destroy()
			slowMarkers[target] = nil
		else
			local fade = 1 - marker.age / FADE_SECONDS
			local radius = target.Size.X * (if marker.reducedMotion then 0.68 else 0.72 - 0.08 * fade)
			showRing(marker.rim, radius, fade * (if marker.reducedMotion then 0.32 else 0.70))
		end
	end
end

function CommonProjectiles.Clear()
	for _, style in styles do
		for _, shot in style.pool do
			release(shot)
		end
	end
	for target, marker in slowMarkers do
		marker.rim:Destroy()
		slowMarkers[target] = nil
	end
end

return CommonProjectiles
