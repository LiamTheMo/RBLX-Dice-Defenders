local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Display = require(ReplicatedStorage.Shared.Display)
local Layout = require(ReplicatedStorage.Shared.Layout)
local DiceVisuals = require(script.Parent.Parent.Dice.Visuals)
local ProjectileStyles = require(script.Parent.ProjectileStyles)
local Fx = require(script.Parent.FxLib)
local ProjectileScale = require(script.Parent.ProjectileScale)
local RarityEffects = require(script.Parent.RarityEffects)

local Projectiles = {}

local MAX_SHOTS = 40
local SIZE_SCALE = ProjectileScale.Flight
local IMPACT_SCALE = ProjectileScale.Impact
local IMPACT_BASE = ProjectileScale.FlightLegacy
local LANE_OFFSET = 0.6 -- C04: studs each side of the shot line at D=5
local ROUTE_TOP = Layout.Y - 0.8 -- enemies walk 0.8 above the route cap (3.2 in the maps)
local GROUND_Y = ROUTE_TOP + 0.05 -- flat common layers sit just over it
local HIT_SECONDS = 0.30 -- R3: hit rings and flash end by +300 ms
local SLOW_FALLBACK = 0.40 -- slow marker lifetime when the record carries no SlowUntil
local styles = table.clone(RarityEffects.Styles)

for id, die in Display.Dice do
	if not styles[id] and not ProjectileStyles[id] then
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

local function piece(name: string, color: Color3)
	local p = Instance.new("Part")
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
	for _, h in shot.trails do
		h.trail.MaxLength = 0
		Fx.ReleaseTrail(h)
	end
	table.clear(shot.trails)
end

-- Trails come from FxLib's pool (30-trail budget) for the flight only and go back on impact or release.
local function startTrails(shot)
	local style, dot, count = shot.style, shot.dot, shot.trailCount
	for i = 1, count do
		local half = SIZE_SCALE * (if style.detail then 0.045 else 0.055)
		local h = Fx.Trail(dot, {
			Lifetime = 0.12,
			Width = half * 2,
			LightEmission = 0.6,
			Transparency = if style.detail then 0.1 else 0.12,
		})
		if not h then
			return
		end
		local offset = Vector3.xAxis * ((i - (count + 1) / 2) * 0.24)
		h.a0.Position, h.a1.Position = offset + Vector3.yAxis * half, offset - Vector3.yAxis * half
		h.trail.MaxLength = SIZE_SCALE * (if style.detail then 1.8 elseif style.name == "Hammer" then 1.2 else 0.9)
		h.trail.Color = if style.streak
			then ColorSequence.new(style.streak:Lerp(style.burstColor, 0.32), style.streak:Lerp(style.accent, 0.35))
			else ColorSequence.new(style.trailColor or style.color)
		table.insert(shot.trails, h)
	end
end

-- The hit ends at +0.30 s, except a layer the profile specifies longer (Emberstorm embers) keeps its own length.
local function hitSeconds(style): number
	local seconds = style.hitSeconds
	if not seconds then
		seconds = HIT_SECONDS
		if style.profile then
			for _, layer in style.profile.impact do
				seconds = math.max(seconds, layer.dur or 0)
			end
		end
		style.hitSeconds = seconds
	end
	return seconds
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
	shot.parent, shot.target, shot.onImpact = nil, nil, nil
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
	local shot = { dot = dot, style = style, trails = {}, trailCount = 0 }
	if style.detail then
		shot.visuals = RarityEffects.Create(style, dot)
	else
		local flash = piece(style.name .. "Impact", style.color)
		flash.Shape = Enum.PartType.Ball
		shot.flash = flash
		if style.ring then
			shot.ring = ring(flash, style.name .. "Ring", style.ring)
		end
	end
	local count = if not dot or not style.trail
		then 0
		elseif style.detail == "Bolt" then 3
		elseif style.detail == "Crystal" or style.name == "Arc" then 2
		else 1
	shot.trailCount = count
	table.insert(style.pool, shot)
	return shot
end

local SLOW_COLOR_FROM, SLOW_COLOR_TO = Color3.fromHex("#6CE0FF"), Color3.fromHex("#2FB4FF")
local SLOW_DIA: { Fx.Key } = {
	{ t = 0, v = 0.9 },
	{ t = 0.3, v = 3.0, ease = Fx.Easing.quadOut },
	{ t = 0.45, v = 2.2, ease = Fx.Easing.quadOut },
}
local SLOW_TRANS: { Fx.Key } = { { t = 0, v = 0 }, { t = 0.1, v = 0.6 }, { t = 0.3, v = 0.55 } }

local function releaseMarker(target: BasePart)
	local marker = slowMarkers[target]
	if marker then
		Fx.Release(marker.part)
		slowMarkers[target] = nil
	end
end

-- C06's hit ring doubles as the slow marker: expands, settles to a steady ring and lasts the real slow
-- (SlowUntil from the hit record). A refresh extends the end time; it does not replay the expansion.
local function startSlowMarker(target: BasePart, expiresAt: number?, parent: Instance, scale: number)
	local now = workspace:GetServerTimeNow()
	local expires = expiresAt or now + SLOW_FALLBACK
	if expires <= now then
		return
	end
	local marker = slowMarkers[target]
	if not marker then
		local part = Fx.Part("Fx_Ring", { Parent = parent, Material = Enum.Material.Neon, Color = SLOW_COLOR_FROM })
		if not part then
			return
		end
		marker = { part = part, started = now, expires = expires, scale = scale }
		slowMarkers[target] = marker
	end
	marker.expires = math.max(marker.expires, expires)
end

local function stepMarker(target: BasePart, marker, now: number, steady: boolean)
	local age = now - marker.started
	local diameter, transparency, alpha
	if steady then
		diameter, transparency, alpha = 2.2, 0.55, 1
	else
		diameter = Fx.Sample(SLOW_DIA, age)
		if age > 0.45 then
			diameter *= 1 + 0.05 * (0.5 + 0.5 * math.sin(age * 6))
		end
		transparency = Fx.Sample(SLOW_TRANS, age)
		alpha = math.clamp(age / 0.3, 0, 1)
	end
	local fade = math.min((marker.expires - now) / 0.15, 1)
	local part = marker.part
	local base = target.Position
	part.Size = Fx.Meshes.Fx_Ring.Size * (diameter * marker.scale)
	part.CFrame = CFrame.new(base.X, base.Y - target.Size.Y / 2 + 0.04, base.Z)
	part.Color = SLOW_COLOR_FROM:Lerp(SLOW_COLOR_TO, alpha)
	part.Transparency = 1 - (1 - transparency) * fade
end

local function fire(parent, enemy, attack, reducedMotion, style, visualLane, onImpact: (() -> ())?)
	local shot = borrow(style)
	if not shot then
		return not style.impactOnly, false
	end
	local distance = attack.Distance or enemy.speed * (workspace:GetServerTimeNow() - enemy.spawnAt)
	local center = Layout.PositionAt(distance, enemy.seat, enemy.playerCount) + Vector3.yAxis * enemy.lift
	-- The die stands on a 0.4-stud pad, with a quarter stud between its top and the launch.
	local from = if style.impactOnly
		then center
		else Layout.CellPosition(attack.Cell, attack.Seat, attack.Arena or attack.PlayerCount)
			+ Vector3.yAxis * (DiceVisuals.Size(attack.Type) + 0.25 + Layout.PadTop - Layout.Y)
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
	shot.onImpact = onImpact
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
			local cell = Layout.CellPosition(shot.effectCell, attack.Seat, attack.Arena or attack.PlayerCount)
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
		shot.ground = Vector3.new(shot.center.X, ROUTE_TOP, shot.center.Z)
	end
	if shot.dot and not reducedMotion then
		shot.dot.CFrame = if shot.visuals then shot.travelFrame + shot.from else CFrame.new(shot.from)
		shot.dot.Parent = parent
		startTrails(shot)
		if shot.visuals then
			RarityEffects.Travel(shot, shot.from, 0)
		end
	end
	-- EnemyView still supplies the tracer for impact-only styles.
	return not style.impactOnly, true
end

-- Common dice (C01-C07): pooled Fx MeshParts driven by one Fx.Run entry per shot ------------------------------

local activeShots = {}

-- Flat shapes (stars, flashes) face the camera; fans also turn so their prong side points along `direction`.
local function orientation(orient: string, point: Vector3, ground: Vector3, direction: Vector3): CFrame
	if orient == "ground" then
		return CFrame.new(ground)
	end
	local facing = Fx.FaceCamera(CFrame.new(point))
	if orient == "camera" then
		return facing
	end
	local v = facing:VectorToObjectSpace(direction)
	if v.X * v.X + v.Z * v.Z < 1e-6 then
		return facing
	end
	local roll = if orient == "fanBack" then math.atan2(-v.X, -v.Z) else math.atan2(v.X, v.Z)
	return Fx.FaceCamera(CFrame.new(point), roll)
end

local function setSize(part: MeshPart, mesh: string, uniform: boolean?, size: number)
	size = math.max(size, 0.01)
	part.Size = if uniform then Vector3.one * size else Fx.Meshes[mesh].Size * size
end

local function fireCommon(
	parent: Folder,
	enemy,
	attack,
	reducedMotion: boolean,
	style,
	onImpact: () -> ()
): (boolean, boolean)
	local tier = Fx.Tier(reducedMotion)
	local scale = Fx.Scale(DiceVisuals.Size(attack.Type))
	local token = {}
	local cores, trails, parts = {}, {}, {}
	local elapsed, impacted = 0, false

	local distance = attack.Distance
	local center = Layout.PositionAt(distance, enemy.seat, enemy.playerCount) + Vector3.yAxis * enemy.lift
	-- The die stands on a 0.4-stud pad, with a quarter stud between its top and the launch.
	local from = Layout.CellPosition(attack.Cell, attack.Seat, attack.Arena or attack.PlayerCount)
		+ Vector3.yAxis * (DiceVisuals.Size(attack.Type) + 0.25 + Layout.PadTop - Layout.Y)
	local camera = workspace.CurrentCamera
	local up = if camera then camera.CFrame.UpVector else Vector3.yAxis
	local lane = up * ((attack.Lane or 0) * LANE_OFFSET * scale)
	local hitOffset = if attack.SharedTarget or attack.Lane ~= nil then lane else Vector3.zero
	from += lane
	local flight = if reducedMotion then 0 else (center - from).Magnitude / style.speed
	if enemy.hp > 0 then
		local arrival = workspace:GetServerTimeNow() + flight
		center = Layout.PositionAt(enemy.speed * (arrival - enemy.spawnAt), enemy.seat, enemy.playerCount)
			+ Vector3.yAxis * enemy.lift
	end
	local eye = if camera then (camera.CFrame.Position - center).Unit else Vector3.yAxis
	local axis = math.max(math.abs(eye.X), math.abs(eye.Y), math.abs(eye.Z))
	local surface = center + eye * (enemy.lift / axis + 0.45) + hitOffset
	local ground = Vector3.new(center.X, GROUND_Y, center.Z)
	local direction = surface - from
	direction = if direction.Magnitude > 0.01 then direction.Unit else Vector3.zAxis
	-- C02 sixth hit / C07 fourth hit: the server marks the record Boosted (Match procEvery).
	local boosted = attack.Boosted == true and not reducedMotion
	local target = enemy.part
	local slowed, slowUntil = attack.Slowed, attack.SlowUntil

	local function stopTrails()
		for _, h in trails do
			h.trail.MaxLength = 0
			Fx.ReleaseTrail(h)
		end
		table.clear(trails)
	end

	local function releaseParts(list)
		for _, part in list do
			Fx.Release(part)
		end
		table.clear(list)
	end

	local function startTrail(part: MeshPart)
		local def = style.trail
		if not def or not Fx.LayerAllowed(tier, "trail") then
			return
		end
		local h = Fx.Trail(part, {
			Color = def.color,
			Lifetime = def.lifetime,
			Width = def.width * scale,
			LightEmission = def.emission,
			Transparency = def.transparency,
		})
		if h then
			h.trail.MaxLength = if def.length then def.length * scale else 0
			table.insert(trails, h)
		end
	end

	local function update(dt: number): boolean
		elapsed += dt
		if not impacted then
			if elapsed < flight then
				local progress = elapsed / flight
				local cf = CFrame.new(from:Lerp(surface, progress))
				for i, part in cores do
					part.CFrame = cf
					local fadeIn = style.cores[i].fadeIn
					if fadeIn then
						part.Transparency = fadeIn * (1 - math.min(progress / 0.25, 1))
					end
				end
				if style.trail and #trails == 0 and progress >= style.trail.from and cores[1] then
					startTrail(cores[1])
				end
				return false
			end
			impacted = true
			if onImpact then
				onImpact()
			end
			stopTrails()
			releaseParts(cores)
			for _, def in style.hits do
				if Fx.LayerAllowed(tier, def.layer) then
					local part = Fx.Part(def.mesh, {
						Parent = parent,
						Color = def.color,
						Material = def.material,
						CFrame = CFrame.new(surface),
					})
					if part then
						parts[def] = part
					end
				end
			end
			if slowed and target.Parent then
				startSlowMarker(target, slowUntil, parent, scale)
			end
		end
		local age = elapsed - flight
		if age >= style.duration then
			return true
		end
		for def, part in parts do
			if age >= def.dur then
				Fx.Release(part)
				parts[def] = nil
			else
				local mul = Fx.Sample(def.sizeKeys, age) * def.size * scale
				if boosted and def.boost then
					mul *= def.boost
				end
				setSize(part, def.mesh, def.uniform, mul)
				part.CFrame = orientation(def.orient, surface, ground, direction)
				local opacity = 1 - Fx.Sample(def.transKeys, age)
				part.Transparency = 1 - (if reducedMotion then Fx.FlashOpacity(true, opacity) else opacity)
			end
		end
		return false
	end

	local function onEnd()
		activeShots[token] = nil
		stopTrails()
		releaseParts(cores)
		for _, part in parts do
			Fx.Release(part)
		end
		table.clear(parts)
		onImpact = nil
	end

	local handle = Fx.Run(update, onEnd, style.limiter)
	if not handle then
		return true, false
	end
	activeShots[token] = handle
	if not reducedMotion then
		for i, def in style.cores do
			if Fx.LayerAllowed(tier, def.layer) then
				local part = Fx.Part(def.mesh, {
					Parent = parent,
					Color = def.color,
					Material = def.material,
					CFrame = CFrame.new(from),
				})
				if part then
					setSize(part, def.mesh, def.uniform, def.size * scale)
					if def.fadeIn then
						part.Transparency = def.fadeIn
					end
				end
				cores[i] = part
			end
		end
	end
	return true, true
end

function Projectiles.Fire(
	parent: Folder,
	enemy,
	attack,
	reducedMotion: boolean,
	onImpact: () -> ()
): (boolean, boolean)
	local common = ProjectileStyles[attack.Type]
	if common then
		if attack.Distance == nil then
			return false, false
		end
		return fireCommon(parent, enemy, attack, reducedMotion, common, onImpact)
	end
	local style = styles[attack.Type]
	if not style or (attack.Distance == nil and not style.impactOnly) then
		return false, false
	end
	local handled, hasImpact = fire(parent, enemy, attack, reducedMotion, style, 0, onImpact)
	if attack.Type == "R03" then
		fire(parent, enemy, attack, reducedMotion, style, -1, nil)
		fire(parent, enemy, attack, reducedMotion, style, 1, nil)
	end
	return handled, hasImpact
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
		if shot.onImpact then
			shot.onImpact()
			shot.onImpact = nil
		end
		stopTrail(shot)
		if shot.dot then
			shot.dot.Parent = nil
		end
		if shot.visuals then
			RarityEffects.StartStatus(shot)
		elseif shot.slowed and shot.target.Parent then
			startSlowMarker(shot.target, shot.slowUntil, shot.parent, 1)
		end
	end

	local age = shot.elapsed - shot.flight
	local hitEnd = hitSeconds(shot.style)
	if age >= hitEnd then
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
	shot.flash.Size = Vector3.one * (style.size * IMPACT_BASE * IMPACT_SCALE * coreScale * (style.core or 1))
	shot.flash.Color = color
	local coreOpacity = strength * (1 - coreProgress) ^ (if shot.reducedMotion then 1.65 else 1.25)
	shot.flash.Transparency = 1 - coreOpacity
	if shot.ring then
		local ringProgress = if shot.reducedMotion then 0.5 else age / hitEnd
		local radius = IMPACT_SCALE * (0.27 + 0.83 * (1 - (1 - ringProgress) ^ 2))
		showRing(shot.ring, radius, strength * (1 - age / hitEnd) ^ 1.4, ProjectileScale.RingWeight)
	end
	shot.flash.Parent = shot.parent
end

function Projectiles.Step(dt: number, reducedMotion: boolean?)
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
	local steady = Fx.Tier(reducedMotion == true) == "Low"
	for target, marker in slowMarkers do
		if not target.Parent or marker.expires <= now then
			releaseMarker(target)
		else
			stepMarker(target, marker, now, steady)
		end
	end
end

function Projectiles.Clear(keepSlowMarkers: boolean?)
	for _, handle in activeShots do
		handle.cancel()
	end
	for _, style in styles do
		for _, shot in style.pool do
			release(shot)
		end
	end
	if not keepSlowMarkers then
		for target in slowMarkers do
			releaseMarker(target)
		end
	end
end

return Projectiles
