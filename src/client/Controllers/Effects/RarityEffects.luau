local Layout = require(game:GetService("ReplicatedStorage").Shared.Layout)
local ProjectileScale = require(script.Parent.ProjectileScale)
local Meshes = require(script.Parent.RarityMeshes)
local Textures = require(script.Parent.RarityTextures)

local RarityEffects = {}
local IMPACT_SCALE = ProjectileScale.Impact
local IMPACT_WEIGHT = 1.5 * ProjectileScale.ImpactWeight
local CORE_SIZE = ProjectileScale.Flight * 0.19
local FLIGHT_SCALE = CORE_SIZE / 0.665
local TAU = math.pi * 2
local DURATION = 0.30
local HIDDEN = 1
local chronoAuras = {}
local statuses = { Frost = {}, Venom = {} }
local WHITE = Color3.new(1, 1, 1)
local CYAN = Color3.fromHex("82E9FF")
local VIOLET = Color3.fromHex("B967FF")
local LEAF = Color3.fromHex("B7FF3A")
local FLAME = Color3.fromHex("FFD33A")

-- Length, width, sideways offset, height, curve and optional highlight.
local TAILS = {
	Frost = { { 2.9, 0.13, 0, 0 }, { 2.2, 0.07, 0.13, 0.19 }, { 1.8, 0.07, -0.16, -0.16 } },
	Arc = { { 2.8, 0.15, 0, 0 }, { 1.9, 0.06, 0.12, 0.13 }, { 2.2, 0.06, -0.13, -0.11 } },
	Volley = { { 2.8, 0.12, 0, 0 }, { 1.9, 0.06, 0.08, 0.13 }, { 1.6, 0.06, -0.06, -0.11 } },
	Venom = { { 2.2, 0.24, 0, 0, 0.42, LEAF }, { 1.8, 0.14, -0.08, -0.1, -0.38 } },
	Beacon = { { 2.2, 0.13, 0, 0, 0, FLAME }, { 1.8, 0.055, 0.12, 0.13 } },
	Emberstorm = {
		{ 3.0, 0.31, -0.10, 0.11, 0.60, FLAME },
		{ 2.6, 0.25, 0.12, -0.11, -0.56 },
		{ 2.2, 0.15, 0.08, 0.1, 0.35 },
	},
	Mirror = { { 2.0, 0.13, 0, 0, 0.14 }, { 1.6, 0.072, 0.12, 0.1, -0.17 } },
	Gravity = { { 2.7, 0.12, 0, 0 }, { 2.0, 0.055, 0.12, 0.11 }, { 1.8, 0.055, -0.11, -0.12 } },
	Chrono = { { 2.5, 0.14, 0, 0 }, { 2.0, 0.07, 0.13, 0.17 }, { 1.7, 0.065, -0.12, -0.14 } },
	Forge = { { 2.7, 0.13, 0, 0, 0, FLAME }, { 2.2, 0.065, 0.16, 0.14 }, { 1.8, 0.06, -0.10, -0.13 } },
	Astral = { { 3.5, 0.23, 0, 0, 0, CYAN }, { 2.6, 0.07, -0.09, 0.14, -0.13, VIOLET } },
}

local function style(name, shape, rays, color, streak, ring, accent, flash)
	return {
		name = name,
		detail = shape,
		rays = rays,
		color = Color3.fromHex(color),
		streak = Color3.fromHex(streak),
		glow = Color3.fromHex(ring),
		accent = Color3.fromHex(accent),
		burstColor = Color3.fromHex(flash),
		pool = {},
		speed = 150,
		size = 0.19,
	}
end

RarityEffects.Styles = {
	R01 = style("Frost", "Crystal", 6, "7FEFFF", "00D9FF", "00D9FF", "0A6FBF", "EFFFFF"),
	R02 = style("Arc", "Orb", 8, "D77BFF", "D77BFF", "9A40FF", "4A0FB9", "F8E6FF"),
	R03 = style("Volley", "Bolt", 3, "FF7A7A", "FF3B3B", "FF3B3B", "B7192A", "FFF6F6"),
	R04 = style("Venom", "Orb", 5, "55D20A", "B7FF3A", "55D20A", "2B6E00", "E8FFB4"),
	R05 = style("Beacon", "Orb", 5, "FFC400", "FF9A00", "FFC400", "6B4A00", "FFF08A"),
	E01 = style("Emberstorm", "Ember", 7, "FFD33A", "FF8A00", "FF8A00", "FF4A00", "FFF7A3"),
	E02 = style("Mirror", "Orb", 8, "00FFE6", "E6FFFF", "00BDAA", "007D75", "AFFFFF"),
	E03 = style("Gravity", "Orb", 5, "7A3BFF", "C67AFF", "C67AFF", "3A0C7A", "F5E8FF"),
	L01 = style("Chrono", "Diamond", 8, "00FFF6", "00C4BD", "00C4BD", "007F7A", "E6FFFF"),
	L02 = style("Forge", "Diamond", 6, "FFD34D", "FF8A00", "FF8A00", "C24B00", "FFF7B2"),
	M01 = style("Astral", "Star", 8, "F7B6FF", "5E6BFF", "B967FF", "1B0D4A", "FFFFFF"),
}

local function piece(parent, name, color, shape)
	local part = Instance.new(if shape == "Wedge" then "WedgePart" else "Part")
	if shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	end
	part.Name = name
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CastShadow = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = HIDDEN
	part.Parent = parent
	return part
end

local function pieces(count, parent, name, color, shape)
	local items = table.create(count)
	for i = 1, count do
		items[i] = piece(parent, name, color, shape)
	end
	return items
end

local function ring(parent, color, secondary)
	local part = piece(parent, "GroundRing", color)
	local canvas = Instance.new("SurfaceGui")
	canvas.Face = Enum.NormalId.Top
	canvas.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	canvas.PixelsPerStud = 48
	canvas.LightInfluence = 0
	canvas.Enabled = false
	canvas.Parent = part
	local rim = Instance.new("Frame")
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.fromScale(0.93, 0.93)
	rim.BackgroundTransparency = 1
	rim.Parent = canvas
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = rim
	local feather = rim:Clone()
	feather.Parent = canvas
	local function rimStroke(frame, front)
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = front
		stroke.Parent = frame
		if secondary then
			local gradient = Instance.new("UIGradient")
			gradient.Color = ColorSequence.new(front, secondary)
			stroke.Color = WHITE
			gradient.Parent = stroke
		end
		return stroke
	end
	local stroke = rimStroke(rim, color:Lerp(WHITE, 0.38))
	local glow = rimStroke(feather, color)
	rim.ZIndex = feather.ZIndex + 1
	return { part = part, canvas = canvas, stroke = stroke, glow = glow }
end

local function beam(parent, color, width, falloff, bend)
	local near, far = Instance.new("Attachment"), Instance.new("Attachment")
	near.Parent, far.Parent = parent, parent
	local ribbon = Instance.new("Beam")
	ribbon.Attachment0, ribbon.Attachment1 = near, far
	ribbon.Enabled = false
	ribbon.FaceCamera = true
	ribbon.LightEmission = 0.83
	ribbon.LightInfluence = 0
	ribbon.Color = color
	ribbon.Width0, ribbon.Width1 = width, width * falloff
	ribbon.CurveSize0, ribbon.CurveSize1 = bend, -bend * 0.66
	ribbon.Segments = if bend == 0 then 1 else 8
	ribbon.Parent = parent
	return { near = near, far = far, part = ribbon }
end

local function fadeRibbon(ribbon, alpha, tail)
	ribbon.part.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - alpha),
		NumberSequenceKeypoint.new(0.58, 1 - alpha * 0.62),
		NumberSequenceKeypoint.new(1, 1 - alpha * tail),
	})
end

local function show(part, frame, size, opacity)
	part.CFrame, part.Size, part.Transparency = frame, size, 1 - math.clamp(opacity, 0, 1)
end

local function line(part, from, to, width, opacity)
	local delta = to - from
	local length = delta.Magnitude
	if length < 0.01 then
		part.Transparency = HIDDEN
		return
	end
	local up = if math.abs(delta.Y) > 0.98 * length then Vector3.zAxis else Vector3.yAxis
	show(part, CFrame.lookAt((from + to) / 2, to, up), Vector3.new(width, width, length), opacity)
end

local function polar(angle, radius, height)
	return Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
end

local function poseMesh(parts, mesh, frame, scale, opacity)
	for i, wedge in mesh do
		local origin = wedge[1]
		show(parts[i], frame * (origin.Rotation + origin.Position * scale), wedge[2] * scale, opacity)
	end
end

function RarityEffects.Create(style, dot)
	local root = Instance.new("Folder")
	root.Name = style.name .. "VFX"
	local travel = Instance.new("Folder")
	travel.Name = "Flight"
	local burst = Instance.new("Folder")
	burst.Name = "ImpactFlash"
	local shape = style.detail
	local mesh = Meshes[shape]
	local visuals = {
		root = root,
		travel = travel,
		burst = burst,
		core = pieces(
			if mesh then #mesh else 1,
			travel,
			shape,
			style.color,
			if shape == "Orb" then "Ball" else "Wedge"
		),
		ring = ring(root, style.glow, if style.name == "Astral" then Color3.fromHex("82E9FF") else nil),
	}
	if shape == "Crystal" or shape == "Diamond" or shape == "Ember" then
		for i, wedge in mesh do
			visuals.core[i].Color = if wedge[3] % 4 == 3
				then style.color:Lerp(style.accent, 0.52)
				elseif wedge[3] % 2 == 0 then style.color:Lerp(style.burstColor, 0.54)
				else style.color
		end
	elseif shape == "Star" or shape == "Bolt" then
		for _, part in visuals.core do
			part.Color = if shape == "Star" then style.burstColor else style.color:Lerp(style.burstColor, 0.65)
		end
	else
		visuals.highlight = piece(travel, "OrbHighlight", style.burstColor, "Ball")
	end
	local name = style.name
	local ribbonAnchor = piece(travel, "TrailAnchor", style.streak)
	visuals.ribbons = {}
	for i, profile in TAILS[name] do
		local edge = profile[6] or style.streak
		local near = edge:Lerp(style.burstColor, if i == 1 then 0.75 else 0.26)
		local ribbon =
			beam(ribbonAnchor, ColorSequence.new(near, edge), profile[2] * FLIGHT_SCALE * 1.8, 0.06, profile[5] or 0)
		fadeRibbon(ribbon, if i == 1 then 0.94 else 0.69, 0)
		visuals.ribbons[i] = ribbon
	end
	if name == "Frost" then
		visuals.flakes = {}
		for i = 1, 3 do
			visuals.flakes[i] =
				Textures.Create(ribbonAnchor, "Snowflake", if i == 1 then style.burstColor else style.glow)
		end
		if not visuals.flakes[1] then
			visuals.snow = pieces(9, travel, "TrailSnow", style.burstColor)
		end
		visuals.shards = table.create(style.rays)
		for i = 1, style.rays do
			visuals.shards[i] =
				pieces(#Meshes.Shard, burst, "IceShard", if i % 2 == 0 then style.color else style.burstColor, "Wedge")
		end
	elseif name == "Arc" then
		visuals.links = pieces(15, root, "LightningGlow", style.glow)
		visuals.linkCores = pieces(15, root, "LightningCore", style.burstColor)
	elseif name == "Volley" then
		visuals.chips = pieces(4, root, "VolleyChip", style.streak, "Wedge")
	elseif name == "Venom" then
		visuals.poolRing = ring(root, style.accent)
		visuals.splash = pieces(style.rays, burst, "Splash", style.streak, "Ball")
		visuals.dust = pieces(3, travel, "SlimeDrop", style.color, "Ball")
	elseif name == "Beacon" then
		visuals.supportRing = ring(root, style.accent)
		visuals.supportRing.part.Name = "SupportPulse"
		visuals.neighbors = {}
		visuals.supportLinks = pieces(4, root, "SupportLink", style.glow)
		for i = 1, 4 do
			visuals.neighbors[i] = ring(root, style.accent:Lerp(style.glow, 0.65))
		end
	elseif name == "Emberstorm" or name == "Forge" then
		visuals.sparks = pieces(if name == "Forge" then 5 else 4, root, "RisingSpark", style.color, "Ball")
		visuals.flame = pieces(if name == "Forge" then 0 else 9, root, "FlameArc", style.accent)
		if name == "Forge" then
			visuals.anvil = pieces(#Meshes.Anvil, root, "AnvilSilhouette", style.color, "Wedge")
		end
		visuals.dust = pieces(3, travel, "TravelSpark", style.burstColor, "Ball")
	elseif name == "Mirror" then
		visuals.poolRing = ring(root, style.glow)
		local glassAnchor = piece(root, "GlassAnchor", style.color)
		visuals.glass = {
			beam(glassAnchor, ColorSequence.new(style.glow, style.color), 0.21, 0.70, 1.3),
			beam(glassAnchor, ColorSequence.new(style.color, style.burstColor), 0.12, 0.81, -1),
		}
	elseif name == "Gravity" then
		visuals.spiral = pieces(20, root, "Vortex", style.color)
		for i, segment in visuals.spiral do
			segment.Color = style.streak:Lerp(style.color, ((i - 1) % 10) * 0.054)
		end
		visuals.fragments = pieces(3, root, "VortexFragment", style.streak, "Wedge")
		visuals.dust = pieces(3, travel, "TravelLight", style.burstColor, "Ball")
	elseif name == "Chrono" then
		visuals.ticks = pieces(12, root, "ClockTick", style.burstColor)
	elseif name == "Astral" then
		visuals.dust = pieces(5, travel, "TrailStar", CYAN, "Ball")
		visuals.trailLinks = pieces(4, travel, "TrailLink", style.streak)
		visuals.stars = pieces(5, root, "ConstellationStar", style.burstColor, "Ball")
		visuals.lines = pieces(5, root, "ConstellationLink", VIOLET)
		visuals.pillars = pieces(5, root, "LightPillar", CYAN)
	end
	local haloColor = if shape == "Star" then VIOLET else style.streak
	visuals.halo = piece(travel, "ProjectileGlow", haloColor, "Ball")
	visuals.flightGlow = Textures.Create(visuals.halo, "Glow", haloColor)
	local flashAnchor = piece(burst, "FlashBloom", style.glow)
	visuals.hitGlow = Textures.Create(flashAnchor, "Glow", style.glow)
	if name == "Venom" then
		visuals.flash = piece(burst, "FlashCore", style.burstColor, "Ball")
	elseif name ~= "Frost" then
		visuals.flashMesh = Meshes.Flash(style.rays, name == "Beacon" or name == "Emberstorm" or name == "Forge")
		visuals.flash = pieces(
			#visuals.flashMesh,
			burst,
			"RadialFlash",
			style.burstColor:Lerp(style.color, if name == "Astral" then 0.06 else 0.23),
			"Wedge"
		)
	end
	dot.Transparency = HIDDEN
	return visuals
end

function RarityEffects.Travel(shot, position, progress)
	local visuals, style = shot.visuals, shot.style
	local frame = shot.travelFrame.Rotation + position
	local shape = style.detail
	local camera = workspace.CurrentCamera
	if shape == "Orb" then
		local diameter = CORE_SIZE * (if style.name == "Beacon" or style.name == "Venom" then 0.9 else 1)
		show(visuals.core[1], frame, Vector3.one * diameter, 1)
		local eye = if camera then camera.CFrame.Rotation else frame.Rotation
		local shine = position + (eye.LookVector * -0.80 + eye.UpVector * 0.37 - eye.RightVector * 0.31) * diameter / 2
		show(visuals.highlight, CFrame.new(shine), Vector3.one * (diameter * 0.31), 0.90)
	else
		local pose = frame
		if camera and (shape == "Star" or shape == "Bolt") then
			pose = camera.CFrame.Rotation + position
			if shape == "Bolt" then
				local forward = pose:VectorToObjectSpace(frame.LookVector)
				pose *= CFrame.Angles(0, 0, math.atan2(forward.Y, forward.X))
			end
		end
		poseMesh(visuals.core, Meshes[shape], pose, FLIGHT_SCALE, 1)
	end
	if visuals.flightGlow then
		Textures.Show(visuals.flightGlow, position, (if shape == "Star" then 3.4 else 2.85) * FLIGHT_SCALE, 0.75)
	else
		show(visuals.halo, frame, Vector3.one * (0.97 * FLIGHT_SCALE), if shape == "Orb" then 0.27 else 0.12)
	end
	local reach = math.min(progress * (shot.surface - shot.from).Magnitude, 6) * FLIGHT_SCALE
	for i, ribbon in visuals.ribbons do
		local profile = TAILS[style.name][i]
		local length = math.min(reach, profile[1] * FLIGHT_SCALE * 1.5)
		local side = profile[3] * FLIGHT_SCALE
		local height = profile[4] * FLIGHT_SCALE
		ribbon.near.WorldCFrame = frame.Rotation
			+ (frame * Vector3.new(side * 0.65, height * 0.65, 0.08 * FLIGHT_SCALE))
		ribbon.far.WorldCFrame = frame.Rotation + (frame * Vector3.new(side, height, length))
		ribbon.part.Enabled = reach > 0.18
	end
	if visuals.dust then
		local last
		for i, part in visuals.dust do
			local p = frame
				* Vector3.new(math.sin(i * 4) * reach * 0.14, math.cos(i * 3) * reach * 0.11, reach * i / #visuals.dust)
			local sparkle = if style.name == "Astral" then (0.22 - i * 0.022) else (0.22 - i * 0.029)
			if visuals.trailLinks then
				part.Color = if i == 1 then style.burstColor else CYAN:Lerp(VIOLET, (i - 1) * 0.15)
			end
			show(part, CFrame.new(p), Vector3.one * sparkle, if reach > 0.2 then 0.88 - i * 0.12 else 0)
			if last and visuals.trailLinks then
				line(visuals.trailLinks[i - 1], last, p, 0.045, 0.68 - i * 0.11)
			end
			last = p
		end
	end
	for i, flake in visuals.flakes or {} do
		local p = frame * Vector3.new(math.sin(i * 7) * 0.43, math.cos(i * 4) * 0.35, reach * i / 3)
		Textures.Show(flake, p, (0.41 - 0.048 * i) * FLIGHT_SCALE, if reach > 0.3 then 0.86 - i * 0.15 else 0)
	end
	if visuals.snow then
		for i, bar in visuals.snow do
			local flake = (i - 1) // 3 + 1
			local p = frame * Vector3.new(math.sin(flake * 7) * 0.43, math.cos(flake * 4) * 0.35, reach * flake / 3)
			show(
				bar,
				CFrame.new(p) * frame.Rotation * CFrame.Angles(0, 0, i * math.pi / 3),
				Vector3.new(0.036, 0.22 - 0.023 * flake, 0.036),
				if reach > 0.3 then 0.70 - flake * 0.14 else 0
			)
		end
	end
	visuals.travel.Parent = shot.parent
end

local function showRing(rim, position, diameter, opacity, thickness)
	local canvasDiameter = diameter + 0.32
	local ratio = 0.93 * diameter / canvasDiameter
	local size = UDim2.fromScale(ratio, ratio)
	rim.part.CFrame = CFrame.new(position)
	rim.part.Size = Vector3.new(canvasDiameter, 0.06, canvasDiameter)
	rim.stroke.Parent.Size = size
	rim.glow.Parent.Size = size
	rim.stroke.Transparency = 1 - opacity
	rim.stroke.Thickness = if thickness
		then thickness * ProjectileScale.RingWeight
		else 5 * ProjectileScale.RingWeight / ProjectileScale.ImpactWeight
	rim.glow.Transparency = 1 - opacity * 0.24
	rim.glow.Thickness = rim.stroke.Thickness + 6
	rim.canvas.Enabled = true
end

function RarityEffects.StartStatus(shot)
	local name = shot.style.name
	local expires = if name == "Frost"
		then shot.attack.SlowUntil
		elseif name == "Venom" then shot.attack.PoisonUntil
		else nil
	local target = shot.target
	if not expires or not target.Parent or expires <= workspace:GetServerTimeNow() then
		return
	end
	local active = statuses[name]
	local marker = active[target]
	if marker then
		marker.expires = math.max(marker.expires, expires)
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = name .. "Status"
	folder.Parent = shot.parent
	local frost = name == "Frost"
	local icon
	if frost then
		local anchor = piece(folder, "SlowMarker", shot.style.burstColor)
		icon = Textures.Create(anchor, "Snowflake", shot.style.burstColor)
	end
	active[target] = {
		expires = expires,
		folder = folder,
		icon = icon,
		parts = pieces(
			if icon then 0 else 3,
			folder,
			if frost then "Snowflake" else "Bubble",
			shot.style.streak,
			if frost then nil else "Ball"
		),
		rim = if frost then ring(folder, shot.style.glow) else nil,
	}
end

function RarityEffects.StepStatus(now, reducedMotion)
	for _, active in statuses do
		for target, marker in active do
			local opacity = math.clamp(1 - (now - marker.expires) / 0.12, 0, 1) * (if reducedMotion then 0.36 else 0.67)
			if not target.Parent or opacity <= 0 then
				marker.folder:Destroy()
				active[target] = nil
			elseif marker.rim then
				local top = target.Position + Vector3.yAxis * (target.Size.Y / 2 + 0.38)
				if marker.icon then
					Textures.Show(marker.icon, top, 0.8, opacity)
				else
					local camera = workspace.CurrentCamera
					local facing = if camera then CFrame.lookAt(top, camera.CFrame.Position) else CFrame.new(top)
					for i, part in marker.parts do
						show(
							part,
							facing * CFrame.Angles(0, 0, i * math.pi / 3),
							Vector3.new(0.065, 0.58, 0.065),
							opacity
						)
					end
				end
				showRing(
					marker.rim,
					target.Position - Vector3.yAxis * (target.Size.Y / 2 - 0.06),
					target.Size.X * 1.38,
					opacity * 0.62
				)
			else
				for i, part in marker.parts do
					local height = if reducedMotion then 0.48 else ((now * 0.6 + i / 3) % 1)
					local point = target.Position + polar(i * 2.4, target.Size.X * 0.59, (height - 0.4) * target.Size.Y)
					show(part, CFrame.new(point), Vector3.one * (0.17 + 0.04 * i), opacity * (1 - 0.65 * height))
				end
			end
		end
	end
end

function RarityEffects.ClearStatus()
	for _, active in statuses do
		for _, marker in active do
			marker.folder:Destroy()
		end
		table.clear(active)
	end
end

local function clockTicks(ticks, ground, diameter, opacity, scale)
	for i, tick in ticks do
		local angle = (i - 1) * TAU / 12
		local point = ground + polar(angle, diameter / 2 - 0.14, 0.015)
		show(
			tick,
			CFrame.new(point) * CFrame.Angles(0, -angle, 0),
			Vector3.new(if i % 3 == 1 then 0.37 else 0.23, 0.07, 0.075) * scale,
			opacity
		)
	end
end

function RarityEffects.SetChronoAllies(parent, cells, seat, playerCount)
	local keep = {}
	local style = RarityEffects.Styles.L01
	for _, cell in cells or {} do
		keep[cell] = true
		if not chronoAuras[cell] then
			local root = Instance.new("Folder")
			root.Name = "ChronoAllyAura"
			chronoAuras[cell] = {
				root = root,
				ring = ring(root, style.glow),
				ticks = pieces(12, root, "ClockTick", style.burstColor),
				pillars = pieces(4, root, "ClockLight", style.color),
				center = Layout.CellPosition(cell, seat, playerCount) - Vector3.yAxis * 0.53,
			}
			root.Parent = parent
		end
	end
	for cell, aura in chronoAuras do
		if not keep[cell] then
			aura.root:Destroy()
			chronoAuras[cell] = nil
		end
	end
end

function RarityEffects.StepChrono(reducedMotion)
	for _, aura in chronoAuras do
		local glow = if reducedMotion then 0.30 else 0.36 + 0.12 * math.sin(os.clock() * math.pi)
		local diameter = 5
		showRing(aura.ring, aura.center, diameter, glow)
		clockTicks(aura.ticks, aura.center, diameter, glow, 1)
		for i, pillar in aura.pillars do
			local point = aura.center + polar((i - 0.5) * TAU / 4, diameter * 0.46, 0.05)
			line(pillar, point, point + Vector3.yAxis * 0.52, 0.07, glow * 0.62)
		end
	end
end

local function links(shot, opacity)
	local parts = shot.visuals.links
	if shot.style.name == "Arc" then
		for i, distance in shot.links or {} do
			local finish = Layout.PositionAt(distance, shot.enemySeat, shot.playerCount) + Vector3.yAxis * shot.lift
			local previous = shot.center
			for segment = 1, 5 do
				local point = shot.center:Lerp(finish, segment / 5)
				if segment ~= 5 then
					point += Vector3.new(
						math.cos(segment * 5) * 0.45,
						math.sin(segment * 7) * 0.65,
						math.sin(segment * 5) * 0.45
					)
				end
				local index = (i - 1) * 5 + segment
				line(parts[index], previous, point, 0.24 * IMPACT_WEIGHT, opacity * 0.39)
				line(shot.visuals.linkCores[index], previous, point, 0.073 * IMPACT_WEIGHT, opacity)
				previous = point
			end
			if i == 3 then
				break
			end
		end
	elseif shot.copiedCell then
		for i, ribbon in shot.visuals.glass do
			local rise = Vector3.yAxis * (0.3 + i * 0.19)
			local start, finish = shot.from + rise, shot.center + rise
			ribbon.near.WorldCFrame = CFrame.fromMatrix(start, Vector3.yAxis, Vector3.zAxis)
			ribbon.far.WorldCFrame = CFrame.fromMatrix(finish, Vector3.yAxis, Vector3.zAxis)
			ribbon.part.Enabled = true
			fadeRibbon(ribbon, opacity * 0.88, 0.72)
		end
	end
end

function RarityEffects.Impact(shot, age, facing)
	local v, s = shot.visuals, shot.style
	local t = age / DURATION
	local motion = if shot.reducedMotion then 0.45 else t
	local growth = 1 - (1 - motion) ^ 2
	local strength = if shot.reducedMotion then 0.44 else 0.92
	local criticalScale = if s.name == "Astral" and shot.attack.Critical and not shot.reducedMotion then 1.22 else 1
	local opacity = (1 - t) * strength
	local flash = math.max(0, 1 - age / 0.10) ^ (if shot.reducedMotion then 1.45 else 0.95) * strength
	local size = if s.name == "Astral" then 2.2 else 1.65
	local diameter = size * IMPACT_SCALE * (1 + growth * (if s.name == "Emberstorm" then 0.6 else 0.8))
	local footprint = if shot.effectCell then 3.25 else shot.lift * 2.83
	diameter = math.max(diameter, footprint * (0.88 + growth * 0.35))
	local ground = shot.ground
	v.travel.Parent = nil
	v.root.Parent = shot.parent
	v.burst.Parent = if flash > 0 then v.root else nil
	if v.hitGlow and flash > 0 and not shot.reducedMotion then
		local glowSize = if s.name == "Volley" then 1.6 elseif s.name == "Astral" then 3.5 else 2.65
		Textures.Show(v.hitGlow, facing.Position, glowSize * IMPACT_SCALE * criticalScale, flash * 0.83)
	end
	if flash > 0 and v.flashMesh then
		local radius = if s.name == "Volley" then 0.42 elseif s.name == "Astral" then 1.05 else 0.84
		poseMesh(v.flash, v.flashMesh, facing, radius * IMPACT_SCALE * criticalScale * (0.9 + growth * 0.22), flash)
	elseif flash > 0 and v.shards then
		for i, shard in v.shards do
			local pose = facing
				* CFrame.Angles(0, 0, (i - 1) * TAU / #v.shards + 0.18)
				* CFrame.new((0.41 + growth * 0.64) * IMPACT_SCALE, 0, 0)
			poseMesh(shard, Meshes.Shard, pose, (0.48 + i % 2 * 0.18) * IMPACT_SCALE, flash)
		end
	elseif flash > 0 and v.splash then
		show(v.flash, facing, Vector3.one * (0.53 * IMPACT_SCALE), flash)
		for i, drop in v.splash do
			local pose = facing
				* CFrame.Angles(0, 0, (i - (#v.splash + 1) / 2) * 0.50)
				* CFrame.new(0, (0.34 + growth * 0.73 + i % 2 * 0.11) * IMPACT_SCALE, 0)
			local width = 0.135 * ProjectileScale.ImpactWeight
			show(drop, pose, Vector3.new(width, 0.32, width) * IMPACT_SCALE, flash)
		end
	end
	if shot.visualLane == 0 then
		showRing(v.ring, ground, diameter, opacity * (if shot.reducedMotion then 0.78 else 0.90), 7)
	end
	if v.poolRing then
		local size = if s.name == "Venom" then 1.13 else 0.84
		showRing(v.poolRing, ground - Vector3.yAxis * 0.025, diameter * size, opacity * 0.48, 4)
	end
	if v.neighbors then
		local source = Layout.CellPosition(shot.attack.Cell, shot.attack.Seat, shot.attack.PlayerCount)
			- Vector3.yAxis * 0.40
		if shot.supportCells and #shot.supportCells > 0 then
			showRing(v.supportRing, source, 2.8 + growth * 1.45, opacity * 0.66)
		end
		for i, cell in shot.supportCells or {} do
			local center = Layout.CellPosition(cell, shot.attack.Seat, shot.attack.PlayerCount) - Vector3.yAxis * 0.53
			showRing(v.neighbors[i], center, 3.35 + growth * 1.65, opacity * 0.72)
			if not shot.reducedMotion then
				line(v.supportLinks[i], source, center + Vector3.yAxis * 0.13, 0.10, opacity * 0.58)
			end
		end
	elseif ((v.links and shot.links) or (v.glass and shot.copiedCell)) and not shot.reducedMotion then
		links(shot, opacity)
	elseif v.ticks then
		clockTicks(v.ticks, ground, diameter, opacity, IMPACT_SCALE)
	elseif v.spiral and not shot.reducedMotion then
		local contraction = (1 - motion * 0.17 - math.max(0, motion - 0.37) * 0.46) * diameter / 2
		for i, segment in v.spiral do
			local arm, step = (i - 1) // 10, (i - 1) % 10
			local angle = arm * math.pi + step * 0.43 - motion * 3
			-- The inner turns disappear beneath the target. The outer turns clear its silhouette.
			local radius = (0.58 + step * 0.066) * contraction
			local height = 0.12 + step * 0.014
			line(
				segment,
				ground + polar(angle, radius, height),
				ground + polar(angle + 0.43, radius + 0.066 * contraction, height + 0.014),
				(0.075 + step * 0.008) * IMPACT_WEIGHT,
				opacity * (0.99 - step * 0.030)
			)
		end
		for i, fragment in v.fragments do
			local angle = i * TAU / 3 - motion * 4.3
			local point = ground + polar(angle, contraction * (1.10 + i * 0.08), 0.34 + i * 0.12 + motion * 0.36)
			show(
				fragment,
				CFrame.new(point) * CFrame.Angles(angle, angle * 2, i),
				Vector3.one * (0.11 + i * 0.026),
				opacity * 0.69
			)
		end
	elseif v.stars and not shot.reducedMotion then
		for i, star in v.stars do
			local angle = i * TAU / 5 + 0.12
			local point = ground + polar(angle, diameter * 0.44, 0.15 + (i % 3) * 0.42)
			local nextPoint = ground + polar(angle + TAU / 5, diameter * 0.44, 0.15 + ((i % 5 + 1) % 3) * 0.42)
			show(star, CFrame.new(point), Vector3.one * (0.19 * IMPACT_SCALE), opacity)
			line(v.lines[i], point, nextPoint, 0.047 * IMPACT_WEIGHT, opacity * 0.56)
			line(
				v.pillars[i],
				point,
				point + Vector3.yAxis * ((0.62 + 0.47 * (i % 3)) * IMPACT_SCALE),
				0.065 * IMPACT_WEIGHT,
				opacity * 0.61
			)
		end
	end
	if v.chips and shot.visualLane == 0 and not shot.reducedMotion then
		for i, chip in v.chips do
			local angle = i * TAU / #v.chips + 0.18
			local point = ground + polar(angle, (0.38 + motion * 1.15) * diameter * 0.52, 0.30 + motion * 1.65)
			show(
				chip,
				CFrame.new(point) * CFrame.Angles(angle, motion * 3.8, i),
				Vector3.new(0.10, 0.23, 0.11),
				opacity * 0.69
			)
		end
	end
	if v.sparks and (shot.attack.Detonated or shot.transformedCell) and not shot.reducedMotion then
		for i, spark in v.sparks do
			local point = ground + polar(i * 2.40, 0.34 + motion * (0.7 + i * 0.19), 0.25 + motion * (2 + i * 0.25))
			show(spark, CFrame.new(point), Vector3.one * (0.16 * IMPACT_SCALE), opacity)
		end
		for i, flame in v.flame do
			local arm, segment = (i - 1) // 3, (i - 1) % 3
			local angle = arm * TAU / 3 + segment * 0.27 + motion * 0.4
			local radius = (0.8 + growth * 0.43 - segment * 0.055) * IMPACT_SCALE
			line(
				flame,
				ground + polar(angle, radius, (0.18 + segment * 0.31) * IMPACT_SCALE),
				ground + polar(angle + 0.27, radius - 0.055 * IMPACT_SCALE, (0.49 + segment * 0.31) * IMPACT_SCALE),
				(0.15 - segment * 0.025) * IMPACT_WEIGHT,
				opacity
			)
		end
	end
	if v.anvil and shot.transformedCell then
		local pulse = math.min(0.6 + age * 4, 1) * (1 - 0.15 * t) * IMPACT_SCALE
		local glow = opacity * math.min(0.5 + age * 9, 1)
		poseMesh(v.anvil, Meshes.Anvil, facing * CFrame.new(0, 0.24, 0.08), pulse, glow)
	end
end

function RarityEffects.Release(visuals)
	visuals.root.Parent = nil
	visuals.travel.Parent = nil
	visuals.burst.Parent = nil
	for _, ribbon in visuals.glass or {} do
		ribbon.part.Enabled = false
	end
	if visuals.hitGlow then
		visuals.hitGlow.billboard.Enabled = false
	end
	for _, part in visuals.root:GetChildren() do
		part.Transparency = HIDDEN
		local canvas = part:FindFirstChildOfClass("SurfaceGui")
		if canvas then
			canvas.Enabled = false
		end
	end
end

return RarityEffects
