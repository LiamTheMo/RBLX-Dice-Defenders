-- Client side of the remotes: intent sender and State/Enemies relay. UX throttle
-- only; the server stays the authority (rate limit, seq, rules).
--   NetClient.State / .Enemies : Signals (snapshot) / (batch)
--   NetClient.Meta / .LastMeta : lobby payload (dice, deck, quests), same shape of API
--   NetClient.Last             : latest State snapshot or nil
--   NetClient.Request(name, ...) -> (ok, code?)   yields
--   NetClient.Rejected         : Signal (name, code) on every false result

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Core.Signal)

local NetClient = {}

NetClient.State = Signal.new()
NetClient.Enemies = Signal.new()
NetClient.Rejected = Signal.new()
NetClient.Meta = Signal.new()
NetClient.Last = nil
NetClient.LastMeta = nil

-- Minimum seconds between sends per intent, below the server's token buckets, plus
-- one request in flight per intent: an honest client can never trip RateLimited.
local MIN_INTERVAL = { Start = 1.0, Summon = 0.25, Merge = 0.25, EquipDeck = 1.0, ClaimQuest = 0.5 }
local pending = {}
local seq = 0
local lastSent = {}
local functions = {}

local function reject(name: string, code: string)
	NetClient.Rejected:Fire(name, code)
	return false, code
end

function NetClient.Request(name: string, ...): (boolean, string?)
	local remote = functions[name]
	if remote == nil then
		return reject(name, "Network")
	end
	local now = os.clock()
	if pending[name] or (lastSent[name] and now - lastSent[name] < (MIN_INTERVAL[name] or 1)) then
		return reject(name, "Throttled")
	end
	lastSent[name] = now
	seq += 1
	pending[name] = true
	local ok, result, code = pcall(remote.InvokeServer, remote, seq, ...)
	pending[name] = nil
	if not ok then
		return reject(name, "Network")
	end
	if result ~= true then
		return reject(name, if type(code) == "string" then code else "Rejected")
	end
	return true, nil
end

function NetClient.Start()
	-- Waiting for the server's remotes must not block the other controllers.
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Remotes")
		for _, name in { "Start", "Summon", "Merge", "EquipDeck", "ClaimQuest" } do
			functions[name] = folder:WaitForChild(name)
		end
		folder:WaitForChild("State").OnClientEvent:Connect(function(snapshot)
			NetClient.Last = snapshot
			NetClient.State:Fire(snapshot)
		end)
		folder:WaitForChild("Enemies").OnClientEvent:Connect(function(batch)
			NetClient.Enemies:Fire(batch)
		end)
		folder:WaitForChild("Meta").OnClientEvent:Connect(function(meta)
			NetClient.LastMeta = meta
			NetClient.Meta:Fire(meta)
		end)
	end)
end

return NetClient
