-- Bag logic: filter, stable sort, count formatting.

local BagLogic = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Bag.BagLogic)

local function ids(list)
	local out = {}
	for i, it in list do
		out[i] = it.Id
	end
	return table.concat(out, ",")
end

local ITEMS = {
	{ Id = "C01", Name = "Pebble", Rarity = "Common", Level = 3 },
	{ Id = "R01", Name = "Frost", Rarity = "Rare", Level = 3 },
	{ Id = "E01", Name = "Emberstorm", Rarity = "Epic", Level = 10, Equipped = true },
	{ Id = "M01", Name = "Astral", Rarity = "Mythic", Level = 1 },
	{ Id = "L01", Name = "Chrono", Rarity = "Legendary", Level = 3, Equipped = true },
	{ Id = "U01", Name = "Fern", Rarity = "Uncommon", Level = 2 },
}

test("filter: empty and blank query keep everything, as a copy", function()
	local out = BagLogic.filter(ITEMS, "")
	expectEq(#out, 6, "empty")
	expectEq(#BagLogic.filter(ITEMS, "   "), 6, "blank")
	expectEq(#BagLogic.filter(ITEMS, nil), 6, "nil")
	expect(out ~= ITEMS, "copy")
end)

test("filter: case-insensitive substring on Name and Rarity", function()
	expectEq(ids(BagLogic.filter(ITEMS, "FI")), "", "fi matches nothing here")
	expectEq(ids(BagLogic.filter(ITEMS, "fr")), "R01", "name")
	expectEq(ids(BagLogic.filter(ITEMS, "EPIC")), "E01", "rarity")
	expectEq(ids(BagLogic.filter(ITEMS, "on")), "C01,L01,U01", "mixed fields, input order kept")
end)

test("filter: no results and pattern characters are literal", function()
	expectEq(#BagLogic.filter(ITEMS, "zzz"), 0, "none")
	expectEq(#BagLogic.filter(ITEMS, "%"), 0, "percent")
	expectEq(#BagLogic.filter(ITEMS, "."), 0, "dot")
	expectEq(#BagLogic.filter({}, "a"), 0, "empty list")
end)

test("sort: Rarity high to low, ties by Name", function()
	expectEq(ids(BagLogic.sort(ITEMS, "Rarity")), "M01,L01,E01,R01,U01,C01", "rarity")
end)

test("sort: Level desc with Name then Id tie-break; input untouched", function()
	local before = ids(ITEMS)
	expectEq(ids(BagLogic.sort(ITEMS, "Level")), "E01,L01,R01,C01,U01,M01", "level (3s: Chrono, Frost, Pebble)")
	expectEq(ids(ITEMS), before, "no mutation")
	local twins = { { Id = "B", Name = "Same", Level = 1 }, { Id = "A", Name = "Same", Level = 1 } }
	expectEq(ids(BagLogic.sort(twins, "Level")), "A,B", "Id breaks full ties")
end)

test("sort: Name ascending, Equipped first, Quantity desc", function()
	expectEq(ids(BagLogic.sort(ITEMS, "Name")), "M01,L01,E01,U01,R01,C01", "name")
	expectEq(ids(BagLogic.sort(ITEMS, "Equipped")):sub(1, 7), "L01,E01", "equipped first, by name")
	local q =
		{ { Id = "a", Name = "A", Quantity = 5 }, { Id = "b", Name = "B", Quantity = 1248 }, { Id = "c", Name = "C" } }
	expectEq(ids(BagLogic.sort(q, "Quantity")), "b,a,c", "quantity")
	expectEq(ids(BagLogic.sort(q, "Nope")), "a,b,c", "unknown key falls back to Name")
end)

test("rarityRank orders the six rarities", function()
	local order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
	for i = 2, 6 do
		expect(BagLogic.rarityRank(order[i]) > BagLogic.rarityRank(order[i - 1]), order[i])
	end
	expectEq(BagLogic.rarityRank("???"), 0, "unknown")
end)

test("formatCount", function()
	expectEq(BagLogic.formatCount(0), "0", "0")
	expectEq(BagLogic.formatCount(999), "999", "999")
	expectEq(BagLogic.formatCount(1000), "1,000", "1000")
	expectEq(BagLogic.formatCount(1248), "1,248", "1248")
	expectEq(BagLogic.formatCount(9999), "9,999", "9999")
	expectEq(BagLogic.formatCount(99999), "99,999", "99999")
	expectEq(BagLogic.formatCount(100000), "100K", "100K")
	expectEq(BagLogic.formatCount(999999), "999K", "999999")
	expectEq(BagLogic.formatCount(1000000), "1M", "1M")
	expectEq(BagLogic.formatCount(1200000), "1.2M", "1.2M")
	expectEq(BagLogic.formatCount(25000000), "25M", "25M")
end)

test("sort: locked items always come last", function()
	local list =
		{ { Id = "L", Name = "A", Rarity = "Mythic", Locked = true }, { Id = "O", Name = "Z", Rarity = "Common" } }
	expectEq(ids(BagLogic.sort(list, "Rarity")), "O,L", "rarity")
	expectEq(ids(BagLogic.sort(list, "Name")), "O,L", "name")
end)

test("replaceSlot: happy path replaces one slot and never mutates the input", function()
	local deck = { "C01", "C02", "C03", "C04", "C05" }
	local owned = { "C01", "C02", "C03", "C04", "C05", "C06" }
	local out = BagLogic.replaceSlot(deck, owned, "C06", 3)
	expectEq(table.concat(out, ","), "C01,C02,C06,C04,C05", "replaced")
	expectEq(table.concat(deck, ","), "C01,C02,C03,C04,C05", "input untouched")
end)

test("replaceSlot: rejects duplicate, unowned, bad size, bad slot, nil input", function()
	local deck = { "C01", "C02", "C03", "C04", "C05" }
	local owned = { "C01", "C02", "C03", "C04", "C05", "C06" }
	expect(BagLogic.replaceSlot(deck, owned, "C02", 1) == nil, "duplicate id")
	expect(BagLogic.replaceSlot(deck, owned, "R01", 1) == nil, "not owned")
	expect(BagLogic.replaceSlot({ "C01", "C02", "C03", "C04" }, owned, "C06", 1) == nil, "4 ids")
	expect(BagLogic.replaceSlot({ "C01", "C02", "C03", "C04", "C05", "C06" }, owned, "C06", 1) == nil, "6 ids")
	expect(BagLogic.replaceSlot(deck, owned, "C06", 0) == nil, "slot 0")
	expect(BagLogic.replaceSlot(deck, owned, "C06", 6) == nil, "slot 6")
	expect(BagLogic.replaceSlot(deck, owned, "C06", 1.5) == nil, "fractional slot")
	expect(BagLogic.replaceSlot(nil, owned, "C06", 1) == nil, "nil deck")
	expect(BagLogic.replaceSlot(deck, nil, "C06", 1) == nil, "nil owned")
	expect(BagLogic.replaceSlot(deck, owned, nil, 1) == nil, "nil id")
	expect(BagLogic.replaceSlot({ "C01", "C02", "C03", "C04", 5 }, owned, "C06", 1) == nil, "non-string deck entry")
end)
