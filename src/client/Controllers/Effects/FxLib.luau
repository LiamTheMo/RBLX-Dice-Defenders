--!strict
-- Shared runtime for 3D dice effects (rulings R3/R6): pooled MeshParts, pooled Trails/Beams, one
-- Heartbeat loop, global cap, easing/curves, quality tier. No textures, SurfaceGui, Decal or
-- ParticleEmitter. After warm-up a pool only grows (Clone) up to its max; nothing is created per shot.
-- Pure logic lives in FxCore (tested headless); mesh ids/sizes come from FxMeshes (generated).

local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local FxCore = require(script.Parent.FxCore)
local FxMeshes = require(script.Parent.FxMeshes)

export type Easing = FxCore.Easing
export type Key = FxCore.Key
export type Handle = FxCore.Handle
export type Limiter = FxCore.Limiter
export type Tier = FxCore.Tier

export type PartProps = {
	Parent: Instance?,
	CFrame: CFrame?,
	Size: Vector3?, -- explicit studs (already scaled)
	Scale: (number | Vector3)?, -- multiplies the mesh's base size instead of Size
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
}

export type TrailProps = {
	Color: Color3?,
	Lifetime: number?, -- 0.1-0.4
	Width: number?, -- studs at the head
	WidthScale: NumberSequence?, -- default 1 -> 0
	LightEmission: number?,
	Transparency: number?, -- start transparency
}

export type BeamProps = {
	Color: Color3?,
	Width0: number?,
	Width1: number?,
	Segments: number?, -- 1 straight, ~8 curved
	CurveSize0: number?,
	CurveSize1: number?,
	LightEmission: number?,
	Transparency: number?,
}

export type TrailHandle = { trail: Trail, a0: Attachment, a1: Attachment }
export type BeamHandle = { beam: Beam, a0: Attachment, a1: Attachment }

local Fx = {}

Fx.Easing = FxCore.Easing
Fx.GLOBAL_CAP = FxCore.GLOBAL_CAP
Fx.Meshes = FxMeshes

local PART_POOL_MAX = 32
local TRAIL_POOL_MAX = 30 -- budget: <= 30 trails alive
local BEAM_POOL_MAX = 12 -- budget: <= 12 beams alive

-- Scale / curves (pure) --------------------------------------------------------------------------------

-- k = dieSize / 5; multiply every authored size by it.
Fx.Scale = FxCore.scale
Fx.Sample = FxCore.sample
Fx.Lerp = FxCore.lerp

-- Quality -----------------------------------------------------------------------------------------------

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled
end

function Fx.Tier(reducedMotion: boolean): Tier
	return FxCore.tier(reducedMotion, isPhone())
end

-- layer: "projectile" | "flash" | "trail" | "ring" | "shard" | "support" | "status"
Fx.LayerAllowed = FxCore.layerAllowed
Fx.FlashOpacity = FxCore.flashOpacity

-- Shared loop -------------------------------------------------------------------------------------------

local scheduler = FxCore.newScheduler(function(step)
	local conn = RunService.Heartbeat:Connect(step)
	return function()
		conn:Disconnect()
	end
end, FxCore.GLOBAL_CAP)

-- Per-style MAX_SHOTS: pass the limiter as the third argument of Fx.Run.
function Fx.Limiter(maxShots: number): Limiter
	return FxCore.newLimiter(maxShots)
end

-- Register a live effect. update(dt) returns true when finished; onEnd runs once on finish or cancel
-- (release your parts/trails there). Returns nil when over the global cap or the style's limiter:
-- the caller then skips the flourish (never gameplay) and must release anything it borrowed.
function Fx.Run(update: (number) -> boolean, onEnd: (() -> ())?, limiter: Limiter?): Handle?
	return scheduler.run(update, onEnd, limiter)
end

function Fx.Live(): number
	return scheduler.live()
end

-- Cancel everything (match end / cleanup). onEnd callbacks run, releasing pooled objects.
function Fx.Clear()
	scheduler.clear()
end

-- Part pools ---------------------------------------------------------------------------------------------

local DEFAULT_COLOR = Color3.new(1, 1, 1)
local DEFAULT_MATERIAL = Enum.Material.SmoothPlastic
local IDENTITY = CFrame.new()
local ALLOWED_PROPS = {
	Parent = true,
	CFrame = true,
	Size = true,
	Scale = true,
	Color = true,
	Material = true,
	Transparency = true,
}

local templates: { [string]: MeshPart } = {}
local partPools: { [string]: FxCore.Pool<MeshPart> } = {}
local partKey: { [MeshPart]: string } = {}

local function resetPart(part: MeshPart, key: string)
	part.Parent = nil
	part.Size = FxMeshes[key].Size
	part.CFrame = IDENTITY
	part.Color = DEFAULT_COLOR
	part.Material = DEFAULT_MATERIAL
	part.Transparency = 0
end

local function buildTemplate(key: string): MeshPart?
	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromUri(FxMeshes[key].MeshId))
	end)
	if not ok then
		warn(("Fx: mesh %s failed to load: %s"):format(key, tostring(result)))
		return nil
	end
	local part = result :: MeshPart
	part.Name = key
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Size = FxMeshes[key].Size
	return part
end

local function poolFor(key: string): FxCore.Pool<MeshPart>
	local pool = partPools[key]
	if pool then
		return pool
	end
	pool = FxCore.newPool(function(): MeshPart?
		local template = templates[key]
		if template == nil then
			return nil -- still loading: the flourish is skipped this time
		end
		local part = template:Clone()
		partKey[part] = key
		return part
	end, function(part: MeshPart)
		resetPart(part, key)
	end, PART_POOL_MAX)
	partPools[key] = pool
	return pool
end

-- Load the template then pre-warm 8. Yields; runs in its own thread at load.
local function warmKey(key: string)
	local pool = poolFor(key)
	if templates[key] == nil then
		local template = buildTemplate(key)
		if template == nil then
			return
		end
		templates[key] = template
	end
	pool.warm(FxCore.POOL_WARM)
end

-- Pre-warm the given mesh keys (all of FxMeshes when omitted). Called once at load.
function Fx.Warm(keys: { string }?)
	local list = keys
	if list == nil then
		list = {}
		for key in FxMeshes do
			table.insert(list :: { string }, key)
		end
	end
	for _, key in list :: { string } do
		if FxMeshes[key] == nil then
			error("Fx.Warm: unknown mesh " .. key, 2)
		end
		task.spawn(warmKey, key)
	end
end

-- Borrow a MeshPart for a mesh key. Returns nil while loading or at the pool cap (drop the flourish).
function Fx.Part(meshKey: string, props: PartProps?): MeshPart?
	if FxMeshes[meshKey] == nil then
		error("Fx.Part: unknown mesh " .. meshKey, 2)
	end
	local p: { [string]: any } = (props or {}) :: any
	for name in p do
		if not ALLOWED_PROPS[name] then
			error("Fx.Part: unsupported prop " .. name, 2)
		end
	end
	local part = poolFor(meshKey).borrow()
	if part == nil then
		return nil
	end
	local scale = p.Scale
	if scale ~= nil then
		local base = FxMeshes[meshKey].Size
		part.Size = base * (scale :: any)
	elseif p.Size ~= nil then
		part.Size = p.Size
	end
	if p.CFrame ~= nil then
		part.CFrame = p.CFrame
	end
	if p.Color ~= nil then
		part.Color = p.Color
	end
	if p.Material ~= nil then
		part.Material = p.Material
	end
	if p.Transparency ~= nil then
		part.Transparency = p.Transparency
	end
	if p.Parent ~= nil then
		part.Parent = p.Parent -- last, after the properties are set
	end
	return part
end

-- Return a part to its pool (Parent=nil, every property reset). Safe on nil / non-pooled / released parts.
function Fx.Release(part: MeshPart?)
	if part == nil then
		return
	end
	local key = partKey[part]
	if key == nil then
		return
	end
	local pool = partPools[key]
	if pool then
		pool.release(part)
	end
end

-- Trail / Beam pools -----------------------------------------------------------------------------------------

local function newTrailHandle(): TrailHandle?
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Texture = "" -- plain colour ribbon, no texture
	trail.FaceCamera = true
	trail.Enabled = false
	return { trail = trail, a0 = a0, a1 = a1 }
end

local function resetTrail(h: TrailHandle)
	h.trail.Enabled = false
	h.trail:Clear()
	h.trail.Parent = nil
	h.a0.Parent = nil
	h.a1.Parent = nil
end

local function newBeamHandle(): BeamHandle?
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Texture = ""
	beam.FaceCamera = true
	beam.Enabled = false
	return { beam = beam, a0 = a0, a1 = a1 }
end

local function resetBeam(h: BeamHandle)
	h.beam.Enabled = false
	h.beam.Parent = nil
	h.beam.Segments = 10
	h.beam.CurveSize0 = 0
	h.beam.CurveSize1 = 0
	h.a0.Parent = nil
	h.a1.Parent = nil
end

local trailPool = FxCore.newPool(newTrailHandle, resetTrail, TRAIL_POOL_MAX)
local beamPool = FxCore.newPool(newBeamHandle, resetBeam, BEAM_POOL_MAX)
trailPool.warm(FxCore.POOL_WARM)
beamPool.warm(FxCore.POOL_WARM)

-- Borrow a plain-colour Trail on `part` (moving part: the ribbon follows it). Returns nil at the cap.
function Fx.Trail(part: BasePart, props: TrailProps?): TrailHandle?
	local h = trailPool.borrow()
	if h == nil then
		return nil
	end
	local p = props or {}
	local width = p.Width or 0.2
	local trail = h.trail
	h.a0.Position = Vector3.new(0, width / 2, 0)
	h.a1.Position = Vector3.new(0, -width / 2, 0)
	h.a0.Parent = part
	h.a1.Parent = part
	local color = p.Color or DEFAULT_COLOR
	trail.Color = ColorSequence.new(color)
	trail.Lifetime = p.Lifetime or 0.15
	trail.LightEmission = p.LightEmission or 0.8
	trail.Transparency = NumberSequence.new(p.Transparency or 0, 1)
	trail.WidthScale = p.WidthScale or NumberSequence.new(1, 0)
	trail.MinLength = 0.05
	trail.Parent = part
	trail.Enabled = true
	return h
end

function Fx.ReleaseTrail(h: TrailHandle?)
	if h then
		trailPool.release(h)
	end
end

-- Borrow a Beam between two attachment parents (a0Parent/a1Parent: BaseParts or Attachments' hosts).
function Fx.Beam(a0Parent: Instance, a1Parent: Instance, props: BeamProps?): BeamHandle?
	local h = beamPool.borrow()
	if h == nil then
		return nil
	end
	local p = props or {}
	local beam = h.beam
	h.a0.Parent = a0Parent
	h.a1.Parent = a1Parent
	beam.Color = ColorSequence.new(p.Color or DEFAULT_COLOR)
	beam.Width0 = p.Width0 or 0.3
	beam.Width1 = p.Width1 or p.Width0 or 0.3
	beam.Segments = p.Segments or 1
	beam.CurveSize0 = p.CurveSize0 or 0
	beam.CurveSize1 = p.CurveSize1 or 0
	beam.LightEmission = p.LightEmission or 0.8
	beam.Transparency = NumberSequence.new(p.Transparency or 0)
	beam.Parent = a0Parent
	beam.Enabled = true
	return h
end

function Fx.ReleaseBeam(h: BeamHandle?)
	if h then
		beamPool.release(h)
	end
end

-- Orientation ---------------------------------------------------------------------------------------------------

-- Meshes are flat in Roblox XZ with the thin axis along +Y (rings lie flat: leave them alone).
-- Stars/flashes: tilt so +Y points at the current camera. roll spins the shape about its own normal.
function Fx.FaceCamera(cf: CFrame, roll: number?): CFrame
	local camera = workspace.CurrentCamera
	if camera == nil then
		return cf
	end
	local camPos = camera.CFrame.Position
	local pos = cf.Position
	if (camPos - pos).Magnitude < 1e-3 then
		return cf
	end
	local facing = CFrame.lookAt(pos, camPos) * CFrame.Angles(-math.pi / 2, 0, 0)
	if roll and roll ~= 0 then
		facing = facing * CFrame.Angles(0, roll, 0)
	end
	return facing
end

-- Load-time warm-up (templates load asynchronously; borrows return nil until ready).
Fx.Warm()

return Fx
