-- Config/Shop + Rules/Shop: Buy (exact price once, refusals leave the profile deep-equal), the economy rules, and the
-- Marketplace receipt path (exactly once per PurchaseId, a failed save retries without a second grant, the ring).

local Server = game:GetService("ServerScriptService").Server
local Inventory = require(Server.Config.Inventory)
local ShopConfig = require(Server.Config.Shop)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local Shop = require(Server.Rules.Shop)

local function profile(gold, gems)
	local p = ProfileSchema.Default()
	p.Gold, p.Gems = gold, gems
	return p
end

-- An injected io whose k-th save returns saves[min(k, #saves)]; the log counts changed / save / warn calls.
local function newIo(saves)
	local log = { changed = 0, saves = 0, warns = 0 }
	local io = {
		changed = function()
			log.changed += 1
		end,
		save = function()
			log.saves += 1
			return saves[math.min(log.saves, #saves)] == true
		end,
		warn = function()
			log.warns += 1
		end,
	}
	return io, log
end

local function refused(p, id, code)
	local before = snap(p)
	local ok, got = Shop.Buy(p, id)
	expect(not ok and got == code, ("%s: %s (got %s)"):format(id, code, tostring(got)))
	expectEq(snap(p), before, id .. " " .. code .. " leaves the profile deep-equal")
end

test("Config/Shop: the offers, no real product ids, no Robux offer available yet", function()
	local want = {
		XpTome1 = { "Gold", 300 },
		Frag20 = { "Gold", 100 },
		XpTome3 = { "Gems", 40 },
		Starter = { "Robux", 399 },
		Gems400 = { "Robux", 99 },
		Gems1200 = { "Robux", 249 },
		Gems3500 = { "Robux", 699 },
	}
	expectEq(#ShopConfig.Offers, 7, "offer count")
	for _, o in ShopConfig.Offers do
		expect(want[o.Id] and o.Currency == want[o.Id][1] and o.Price == want[o.Id][2], o.Id .. " currency and price")
		expect(#o.Id >= 1 and #o.Id <= 16 and ShopConfig.ById[o.Id] == o, o.Id .. " id")
		expect(o.ProductId == nil, o.Id .. " has no developer product id until the owner provides one")
	end
	expect(next(ShopConfig.ByProduct) == nil, "no product maps to an offer")
	local starter = ShopConfig.ById.Starter
	expect(starter.Limit == 1 and starter.Grant.Gems == 1200 and starter.Grant.Gold == 2000, "Starter bundle")
	expect(starter.Grant.Dice.R01 == 1, "Starter grants one R01")
	expect(ShopConfig.ById.Gems3500.Grant.Gems == 3500, "gem pack grants its Gems")
end)

test("Shape: a string of 1..16 bytes", function()
	expect(Shop.Shape("a") and Shop.Shape(("x"):rep(16)), "1 and 16 bytes")
	for _, bad in { "", ("x"):rep(17), 5, true, {}, 0 / 0 } do
		expect(not Shop.Shape(bad), "bad " .. tostring(bad))
	end
	expect(not Shop.Shape(nil), "nil")
end)

test("Buy: each currency offer charges the exact price once and grants once", function()
	local p = profile(1000, 100)
	local ok = Shop.Buy(p, "XpTome1")
	expect(ok and p.Gold == 700 and p.Gems == 100 and p.Items.XpTome == 1, "XP Tome: 300 Gold, +1 tome")
	ok = Shop.Buy(p, "Frag20")
	expect(ok and p.Gold == 600 and p.Materials.Fragment == 20, "Fragments: 100 Gold, +20")
	ok = Shop.Buy(p, "XpTome3")
	expect(ok and p.Gold == 600 and p.Gems == 60 and p.Items.XpTome == 4, "3 tomes: 40 Gems")
	expect(next(p.Purchases) == nil, "unlimited offers do not count")
	local exact = profile(300, 0)
	expect(Shop.Buy(exact, "XpTome1") and exact.Gold == 0, "exactly the price is enough")
end)

test("Buy: UnknownOffer, NotAvailable, Insufficient and Overflow leave the profile deep-equal", function()
	refused(profile(1000, 1000), "Nope", "UnknownOffer")
	for _, id in { "Starter", "Gems400", "Gems1200", "Gems3500" } do
		refused(profile(1e9, 1e9), id, "NotAvailable") -- Robux offers never go through Buy
	end
	refused(profile(299, 1000), "XpTome1", "Insufficient")
	refused(profile(0, 39), "XpTome3", "Insufficient")
	local full = profile(1000, 0)
	full.Items.XpTome = 1e9
	refused(full, "XpTome1", "Overflow")
	local corrupt = profile(1000, 0)
	corrupt.Items = nil
	local ok = Shop.Buy(corrupt, "XpTome1")
	expect(not ok and corrupt.Gold == 1000, "a corrupt stored table refuses and does not charge")
end)

test("economy: selling what a Gold offer gives never makes Gold; Gold never buys Gems or Robux", function()
	for _, o in ShopConfig.Offers do
		if o.Currency == "Gold" then
			for kind, map in { Materials = Inventory.Materials, Items = Inventory.Items } do
				for id, n in o.Grant[kind] or {} do
					local sell = map[id].Sell or 0
					expect(
						sell * n < o.Price,
						("%s: selling %d x %s (%d) stays below %d"):format(o.Id, n, id, sell * n, o.Price)
					)
				end
			end
			expect(o.Grant.Gems == nil and o.Grant.Gold == nil, o.Id .. " never turns Gold into Gems or Gold")
		elseif o.Grant.Gold ~= nil then
			expect(o.Id == "Starter", o.Id .. " grants Gold: only the fixed Starter bundle may")
		end
	end
end)

test("receipts: a new PurchaseId grants once; the same id twice grants once", function()
	local starter = ShopConfig.ById.Starter
	local p = profile(0, 0)
	local io, log = newIo({ true })
	expectEq(Shop.Process(p, starter, "r1", io), "PurchaseGranted", "first")
	expect(p.Gems == 1200 and p.Gold == 2000 and p.Dice.R01 ~= nil, "bundle granted")
	expect(p.Purchases.Starter == 1 and p.Receipts[1] == "r1", "counted and recorded")
	expectEq(Shop.Process(p, starter, "r1", io), "PurchaseGranted", "the retry")
	expect(p.Gems == 1200 and p.Gold == 2000 and p.Purchases.Starter == 1 and #p.Receipts == 1, "no second grant")
	expectEq(log.changed, 1, "changed once")
	local packs = profile(0, 0)
	expect(
		Shop.Process(packs, ShopConfig.ById.Gems400, "a", io) == "PurchaseGranted"
			and Shop.Process(packs, ShopConfig.ById.Gems400, "b", io) == "PurchaseGranted"
			and packs.Gems == 800,
		"two distinct purchases of an unlimited pack both pay"
	)
end)

test("receipts: a second paid Starter receipt still grants (the player was charged); each id pays once", function()
	local starter = ShopConfig.ById.Starter
	local p = profile(0, 0)
	local io = newIo({ true })
	Shop.Process(p, starter, "r1", io)
	expectEq(Shop.Process(p, starter, "r2", io), "PurchaseGranted", "second receipt granted")
	expect(p.Gems == 2400 and p.Gold == 4000, "paid for each receipt")
	expectEq(p.Purchases.Starter, 1, "the counter stays within 0..Limit, so the save stays valid")
	expectEq(Shop.Process(p, starter, "r2", io), "PurchaseGranted", "its retry finds the id")
	expect(#p.Receipts == 2 and p.Gems == 2400, "still once per id")
	local ok, code = Shop.Buy(p, "Starter")
	expect(not ok and code == "NotAvailable", "Robux offers never go through Buy")
end)

test("receipts: a failed save is NotProcessedYet and the retry does not grant again", function()
	local pack = ShopConfig.ById.Gems1200
	local p = profile(0, 0)
	local io, log = newIo({ false, true })
	expectEq(Shop.Process(p, pack, "r1", io), "NotProcessedYet", "save failed")
	expect(p.Gems == 1200, "the grant is on the profile, so an autosave cannot lose it")
	expectEq(Shop.Process(p, pack, "r1", io), "PurchaseGranted", "retry saves")
	expect(p.Gems == 1200 and #p.Receipts == 1, "granted exactly once")
	expectEq(log.saves, 2, "saved on each attempt")
	expectEq(log.changed, 1, "changed on the grant only")
end)

test("receipts: bad PurchaseIds, an ungrantable bundle and unknown products are NotProcessedYet", function()
	local pack = ShopConfig.ById.Gems400
	local p = profile(0, 0)
	local io = newIo({ true })
	for _, bad in { "", ("x"):rep(65), 5, true, {} } do
		expectEq(Shop.Process(p, pack, bad, io), "NotProcessedYet", "bad id " .. tostring(bad))
	end
	expect(p.Gems == 0 and #p.Receipts == 0, "nothing granted")
	local full = profile(0, 1e9)
	expectEq(Shop.Process(full, pack, "r1", io), "NotProcessedYet", "Overflow")
	expect(full.Gems == 1e9 and #full.Receipts == 0, "nothing recorded either")
	for _, product in { 1, 123456, "x", 0 / 0 } do
		expectEq(Shop.ProcessProduct(p, product, "r2", io), "NotProcessedYet", "unknown product " .. tostring(product))
	end
	expect(p.Gems == 0 and #p.Receipts == 0, "an unknown product grants nothing")
end)

test("receipts: the ring keeps the newest 100 and never holds a duplicate", function()
	local pack = ShopConfig.ById.Gems400
	local p = profile(0, 0)
	local io = newIo({ true })
	for n = 1, 250 do
		p.Gems = 0 -- keep the counter far from the cap
		Shop.Process(p, pack, "p" .. n, io)
	end
	expectEq(#p.Receipts, ShopConfig.MaxReceipts, "capped")
	expect(p.Receipts[1] == "p151" and p.Receipts[100] == "p250", "the newest 100, in order")
	p.Gems = 0
	Shop.Process(p, pack, "p250", io)
	expect(p.Gems == 0 and #p.Receipts == 100, "a recent id is not paid again")
	local seen = {}
	for _, id in p.Receipts do
		expect(not seen[id], "unique " .. id)
		seen[id] = true
	end
end)
