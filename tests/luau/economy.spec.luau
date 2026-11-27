-- Economy is the only code that changes MP and Gold.

local Server = game:GetService("ServerScriptService").Server
local Economy = require(Server.Rules.Economy)
local Validate = require(Server.Rules.Validate)

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

test("Sum returns current + delta or a code", function()
	local ok, result = Economy.Sum(10, 5)
	expect(ok and result == 15, "gain")
	ok, result = Economy.Sum(10, -10)
	expect(ok and result == 0, "spend to zero")
	ok, result = Economy.Sum(Economy.MAX - 1, 1)
	expect(ok and result == Economy.MAX, "exactly MAX is allowed")
	ok, result = Economy.Sum(10, -11)
	expect(not ok and result == "Insufficient", "negative result")
	ok, result = Economy.Sum(Economy.MAX, 1)
	expect(not ok and result == "Overflow", "above MAX")
	for _, bad in { NAN, INF, -INF, 0.5, -0.5, "5", true, {}, 2e9, -2e9 } do
		local ok2, code2 = Economy.Sum(10, bad)
		expect(not ok2 and code2 == "BadAmount", "rejects delta " .. tostring(bad))
	end
	for _, corrupt in { NAN, INF, -INF, -5, 1.5, "3", 2e9 } do
		local ok3, code3 = Economy.Sum(corrupt, 1)
		expect(not ok3 and code3 == "BadAmount", "rejects current " .. tostring(corrupt))
	end
	local ok4, code4 = Economy.Sum(nil, 1)
	expect(not ok4 and code4 == "BadAmount", "rejects nil current")
	local ok5, code5 = Economy.Sum(1, nil)
	expect(not ok5 and code5 == "BadAmount", "rejects nil delta")
end)

test("TryChange changes only mp and Gold; Gems and Xp belong to Rewards", function()
	local profile = { Gems = 5, Xp = 40, Materials = {} }
	for _, key in { "Gems", "Xp", "Materials", "Items", "gems", "XP" } do
		local ok, code = Economy.TryChange(profile, key, 1)
		expect(not ok and code == "BadKey", "rejects key " .. key)
	end
	expectEq(snapshot(profile), "Gems=5,Materials=" .. tostring(profile.Materials) .. ",Xp=40", "record unchanged")
end)
