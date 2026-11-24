-- Teams: five saved loadouts per profile. Shape matrix, save/load rules, cleaning of stale slots, schema round trip.

local Server = game:GetService("ServerScriptService").Server
local Teams = require(Server.Rules.Teams)
local ProfileSchema = require(Server.Rules.ProfileSchema)

local OWNED = { C01 = {}, C02 = {}, C03 = {}, C04 = {}, C05 = {} }
local GOOD = { "C01", "C02", "C03", "C04", "C05" }

local function profile()
	return { Dice = OWNED, Deck = table.clone(GOOD), Teams = {} }
end

test("Shape takes Save or Load with a slot 1..5 and nothing else", function()
	for slot = 1, 5 do
		expect(Teams.Shape("Save", slot) and Teams.Shape("Load", slot), "slot " .. slot)
	end
	for _, c in
		{
			{ "Wipe", 1 },
			{ "Save", 0 },
			{ "Save", 6 },
			{ "Save", 1.5 },
			{ "Save", "1" },
			{ "Save", 0 / 0 },
			{ "Save", math.huge },
			{ 1, 1 },
			{ nil, 1 },
			{ "Save", nil },
		}
	do
		expect(Teams.Shape(c[1], c[2]) == false, "rejects " .. tostring(c[1]) .. "/" .. tostring(c[2]))
	end
end)

test("Save copies the equipped deck into the slot; Load equips it back", function()
	local p = profile()
	expect(Teams.Run(p, "Save", 2), "saved")
	expect(p.Teams["2"] ~= p.Deck, "own table")
	expectEq(table.concat(p.Teams["2"], ","), table.concat(GOOD, ","), "saved ids")
	p.Deck = { "C05", "C04" }
	expect(Teams.Run(p, "Load", 2), "loaded")
	expectEq(table.concat(p.Deck, ","), table.concat(GOOD, ","), "deck restored")
	expect(p.Deck ~= p.Teams["2"], "load copies too")
end)

test("Save needs a die equipped; Load needs a saved team; bad input changes nothing", function()
	local p = profile()
	local _, noTeam = Teams.Run(p, "Load", 3)
	expectEq(noTeam, "EmptyTeam", "nothing saved")
	p.Deck = {}
	local _, noDeck = Teams.Run(p, "Save", 1)
	expectEq(noDeck, "EmptyDeck", "nothing equipped")
	expect(next(p.Teams) == nil, "no slot written")
	local _, bad = Teams.Run(p, "Save", 9)
	expectEq(bad, "BadTeam", "slot out of range")
end)

test("Load of a team holding a die that is no longer owned is refused and keeps the deck", function()
	local p = profile()
	p.Teams["1"] = { "C01", "C02", "C03", "C04", "R09" }
	local before = table.concat(p.Deck, ",")
	local ok = Teams.Run(p, "Load", 1)
	expect(not ok, "refused")
	expectEq(table.concat(p.Deck, ","), before, "deck unchanged")
end)

test("Clean keeps only well formed, fully owned slots", function()
	local stored = {
		["1"] = { "C01", "C02" },
		["2"] = { "C01", "ZZZ" },
		["3"] = {},
		["4"] = "C01",
		["7"] = { "C01" },
		["5"] = { "C01", "C01" },
	}
	local teams = Teams.Clean(stored, OWNED)
	expectEq(table.concat(teams["1"], ","), "C01,C02", "valid slot kept")
	expect(teams["2"] == nil and teams["3"] == nil and teams["4"] == nil, "bad slots dropped")
	expect(teams["5"] == nil and teams["7"] == nil, "duplicates and slot 7 dropped")
	expect(teams["1"] ~= stored["1"], "copy")
	expect(next(Teams.Clean(nil, OWNED)) == nil and next(Teams.Clean("x", OWNED)) == nil, "junk input gives empty")
end)

test("a profile round trips its teams through Migrate and drops stale ones", function()
	local saved = ProfileSchema.Default()
	saved.Teams = { ["1"] = { "C01", "C02", "C03", "C04", "C05" }, ["2"] = { "ZZZ" } }
	local back = ProfileSchema.Migrate(saved)
	expectEq(table.concat(back.Teams["1"], ","), "C01,C02,C03,C04,C05", "kept")
	expect(back.Teams["2"] == nil, "unknown die dropped")
	local old = ProfileSchema.Default()
	old.Teams = nil
	local fresh = ProfileSchema.Migrate(old)
	expect(type(fresh.Teams) == "table" and next(fresh.Teams) == nil, "missing field starts empty")
end)
