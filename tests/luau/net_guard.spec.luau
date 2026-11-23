-- RemoteGuard: rate limits, exact argument matrix, seq rules, kick threshold,
-- soft rejects, throwing handlers, cleanup.

local Server = game:GetService("ServerScriptService").Server
local RemoteGuard = require(Server.Infrastructure.RemoteGuard)
local Balance = require(Server.Config.Balance)

local NAN, INF = 0 / 0, math.huge
local P = table.pack

-- A SaveSettings patch of n well-formed entries with distinct keys.
local function entries(n)
	local patch = {}
	for i = 1, n do
		patch["k" .. i] = true
	end
	return patch
end

local function make(ready)
	local env = { t = 100, kicks = {}, logs = {}, calls = 0 }
	env.guard = RemoteGuard.new({
		clock = function()
			return env.t
		end,
		ready = ready or function()
			return true
		end,
		kick = function(owner, reason)
			table.insert(env.kicks, { owner = owner, reason = reason })
		end,
		warn = function(message)
			table.insert(env.logs, message)
		end,
	})
	env.handler = function()
		env.calls += 1
		return true
	end
	-- One call per simulated second so the rate limit never interferes.
	function env.call(owner, name, ...)
		env.t += 1
		return env.guard:Call(owner, name, env.handler, ...)
	end
	return env
end

test("valid calls reach the handler with the arguments after seq", function()
	local env, owner = make(), {}
	local got
	env.handler = function(_, ...)
		got = table.pack(...)
		return true
	end
	local ok, code = env.call(owner, "Start", 1)
	expect(ok and code == nil, "Start ok")
	expectEq(got.n, 0, "Start passes no extra args")
	expect(env.call(owner, "Summon", 2), "Summon ok")
	local ok2 = env.call(owner, "Merge", 3, 1, 15)
	expect(ok2 and got.n == 2 and got[1] == 1 and got[2] == 15, "Merge args passed")
end)

test("malformed argument matrix: BadArgs, never reaches the handler, seq not consumed", function()
	local matrix = {
		Start = { P(), P(1, 2), P(1, "x") },
		Summon = { P(), P(1, 2), P(1, nil, nil) },
		EquipDeck = {
			P(),
			P(1),
			P(1, { [2] = "C01" }),
			P(1, { "C01", "C02", "C03", "C04", "C05", "C06" }),
			P(1, { "C01", "C01", "C02", "C03", "C04" }),
			P(1, { "C01", "C02", "C03", "C04", 5 }),
			P(1, { "C01", "C02", "C03", "C04", "" }),
			P(1, { "C01", "C02", "C03", "C04", "123456789" }),
			P(1, { "C01", "C02", "C03", "C04", "C05", x = "C06" }),
			P(1, { [0] = "C01", "C02", "C03", "C04", "C05" }),
			P(1, { [1] = "C01", [2] = "C02", [3] = "C03", [4] = "C04", [6] = "C05" }),
			P(1, "C01"),
			P(1, 5),
			P(1, true),
			P(1, nil),
			P(1, { "C01", "C02", "C03", "C04", "C05" }, 1),
		},
		TeamAction = {
			P(),
			P(1),
			P(1, "Save"),
			P(1, "Save", 0),
			P(1, "Save", 6),
			P(1, "Save", 1.5),
			P(1, "Wipe", 1),
			P(1, 5, 1),
			P(1, "Load", "1"),
			P(1, "Load", NAN),
			P(1, "Load", 1, 1),
		},
		ClaimQuest = {
			P(),
			P(1),
			P(1, ""),
			P(1, ("x"):rep(17)),
			P(1, 5),
			P(1, {}),
			P(1, true),
			P(1, nil),
			P(1, NAN),
			P(1, "S1", "S1"),
		},
		RedeemCode = {
			P(),
			P(1),
			P(1, ""),
			P(1, ("A"):rep(33)),
			P(1, ("A"):rep(4096)),
			P(1, "WEL COME"),
			P(1, " WELCOME"),
			P(1, "WELCOME\n"),
			P(1, "WEL\0COME"),
			P(1, "WEL\tCOME"),
			P(1, "WEL\127COME"),
			P(1, "CAF\u{C9}"),
			P(1, "WELCOME\u{200B}"),
			P(1, "WELCOME!"),
			P(1, "WEL.COME"),
			P(1, NAN),
			P(1, 5),
			P(1, {}),
			P(1, { "WELCOME" }),
			P(1, true),
			P(1, nil),
			P(1, "WELCOME", "WELCOME"),
			P(1, "WELCOME", nil),
		},
		SaveSettings = {
			P(),
			P(1),
			P(1, nil),
			P(1, "shadows"),
			P(1, 5),
			P(1, true),
			P(1, entries(21)), -- more entries than the registry has
			P(1, { true }), -- array: a number key
			P(1, { [1] = true, shadows = true }),
			P(1, { [true] = true }),
			P(1, { [""] = true }),
			P(1, { [("k"):rep(33)] = true }),
			P(1, { shadows = {} }),
			P(1, { shadows = { true } }),
			P(1, { uiScale = NAN }),
			P(1, { uiScale = INF }),
			P(1, { uiScale = -INF }),
			P(1, { language = ("x"):rep(33) }),
			P(1, { language = ("x"):rep(40) }),
			P(1, { shadows = print }),
			P(1, setmetatable({}, {})),
			P(1, { shadows = true }, 1),
			P(1, { shadows = true }, nil),
		},
		BagAction = {
			P(),
			P(1),
			P(1, "Sell"),
			P(1, "Sell", "Fragment"), -- missing qty
			P(1, "Sell", "Fragment", 1, 1), -- extra arg
			P(1, "Sell", "Fragment", 1, nil),
			P(1, "Nope", "Fragment", 1),
			P(1, "sell", "Fragment", 1),
			P(1, "", "Fragment", 1),
			P(1, 5, "Fragment", 1),
			P(1, nil, "Fragment", 1),
			P(1, {}, "Fragment", 1),
			P(1, "Sell", "", 1), -- "" only with Unequip
			P(1, "Use", "", 1),
			P(1, "Lock", "", 1),
			P(1, "Unlock", "", 1),
			P(1, "Equip", "", 1),
			P(1, "Sell", ("x"):rep(17), 1),
			P(1, "Sell", 5, 1),
			P(1, "Sell", nil, 1),
			P(1, "Sell", {}, 1),
			P(1, "Sell", "Fragment", 0),
			P(1, "Sell", "Fragment", -1),
			P(1, "Sell", "Fragment", 1.5),
			P(1, "Sell", "Fragment", NAN),
			P(1, "Sell", "Fragment", INF),
			P(1, "Sell", "Fragment", 1e7),
			P(1, "Sell", "Fragment", "1"),
			P(1, "Sell", "Fragment", nil),
			P(1, "Lock", "Fragment", 2), -- qty is 1 unless Sell or Use
			P(1, "Unlock", "Fragment", 2),
			P(1, "Equip", "ThornDice", 2),
			P(1, "Unequip", "ThornDice", 2),
			P(1, "Unequip", "", 2),
		},
		Roll = {
			P(),
			P(1),
			P(1, "Standard"), -- missing count
			P(1, "Standard", 1, 1), -- extra arg
			P(1, "Standard", 1, nil),
			P(1, 5, 1), -- non-string pool
			P(1, nil, 1),
			P(1, {}, 1),
			P(1, true, 1),
			P(1, "", 1),
			P(1, ("x"):rep(17), 1), -- 17-byte pool
			P(1, "Standard", 0),
			P(1, "Standard", 51),
			P(1, "Standard", -1),
			P(1, "Standard", 1.5),
			P(1, "Standard", NAN),
			P(1, "Standard", INF),
			P(1, "Standard", "1"),
			P(1, "Standard", nil),
			P(1, "Standard", {}),
		},
		Buy = {
			P(),
			P(1),
			P(1, "Frag20", 1), -- extra arg
			P(1, "Frag20", nil),
			P(1, 5), -- non-string id
			P(1, nil),
			P(1, {}),
			P(1, true),
			P(1, ""), -- empty id
			P(1, ("x"):rep(17)), -- 17-byte id
		},
		UpgradeDie = {
			P(),
			P(1),
			P(1, "C01", "C02"), -- extra arg
			P(1, "C01", nil),
			P(1, nil),
			P(1, 5),
			P(1, true),
			P(1, {}),
			P(1, ""),
			P(1, ("x"):rep(9)), -- 9-byte id
			P(1, ("x"):rep(4096)),
			P(1, NAN),
		},
		PowerUp = {
			P(),
			P(1),
			P(1, "C01", "C02"), -- extra arg
			P(1, "C01", nil),
			P(1, nil),
			P(1, 5),
			P(1, true),
			P(1, {}),
			P(1, ""),
			P(1, ("x"):rep(9)), -- 9-byte id
			P(1, ("x"):rep(4096)),
			P(1, NAN),
			P(1, INF),
		},
		AdminAction = {
			P(1, "Give", 123, "Gold", ""),
			P(1, "Give", {}, "Gold", "", 1),
			P(1, "Give", 123, "Gold", "Gold", 1),
			P(1, "Give", 123, "Cosmetics", "Trail", 2),
			P(1, "Take", 123, "Dice", "C01", 0),
			P(1, "Revoke", 123, "Items", "XpTome", 1),
			P(1, "Revoke", 123, "Dice", "C01", 2),
			P(1, "Reset", 123, "", "", 0),
		},
		CoopReady = { P(1), P(1, "true"), P(1, true, 2) },
		QueueDuel = { P(1), P(1, "true"), P(1, true, 2), P(1, 1), P(1, nil), P(1, {}) },
		Surrender = { P(), P(1, true), P(1, 1) },
		LeaveDuel = { P(), P(1, true), P(1, 1) },
		TutorialAction = { P(1, "Claim"), P(1, "Other", ""), P(1, "Convert", ""), P(1, "End", "R01") },
		Merge = {
			P(),
			P(1),
			P(1, 1),
			P(1, 1, 2, 3),
			P(1, 0, 1),
			P(1, 1, 0),
			P(1, 16, 1),
			P(1, 1, 16),
			P(1, -1, 2),
			P(1, 1.5, 2),
			P(1, 1, 2.5),
			P(1, NAN, 2),
			P(1, 1, NAN),
			P(1, INF, 2),
			P(1, -INF, 2),
			P(1, "1", 2),
			P(1, 1, "2"),
			P(1, nil, 2),
			P(1, 1, nil),
			P(1, {}, 2),
			P(1, true, 2),
		},
	}
	local valid = {
		Start = P(1),
		Summon = P(1),
		Merge = P(1, 1, 2),
		EquipDeck = P(1, { "C01", "C02", "C03", "C04", "C05" }),
		TeamAction = P(1, "Save", 1),
		ClaimQuest = P(1, "S1"),
		RedeemCode = P(1, "WELCOME"),
		SaveSettings = P(1, { shadows = false }),
		BagAction = P(1, "Sell", "Fragment", 1),
		Roll = P(1, "Standard", 1),
		Buy = P(1, "Frag20"),
		UpgradeDie = P(1, "C01"),
		PowerUp = P(1, "C01"),
		AdminAction = P(1, "Give", 123, "Gold", "", 1),
		CoopReady = P(1, true),
		QueueDuel = P(1, true),
		Surrender = P(1),
		LeaveDuel = P(1),
		TutorialAction = P(1, "Roll", ""),
	}
	for name in RemoteGuard.Specs do
		expect(matrix[name] ~= nil and valid[name] ~= nil, name .. " is covered by the matrix")
	end
	for name, cases in matrix do
		for index, args in cases do
			local env, owner = make(), {}
			local ok, code = env.call(owner, name, table.unpack(args, 1, args.n))
			expect(not ok and code == "BadArgs", ("%s case %d rejected (%s)"):format(name, index, tostring(code)))
			expectEq(env.calls, 0, ("%s case %d handler not called"):format(name, index))
			local again = valid[name]
			expect(
				env.call(owner, name, table.unpack(again, 1, again.n)),
				("%s case %d did not consume seq 1"):format(name, index)
			)
		end
	end
end)

test("AdminAction authorizes the requester independently of the target user ID", function()
	local Admin = require(Server.Rules.Admin)
	local env = make(function(player, remote)
		return remote == "AdminAction" and Admin.IsAllowed(player.UserId), "Forbidden"
	end)
	local ok, code = env.call({ UserId = 123 }, "AdminAction", 1, "Reset", 855002824, "", "RESET", 0)
	expect(not ok and code == "Forbidden", "an allowlisted target grants no permission to the requester")
	expectEq(env.calls, 0, "rejected before the handler")
	expect(env.call({ UserId = 855002824 }, "AdminAction", 1, "Revoke", 123, "Dice", "R01", 1), "allowlisted requester")
	expectEq(env.calls, 1, "authorized action reaches the handler")
end)

test("exact arg count: extra and missing args fail, nil seq is BadSeq", function()
	local env, owner = make(), {}
	local _, c1 = env.call(owner, "Start")
	expectEq(c1, "BadArgs", "none")
	local _, c2 = env.call(owner, "Start", 1, 1)
	expectEq(c2, "BadArgs", "extra")
	local _, c3 = env.call(owner, "Start", nil)
	expectEq(c3, "BadSeq", "nil seq")
	expectEq(env.calls, 0, "handler untouched")
end)

test("seq must be an integer in [1, 2^31-1]", function()
	for _, bad in { 0, -1, 1.5, NAN, INF, -INF, "1", {}, true, 2 ^ 31, 2 ^ 40 } do
		local env, owner = make(), {}
		local ok, code = env.call(owner, "Start", bad)
		expect(not ok and code == "BadSeq", "rejected " .. tostring(bad))
		expectEq(env.calls, 0, "handler untouched for " .. tostring(bad))
	end
	local env, owner = make(), {}
	expect(env.call(owner, "Start", 2 ^ 31 - 1), "max seq accepted")
	local ok, code = env.call(owner, "Start", 2 ^ 31 - 1)
	expect(not ok and code == "BadSeq", "and cannot repeat")
end)

test("replayed and out-of-order seq are rejected; increasing seq with gaps is fine", function()
	local env, owner = make(), {}
	expect(env.call(owner, "Summon", 5), "5 ok")
	local _, replay = env.call(owner, "Summon", 5)
	expectEq(replay, "BadSeq", "replay")
	local _, older = env.call(owner, "Summon", 4)
	expectEq(older, "BadSeq", "older")
	expect(env.call(owner, "Summon", 6), "6 ok")
	expect(env.call(owner, "Merge", 100, 1, 2), "gap ok, seq shared across remotes")
	local _, cross = env.call(owner, "Start", 50)
	expectEq(cross, "BadSeq", "seq is per player, not per remote")
	expectEq(env.calls, 3, "only valid calls ran")
end)

test("token bucket per player and remote: burst, refill, independence", function()
	local env, a, b = make(), {}, {}
	local function raw(owner, name, seq)
		return env.guard:Call(owner, name, env.handler, seq)
	end
	local burst = Balance.Remotes.Start.burst
	for i = 1, burst do
		expect(raw(a, "Start", i), "start " .. i)
	end
	local ok, code = raw(a, "Start", burst + 1)
	expect(not ok and code == "RateLimited", "over burst")
	expect(raw(b, "Start", 1), "other player unaffected")
	expect(raw(a, "Summon", burst + 2), "other remote unaffected")
	env.t += 1 / Balance.Remotes.Start.rate
	expect(raw(a, "Start", burst + 3), "refilled after 1/rate seconds")
	local ok2, code2 = raw(a, "Start", burst + 4)
	expect(not ok2 and code2 == "RateLimited", "only one token refilled")
	local c = {}
	for i = 1, Balance.Remotes.Summon.burst do
		expect(raw(c, "Summon", i), "summon " .. i)
	end
	local _, limited = raw(c, "Summon", 99)
	expectEq(limited, "RateLimited", "summon over burst")
end)

test("summon rate limit supports the client sending every 0.125 seconds", function()
	local env, owner = make(), {}
	local source = __sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/NetClient"]
	local interval = tonumber(string.match(source, "\n%s*Summon = ([%d%.]+),"))
	expectEq(interval, 0.125, "client summon interval")
	for seq = 1, 32 do
		expect(env.guard:Call(owner, "Summon", env.handler, seq), "summon " .. seq)
		env.t += interval or 0
	end
	expectEq(env.guard:Violations(owner), 0, "regular summons are never rate-limited")
end)

test("soft rejections are never counted and never kick", function()
	local env, owner = make(), {}
	env.handler = function()
		return false, "NoMP"
	end
	for i = 1, 60 do
		local ok, code = env.call(owner, "Summon", i)
		expect(not ok and code == "NoMP", "soft code returned")
	end
	expectEq(env.guard:Violations(owner), 0, "no violations")
	expectEq(#env.kicks, 0, "no kick")
	-- Not ready: soft, not counted, seq not consumed.
	local notOwner = make(function()
		return false, "NotOwner"
	end)
	for _ = 1, 30 do
		local ok, code = notOwner.call(owner, "Start", 1)
		expect(not ok and code == "NotOwner", "ready code returned")
	end
	expectEq(notOwner.guard:Violations(owner), 0, "ready rejects not counted")
	expectEq(#notOwner.kicks, 0, "no kick for ready rejects")
end)

test("seq is consumed even when the rules reject", function()
	local env, owner = make(), {}
	env.handler = function()
		return false, "BoardFull"
	end
	local _, code = env.call(owner, "Summon", 7)
	expectEq(code, "BoardFull", "soft reject")
	local _, replay = env.call(owner, "Summon", 7)
	expectEq(replay, "BadSeq", "same seq now a replay")
end)

test("hard violations kick exactly once at the threshold; logs are throttled", function()
	local env, owner = make(), {}
	for i = 1, Balance.KickThreshold - 1 do
		env.call(owner, "Start", 0)
		expectEq(#env.kicks, 0, "no kick yet at " .. i)
	end
	env.call(owner, "Start", 0)
	expectEq(#env.kicks, 1, "kicked at threshold")
	expectEq(env.kicks[1].owner, owner, "kicked the offender")
	for _ = 1, 30 do
		env.call(owner, "Start", 0)
	end
	expectEq(#env.kicks, 1, "kick fires once")
	expect(#env.logs >= 1 and #env.logs < env.guard:Violations(owner), "logs throttled: " .. #env.logs)
	local other = {}
	expect(env.call(other, "Start", 1), "other player unaffected")
	expectEq(env.guard:Violations(other), 0, "violations are per player")
end)

test("rate-limit and BadArgs count toward the kick", function()
	local env, owner = make(), {}
	for i = 1, 10 do
		env.guard:Call(owner, "Start", env.handler, i) -- same instant: 2 pass, 8 limited
	end
	expectEq(env.guard:Violations(owner), 8, "rate limits counted")
	for _ = 1, 12 do
		env.call(owner, "Start", 1, 2)
	end
	expectEq(#env.kicks, 1, "kicked from mixed violations")
end)

test("throwing handler, ready and kick callbacks never throw out of the guard", function()
	local env, owner = make(), {}
	env.handler = function()
		error("boom")
	end
	local ok, code = env.call(owner, "Summon", 1)
	expect(not ok and code == "Error", "handler error contained")
	expect(#env.logs >= 1, "logged")
	local _, replay = env.call(owner, "Summon", 1)
	expectEq(replay, "BadSeq", "seq was consumed")

	local bad = make(function()
		error("ready boom")
	end)
	local ok2, code2 = bad.call(owner, "Start", 1)
	expect(not ok2 and code2 == "NotLoaded", "throwing ready is NotLoaded")

	local kickBoom = RemoteGuard.new({
		clock = function()
			return 1
		end,
		kick = function()
			error("kick boom")
		end,
		warn = function() end,
		kickThreshold = 1,
	})
	local ok3, code3 = kickBoom:Call(owner, "Start", function()
		return true
	end, 0)
	expect(not ok3 and code3 == "BadSeq", "throwing kick contained")
end)

test("unknown remote is refused; Forget drops all per-player state", function()
	local env, owner = make(), {}
	local ok, code = env.call(owner, "Nope", 1)
	expect(not ok and code == "BadArgs", "unknown remote")
	expect(env.call(owner, "Start", 5), "seq 5")
	env.call(owner, "Start", 0)
	expect(env.guard:Violations(owner) > 0, "has violations")
	env.guard:Forget(owner)
	expectEq(env.guard:Violations(owner), 0, "violations cleared")
	expectEq(env.guard._players[owner], nil, "state released")
	expect(env.call(owner, "Start", 1), "seq state reset too")
end)

test("Strike counts toward the threshold and kicks exactly once", function()
	local env, owner = make(), {}
	for i = 1, Balance.KickThreshold - 1 do
		env.guard:Strike(owner, "State", "BadRemote")
		expectEq(#env.kicks, 0, "no kick yet at " .. i)
	end
	env.guard:Strike(owner, "State", "BadRemote")
	expectEq(#env.kicks, 1, "kicked at threshold")
	expectEq(env.kicks[1].reason, "BadRemote", "reason")
	for _ = 1, 10 do
		env.guard:Strike(owner, "Enemies", "BadRemote")
	end
	expectEq(#env.kicks, 1, "once only")
end)

test("EquipDeck and ClaimQuest pass their arguments through; ids of 1 and 16 bytes are well formed", function()
	local env, owner = make(), {}
	local got
	env.handler = function(_, ...)
		got = table.pack(...)
		return true
	end
	local ids = { "C05", "C04", "C03", "C02", "C01" }
	expect(env.call(owner, "EquipDeck", 1, ids), "EquipDeck ok")
	expect(got.n == 1 and got[1] == ids, "ids passed")
	expect(env.call(owner, "ClaimQuest", 2, "S1"), "ClaimQuest ok")
	expect(got.n == 1 and got[1] == "S1", "id passed")
	expect(env.call(owner, "ClaimQuest", 3, "x"), "1 byte")
	expect(env.call(owner, "ClaimQuest", 4, ("x"):rep(16)), "16 bytes")
	expect(env.call(owner, "EquipDeck", 5, { "C01" }), "partial deck reaches the handler")
	expect(env.call(owner, "EquipDeck", 6, {}), "clearing the deck reaches the handler")
end)

test("EquipDeck and ClaimQuest buckets match Balance (burst 3 and 4), per remote", function()
	expectEq(Balance.Remotes.EquipDeck.burst, 3, "equip burst")
	expectEq(Balance.Remotes.ClaimQuest.burst, 4, "claim burst")
	local env, owner = make(), {}
	local ids = { "C01", "C02", "C03", "C04", "C05" }
	local seq = 0
	local function raw(name, arg)
		seq += 1
		return env.guard:Call(owner, name, env.handler, seq, arg)
	end
	for i = 1, 3 do
		expect(raw("EquipDeck", ids), "equip " .. i)
	end
	local ok, code = raw("EquipDeck", ids)
	expect(not ok and code == "RateLimited", "equip 4th limited")
	for i = 1, 4 do
		expect(raw("ClaimQuest", "S1"), "claim " .. i)
	end
	local ok2, code2 = raw("ClaimQuest", "S1")
	expect(not ok2 and code2 == "RateLimited", "claim 5th limited")
end)

test("seq is shared: a seq used on Summon is BadSeq on EquipDeck and ClaimQuest", function()
	local env, owner = make(), {}
	expect(env.call(owner, "Summon", 5), "Summon 5")
	local _, equip = env.call(owner, "EquipDeck", 5, { "C01", "C02", "C03", "C04", "C05" })
	expectEq(equip, "BadSeq", "equip replay")
	local _, claim = env.call(owner, "ClaimQuest", 5, "S1")
	expectEq(claim, "BadSeq", "claim replay")
	local _, older = env.call(owner, "ClaimQuest", 4, "S1")
	expectEq(older, "BadSeq", "claim older")
	expect(env.call(owner, "EquipDeck", 6, { "C01", "C02", "C03", "C04", "C05" }), "fresh seq ok")
	expectEq(env.calls, 2, "only valid calls ran")
end)

test("soft codes from the new handlers are not counted and never kick", function()
	local env, owner = make(), {}
	local codes =
		{ "WrongPhase", "UnknownDie", "NotOwned", "UnknownQuest", "NotComplete", "AlreadyClaimed", "Overflow" }
	local seq = 0
	for round = 1, 8 do
		env.t += 2 -- refill buckets
		for i, code in codes do
			env.handler = function()
				return false, code
			end
			env.t += 1
			seq += 1
			local name = if i <= 3 then "EquipDeck" else "ClaimQuest"
			local arg = if i <= 3 then { "C01", "C02", "C03", "C04", "C05" } else "S1"
			local ok, got = env.guard:Call(owner, name, env.handler, seq, arg)
			expect(not ok and got == code, ("round %d %s"):format(round, code))
		end
	end
	expectEq(env.guard:Violations(owner), 0, "no violations")
	expectEq(#env.kicks, 0, "no kick")
end)

test("RedeemCode passes the text through as typed; 1 and 32 bytes of [A-Za-z0-9_-] are well formed", function()
	local env, owner = make(), {}
	local got
	env.handler = function(_, ...)
		got = table.pack(...)
		return true
	end
	expect(env.call(owner, "RedeemCode", 1, "welcome"), "lower case ok")
	expect(got.n == 1 and got[1] == "welcome", "text passed unchanged")
	expect(env.call(owner, "RedeemCode", 2, "a"), "1 byte")
	expect(env.call(owner, "RedeemCode", 3, ("Z"):rep(32)), "32 bytes")
	expect(env.call(owner, "RedeemCode", 4, "Az09-_"), "every allowed class")
end)

test("RedeemCode: replayed and out-of-order seq are BadSeq; bucket is burst 3 at 1/s", function()
	expectEq(Balance.Remotes.RedeemCode.rate, 1, "rate")
	expectEq(Balance.Remotes.RedeemCode.burst, 3, "burst")
	local env, owner = make(), {}
	expect(env.call(owner, "RedeemCode", 5, "WELCOME"), "5 ok")
	local _, replay = env.call(owner, "RedeemCode", 5, "WELCOME")
	expectEq(replay, "BadSeq", "replay")
	local _, older = env.call(owner, "RedeemCode", 4, "WELCOME")
	expectEq(older, "BadSeq", "older")
	expect(env.call(owner, "Summon", 6), "Summon 6")
	local _, cross = env.call(owner, "RedeemCode", 6, "WELCOME")
	expectEq(cross, "BadSeq", "seq shared across remotes")
	expectEq(env.calls, 2, "only valid calls ran")
	local other = {}
	for i = 1, 3 do
		expect(env.guard:Call(other, "RedeemCode", env.handler, i, "X"), "burst " .. i)
	end
	local ok, code = env.guard:Call(other, "RedeemCode", env.handler, 4, "X")
	expect(not ok and code == "RateLimited", "4th in the same instant limited")
	env.t += 1
	expect(env.guard:Call(other, "RedeemCode", env.handler, 5, "X"), "one token per second")
end)

test("RedeemCode soft codes are not counted and never kick", function()
	local env, owner = make(), {}
	local seq = 0
	for round = 1, 15 do
		for _, code in { "Invalid", "Expired", "AlreadyRedeemed", "RateLimited" } do
			env.handler = function()
				return false, code
			end
			seq += 1
			local ok, got = env.call(owner, "RedeemCode", seq, "WELCOME")
			expect(not ok and got == code, ("round %d %s"):format(round, code))
		end
	end
	expectEq(env.guard:Violations(owner), 0, "no violations")
	expectEq(#env.kicks, 0, "no kick")
end)

test("SaveSettings passes the patch through; 20 entries and 1/32-byte keys and values are well formed", function()
	local env, owner = make(), {}
	local got
	env.handler = function(_, ...)
		got = table.pack(...)
		return true
	end
	local patch = { shadows = false, uiScale = 85, effectsQuality = "Low" }
	expect(env.call(owner, "SaveSettings", 1, patch), "ok")
	expect(got.n == 1 and got[1] == patch, "patch passed unchanged")
	expect(env.call(owner, "SaveSettings", 2, {}), "empty patch")
	expect(env.call(owner, "SaveSettings", 3, entries(20)), "20 entries (the registry size)")
	expect(
		env.call(owner, "SaveSettings", 4, { k = ("x"):rep(32), [("k"):rep(32)] = "" }),
		"1/32-byte keys, 32/0-byte values"
	)
	expect(
		env.call(owner, "SaveSettings", 5, { nope = 1e300, uiScale = -7.5 }),
		"unknown keys and odd numbers are the rule's job"
	)
	expectEq(env.guard:Violations(owner), 0, "no violations")
end)

test("SaveSettings bucket is burst 3 at 0.5/s; NetClient's interval never trips it", function()
	local limits = Balance.Remotes.SaveSettings
	expect(limits.rate == 0.5 and limits.burst == 3, "Balance")
	local env, owner = make(), {}
	local seq = 0
	local function raw()
		seq += 1
		return env.guard:Call(owner, "SaveSettings", env.handler, seq, { shadows = true })
	end
	for i = 1, 3 do
		expect(raw(), "burst " .. i)
	end
	local ok, code = raw()
	expect(not ok and code == "RateLimited", "4th in the same instant limited")
	env.t += 2
	expect(raw(), "one token per 2 s")
	local ok2, code2 = raw()
	expect(not ok2 and code2 == "RateLimited", "only one refilled")
	expectEq(env.guard:Violations(owner), 2, "RateLimited is a hard violation")

	local source = __sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/NetClient"]
	local interval = tonumber(string.match(source or "", "\n%s*SaveSettings = ([%d%.]+),"))
	expect(
		interval ~= nil and interval >= 1 / limits.rate,
		"NetClient SaveSettings interval >= 1/rate: " .. tostring(interval)
	)
	local honest, sent = make(), {}
	for i = 1, 60 do
		honest.t += interval or 0
		local okI, codeI = honest.guard:Call(sent, "SaveSettings", honest.handler, i, { shadows = i % 2 == 0 })
		expect(okI, ("honest send %d (%s)"):format(i, tostring(codeI)))
	end
	expectEq(honest.guard:Violations(sent), 0, "honest client never limited")
end)

test("BagAction passes action, id and qty through; edge shapes are well formed", function()
	local env, owner = make(), {}
	local got
	env.handler = function(_, ...)
		got = table.pack(...)
		return true
	end
	expect(env.call(owner, "BagAction", 1, "Sell", "Fragment", 3), "ok")
	expect(got.n == 3 and got[1] == "Sell" and got[2] == "Fragment" and got[3] == 3, "args passed")
	expect(env.call(owner, "BagAction", 2, "Use", "XpTome", 1e6), "qty 1e6")
	expect(env.call(owner, "BagAction", 3, "Unequip", "", 1), "Unequip all")
	expect(env.call(owner, "BagAction", 4, "Lock", ("x"):rep(16), 1), "16-byte id (unknown ids are the rule's job)")
	expectEq(env.guard:Violations(owner), 0, "no violations")
end)

test("BagAction bucket is burst 6 at 3/s; soft codes are not counted; NetClient's interval never trips it", function()
	local limits = Balance.Remotes.BagAction
	expect(limits.rate == 3 and limits.burst == 6, "Balance")
	local env, owner = make(), {}
	local seq = 0
	local function raw()
		seq += 1
		return env.guard:Call(owner, "BagAction", env.handler, seq, "Lock", "Fragment", 1)
	end
	for i = 1, 6 do
		expect(raw(), "burst " .. i)
	end
	local ok, code = raw()
	expect(not ok and code == "RateLimited", "7th in the same instant limited")
	env.t += 0.34 -- just over 1/rate ((1/3) * 3 rounds below one token)
	expect(raw(), "one token per 1/rate s")
	expectEq(env.guard:Violations(owner), 1, "RateLimited is a hard violation")

	local soft = make()
	for i, c in { "UnknownItem", "NotOwned", "Insufficient", "Locked", "NotSellable", "NotUsable", "Overflow" } do
		soft.handler = function()
			return false, c
		end
		local okS, codeS = soft.call(owner, "BagAction", i, "Sell", "Fragment", 1)
		expect(not okS and codeS == c, "soft " .. c)
	end
	expectEq(soft.guard:Violations(owner), 0, "soft codes not counted")

	local source = __sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/NetClient"]
	local interval = tonumber(string.match(source or "", "\n%s*BagAction = ([%d%.]+),"))
	expect(
		interval ~= nil and interval >= 1 / limits.rate,
		"NetClient BagAction interval >= 1/rate: " .. tostring(interval)
	)
	local honest, sent = make(), {}
	for i = 1, 60 do
		honest.t += interval or 0
		local okI, codeI = honest.guard:Call(sent, "BagAction", honest.handler, i, "Sell", "Fragment", 1)
		expect(okI, ("honest send %d (%s)"):format(i, tostring(codeI)))
	end
	expectEq(honest.guard:Violations(sent), 0, "honest client never limited")
end)

test("Roll passes pool and count through; 1/16-byte pools and counts 1..50 are well formed", function()
	local env, owner = make(), {}
	local got
	env.handler = function(_, ...)
		got = table.pack(...)
		return true
	end
	expect(env.call(owner, "Roll", 1, "Standard", 50), "ok")
	expect(got.n == 2 and got[1] == "Standard" and got[2] == 50, "args passed")
	expect(env.call(owner, "Roll", 2, "x", 1), "1-byte pool")
	expect(
		env.call(owner, "Roll", 3, ("x"):rep(16), 5),
		"16-byte pool, count 5 (unknown pools and prices are the rule's job)"
	)
	expectEq(env.guard:Violations(owner), 0, "no violations")
end)

test(
	"Roll bucket is burst 2 at 1/s; double-fire is limited; soft codes are not counted; NetClient's interval never trips it",
	function()
		local limits = Balance.Remotes.Roll
		expect(limits.rate == 1 and limits.burst == 2, "Balance")
		local env, owner = make(), {}
		local seq = 0
		local function raw()
			seq += 1
			return env.guard:Call(owner, "Roll", env.handler, seq, "Standard", 1)
		end
		for i = 1, 2 do
			expect(raw(), "burst " .. i)
		end
		local ok, code = raw()
		expect(not ok and code == "RateLimited", "3rd in the same instant limited")
		expectEq(env.calls, 2, "the limited call never reached the handler")
		env.t += 1
		expect(raw(), "one token per second")
		expectEq(env.guard:Violations(owner), 1, "RateLimited is a hard violation")
		local replay = env.guard:Call(owner, "Roll", env.handler, seq, "Standard", 1)
		expect(not replay, "a replayed seq (double-fire of the same request) is refused")

		local soft = make()
		for i, c in { "UnknownPool", "UnknownPrice", "Restricted", "Insufficient", "Overflow" } do
			soft.handler = function()
				return false, c
			end
			local okS, codeS = soft.call(owner, "Roll", i, "Standard", 1)
			expect(not okS and codeS == c, "soft " .. c)
		end
		expectEq(soft.guard:Violations(owner), 0, "soft codes not counted")

		local source = __sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/NetClient"]
		local interval = tonumber(string.match(source or "", "\n%s*Roll = ([%d%.]+),"))
		expect(
			interval ~= nil and interval >= 1 / limits.rate,
			"NetClient Roll interval >= 1/rate: " .. tostring(interval)
		)
		local honest, sent = make(), {}
		for i = 1, 60 do
			honest.t += interval or 0
			local okI, codeI =
				honest.guard:Call(sent, "Roll", honest.handler, i, "Standard", if i % 2 == 0 then 10 else 1)
			expect(okI, ("honest send %d (%s)"):format(i, tostring(codeI)))
		end
		expectEq(honest.guard:Violations(sent), 0, "honest client never limited")
	end
)

test(
	"Buy passes the offer id through (1 and 16 bytes); its bucket is burst 3 at 1/s; NetClient's interval never trips it",
	function()
		local limits = Balance.Remotes.Buy
		expect(limits.rate == 1 and limits.burst == 3, "Balance")
		local env, owner = make(), {}
		local got
		env.handler = function(_, ...)
			got = table.pack(...)
			return true
		end
		local seq = 0
		local function raw(id)
			seq += 1
			return env.guard:Call(owner, "Buy", env.handler, seq, id)
		end
		expect(raw("Frag20"), "ok")
		expect(got.n == 1 and got[1] == "Frag20", "args passed")
		expect(raw("x"), "1-byte id")
		expect(raw(("x"):rep(16)), "16-byte id (unknown offers are the rule's job)")
		local ok, code = raw("Frag20")
		expect(not ok and code == "RateLimited", "4th in the same instant limited")
		expectEq(env.guard:Violations(owner), 1, "RateLimited is a hard violation")

		local soft = make()
		for i, c in { "UnknownOffer", "NotAvailable", "SoldOut", "Insufficient", "Overflow" } do
			soft.handler = function()
				return false, c
			end
			local okS, codeS = soft.call(owner, "Buy", i, "Frag20")
			expect(not okS and codeS == c, "soft " .. c)
		end
		expectEq(soft.guard:Violations(owner), 0, "soft codes not counted")

		local source = __sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/NetClient"]
		local interval = tonumber(string.match(source or "", "\n%s*Buy = ([%d%.]+),"))
		expect(
			interval ~= nil and interval >= 1 / limits.rate,
			"NetClient Buy interval >= 1/rate: " .. tostring(interval)
		)
		local honest, sent = make(), {}
		for i = 1, 60 do
			honest.t += interval or 0
			local okI, codeI = honest.guard:Call(sent, "Buy", honest.handler, i, "Frag20")
			expect(okI, ("honest send %d (%s)"):format(i, tostring(codeI)))
		end
		expectEq(honest.guard:Violations(sent), 0, "honest client never limited")
	end
)

test(
	"UpgradeDie passes the die id through (1 and 8 bytes); bucket 2/s burst 4; soft codes not counted; seq is shared; NetClient never trips it",
	function()
		local limits = Balance.Remotes.UpgradeDie
		expect(limits.rate == 2 and limits.burst == 4, "Balance")
		local env, owner = make(), {}
		local got
		env.handler = function(_, ...)
			got = table.pack(...)
			return true
		end
		local seq = 0
		local function raw(id)
			seq += 1
			return env.guard:Call(owner, "UpgradeDie", env.handler, seq, id)
		end
		expect(raw("C01"), "ok")
		expect(got.n == 1 and got[1] == "C01", "args passed")
		expect(raw("x"), "1-byte id")
		expect(raw(("x"):rep(8)), "8-byte id (unknown dice are the rule's job)")
		expect(raw("C01"), "4th burst token")
		local ok, code = raw("C01")
		expect(not ok and code == "RateLimited", "5th in the same instant limited")
		expectEq(env.guard:Violations(owner), 1, "RateLimited is a hard violation")

		local soft = make()
		for i, c in { "UnknownDie", "NotOwned", "MaxLevel", "Insufficient", "WrongPhase", "BadAmount" } do
			soft.handler = function()
				return false, c
			end
			local okS, codeS = soft.call(owner, "UpgradeDie", i, "C01")
			expect(not okS and codeS == c, "soft " .. c)
		end
		expectEq(soft.guard:Violations(owner), 0, "soft codes not counted")

		local seqEnv = make()
		expect(seqEnv.call(owner, "UpgradeDie", 5, "C01"), "first")
		local dup, dupCode = seqEnv.call(owner, "UpgradeDie", 5, "C01")
		expect(not dup and dupCode == "BadSeq", "duplicate seq")
		expectEq(seqEnv.calls, 1, "handler not called for the duplicate")
		expect(seqEnv.call(owner, "Roll", 10, "Standard", 1), "Roll seq 10")
		local older, olderCode = seqEnv.call(owner, "UpgradeDie", 9, "C01")
		expect(not older and olderCode == "BadSeq", "UpgradeDie seq below an earlier Roll seq")
		expectEq(seqEnv.calls, 2, "handler not called for the older seq")

		local source = __sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/NetClient"]
		local interval = tonumber(string.match(source or "", "\n%s*UpgradeDie = ([%d%.]+),"))
		expect(
			interval ~= nil and interval >= 1 / limits.rate,
			"NetClient UpgradeDie interval >= 1/rate: " .. tostring(interval)
		)
		local honest, sent = make(), {}
		for i = 1, 60 do
			honest.t += interval or 0
			local okI, codeI = honest.guard:Call(sent, "UpgradeDie", honest.handler, i, "C01")
			expect(okI, ("honest send %d (%s)"):format(i, tostring(codeI)))
		end
		expectEq(honest.guard:Violations(sent), 0, "honest client never limited")

		local kicker, bad = make(), {}
		for i = 1, Balance.KickThreshold + 5 do
			kicker.env = nil
			kicker.call(bad, "UpgradeDie", i, 5)
		end
		expectEq(#kicker.kicks, 1, "20 BadArgs kick exactly once")
	end
)

test(
	"PowerUp passes the die id through (1 and 8 bytes); bucket 2/s burst 4; soft codes not counted; seq is shared; NetClient never trips it",
	function()
		local limits = Balance.Remotes.PowerUp
		expect(limits.rate == 2 and limits.burst == 4, "Balance")
		local env, owner = make(), {}
		local got
		env.handler = function(_, ...)
			got = table.pack(...)
			return true
		end
		local seq = 0
		local function raw(id)
			seq += 1
			return env.guard:Call(owner, "PowerUp", env.handler, seq, id)
		end
		expect(raw("C01"), "ok")
		expect(got.n == 1 and got[1] == "C01", "args passed")
		expect(raw("x"), "1-byte id")
		expect(raw(("x"):rep(8)), "8-byte id (NotInDeck is the rule's job)")
		expect(raw("C01"), "4th burst token")
		local ok, code = raw("C01")
		expect(not ok and code == "RateLimited", "5th in the same instant limited")
		expectEq(env.guard:Violations(owner), 1, "RateLimited is a hard violation")

		local soft = make()
		for i, c in { "WrongPhase", "NotInDeck", "MaxTier", "NoMP" } do
			soft.handler = function()
				return false, c
			end
			local okS, codeS = soft.call(owner, "PowerUp", i, "C01")
			expect(not okS and codeS == c, "soft " .. c)
		end
		expectEq(soft.guard:Violations(owner), 0, "soft codes not counted")

		local seqEnv = make()
		expect(seqEnv.call(owner, "PowerUp", 5, "C01"), "first")
		local dup, dupCode = seqEnv.call(owner, "PowerUp", 5, "C01")
		expect(not dup and dupCode == "BadSeq", "duplicate seq")
		expect(seqEnv.call(owner, "Roll", 10, "Standard", 1), "Roll seq 10")
		local older, olderCode = seqEnv.call(owner, "PowerUp", 9, "C01")
		expect(not older and olderCode == "BadSeq", "PowerUp seq below an earlier Roll seq (out of order)")
		expectEq(seqEnv.calls, 2, "handler not called for the duplicate or the older seq")

		local source = __sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/NetClient"]
		local interval = tonumber(string.match(source or "", "\n%s*PowerUp = ([%d%.]+),"))
		expect(
			interval ~= nil and interval >= 1 / limits.rate,
			"NetClient PowerUp interval >= 1/rate: " .. tostring(interval)
		)
		local honest, sent = make(), {}
		for i = 1, 60 do
			honest.t += interval or 0
			local okI, codeI = honest.guard:Call(sent, "PowerUp", honest.handler, i, "C01")
			expect(okI, ("honest send %d (%s)"):format(i, tostring(codeI)))
		end
		expectEq(honest.guard:Violations(sent), 0, "honest client never limited")

		local kicker, bad = make(), {}
		for i = 1, Balance.KickThreshold + 5 do
			kicker.call(bad, "PowerUp", i, 5)
		end
		expectEq(#kicker.kicks, 1, "20 BadArgs kick exactly once")
	end
)
