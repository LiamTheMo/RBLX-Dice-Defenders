-- Bag logic: filter, stable sort, count formatting, Meta + Catalog inventory rows.

local Bag = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Bag
local BagLogic = require(Bag.BagLogic)
local Tabs = { require(Bag.Tabs.Materials), require(Bag.Tabs.Items), require(Bag.Tabs.Cosmetics) }
local DiceTab = require(Bag.Tabs.Dice)
local Catalog = require(game:GetService("ServerScriptService").Server.Rules.Catalog)

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

local CATALOG = {
	Materials = {
		{ Id = "Fragment", Name = "Verdant Fragments", Rarity = "Common", Description = "Shards.", Sell = 2 },
		{ Id = "Ore", Name = "Ore", Rarity = "Rare", Description = "Rock." },
		{ Id = "Unowned", Name = "Unowned", Rarity = "Epic", Description = "Not in Meta." },
	},
	Items = {
		{
			Id = "GoldPouch",
			Name = "Gold Pouch",
			Rarity = "Common",
			Description = "Gold.",
			Icon = "Coins",
			Use = "+200 Gold",
		},
		{ Id = "XpTome", Name = "XP Tome", Rarity = "Uncommon", Description = "XP.", Sell = 50, Use = "+100 XP" },
	},
	Cosmetics = {
		{
			Id = "Firefly",
			Name = "Firefly Trail",
			Rarity = "Epic",
			Type = "Effect (Cosmetic)",
			Slot = "Effect",
			Description = "F.",
		},
		{
			Id = "Sprout",
			Name = "Sprout Cap",
			Rarity = "Uncommon",
			Type = "Hat (Cosmetic)",
			Slot = "Hat",
			Description = "S.",
		},
		{
			Id = "Thorn",
			Name = "Thornbark Dice",
			Rarity = "Rare",
			Type = "Dice Skin (Cosmetic)",
			Slot = "DiceSkin",
			Description = "T.",
		},
	},
}
local META = {
	Materials = { { Id = "Fragment", Quantity = 1248 }, { Id = "Gone", Quantity = 9 }, { Id = "Ore", Quantity = 3 } },
	Items = { { Id = "GoldPouch", Quantity = 2 }, { Id = "XpTome", Quantity = 7 } },
	Cosmetics = { { Id = "Firefly" }, { Id = "Sprout" }, { Id = "Thorn" }, { Id = "Gone" } },
}

test("inventory: owned quantities joined with catalogue display fields", function()
	local m = BagLogic.inventory(META, CATALOG, "Materials")
	expectEq(ids(m), "Fragment,Ore", "Meta order, unowned catalogue entry absent")
	expect(m[1].Name == "Verdant Fragments" and m[1].Rarity == "Common" and m[1].Description == "Shards.", "fields")
	expectEq(m[1].Quantity, 1248, "quantity from Meta")
	expect(m[1].Equipped == nil and m[1].Sell == 2 and m[2].Sell == nil, "no Equipped; the Catalog price, if any")
	expect(m[1].UserLocked == false, "not locked without Meta.Locked")
	local it = BagLogic.inventory(META, CATALOG, "Items")
	expect(it[1].Icon == "Coins" and it[2].Icon == nil, "item icon passed through")
	expectEq(it[2].Quantity, 7, "item quantity")
	local c = BagLogic.inventory(META, CATALOG, "Cosmetics")
	expect(c[3].Type == "Dice Skin (Cosmetic)" and c[3].Name == "Thornbark Dice", "cosmetic type")
	expect(c[1].Equipped == false and c[2].Equipped == false and c[3].Equipped == false, "never equipped yet")
end)

test("inventory: ids missing from the catalogue are skipped", function()
	expectEq(#BagLogic.inventory(META, CATALOG, "Materials"), 2, "materials")
	expectEq(ids(BagLogic.inventory(META, CATALOG, "Cosmetics")), "Firefly,Sprout,Thorn", "cosmetics")
	expectEq(#BagLogic.inventory(META, { Materials = {} }, "Materials"), 0, "empty catalogue section")
end)

test("inventory: missing or empty Meta / Catalog give no rows", function()
	for _, kind in { "Materials", "Items", "Cosmetics" } do
		expectEq(#BagLogic.inventory(nil, CATALOG, kind), 0, "nil meta " .. kind)
		expectEq(#BagLogic.inventory(META, nil, kind), 0, "nil catalog " .. kind)
		expectEq(#BagLogic.inventory({}, {}, kind), 0, "empty " .. kind)
		expectEq(#BagLogic.inventory({ [kind] = {} }, CATALOG, kind), 0, "nothing owned " .. kind)
	end
	for _, tab in Tabs do
		expectEq(#tab.GetItems(nil, nil), 0, tab.Id .. " before Meta and Catalog")
	end
end)

test("tabs: rows sort as the Bag shows them (each tab's default sort)", function()
	local mat, items, cos = Tabs[1], Tabs[2], Tabs[3]
	local rows = BagLogic.sort(mat.GetItems(META, CATALOG), mat.DefaultSort)
	expectEq(ids(rows), "Ore,Fragment", "materials: rarity high to low")
	expectEq(rows[2].Footer, "x1,248", "materials card count")
	expectEq(rows[2].TopTag, "COMMON", "materials rarity pill")
	expectEq(mat.Detail(rows[2]).Stepper.Max, 1248, "detail stepper max")
	expectEq(
		ids(BagLogic.sort(items.GetItems(META, CATALOG), items.DefaultSort)),
		"XpTome,GoldPouch",
		"items: quantity"
	)
	local cosRows = BagLogic.sort(cos.GetItems(META, CATALOG), cos.DefaultSort)
	expectEq(ids(cosRows), "Firefly,Thorn,Sprout", "cosmetics: rarity")
	expect(cosRows[2].Footer == "Dice Skin" and cosRows[2].TopTag == nil, "type footer, no EQUIPPED pill")
end)

test("inventory: every entry the server catalogue sends maps to a full row", function()
	local catalog = Catalog.Build()
	for _, kind in { "Materials", "Items", "Cosmetics" } do
		local meta = { [kind] = {} }
		for _, c in catalog[kind] do
			table.insert(meta[kind], { Id = c.Id, Quantity = 1 })
		end
		local rows = BagLogic.inventory(meta, catalog, kind)
		expectEq(#rows, #catalog[kind], kind .. " count")
		for _, r in rows do
			expect(type(r.Name) == "string" and type(r.Rarity) == "string", kind .. " name/rarity " .. r.Id)
			expect(type(r.Description) == "string", kind .. " description " .. r.Id)
			expect(BagLogic.rarityRank(r.Rarity) > 0, kind .. " known rarity " .. r.Id)
			expect(kind ~= "Cosmetics" or type(r.Type) == "string", "cosmetic type " .. r.Id)
		end
	end
end)

test("dice detail: Damage and Attack Speed from the Catalog, ability note on non-Common dice", function()
	local D = "\u{2013}"
	local catalog = {
		Dice = {
			{ Id = "C02", Damage = 9, Rate = 1.75 },
			{ Id = "R01", Damage = 19, Rate = 1.0 },
			{ Id = "R02", Damage = 21, Rate = 0.55 },
		},
	}
	local meta = { Dice = { { Id = "C02", Level = 1 }, { Id = "R01", Level = 2 } }, Deck = {} }
	local function detail(c, id)
		for _, it in DiceTab.GetItems(meta, c) do
			if it.Id == id then
				return DiceTab.Detail(it)
			end
		end
		error("no die " .. id)
	end
	local function values(d)
		local out = {}
		for i, st in d.Stats do
			out[i] = st.Value
		end
		return table.concat(out, ",")
	end
	local needle = detail(catalog, "C02")
	expectEq(values(needle), `9,{D},1.75,{D}`, "Damage, Range dash, Attack Speed, Burn dash")
	expectEq(needle.Description, "", "owned Common: no ability note")
	local frost = detail(catalog, "R01")
	expectEq(values(frost), `19,{D},1,{D}`, "1.0 shows as 1")
	expectEq(frost.Description, "Ability: coming soon", "owned Rare")
	local arc = detail(catalog, "R02")
	expectEq(values(arc), `21,{D},0.55,{D}`, "unowned playable die shows its stats")
	expectEq(arc.Description, "Not owned. Ability: coming soon", "unowned Rare")
	expectEq(detail(nil, "C02").Stats[1].Value, D, "no Catalog yet: dash")
	local astral = detail(catalog, "M01")
	expectEq(values(astral), `{D},{D},{D},{D}`, "unreleased die: all dashes")
	expectEq(astral.Description, "Not available yet", "unreleased die keeps its note")
end)

local function button(model, id)
	for _, b in model.Buttons do
		if b.Id == id then
			return b
		end
	end
	return nil
end

test("inventory: Meta.Locked marks rows locked; Meta cosmetics carry Equipped", function()
	local meta = {
		Materials = { { Id = "Fragment", Quantity = 5 } },
		Items = { { Id = "XpTome", Quantity = 2 } },
		Cosmetics = { { Id = "Firefly", Equipped = true }, { Id = "Sprout", Equipped = false } },
		Locked = { "Fragment" },
	}
	local m = BagLogic.inventory(meta, CATALOG, "Materials")
	expect(m[1].UserLocked == true and m[1].Sell == 2, "locked material, price")
	local it = BagLogic.inventory(meta, CATALOG, "Items")
	expect(it[1].UserLocked == false and it[1].Use == "+100 XP" and it[1].Sell == 50, "unlocked item, use and price")
	local c = BagLogic.inventory(meta, CATALOG, "Cosmetics")
	expect(c[1].Equipped == true and c[2].Equipped == false, "equipped from Meta")
	local mat, cos = Tabs[1], Tabs[3]
	local rows = mat.GetItems(meta, CATALOG)
	expectEq(rows[1].CornerBadge, "Lock", "locked card shows the padlock")
	expect(rows[1].Locked == nil, "a player lock never uses the unowned (sorted-last) flag")
	local cosRows = cos.GetItems(meta, CATALOG)
	expectEq(cosRows[1].TopTag, "EQUIPPED", "EQUIPPED pill from Meta")
end)

test("stepQty: 1..owned, MAX picks owned, never above the server's 1e6 cap", function()
	local BagRule = require(game:GetService("ServerScriptService").Server.Rules.Bag)
	expectEq(BagLogic.MAX_QTY, BagRule.MAX_QTY, "client cap mirrors the server validator")
	expectEq(BagLogic.stepQty(1, 1, 5), 2, "+1")
	expectEq(BagLogic.stepQty(5, 1, 5), 5, "capped at owned")
	expectEq(BagLogic.stepQty(1, -1, 5), 1, "floor 1")
	expectEq(BagLogic.stepQty(2, "max", 5), 5, "MAX")
	expectEq(BagLogic.stepQty(9, 1, 3), 3, "a smaller stack clamps a stale qty")
	expectEq(BagLogic.stepQty(nil, 0, 4), 1, "nil qty starts at 1")
	expectEq(BagLogic.stepQty(1, "max", 0), 1, "nothing owned: 1")
	expectEq(BagLogic.stepQty(1, "max", 5e6), 1e6, "MAX never above 1e6")
end)

test("materials and items detail: SELL / USE / LOCK states and the Catalog price", function()
	local mat, items = Tabs[1], Tabs[2]
	local frag = { Id = "Fragment", Name = "F", Rarity = "Common", Quantity = 8, Description = "Shards.", Sell = 2 }
	local d = mat.Detail(frag, 3)
	expect(d.Stepper.Qty == 3 and d.Stepper.Enabled, "stepper live at the chosen qty")
	expect(button(d, "Sell").Enabled and button(d, "Sell").Send, "SELL live")
	expect(button(d, "Lock").Enabled and button(d, "Lock").Send, "LOCK live")
	expect(string.find(d.Description, "2 Gold", 1, true) ~= nil, "server price shown: " .. d.Description)
	frag.UserLocked = true
	local dl = mat.Detail(frag)
	expect(dl.Stepper.Qty == 1 and not dl.Stepper.Enabled, "locked: stepper off, qty defaults to 1")
	expect(not button(dl, "Sell").Enabled, "locked: SELL off")
	expect(button(dl, "Unlock").Enabled and button(dl, "Lock") == nil, "locked: UNLOCK instead of LOCK")
	local ore = mat.Detail({ Id = "Ore", Name = "O", Rarity = "Rare", Quantity = 1, Description = "Rock." })
	expect(not button(ore, "Sell").Enabled and button(ore, "Sell").Hint == "Can't be sold", "no price: SELL off")

	local pouch =
		{ Id = "GoldPouch", Name = "G", Rarity = "Common", Quantity = 2, Description = "Gold.", Use = "+200 Gold" }
	local p = items.Detail(pouch, 2)
	expect(button(p, "Use").Enabled and button(p, "Use").Send, "USE live")
	expect(not button(p, "Sell").Enabled, "no Sell: SELL off")
	expect(p.Stepper.Enabled and p.Stepper.Qty == 2, "stepper live")
	pouch.UserLocked = true
	local pl = items.Detail(pouch)
	expect(not button(pl, "Use").Enabled and button(pl, "Use").Hint == "Unlock it first", "locked: USE off")
	expect(button(pl, "Unlock").Enabled, "locked: UNLOCK live")
	local frag2 = items.Detail({ Id = "X", Name = "X", Rarity = "Common", Quantity = 1, Description = "X.", Sell = 5 })
	expect(not button(frag2, "Use").Enabled and button(frag2, "Use").Hint == "Can't be used", "no Use: USE off")
end)

test("cosmetics detail: EQUIP / UNEQUIP live, LOCK off with a reason, no-visual note", function()
	local cos = Tabs[3]
	local item = { Id = "Thorn", Name = "T", Rarity = "Rare", Type = "Dice Skin (Cosmetic)", Description = "T." }
	local d = cos.Detail(item)
	expect(button(d, "Equip").Enabled and button(d, "Equip").Send, "EQUIP live")
	expect(not button(d, "Unequip").Enabled, "UNEQUIP off when not equipped")
	expect(
		not button(d, "Lock").Enabled and not button(d, "Lock").Send and button(d, "Lock").Hint ~= "Coming soon",
		"LOCK off"
	)
	expect(string.find(d.Description, "No visual effect yet", 1, true) ~= nil, "note")
	item.Equipped = true
	local e = cos.Detail(item)
	expect(
		not button(e, "Equip").Enabled and button(e, "Unequip").Enabled and button(e, "Unequip").Send,
		"UNEQUIP live"
	)
end)

test("dice: UNEQUIP ALL resets to the starter deck; LOCK and SELL keep copies", function()
	local starter = { "C01", "C02", "C03", "C04", "C05" }
	local catalog = { StarterDeck = starter, Dice = {} }
	local same = DiceTab.Footer({ Deck = table.clone(starter) }, catalog).Button
	expect(not same.Enabled and same.Hint ~= "Coming soon", "already the starter deck: off")
	local moved = DiceTab.Footer({ Deck = { "C02", "C01", "C03", "C04", "C05" } }, catalog).Button
	expect(moved.Enabled and moved.Deck == starter, "another order: live, sends the starter deck")
	expect(not DiceTab.Footer({ Deck = {} }, nil).Button.Enabled, "no Catalog yet: off")
	expect(BagLogic.sameDeck(starter, table.clone(starter)) and not BagLogic.sameDeck(starter, { "C01" }), "sameDeck")
	expect(not BagLogic.sameDeck(nil, starter), "sameDeck nil")
	local meta = { Dice = { { Id = "C01", Level = 1 } }, Deck = starter }
	for _, it in DiceTab.GetItems(meta, catalog) do
		if it.Id == "C01" then
			local d = DiceTab.Detail(it)
			for _, id in { "Lock", "Sell" } do
				local b = button(d, id)
				expect(not b.Enabled and b.Hint == "Copies are kept for future level-ups", id .. " reason")
			end
		end
	end
end)
