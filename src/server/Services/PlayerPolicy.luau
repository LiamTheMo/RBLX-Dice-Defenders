-- Paid random items policy per player (docs/MVP.md "Roll"): PolicyService's ArePaidRandomItemsRestricted, fetched once
-- per join in its own thread (pcall, up to 3 tries with backoff) and cached. FAIL CLOSED: unknown (not answered yet) or
-- failed = not allowed, except in Studio, where a failed call counts as allowed so the flow can be tested. Readers
-- (the Roll handler) only read the cache and never yield. Changed(player) fires once the answer is cached.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Shared.Core.Signal)

local PlayerPolicy = {}

PlayerPolicy.ATTEMPTS = 3
PlayerPolicy.Changed = Signal.new()

local allowed: { [Player]: boolean } = {} -- absent = unknown = not allowed

-- The engine calls Fetch makes; specs pass their own.
local LIVE = {
	lookup = function(player: Player)
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end,
	wait = function(seconds: number)
		task.wait(seconds)
	end,
	isStudio = function(): boolean
		return RunService:IsStudio()
	end,
	warn = function(message: string)
		warn(message)
	end,
}

-- Looks the policy up (pcall, ATTEMPTS tries, 1 s then 2 s apart) and caches it; a player who left meanwhile
-- (Parent nil) gets nothing cached. Yields: run it in its own thread.
function PlayerPolicy.Fetch(player: Player, io: typeof(LIVE)?)
	local env = io or LIVE
	local delay = 1
	for attempt = 1, PlayerPolicy.ATTEMPTS do
		local ok, info = pcall(env.lookup, player)
		if player.Parent == nil then
			return -- left while waiting: nothing to cache
		end
		if ok and type(info) == "table" and type(info.ArePaidRandomItemsRestricted) == "boolean" then
			allowed[player] = not info.ArePaidRandomItemsRestricted
			PlayerPolicy.Changed:Fire(player)
			return
		end
		env.warn(("[PlayerPolicy] %s: policy lookup %d failed: %s"):format(tostring(player), attempt, tostring(info)))
		if attempt < PlayerPolicy.ATTEMPTS then
			env.wait(delay)
			delay *= 2
			if player.Parent == nil then
				return
			end
		end
	end
	allowed[player] = env.isStudio() -- closed on a live server
	PlayerPolicy.Changed:Fire(player)
end

-- True only when this player's policy was fetched and allows paid random items (or Studio could not fetch it).
function PlayerPolicy.RollAllowed(player: Player): boolean
	return allowed[player] == true
end

-- Drops a leaving player's cached answer.
function PlayerPolicy.Forget(player: Player)
	allowed[player] = nil
end

function PlayerPolicy.Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(PlayerPolicy.Fetch, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(PlayerPolicy.Fetch, player)
	end
	Players.PlayerRemoving:Connect(PlayerPolicy.Forget)
end

return PlayerPolicy
