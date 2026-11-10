-- Fixed Scriptable camera framing the path and the board (Layout.Camera).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Layout)

local CameraController = {}

local function apply()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	camera.FieldOfView = Layout.Camera.FieldOfView
	camera.CFrame = CFrame.lookAt(Layout.Camera.Position, Layout.Camera.LookAt)
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

function CameraController.Start()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watch)
	watch()
end

return CameraController
