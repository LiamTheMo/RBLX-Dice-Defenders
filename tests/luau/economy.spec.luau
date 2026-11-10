-- Economy is the only code that changes MP and Gold.

local Server = game:GetService("ServerScriptService").Server
local Economy = require(Server.Rules.Economy)
local Validate = require(Server.Rules.Validate)
local ProfileSchema = require(Server.Rules.ProfileSchema)

local NAN, INF = 0 / 0, math.huge

local function snapshot(t)
	local keys = {}
	for k in t do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	local parts = {}
	for _, k in keys do
		table.insert(parts, k .. "=" .. tostring(t[k]))
	end
	return table.concat(parts, ",")
end

test("Validate.IsInt rejects non-numbers, NaN, inf, fractions and out-of-range", function()
	expect(Validate.IsInt(5, 1, 10), "in range")
	expect(Validate.IsInt(1, 1, 10) and Validate.IsInt(10, 1, 10), "bounds inclusive")
	expect(Validate.IsInt(0) and Validate.IsInt(1e9), "defaults 0..1e9")
	for _, bad in { "5", true, {}, NAN, INF, -INF, 5.5, 0, 11, -1 } do
		expect(not Validate.IsInt(bad, 1, 10), "rejects " .. tostring(bad))
	end
	expect(not Validate.IsInt(nil, 1, 10), "rejects nil")
	expect(not Validate.IsInt(-1), "default lower bound 0")
	expect(not Validate.IsInt(1e9 + 1), "default upper bound")
end)

test("TryChange adds and subtracts exactly", function()
	local state = { mp = 20 }
	expect(Economy.TryChange(state, "mp", 5), "gain")
	expectEq(state.mp, 25, "gained")
	expect(Economy.TryChange(state, "mp", -25), "spend all")
	expectEq(state.mp, 0, "zero is allowed")
	local profile = { Gold = 10 }
	expect(Economy.TryChange(profile, "Gold", 90), "gold gain")
	expectEq(profile.Gold, 100, "gold")
end)

test("TryChange never goes negative", function()
	local state = { mp = 10 }
	local ok, code = Economy.TryChange(state, "mp", -11)
	expect(not ok and code == "Insufficient", "overspend rejected")
	expectEq(state.mp, 10, "unchanged")
end)

test("TryChange rejects NaN, inf, fractions, overflow and bad keys, leaving the record alone", function()
	local state = { mp = 10, summons = 3 }
	local before = snapshot(state)
	for _, bad in { NAN, INF, -INF, 0.5, -0.5, "5", true, {}, 2e9, -2e9 } do
		local ok, code = Economy.TryChange(state, "mp", bad)
		expect(not ok and code == "BadAmount", "rejects delta " .. tostring(bad))
	end
	local ok, code = Economy.TryChange(state, "mp", nil)
	expect(not ok and code == "BadAmount", "rejects nil delta")
	for _, key in { "summons", "MP", "gold", 1, true } do
		local ok2, code2 = Economy.TryChange(state, key, 1)
		expect(not ok2 and code2 == "BadKey", "rejects key " .. tostring(key))
	end
	local ok3, code3 = Economy.TryChange(nil, "mp", 1)
	expect(not ok3 and code3 == "BadKey", "rejects nil record")
	expectEq(snapshot(state), before, "record unchanged")

	local rich = { Gold = Economy.MAX - 1 }
	local ok4, code4 = Economy.TryChange(rich, "Gold", 2)
	expect(not ok4 and code4 == "Overflow", "result above 1e9 rejected")
	expectEq(rich.Gold, Economy.MAX - 1, "gold unchanged")
	expect(Economy.TryChange(rich, "Gold", 1), "exactly 1e9 is allowed")

	for _, corrupt in { NAN, INF, -5, 1.5, "3" } do
		local bad = { mp = corrupt }
		local ok5, code5 = Economy.TryChange(bad, "mp", 1)
		expect(not ok5 and code5 == "BadAmount", "corrupt current value " .. tostring(corrupt))
		expect(bad.mp == corrupt or bad.mp ~= bad.mp, "corrupt value untouched")
	end
end)

test("GrantRunReward pays 50 + 3*waves once per run id and updates the record", function()
	local profile = ProfileSchema.Default()
	local ok, gold = Economy.GrantRunReward(profile, 7, 4, false)
	expect(ok and gold == 62, "62 gold for 4 waves")
	expectEq(profile.Gold, 62, "gold")
	expectEq(profile.BestWave, 4, "best wave")
	expectEq(profile.RunsPlayed, 1, "runs")
	expectEq(profile.TrialCleared, false, "not cleared")
	expectEq(profile.LastRewardRunId, 7, "run id recorded")

	local ok2, code2 = Economy.GrantRunReward(profile, 7, 10, true)
	expect(not ok2 and code2 == "AlreadyGranted", "same run id refused")
	expectEq(profile.Gold, 62, "no second payment")
	expectEq(profile.RunsPlayed, 1, "runs unchanged")

	local ok3, gold3 = Economy.GrantRunReward(profile, 8, 10, true)
	expect(ok3 and gold3 == 80, "win pays 80")
	expectEq(profile.Gold, 142, "gold sums")
	expectEq(profile.BestWave, 10, "best wave raised")
	expectEq(profile.TrialCleared, true, "cleared")

	Economy.GrantRunReward(profile, 9, 1, false)
	expectEq(profile.BestWave, 10, "best wave never lowered")
	expectEq(profile.TrialCleared, true, "cleared never unset")
end)

test("GrantRunReward rejects bad input and leaves the profile unchanged", function()
	local profile = ProfileSchema.Default()
	local before = snapshot(profile)
	local cases = {
		{ nil, 1, false },
		{ 0, 1, false },
		{ 1.5, 1, false },
		{ NAN, 1, false },
		{ "1", 1, false },
		{ 1, -1, false },
		{ 1, 1.5, false },
		{ 1, NAN, false },
		{ 1, INF, false },
		{ 1, 1, "yes" },
		{ 1, 1, nil },
	}
	for index, args in cases do
		local ok = Economy.GrantRunReward(profile, args[1], args[2], args[3])
		expect(not ok, "case " .. index .. " rejected")
	end
	expectEq(snapshot(profile), before, "profile unchanged")

	local capped = ProfileSchema.Default()
	capped.Gold = Economy.MAX - 10
	local capBefore = snapshot(capped)
	local ok, code = Economy.GrantRunReward(capped, 1, 5, true)
	expect(not ok and code == "Overflow", "overflow rejected")
	expectEq(snapshot(capped), capBefore, "no partial update on overflow")
end)
