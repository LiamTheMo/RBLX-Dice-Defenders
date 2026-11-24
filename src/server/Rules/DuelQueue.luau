-- Per-server decision logic of the cross-server Duel queue (docs/DICE_RATING.md section 9). No Roblox services:
-- the MemoryStore maps and the teleport service arrive as gateway objects (MemoryStoreGateway / TeleportGateway or
-- their in-memory fakes), the clock and rng are injected, so specs drive several simulated servers headless.
--
-- Stores (two maps, key = tostring(UserId)):
--   queue   : Matchmaker.Entry (plus a Name field), TTL Config.TicketTtlSeconds
--   tickets : Matchmaker.Ticket written by whichever server paired the humans, TTL Config.MatchTtlSeconds
-- Each server calls Poll() every Config.PollSeconds. A Poll
--   1. matches the live queue entries (any server may do it; the atomic Claim decides who wins a race),
--   2. picks up the tickets of THIS server's searching players and teleports them to the reserved server,
--   3. retries teleports that failed,
--   4. after Config.BotAfterSeconds claims the player's own entry and teleports the lone human to a reserved server
--      with a bot descriptor. Every degraded path (store down, no reserve, no ticket for too long) ends in a
--      "LocalBot" event: the Duel then runs in this very server.
-- Poll returns events: { Kind = "Matched" | "LocalBot" | "Expired", UserId, Player, Bot? }.

local Bots = require(script.Parent.Parent.Config.Bots)
local Config = require(script.Parent.Parent.Config.Matchmaking)
local Bot = require(script.Parent.Bot)
local Matchmaker = require(script.Parent.Matchmaker)
local Rating = require(script.Parent.Rating)

local DuelQueue = {}
DuelQueue.__index = DuelQueue

-- Entries read per matching round. The sorted map lists in KEY order (200 per read), so a crowd beyond this limit
-- leaves the highest keys unseen for that round; those players still reach a bot after BotAfterSeconds. Fine for the
-- current scale (a few hundred concurrent searchers at most); revisit with a sharded map if it ever grows.
local LIST_LIMIT = 400
local TICKET_SKEW = Config.PollSeconds -- clock difference tolerated between servers when judging a ticket's age
local MAX_PAIRS_PER_POLL = 8
local BOT_RANK_SHIFT_CHANCE = 0.3 -- the bot is +-1 rank from the human, like a human opponent could be (docs section 9)
local GRACE_SECONDS = Config.PollSeconds * 5 -- store trouble this long past BotAfterSeconds degrades to a same-server bot

export type Options = {
	queue: any, -- gateway: Available/Set/Get/Remove/List/Claim
	tickets: any,
	teleport: any, -- gateway: ReserveServer/TeleportPlayerToReserved
	now: () -> number, -- seconds (os.time scale: it is compared across servers)
	rng: any,
	placeId: number,
	newMatchId: () -> string,
	shouldStop: (() -> boolean)?, -- polled between Poll steps (server shutdown): the round ends early
	localOnly: boolean?, -- Studio: never touch the stores or teleport; the bot Duel runs in this server
}

function DuelQueue.new(options: Options)
	return setmetatable({
		_queue = options.queue,
		_tickets = options.tickets,
		_teleport = options.teleport,
		_now = options.now,
		_rng = options.rng,
		_placeId = options.placeId,
		_newMatchId = options.newMatchId,
		_shouldStop = options.shouldStop or function()
			return false
		end,
		_localOnly = options.localOnly == true or not options.queue:Available(),
		_searching = {}, -- userId -> state
		_cancelled = {}, -- userId -> time this server saw the owner cancel/leave (ghost entries are never re-queued)
		_busy = false,
	}, DuelQueue)
end

local function key(userId: number): string
	return tostring(userId)
end

local function validEntry(value: any): boolean
	return type(value) == "table"
		and type(value.UserId) == "number"
		and type(value.DR) == "number"
		and type(value.RankIndex) == "number"
		and type(value.EnqueuedAt) == "number"
end

local function validTicket(value: any, userId: number): boolean
	if
		type(value) ~= "table"
		or type(value.MatchId) ~= "string"
		or type(value.ReservedAccessCode) ~= "string"
		or type(value.PlaceId) ~= "number"
		or type(value.CreatedAt) ~= "number"
		or type(value.Players) ~= "table"
	then
		return false
	end
	for _, info in value.Players do
		if type(info) == "table" and info.UserId == userId then
			return true
		end
	end
	return false
end

-- (true) or (false, "Unavailable"). `info` = { DR, Recent, IsAdmin }. A second Enqueue for the same user is a no-op.
function DuelQueue:Enqueue(player: any, info: { DR: number, Recent: any?, IsAdmin: boolean? })
	local userId = player.UserId
	if self._searching[userId] then
		return true
	end
	local now = self._now()
	local rank = Rating.RankOf(info.DR)
	local entry = Matchmaker.QueueEntry(userId, info.DR, rank.Index, info.Recent or {}, info.IsAdmin == true, now)
	local named: any = entry -- the pairing server needs the display name for the ticket
	named.Name = player.DisplayName or player.Name or "Player"
	self._cancelled[userId] = nil
	local state = { Player = player, Since = now, Entry = entry, Local = self._localOnly, Gone = nil, Pending = nil }
	self._searching[userId] = state -- registered before the yielding Set, so a second Enqueue is a no-op
	if not self._localOnly then
		local ok = self._queue:Set(key(userId), entry, Config.TicketTtlSeconds)
		if self._searching[userId] ~= state then
			if ok then
				self._queue:Remove(key(userId)) -- cancelled while the write was in flight
			end
		elseif not ok then
			state.Local = true -- the queue is down: this player gets a bot in this server
			self._queue:Remove(key(userId)) -- the failed write may still have landed: best effort, no ghost entry
		end
	end
	return true
end

-- Stops searching. Returns true when the user was searching. The entry is removed best-effort (an entry that
-- was already claimed is gone anyway; one that lingers expires by TTL and a claimed-by-nobody ticket is ignored).
function DuelQueue:Cancel(userId: number): boolean
	local state = self._searching[userId]
	if state == nil then
		return false
	end
	self._searching[userId] = nil
	self._cancelled[userId] = self._now()
	if not state.Local and state.Pending == nil then
		self._queue:Remove(key(userId))
		self._tickets:Remove(key(userId)) -- a ticket written just now must not outlive the search
	end
	return true
end

-- nil | "Searching" | "Matched" (a ticket or bot duel is being teleported to).
function DuelQueue:State(userId: number): string?
	local state = self._searching[userId]
	if state == nil then
		return nil
	end
	return if state.Pending then "Matched" else "Searching"
end

function DuelQueue:SearchingCount(): number
	local n = 0
	for _ in self._searching do
		n += 1
	end
	return n
end

function DuelQueue:IsLocalOnly(): boolean
	return self._localOnly
end

local function infoOf(entry): any
	return Matchmaker.PlayerInfo(
		entry.UserId,
		entry.DR,
		entry.RankIndex,
		Rating.RankOf(entry.DR).Name,
		entry.Name or "Player"
	)
end

function DuelQueue:_putBack(entry, now: number)
	if self._cancelled[entry.UserId] then
		return -- the owner (on this server) cancelled or left: a returned entry would be a ghost
	end
	local left = math.max(1, Config.TicketTtlSeconds - (now - entry.EnqueuedAt))
	self._queue:Set(key(entry.UserId), entry, left)
end

local function ids(list): { number }
	local out = {}
	for userId in list do
		table.insert(out, userId)
	end
	table.sort(out)
	return out
end

-- Pairs two compatible entries: claim both (always in ascending key order, so two servers racing for the same pair
-- take the same first key and one of them loses at once), reserve a server, write one ticket per human.
-- Returns "Paired" | "AGone" | "BGone" | "Failed" (a/b are the arguments, whatever the claim order).
function DuelQueue:_pair(a, b, now: number): string
	local aFirst = key(a.UserId) <= key(b.UserId)
	local first, second = if aFirst then a else b, if aFirst then b else a
	local goneFirst, goneSecond = if aFirst then "AGone" else "BGone", if aFirst then "BGone" else "AGone"
	local okF, claimedF = self._queue:Claim(key(first.UserId))
	if not okF or claimedF == nil then
		return goneFirst
	end
	local okS, claimedS = self._queue:Claim(key(second.UserId))
	if not okS or claimedS == nil then
		self:_putBack(claimedF, now) -- the second claim lost the race: the first goes back
		return goneSecond
	end
	local cancelledF, cancelledS = self._cancelled[claimedF.UserId], self._cancelled[claimedS.UserId]
	if cancelledF or cancelledS then
		-- An owner on this server cancelled while we were claiming: drop theirs, return the other.
		if not cancelledF then
			self:_putBack(claimedF, now)
		elseif not cancelledS then
			self:_putBack(claimedS, now)
		end
		return if cancelledF then goneFirst else goneSecond
	end
	local claimedA, claimedB = if aFirst then claimedF else claimedS, if aFirst then claimedS else claimedF
	local okR, code = self._teleport:ReserveServer(self._placeId)
	if not okR then
		self:_putBack(claimedA, now)
		self:_putBack(claimedB, now)
		return "Failed"
	end
	local players = { infoOf(claimedA), infoOf(claimedB) }
	if self._rng:NextInteger(1, 2) == 2 then
		players[1], players[2] = players[2], players[1] -- seat order is a coin flip
	end
	local ticket = Matchmaker.Ticket(self._newMatchId(), code, self._placeId, players, now)
	local written = {}
	for _, info in players do
		local ok = self._tickets:Set(key(info.UserId), ticket, Config.MatchTtlSeconds)
		if not ok then
			for _, userId in written do
				self._tickets:Remove(key(userId))
			end
			self:_putBack(claimedA, now)
			self:_putBack(claimedB, now)
			return "Failed"
		end
		table.insert(written, info.UserId)
	end
	return "Paired"
end

function DuelQueue:_match(now: number)
	local ok, rows = self._queue:List(LIST_LIMIT)
	if not ok then
		return
	end
	local entries = {}
	for _, row in rows do
		local value = row.Value
		if validEntry(value) and not Matchmaker.IsExpired(value.EnqueuedAt, now) then
			table.insert(entries, value)
		end
	end
	table.sort(entries, function(x, y) -- the map lists by key; FindPair wants waiting time (it sorts too)
		if x.EnqueuedAt ~= y.EnqueuedAt then
			return x.EnqueuedAt < y.EnqueuedAt
		end
		return x.UserId < y.UserId
	end)
	local function drop(entry)
		local index = table.find(entries, entry)
		if index then
			table.remove(entries, index)
		end
	end
	local paired = 0
	for _ = 1, math.min(#entries, LIST_LIMIT) do
		if paired >= MAX_PAIRS_PER_POLL then
			break
		end
		local a, b = Matchmaker.FindPair(entries, now)
		if a == nil or b == nil then
			break
		end
		local result = self:_pair(a, b, now)
		if result == "Paired" then
			paired += 1
			drop(a)
			drop(b)
		elseif result == "AGone" then
			drop(a)
		elseif result == "BGone" then
			drop(b)
		else
			break -- the store or the teleport service is failing: stop this round
		end
	end
end

-- Marks the state matched: the human is being sent to a reserved server.
function DuelQueue:_setPending(state, ticket, data, now: number, events)
	state.Pending = { Ticket = ticket, Data = data, At = now, Sent = false }
	table.insert(events, { Kind = "Matched", UserId = state.Player.UserId, Player = state.Player })
end

function DuelQueue:_pickUpTickets(now: number, events)
	for _, userId in ids(self._searching) do
		local state = self._searching[userId]
		if state and not state.Local and state.Pending == nil then
			-- Get first: a Claim is a write, and most polls find nothing (MemoryStore write quota).
			local seen, peek = self._tickets:Get(key(userId))
			if seen and peek ~= nil then
				local ok, ticket = self._tickets:Claim(key(userId))
				if
					ok
					and self._searching[userId] == state -- the owner cancelled while we waited: discard
					and validTicket(ticket, userId)
					and not Matchmaker.IsExpired(ticket.CreatedAt, now, Config.MatchTtlSeconds)
					and ticket.CreatedAt >= state.Since - TICKET_SKEW -- older than this search: a leftover
				then
					self:_setPending(state, ticket, Matchmaker.TeleportData(ticket), now, events)
				end
			end
		end
	end
end

function DuelQueue:_sendPending(now: number, events)
	for _, userId in ids(self._searching) do
		local state = self._searching[userId]
		local pending = state and state.Pending
		if pending then
			if Matchmaker.IsExpired(pending.At, now, Config.MatchTtlSeconds) then
				self._searching[userId] = nil -- never left (teleport failed for good): searching is over
				table.insert(events, { Kind = "Expired", UserId = userId, Player = state.Player })
			elseif not pending.Sent then
				local ok = self._teleport:TeleportPlayerToReserved(
					state.Player,
					pending.Ticket.ReservedAccessCode,
					pending.Data,
					pending.Ticket.PlaceId
				)
				pending.Sent = ok -- a failed send is retried next poll until the ticket expires
			end
		end
	end
end

-- A bot for `entry`: the human's rank, or +-1 (clamped to the existing ranks) with probability 0.3.
function DuelQueue:_makeBot(entry)
	local rank = entry.RankIndex
	if self._rng:NextNumber() < BOT_RANK_SHIFT_CHANCE then
		rank += if self._rng:NextInteger(1, 2) == 1 then -1 else 1
	end
	local bot = Bot.Make(math.clamp(rank, 1, #Bots.Ranks), self._rng)
	bot.IsBot = true
	return bot
end

function DuelQueue:_localBot(state, events)
	local userId = state.Player.UserId
	if self._searching[userId] ~= state then
		return
	end
	self._searching[userId] = nil
	if not self._localOnly then
		-- Best effort: no entry or ticket may outlive the degrade, or someone could be paired with a ghost.
		self._cancelled[userId] = self._now()
		self._queue:Claim(key(userId))
		self._tickets:Remove(key(userId))
	end
	table.insert(events, {
		Kind = "LocalBot",
		UserId = state.Player.UserId,
		Player = state.Player,
		Bot = self:_makeBot(state.Entry),
	})
end

function DuelQueue:_botFallback(now: number, events)
	for _, userId in ids(self._searching) do
		local state = self._searching[userId]
		if state and state.Pending == nil then
			if state.Local then
				if Matchmaker.WantsBot(state.Entry, now) then
					self:_localBot(state, events)
				end
			elseif Matchmaker.WantsBot(state.Entry, now) then
				local seen, present = self._queue:Get(key(userId)) -- Get first, Claim (a write) only if it is there
				local ok, claimed = false, nil
				if seen and present ~= nil then
					ok, claimed = self._queue:Claim(key(userId))
				end
				if ok and claimed ~= nil then
					-- Own entry claimed: nobody else can pair this human any more.
					local bot = self:_makeBot(state.Entry)
					local reserved, code = self._teleport:ReserveServer(self._placeId)
					if reserved then
						local ticket =
							Matchmaker.Ticket(self._newMatchId(), code, self._placeId, { infoOf(state.Entry) }, now)
						local data = Matchmaker.TeleportData(ticket)
						data.Bot = bot
						self:_setPending(state, ticket, data, now, events)
					else
						self:_localBot(state, events) -- cannot reserve: the Duel runs in this server
					end
				else
					-- (true, nil): someone else claimed the entry and a ticket should arrive; (false): store error.
					-- Both degrade to a same-server bot when nothing resolves within the grace period.
					state.Trouble = state.Trouble or now
					if now - state.Trouble >= GRACE_SECONDS then
						self:_localBot(state, events)
					end
				end
			end
		end
	end
end

-- One round (call every Config.PollSeconds). Returns the events described at the top. Errors propagate after the
-- busy flag is released, so a caller may pcall and log.
function DuelQueue:Poll()
	local events = {}
	if self._busy then
		return events
	end
	self._busy = true
	local ok, err = pcall(function()
		local now = self._now()
		for userId, at in self._cancelled do
			if now - at > Config.TicketTtlSeconds then
				self._cancelled[userId] = nil
			end
		end
		if not self._localOnly and self:SearchingCount() > 0 then
			self:_match(now)
			if self._shouldStop() then
				return
			end
			self:_pickUpTickets(now, events)
			if self._shouldStop() then
				return
			end
			self:_sendPending(now, events)
		end
		if self._shouldStop() then
			return
		end
		self:_botFallback(now, events)
		self:_sendPending(now, events) -- a bot ticket created this round leaves at once
	end)
	self._busy = false
	if not ok then
		error(err, 0)
	end
	return events
end

return DuelQueue
