-- Client-only enemy parts. Position is a pure function of the server's SpawnAt and
-- Speed; HP, hits and deaths come from the Enemies batches. Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Display = require(ReplicatedStorage.Shared.Display)
local Layout = require(ReplicatedStorage.Shared.Layout)
local NetClient = require(script.Parent.NetClient)

local EnemyView = {}

local SIZES = { Grunt = 2.4, Runner = 1.8, Brute = 3.4, Boss = 7 }
local TRACER_MAX = 40
local TRACER_SECONDS = 0.12

local enemies = {} -- id -> { part, fill, spawnAt, speed, maxHp, lift }
local folder: Folder
local tracers = {} -- pool of { part, until }
local tracerFolder: Folder

local function remove(id: number)
	local e = enemies[id]
	if e then
		e.part:Destroy()
		enemies[id] = nil
	end
end

local function clear()
	for id in table.clone(enemies) do
		remove(id)
	end
end

local function spawn(record)
	if enemies[record.Id] then
		return
	end
	local size = SIZES[record.Kind] or 2.4
	local style = Display.Enemies[record.Kind]
	local p = Instance.new("Part")
	p.Name = "Enemy" .. record.Id
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = Vector3.new(size, size, size)
	p.Color = if style then style.Color else Color3.new(1, 0, 1)
	p.Material = Enum.Material.SmoothPlastic

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(if record.Kind == "Boss" then 120 else 48, 7)
	gui.StudsOffset = Vector3.new(0, size / 2 + 1.5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = p
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(record.Hp / record.MaxHp, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = back

	p.Parent = folder
	enemies[record.Id] = {
		part = p,
		fill = fill,
		spawnAt = record.SpawnAt,
		speed = record.Speed,
		maxHp = record.MaxHp,
		lift = size / 2,
	}
end

local function tracer()
	local now = os.clock()
	for _, t in tracers do
		if t.untilTime <= now then
			return t
		end
	end
	if #tracers >= TRACER_MAX then
		return nil
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 240, 150)
	local t = { part = p, untilTime = 0 }
	table.insert(tracers, t)
	return t
end

local function fire(cell: number, id: number)
	local e = enemies[id]
	local t = e and tracer()
	if t == nil then
		return
	end
	local from = Layout.CellPosition(cell) + Vector3.new(0, 3, 0)
	-- From the path, not e.part: an enemy spawned in this batch isn't positioned until RenderStepped.
	local to = Layout.PositionAt(e.speed * (workspace:GetServerTimeNow() - e.spawnAt)) + Vector3.new(0, e.lift, 0)
	t.part.Size = Vector3.new(0.2, 0.2, (to - from).Magnitude)
	t.part.CFrame = CFrame.lookAt((from + to) / 2, to)
	t.part.Parent = tracerFolder
	t.untilTime = os.clock() + TRACER_SECONDS
end

local function onBatch(batch)
	for _, record in batch.S or {} do
		spawn(record)
	end
	for _, record in batch.H or {} do
		local e = enemies[record.Id]
		if e then
			e.fill.Size = UDim2.fromScale(math.clamp(record.Hp / e.maxHp, 0, 1), 1)
		end
	end
	for _, record in batch.F or {} do
		fire(record.Cell, record.Id)
	end
	for _, record in batch.R or {} do
		remove(record.Id)
	end
end

local function onFrame()
	local now = workspace:GetServerTimeNow()
	for _, e in enemies do
		local p = Layout.PositionAt(e.speed * (now - e.spawnAt))
		e.part.Position = p + Vector3.new(0, e.lift, 0)
	end
	local clock = os.clock()
	for _, t in tracers do
		if t.part.Parent and t.untilTime <= clock then
			t.part.Parent = nil
		end
	end
end

function EnemyView.Start()
	local root = workspace:FindFirstChild("ClientWorld")
	if root == nil then
		root = Instance.new("Folder")
		root.Name = "ClientWorld"
		root.Parent = workspace
	end
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = root
	tracerFolder = Instance.new("Folder")
	tracerFolder.Name = "Tracers"
	tracerFolder.Parent = root

	NetClient.Enemies:Connect(onBatch)
	NetClient.State:Connect(function(snapshot)
		if snapshot.Phase ~= "Playing" then
			clear()
		end
	end)
	RunService.RenderStepped:Connect(onFrame)
end

return EnemyView
