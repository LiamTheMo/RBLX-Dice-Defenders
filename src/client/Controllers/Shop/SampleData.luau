--!strict
-- CLIENT-ONLY SAMPLE DATA: display only. No real catalogue, no real product or gamepass ids; prices are the
-- mock-up's Robux numbers and nothing here is purchasable.

return {
	Starter = {
		Id = "StarterPack",
		Name = "STARTER PACK",
		Price = 399,
		Art = "HeroArt",
		Bullets = {
			{ Icon = "Gem", Text = "1,200 Gems" },
			{ Icon = "Dice3", Text = "10 Rare Dice" },
			{ Icon = "Potion", Text = "5 Luck Potions" },
			{ Icon = "Chest", Text = "1 Treasure Chest" },
		},
	},
	Gamepasses = {
		{
			Id = "AutoRoll",
			Name = "AUTO ROLL",
			Desc = "Automatically reroll\ndice for new ones!",
			Price = 299,
			Art = "AutoRoll",
		},
		{ Id = "Vip", Name = "VIP", Desc = "Exclusive crown,\nchat tag, and perks!", Price = 499, Art = "Crown" },
		{ Id = "LuckBoost", Name = "LUCK BOOST", Desc = "+50% Luck for\ndice rolls!", Price = 349, Art = "Clover" },
	},
	Gems = {
		{ Id = "Gems400", Name = "400 Gems", Price = 99, Art = "Gems3" },
		{ Id = "Gems1200", Name = "1,200 Gems", Price = 249, Art = "GemBag" },
		{ Id = "Gems3500", Name = "3,500 Gems", Price = 699, Art = "ChestOpenGems" },
	},
}
