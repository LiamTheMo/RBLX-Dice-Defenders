-- Rigged enemy models (ReplicatedStorage.EnemyModels.<Kind>: an anchored Root + Motor6D per body group,
-- built in Studio from the Blender models). Walk cycles come from each enemy's animation reference:
-- Grunt 0.80s bounce, Runner 0.48s run, Brute 1.20s armoured walk. Phase follows distance walked, so feet
-- never slide and a faster wave plays the cycle faster. Client-only presentation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyRig = {}

local rad, sin, cos, pi = math.rad, math.sin, math.cos, math.pi
local CF, ANG = CFrame.new, CFrame.Angles

-- studs of path per cycle = the server speed x the reference cycle seconds
local STRIDE = { Grunt = 6 * 0.8, Runner = 9 * 0.48, Brute = (16 / 3) * 1.2 }

-- Each clip: (p: 0..1 phase, k: amplitude) -> root height, root pitch, { motorName = Transform }.
local CLIPS = {}

function CLIPS.Grunt(p, k)
	local hop = sin(pi * p) ^ 0.75 -- 0 at contact, 1 airborne (frame 12)
	local squash = 1 - hop -- compression is deepest at contact
	return 0.4 * hop * k,
		rad(-4) * k * hop,
		{
			Helmet = CF(0, -0.14 * squash * k, 0) * ANG(rad(3) * k * sin(2 * pi * p), 0, 0),
			Plume = ANG(rad(14) * k * sin(2 * pi * p - 0.9), 0, rad(4) * k * sin(2 * pi * p)),
			Sword = ANG(rad(-9) * k * sin(2 * pi * p - 0.5), 0, 0),
			Shield = CF(0, -0.08 * squash * k, 0),
			Eyes = CF(0, -0.05 * squash * k, 0),
		}
end

function CLIPS.Runner(p, k)
	local s = sin(2 * pi * p)
	local step = 0.5 - 0.5 * cos(4 * pi * p) -- two footfalls per cycle
	return 0.12 * step * k,
		rad(-9) * k, -- forward lean
		{
			LegL = ANG(rad(40) * k * s, 0, 0),
			LegR = ANG(rad(-40) * k * s, 0, 0),
			Dagger = ANG(rad(-32) * k * s, 0, 0),
			Cap = CF(0, 0.05 * k * sin(4 * pi * p - 0.6), 0) * ANG(rad(2) * k * s, 0, 0),
			ScarfWrap = ANG(rad(4) * k * sin(4 * pi * p), 0, 0),
			ScarfTails = ANG(rad(10) * k * sin(4 * pi * p - 1.0), rad(12) * k * sin(2 * pi * p - 0.5), 0),
		}
end

function CLIPS.Brute(p, k)
	local s = sin(2 * pi * p)
	local step = 0.5 - 0.5 * cos(4 * pi * p)
	return 0.1 * step * k,
		rad(-3) * k,
		{
			LegL = ANG(rad(22) * k * s, 0, 0),
			LegR = ANG(rad(-22) * k * s, 0, 0),
			ArmR = ANG(rad(-9) * k * s, 0, 0), -- sword arm swings against the near leg
			ArmL = ANG(rad(4) * k * s, 0, 0),
			Helmet = CF(0, -0.05 * k * (1 - step), 0) * ANG(rad(4) * k * sin(4 * pi * p - 0.7), 0, 0),
			Plume = ANG(rad(9) * k * sin(2 * pi * p - 1.0), 0, rad(3) * k * s),
		}
end

local store: Instance?
local heights = {}

local function template(kind: string): Model?
	if store == nil then
		store = ReplicatedStorage:FindFirstChild("EnemyModels")
	end
	local m = store and store:FindFirstChild(kind)
	return if m and m:IsA("Model") and CLIPS[kind] then m else nil
end

-- Height of the model in studs, or nil when this kind has no rig (the caller keeps its cube).
function EnemyRig.Height(kind: string): number?
	local t = template(kind)
	return t and t:GetAttribute("Height")
end

-- Clones the rig under `parent`. Returns the handle EnemyRig.Step takes, or nil.
function EnemyRig.New(kind: string, parent: Instance)
	local t = template(kind)
	if t == nil then
		return nil
	end
	local model = t:Clone()
	local motors = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	model.Parent = parent
	return { model = model, motors = motors, clip = CLIPS[kind], stride = STRIDE[kind], dir = -Vector3.zAxis }
end

-- ground: feet position; ahead: a point further along the route (nil at the end, keeps the last heading).
function EnemyRig.Step(rig, distance: number, ground: Vector3, ahead: Vector3?, still: boolean)
	if ahead then
		local d = Vector3.new(ahead.X - ground.X, 0, ahead.Z - ground.Z)
		if d.Magnitude > 1e-3 then
			rig.dir = d.Unit
		end
	end
	local p = if still then 0.25 else (distance / rig.stride) % 1
	local y, pitch, poses = rig.clip(p, if still then 0 else 1)
	-- front of the model is -Z, so look along the heading
	rig.model:PivotTo(CFrame.lookAt(ground, ground + rig.dir) * CF(0, y, 0) * ANG(pitch, 0, 0))
	for name, motor in rig.motors do
		motor.Transform = poses[name] or CFrame.identity
	end
end

return EnemyRig
