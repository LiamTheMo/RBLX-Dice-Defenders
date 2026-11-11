-- shortcut: client-only sample inventory for MATERIALS / ITEMS / COSMETICS; the server has no such data yet. Delete this module when it does.
-- Display-only: nothing here is game state (the "Equipped" cosmetic is a sample flag, quantities are made up).
-- Icon = nil renders the tab glyph tinted by rarity; a BagSprites key (Flask, Coins) is used where it obviously fits.

local function m(id, name, rarity, qty, desc)
	return { Id = id, Name = name, Rarity = rarity, Quantity = qty, Description = desc }
end

local function i(id, name, rarity, qty, desc, icon)
	return { Id = id, Name = name, Rarity = rarity, Quantity = qty, Description = desc, Icon = icon }
end

local function c(id, name, rarity, kind, desc, equipped)
	return { Id = id, Name = name, Rarity = rarity, Type = kind, Description = desc, Equipped = equipped or false }
end

local SampleData = {}

SampleData.Materials = {
	m("M01", "Prism Shard", "Mythic", 12, "A crystal that hums with every colour at once."),
	m(
		"M02",
		"Ancient Dragonfire Crystalline Gold Ore",
		"Legendary",
		48,
		"Heavy gold ore still warm from an old forge."
	),
	m("M03", "Amethyst", "Epic", 326, "A deep purple crystal prized by enchanters."),
	m(
		"M04",
		"Ember",
		"Epic",
		1248,
		"A condensed shard of pure heat. Used in crafting and upgrading powerful dice and towers."
	),
	m("M05", "Frost Crystal", "Epic", 903, "A shard of everlasting ice."),
	m("M06", "Verdant Leaf", "Rare", 2350, "A leaf that never wilts."),
	m("M07", "Iron Ore", "Rare", 1876, "Raw iron, ready for the smelter."),
	m("M08", "Spring Water", "Rare", 1468, "Clear water from a mountain spring."),
	m("M09", "Oak Wood", "Uncommon", 5672, "Sturdy timber."),
	m("M10", "Silver Ingot", "Uncommon", 3904, "A smooth bar of refined silver."),
	m("M11", "Stone", "Common", 9999, "Plain, reliable stone."),
	m("M12", "Mushroom", "Common", 7410, "A red-capped forest mushroom."),
}

SampleData.Items = {
	i(
		"I01",
		"Power Potion",
		"Legendary",
		247,
		"Temporarily increases all tower damage by +50% for 10 minutes.",
		"Flask"
	),
	i("I02", "Health Potion", "Uncommon", 132, "Restores a chunk of your base health.", "Flask"),
	i("I03", "Swift Potion", "Rare", 98, "Speeds up tower attacks for a short time.", "Flask"),
	i("I04", "Luck Potion", "Uncommon", 76, "Improves your odds on the next summons.", "Flask"),
	i("I05", "Golden Chest", "Epic", 42, "Opens for a stack of rewards."),
	i("I06", "Silver Chest", "Rare", 21, "Opens for a few rewards."),
	i("I07", "Golden Key", "Uncommon", 119, "Opens a Golden Chest."),
	i("I08", "Royal Key", "Legendary", 37, "Opens a Royal Vault."),
	i("I09", "XP Ticket x2", "Epic", 64, "Doubles XP gained for one run."),
	i("I10", "Coin Boost", "Uncommon", 58, "Doubles coins gained for one run.", "Coins"),
	i("I11", "Dice Ticket x2", "Epic", 53, "Doubles dice drops for one run."),
	i("I12", "Quest Scroll", "Common", 18, "Refreshes one daily quest."),
	i("I13", "Dice Scroll", "Common", 14, "Grants a random common die."),
	i("I14", "Upgrade Scroll", "Common", 11, "Adds a bonus to a die upgrade."),
	i("I15", "Tower Ticket x2", "Mythic", 9, "Doubles tower rewards for one run."),
}

SampleData.Cosmetics = {
	c(
		"C01",
		"Royal Dice",
		"Legendary",
		"Dice Skin (Cosmetic)",
		"A majestic dice skin fit for a king of the Dice Kingdom.",
		true
	),
	c("C02", "Royal Crown", "Legendary", "Hat (Cosmetic)", "A golden crown set with purple gems."),
	c("C03", "Royal Cape", "Legendary", "Back (Cosmetic)", "A flowing purple cape with a golden clasp."),
	c("C04", "Galaxy Dice", "Epic", "Dice Skin (Cosmetic)", "A tiny galaxy swirls inside every face."),
	c("C05", "Frost Dice", "Epic", "Dice Skin (Cosmetic)", "Frozen faces dusted with snow."),
	c("C06", "Lava Dice", "Epic", "Dice Skin (Cosmetic)", "Molten cracks glow across the surface."),
	c("C07", "Divine Aura", "Epic", "Effect (Cosmetic)", "Golden wings and a soft halo."),
	c("C08", "Tech Dice", "Rare", "Dice Skin (Cosmetic)", "Cyan circuitry on every face."),
	c("C09", "Nature Dice", "Rare", "Dice Skin (Cosmetic)", "Mossy faces with tiny flowers."),
	c("C10", "Prism Dice", "Rare", "Dice Skin (Cosmetic)", "Light splits into rainbows."),
	c("C11", "Rift Effect", "Rare", "Effect (Cosmetic)", "A swirling purple rift trails your dice."),
	c("C12", "Dice Trail", "Uncommon", "Effect (Cosmetic)", "Little golden dice follow your cursor."),
}

return SampleData
