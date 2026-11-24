-- Camera per phase. During a run (Phase "Playing") a fixed Scriptable camera frames the path and the
-- board (Layout.Camera) and the character's movement controls are off; otherwise the default camera
-- follows the player's character around the lobby map. In Co-op and Duel a player can also hop their character onto
-- the board automatically: movement controls stay on under the fixed camera and the body stands on the arena, where
-- the other player sees it; it goes back to the lobby when the match ends. The client owns its character, so PivotTo
-- replicates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Layout)
local NetClient = require(script.Parent.NetClient)

local CameraController = {}

local DEFAULT_FOV = 70 -- Roblox's default camera field of view, restored when leaving the board

local onBoard = false
local view = Layout.Camera
local controls: any = nil -- PlayerModule's ControlModule, once loaded
local bodyOn = false -- the character is standing on the board
local returnCFrame: CFrame? = nil -- where it was before it hopped on
local shared = false -- this match has another player (Co-op or Duel)

local function setControls()
	if controls then
		if onBoard and not bodyOn then
			controls:Disable()
		else
			controls:Enable()
		end
	end
end

local function setBody(on: boolean)
	local character = Players.LocalPlayer.Character
	if on == bodyOn or (on and character == nil) then
		return
	end
	if character then
		if on then
			local root = character:FindFirstChild("HumanoidRootPart")
			returnCFrame = if root and root:IsA("BasePart") then root.CFrame else nil
			character:PivotTo(CFrame.new(view.LookAt + Vector3.new(0, 4, 0))) -- drops onto the board's centre
		elseif returnCFrame then
			character:PivotTo(returnCFrame)
		end
	end
	bodyOn = on
	setControls()
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
	shared = snapshot.Mode == "Duel" or snapshot.PlayerCount == 2
	if bodyOn and not (board and shared) then
		setBody(false) -- the match ended: the body goes back to the lobby
	end
	local nextView = if snapshot.Mode == "Duel"
		then Layout.DuelCamera(snapshot.Seat)
		elseif snapshot.PlayerCount == 2 then Layout.CoopCameraFor(snapshot.Seat)
		else Layout.Camera
	if board ~= onBoard or (board and nextView ~= view) then
		onBoard, view = board, nextView
		setControls()
		apply()
	end
	if board and shared and not bodyOn then
		setBody(true) -- retried on the next snapshot while the character is still loading
	end
end

function CameraController.Start()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watch)
	watch()
	NetClient.State:Connect(onState)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		bodyOn = false -- a fresh character spawns in the lobby
		setControls()
	end)
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
