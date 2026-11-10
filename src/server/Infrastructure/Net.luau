-- Server side of ReplicatedStorage.Remotes: creates every remote declared in
-- Shared.Net.Remotes and routes every client request through RemoteGuard.
--   Net.Handle(name, handler)   -- RemoteFunction: handler(player, ...) -> (ok, code?)
--   Net.Fire(name, player, payload)  -- RemoteEvent to one player
--   Net.SetReadyCheck(fn(player) -> (boolean, code?))
-- Server never calls into clients: events only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteGuard = require(script.Parent.RemoteGuard)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local Net = {}

local readyCheck: ((Player) -> (boolean, string?))? = nil

local guard = RemoteGuard.new({
	clock = os.clock,
	ready = function(player)
		if readyCheck == nil then
			return false, "NotLoaded"
		end
		return readyCheck(player)
	end,
	kick = function(player)
		player:Kick("Disconnected.")
	end,
})
local remotes = {}

local folder = ReplicatedStorage:FindFirstChild("Remotes")
if folder == nil then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
end
for name, kind in Remotes.Kinds do
	local remote = Instance.new(if kind == "Function" then "RemoteFunction" else "RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	remotes[name] = remote
end

local function getRemote(name: string, className: string)
	local remote = remotes[name]
	assert(remote and remote.ClassName == className, `Net: no {className} named {name}`)
	return remote
end

function Net.SetReadyCheck(ready: (Player) -> (boolean, string?))
	readyCheck = ready
end

function Net.Handle(name: string, handler: (Player, ...any) -> (boolean, string?))
	local remote = getRemote(name, "RemoteFunction")
	remote.OnServerInvoke = function(player: Player, ...)
		return guard:Call(player, name, handler, ...)
	end
end

function Net.Fire(name: string, player: Player, payload: any)
	if player.Parent == nil then
		return -- already left
	end
	getRemote(name, "RemoteEvent"):FireClient(player, payload)
end

Players.PlayerRemoving:Connect(function(player)
	guard:Forget(player)
end)

return Net
