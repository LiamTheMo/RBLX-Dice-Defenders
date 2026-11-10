-- RemoteGuard: rate limits, exact argument matrix, seq rules, kick threshold,
-- soft rejects, throwing handlers, cleanup.

local Server = game:GetService("ServerScriptService").Server
local RemoteGuard = require(Server.Infrastructure.RemoteGuard)
local Balance = require(Server.Config.Balance)

local NAN, INF = 0 / 0, math.huge
local P = table.pack

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
	local valid = { Start = P(1), Summon = P(1), Merge = P(1, 1, 2) }
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

test("soft rejections are never counted and never kick", function()
	local env, owner = make(), {}
	env.handler = function()
		return false, "NoEnergy"
	end
	for i = 1, 60 do
		local ok, code = env.call(owner, "Summon", i)
		expect(not ok and code == "NoEnergy", "soft code returned")
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
