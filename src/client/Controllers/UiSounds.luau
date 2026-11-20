local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local SettingsLogic = require(script.Parent.Settings.SettingsLogic)

local UiSounds = {}
local HOVER_ID = 79731766423271
local CLICK_ID = 101198440331061

local function createSound(name: string, id: number): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. id
	sound.Parent = SoundService
	return sound
end

local function play(sound: Sound)
	local volume = SettingsLogic.get("masterVolume") * SettingsLogic.get("interfaceVolume") / 10000
	if volume > 0 and sound.IsLoaded then
		sound.Volume = volume
		sound:Play()
	end
end

function UiSounds.Start()
	local hover = createSound("ButtonHover", HOVER_ID)
	local click = createSound("UiClick", CLICK_ID)
	task.spawn(function()
		ContentProvider:PreloadAsync({ hover, click })
	end)

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
						play(hover)
					end
				end
			end),
			button.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					and canPlayAt(button, input.Position.X, input.Position.Y)
				then
					play(click)
				end
			end),
			button.Activated:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
					play(click)
				end
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
