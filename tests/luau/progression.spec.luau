-- Progression.Level turns a running total into (level, into, need) on a curve.

local Progression = require(game:GetService("ServerScriptService").Server.Config.Progression)

local function expectLevel(xp, curve, level, into, need, label)
	local l, i, n = Progression.Level(xp, curve)
	expect(
		l == level and i == into and n == need,
		("%s: expected (%d, %d, %d), got (%s, %s, %s)"):format(
			label,
			level,
			into,
			need,
			tostring(l),
			tostring(i),
			tostring(n)
		)
	)
end

test("account curve: 100 * level Xp to the next level, max 50", function()
	local account = Progression.Account
	expectEq(account.Max, 50, "max")
	expectLevel(0, account, 1, 0, 100, "0 xp")
	expectLevel(99, account, 1, 99, 100, "99 xp")
	expectLevel(100, account, 2, 0, 200, "100 xp")
	expectLevel(250, account, 2, 150, 200, "250 xp")
	expectLevel(122499, account, 49, 4899, 4900, "one short of max")
	expectLevel(122500, account, 50, 0, 0, "max level")
	expectLevel(1e9, account, 50, 0, 0, "1e9 xp is bounded")
end)

test("bad xp reads as 0", function()
	for _, bad in { -1, 0.5, 0 / 0, math.huge, -math.huge, "100", true, {} } do
		expectLevel(bad, Progression.Account, 1, 0, 100, "xp " .. tostring(bad))
	end
	expectLevel(nil, Progression.Account, 1, 0, 100, "nil xp")
end)

test("mastery curve: 5 * level to the next level, max 20, milestones every 5", function()
	local mastery = Progression.Mastery
	expectEq(mastery.Max, 20, "max")
	expectEq(table.concat(mastery.Milestones, ","), "5,10,15,20", "milestones")
	expectLevel(0, mastery, 1, 0, 5, "0")
	expectLevel(4, mastery, 1, 4, 5, "4")
	expectLevel(5, mastery, 2, 0, 10, "5")
	expectLevel(949, mastery, 19, 94, 95, "one short of max")
	expectLevel(950, mastery, 20, 0, 0, "max")
end)

test("config is frozen", function()
	expect(table.isfrozen(Progression), "module")
	expect(table.isfrozen(Progression.Account) and table.isfrozen(Progression.Mastery), "curves")
	expect(table.isfrozen(Progression.Mastery.Milestones), "milestones")
end)
