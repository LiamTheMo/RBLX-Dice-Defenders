-- Server-only catalogue of Materials, Items and Cosmetics by id. Ids key saved
-- counts, so they are never reused. Display fields match the Bag tabs. *tune* marks
-- placeholder numbers.
--   Sell = Gold paid per unit sold (absent: not sellable)
--   Use  = reward bundle (Rules/Rewards) granted per unit used
--   Icon = BagSprites key (absent: the tab glyph tinted by rarity)
--   Slot = cosmetic equip slot
local Dice = require(script.Parent.Dice)
local Validate = require(script.Parent.Parent.Rules.Validate)

local function entry(fields)
	if fields.Use then
		table.freeze(fields.Use)
	end
	return table.freeze(fields)
end

local Inventory = {}

Inventory.Materials = table.freeze({
	Fragment = entry({
		Name = "Verdant Fragments",
		Rarity = "Common",
		Description = "Green shards left behind by Verdant Trial enemies.",
		Sell = 2, -- *tune*
	}),
})

Inventory.Items = table.freeze({
	XpTome = entry({
		Name = "XP Tome",
		Rarity = "Uncommon",
		Description = "Read it for 100 account XP.",
		Use = { Xp = 100 }, -- *tune*; no Sell: the Shop sells tomes for Gems, so selling them would turn Gems into Gold
	}),
	GoldPouch = entry({
		Name = "Gold Pouch",
		Rarity = "Common",
		Description = "Open it for 200 Gold.",
		Icon = "Coins",
		Use = { Gold = 200 }, -- *tune*; no Sell: it already is Gold
	}),
})

Inventory.Cosmetics = table.freeze({
	ThornDice = entry({
		Name = "Thornbark Dice",
		Rarity = "Rare",
		Type = "Dice Skin (Cosmetic)",
		Slot = "DiceSkin",
		Description = "Bark-brown faces bound in thorny vines.",
	}),
	SproutCap = entry({
		Name = "Sprout Cap",
		Rarity = "Uncommon",
		Type = "Hat (Cosmetic)",
		Slot = "Hat",
		Description = "A little green sprout that bobs as you walk.",
	}),
	FireflyTrail = entry({
		Name = "Firefly Trail",
		Rarity = "Epic",
		Type = "Effect (Cosmetic)",
		Slot = "Effect",
		Description = "A drift of fireflies follows your dice.",
	}),
})

-- Ids share one namespace with each other and with dice (letter + two digits).
local seen = {}
for _, map in { Inventory.Materials, Inventory.Items, Inventory.Cosmetics } do
	for id, item in map do
		assert(string.match(id, "^[A-Za-z0-9]+$") and #id <= 16, "Inventory: bad id " .. id)
		assert(
			not seen[id] and Dice.Types[id] == nil and not string.match(id, "^[A-Z]%d%d$"),
			"Inventory: id taken " .. id
		)
		assert(item.Sell == nil or Validate.IsInt(item.Sell, 1, Validate.MAX_INT), "Inventory: bad Sell on " .. id)
		seen[id] = true
	end
end

return table.freeze(Inventory)
