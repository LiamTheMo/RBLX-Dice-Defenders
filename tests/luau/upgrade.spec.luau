-- Rules/Upgrade.Die: spare copies of a die buy +1 level at Progression.DieLevel.Copies[level]. Every
-- rejection leaves the profile deep-equal; success is one write; Catalog carries a read-only copy.

local Server = game:GetService("ServerScriptService").Server
local Upgrade = require(Server.Rules.Upgrade)
local Roll = require(Server.Rules.Roll)
local Catalog = require(Server.Rules.Catalog)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local Progression = require(Server.Config.Progression)

local DL = Progression.DieLevel

local function profile(level, copies, gold)
	local p = ProfileSchema.Default()
	p.Dice.C01 = { Level = level, Copies = copies }
	p.Gold = gold or 10000000
	return p
end

local function refused(p, id, code, label)
	local before = snap(p)
	local ok, got = Upgrade.Die(p, id)
	expect(not ok and got == code, ("%s: %s (got %s)"):format(label, code, tostring(got)))
	expectEq(snap(p), before, label .. " leaves the profile deep-equal")
end

test("the cost table: Max 12, Max - 1 whole copy costs and gold / crit for every class a rarity reaches", function()
	expectEq(DL.Max, 12, "Max")
	expectEq(#DL.Copies, DL.Max - 1, "one cost per level-up")
	for level, cost in DL.Copies do
		expect(cost % 1 == 0 and cost >= 1, "cost " .. level)
	end
	local top = 0
	for _, offset in DL.Offset do
		top = math.max(top, offset)
	end
	expect(#DL.Gold >= DL.Max - 1 + top and #DL.Crit >= DL.Max - 1 + top, "curves cover the highest-offset rarity")
	for class = 1, #DL.Gold do
		expect(DL.Gold[class] >= 1 and DL.Gold[class] % 1 == 0, "gold " .. class)
		expect(DL.Crit[class] > 0, "crit " .. class)
		expect(class == 1 or DL.Gold[class] >= DL.Gold[class - 1], "gold never falls " .. class)
	end
end)

test("rarer dice start further up the gold and crit curves", function()
	expectEq(Progression.GoldCost("Common", 1), DL.Gold[1], "Common first step")
	expectEq(Progression.GoldCost("Rare", 1), DL.Gold[3], "Rare first step is class 3")
	expectEq(Progression.GoldCost("Legendary", 1), DL.Gold[7], "Legendary first step is class 7")
	expectEq(Progression.CritGain("Rare", 1), DL.Crit[3], "Rare crit gain")
	expectEq(Progression.CritOf("Common", 1), 0, "level 1 earns nothing")
	expectEq(Progression.CritOf("Common", 4), DL.Crit[1] + DL.Crit[2] + DL.Crit[3], "sum of the steps so far")
end)

test("Shape: strings of 1..8 bytes only", function()
	expect(Upgrade.Shape("C01") and Upgrade.Shape("x") and Upgrade.Shape(("x"):rep(8)), "valid")
	for _, bad in { "", ("x"):rep(9), ("x"):rep(4096), 5, true, {}, NAN, INF } do
		expect(not Upgrade.Shape(bad), "rejected " .. tostring(bad))
	end
	expect(not Upgrade.Shape(nil), "nil rejected")
end)

test("UnknownDie, NotOwned, MaxLevel leave the profile deep-equal", function()
	local p = profile(2, 9)
	for _, id in { "Z99", "Z98", "__index", "", 5, true } do
		refused(p, id, "UnknownDie", "id " .. tostring(id))
	end
	refused(p, nil, "UnknownDie", "nil id")
	refused(p, "R01", "NotOwned", "unowned R01")
	refused(p, "M01", "NotOwned", "M01 never owned")
	refused(profile(DL.Max, 99), "C01", "MaxLevel", "at the cap with 99 copies")
end)

test("copies exactly at the cost level up; one below is Insufficient", function()
	for level = 1, DL.Max - 1 do
		local cost = DL.Copies[level]
		local gold = Progression.GoldCost("Common", level)
		local p2 = profile(level, cost, gold)
		local ok, code = Upgrade.Die(p2, "C01")
		expect(ok and code == nil, "level " .. level .. " at cost")
		expect(
			p2.Dice.C01.Copies == 0 and p2.Dice.C01.Level == level + 1 and p2.Gold == 0,
			"spent copies and gold, +1 level"
		)
		refused(profile(level, cost, gold - 1), "C01", "NoGold", "level " .. level .. " one gold short")
		refused(profile(level, cost - 1), "C01", "Insufficient", "level " .. level .. " one below")
	end
end)

test("a full climb 1 -> Max spends exactly the table total, then MaxLevel", function()
	local total = 0
	for _, cost in DL.Copies do
		total += cost
	end
	local goldTotal = 0
	for level = 1, DL.Max - 1 do
		goldTotal += Progression.GoldCost("Common", level)
	end
	local p = profile(1, total + 4, goldTotal + 9)
	for level = 1, DL.Max - 1 do
		expect(Upgrade.Die(p, "C01"), "climb " .. level)
	end
	expect(p.Dice.C01.Level == DL.Max and p.Dice.C01.Copies == 4, "spent exactly the total")
	expectEq(p.Gold, 9, "spent exactly the gold total")
	expectEq(Upgrade.CritBonus(p), Progression.CritOf("Common", DL.Max), "a maxed die earns its full crit")
	refused(p, "C01", "MaxLevel", "after the climb")
end)

test("CritBonus sums every owned die; junk entries count for nothing", function()
	local p = ProfileSchema.Default()
	p.Dice = { C01 = { Level = 4, Copies = 0 }, R01 = { Level = 3, Copies = 0 }, Z99 = { Level = 9, Copies = 0 } }
	local want = Progression.CritOf("Common", 4) + Progression.CritOf("Rare", 3)
	expectEq(Upgrade.CritBonus(p), want, "Common Lv4 + Rare Lv3, unknown die ignored")
	p.Dice.C01.Level = NAN
	expectEq(Upgrade.CritBonus(p), Progression.CritOf("Rare", 3), "a corrupt level counts for nothing")
	expectEq(Upgrade.CritBonus({}), 0, "no dice table")
end)

test("corrupt entries are BadAmount and untouched", function()
	for _, level in { 0, DL.Max + 1, 1.5, NAN, "3", -1 } do
		refused(profile(level, 50), "C01", "BadAmount", "Level " .. tostring(level))
	end
	for _, copies in { -1, INF, 1e10, NAN, "5", 1.5 } do
		refused(profile(2, copies), "C01", "BadAmount", "Copies " .. tostring(copies))
	end
	local frozen = ProfileSchema.Default()
	frozen.Dice.C01 = table.freeze({ Level = 2, Copies = 9 })
	refused(frozen, "C01", "BadAmount", "frozen entry")
	local meta = ProfileSchema.Default()
	meta.Dice.C01 = setmetatable({ Level = 2, Copies = 9 }, {})
	refused(meta, "C01", "BadAmount", "entry with a metatable")
	local notTable = ProfileSchema.Default()
	notTable.Dice.C01 = "x"
	refused(notTable, "C01", "BadAmount", "non-table entry")
end)

test("Catalog.Build().DieLevel equals the config and is a clone", function()
	local c = Catalog.Build().DieLevel
	expectEq(c.Max, DL.Max, "Max")
	expectEq(snap(c.Copies), snap(DL.Copies), "Copies")
	expect(c.Copies ~= DL.Copies and not table.isfrozen(c.Copies), "nothing shared with the config")
	c.Copies[1] = 999
	expect(DL.Copies[1] ~= 999, "mutating the clone leaves the config")
end)

test("interleaving Roll.Buy and Upgrade.Die keeps Copies >= 0, Level <= Max and spends exactly the cost", function()
	local cum = { 0 } -- cum[level] = copies spent to reach `level`
	for level = 2, DL.Max do
		cum[level] = cum[level - 1] + DL.Copies[level - 1]
	end
	local p = ProfileSchema.Default()
	p.Gems = 100000
	p.Gold = 1000000000
	local rng = Random.new(7)
	local function held() -- per die: copies still held plus copies sunk into levels
		local out = {}
		for id, e in p.Dice do
			expect(e.Copies >= 0 and e.Level >= 1 and e.Level <= DL.Max, id .. " in range")
			out[id] = e.Copies + cum[e.Level]
		end
		return out
	end
	for step = 1, 300 do
		local before = held()
		if step % 3 == 0 then
			expect(Roll.Buy(p, "Standard", 1, true, rng), "roll " .. step)
			local after = held()
			for id, was in before do
				expect(after[id] >= was, id .. " never loses copies to a roll")
			end
		else
			local ids = {}
			for id in p.Dice do
				table.insert(ids, id)
			end
			table.sort(ids)
			Upgrade.Die(p, ids[rng:NextInteger(1, #ids)])
			local after = held()
			for id, was in before do
				expectEq(after[id], was, id .. " upgrade conserves copies")
			end
		end
	end
end)

test("Rules/Upgrade never yields", function()
	local source = __sources["ServerScriptService/Server/Rules/Upgrade"]
	expect(source ~= nil, "source readable")
	for _, word in { "task%.", "wait", ":Wait", "Invoke" } do
		expect(not string.find(source, word), "no " .. word)
	end
end)
