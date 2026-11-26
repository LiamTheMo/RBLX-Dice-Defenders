-- Roblox glue of the Duel queue: owns the MemoryStore and Teleport gateways, the per-server DuelQueue (all decisions
-- live in Rules/DuelQueue) and the poll loop. MatchService calls Enqueue/Cancel/State and listens to the signals.
--   QueueService.Changed(player)          the search state changed (Matched, ticket expired)
--   QueueService.LocalBot(player, bot)    no human in time or the queue is unavailable: run the bot Duel in this server
-- Studio cannot use MemoryStore or teleports reliably: it always takes the same-server bot path.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.Parent.Config.Matchmaking)
local MemoryStoreGateway = require(script.Parent.Parent.Infrastructure.MemoryStoreGateway)
local TeleportGateway = require(script.Parent.Parent.Infrastructure.TeleportGateway)
local Admin = require(script.Parent.Parent.Rules.Admin)
local DuelQueue = require(script.Parent.Parent.Rules.DuelQueue)
local Signal = require(ReplicatedStorage.Shared.Core.Signal)
local ProfileService = require(script.Parent.ProfileService)

local QueueService = {}

QueueService.Changed = Signal.new()
QueueService.LocalBot = Signal.new()

local queue = nil -- DuelQueue
local teleport = nil -- TeleportGateway
local stopped = false
local SHUTDOWN_CANCEL_SECONDS = 5 -- BindToClose budget for removing the queue entries of leaving players

local function build()
	local localOnly = RunService:IsStudio()
	teleport = TeleportGateway.new({})
	queue = DuelQueue.new({
		queue = MemoryStoreGateway.new({ name = "DuelQueue_v1" }),
		tickets = MemoryStoreGateway.new({ name = "DuelTickets_v1" }),
		teleport = teleport,
		now = os.time,
		rng = Random.new(),
		placeId = game.PlaceId, -- the reserved server runs this same place
		newMatchId = function()
			return HttpService:GenerateGUID(false)
		end,
		shouldStop = function()
			return stopped
		end,
		localOnly = localOnly,
	})
end

-- (true) or (false, code). Reads DR and the cooldown list from the loaded profile.
function QueueService.Enqueue(player: Player): boolean
	local profile = ProfileService.Get(player)
	if profile == nil or queue == nil or stopped then
		return false
	end
	return queue:Enqueue(player, {
		DR = profile.Rating.DR,
		Recent = table.clone(profile.Rating.Recent or {}),
		IsAdmin = Admin.IsAllowed(player.UserId),
	})
end

-- Stops the player's search (no-op when not searching). Returns true when a search was running.
function QueueService.Cancel(player: Player): boolean
	return queue ~= nil and queue:Cancel(player.UserId)
end

-- nil | "Searching" | "Matched"
function QueueService.State(player: Player): string?
	return if queue then queue:State(player.UserId) else nil
end

-- Teleports one player to the public lobby server. Yields; returns (ok, reason?).
function QueueService.TeleportToLobby(player: Player, teleportData: any?)
	if teleport == nil or RunService:IsStudio() then
		return false, "Unavailable"
	end
	return teleport:TeleportToLobby(player, teleportData)
end

local function pollOnce()
	local ok, events = pcall(queue.Poll, queue)
	if not ok then
		warn("[QueueService] Poll failed: " .. tostring(events))
		return
	end
	for _, event in events do
		if stopped then
			return
		end
		if event.Player.Parent ~= nil then
			if event.Kind == "LocalBot" then
				QueueService.LocalBot:Fire(event.Player, event.Bot)
			else
				QueueService.Changed:Fire(event.Player)
			end
		end
	end
end

function QueueService.Init()
	build()
end

function QueueService.Start()
	Players.PlayerRemoving:Connect(function(player)
		task.spawn(queue.Cancel, queue, player.UserId) -- leaving the server removes the entry (the store call yields)
	end)
	game:BindToClose(function()
		stopped = true
		-- Cancel everyone in parallel (each Cancel yields on the MemoryStore) and wait a bounded time.
		local pending = 0
		for _, player in Players:GetPlayers() do
			if queue:State(player.UserId) ~= nil then
				pending += 1
				task.spawn(function()
					pcall(queue.Cancel, queue, player.UserId)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + SHUTDOWN_CANCEL_SECONDS
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
	task.spawn(function()
		while not stopped do
			task.wait(Config.PollSeconds)
			if not stopped and queue:SearchingCount() > 0 then
				pollOnce()
			end
		end
	end)
end

return QueueService
