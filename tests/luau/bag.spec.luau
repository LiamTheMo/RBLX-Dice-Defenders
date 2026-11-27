-- Rules/Bag (BagAction): sell, use, lock and unlock Materials and Items; equip and unequip Cosmetics.
-- The client never sends a price or an amount; every rejection leaves the profile deep-equal.

local Server = game:GetService("ServerScriptService").Server
local Bag = require(Server.Rules.Bag)
local Economy = require(Server.Rules.Economy)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local Inventory = require(Server.Config.Inventory)

local function profile()
	local p = ProfileSchema.Default()
	p.Gold = 100
	p.Materials.Fragment = 10
	p.Items.XpTome = 5
	p.Items.GoldPouch = 3
	p.Cosmetics.Owned.ThornDice = true
	p.Cosmetics.Owned.SproutCap = true
	return p
end

-- Expects (false, code) and an untouched profile.
local function rejected(p, code, action, id, qty, label)
	local before = snap(p)
	local ok, got = Bag.Act(p, action, id, qty)
	expect(not ok and got == code, ("%s: %s (got %s)"):format(label, code, tostring(got)))
	expectEq(snap(p), before, label .. ": profile unchanged")
end

test("sell pays Sell x qty from the config and removes qty", function()
	local p = profile()
	expect(Bag.Act(p, "Sell", "Fragment", 4), "sold 4")
	expectEq(p.Gold, 100 + Inventory.Materials.Fragment.Sell * 4, "Gold = Sell x qty")
	expectEq(p.Materials.Fragment, 6, "4 removed")
	rejected(p, "NotSellable", "Sell", "XpTome", 2, "XP Tomes are bought with Gems, so never sold for Gold")
	expect(Bag.Act(p, "Sell", "Fragment", 6), "sold the rest")
	expectEq(p.Materials.Fragment, nil, "an empty stack is removed")
end)

test("sell refusals: Locked, Insufficient, NotOwned, NotSellable, UnknownItem", function()
	local p = profile()
	p.Locked.Fragment = true
	rejected(p, "Locked", "Sell", "Fragment", 1, "locked material")
	p.Locked.Fragment = nil
	rejected(p, "Insufficient", "Sell", "Fragment", 11, "qty > owned")
	p.Materials.Fragment = nil
	rejected(p, "NotOwned", "Sell", "Fragment", 1, "none owned")
	rejected(p, "NotSellable", "Sell", "GoldPouch", 1, "Gold Pouch has no Sell")
	for _, id in { "Nope", "C01", "R01", "ThornDice", "", "LOGIN" } do
		rejected(p, "UnknownItem", "Sell", id, 1, "sell " .. id)
		rejected(p, "UnknownItem", "Use", id, 1, "use " .. id)
		rejected(p, "UnknownItem", "Lock", id, 1, "lock " .. id)
		rejected(p, "UnknownItem", "Unlock", id, 1, "unlock " .. id)
	end
end)

test("use: XP Tome x qty adds Xp, Gold Pouch x qty adds Gold, the used copies go", function()
	local p = profile()
	expect(Bag.Act(p, "Use", "XpTome", 3), "used 3 tomes")
	expectEq(p.Xp, Inventory.Items.XpTome.Use.Xp * 3, "Xp x 3")
	expectEq(p.Items.XpTome, 2, "3 removed")
	expect(Bag.Act(p, "Use", "GoldPouch", 3), "opened every pouch")
	expectEq(p.Gold, 100 + Inventory.Items.GoldPouch.Use.Gold * 3, "Gold x 3")
	expectEq(p.Items.GoldPouch, nil, "an empty stack is removed")
end)

test("use refusals: NotUsable, Locked, Insufficient, NotOwned", function()
	local p = profile()
	rejected(p, "NotUsable", "Use", "Fragment", 1, "Fragment has no Use")
	p.Locked.XpTome = true
	rejected(p, "Locked", "Use", "XpTome", 1, "locked item")
	p.Locked.XpTome = nil
	rejected(p, "Insufficient", "Use", "XpTome", 6, "qty > owned")
	p.Items.XpTome = nil
	rejected(p, "NotOwned", "Use", "XpTome", 1, "none owned")
end)

test("Gold or Xp near MAX refuses with Overflow and changes nothing", function()
	local p = profile()
	p.Gold = Economy.MAX - 1
	rejected(p, "Overflow", "Sell", "Fragment", 1, "sell past MAX")
	rejected(p, "Overflow", "Use", "GoldPouch", 1, "pouch past MAX")
	p.Xp = Economy.MAX - 99
	rejected(p, "Overflow", "Use", "XpTome", 1, "tome past MAX")
	p.Gold = Economy.MAX - 2
	expect(Bag.Act(p, "Sell", "Fragment", 1), "exactly MAX is fine")
	expectEq(p.Gold, Economy.MAX, "at MAX")
end)

test("lock and unlock an owned Material or Item; cosmetics and dice cannot be locked", function()
	local p = profile()
	expect(Bag.Act(p, "Lock", "Fragment", 1), "lock material")
	expect(Bag.Act(p, "Lock", "XpTome", 1), "lock item")
	expectEq(snap(p.Locked), snap({ Fragment = true, XpTome = true }), "flags set")
	expect(Bag.Act(p, "Lock", "Fragment", 1), "locking twice is fine")
	expect(Bag.Act(p, "Unlock", "Fragment", 1), "unlock")
	expectEq(snap(p.Locked), snap({ XpTome = true }), "flag cleared")
	expect(Bag.Act(p, "Sell", "Fragment", 1), "sellable again")
	p.Materials.Fragment = nil
	rejected(p, "NotOwned", "Lock", "Fragment", 1, "lock unowned")
	rejected(p, "UnknownItem", "Lock", "ThornDice", 1, "cosmetic")
	rejected(p, "UnknownItem", "Lock", "C01", 1, "die")
end)

test("equip sets the cosmetic's slot (replacing it); unequip one or all", function()
	local p = profile()
	expect(Bag.Act(p, "Equip", "ThornDice", 1), "equip dice skin")
	expect(Bag.Act(p, "Equip", "SproutCap", 1), "equip hat")
	expectEq(snap(p.Cosmetics.Equipped), snap({ DiceSkin = "ThornDice", Hat = "SproutCap" }), "one per slot")
	expect(Bag.Act(p, "Equip", "ThornDice", 1), "equipping twice is fine")
	expectEq(p.Cosmetics.Equipped.DiceSkin, "ThornDice", "still the one")
	expect(Bag.Act(p, "Unequip", "SproutCap", 1), "unequip one")
	expectEq(snap(p.Cosmetics.Equipped), snap({ DiceSkin = "ThornDice" }), "hat cleared only")
	expect(Bag.Act(p, "Unequip", "SproutCap", 1), "unequipping a non-equipped cosmetic is a no-op")
	expectEq(snap(p.Cosmetics.Equipped), snap({ DiceSkin = "ThornDice" }), "nothing else touched")
	expect(Bag.Act(p, "Equip", "SproutCap", 1), "re-equip hat")
	expect(Bag.Act(p, "Unequip", "", 1), "unequip all")
	expect(next(p.Cosmetics.Equipped) == nil, "every slot clear")
	expectEq(snap(p.Cosmetics.Owned), snap({ ThornDice = true, SproutCap = true }), "still owned")
end)

test("a new cosmetic in a taken slot replaces the equipped one", function()
	local p = profile()
	-- Two cosmetics share a slot only through a future config; simulate it on the stored map.
	p.Cosmetics.Equipped.DiceSkin = "SproutCap"
	expect(Bag.Act(p, "Equip", "ThornDice", 1), "equip into a taken slot")
	expectEq(p.Cosmetics.Equipped.DiceSkin, "ThornDice", "replaced")
end)

test("equip refusals: NotOwned, UnknownItem; cosmetics are never sold or used", function()
	local p = profile()
	rejected(p, "NotOwned", "Equip", "FireflyTrail", 1, "unowned cosmetic")
	for _, id in { "Fragment", "XpTome", "C01", "Nope" } do
		rejected(p, "UnknownItem", "Equip", id, 1, "equip " .. id)
		rejected(p, "UnknownItem", "Unequip", id, 1, "unequip " .. id)
	end
	rejected(p, "UnknownItem", "Sell", "ThornDice", 1, "sell cosmetic")
	rejected(p, "UnknownItem", "Use", "ThornDice", 1, "use cosmetic")
end)

test("Shape: the BagAction validator", function()
	local good = {
		{ "Sell", "Fragment", 1 },
		{ "Sell", "Fragment", 1e6 },
		{ "Use", "XpTome", 2 },
		{ "Lock", "Fragment", 1 },
		{ "Unlock", ("x"):rep(16), 1 },
		{ "Equip", "ThornDice", 1 },
		{ "Unequip", "ThornDice", 1 },
		{ "Unequip", "", 1 },
	}
	for _, a in good do
		expect(Bag.Shape(a[1], a[2], a[3]) == true, "ok " .. a[1] .. " " .. a[2] .. " " .. a[3])
	end
	local bad = {
		{ "Nope", "Fragment", 1 },
		{ "sell", "Fragment", 1 },
		{ 5, "Fragment", 1 },
		{ "Sell", "", 1 },
		{ "Use", "", 1 },
		{ "Lock", "", 1 },
		{ "Equip", "", 1 },
		{ "Sell", ("x"):rep(17), 1 },
		{ "Sell", 5, 1 },
		{ "Sell", "Fragment", 0 },
		{ "Sell", "Fragment", -1 },
		{ "Sell", "Fragment", 1.5 },
		{ "Sell", "Fragment", 0 / 0 },
		{ "Sell", "Fragment", 1e7 },
		{ "Sell", "Fragment", math.huge },
		{ "Sell", "Fragment", "1" },
		{ "Lock", "Fragment", 2 },
		{ "Unlock", "Fragment", 2 },
		{ "Equip", "ThornDice", 2 },
		{ "Unequip", "", 2 },
	}
	for i, a in bad do
		expect(Bag.Shape(a[1], a[2], a[3]) ~= true, "bad case " .. i)
	end
	expectEq(Bag.MAX_QTY, 1e6, "qty cap")
end)
