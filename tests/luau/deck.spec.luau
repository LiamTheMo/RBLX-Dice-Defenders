-- Deck: shape matrix, ownership checks, Equip copy and no-mutation-on-reject.

local Server = game:GetService("ServerScriptService").Server
local Deck = require(Server.Rules.Deck)
local Quests = require(Server.Config.Quests)

local NAN, INF = 0 / 0, math.huge
local OWNED = { C01 = {}, C02 = {}, C03 = {}, C04 = {}, C05 = {} }
local GOOD = { "C01", "C02", "C03", "C04", "C05" }

test("Shape accepts a 5 distinct string array in any order", function()
	expect(Deck.Shape(GOOD), "starter")
	expect(Deck.Shape({ "C05", "C01", "C04", "C02", "C03" }), "permutation")
	expect(Deck.Shape({ "a", "b", "c", "d", "12345678" }), "8 byte id")
end)

test("Shape rejects malformed input", function()
	local huge = {}
	for i = 1, 10000 do
		huge[i] = "C" .. i
	end
	local cases = {
		{ "nil", nil },
		{ "string", "C01" },
		{ "number", 5 },
		{ "bool", true },
		{ "empty", {} },
		{ "4", { "C01", "C02", "C03", "C04" } },
		{ "6", { "C01", "C02", "C03", "C04", "C05", "C06" } },
		{ "dup", { "C01", "C01", "C02", "C03", "C04" } },
		{ "number value", { "C01", "C02", "C03", "C04", 5 } },
		{ "table value", { "C01", "C02", "C03", "C04", {} } },
		{ "empty string", { "C01", "C02", "C03", "C04", "" } },
		{ "9 bytes", { "C01", "C02", "C03", "C04", "123456789" } },
		{ "string key", { "C01", "C02", "C03", "C04", "C05", x = "C06" } },
		{ "string key replaces", { "C01", "C02", "C03", "C04", x = "C05" } },
		{ "0 based", { [0] = "C01", "C02", "C03", "C04", "C05" } },
		{ "sparse", { [1] = "C01", [2] = "C02", [3] = "C03", [4] = "C04", [6] = "C05" } },
		{ "fraction key", { [1] = "C01", [2] = "C02", [3] = "C03", [4] = "C04", [4.5] = "C05" } },
		{ "nan value", { "C01", "C02", "C03", "C04", NAN } },
		{ "inf key", { [INF] = "C01", "C02", "C03", "C04", "C05" } },
		{ "nested", { { "C01" }, "C02", "C03", "C04", "C05" } },
		{ "huge", huge },
	}
	for _, c in cases do
		expect(Deck.Shape(c[2]) == false, "rejects " .. c[1])
	end
end)

test("Check: UnknownDie before NotOwned, permutation ok", function()
	expect(Deck.Check(OWNED, GOOD), "starter ok")
	expect(Deck.Check(OWNED, { "C05", "C04", "C03", "C02", "C01" }), "permutation ok")
	local _, unknown = Deck.Check(OWNED, { "C01", "C02", "C03", "C04", "ZZZ" })
	expectEq(unknown, "UnknownDie", "not in catalog")
	local _, notOwned = Deck.Check({ C01 = {} }, GOOD)
	expectEq(notOwned, "NotOwned", "catalog die not owned")
	local _, bad = Deck.Check(OWNED, { "C01" })
	expectEq(bad, "BadDeck", "bad shape")
end)

test("Equip copies the ids; a rejected equip leaves the profile unchanged", function()
	local profile = { Dice = OWNED, Deck = table.clone(GOOD) }
	local ids = { "C05", "C04", "C03", "C02", "C01" }
	expect(Deck.Equip(profile, ids), "equipped")
	expect(profile.Deck ~= ids, "own table")
	ids[1] = "C01"
	expectEq(profile.Deck[1], "C05", "copy independent of caller")
	local before = table.concat(profile.Deck, ",")
	for _, bad in { { "C01" }, { "C01", "C01", "C02", "C03", "C04" }, { "C01", "C02", "C03", "C04", "ZZZ" } } do
		local ok = Deck.Equip(profile, bad)
		expect(not ok, "rejected")
		expectEq(table.concat(profile.Deck, ","), before, "unchanged")
	end
end)

test("quest catalog is well formed", function()
	local seen = {}
	local stats = { RunsPlayed = true, BestWave = true, TrialCleared = true }
	expect(#Quests.List >= 1, "has quests")
	for _, q in Quests.List do
		expect(type(q.Id) == "string" and #q.Id >= 1 and #q.Id <= 16, "id " .. tostring(q.Id))
		expect(not seen[q.Id], "unique " .. q.Id)
		seen[q.Id] = true
		expect(Quests.ById[q.Id] == q, "ById " .. q.Id)
		expect(type(q.Name) == "string" and type(q.Desc) == "string", "text " .. q.Id)
		expect(q.Goal % 1 == 0 and q.Goal >= 1 and q.Gold % 1 == 0 and q.Gold >= 1, "numbers " .. q.Id)
		expect((q.Daily == true) ~= (q.Stat ~= nil and stats[q.Stat] == true), "exactly one source " .. q.Id)
	end
end)
