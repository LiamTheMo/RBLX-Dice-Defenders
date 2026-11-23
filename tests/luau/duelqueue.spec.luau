-- Rules/DuelQueue: the per-server Duel queue logic, driven by simulated servers that share one fake MemoryStore.

local Server = game:GetService("ServerScriptService").Server
local Config = require(Server.Config.Matchmaking)
local DuelQueue = require(Server.Rules.DuelQueue)
local InMemoryMemoryStore = require(Server.Infrastructure.InMemoryMemoryStore)
local InMemoryTeleport = require(Server.Infrastructure.InMemoryTeleport)

local PLACE = 777

-- Servers over the same queue and ticket maps; `t` is the shared clock.
local function world()
	local w = { t = 1000, matchCounter = 0 }
	local function now()
		return w.t
	end
	w.queueStore = InMemoryMemoryStore.new(now)
	w.ticketStore = InMemoryMemoryStore.new(now)
	function w.server(seed, overrides)
		local teleport = InMemoryTeleport.new()
		local q = DuelQueue.new({
			queue = (overrides and overrides.queue) or w.queueStore,
			tickets = (overrides and overrides.tickets) or w.ticketStore,
			teleport = teleport,
			now = now,
			rng = Random.new(seed or 1),
			placeId = PLACE,
			newMatchId = function()
				w.matchCounter += 1
				return "match-" .. w.matchCounter
			end,
			localOnly = overrides and overrides.localOnly,
		})
		return q, teleport
	end
	return w
end

local function player(userId)
	return { UserId = userId, DisplayName = "P" .. userId, Parent = {} }
end

local function info(dr, recent, isAdmin)
	return { DR = dr, Recent = recent or {}, IsAdmin = isAdmin == true }
end

local function kinds(events)
	local out = {}
	for _, e in events do
		table.insert(out, e.Kind .. ":" .. e.UserId)
	end
	table.sort(out)
	return table.concat(out, ",")
end

local function queued(w)
	local _, rows = w.queueStore:List(100)
	return #rows
end

local function reservedCalls(teleport)
	local out = {}
	for _, call in teleport.calls do
		if call.Kind == "Reserved" then
			table.insert(out, call)
		end
	end
	return out
end

local function humanTicket(w, userId, other, createdAt)
	return {
		MatchId = "m",
		ReservedAccessCode = "c",
		PlaceId = PLACE,
		CreatedAt = createdAt or w.t,
		Players = {
			{ UserId = userId, DR = 0, RankIndex = 1, Rank = "Bronze", Name = "P" .. userId },
			{ UserId = other, DR = 0, RankIndex = 1, Rank = "Bronze", Name = "P" .. other },
		},
	}
end

test("two servers: a cross-server pair is matched and each server teleports its own player", function()
	local w = world()
	local a, ta = w.server(1)
	local b, tb = w.server(2)
	local p1, p2 = player(1), player(2)
	a:Enqueue(p1, info(0))
	b:Enqueue(p2, info(100))
	expectEq(queued(w), 2, "both entries stored")
	expectEq(a:State(1), "Searching", "searching")

	local events = a:Poll() -- A pairs them and picks up its own ticket
	expectEq(kinds(events), "Matched:1", "A matched its human")
	expectEq(queued(w), 0, "both entries claimed")
	expectEq(a:State(1), "Matched", "state")
	local fromA = reservedCalls(ta)
	expectEq(#fromA, 1, "one reserved teleport from A")
	expectEq(fromA[1].Player, p1, "its own player")
	expectEq(fromA[1].PlaceId, PLACE, "place")
	expectEq(fromA[1].TeleportData.Mode, "Duel", "mode")
	expectEq(#fromA[1].TeleportData.Players, 2, "two humans")
	expectEq(fromA[1].TeleportData.Bot, nil, "no bot")

	local eventsB = b:Poll()
	expectEq(kinds(eventsB), "Matched:2", "B picks up its ticket")
	local fromB = reservedCalls(tb)
	expectEq(#fromB, 1, "B teleports once")
	expectEq(fromB[1].Player, p2, "B teleports its own player")
	expectEq(fromB[1].AccessCode, fromA[1].AccessCode, "same reserved server")
	expectEq(fromB[1].TeleportData.MatchId, fromA[1].TeleportData.MatchId, "same match")
	expectEq(#a:Poll(), 0, "no second event")
	expectEq(#reservedCalls(ta), 1, "no second teleport")
end)

test("rank gap larger than one is never paired", function()
	local w = world()
	local a = w.server(1)
	local b = w.server(2)
	a:Enqueue(player(1), info(0)) -- Bronze
	b:Enqueue(player(2), info(700)) -- Gold
	expectEq(#a:Poll(), 0, "no pair")
	expectEq(#b:Poll(), 0, "no pair")
	expectEq(queued(w), 2, "both still waiting")
	expectEq(a:State(1), "Searching", "searching")
end)

test("cooldown blocks a rematch and admins ignore it", function()
	local w = world()
	local a = w.server(1)
	local b = w.server(2)
	a:Enqueue(player(1), info(0, { { UserId = 2, At = w.t - 10 } }))
	b:Enqueue(player(2), info(0))
	expectEq(#a:Poll(), 0, "blocked by the cooldown")
	expectEq(queued(w), 2, "still waiting")

	local w2 = world()
	local a2 = w2.server(1)
	local b2 = w2.server(2)
	a2:Enqueue(player(1), info(0, { { UserId = 2, At = w2.t - 10 } }, true))
	b2:Enqueue(player(2), info(0))
	expectEq(kinds(a2:Poll()), "Matched:1", "admin paired despite the cooldown")
end)

test("a lone player gets a bot Duel in a reserved server after BotAfterSeconds", function()
	local w = world()
	local a, ta = w.server(3)
	a:Enqueue(player(1), info(0))
	w.t += Config.BotAfterSeconds - 1
	expectEq(#a:Poll(), 0, "too early")
	expectEq(#ta.calls, 0, "no teleport yet")
	w.t += 1
	local events = a:Poll()
	expectEq(kinds(events), "Matched:1", "matched with a bot")
	expectEq(queued(w), 0, "own entry claimed")
	local sent = reservedCalls(ta)[1]
	expect(sent ~= nil, "teleported")
	expectEq(#sent.TeleportData.Players, 1, "one human")
	local bot = sent.TeleportData.Bot
	expect(bot ~= nil and bot.IsBot == true, "bot descriptor")
	expect(type(bot.Name) == "string" and type(bot.DR) == "number" and #bot.Deck == 5, "bot identity and deck")
	expect(bot.RankIndex >= 1 and bot.RankIndex <= 3, "bot rank in range")
end)

test("the bot rank is the human rank or one away, clamped", function()
	local seen = {}
	for seed = 1, 60 do
		local w = world()
		local a, ta = w.server(seed)
		a:Enqueue(player(1), info(0)) -- Bronze: only Bronze or Silver are possible
		w.t += Config.BotAfterSeconds
		a:Poll()
		seen[reservedCalls(ta)[1].TeleportData.Bot.RankIndex] = true
	end
	expect(seen[1] and seen[2], "mostly the same rank, sometimes +1")
	expect(seen[3] == nil and seen[0] == nil, "never outside 1..3")
end)

test("a claim race: the second claim fails and the first entry goes back", function()
	local w = world()
	local lost = {}
	-- A store view where another server takes the keys in `lost` just before our claim.
	local proxy = setmetatable({}, {
		__index = function(_, name)
			if name == "Claim" then
				return function(_, key)
					if lost[key] then
						w.queueStore:Claim(key)
						return true, nil
					end
					return w.queueStore:Claim(key)
				end
			end
			local member = w.queueStore[name]
			return function(_, ...)
				return member(w.queueStore, ...)
			end
		end,
	})
	local a, ta = w.server(1, { queue = proxy })
	local b = w.server(2)
	a:Enqueue(player(1), info(0))
	b:Enqueue(player(2), info(0))
	lost["2"] = true
	expectEq(#a:Poll(), 0, "no pair, no ticket")
	expectEq(#ta.calls, 0, "no server reserved")
	local ok, entry = w.queueStore:Get("1")
	expect(ok and entry ~= nil and entry.UserId == 1, "the first entry was put back")
	local _, gone = w.queueStore:Get("2")
	expectEq(gone, nil, "the lost entry stays gone")
	local _, ticket = w.ticketStore:Get("1")
	expectEq(ticket, nil, "no ticket written")
end)

test("a claim race lost on the first entry touches nothing else", function()
	local w = world()
	local proxy = setmetatable({}, {
		__index = function(_, name)
			if name == "Claim" then
				return function(_, key)
					if key == "1" then
						w.queueStore:Claim(key)
						return true, nil
					end
					return w.queueStore:Claim(key)
				end
			end
			local member = w.queueStore[name]
			return function(_, ...)
				return member(w.queueStore, ...)
			end
		end,
	})
	local a, ta = w.server(1, { queue = proxy })
	local b = w.server(2)
	a:Enqueue(player(1), info(0))
	b:Enqueue(player(2), info(0))
	expectEq(#a:Poll(), 0, "nothing")
	expectEq(#ta.calls, 0, "no server reserved")
	local _, still = w.queueStore:Get("2")
	expect(still ~= nil and still.UserId == 2, "the other entry was not touched")
end)

test("cancel removes the entry and the search", function()
	local w = world()
	local a, ta = w.server(1)
	a:Enqueue(player(1), info(0))
	expectEq(queued(w), 1, "queued")
	expect(a:Cancel(1), "was searching")
	expectEq(queued(w), 0, "entry removed")
	expectEq(a:State(1), nil, "no state")
	w.t += Config.BotAfterSeconds * 2
	expectEq(#a:Poll(), 0, "nothing to do")
	expectEq(#ta.calls, 0, "no teleport")
	expect(not a:Cancel(1), "second cancel is a no-op")
end)

test("enqueue is idempotent", function()
	local w = world()
	local a = w.server(1)
	a:Enqueue(player(1), info(0))
	a:Enqueue(player(1), info(0))
	expectEq(queued(w), 1, "one entry")
	expectEq(a:SearchingCount(), 1, "one search")
end)

test("tickets: an expired ticket is ignored; a ticket that never teleports ends the search", function()
	local w = world()
	local a, ta = w.server(1)
	a:Enqueue(player(5), info(0))
	w.ticketStore:Set("5", humanTicket(w, 5, 6, w.t - Config.MatchTtlSeconds - 1), 100)
	expectEq(#a:Poll(), 0, "stale ticket ignored")
	expectEq(a:State(5), "Searching", "still searching")

	-- A live ticket whose teleport keeps failing: the search ends when the ticket would have expired.
	w.ticketStore:Set("5", humanTicket(w, 5, 6), 100)
	ta.failNext = 100
	expectEq(kinds(a:Poll()), "Matched:5", "ticket picked up")
	expectEq(a:State(5), "Matched", "matched")
	w.t += Config.PollSeconds
	a:Poll() -- retried (and failed again)
	w.t += Config.MatchTtlSeconds
	expectEq(kinds(a:Poll()), "Expired:5", "gave up")
	expectEq(a:State(5), nil, "search over")
end)

test("a malformed ticket or one for someone else is not used", function()
	local w = world()
	local a = w.server(1)
	a:Enqueue(player(5), info(0))
	w.ticketStore:Set("5", { MatchId = 3 }, 100)
	expectEq(#a:Poll(), 0, "malformed ticket")
	w.ticketStore:Set("5", humanTicket(w, 8, 9), 100)
	expectEq(#a:Poll(), 0, "ticket without this user")
end)

test("local only (Studio): the bot Duel runs in this server, nothing is stored or teleported", function()
	local w = world()
	local a, ta = w.server(1, { localOnly = true })
	local p = player(1)
	a:Enqueue(p, info(0))
	expectEq(queued(w), 0, "no entry")
	expect(a:IsLocalOnly(), "local")
	w.t += Config.BotAfterSeconds - 1
	expectEq(#a:Poll(), 0, "too early")
	w.t += 1
	local events = a:Poll()
	expectEq(#events, 1, "one event")
	expectEq(events[1].Kind, "LocalBot", "same-server bot")
	expectEq(events[1].Player, p, "player")
	expect(events[1].Bot.IsBot == true and #events[1].Bot.Deck == 5, "bot")
	expectEq(#ta.calls, 0, "no teleport")
	expectEq(a:State(1), nil, "search over")
end)

test("degraded paths fall back to a same-server bot", function()
	-- The queue write fails: the player is local from the start.
	local w = world()
	local a = w.server(1)
	w.queueStore.failNext = 1
	a:Enqueue(player(1), info(0))
	w.t += Config.BotAfterSeconds
	expectEq(kinds(a:Poll()), "LocalBot:1", "queue unavailable")

	-- ReserveServer fails when the entry is claimed for a bot.
	local w2 = world()
	local b, tb = w2.server(1)
	b:Enqueue(player(2), info(0))
	w2.t += Config.BotAfterSeconds
	tb.failNext = 10
	expectEq(kinds(b:Poll()), "LocalBot:2", "cannot reserve")

	-- The own entry was taken by someone else but no ticket ever arrives.
	local w3 = world()
	local c = w3.server(1)
	c:Enqueue(player(3), info(0))
	w3.queueStore:Claim("3")
	w3.t += Config.BotAfterSeconds
	expectEq(#c:Poll(), 0, "waiting for the ticket")
	w3.t += Config.PollSeconds * 5
	expectEq(kinds(c:Poll()), "LocalBot:3", "grace over")
end)

test("a player taken by another server gets their ticket instead of a bot", function()
	local w = world()
	local a, ta = w.server(1)
	a:Enqueue(player(3), info(0))
	w.t += Config.BotAfterSeconds
	w.queueStore:Claim("3") -- another server paired this human just now
	w.ticketStore:Set("3", humanTicket(w, 3, 4), 100)
	expectEq(kinds(a:Poll()), "Matched:3", "ticket wins over the bot")
	expectEq(reservedCalls(ta)[1].TeleportData.Bot, nil, "human opponent")
end)

-- Wraps a store: `hooks[method](store, ...)` runs before the real call and may return replacement results.
local function spy(store, hooks, log)
	return setmetatable({}, {
		__index = function(_, name)
			return function(_, ...)
				table.insert(log, name .. ":" .. tostring((...)))
				local hook = hooks and hooks[name]
				if hook then
					local replaced = table.pack(hook(...))
					if replaced.n > 0 then
						return table.unpack(replaced, 1, replaced.n)
					end
				end
				return store[name](store, ...)
			end
		end,
	})
end

test("claims are taken in ascending key order whatever the pair order", function()
	for _, ids in { { 2, 10 }, { 10, 2 } } do
		local w = world()
		local log = {}
		local a = w.server(1, { queue = spy(w.queueStore, nil, log) })
		a:Enqueue(player(ids[1]), info(0))
		a:Enqueue(player(ids[2]), info(0))
		a:Poll()
		local claims = {}
		for _, line in log do
			if string.find(line, "^Claim:") then
				table.insert(claims, line)
			end
		end
		expectEq(claims[1], "Claim:10", "string-smaller key first")
		expectEq(claims[2], "Claim:2", "then the other")
	end
end)

test("the matcher sorts by waiting time even though the store lists by key", function()
	local w = world()
	local a, ta = w.server(1)
	-- User 9 waited longest but has the highest key; 1 just fought 9 (cooldown), so 2 is the partner.
	a:Enqueue(player(9), info(0))
	w.t += 3
	a:Enqueue(player(1), info(0, { { UserId = 9, At = w.t } }))
	a:Enqueue(player(2), info(0))
	local events = a:Poll()
	expectEq(
		kinds(events),
		"Matched:2,Matched:9",
		"the longest waiter (9) got the best compatible partner (2, not blocked)"
	)
	expectEq(#reservedCalls(ta), 2, "both teleported from this server")
end)

test("cancel also removes the ticket; a ticket claimed after the owner cancelled is discarded", function()
	local w = world()
	local a = w.server(1)
	a:Enqueue(player(5), info(0))
	w.ticketStore:Set("5", humanTicket(w, 5, 6), 100)
	a:Cancel(5)
	local _, left = w.ticketStore:Get("5")
	expectEq(left, nil, "ticket key removed on cancel")

	local w2 = world()
	local holder = {}
	local log = {}
	local tickets = spy(w2.ticketStore, {
		Claim = function(key)
			holder.q:Cancel(tonumber(key)) -- the owner cancels while the claim is in flight
		end,
	}, log)
	local b, tb = w2.server(1, { tickets = tickets })
	holder.q = b
	b:Enqueue(player(5), info(0))
	w2.ticketStore:Set("5", humanTicket(w2, 5, 6), 100)
	expectEq(#b:Poll(), 0, "no Matched event")
	expectEq(#reservedCalls(tb), 0, "no teleport after the cancel")
end)

test("a stale ticket from an earlier search is rejected, a fresh one accepted", function()
	local w = world()
	local a = w.server(1)
	w.t = 5000
	a:Enqueue(player(5), info(0))
	w.ticketStore:Set("5", humanTicket(w, 5, 6, w.t - 20), 100) -- inside MatchTtl but older than this search
	expectEq(#a:Poll(), 0, "stale ticket ignored")
	w.ticketStore:Set("5", humanTicket(w, 5, 6, w.t), 100)
	expectEq(kinds(a:Poll()), "Matched:5", "fresh ticket used")
end)

test("reads before writes: no Claim without an entry or ticket to claim", function()
	local w = world()
	local qlog, tlog = {}, {}
	local a = w.server(1, { queue = spy(w.queueStore, nil, qlog), tickets = spy(w.ticketStore, nil, tlog) })
	a:Enqueue(player(5), info(0))
	a:Poll()
	for _, line in tlog do
		expect(not string.find(line, "^Claim"), "no ticket Claim while none exists: " .. line)
	end
	w.t += Config.BotAfterSeconds
	a:Poll() -- own entry exists: Get then Claim
	local sawGet, sawClaim = false, false
	for _, line in qlog do
		if line == "Get:5" then
			sawGet = true
		elseif line == "Claim:5" then
			sawClaim = sawGet
		end
	end
	expect(sawClaim, "own entry read before it was claimed")
	-- Entry already gone: Get sees nothing, so no Claim is issued for it.
	local w2 = world()
	local log2 = {}
	local b = w2.server(1, { queue = spy(w2.queueStore, nil, log2) })
	b:Enqueue(player(6), info(0))
	w2.queueStore:Remove("6")
	w2.t += Config.BotAfterSeconds
	b:Poll()
	for _, line in log2 do
		expect(line ~= "Claim:6", "no Claim on an entry that is not there")
	end
end)

test("a returned entry whose owner cancelled is not put back (no ghost)", function()
	local w = world()
	local holder, log = {}, {}
	local queue = spy(w.queueStore, {
		Claim = function(key)
			if key == "2" then
				holder.q:Cancel(1) -- user 1 (already claimed first) cancels before the second claim resolves
				w.queueStore:Claim("2")
				return true, nil -- and user 2 was taken by another server
			end
		end,
	}, log)
	local a = w.server(1, { queue = queue })
	holder.q = a
	local b = w.server(2)
	a:Enqueue(player(1), info(0))
	b:Enqueue(player(2), info(0))
	a:Poll()
	local _, ghost = w.queueStore:Get("1")
	expectEq(ghost, nil, "entry 1 stays gone")
end)

test("degrading to a same-server bot leaves no entry or ticket behind", function()
	local w = world()
	local qlog, tlog = {}, {}
	local b, tb = w.server(1, { queue = spy(w.queueStore, nil, qlog), tickets = spy(w.ticketStore, nil, tlog) })
	b:Enqueue(player(2), info(0))
	w.t += Config.BotAfterSeconds
	tb.failNext = 10
	expectEq(kinds(b:Poll()), "LocalBot:2", "cannot reserve")
	local removed = false
	for _, line in tlog do
		if line == "Remove:2" then
			removed = true
		end
	end
	expect(removed, "ticket key cleared")
	expectEq(queued(w), 0, "no entry left")
end)

test("shouldStop ends a Poll round early", function()
	local w = world()
	local stop = false
	local q = DuelQueue.new({
		queue = w.queueStore,
		tickets = w.ticketStore,
		teleport = InMemoryTeleport.new(),
		now = function()
			return w.t
		end,
		rng = Random.new(1),
		placeId = PLACE,
		newMatchId = function()
			return "m"
		end,
		shouldStop = function()
			return stop
		end,
	})
	q:Enqueue(player(1), info(0))
	w.t += Config.BotAfterSeconds
	stop = true
	expectEq(#q:Poll(), 0, "stopped: nothing claimed")
	expectEq(queued(w), 1, "entry untouched")
	stop = false
	expectEq(kinds(q:Poll()), "Matched:1", "resumes normally")
end)
