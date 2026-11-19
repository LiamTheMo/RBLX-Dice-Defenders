local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Display = require(ReplicatedStorage.Shared.Display)
local Layout = require(ReplicatedStorage.Shared.Layout)
local DiceVisuals = require(script.Parent.Parent.Dice.Visuals)
local CommonImpactMeshes = require(script.Parent.CommonImpactMeshes)
local ProjectileScale = require(script.Parent.ProjectileScale)
local RarityEffects = require(script.Parent.RarityEffects)
local Textures = require(script.Parent.RarityTextures)

local CommonProjectiles = {}

local MAX_SHOTS = 40
local SIZE_SCALE = ProjectileScale.Flight
local IMPACT_SCALE = ProjectileScale.Impact
local OUTLINE_SCALE = SIZE_SCALE * IMPACT_SCALE * 0.65
local FADE_SECONDS = 0.30
local WHITE = Color3.new(1, 1, 1)
local styles = {
	C01 = {
		name = "Pebble",
		color = Color3.fromHex("#BEBEBE"),
		speed = 140,
		size = 0.20,
		flash = 0.055,
		core = 1.18,
		flashColor = Color3.fromHex("#D9D9D9"),
		ring = Color3.fromHex("#8F8F8F"),
		pool = {},
	},
	C02 = {
		name = "Needle",
		color = Color3.fromHex("#D9D9D9"),
		speed = 170,
		size = 0.18,
		flash = 0.10,
		core = 0.68,
		halo = 0.27,
		flashColor = WHITE,
		trail = true,
		trailColor = Color3.fromHex("#BFBFBF"),
		outline = CommonImpactMeshes.Needle,
		pool = {},
	},
	C03 = {
		name = "Hammer",
		color = Color3.fromHex("#FFC34D"),
		speed = 145,
		size = 0.22,
		flash = 0.22,
		core = 0.82,
		halo = 0.36,
		flashColor = Color3.fromHex("#FFE9B0"),
		trail = true,
		trailColor = Color3.fromHex("#FFD079"),
		outline = CommonImpactMeshes.Hammer,
		outlineScale = 0.82,
		pool = {},
	},
	C04 = {
		name = "Twinshot",
		color = Color3.fromHex("#FFF8E8"),
		speed = 155,
		size = 0.20,
		flash = FADE_SECONDS,
		core = 0.36,
		halo = 0.25,
		trail = true,
		outline = CommonImpactMeshes.Twinshot,
		outlineScale = 0.85,
		pool = {},
	},
	C05 = {
		name = "Longshot",
		color = Color3.fromHex("#66FF33"),
		speed = 165,
		size = 0.16,
		flash = 0.10,
		core = 1.05,
		halo = 0.40,
		flashColor = Color3.fromHex("#A3FF73"),
		ring = Color3.fromHex("#66FF33"),
		pool = {},
	},
	C06 = {
		name = "Chill",
		color = Color3.fromHex("#6CE0FF"),
		speed = 150,
		size = 0.20,
		flash = 0.10,
		core = 0.48,
		halo = 0.38,
		flashColor = Color3.fromHex("#E8FFFF"),
		trail = true,
		outline = CommonImpactMeshes.Chill,
		pool = {},
	},
	C07 = {
		name = "Spark",
		color = Color3.fromHex("#FFF066"),
		speed = 160,
		size = 0.20,
		flash = 0.10,
		core = 0.50,
		halo = 0.34,
		flashColor = Color3.fromHex("#FFF7BA"),
		trail = true,
		outline = CommonImpactMeshes.Spark,
		ring = Color3.fromHex("#FFD700"),
		pool = {},
	},
}

for id, style in RarityEffects.Styles do
	styles[id] = style
end

for id, die in Display.Dice do
	if not styles[id] then
		styles[id] = {
			name = die.Name:gsub("%s", ""),
			color = die.Color,
			size = 0.20,
			flash = 0.13,
			ring = die.Color,
			impactOnly = true,
			pool = {},
		}
	end
end

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

local function showRing(rim: CylinderHandleAdornment, radius: number, opacity: number, weight: number?)
	rim.Radius = radius
	rim.InnerRadius = radius * (1 - 0.11 * (weight or 1))
	rim.Transparency = 1 - opacity
end

local function stopTrail(shot)
	for _, trail in shot.trails do
		trail.Enabled = false
		trail:Clear()
	end
end

local function release(shot)
	stopTrail(shot)
	if shot.dot then
		shot.dot.Parent = nil
	end
	if shot.visuals then
		RarityEffects.Release(shot.visuals)
		shot.attack = nil
	else
		shot.flash.Parent = nil
	end
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

	local dot
	if not style.impactOnly then
		dot = piece(style.name .. "Projectile", style.color)
		dot.Shape = Enum.PartType.Ball
		dot.Size = Vector3.one * SIZE_SCALE * style.size
		if style.name == "Pebble" then
			dot.Material = Enum.Material.SmoothPlastic
		end
	end
	local shot = { dot = dot, style = style, shards = {}, trails = {} }
	if style.detail then
		shot.visuals = RarityEffects.Create(style, dot)
	else
		local flash = piece(style.name .. "Impact", style.color)
		flash.Shape = Enum.PartType.Ball
		shot.flash = flash
		if style.halo and dot then
			shot.travelGlow = Textures.Create(dot, "Glow", style.color)
			shot.impactGlow = Textures.Create(flash, "Glow", style.flashColor or style.color)
		end
		if style.ring then
			shot.ring = ring(flash, style.name .. "Ring", style.ring)
		end
		for i, _ in style.outline or {} do
			local shard = piece(style.name .. "Shard", style.flashColor or style.color, true)
			shard.Parent = flash
			shot.shards[i] = shard
		end
	end
	local count = if not dot or not style.trail
		then 0
		elseif style.detail == "Bolt" then 3
		elseif style.detail == "Crystal" or style.name == "Arc" then 2
		else 1
	for i = 1, count do
		local width = Vector3.yAxis * SIZE_SCALE * (if style.detail then 0.023 else 0.028)
		local offset = Vector3.xAxis * ((i - (count + 1) / 2) * 0.24)
		local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
		top.Position, bottom.Position = offset + width, offset - width
		top.Parent, bottom.Parent = dot, dot
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = top, bottom
		trail.FaceCamera = true
		trail.Lifetime = 0.055
		trail.MaxLength = SIZE_SCALE * (if style.detail then 0.9 elseif style.name == "Hammer" then 0.61 else 0.42)
		trail.LightEmission = 0.2
		trail.Color = if style.streak
			then ColorSequence.new(style.streak:Lerp(style.burstColor, 0.32), style.streak:Lerp(style.accent, 0.35))
			else ColorSequence.new(style.trailColor or style.color)
		trail.Transparency = NumberSequence.new(if style.detail then 0.38 else 0.48, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Enabled = false
		trail.Parent = dot
		table.insert(shot.trails, trail)
	end
	table.insert(style.pool, shot)
	return shot
end

local function fire(parent, enemy, attack, reducedMotion, style, visualLane)
	local shot = borrow(style)
	if not shot then
		return not style.impactOnly
	end
	local distance = attack.Distance or enemy.speed * (workspace:GetServerTimeNow() - enemy.spawnAt)
	local center = Layout.PositionAt(distance, enemy.seat, enemy.playerCount) + Vector3.yAxis * enemy.lift
	-- The die stands on a 0.4-stud pad, with a quarter stud between its top and the launch.
	local from = if style.impactOnly
		then center
		else Layout.CellPosition(attack.Cell, attack.Seat, attack.PlayerCount) + Vector3.yAxis * (DiceVisuals.Size(
			attack.Type
		) + 0.65 - Layout.Y)
	local camera = workspace.CurrentCamera
	local up = if camera then camera.CFrame.UpVector else Vector3.yAxis
	local lane = up * ((attack.Lane or visualLane) * 0.22 * SIZE_SCALE)
	shot.parent, shot.target = parent, enemy.part
	shot.from, shot.center = from + lane, center
	shot.hitOffset = if attack.SharedTarget or visualLane ~= 0 then lane else Vector3.zero
	shot.halfSize = enemy.lift
	shot.reducedMotion = reducedMotion
	shot.slowed = attack.Slowed
	shot.slowUntil = attack.SlowUntil
	shot.boosted = attack.Boosted and not reducedMotion
	shot.flight = if reducedMotion or style.impactOnly then 0 else (center - from).Magnitude / style.speed
	shot.elapsed = 0
	shot.impact = nil
	local arrival = workspace:GetServerTimeNow() + shot.flight
	if shot.visuals then
		shot.enemySeat, shot.playerCount = enemy.seat, enemy.playerCount
		shot.attack = attack
		shot.visualLane = visualLane
		shot.lift = enemy.lift
		shot.copiedCell = if style.name == "Mirror" then attack.CopiedCell else nil
		shot.transformedCell = if style.name == "Forge" then attack.TransformedCell else nil
		shot.effectCell = shot.copiedCell or shot.transformedCell
		shot.supportCells, shot.links = attack.SupportCells, attack.ChainDistances
		if shot.effectCell then
			local cell = Layout.CellPosition(shot.effectCell, attack.Seat, attack.PlayerCount)
			shot.center = cell + Vector3.yAxis * 2
			shot.halfSize = DiceVisuals.Size(attack.Type) / 2
			shot.flight = if reducedMotion then 0 else (shot.center - from).Magnitude / style.speed
		end
	end
	if not (shot.visuals and shot.effectCell) and enemy.hp > 0 then
		shot.center = Layout.PositionAt(enemy.speed * (arrival - enemy.spawnAt), enemy.seat, enemy.playerCount)
			+ Vector3.yAxis * enemy.lift
	end
	local eye = if camera then (camera.CFrame.Position - shot.center).Unit else Vector3.yAxis
	local axis = math.max(math.abs(eye.X), math.abs(eye.Y), math.abs(eye.Z))
	shot.surface = shot.center + eye * (shot.halfSize / axis + 0.45) + shot.hitOffset
	if shot.visuals then
		local direction = shot.surface - shot.from
		shot.travelFrame =
			CFrame.lookAlong(Vector3.zero, if direction.Magnitude > 0.01 then direction else Vector3.zAxis)
		shot.ground = Vector3.new(shot.center.X, 0.47, shot.center.Z)
	end
	if shot.dot and not reducedMotion then
		shot.dot.CFrame = if shot.visuals then shot.travelFrame + shot.from else CFrame.new(shot.from)
		shot.dot.Parent = parent
		if shot.travelGlow then
			Textures.Show(shot.travelGlow, shot.from, shot.dot.Size.X * 2.4, style.halo)
		end
		for _, trail in shot.trails do
			trail.Enabled = true
		end
		if shot.visuals then
			RarityEffects.Travel(shot, shot.from, 0)
		end
	end
	-- EnemyView still supplies the tracer for impact-only styles.
	return not style.impactOnly
end

function CommonProjectiles.Fire(parent: Folder, enemy, attack, reducedMotion: boolean): boolean
	local style = styles[attack.Type]
	if not style or (attack.Distance == nil and not style.impactOnly) then
		return false
	end
	local handled = fire(parent, enemy, attack, reducedMotion, style, 0)
	if attack.Type == "R03" then
		fire(parent, enemy, attack, reducedMotion, style, -1)
		fire(parent, enemy, attack, reducedMotion, style, 1)
	end
	return handled
end

local function startSlowMarker(target: BasePart, expiresAt: number?)
	local now = workspace:GetServerTimeNow()
	local expires = expiresAt or now + FADE_SECONDS
	if expires <= now then
		return
	end
	local marker = slowMarkers[target]
	if not marker then
		local rim = ring(target, "ChillSlowMarker", Color3.fromHex("#2FB4FF"))
		rim.CFrame = CFrame.new(0, -target.Size.Y / 2 + 0.04, 0) * CFrame.Angles(math.pi / 2, 0, 0)
		marker = { rim = rim, started = now, expires = expires }
		slowMarkers[target] = marker
	end
	marker.expires = math.max(marker.expires, expires)
end

local function advance(shot, dt: number, camera: Camera)
	shot.elapsed += dt
	if not shot.impact then
		local surface = shot.surface
		if shot.elapsed < shot.flight then
			local progress = shot.elapsed / shot.flight
			shot.dot.Position = shot.from:Lerp(surface, progress)
			if shot.visuals then
				RarityEffects.Travel(shot, shot.dot.Position, progress)
			end
			return
		end
		shot.impact = if shot.visuals
			then CFrame.lookAt(surface, camera.CFrame.Position)
			else camera.CFrame.Rotation + surface
		stopTrail(shot)
		if shot.dot then
			shot.dot.Parent = nil
		end
		if shot.visuals then
			RarityEffects.StartStatus(shot)
		elseif shot.slowed and shot.target.Parent then
			startSlowMarker(shot.target, shot.slowUntil)
		end
	end

	local age = shot.elapsed - shot.flight
	if age >= FADE_SECONDS then
		release(shot)
		return
	end
	if shot.visuals then
		RarityEffects.Impact(shot, age, shot.impact)
		return
	end
	local style = shot.style
	local strength = if shot.reducedMotion then 0.42 elseif shot.boosted then 1 else 0.85
	local coreProgress = math.min(age / math.min(0.10, style.flash), 1)
	local coreScale = if shot.reducedMotion then 1 else 1.12 - coreProgress * 0.36
	local color = style.flashColor or style.color
	shot.flash.CFrame = shot.impact
	shot.flash.Size = Vector3.one * (style.size * SIZE_SCALE * IMPACT_SCALE * coreScale * (style.core or 1))
	shot.flash.Color = color
	local coreOpacity = strength * (1 - coreProgress) ^ (if shot.reducedMotion then 1.65 else 1.25)
	shot.flash.Transparency = 1 - coreOpacity
	if shot.impactGlow then
		Textures.Show(shot.impactGlow, shot.impact.Position, shot.flash.Size.X * 2.7, coreOpacity * style.halo)
	end
	if shot.ring then
		local ringProgress = if shot.reducedMotion then 0.5 else age / FADE_SECONDS
		local radius = IMPACT_SCALE * (0.27 + 0.83 * (1 - (1 - ringProgress) ^ 2))
		local intensity = if style.name == "Spark" then 0.70 else 1
		showRing(shot.ring, radius, intensity * strength * (1 - age / FADE_SECONDS) ^ 1.4, ProjectileScale.ImpactWeight)
	end
	if style.outline then
		local progress = math.min(age / style.flash, 1)
		local size = OUTLINE_SCALE * (style.outlineScale or 1)
		if shot.boosted then
			size *= if style.name == "Spark" then 1.4 else 1.22
		end
		if style.name == "Hammer" and not shot.reducedMotion then
			size *= 0.48 + 0.52 * math.min(age / 0.04, 1) - 0.45 * math.max(age - 0.04, 0) / 0.18
		end
		local pose = shot.impact
		if style.name == "Hammer" or style.name == "Twinshot" then
			local direction = pose:VectorToObjectSpace(pose.Position - shot.from)
			pose *= CFrame.Angles(0, 0, math.atan2(direction.Y, direction.X))
		end
		for i, shard in shot.shards do
			local definition = style.outline[i]
			local offset = definition[1]
			shard.Size = definition[2] * size
			shard.CFrame = pose * (offset.Rotation + offset.Position * size)
			shard.Transparency = 1 - strength * (1 - progress) ^ (if shot.reducedMotion then 1.55 else 1.25)
		end
	end
	shot.flash.Parent = shot.parent
end

function CommonProjectiles.Step(dt: number, reducedMotion: boolean?)
	local camera = workspace.CurrentCamera
	if camera then
		for _, style in styles do
			for _, shot in style.pool do
				if shot.parent then
					advance(shot, dt, camera)
				end
			end
		end
	end
	local now = workspace:GetServerTimeNow()
	for target, marker in slowMarkers do
		local remaining = marker.expires - now
		if not target.Parent or remaining <= 0 then
			marker.rim:Destroy()
			slowMarkers[target] = nil
		else
			local fade = math.min(remaining / 0.18, 1)
			local growth = math.clamp((now - marker.started) / FADE_SECONDS, 0, 1)
			local radius = target.Size.X * (if reducedMotion then 0.68 else 0.62 + 0.10 * growth)
			showRing(marker.rim, radius, fade * (if reducedMotion then 0.32 else 0.70))
		end
	end
end

function CommonProjectiles.Clear(keepSlowMarkers: boolean?)
	for _, style in styles do
		for _, shot in style.pool do
			release(shot)
		end
	end
	if not keepSlowMarkers then
		for target, marker in slowMarkers do
			marker.rim:Destroy()
			slowMarkers[target] = nil
		end
	end
end

return CommonProjectiles
