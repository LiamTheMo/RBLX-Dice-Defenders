-- Client-only enemy parts. Position is a pure function of the server's SpawnAt and
-- Speed; HP, hits and deaths come from the Enemies batches. Presentation only.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Display = require(ReplicatedStorage.Shared.Display)
local Layout = require(ReplicatedStorage.Shared.Layout)
local NetClient = require(script.Parent.NetClient)
local CommonProjectiles = require(script.Parent.Effects.CommonProjectiles)
local RarityEffects = require(script.Parent.Effects.RarityEffects)
local SettingsLogic = require(script.Parent.Settings.SettingsLogic)

local EnemyView = {}

local SIZES = { Grunt = 2.4, Runner = 1.8, Brute = 3.4, Boss = 7 }
local TRACER_MAX = 40
local TRACER_SECONDS = 0.12

local HIT_SOUND_IDS = {
	99433010982298,
	102371225864429,
	76650774227119,
	138081247298518,
}
local HIT_VOICES_PER_CLIP = 4
local hitSounds: { { Sound } } = {}

local enemies = {} -- id -> { part, fill, spawnAt, speed, maxHp, lift }
local folder: Folder
local tracers = {} -- pool of { part, until }
local tracerFolder: Folder
local chronoCells
local chronoSeat, chronoPlayerCount

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
	p.Position = Layout.PositionAt(
		record.Speed * (workspace:GetServerTimeNow() - record.SpawnAt),
		record.Seat,
		record.PlayerCount
	) + Vector3.yAxis * (size / 2)

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
		hp = record.Hp,
		lift = size / 2,
		seat = record.Seat,
		playerCount = record.PlayerCount,
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
	p.Color = Color3.fromRGB(255, 0, 255)
	local t = { part = p, untilTime = 0 }
	table.insert(tracers, t)
	return t
end

local function playHitSound()
	local volume = SettingsLogic.get("masterVolume") * SettingsLogic.get("sfxVolume") / 10000
	if volume == 0 then
		return
	end
	local sounds = hitSounds[math.random(#hitSounds)]
	local voice
	for _, sound in sounds do
		if sound.IsLoaded then
			if not sound.IsPlaying then
				voice = sound
				break
			end
			if not voice or sound.TimePosition > voice.TimePosition then
				voice = sound
			end
		end
	end
	-- shortcut: restart the oldest voice if all four overlap, increase the count if bursts cut off clips.
	if voice then
		voice.Volume = volume
		voice:Play()
	end
end

local function fire(record)
	local e = enemies[record.Id]
	if e == nil then
		return
	end
	local effectsEnabled = SettingsLogic.get("projectileEffects")
	local handled, hasImpact
	if effectsEnabled then
		handled, hasImpact =
			CommonProjectiles.Fire(tracerFolder, e, record, SettingsLogic.get("reducedMotion"), playHitSound)
	end
	if not hasImpact then
		playHitSound()
	end
	if handled or not effectsEnabled then
		return
	end
	local from = Layout.CellPosition(record.Cell, record.Seat, record.PlayerCount) + Vector3.new(0, 3, 0)
	local t = tracer()
	if t == nil then
		return
	end
	-- From the path, not e.part: an enemy spawned in this batch isn't positioned until RenderStepped.
	local to = Layout.PositionAt(e.speed * (workspace:GetServerTimeNow() - e.spawnAt), e.seat, e.playerCount)
		+ Vector3.new(0, e.lift, 0)
	t.part.Size = Vector3.new(0.35, 0.35, (to - from).Magnitude)
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
			e.hp = record.Hp
			e.fill.Size = UDim2.fromScale(math.clamp(record.Hp / e.maxHp, 0, 1), 1)
			if record.Speed and record.SpawnAt then
				e.speed, e.spawnAt = record.Speed, record.SpawnAt
			end
		end
	end
	for _, record in batch.F or {} do
		fire(record)
	end
	for _, record in batch.R or {} do
		remove(record.Id)
	end
end

local function onFrame(dt: number)
	local now = workspace:GetServerTimeNow()
	for _, e in enemies do
		local p = Layout.PositionAt(e.speed * (now - e.spawnAt), e.seat, e.playerCount)
		e.part.Position = p + Vector3.new(0, e.lift, 0)
	end
	local clock = os.clock()
	for _, t in tracers do
		if t.part.Parent and t.untilTime <= clock then
			t.part.Parent = nil
		end
	end
	local reducedMotion = SettingsLogic.get("reducedMotion")
	CommonProjectiles.Step(dt, reducedMotion)
	RarityEffects.StepStatus(now, reducedMotion)
	if chronoCells then
		RarityEffects.StepChrono(reducedMotion)
	end
end

local function clearEffects()
	CommonProjectiles.Clear()
	RarityEffects.ClearStatus()
	for _, t in tracers do
		t.part.Parent = nil
		t.untilTime = 0
	end
end

function EnemyView.Start()
	local soundsToPreload = {}
	for index, id in HIT_SOUND_IDS do
		local voices = {}
		hitSounds[index] = voices
		for _ = 1, HIT_VOICES_PER_CLIP do
			local sound = Instance.new("Sound")
			sound.Name = "DiceHit"
			sound.SoundId = "rbxassetid://" .. id
			sound.Parent = SoundService
			table.insert(voices, sound)
			table.insert(soundsToPreload, sound)
		end
	end
	task.spawn(function()
		ContentProvider:PreloadAsync(soundsToPreload)
	end)

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
		chronoCells = if snapshot.Phase == "Playing" then snapshot.ChronoCells else nil
		chronoSeat, chronoPlayerCount = snapshot.Seat, snapshot.PlayerCount
		if SettingsLogic.get("projectileEffects") then
			RarityEffects.SetChronoAllies(tracerFolder, chronoCells, chronoSeat, chronoPlayerCount)
		end
		if snapshot.Phase ~= "Playing" then
			clear()
			clearEffects()
		end
	end)
	SettingsLogic.onChanged(function(id, value)
		if id == "projectileEffects" then
			RarityEffects.SetChronoAllies(
				tracerFolder,
				if value then chronoCells else nil,
				chronoSeat,
				chronoPlayerCount
			)
			if not value then
				clearEffects()
			end
		elseif id == "reducedMotion" and value then
			CommonProjectiles.Clear(true)
		end
	end)
	RunService.RenderStepped:Connect(onFrame)
end

return EnemyView
