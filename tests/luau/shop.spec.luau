-- Shop menu logic: price text, tab sections, sample data sanity, single-flight guard.

local Shop = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Shop
local ShopLogic = require(Shop.ShopLogic)
local SampleData = require(Shop.SampleData)

test("priceText", function()
	for n, want in
		{ [99] = "99", [399] = "399", [1200] = "1,200", [3500] = "3,500", [1000000] = "1,000,000", [0] = "0" }
	do
		expectEq(ShopLogic.priceText(n), want, tostring(n))
	end
	expectEq(ShopLogic.priceText(1234.9), "1,234", "float floors")
	expectEq(ShopLogic.priceText(-5), "0", "never negative")
end)

test("sectionsFor FEATURED", function()
	local s = ShopLogic.sectionsFor("FEATURED", SampleData)
	expectEq(#s, 3, "count")
	local kinds, heads, counts = { "Hero", "Cards", "Cards" }, { "STARTER PACK", "GAMEPASSES", "GEMS" }, { 1, 3, 3 }
	for i = 1, 3 do
		expectEq(s[i].Kind, kinds[i], "kind " .. i)
		expectEq(s[i].Heading, heads[i], "heading " .. i)
		expectEq(#(s[i].Items :: { any }), counts[i], "items " .. i)
	end
end)

test("sectionsFor single tabs, Soon and unknown", function()
	for _, id in { "GAMEPASSES", "GEMS" } do
		local s = ShopLogic.sectionsFor(id, SampleData)
		expectEq(#s, 1, id .. " count")
		expectEq(s[1].Kind, "Cards", id .. " kind")
		expectEq(#(s[1].Items :: { any }), 3, id .. " items")
	end
	local shards = ShopLogic.sectionsFor("SHARDS", SampleData)
	expectEq(#shards, 1, "shards count")
	expectEq(shards[1].Kind, "Soon", "shards kind")
	expectEq(shards[1].Heading, "SHARDS", "shards heading")
	expectEq(ShopLogic.sectionsFor("bogus", SampleData)[1].Kind, "Soon", "bogus kind")
	expectEq(ShopLogic.sectionsFor("bogus", SampleData)[1].Heading, "COMING SOON", "bogus heading")
	for _, tab in ShopLogic.TABS do
		expect(#ShopLogic.sectionsFor(tab.Id, SampleData) > 0, "tab resolves " .. tab.Id)
	end
end)

test("sample data", function()
	local seen = {}
	local function check(item: any)
		expect(not seen[item.Id], "duplicate id " .. item.Id)
		seen[item.Id] = true
		expect(item.Price > 0 and item.Price == math.floor(item.Price), "price " .. item.Id)
	end
	check(SampleData.Starter)
	for _, g in SampleData.Gamepasses do
		check(g)
		expectEq(#string.split(g.Desc, "\n"), 2, "2-line Desc " .. g.Id)
	end
	for i, g in SampleData.Gems do
		check(g)
		if i > 1 then
			expect(g.Price > SampleData.Gems[i - 1].Price, "gems ascending " .. g.Id)
		end
	end
end)

test("guard", function()
	local g = ShopLogic.guard()
	expectEq(g.begin(), true, "first begin")
	expectEq(g.begin(), false, "second begin")
	g.finish()
	expectEq(g.begin(), true, "after finish")
end)

test("sectionsFor with no data (live) is Soon on every tab", function()
	for _, tab in ShopLogic.TABS do
		local s = ShopLogic.sectionsFor(tab.Id, nil)
		expectEq(#s, 1, tab.Id .. " count")
		expectEq(s[1].Kind, "Soon", tab.Id .. " kind")
		expectEq(s[1].Heading, tab.Label, tab.Id .. " heading")
	end
end)
