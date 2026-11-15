-- Show FPS overlay: a small label in its own ScreenGui, refreshed twice a second from frame counts.
-- The Heartbeat connection exists only while shown. Fps.new(playerGui) -> :SetVisible(on) :Destroy()

local RunService = game:GetService("RunService")

local Fps = {}
Fps.__index = Fps

function Fps.new(playerGui: Instance)
	local self = setmetatable({}, Fps)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "ShowFps", false, 20 -- above the HUD (5) and menus (6)
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency, label.Text = 1, "-- FPS"
	label.Position, label.Size = UDim2.fromOffset(8, 6), UDim2.fromOffset(90, 22) -- inside the core-UI safe insets: clear of the Roblox buttons
	label.Font, label.TextSize, label.TextXAlignment = Enum.Font.FredokaOne, 18, Enum.TextXAlignment.Left
	label.TextColor3, label.TextStrokeTransparency = Color3.new(1, 1, 1), 0.4
	label.Parent = gui
	gui.Parent = playerGui
	self._gui, self._label = gui, label
	return self
end

function Fps:SetVisible(on: boolean)
	if on == (self._conn ~= nil) then
		return
	end
	self._gui.Enabled = on
	if not on then
		self._conn:Disconnect()
		self._conn = nil
		return
	end
	local frames, elapsed = 0, 0
	self._conn = RunService.Heartbeat:Connect(function(dt)
		frames += 1
		elapsed += dt
		if elapsed >= 0.5 then
			self._label.Text = string.format("%d FPS", math.round(frames / elapsed))
			frames, elapsed = 0, 0
		end
	end)
end

function Fps:Destroy()
	self:SetVisible(false)
	self._gui:Destroy()
end

return Fps
