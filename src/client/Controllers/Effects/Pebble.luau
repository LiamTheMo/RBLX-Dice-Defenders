local Pebble = {}

local MAX_SHOTS = 40
local SPEED = 140
local DOT_COLOR = Color3.fromRGB(190, 190, 190)
local FLASH_COLOR = Color3.fromRGB(222, 222, 222)
local DOT_SIZE = Vector3.one * 0.22
local RING_ROTATION = CFrame.Angles(0, math.pi / 2, 0)
local ringTemplate = script.Parent.PebbleRing
local shots = {}

-- Elapsed seconds, diameter in studs, and opacity from the Blender impact keys.
local RING = {
	{ 0, 0.26, 1 },
	{ 0.05, 0.48, 0.65 },
	{ 0.10, 0.62, 0.30 },
	{ 0.20, 0.72, 0.10 },
	{ 0.30, 0.75, 0 },
}

local function release(shot)
	shot.dot.Parent = nil
	shot.ring.Parent = nil
	shot.target = nil
	shot.parent = nil
end

local function borrow()
	for _, shot in shots do
		if shot.parent == nil then
			return shot
		end
	end
	if #shots >= MAX_SHOTS then
		return nil
	end
	local dot = Instance.new("Part")
	dot.Name = "PebbleProjectile"
	dot.Shape = Enum.PartType.Ball
	dot.Material = Enum.Material.SmoothPlastic
	dot.Anchored = true
	dot.CastShadow = false
	dot.CanCollide = false
	dot.CanQuery = false
	dot.CanTouch = false
	local shot = { dot = dot, ring = ringTemplate:Clone() }
	table.insert(shots, shot)
	return shot
end

function Pebble.Fire(parent: Folder, from: Vector3, center: Vector3, target: BasePart, reducedMotion: boolean)
	local shot = borrow()
	if shot == nil then
		return
	end
	shot.parent, shot.target = parent, target
	shot.from, shot.center = from, center
	shot.halfSize = target.Size.X / 2
	shot.reducedMotion = reducedMotion
	shot.flight = if reducedMotion then 0 else (center - from).Magnitude / SPEED
	shot.elapsed = 0
	shot.impact = nil
	shot.dot.Transparency = 0
	if not reducedMotion then
		shot.dot.Color = DOT_COLOR
		shot.dot.Size = DOT_SIZE
		shot.dot.Position = from
		shot.dot.Parent = parent
	end
end

local function advance(shot, dt: number, cameraPosition: Vector3)
	shot.elapsed += dt
	if shot.impact == nil then
		if shot.target.Parent then
			shot.center = shot.target.Position
		end
		-- Anchor to the camera-facing surface of the enemy box so the impact stays visible.
		local view = (cameraPosition - shot.center).Unit
		local axis = math.max(math.abs(view.X), math.abs(view.Y), math.abs(view.Z))
		local surface = shot.center + view * (shot.halfSize / axis + 0.05)
		if shot.elapsed < shot.flight then
			shot.dot.Position = shot.from:Lerp(surface, shot.elapsed / shot.flight)
			return
		end
		shot.impact = surface
	end

	local age = shot.elapsed - shot.flight
	if age >= RING[#RING][1] then
		release(shot)
		return
	end
	if not shot.reducedMotion and age < RING[2][1] then
		local fade = age / RING[2][1]
		shot.dot.Position = shot.impact
		shot.dot.Size = Vector3.one * (0.25 - 0.15 * fade)
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
			shot.ring.Size = Vector3.new(0.06, diameter, diameter)
			shot.ring.Transparency = 1 - opacity * (if shot.reducedMotion then 0.65 else 1)
			shot.ring.CFrame = CFrame.lookAt(shot.impact, cameraPosition) * RING_ROTATION
			shot.ring.Parent = shot.parent
			break
		end
	end
end

function Pebble.Step(dt: number)
	local camera = workspace.CurrentCamera
	if camera then
		for _, shot in shots do
			if shot.parent then
				advance(shot, dt, camera.CFrame.Position)
			end
		end
	end
end

function Pebble.Clear()
	for _, shot in shots do
		release(shot)
	end
end

return Pebble
