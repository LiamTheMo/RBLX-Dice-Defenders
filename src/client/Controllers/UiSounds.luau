local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local SettingsLogic = require(script.Parent.Settings.SettingsLogic)

-- Menus report Open/Close (Shell does); a button press only says "something was clicked".
-- Both are settled one frame later so a click that swaps menus plays the open sound alone.
local UiSounds = {}
local OPEN_ID = 86983927654993
local CLOSE_ID = 81748023213695
local CLICK_ID = 103427166722360

local openSound: AudioPlayer?
local closeSound: AudioPlayer?
local clickSound: AudioPlayer?
local opened, closed, clicked, pending = false, false, false, false

local function createSound(name: string, id: number, output: AudioDeviceOutput): AudioPlayer
	local sound = Instance.new("AudioPlayer")
	sound.Name = name
	sound.AutoLoad = true
	sound.AudioContent = Content.fromUri("rbxassetid://" .. id)
	sound.Parent = output

	local wire = Instance.new("Wire")
	wire.SourceInstance = sound
	wire.TargetInstance = output
	wire.Parent = sound
	return sound
end

local function play(sound: AudioPlayer?)
	if not sound then
		return
	end
	local volume = SettingsLogic.get("masterVolume") * SettingsLogic.get("interfaceVolume") / 10000
	if volume > 0 and sound.IsReady then
		sound.Volume = volume
		sound.TimePosition = 0
		sound:Play()
	end
end

local function settle()
	local wasOpened, wasClosed, wasClicked = opened, closed, clicked
	opened, closed, clicked, pending = false, false, false, false
	if wasOpened then
		play(openSound)
	elseif wasClosed then
		play(closeSound)
	elseif wasClicked then
		play(clickSound)
	end
end

local function note()
	if not pending then
		pending = true
		task.defer(settle)
	end
end

function UiSounds.MenuOpened()
	opened = true
	note()
end

function UiSounds.MenuClosed()
	closed = true
	note()
end

function UiSounds.Start()
	local output = Instance.new("AudioDeviceOutput")
	output.Name = "UiAudio"
	output.Player = Players.LocalPlayer
	output.Parent = SoundService
	openSound = createSound("UiOpen", OPEN_ID, output)
	closeSound = createSound("UiClose", CLOSE_ID, output)
	clickSound = createSound("UiClick", CLICK_ID, output)

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local connections: { [Instance]: RBXScriptConnection } = {}

	local function bind(button: Instance)
		if not button:IsA("GuiButton") or connections[button] then
			return
		end
		local screen = button:FindFirstAncestorOfClass("ScreenGui")
		if screen and screen.Name == "TouchGui" then
			return
		end
		connections[button] = button.Activated:Connect(function()
			clicked = true
			note()
		end)
	end

	playerGui.DescendantAdded:Connect(bind)
	playerGui.DescendantRemoving:Connect(function(instance)
		local connection = connections[instance]
		if connection then
			connection:Disconnect()
			connections[instance] = nil
		end
	end)
	for _, instance in playerGui:GetDescendants() do
		bind(instance)
	end
end

return UiSounds
