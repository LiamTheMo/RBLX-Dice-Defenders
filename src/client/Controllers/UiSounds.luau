local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local SettingsLogic = require(script.Parent.Settings.SettingsLogic)

local UiSounds = {}
local HOVER_ID = 112701955250844
local DOWN_ID = 100773009428944
local UP_ID = 113165255820936

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

local function play(sound: AudioPlayer, startTime: number)
	local volume = SettingsLogic.get("masterVolume") * SettingsLogic.get("interfaceVolume") / 10000
	if volume > 0 and sound.IsReady then
		sound.Volume = volume
		sound.TimePosition = startTime
		sound:Play()
	end
end

function UiSounds.Start()
	local output = Instance.new("AudioDeviceOutput")
	output.Name = "UiAudio"
	output.Player = Players.LocalPlayer
	output.Parent = SoundService
	local hover = createSound("ButtonHover", HOVER_ID, output)
	local down = createSound("UiDown", DOWN_ID, output)
	local up = createSound("UiUp", UP_ID, output)

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local connections: { [Instance]: { RBXScriptConnection } } = {}

	local function canPlayAt(button: GuiButton, x: number, y: number): boolean
		if not (button.Active and button.Interactable) then
			return false
		end
		-- GUI pointer events can also fire on buttons underneath other controls.
		for _, target in playerGui:GetGuiObjectsAtPosition(x, y) do
			if target == button then
				return true
			end
			if target.Active and (not target:IsA("GuiButton") or target.Interactable) then
				break
			end
		end
		return false
	end
	local function bind(button: Instance)
		if not button:IsA("GuiButton") or connections[button] then
			return
		end
		local screen = button:FindFirstAncestorOfClass("ScreenGui")
		if screen and screen.Name == "TouchGui" then
			return
		end

		connections[button] = {
			button.MouseEnter:Connect(function(x, y)
				if UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
					local inset = GuiService:GetGuiInset()
					if canPlayAt(button, x - inset.X, y - inset.Y) then
						play(hover, 0)
					end
				end
			end),
			button.MouseButton1Down:Connect(function()
				play(down, 0)
			end),
			button.MouseButton1Up:Connect(function()
				play(up, 0)
			end),
		}
	end

	playerGui.DescendantAdded:Connect(bind)
	playerGui.DescendantRemoving:Connect(function(instance)
		local handlers = connections[instance]
		if handlers then
			for _, connection in handlers do
				connection:Disconnect()
			end
			connections[instance] = nil
		end
	end)
	for _, instance in playerGui:GetDescendants() do
		bind(instance)
	end
end

return UiSounds
