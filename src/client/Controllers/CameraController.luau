-- Camera per phase. During a run (Phase "Playing") a fixed Scriptable camera frames the path and the
-- board (Layout.Camera) and the character's movement controls are off; otherwise the default camera
-- follows the player's character around the lobby map.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Layout)
local NetClient = require(script.Parent.NetClient)

local CameraController = {}

local DEFAULT_FOV = 70 -- Roblox's default camera field of view, restored when leaving the board

local onBoard = false
local view = Layout.Camera
local controls: any = nil -- PlayerModule's ControlModule, once loaded

local function setControls()
	if controls then
		if onBoard then
			controls:Disable()
		else
			controls:Enable()
		end
	end
end

local function apply()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	if onBoard then
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		camera.FieldOfView = view.FieldOfView
		camera.CFrame = CFrame.lookAt(view.Position, view.LookAt)
	elseif camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = DEFAULT_FOV
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

local typeConnection: RBXScriptConnection? = nil

local function watch()
	if typeConnection then
		typeConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		typeConnection = camera:GetPropertyChangedSignal("CameraType"):Connect(apply)
	end
	apply()
end

local function onState(snapshot)
	local board = snapshot.Phase == "Playing"
	local nextView = if snapshot.PlayerCount == 2 then Layout.CoopCamera else Layout.Camera
	if board ~= onBoard or (board and nextView ~= view) then
		onBoard, view = board, nextView
		setControls()
		apply()
	end
end

function CameraController.Start()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watch)
	watch()
	NetClient.State:Connect(onState)
	if NetClient.Last then
		onState(NetClient.Last)
	end
	task.spawn(function()
		local module = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		if module then
			controls = require(module):GetControls()
			setControls()
		end
	end)
end

return CameraController
