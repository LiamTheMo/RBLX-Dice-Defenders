-- Rewards.Apply is the single bundle writer: all of a bundle or none of it.

local Server = game:GetService("ServerScriptService").Server
local Rewards = require(Server.Rules.Rewards)
local Economy = require(Server.Rules.Economy)
local Validate = require(Server.Rules.Validate)
local Inventory = require(Server.Config.Inventory)
local Dice = require(Server.Config.Dice)

-- Deep, order-independent text form of a value, for "unchanged" checks.
local function dump(v)
	if type(v) ~= "table" then
		return tostring(v)
	end
	local keys = {}
	for k in v do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in keys do
		table.insert(parts, tostring(k) .. "=" .. dump(v[k]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function newProfile()
	return {
		Gold = 100,
		Gems = 10,
		Xp = 0,
		Materials = { Fragment = 3 },
		Items = { XpTome = 1 },
		Dice = { C01 = { Level = 2, Copies = 4 } },
		Cosmetics = { Owned = {} },
	}
end

local function expectRejected(profile, bundle, wanted, label)
	local before = dump(profile)
	local ok, code = Rewards.Apply(profile, bundle)
	expect(not ok and code == wanted, label .. " -> " .. wanted .. " (got " .. tostring(code) .. ")")
	expectEq(dump(profile), before, label .. " leaves the profile unchanged")
end

test("every kind of reward applies", function()
	local profile = newProfile()
	local ok, code = Rewards.Apply(profile, {
		Gold = 50,
		Gems = 5,
		Xp = 30,
		Materials = { Fragment = 2 },
		Items = { XpTome = 1, GoldPouch = 2 },
		Dice = { C02 = 3 },
		Cosmetics = { ThornDice = true },
	})
	expect(ok and code == nil, "applied")
	expectEq(profile.Gold, 150, "gold")
	expectEq(profile.Gems, 15, "gems")
	expectEq(profile.Xp, 30, "xp")
	expectEq(profile.Materials.Fragment, 5, "material")
	expectEq(profile.Items.XpTome, 2, "owned item")
	expectEq(profile.Items.GoldPouch, 2, "new item")
	expectEq(profile.Dice.C02.Level, 1, "new die level")
	expectEq(profile.Dice.C02.Copies, 2, "new die: first copy unlocks, the rest are copies")
	expectEq(profile.Cosmetics.Owned.ThornDice, true, "cosmetic")
	expect(Rewards.Apply(profile, {}), "an empty bundle is a no-op")
end)

test("costs subtract and a count reaching 0 removes its key", function()
	local profile = newProfile()
	expect(Rewards.Apply(profile, { Gold = -100, Materials = { Fragment = -3 }, Items = { XpTome = -1 } }), "paid")
	expectEq(profile.Gold, 0, "gold to zero stays a number")
	expect(profile.Materials.Fragment == nil, "material at 0 removed")
	expect(profile.Items.XpTome == nil, "item at 0 removed")
	expect(next(profile.Materials) == nil and next(profile.Items) == nil, "no empty entries left")
end)

test("a failing part rejects the whole bundle", function()
	expectRejected(newProfile(), { Gold = 10, Materials = { Fragment = -5 } }, "Insufficient", "material overspend")
	expectRejected(newProfile(), { Gold = 10, Items = { GoldPouch = -1 } }, "Insufficient", "unowned item spent")
	expectRejected(newProfile(), { Gems = -11, Xp = 5 }, "Insufficient", "gems overspend")
	-- Many passing parts around one failing part, whatever order they are visited in.
	local wide = {
		Gold = 1,
		Gems = 1,
		Xp = 1,
		Items = { XpTome = 1 },
		Dice = { C01 = 1, C02 = 1 },
		Cosmetics = { ThornDice = true },
		Materials = { Fragment = -5 },
	}
	expectRejected(newProfile(), wide, "Insufficient", "one failing part among many")
end)

test("malformed bundles are BadBundle and change nothing", function()
	local bad = {
		{ "nil", nil },
		{ "string", "Gold" },
		{ "number", 5 },
		{ "boolean", true },
		{ "unknown top-level key", { Silver = 1 } },
		{ "lower-case key", { gold = 1 } },
		{ "array entry", { 5 } },
		{ "unknown material", { Materials = { Nope = 1 } } },
		{ "item id in Materials", { Materials = { XpTome = 1 } } },
		{ "die id in Items", { Items = { C01 = 1 } } },
		{ "item id in Dice", { Dice = { XpTome = 1 } } },
		{ "unknown cosmetic", { Cosmetics = { Nope = true } } },
		{ "map not a table", { Materials = 5 } },
		{ "string amount", { Gold = "5" } },
		{ "Xp 0", { Xp = 0 } },
		{ "Xp negative", { Xp = -5 } },
		{ "Dice 0", { Dice = { C01 = 0 } } },
		{ "Dice negative", { Dice = { C01 = -1 } } },
		{ "Cosmetics = 1", { Cosmetics = { ThornDice = 1 } } },
		{ "Cosmetics = false", { Cosmetics = { ThornDice = false } } },
	}
	for _, amount in { NAN, INF, -INF, 0.5, -0.5, 1e10, -1e10 } do
		local label = tostring(amount)
		table.insert(bad, { "Gold " .. label, { Gold = amount } })
		table.insert(bad, { "Gems " .. label, { Gems = amount } })
		table.insert(bad, { "Xp " .. label, { Xp = amount } })
		table.insert(bad, { "Materials " .. label, { Materials = { Fragment = amount } } })
		table.insert(bad, { "Items " .. label, { Items = { XpTome = amount } } })
		table.insert(bad, { "Dice " .. label, { Dice = { C01 = amount } } })
	end
	for _, case in bad do
		local profile = newProfile()
		expect(not Rewards.Valid(case[2]), "Valid rejects " .. case[1])
		expectRejected(profile, case[2], "BadBundle", case[1])
	end
	expect(Rewards.Valid({}), "empty bundle is valid")
	expect(Rewards.Valid({ Gold = -Economy.MAX, Gems = Economy.MAX }), "±MAX is valid")
end)

test("a result above MAX is Overflow and changes nothing", function()
	local profile = newProfile()
	profile.Gold = Economy.MAX
	expectRejected(profile, { Gems = 1, Gold = 1 }, "Overflow", "gold above MAX")
	profile = newProfile()
	profile.Materials.Fragment = Economy.MAX
	expectRejected(profile, { Gold = 1, Materials = { Fragment = 1 } }, "Overflow", "material above MAX")
	profile = newProfile()
	profile.Dice.C01.Copies = Economy.MAX
	expectRejected(profile, { Gold = 1, Dice = { C01 = 1 } }, "Overflow", "copies above MAX")
	profile = newProfile()
	profile.Xp = Economy.MAX - 1
	expect(Rewards.Apply(profile, { Xp = 1 }), "exactly MAX is allowed")
	expectEq(profile.Xp, Economy.MAX, "xp at MAX")
end)

test("a corrupt or missing stored value is BadAmount and changes nothing", function()
	local corruptions = {
		function(p)
			p.Gold = NAN
		end,
		function(p)
			p.Gold = nil
		end,
		function(p)
			p.Materials.Fragment = 1.5
		end,
		function(p)
			p.Materials = nil
		end,
		function(p)
			p.Dice.C01 = 7
		end,
		function(p)
			p.Dice.C01.Copies = -1
		end,
		function(p)
			p.Cosmetics = {}
		end,
	}
	for _, mutate in corruptions do
		local profile = newProfile()
		mutate(profile)
		local bundle = { Gold = 1, Materials = { Fragment = 1 }, Dice = { C01 = 1 }, Cosmetics = { ThornDice = true } }
		expectRejected(profile, bundle, "BadAmount", "corrupt profile")
	end
	expectRejected(nil, { Gold = 1 }, "BadBundle", "nil profile")
end)

test("dice: a new die unlocks at level 1, an owned one gains copies", function()
	local profile = newProfile()
	expect(Rewards.Apply(profile, { Dice = { C02 = 1, C01 = 3 } }), "applied")
	expectEq(profile.Dice.C02.Level, 1, "new level")
	expectEq(profile.Dice.C02.Copies, 0, "one copy only unlocks")
	expectEq(profile.Dice.C01.Level, 2, "owned level untouched")
	expectEq(profile.Dice.C01.Copies, 7, "owned copies added")
end)

test("a cosmetic already owned is a no-op, not an error", function()
	local profile = newProfile()
	profile.Cosmetics.Owned.ThornDice = true
	local before = dump(profile)
	local ok, code = Rewards.Apply(profile, { Cosmetics = { ThornDice = true } })
	expect(ok and code == nil, "accepted")
	expectEq(dump(profile), before, "nothing changed")
end)

test("Config/Inventory: ids, sell prices, use bundles and display fields", function()
	local ranks = { Common = true, Uncommon = true, Rare = true, Epic = true, Legendary = true, Mythic = true }
	local sprites = __sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/Bag/BagSprites"]
	local seen, slots, count = {}, {}, 0
	for kind, map in { Materials = Inventory.Materials, Items = Inventory.Items, Cosmetics = Inventory.Cosmetics } do
		expect(table.isfrozen(map), kind .. " frozen")
		for id, entry in map do
			count += 1
			expect(table.isfrozen(entry), id .. " frozen")
			expect(string.match(id, "^[A-Za-z0-9]+$") ~= nil and #id <= 16, id .. " is 1..16 ASCII alphanumerics")
			expect(seen[id] == nil, id .. " unique across the catalogue")
			seen[id] = true
			expect(Dice.Types[id] == nil and string.match(id, "^[A-Z]%d%d$") == nil, id .. " is not a die id")
			expect(type(entry.Name) == "string" and type(entry.Description) == "string", id .. " text")
			expect(ranks[entry.Rarity] == true, id .. " rarity")
			expect(entry.Sell == nil or Validate.IsInt(entry.Sell, 1, Economy.MAX), id .. " Sell is a positive int")
			if entry.Use ~= nil then
				expect(Rewards.Valid(entry.Use), id .. " Use is a valid bundle")
			end
			if entry.Icon ~= nil then
				expect(
					string.find(sprites, "\n\t" .. entry.Icon .. " = ", 1, true) ~= nil,
					id .. " Icon is a BagSprites key"
				)
			end
			if kind == "Cosmetics" then
				expect(string.match(entry.Type, " %(Cosmetic%)$") ~= nil, id .. " Type")
				expect(type(entry.Slot) == "string" and slots[entry.Slot] == nil, id .. " has its own Slot")
				slots[entry.Slot] = true
			end
		end
	end
	expect(count >= 6, "catalogue has entries (" .. count .. ")")
	expectEq(Inventory.Items.GoldPouch.Sell, nil, "Gold Pouch is not sellable")
	expectEq(Inventory.Items.XpTome.Sell, nil, "XP Tome is not sellable: the Shop sells it for Gems")
end)

test("tables with metatables or frozen write targets are refused before any write", function()
	expectRejected(newProfile(), setmetatable({ Gold = 1 }, {}), "BadBundle", "bundle with a metatable")
	local iter = setmetatable({ Xp = 5 }, {
		__iter = function()
			return next, { Xp = 0 }
		end,
	})
	expectRejected(newProfile(), iter, "BadBundle", "bundle with __iter")
	expectRejected(
		newProfile(),
		{ Materials = setmetatable({ Fragment = 1 }, {}) },
		"BadBundle",
		"nested map with a metatable"
	)
	local p1 = newProfile()
	table.freeze(p1.Cosmetics.Owned)
	expectRejected(p1, { Gold = 1, Cosmetics = { ThornDice = true } }, "BadAmount", "frozen Cosmetics.Owned")
	local p2 = newProfile()
	table.freeze(p2.Dice.C01)
	expectRejected(p2, { Gold = 1, Dice = { C01 = 1 } }, "BadAmount", "frozen die entry")
	local p3 = newProfile()
	table.freeze(p3)
	expectRejected(p3, { Gold = 1 }, "BadAmount", "frozen profile")
end)
