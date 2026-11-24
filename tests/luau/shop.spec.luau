-- Shop menu logic: price text, sections per tab from a Catalog, button states, press decisions, single-flight guard.

local Shop = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Shop
local ShopLogic = require(Shop.ShopLogic)
local Server = game:GetService("ServerScriptService").Server
local Catalog = require(Server.Rules.Catalog)

-- Gives every Robux offer a developer product (the config has none yet).
local function withProducts(offers)
	for _, o in offers do
		if o.Currency == "Robux" then
			o.ProductId, o.Available = 4242, true
		end
	end
end

local function data(gold, gems, purchases, mutate)
	local catalog = Catalog.Build()
	if mutate then
		mutate(catalog.Shop.Offers)
	end
	return ShopLogic.data(
		catalog,
		{ Gems = gems, Purchases = purchases or { { Id = "Starter", Count = 0 } } },
		{ Gold = gold }
	)
end

local function find(items, id)
	for _, item in items do
		if item.Id == id then
			return item
		end
	end
	return nil
end

test("priceText", function()
	for n, want in
		{ [99] = "99", [399] = "399", [1200] = "1,200", [3500] = "3,500", [1000000] = "1,000,000", [0] = "0" }
	do
		expectEq(ShopLogic.priceText(n), want, tostring(n))
	end
	expectEq(ShopLogic.priceText(1234.9), "1,234", "float floors")
	expectEq(ShopLogic.priceText(-5), "0", "never negative")
end)

test("sections: FEATURED is the Starter hero with its real contents, then the Gold and Gems offers", function()
	local s = ShopLogic.sections(data(1000, 100))
	expectEq(#s, 5, "five sections on one page")
	expect(s[1].Kind == "Hero" and s[1].Heading == "STARTER PACK" and #(s[1].Items :: { any }) == 1, "hero")
	local hero = (s[1].Items :: { any })[1]
	expect(hero.Id == "Starter" and hero.Price == 399 and hero.Currency == "Robux", "hero offer")
	local text = {}
	for _, b in hero.Bullets do
		table.insert(text, b.Icon .. ":" .. b.Text)
	end
	expectEq(table.concat(text, "|"), "Coin:2,000 Gold|Gem:1,200 Gems|Dice3:1 Frost Die", "bullets from the Catalog")
	expect(s[2].Kind == "Cards" and #(s[2].Items :: { any }) == 3, "three offer cards")
	local cards = s[2].Items :: { any }
	expect(cards[1].Id == "XpTome1" and cards[1].Currency == "Gold" and cards[1].Price == 300, "XP Tome costs Gold")
	expect(cards[3].Id == "XpTome3" and cards[3].Currency == "Gems" and cards[3].Price == 40, "3 tomes cost Gems")
end)

test("one page contains gem packs and upcoming features", function()
	local sections = ShopLogic.sections(data(0, 0))
	local gems = sections[3]
	expect(gems.Kind == "Cards" and gems.Heading == "GEMS", "gems section")
	local ids = {}
	for _, item in gems.Items :: { any } do
		table.insert(ids, item.Id .. ":" .. item.Price)
	end
	expectEq(table.concat(ids, ","), "Gems400:99,Gems1200:249,Gems3500:699", "packs and Robux prices")
	for i, id in { "GAMEPASSES", "SHARDS" } do
		expect(sections[i + 3].Kind == "Soon" and sections[i + 3].Heading == id, id .. " is Soon")
	end
end)

test("the page shows a loading state before the Catalog arrives", function()
	expectEq(ShopLogic.data(nil, nil, nil), nil, "no data")
	expectEq(ShopLogic.data({}, nil, nil), nil, "a Catalog without Shop")
	local sections = ShopLogic.sections(nil)
	expect(#sections == 1 and sections[1].Kind == "Loading", "loading state")
end)
test("button state: Robux offers without a product say Not available yet and are off", function()
	for _, item in ShopLogic.sections(data(0, 0))[3].Items :: { any } do
		expect(item.Label == "Not available yet" and item.Enabled == false, item.Id)
	end
	local hero = (ShopLogic.sections(data(0, 0))[1].Items :: { any })[1]
	expect(hero.Label == "Not available yet" and hero.Enabled == false, "Starter")
end)

test("button state: a Robux offer with a product is on; Owned once the limit is reached", function()
	local d = data(0, 0, nil, withProducts)
	local hero = (ShopLogic.sections(d)[1].Items :: { any })[1]
	expect(hero.Label == nil and hero.Enabled == true, "Starter ready")
	local owned = data(0, 0, { { Id = "Starter", Count = 1 } }, withProducts)
	local h2 = (ShopLogic.sections(owned)[1].Items :: { any })[1]
	expect(h2.Label == "Owned" and h2.Enabled == false, "Starter owned")
	local pack = find(ShopLogic.sections(owned)[3].Items :: { any }, "Gems400")
	expect(pack.Label == nil and pack.Enabled == true, "an unlimited pack stays on")
end)

test("button state: a Gold or Gems offer is on only when the balance covers the price", function()
	local function cards(gold, gems)
		return ShopLogic.sections(data(gold, gems))[2].Items :: { any }
	end
	local c = cards(300, 40)
	expect(find(c, "XpTome1").Enabled and find(c, "Frag20").Enabled and find(c, "XpTome3").Enabled, "exact balances")
	c = cards(299, 39)
	expect(not find(c, "XpTome1").Enabled and find(c, "Frag20").Enabled and not find(c, "XpTome3").Enabled, "one short")
	expect(find(c, "XpTome1").Label == nil, "an unaffordable offer still shows its price")
	local unknown = ShopLogic.sections(ShopLogic.data(Catalog.Build(), nil, nil))[2].Items :: { any }
	expect(not find(unknown, "XpTome1").Enabled, "no balance known: off")
end)

test("press: toast, Buy or Prompt", function()
	local d = data(300, 0)
	local function press(id, dd)
		return ShopLogic.press(ShopLogic.offer(dd or d, id), dd or d)
	end
	local action, arg = press("XpTome1")
	expect(action == "Buy" and arg == nil, "an affordable Gold offer buys")
	action, arg = press("XpTome3")
	expect(action == "Toast" and arg == "Not enough Gems", "short of Gems")
	action, arg = press("Starter")
	expect(action == "Toast" and arg == "Not available yet", "no product: never prompts")
	action, arg = press("Nope")
	expectEq(action, "Toast", "unknown offer")
	local live = data(0, 0, { { Id = "Starter", Count = 0 } }, withProducts)
	action, arg = press("Starter", live)
	expect(action == "Prompt" and arg == 4242, "an available Robux offer prompts its product")
	local bought = data(0, 0, { { Id = "Starter", Count = 1 } }, withProducts)
	action, arg = press("Starter", bought)
	expect(action == "Toast" and arg == "Already owned", "owned: no prompt")
end)

test("key changes only with a visible change", function()
	local a = ShopLogic.key(data(300, 40))
	expectEq(ShopLogic.key(data(300, 40)), a, "same inputs")
	expectEq(ShopLogic.key(data(301, 41)), a, "balances that change no state")
	expect(ShopLogic.key(data(0, 40)) ~= a, "Gold crossing a price")
	expectEq(ShopLogic.key(nil), "-", "no data")
end)

test("guard", function()
	local g = ShopLogic.guard()
	expectEq(g.begin(), true, "first begin")
	expectEq(g.begin(), false, "second begin")
	g.finish()
	expectEq(g.begin(), true, "after finish")
end)

test("GAMEPASSES: the VIP card shows its Robux price, then Owned; no offer and not owned keeps Coming soon", function()
	local function gamepasses(meta)
		local d = ShopLogic.data(Catalog.Build(), meta, { Gold = 0 })
		for _, sec in ShopLogic.sections(d) do
			if sec.Heading == "GAMEPASSES" then
				return sec, d
			end
		end
		error("no GAMEPASSES section")
	end
	local soon = gamepasses({ Gems = 0, Purchases = {} })
	expectEq(soon.Kind, "Soon", "no pass configured")
	local sale, d = gamepasses({
		Gems = 0,
		Purchases = {},
		RollDiscountPct = 0,
		VipOffer = { PassId = 7, Robux = 299, Pct = 10 },
	})
	local card = sale.Items[1]
	expect(sale.Kind == "Cards" and card.Id == ShopLogic.VIP_ID and card.Name == "VIP", "a VIP card")
	expect(card.Price == 299 and card.Currency == "Robux" and card.Enabled and card.Label == nil, "299 Robux, buyable")
	expectEq(card.Desc, "10% off every\nroll, forever", "perk text")
	expectEq(d.Vip.Offer.PassId, 7, "the press reads the pass id")
	local owned = gamepasses({ Gems = 0, Purchases = {}, RollDiscountPct = 10 })
	local o = owned.Items[1]
	expect(o.Label == "Owned" and not o.Enabled, "Owned once the discount is held")
	expect(
		ShopLogic.key(ShopLogic.data(Catalog.Build(), { Purchases = {}, RollDiscountPct = 10 }, {}))
			~= ShopLogic.key(ShopLogic.data(Catalog.Build(), { Purchases = {}, RollDiscountPct = 0 }, {})),
		"the key changes when VIP is bought"
	)
end)
