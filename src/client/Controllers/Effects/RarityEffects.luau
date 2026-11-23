-- Rare / Epic / Legendary / Mythic dice effects, built from pooled MeshParts, Trails and Beams (FxLib).
-- No textures, SurfaceGui, Decal or ParticleEmitter. Layer data lives in RarityStyles (sizes at D = 5,
-- scaled here by k = dieSize / 5). CommonProjectiles drives the per-frame poses (Travel / Impact) and
-- EnemyView the status loops; parts are borrowed lazily on the first call and every one of them goes back
-- to its pool in Release (or when the shared loop cancels the effect).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Layout)
local DiceVisuals = require(script.Parent.Parent.Dice.Visuals)
local Fx = require(script.Parent.FxLib)
local RarityStyles = require(script.Parent.RarityStyles)

local RarityEffects = {}
RarityEffects.Styles = RarityStyles.Styles

local MAX_SHOTS = 40 -- per style (CommonProjectiles pools the same number of shots)
local LOOP_CAP = 8 -- status loops + support auras alive at once
local NEON = Enum.Material.Neon
local TAU = math.pi * 2
local FLIP = CFrame.Angles(0, math.pi, 0) -- meshes whose tip is +Z (Blender +Y): lookAt points -Z
local UP = Vector3.yAxis

-- Hook fields on the server's attack record. Missing fields simply mean the event did not happen, so the
-- matching layer stays off (rulings: effects only play from confirmed events):
--   SlowUntil (R01), PoisonUntil (R04), PullUntil (E03), ChainDistances (R02), CopiedCell (E02),
--   TransformedCell (L02), Detonated + BlastRadius (E01), Critical (M01), SupportCells (R05).
local STATUS_FIELD = { Frost = "SlowUntil", Venom = "PoisonUntil", Gravity = "PullUntil" }
local conditions = {
	laneZero = function(shot)
		return shot.visualLane == 0
	end,
	detonated = function(shot)
		return shot.attack.Detonated == true
	end,
	forged = function(shot)
		return shot.transformedCell ~= nil
	end,
	copied = function(shot)
		return shot.copiedCell ~= nil
	end,
}

local CHAIN_OPACITY = RarityStyles.curve({ 0, 0 }, { 0.035, 1 }, { 0.2, 0, "quadOut" })
local LINK_OPACITY = RarityStyles.curve({ 0, 0.8 }, { 0.1, 0.8 }, { 0.3, 0 })

local rng = Random.new()
local limiters = {}
for _, style in RarityStyles.Styles do
	limiters[style.name] = Fx.Limiter(MAX_SHOTS)
end
local loopLimiter = Fx.Limiter(LOOP_CAP)
local statuses = { Frost = {}, Venom = {}, Gravity = {} }
local chronoAuras = {}
local auraReducedMotion = false

-- Helpers ------------------------------------------------------------------------------------------------------

local function colorAt(colors, u: number): Color3
	local n = #colors
	if n == 1 then
		return colors[1]
	end
	local at = math.clamp(u, 0, 1) * (n - 1)
	local i = math.min(math.floor(at), n - 2)
	return colors[i + 1]:Lerp(colors[i + 2], at - i)
end

local function meshSize(key: string): Vector3
	return Fx.Meshes[key].Size
end

local function toVector(size): Vector3
	return if typeof(size) == "number" then Vector3.one * size else size
end

local function borrow(key: string, parent: Instance, color: Color3, cf: CFrame?, size: Vector3?): MeshPart?
	return Fx.Part(key, {
		Parent = parent,
		Color = color,
		Material = NEON,
		Transparency = 1,
		CFrame = cf,
		Size = size,
	})
end

local function releaseTrail(handle)
	handle.trail.MaxLength = 0 -- FxLib's pooled trails never set it: leave none behind
	Fx.ReleaseTrail(handle)
end

local function releaseParts(list)
	for i = #list, 1, -1 do
		Fx.Release(list[i])
		list[i] = nil
	end
end

local function releaseItems(list)
	for i = #list, 1, -1 do
		Fx.Release(list[i].part)
		list[i] = nil
	end
end

-- Teardown ------------------------------------------------------------------------------------------------------

local function dropFlight(v)
	for i = #v.trails, 1, -1 do
		releaseTrail(v.trails[i])
		v.trails[i] = nil
	end
	releaseParts(v.followers)
	releaseParts(v.dots)
	if v.core then
		Fx.Release(v.core)
		v.core = nil
	end
end

local function teardown(v)
	dropFlight(v)
	releaseItems(v.items)
	for i = #v.beams, 1, -1 do
		Fx.ReleaseBeam(v.beams[i].handle)
		v.beams[i] = nil
	end
	if v.coreBeam then
		Fx.ReleaseBeam(v.coreBeam)
		v.coreBeam = nil
	end
end

-- Create / begin ------------------------------------------------------------------------------------------------

function RarityEffects.Create(style, dot)
	dot.Transparency = 1
	return {
		style = style,
		profile = style.profile,
		dot = dot,
		trails = {},
		followers = {},
		dots = {},
		items = {},
		beams = {},
		began = false,
		impacting = false,
		skip = false,
		finished = false,
		handle = nil,
		core = nil,
		coreBeam = nil,
		k = 1,
		tier = "High",
	}
end

-- Registers the shot with the shared loop (per-style MAX_SHOTS + global cap). False = flourish dropped.
local function begin(v, shot): boolean
	v.began = true
	v.tier = Fx.Tier(shot.reducedMotion)
	v.k = Fx.Scale(DiceVisuals.Size(shot.attack.Type))
	v.handle = Fx.Run(function()
		return v.finished
	end, function()
		teardown(v)
	end, limiters[v.style.name])
	if v.handle == nil then
		v.skip = true
		return false
	end
	return true
end

local function usable(v): boolean
	return not v.skip and not v.finished and v.handle ~= nil and not v.handle.isDone()
end

local function allowed(v, role: string): boolean
	return Fx.LayerAllowed(v.tier, role)
end

-- Flight ---------------------------------------------------------------------------------------------------------

local function corePose(v, shot, position: Vector3, t: number, progress: number)
	local cfg = v.profile.core
	local dir = shot.travelFrame.LookVector
	local f = 1
	if cfg.scale then
		f = Fx.Sample(cfg.scale, if cfg.scaleByProgress then progress else t)
	end
	local remaining = shot.flight - t
	if cfg.shrink and remaining < cfg.shrink then
		f *= math.max(remaining, 0) / cfg.shrink
	end
	if cfg.twinkle then
		f *= 1 + cfg.twinkle * math.sin(t * TAU * 3)
	end
	local opacity = 1
	if cfg.fadeIn then
		opacity = math.min(progress / cfg.fadeIn, 1)
	end
	if cfg.fadeOut and progress > cfg.fadeOut then
		opacity = math.max(1 - (progress - cfg.fadeOut) / (1 - cfg.fadeOut), 0)
	end
	local spin = if shot.reducedMotion then 0 else (cfg.spin or 0) * t
	local aim = cfg.aim
	local cf
	if aim == "orb" then
		cf = CFrame.new(position)
	elseif aim == "z" then
		cf = CFrame.lookAt(position, position + dir) * CFrame.Angles(0, 0, spin) * FLIP
	elseif aim == "y" then
		cf = CFrame.lookAt(position, position + dir) * CFrame.Angles(-math.pi / 2, 0, 0) * CFrame.Angles(0, spin, 0)
	elseif aim == "flat" then
		local base = Fx.FaceCamera(CFrame.new(position))
		local local_ = base:VectorToObjectSpace(dir)
		cf = Fx.FaceCamera(CFrame.new(position), math.atan2(local_.X, local_.Z))
	else
		cf = Fx.FaceCamera(CFrame.new(position), spin)
	end
	return cf, toVector(cfg.size) * (f * v.k), 1 - opacity
end

local function addTrails(v)
	local cfg = v.profile.core
	local across = if cfg.xTrail then Vector3.yAxis else Vector3.xAxis
	local wide = if cfg.xTrail then Vector3.xAxis else Vector3.yAxis
	for _, def in v.profile.trails do
		local width = def.width * v.k
		local handle = Fx.Trail(v.core, {
			Color = def.c0,
			Lifetime = def.life,
			Width = width,
			LightEmission = def.light,
			Transparency = def.transparency or 0.1,
		})
		if handle == nil then
			break
		end
		handle.trail.Color = ColorSequence.new(def.c0, def.c1)
		handle.trail.MaxLength = def.length * v.k
		local offset = across * ((def.offset or 0) * v.k)
		handle.a0.Position = offset + wide * (width / 2)
		handle.a1.Position = offset - wide * (width / 2)
		table.insert(v.trails, handle)
	end
end

local function addFlightExtras(v, shot)
	local profile = v.profile
	if profile.followers then
		for _ = 1, profile.followers.count do
			local part = borrow(profile.followers.mesh, shot.parent, profile.followers.color)
			if part == nil then
				break
			end
			table.insert(v.followers, part)
		end
	end
	if profile.dots then
		for i = 1, profile.dots.count do
			local part = borrow(profile.dots.mesh, shot.parent, profile.dots.colors[(i - 1) % #profile.dots.colors + 1])
			if part == nil then
				break
			end
			table.insert(v.dots, part)
		end
	end
	local beam = profile.coreBeam
	if beam then
		local handle = Fx.Beam(workspace.Terrain, workspace.Terrain, {
			Width0 = beam.width0 * v.k,
			Width1 = beam.width1 * v.k,
			LightEmission = 1,
			Transparency = 0.2,
		})
		if handle then
			handle.beam.Color = ColorSequence.new(beam.c0, beam.c1)
			v.coreBeam = handle
		end
	end
end

local function updateFollowers(v, shot, position: Vector3, t: number)
	local cfg = v.profile.followers
	local dir = shot.travelFrame.LookVector
	local right, up = shot.travelFrame.RightVector, shot.travelFrame.UpVector
	local count = #v.followers
	for i, part in v.followers do
		local cycle = t / cfg.cycle + (i - 1) / count
		local index = math.floor(cycle)
		local phase = cycle - index
		local angle = index * 2.4 + i
		local drift = (0.15 + 0.35 * phase) * v.k
		local p = position
			- dir * ((0.4 + phase * 0.9) * v.k)
			+ (right * math.cos(angle) + up * math.sin(angle)) * drift
		part.CFrame = CFrame.lookAt(p, p - dir) * CFrame.Angles(-math.pi / 2, 0, 0)
		part.Size = meshSize(cfg.mesh) * (cfg.scale * v.k * math.max(1 - phase, 0.01))
		part.Transparency = 0
	end
end

local function updateDots(v, shot, progress: number)
	local cfg = v.profile.dots
	local length = (shot.surface - shot.from).Magnitude
	local travelled = progress * length
	local newest = math.floor(travelled / cfg.spacing)
	local dir = shot.travelFrame.LookVector
	local right, up = shot.travelFrame.RightVector, shot.travelFrame.UpVector
	for j, part in v.dots do
		local index = newest - ((newest - (j - 1)) % cfg.count)
		local age = if index >= 0 then (travelled - index * cfg.spacing) / shot.style.speed else -1
		local f = 0
		if age >= 0 then
			f = if age < 0.05 then age / 0.05 else math.max(1 - (age - 0.05) / 0.25, 0)
		end
		if f <= 0.01 then
			part.Transparency = 1
		else
			local p = shot.from
				+ dir * (index * cfg.spacing)
				+ (right * math.sin(index * 2.1) + up * math.cos(index * 1.7)) * (0.35 * v.k)
			part.CFrame = CFrame.new(p)
			part.Size = meshSize(cfg.mesh) * (cfg.size * f * v.k)
			part.Transparency = 0
		end
	end
end

function RarityEffects.Travel(shot, position: Vector3, progress: number)
	local v = shot.visuals
	if v.finished or v.skip then
		return
	end
	if not v.began and not begin(v, shot) then
		v.dot.Transparency = 0 -- over the cap: the plain projectile still shows, only the flourish is dropped
		return
	end
	if not usable(v) then
		return
	end
	local t = progress * shot.flight
	local cf, size, transparency = corePose(v, shot, position, t, progress)
	if v.core == nil then
		if v.coreTried then
			return
		end
		v.coreTried = true
		v.core = borrow(v.profile.core.mesh, shot.parent, v.profile.core.color, cf, size)
		if v.core == nil then
			v.dot.Transparency = 0 -- mesh still loading: fall back to the caller's plain projectile
			return
		end
		if allowed(v, "trail") then
			addTrails(v)
			addFlightExtras(v, shot)
		end
	end
	local core = v.core
	core.CFrame, core.Size, core.Transparency = cf, size, transparency
	if v.profile.followers and #v.followers > 0 then
		updateFollowers(v, shot, position, t)
	end
	if v.profile.dots and #v.dots > 0 then
		updateDots(v, shot, progress)
	end
	if v.coreBeam then
		v.coreBeam.a0.Position = shot.from
		v.coreBeam.a1.Position = position
	end
end

-- Impact ---------------------------------------------------------------------------------------------------------

local function jitter(): number
	return (rng:NextNumber() * 2 - 1) * 0.6
end

local function addBeam(v, props, a0: Vector3, a1: Vector3, extra)
	local handle = Fx.Beam(workspace.Terrain, workspace.Terrain, props)
	if handle == nil then
		return
	end
	handle.a0.Position, handle.a1.Position = a0, a1
	local entry = { handle = handle, from = a0, to = a1 }
	for key, value in extra or {} do
		entry[key] = value
	end
	table.insert(v.beams, entry)
end

local function addItems(v, shot)
	local profile = v.profile
	for _, layer in profile.impact do
		local loaded = layer.role == "support"
			and profile.supportLoad ~= nil
			and Fx.Live() >= profile.supportLoad * Fx.GLOBAL_CAP
		if allowed(v, layer.role) and not loaded and (not layer.when or conditions[layer.when](shot)) then
			for i = 1, layer.count or 1 do
				local color = if layer.alternate then layer.colors[(i - 1) % #layer.colors + 1] else layer.colors[1]
				local part = borrow(layer.mesh, shot.parent, color)
				if part == nil then
					break
				end
				table.insert(v.items, { part = part, L = layer, i = i })
			end
		end
	end
	if profile.neighbor and allowed(v, "support") then
		for i, cell in shot.supportCells or {} do
			local part = borrow(profile.neighbor.mesh, shot.parent, profile.neighbor.colors[1])
			if part == nil then
				break
			end
			local center = Layout.CellPosition(cell, shot.attack.Seat, shot.attack.PlayerCount) - UP * 0.53
			table.insert(v.items, { part = part, L = profile.neighbor, i = i, origin = center })
		end
	end
	local low = not allowed(v, "support")
	local chain = profile.chain
	if chain and shot.links then
		for i, distance in shot.links do
			if i > chain.max or (low and i > 1) then
				break -- Low tier keeps ONE thin link (no core beam)
			end
			local finish = Layout.PositionAt(distance, shot.enemySeat, shot.playerCount) + UP * shot.lift
			local width = if low then chain.width * 0.5 else chain.width
			local props = { Color = chain.color, Width0 = width * v.k, Segments = 7, LightEmission = 1 }
			addBeam(v, props, shot.center, finish, { kind = "chain", c = jitter(), rerolled = false })
			if not low then
				props = { Color = chain.core, Width0 = chain.coreWidth * v.k, Segments = 7, LightEmission = 1 }
				addBeam(v, props, shot.center, finish, { kind = "chain", c = jitter(), rerolled = false })
			end
		end
	end
	if low then
		return
	end
	local link = profile.link
	if link and shot.copiedCell then
		local source = shot.from + UP * 0.3
		addBeam(v, {
			Color = link.color,
			Width0 = link.width * v.k,
			Segments = 8,
			CurveSize0 = link.curve * v.k,
			CurveSize1 = -link.curve * v.k,
			LightEmission = 0.7,
		}, source, source, { kind = "link", target = shot.center })
	end
end

local function startImpact(v, shot, facing: CFrame)
	v.impacting = true
	if not v.began and not begin(v, shot) then
		return
	end
	local holdCore = v.core ~= nil and v.profile.core.hold ~= nil
	if holdCore then
		for i = #v.trails, 1, -1 do
			releaseTrail(v.trails[i])
			v.trails[i] = nil
		end
		releaseParts(v.followers)
		releaseParts(v.dots)
	else
		dropFlight(v)
	end
	local hit = facing.Position
	local ground = shot.ground
	local radius = shot.attack.BlastRadius
	local ctx = {
		k = v.k,
		shot = shot,
		ground = ground,
		hit = hit,
		seed = rng:NextNumber() * TAU,
		roll = rng:NextNumber() * TAU,
		roll2 = rng:NextNumber() * TAU,
		critical = shot.attack.Critical == true and not shot.reducedMotion,
		blast = if radius then math.clamp(radius / 1.75, 0.5, 3) else 1,
	}
	ctx.hitCtx = { k = v.k, shot = shot, ground = hit, seed = ctx.seed }
	v.ctx = ctx
	addItems(v, shot)
end

-- Draws one impact layer; returns false once it has finished (the caller releases the part).
local function drawItem(item, age: number, ctx, reduced: boolean): boolean
	local layer, part = item.L, item.part
	local t = age - (layer.delay or 0)
	if t < 0 then
		part.Transparency = 1
		return true
	end
	if t >= layer.dur then
		return false
	end
	local f = Fx.Sample(layer.scale, t)
	local fy = if layer.scaleY then Fx.Sample(layer.scaleY, t) else f
	if f <= 0.003 and fy <= 0.003 then
		part.Transparency = 1
		return true
	end
	local mul = ctx.k
	if layer.critical and ctx.critical then
		mul *= layer.critical
	end
	if layer.blast then
		mul *= ctx.blast
	end
	local full = toVector(layer.full)
	part.Size = meshSize(layer.mesh) * Vector3.new(full.X * f, full.Y * fy, full.Z * f) * mul
	local opacity = if layer.opacity then Fx.Sample(layer.opacity, t) else 1
	if layer.role == "flash" then
		opacity = Fx.FlashOpacity(reduced, opacity)
	end
	part.Transparency = 1 - opacity
	if #layer.colors > 1 and not layer.alternate then
		part.Color = colorAt(layer.colors, t / layer.dur)
	end
	local spin = if reduced then 0 else (layer.spin or 0) * t
	local origin = item.origin or ctx.ground
	local cf
	if layer.motion then
		local c = if layer.at == "hit" then ctx.hitCtx else ctx
		local u = t / layer.dur
		local pos = layer.motion(item.i, u, c, layer.count)
		if layer.align then
			local ahead = layer.motion(item.i, math.min(u + 0.06, 1), c, layer.count)
			local dir = if u < 0.94 then ahead - pos else pos - layer.motion(item.i, u - 0.06, c, layer.count)
			if dir.Magnitude < 1e-3 then
				dir = UP
			end
			cf = CFrame.lookAt(pos, pos + dir)
				* (if layer.align == "y" then CFrame.Angles(-math.pi / 2, 0, 0) else FLIP)
		elseif layer.tumble and not reduced then
			cf = CFrame.new(pos) * CFrame.Angles(u * 5 + item.i, u * 7 + item.i * 2, item.i)
		else
			cf = CFrame.new(pos)
		end
	elseif layer.orient == "ground" then
		cf = CFrame.new(origin + UP * 0.05)
	elseif layer.orient == "upright" then
		local yaw = (if layer.roll then ctx.roll else 0) + spin
		cf = CFrame.new(origin + UP * (layer.pivotUp * fy * mul)) * CFrame.Angles(0, yaw, 0)
	elseif layer.orient == "yaw" then
		local pos = ctx.hit + UP * (layer.pivotUp * fy * mul)
		local camera = workspace.CurrentCamera
		cf = if camera
			then CFrame.lookAt(pos, Vector3.new(camera.CFrame.Position.X, pos.Y, camera.CFrame.Position.Z))
			else CFrame.new(pos)
	else -- "camera"
		local roll = spin
		if layer.roll == "random" then
			roll += if layer.reroll and t >= layer.reroll then ctx.roll2 else ctx.roll
		end
		cf = Fx.FaceCamera(CFrame.new(ctx.hit), roll)
		if layer.startPivot then
			cf *= CFrame.new(layer.startPivot * full.X * f * mul, 0, 0)
		end
	end
	part.CFrame = cf
	return true
end

local function drawBeams(v, shot, age: number)
	for i = #v.beams, 1, -1 do
		local entry = v.beams[i]
		local beam = entry.handle.beam
		local opacity, done
		if entry.kind == "chain" then
			opacity = Fx.Sample(CHAIN_OPACITY, age)
			if shot.reducedMotion then
				opacity = math.min(opacity, 0.7)
			end
			done = age >= v.profile.chain.dur
			if not entry.rerolled and age >= 0.1 then
				entry.rerolled = true
				entry.c = jitter()
			end
			beam.CurveSize0, beam.CurveSize1 = entry.c * v.k, -entry.c * v.k
		else
			local link = v.profile.link
			opacity = Fx.Sample(LINK_OPACITY, age)
			done = age >= link.dur or not shot.target.Parent
			entry.handle.a1.Position = entry.from:Lerp(entry.target, math.min(age / link.draw, 1))
		end
		if done then
			Fx.ReleaseBeam(entry.handle)
			table.remove(v.beams, i)
		else
			beam.Transparency = NumberSequence.new(1 - opacity)
		end
	end
end

function RarityEffects.Impact(shot, age: number, facing: CFrame)
	local v = shot.visuals
	if v.finished or v.skip then
		return
	end
	if not v.impacting then
		startImpact(v, shot, facing)
	end
	if not usable(v) then
		return
	end
	local reduced = shot.reducedMotion
	local ctx = v.ctx
	local cfg = v.profile.core
	if v.core then -- E02: the core shrinks away over the first 50 ms
		local f = 1 - age / cfg.hold
		if f > 0.02 then
			v.core.CFrame = CFrame.new(shot.surface)
			v.core.Size = toVector(cfg.size) * (f * v.k)
			v.core.Transparency = 0
		else
			Fx.Release(v.core)
			v.core = nil
		end
	end
	if v.coreBeam then -- M01: the core beam fades over 80 ms after the hit
		local tail = v.profile.coreBeam.tail
		if age >= tail then
			Fx.ReleaseBeam(v.coreBeam)
			v.coreBeam = nil
		else
			v.coreBeam.beam.Transparency = NumberSequence.new(0.2 + 0.8 * age / tail)
		end
	end
	local items = v.items
	for i = #items, 1, -1 do
		local item = items[i]
		if not drawItem(item, age, ctx, reduced) then
			Fx.Release(item.part)
			table.remove(items, i)
		end
	end
	if #v.beams > 0 then
		drawBeams(v, shot, age)
	end
end

function RarityEffects.Release(v)
	v.finished = true
	if v.handle then
		v.handle.cancel() -- runs teardown through the loop
	end
	teardown(v)
	v.handle, v.ctx = nil, nil
	v.began, v.impacting, v.skip, v.finished, v.coreTried = false, false, false, false, nil
	v.dot.Transparency = 1
end

-- Status loops -----------------------------------------------------------------------------------------------------

local function statusParts(name: string, profile, parent: Instance)
	local parts = {}
	local function add(key: string, color: Color3): boolean
		local part = borrow(key, parent, color)
		if part == nil then
			return false
		end
		table.insert(parts, part)
		return true
	end
	local cfg = profile.status
	if name == "Frost" then
		if not (add(cfg.flake.mesh, cfg.flake.color) and add(cfg.ring.mesh, cfg.ring.color)) then
			releaseParts(parts)
			return nil
		end
	elseif name == "Venom" then
		for _ = 1, cfg.bubbles.count do
			if not add(cfg.bubbles.mesh, cfg.bubbles.color) then
				releaseParts(parts)
				return nil
			end
		end
	elseif not add(cfg.vortex.mesh, cfg.vortex.color) then
		return nil
	end
	return parts
end

function RarityEffects.StartStatus(shot)
	local name = shot.style.name
	local field = STATUS_FIELD[name]
	local target = shot.target
	if not field or not target or not target.Parent then
		return
	end
	local expires = shot.attack[field]
	if not expires or expires <= workspace:GetServerTimeNow() then
		return
	end
	local active = statuses[name]
	local entry = active[target]
	if entry then
		entry.expires = math.max(entry.expires, expires) -- a refresh extends the one marker
		return
	end
	local k = Fx.Scale(DiceVisuals.Size(shot.attack.Type))
	local parts = statusParts(name, shot.style.profile, shot.parent)
	if parts == nil then
		return
	end
	entry = {
		name = name,
		profile = shot.style.profile,
		parts = parts,
		parent = shot.parent,
		expires = expires,
		start = workspace:GetServerTimeNow(),
		tail = if name == "Venom" then shot.style.profile.status.bubbles.cycle else 0,
		groundY = shot.ground.Y,
		k = k,
		shown = true,
		done = false,
	}
	entry.handle = Fx.Run(function()
		return entry.done
	end, function()
		releaseParts(entry.parts)
		if active[target] == entry then
			active[target] = nil
		end
	end, loopLimiter)
	if entry.handle == nil then
		releaseParts(entry.parts)
		return
	end
	active[target] = entry
end

local function drawFrost(e, target: BasePart, now: number, low: boolean)
	local cfg = e.profile.status
	local age, remaining = now - e.start, e.expires - now
	local fade = math.clamp(remaining / 0.15, 0, 1)
	local pop = if low then 1 else 0.6 + 0.4 * math.clamp(age / 0.1, 0, 1)
	local f = math.max(pop * fade, 0.01)
	local flake, ring = e.parts[1], e.parts[2]
	local top = target.Position + UP * (target.Size.Y / 2 + cfg.flake.above)
	flake.CFrame = Fx.FaceCamera(CFrame.new(top), if low then 0 else cfg.flake.spin * age)
	flake.Size = meshSize(cfg.flake.mesh) * f
	flake.Transparency = 0
	local diameter = math.max(cfg.ring.diameter, target.Size.X * 1.3)
	ring.CFrame = CFrame.new(target.Position - UP * (target.Size.Y / 2 - 0.06))
	ring.Size = meshSize(cfg.ring.mesh) * (diameter * f)
	ring.Transparency = cfg.ring.transparency
end

local function drawVenom(e, target: BasePart, now: number, low: boolean)
	local cfg = e.profile.status.bubbles
	local count = #e.parts
	for i, part in e.parts do
		local cycle = now / cfg.cycle + (i - 1) / count
		local index = math.floor(cycle)
		local u = if low then 0.45 else cycle - index
		local startedAt = (index - (i - 1) / count) * cfg.cycle
		if not low and startedAt > e.expires then
			part.Transparency = 1 -- poison ended: no new bubbles, live ones already finished
		else
			local f = math.min(0.5 + 0.5 * u / 0.33, 1) * (if u > 0.33 then 1 - (u - 0.33) / 0.67 else 1)
			local angle = (if low then 0 else index * 2.4) + i * 2.1
			local p = target.Position
				+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * (target.Size.X * 0.45)
				- UP * (target.Size.Y * 0.3)
				+ UP * (u * cfg.rise)
			part.CFrame = CFrame.new(p)
			part.Size = meshSize(cfg.mesh) * (cfg.sizes[i] * math.max(f, 0.01) * e.k)
			part.Transparency = 0.65
		end
	end
end

local function drawVortex(e, target: BasePart, now: number, low: boolean)
	local cfg = e.profile.status.vortex
	local age, remaining = now - e.start, e.expires - now
	local grow = Fx.Easing.quadOut(age / 0.1)
	local shrink = Fx.Easing.quadIn(math.clamp(remaining / 0.2, 0, 1))
	local f = math.max(grow * shrink, 0.01)
	local part = e.parts[1]
	-- eases in (quadIn) through 720 degrees over spinEase seconds, then keeps the final speed while the pull lasts
	local u = age / cfg.spinEase
	local spin = 0
	if not low then
		spin = if u < 1
			then cfg.spinTurn * Fx.Easing.quadIn(u)
			else cfg.spinTurn + 2 * cfg.spinTurn / cfg.spinEase * (age - cfg.spinEase)
	end
	part.CFrame = CFrame.new(target.Position.X, e.groundY + 0.1, target.Position.Z) * CFrame.Angles(0, spin, 0)
	part.Size = meshSize(cfg.mesh) * (f * e.k)
	part.Transparency = 0
end

local drawers = { Frost = drawFrost, Venom = drawVenom, Gravity = drawVortex }

function RarityEffects.StepStatus(now: number, reducedMotion: boolean)
	local camera = workspace.CurrentCamera
	local low = Fx.Tier(reducedMotion) == "Low"
	for name, active in statuses do
		for target, e in active do
			if not target.Parent or now >= e.expires + e.tail then
				e.done = true
				e.handle.cancel() -- parts back to the pool, entry removed
			else
				local visible = camera == nil or select(2, camera:WorldToViewportPoint(target.Position))
				if visible ~= e.shown then
					e.shown = visible
					for _, part in e.parts do
						part.Parent = if visible then e.parent else nil
					end
				end
				if visible then
					drawers[name](e, target, now, low)
				end
			end
		end
	end
end

function RarityEffects.ClearStatus()
	for _, active in statuses do
		local entries = {}
		for _, e in active do
			table.insert(entries, e)
		end
		for _, e in entries do
			e.done = true
			e.handle.cancel()
		end
	end
end

-- Chrono support auras: one ring per real supported ally ------------------------------------------------------------

local function removeAura(cell: number, aura)
	chronoAuras[cell] = nil
	if Fx.Tier(auraReducedMotion) == "Low" then
		aura.handle.cancel()
	else
		aura.leaving = os.clock() -- the loop shrinks it away over 200 ms, then releases it
	end
end

local function newAura(cell: number, parent: Instance, center: Vector3)
	local cfg = RarityStyles.Profiles.L01.aura
	local part = borrow(cfg.mesh, parent, cfg.color, CFrame.new(center))
	if part == nil then
		return nil
	end
	local base = meshSize(cfg.mesh)
	local aura = { part = part, leaving = nil }
	aura.handle = Fx.Run(function()
		local low = Fx.Tier(auraReducedMotion) == "Low"
		if aura.leaving then
			local p = (os.clock() - aura.leaving) / cfg.exit
			if p >= 1 then
				return true
			end
			part.Size = base * math.max(1 - p, 0.01)
			part.Transparency = 0.55 + 0.45 * p
			return false
		end
		local opacity = if low then 0.45 else 0.45 + 0.10 * math.sin(os.clock() * TAU / 1.2)
		part.Transparency = 1 - opacity
		return false
	end, function()
		Fx.Release(part)
		if chronoAuras[cell] == aura then
			chronoAuras[cell] = nil
		end
	end, loopLimiter)
	if aura.handle == nil then
		Fx.Release(part)
		return nil
	end
	return aura
end

function RarityEffects.SetChronoAllies(parent: Instance, cells, seat, playerCount)
	local keep = {}
	for _, cell in cells or {} do
		keep[cell] = true
		if not chronoAuras[cell] then
			local center = Layout.CellPosition(cell, seat, playerCount) - UP * 0.53
			chronoAuras[cell] = newAura(cell, parent, center)
		end
	end
	for cell, aura in chronoAuras do
		if not keep[cell] then
			removeAura(cell, aura)
		end
	end
end

function RarityEffects.StepChrono(reducedMotion: boolean)
	auraReducedMotion = reducedMotion -- the shared loop animates the rings; this only carries the setting
end

return RarityEffects
