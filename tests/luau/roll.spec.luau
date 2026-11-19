-- Roll menu logic (client, display only): odds rows from a Catalog pool, prices and affordability, pity text, featured
-- dice, result tiles and toasts. The server owns every number; nothing here is sample data.

local Roll = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Roll
local RollLogic = require(Roll.RollLogic)
local Catalog = require(game:GetService("ServerScriptService").Server.Rules.Catalog)
local Display = require(game:GetService("ReplicatedStorage").Shared.Display)

local POOL = Catalog.Build().Roll.Pools[1] -- the Standard pool exactly as the server sends it

test("pctText", function()
	for n, want in { [0] = "0%", [0.2] = "0.2%", [4.8] = "4.8%", [31] = "31%", [63.79] = "63.79%", [0.01] = "0.01%" } do
		expectEq(RollLogic.pctText(n), want, tostring(n))
	end
	expectEq(RollLogic.pctText(0.0125), "0.0125%", "4 places by default")
	expectEq(RollLogic.pctText(66.7514991825, 2), "66.75%", "2 places")
end)

test("oddsRows: the Catalog's basis points as true percentages in display order, summing to 100%", function()
	local rows = RollLogic.oddsRows(POOL)
	expectEq(#rows, 6, "six rows: the existing row art")
	local sum = 0
	for i, r in RollLogic.ORDER do
		expectEq(rows[i].Rarity, r, "order " .. i)
		sum += rows[i].Pct
	end
	expectNear(sum, 100, 1e-9, "sum")
	local text = {}
	for _, row in rows do
		text[row.Rarity] = row.Text
	end
	for r, want in
		{ Secret = "0.01%", Mythic = "0.1%", Legendary = "1%", Epic = "14%", Rare = "45%", Common = "39.89%" }
	do
		expectEq(text[r], want, r)
	end
	expectEq(#RollLogic.oddsRows(nil), 0, "no Catalog yet: no rows")
	local partial = RollLogic.oddsRows({ Odds = { { Rarity = "Common", Bp = 10000 } } })
	expect(partial[1].Text == "0%" and partial[6].Text == "100%", "a rarity the pool leaves out shows 0%")
end)

test("prices from the Catalog; canAfford", function()
	expectEq(RollLogic.price(POOL, 1), 100, "one roll")
	expectEq(RollLogic.price(POOL, 10), 900, "ten rolls")
	expectEq(RollLogic.price(POOL, 5), nil, "no such count")
	expectEq(RollLogic.price(nil, 1), nil, "no Catalog")
	expectEq(RollLogic.canAfford(nil, 100), false, "no balance")
	expectEq(RollLogic.canAfford(99, 100), false, "below")
	expectEq(RollLogic.canAfford(100, 100), true, "equal")
	expectEq(RollLogic.canAfford(101, 100), true, "above")
	expectEq(RollLogic.canAfford(500, nil), false, "no price")
end)

test("buttons: enabled only when allowed and affordable", function()
	local b = RollLogic.buttons(POOL, 150, true)
	expect(#b == 2 and b[1].Count == 1 and b[2].Count == 10, "ROLL 1 and ROLL 10")
	expect(b[1].Price == 100 and b[1].Enabled, "ROLL 1 affordable")
	expect(b[2].Price == 900 and not b[2].Enabled, "ROLL 10 not")
	local rich = RollLogic.buttons(POOL, 5000, true)
	expect(rich[1].Enabled and rich[2].Enabled, "both affordable")
	local barred = RollLogic.buttons(POOL, 5000, false)
	expect(not barred[1].Enabled and not barred[2].Enabled, "not allowed: both off")
	local loading = RollLogic.buttons(nil, 5000, true)
	expect(#loading == 2 and not loading[1].Enabled and loading[1].Price == "-", "no Catalog: off, no price")
end)

test("pity: count from Meta.Pity, 'n / Max' text, fraction", function()
	local meta = { Pity = { { Pool = "Other", Count = 5 }, { Pool = "Standard", Count = 32 } } }
	expectEq(RollLogic.pityCount(meta, "Standard"), 32, "Standard")
	expectEq(RollLogic.pityCount(meta, "Event"), 0, "unknown pool")
	expectEq(RollLogic.pityCount(nil, "Standard"), 0, "no Meta")
	expectEq(RollLogic.pityCount({}, "Standard"), 0, "no Pity rows")
	expectEq(RollLogic.pityText(32, 80), "32 / 80", "text")
	expectEq(RollLogic.pityText(0, POOL.Pity.Max), "0 / 80", "Catalog max")
	expectEq(RollLogic.pityFraction(40, 80), 0.5, "half")
	expectEq(RollLogic.pityFraction(200, 80), 1, "clamp high")
	expectEq(RollLogic.pityFraction(-5, 80), 0, "clamp low")
	expectEq(RollLogic.pityFraction(10, 0), 0, "zero max")
end)

test("featured: the Catalog's ids with their rarity and Display name", function()
	local f = RollLogic.featured(POOL)
	expectEq(#f, 2, "two")
	for i, id in POOL.Featured do
		expect(f[i].Id == id and f[i].Rarity == "Legendary" and f[i].Name == Display.Dice[id].Name, id)
	end
	expectEq(#RollLogic.featured(nil), 0, "no Catalog")
end)

test("result tiles: one result in the middle; ten show the three rarest, the best in the middle", function()
	local one = RollLogic.resultTiles({ { Id = "R01", Rarity = "Rare", New = true } })
	expect(one[1] == nil and one[3] == nil and one[2].Id == "R01" and one[2].Name == "Frost", "centred")
	local ten = {}
	for i = 1, 10 do
		ten[i] = { Id = "C01", Rarity = "Common", New = false }
	end
	ten[4] = { Id = "E03", Rarity = "Epic", New = false }
	ten[7] = { Id = "L02", Rarity = "Legendary", New = true }
	ten[9] = { Id = "R02", Rarity = "Rare", New = false }
	local t = RollLogic.resultTiles(ten)
	expect(t[2].Id == "L02" and t[1].Id == "E03" and t[3].Id == "R02", "best three, best centred")
	expectEq(t[2].Name, "Forge", "named")
end)

test("result toasts", function()
	expectEq(RollLogic.resultToast({ { Id = "R01", Rarity = "Rare", New = true } }), "+1 Frost (new)", "new")
	expectEq(RollLogic.resultToast({ { Id = "C01", Rarity = "Common", New = false } }), "+1 Pebble", "owned")
	local ten = {}
	for i = 1, 10 do
		ten[i] = { Id = "C01", Rarity = "Common", New = i <= 2 }
	end
	expectEq(RollLogic.resultToast(ten), "+10 dice (2 new)", "ten, two new")
	for _, r in ten do
		r.New = false
	end
	expectEq(RollLogic.resultToast(ten), "+10 dice", "ten, none new")
end)

test("no client sample data or 'coming soon' path is left in the Roll menu", function()
	expectEq(
		__sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/Roll/SampleData"],
		nil,
		"SampleData deleted"
	)
	for _, name in { "Roll", "RollLogic", "View" } do
		local source = __sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/Roll/" .. name]
		expect(source ~= nil, name .. " scanned")
		expect(not string.find(string.lower(source or ""), "coming soon", 1, true), name .. ": no 'coming soon'")
		expect(not string.find(source or "", "SampleData", 1, true), name .. ": no SampleData")
	end
end)

test("pool: a missing Catalog or a malformed pool reads as no pool, so the menu never indexes nil", function()
	expectEq(RollLogic.pool(nil, "Standard"), nil, "no Catalog")
	expectEq(RollLogic.pool({}, "Standard"), nil, "no Roll section")
	expectEq(RollLogic.pool({ Roll = {} }, "Standard"), nil, "no Pools")
	local partial = table.clone(POOL)
	partial.Odds = nil
	expectEq(RollLogic.pool({ Roll = { Pools = { partial } } }, "Standard"), nil, "pool without Odds")
	expect(RollLogic.pool({ Roll = { Pools = { POOL } } }, "Standard") == POOL, "a whole pool is returned")
	expectEq(
		#RollLogic.oddsRows(RollLogic.pool({ Roll = { Pools = { partial } } }, "Standard")),
		0,
		"no rows, no error"
	)
end)
