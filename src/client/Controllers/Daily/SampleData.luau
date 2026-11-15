--!strict
-- CLIENT-ONLY SAMPLE DATA: display only. The server has no daily-reward feature; the calendar is the mock-up's
-- and nothing here is claimable. Rewards are listed top-left, top-right, bottom-left, bottom-right.

local function coins(n: number)
	return { Kind = "Coins", Amount = n }
end
local function gems(n: number)
	return { Kind = "Gems", Amount = n }
end
local function potion(n: number)
	return { Kind = "Potion", Amount = n }
end
local function die(name: string)
	return { Kind = "Die", Die = name, Amount = 1 }
end

return {
	Days = {
		{ Day = 1, Rewards = { coins(750), potion(2), gems(50), die("Fire") } },
		{ Day = 2, Rewards = { coins(1000), die("Ice"), potion(5), gems(100) } },
		{ Day = 3, Rewards = { gems(50), die("Fire"), coins(1500), potion(8) } },
		{ Day = 4, Rewards = { potion(5), die("Leaf"), coins(750), gems(100) } },
		{ Day = 5, Rewards = { gems(100), coins(1500), die("Fire"), potion(8) } },
		{ Day = 6, Rewards = { coins(1000), die("Lightning"), gems(50), potion(8) } },
		{
			Day = 7,
			Chest = "ROYAL DICE CHEST",
			Rewards = { { Kind = "Crystals", Amount = 500 }, coins(5000), potion(20) },
		},
	},
	Streak = 0,
	ClaimedToday = false,
	NextClaimIn = 12 * 3600 + 34 * 60 + 59, -- seconds; the controller turns it into a deadline on first open
}
