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
	expectEq(ids(BagLogic.sort(ITEMS, "Rarity")), "L01,E01,M01,R01,U01,C01", "rarity, equipped (L01, E01) first")
end)

test("sort: Level desc with Name then Id tie-break; input untouched", function()
	local before = ids(ITEMS)
	expectEq(
		ids(BagLogic.sort(ITEMS, "Level")),
		"E01,L01,R01,C01,U01,M01",
		"level (equipped first, then 3s: Chrono, Frost, Pebble)"
	)
	expectEq(ids(ITEMS), before, "no mutation")
	local twins = { { Id = "B", Name = "Same", Level = 1 }, { Id = "A", Name = "Same", Level = 1 } }
	expectEq(ids(BagLogic.sort(twins, "Level")), "A,B", "Id breaks full ties")
end)

test("sort: Name ascending, Equipped first, Quantity desc", function()
	expectEq(ids(BagLogic.sort(ITEMS, "Name")), "L01,E01,M01,U01,R01,C01", "name, equipped first")
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
	expectEq(table.concat(BagLogic.replaceSlot({}, owned, "C06", 1), ","), "C06", "equip into an empty loadout")
	expectEq(table.concat(BagLogic.replaceSlot({ "C01" }, owned, "C06", 2), ","), "C01,C06", "append into a free slot")
end)

test("replaceSlot: rejects duplicate, unowned, bad size, bad slot, nil input", function()
	local deck = { "C01", "C02", "C03", "C04", "C05" }
	local owned = { "C01", "C02", "C03", "C04", "C05", "C06" }
	expect(BagLogic.replaceSlot(deck, owned, "C02", 1) == nil, "duplicate id")
	expect(BagLogic.replaceSlot(deck, owned, "R01", 1) == nil, "not owned")
	expect(BagLogic.replaceSlot({ "C01" }, owned, "C06", 3) == nil, "no gaps")
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
	expect(cosRows[2].TopTag == "RARE" and cosRows[2].Equipped == false, "rarity pill on top, not equipped")
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

test(
	"dice detail: Damage, Attack Speed and Targeting from the Catalog, extra ability stats, default description",
	function()
		local D = "\u{2013}"
		local catalog = {
			Dice = {
				{ Id = "C02", Damage = 9, Rate = 1.75, AttackSpeed = 0.57 },
				{ Id = "R01", Damage = 19, Rate = 1.0, AttackSpeed = 1 },
				{ Id = "R02", Damage = 21, Rate = 0.55, AttackSpeed = 1.82 },
				{
					Id = "R05",
					Damage = 5,
					Rate = 0.8,
					AttackSpeed = 1.25,
					Aura = 6, -- no longer shown
					Stats = {
						{ Label = "Crit Chance", Value = 12.5, Suffix = "%" },
						{ Label = "Poison", Value = "3 / s" },
						{ Value = 1 },
					},
				},
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
		expectEq(values(needle), "9,0.57s,Front", "Damage, Attack Speed (s), Targeting (Front by default)")
		expectEq(needle.Description, "placeholder desc", "owned Common: the default description")
		local frost = detail(catalog, "R01")
		expectEq(values(frost), "19,1s,Front", "1.0 shows as 1")
		expectEq(frost.Description, "placeholder desc", "owned Rare: the default description")
		expectEq(detail(nil, "C02").Stats[1].Value, D, "no Catalog yet: dash")
		meta = { Dice = { { Id = "R05", Level = 1 } }, Deck = {} }
		local rows = detail(catalog, "R05").Stats
		expectEq(
			values(detail(catalog, "R05")),
			"5,1.25s,Front,12.5%,3 / s",
			"extra stats follow in order; Aura is not a row; a row without a label is skipped"
		)
		expectEq(rows[4].Label, "Crit Chance", "label kept")
	end
)

test("cosmetics counter: owned / total from the Catalog", function()
	local cat = {
		Cosmetics = {
			{ Id = "ThornDice", Name = "T", Rarity = "Rare", Type = "x" },
			{ Id = "SproutCap", Name = "S", Rarity = "Rare", Type = "x" },
		},
	}
	expectEq(Tabs[3].Count({ Cosmetics = { { Id = "ThornDice", Quantity = 1 } } }, cat), "1 / 2", "one of two")
	expectEq(Tabs[3].Count({}, nil), nil, "Catalog not loaded")
end)

test("iconFor: the new icon only once uploaded, else the Catalog's own", function()
	expectEq(BagLogic.iconFor("Fragment", nil, nil), nil, "no sprites (headless)")
	expectEq(
		BagLogic.iconFor("Fragment", "IconCrystals", { MatSprout = { Image = "" } }),
		"IconCrystals",
		"not uploaded"
	)
	expectEq(
		BagLogic.iconFor("Fragment", "IconCrystals", { MatSprout = { Image = "rbxassetid://1" } }),
		"MatSprout",
		"uploaded"
	)
	expectEq(BagLogic.iconFor("Nope", "Coins", { MatSprout = { Image = "rbxassetid://1" } }), "Coins", "unmapped id")
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
	expectEq(cosRows[1].Equipped, true, "Equipped from Meta")
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

test("dice: UNEQUIP ALL can clear any equipped loadout and the selected die has the matching action", function()
	local starter = { "C01", "C02", "C03", "C04", "C05" }
	local catalog = { StarterDeck = starter, Dice = {} }
	expect(DiceTab.TopBar({ Deck = starter }).UnequipAll.Enabled, "clear the starter deck")
	expect(DiceTab.TopBar({ Deck = { "C01" } }).UnequipAll.Enabled, "clear a partial deck")
	expect(not DiceTab.TopBar({ Deck = {} }).UnequipAll.Enabled, "empty deck: off")
	local meta = { Dice = { { Id = "C01", Level = 1 } }, Deck = starter }
	for _, it in DiceTab.GetItems(meta, catalog) do
		if it.Id == "C01" then
			local d = DiceTab.Detail(it)
			expect(button(d, "Unequip").Enabled and button(d, "Equip") == nil, "equipped die can be removed")
			local reEquip = DiceTab.Detail(DiceTab.GetItems({ Dice = meta.Dice, Deck = {} }, catalog)[1])
			expect(button(reEquip, "Equip").Enabled, "owned die can be equipped again")
			expect(button(d, "Sell") == nil, "no SELL on dice")
			expect(button(d, "Lock") == nil, "no LOCK on dice")
		end
	end
end)

test("dice upgrade: UPGRADE gates on copies, cap and Catalog; copies show on card and detail", function()
	local DL = {
		Max = 7,
		Copies = { 1, 1, 1, 2, 2, 3 },
		Gold = { 5, 10, 25, 50, 100, 200, 400, 800 },
		Crit = { 1, 2, 2, 3, 3, 3, 4, 4 },
		Offset = { Common = 0, Rare = 2 },
	}
	local catalog = { DieLevel = DL, Dice = {} }
	local function die(level, copies, c, id, gold)
		local meta = { Dice = { { Id = id or "C01", Level = level, Copies = copies } }, Deck = {}, Gold = gold or 1000 }
		for _, it in DiceTab.GetItems(meta, c) do
			if it.Id == (id or "C01") then
				return it, DiceTab.Detail(it)
			end
		end
		error("no die")
	end
	local _, d = die(4, 2, catalog) -- level 4 costs 2
	expect(button(d, "Upgrade").Enabled, "UPGRADE on exactly at the cost")
	expectEq(d.Subline.Copies, "Copies 2 / 2", "detail copies line")
	expectEq(d.Subline.Max, 7, "Max from the Catalog")
	local _, dg = die(4, 2, catalog, nil, 49) -- level 4 costs 50 gold
	expect(not button(dg, "Upgrade").Enabled and button(dg, "Upgrade").Hint == "Need 50 gold", "gold - 1 off")
	expectEq(dg.UpgradeCost.Amount, 50, "gold price on the tag")
	expectEq(dg.Preview, "+3%", "crit the level adds, shown on the toolbar preview")
	expect(not dg.UpgradeCost.Afford, "unaffordable price flagged")
	local _, dr = die(2, 9, catalog, "R01") -- a Rare starts at class 3
	expectEq(dr.UpgradeCost.Amount, 50, "Rare level 2 is class 4: its gold")
	local item, d1 = die(4, 1, catalog)
	expect(not button(d1, "Upgrade").Enabled, "cost - 1 off")
	expectEq(button(d1, "Upgrade").Hint, "Need 2 copies", "cost hint")
	expectEq(d1.Subline.Copies, "Copies 1 / 2", "below-cost copies line")
	expectEq(item.Count, "x1", "card copy count")
	expectEq(select(1, die(1, 0, catalog)).Count, "x0", "a die owned once shows 0")
	local _, dm = die(7, 5, catalog)
	expect(not button(dm, "Upgrade").Enabled and button(dm, "Upgrade").Hint == "Max level", "max level off")
	expectEq(dm.Subline.Copies, "Copies 5", "max level shows copies alone")
	local _, dn = die(4, 9, nil)
	expect(dn.Subline == nil, "no Catalog: no Subline")
	expect(not button(dn, "Upgrade").Enabled and button(dn, "Upgrade").Hint == "Still loading", "no Catalog hint")
	local _, du = die(1, 0, { DieLevel = { Max = "x", Copies = "y" } })
	expect(du.Subline == nil and not button(du, "Upgrade").Enabled, "untrusted Catalog values ignored")
	local bad = {
		5,
		{ Max = 0 / 0, Copies = { 1 } },
		{ Max = math.huge, Copies = { 1 } },
		{ Max = 3, Copies = { -1, 1 } },
		{ Max = 3, Copies = { 1.5, 1 } },
		{ Max = 3, Copies = { 0 / 0, 1 } },
		{ Max = 3 },
		{ Max = 3, Copies = { 1 } },
	}
	for i, dl in bad do
		local _, db = die(1, 9, { DieLevel = dl })
		expect(
			db.Subline == nil and not button(db, "Upgrade").Enabled and button(db, "Upgrade").Hint == "Still loading",
			"malformed DieLevel #" .. i .. " acts as no Catalog"
		)
	end
	expect(#DiceTab.GetItems({ Dice = {}, Deck = {} }, catalog) == 0, "unowned dice are not listed")
	expect(button(d, "Lock") == nil and button(d, "Upgrade").Style == "Yellow", "UPGRADE replaces LOCK")
end)

test("only owned Config dice are listed; removed ids are not", function()
	local catalog = Catalog.Build()
	local function find(meta, id)
		for _, item in DiceTab.GetItems(meta, catalog) do
			if item.Id == id then
				return item
			end
		end
	end
	expect(find({ Dice = {} }, "E03") == nil, "unowned die not listed")
	expect(find({ Dice = { { Id = "E03", Level = 3 } } }, "E03") ~= nil, "owned die listed")
	expect(find({ Dice = {} }, "E05") == nil, "retired Gravity ID never listed")
	local chill = find({ Dice = { { Id = "C06", Level = 1 } } }, "C06")
	expect(
		chill ~= nil and DiceTab.Detail(chill).Description == "Hits slow enemies by 15% for 1.5 seconds.",
		"Chill ability visible"
	)
end)
