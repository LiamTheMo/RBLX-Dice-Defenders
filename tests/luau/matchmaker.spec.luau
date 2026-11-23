-- Duel matchmaking core (docs/DICE_RATING.md section 9): pairing, cooldown, bots, recent list, gateway fakes.

local Server = game:GetService("ServerScriptService").Server
local Matchmaker = require(Server.Rules.Matchmaker)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local Config = require(Server.Config.Matchmaking)
local InMemoryMemoryStore = require(Server.Infrastructure.InMemoryMemoryStore)
local InMemoryTeleport = require(Server.Infrastructure.InMemoryTeleport)
local MemoryStoreGateway = require(Server.Infrastructure.MemoryStoreGateway)
local TeleportGateway = require(Server.Infrastructure.TeleportGateway)

local NOW = 10000

local function entry(userId, rankIndex, dr, enqueuedAt, recent, isAdmin)
	return {
		UserId = userId,
		DR = dr or 0,
		RankIndex = rankIndex,
		EnqueuedAt = enqueuedAt or NOW,
		Recent = recent or {},
		IsAdmin = isAdmin or false,
	}
end

test("rank pairing table", function()
	local cases = {
		{ 1, 2, true }, -- Bronze-Silver
		{ 1, 3, false }, -- Bronze-Gold
		{ 2, 3, true }, -- Silver-Gold
		{ 1, 1, true },
		{ 2, 2, true },
		{ 3, 3, true },
	}
	for _, c in cases do
		expectEq(Matchmaker.Compatible(entry(1, c[1]), entry(2, c[2]), NOW), c[3], c[1] .. " vs " .. c[2])
		expectEq(Matchmaker.Compatible(entry(2, c[2]), entry(1, c[1]), NOW), c[3], "symmetric")
	end
	expect(not Matchmaker.Compatible(entry(1, 1), entry(1, 1), NOW), "never with yourself")
end)

test("cooldown blocks, expires, and admins ignore it", function()
	local fresh = { { UserId = 2, At = NOW - 10 } }
	local a, b = entry(1, 1, 0, NOW, fresh), entry(2, 1)
	expect(not Matchmaker.Compatible(a, b, NOW), "blocked from a's recent")
	expect(not Matchmaker.Compatible(b, a, NOW), "symmetric")
	expect(
		not Matchmaker.Compatible(entry(2, 1), entry(1, 1, 0, NOW, { { UserId = 2, At = NOW - 599 } }), NOW),
		"inside window"
	)
	expect(
		Matchmaker.Compatible(entry(1, 1, 0, NOW, { { UserId = 2, At = NOW - Config.CooldownSeconds } }), b, NOW),
		"expired"
	)
	expect(Matchmaker.Compatible(entry(1, 1, 0, NOW, fresh, true), b, NOW), "admin a")
	expect(Matchmaker.Compatible(a, entry(2, 1, 0, NOW, {}, true), NOW), "admin b")
	expect(Matchmaker.Compatible(entry(1, 1, 0, NOW, {}), entry(3, 1), NOW), "someone else is fine")
end)

test("FindPair: longest waiting first, best partner, deterministic", function()
	local none1, none2 = Matchmaker.FindPair({}, NOW)
	expect(none1 == nil and none2 == nil, "empty")
	local single = Matchmaker.FindPair({ entry(1, 1) }, NOW)
	expect(single == nil, "one entry")
	expect(Matchmaker.FindPair({ entry(1, 1), entry(2, 3) }, NOW) == nil, "no compatible pair")

	local entries = {
		entry(5, 2, 400, NOW - 5),
		entry(1, 2, 500, NOW - 30), -- longest waiting
		entry(2, 1, 290, NOW - 20), -- rank gap 1
		entry(3, 2, 450, NOW - 10), -- rank gap 0, DR gap 50
		entry(4, 2, 520, NOW - 40 + 35), -- rank gap 0, DR gap 20
	}
	local a, b = Matchmaker.FindPair(entries, NOW)
	expectEq(a.UserId, 1, "longest waiting leads")
	expectEq(b.UserId, 4, "smallest rank gap, then smallest DR gap")

	-- same DR gap: the longer-waiting partner wins
	local x, y =
		Matchmaker.FindPair({ entry(1, 2, 500, NOW - 9), entry(2, 2, 510, NOW - 8), entry(3, 2, 490, NOW - 7) }, NOW)
	expect(x.UserId == 1 and y.UserId == 2, "tie goes to the longer wait")

	-- the longest waiter has only a blocked partner: the next entry leads
	local blocked = { { UserId = 2, At = NOW - 5 } }
	local p, q = Matchmaker.FindPair({
		entry(1, 1, 0, NOW - 50, blocked),
		entry(2, 1, 0, NOW - 40),
		entry(3, 3, 0, NOW - 30),
		entry(4, 3, 0, NOW - 20),
	}, NOW)
	expect(p.UserId == 3 and q.UserId == 4, "skips an entry with no partner")

	-- input order does not matter
	local reversed = {}
	for i = #entries, 1, -1 do
		table.insert(reversed, entries[i])
	end
	local a2, b2 = Matchmaker.FindPair(reversed, NOW)
	expect(a2.UserId == a.UserId and b2.UserId == b.UserId, "deterministic")
end)

test("bot threshold and expiry", function()
	expect(not Matchmaker.WantsBot(entry(1, 1, 0, NOW - 11), NOW), "11s waits on")
	expect(Matchmaker.WantsBot(entry(1, 1, 0, NOW - 12), NOW), "12s gets a bot")
	expect(not Matchmaker.IsExpired(NOW - 59, NOW), "ticket alive")
	expect(Matchmaker.IsExpired(NOW - 60, NOW), "ticket dead")
	expect(not Matchmaker.IsExpired(NOW - 89, NOW, Config.MatchTtlSeconds), "match alive")
	expect(Matchmaker.IsExpired(NOW - 90, NOW, Config.MatchTtlSeconds), "match dead")
end)

test("Record keeps the newest RecentMax, skips bots, dedupes", function()
	local profile = ProfileSchema.Default()
	for i = 1, 12 do
		Matchmaker.Record(profile, 100 + i, NOW + i)
	end
	local recent = profile.Rating.Recent
	expectEq(#recent, Config.RecentMax, "trimmed")
	expectEq(recent[1].UserId, 103, "oldest kept")
	expectEq(recent[#recent].UserId, 112, "newest last")
	Matchmaker.Record(profile, 0, NOW)
	Matchmaker.Record(profile, -5, NOW)
	Matchmaker.Record(profile, nil, NOW)
	expectEq(#profile.Rating.Recent, Config.RecentMax, "bots not recorded")
	expectEq(profile.Rating.Recent[#profile.Rating.Recent].UserId, 112, "unchanged")
	Matchmaker.Record(profile, 105, NOW + 99)
	expectEq(#profile.Rating.Recent, Config.RecentMax, "rematch replaces the old record")
	expect(
		profile.Rating.Recent[#profile.Rating.Recent].UserId == 105
			and profile.Rating.Recent[#profile.Rating.Recent].At == NOW + 99,
		"moved to newest"
	)
end)

test("ticket and teleport data shapes", function()
	local players = { Matchmaker.PlayerInfo(1, 310, 2, "Silver", "A"), Matchmaker.PlayerInfo(2, 290, 1, "Bronze", "B") }
	local ticket = Matchmaker.Ticket("m1", "code", 123, players, NOW)
	expect(ticket.MatchId == "m1" and ticket.ReservedAccessCode == "code" and ticket.PlaceId == 123, "ticket")
	expect(ticket.CreatedAt == NOW and #ticket.Players == 2 and ticket.Players[1].Rank == "Silver", "players")
	local data = Matchmaker.TeleportData(ticket)
	expect(data.Mode == "Duel" and data.MatchId == "m1" and data.Players == players, "teleport data")
	local queued = Matchmaker.QueueEntry(7, 100, 1, {}, false, NOW)
	expect(queued.UserId == 7 and queued.EnqueuedAt == NOW and queued.RankIndex == 1, "queue entry")
end)

test("in-memory store: TTL, list, single claim", function()
	local clock = NOW
	local store = InMemoryMemoryStore.new(function()
		return clock
	end)
	expect(store:Set("1", { UserId = 1 }, 60), "set")
	store:Set("2", { UserId = 2 }, 30)
	local _, got = store:Get("1")
	expectEq(got.UserId, 1, "get")
	local _, rows = store:List(10)
	expect(#rows == 2 and rows[1].Key == "1" and rows[2].Key == "2", "list in key order")
	local _, one = store:List(1)
	expectEq(#one, 1, "list limit")
	clock = NOW + 30
	local _, live = store:List(10)
	expect(#live == 1 and live[1].Key == "1", "expired entry gone")
	local _, gone = store:Get("2")
	expect(gone == nil, "expired get")
	local _, first = store:Claim("1")
	local _, second = store:Claim("1")
	expect(first ~= nil and first.UserId == 1 and second == nil, "claimed once")
	store:Set("3", { UserId = 3 }, 10)
	store:Remove("3")
	expect(select(2, store:Get("3")) == nil, "removed")
	store.failNext = 1
	expect(not store:Set("4", {}, 10), "simulated failure surfaces")
end)

test("MemoryStoreGateway retries and degrades", function()
	local calls = 0
	local map = {
		SetAsync = function()
			calls += 1
			if calls < 3 then
				error("throttled")
			end
		end,
		GetAsync = function()
			error("down")
		end,
	}
	local gateway = MemoryStoreGateway.new({ map = map, sleep = function() end })
	expect(gateway:Available(), "available")
	expect(gateway:Set("k", {}, 5) and calls == 3, "retried until success")
	local ok, reason = gateway:Get("k")
	expect(not ok and string.find(reason, "down") ~= nil, "gives up with a reason")
	local off = MemoryStoreGateway.new({ map = nil, name = "x", sleep = function() end })
	if not off:Available() then
		local offOk = off:Set("k", {}, 5)
		expect(not offOk, "unavailable store fails without throwing")
	end
end)

test("TeleportGateway retries; the recording fake records", function()
	local reserveCalls = 0
	local service = {
		ReserveServer = function()
			reserveCalls += 1
			if reserveCalls < 2 then
				error("busy")
			end
			return "abc"
		end,
	}
	local gateway = TeleportGateway.new({ service = service, lobbyPlaceId = 1, sleep = function() end })
	local ok, code = gateway:ReserveServer(55)
	expect(ok and code == "abc" and reserveCalls == 2, "reserve retried")

	local fake = InMemoryTeleport.new()
	local _, access = fake:ReserveServer(55)
	local player = { Name = "P" }
	expect(fake:TeleportPlayerToReserved(player, access, { Mode = "Duel" }, 55), "teleport ok")
	expect(fake:TeleportToLobby(player), "lobby ok")
	expect(
		#fake.calls == 3 and fake.calls[2].Kind == "Reserved" and fake.calls[2].TeleportData.Mode == "Duel",
		"recorded"
	)
	fake.failNext = 1
	expect(not fake:TeleportToLobby(player), "failure injected")
end)

test("schema v14 -> v15 adds an empty Rating.Recent; bad lists are cleaned", function()
	local old = ProfileSchema.Default()
	old.Version = 14
	old.Rating.Recent = nil
	local migrated = ProfileSchema.Migrate(old)
	expect(migrated.Version == ProfileSchema.VERSION and #migrated.Rating.Recent == 0, "empty list")

	local dirty = ProfileSchema.Default()
	local list = { { UserId = 5, At = 100 }, { UserId = -1, At = 1 }, { UserId = 6.5, At = 1 }, "x", { UserId = 7 } }
	for i = 1, 20 do
		table.insert(list, { UserId = 1000 + i, At = i })
	end
	dirty.Rating.Recent = list
	local cleaned = ProfileSchema.Migrate(dirty).Rating.Recent
	expectEq(#cleaned, Config.RecentMax, "bounded")
	expect(cleaned[1].UserId == 5 and cleaned[1].At == 100 and cleaned[2].UserId == 1001, "invalid rows dropped")
	dirty.Rating.Recent = "junk"
	expectEq(#ProfileSchema.Migrate(dirty).Rating.Recent, 0, "junk resets")
end)

-- A tiny MemoryStoreSortedMap stand-in: UpdateAsync cancels on a nil return, like the real one.
local function fakeMap(state)
	local items = {}
	local map = { items = items, ranges = 0 }
	function map:SetAsync(key, value)
		items[key] = value
	end
	function map:GetAsync(key)
		return items[key]
	end
	function map:RemoveAsync(key)
		if state and (state.failRemove or 0) > 0 then
			state.failRemove -= 1
			error("remove failed")
		end
		items[key] = nil
	end
	function map:UpdateAsync(key, transform)
		local new = transform(items[key])
		if new ~= nil then
			items[key] = new
		end
		if state and state.failAfterUpdate then
			state.failAfterUpdate = false
			error("committed, then errored")
		end
	end
	function map:GetRangeAsync(_, count, lower)
		self.ranges += 1
		local keys = {}
		for key in items do
			if lower == nil or key > lower.key then
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		local out = {}
		for i = 1, math.min(count, #keys) do
			out[i] = { key = keys[i], value = items[keys[i]] }
		end
		return out
	end
	return map
end

test("gateway Claim: a failed remove or an errored update still returns the won value once", function()
	local state = { failRemove = 1 }
	local map = fakeMap(state)
	local gateway = MemoryStoreGateway.new({ map = map, sleep = function() end })
	gateway:Set("a", { UserId = 1 }, 60)
	local ok, value = gateway:Claim("a")
	expect(ok and value ~= nil and value.UserId == 1, "claimer gets the value although RemoveAsync threw")
	local _, again = gateway:Claim("a")
	expectEq(again, nil, "nobody claims it again (marker left)")
	local _, got = gateway:Get("a")
	expectEq(got, nil, "marked entries are hidden from Get")
	local _, rows = gateway:List(10)
	expectEq(#rows, 0, "and from List")

	-- UpdateAsync commits, then errors: the retry must not see its own marker and report nil.
	gateway:Set("b", { UserId = 2 }, 60)
	state.failAfterUpdate = true
	local okB, valueB = gateway:Claim("b")
	expect(okB and valueB ~= nil and valueB.UserId == 2, "value survives a retry after a committed update")
	local _, third = gateway:Claim("b")
	expectEq(third, nil, "still claimed once")
end)

test("fake store mirrors a lost claim remove", function()
	local store = InMemoryMemoryStore.new(function()
		return NOW
	end)
	store:Set("1", { UserId = 1 }, 60)
	store.failClaimRemove = 1
	local _, first = store:Claim("1")
	local _, second = store:Claim("1")
	expect(first ~= nil and first.UserId == 1 and second == nil, "claimed once")
	expectEq(#select(2, store:List(10)), 0, "marker hidden from List")
	expectEq(select(2, store:Get("1")), nil, "marker hidden from Get")
end)

test("gateway List pages past 200 rows in key order and respects the limit", function()
	local map = fakeMap()
	local gateway = MemoryStoreGateway.new({ map = map, sleep = function() end })
	for i = 1, 450 do
		gateway:Set(string.format("%04d", i), { UserId = i }, 60)
	end
	local ok, rows = gateway:List(1000)
	expect(ok and #rows == 450, "all rows")
	expect(rows[1].Key == "0001" and rows[450].Key == "0450", "key order")
	expectEq(map.ranges, 3, "three pages")
	local _, limited = gateway:List(250)
	expectEq(#limited, 250, "limit")
end)
