-- Daily login calendar (docs/_archive/MVP.md, claim id "LOGIN"). Days[n] is paid on the
-- n-th consecutive UTC day; a missed day or the day after Day 7 pays Day 1 again.
-- Rewards are Rules/Rewards bundles *tune*; Chest marks the big day for display.
local function day(n: number, reward, chest: boolean?)
	return table.freeze({ Day = n, Reward = table.freeze(reward), Chest = chest })
end

return table.freeze({
	Days = table.freeze({
		day(1, { Gold = 100, Gems = 10 }),
		day(2, { Gold = 150, Gems = 10, Materials = table.freeze({ Fragment = 10 }) }),
		day(3, { Gold = 200, Gems = 15, Dice = table.freeze({ C01 = 1 }) }),
		day(4, { Gold = 250, Gems = 20, Items = table.freeze({ GoldPouch = 1 }) }),
		day(5, { Gold = 300, Gems = 20, Items = table.freeze({ XpTome = 1 }) }),
		day(6, { Gold = 500, Gems = 30, Dice = table.freeze({ C03 = 1 }) }),
		day(7, { Gold = 1000, Gems = 100, Items = table.freeze({ XpTome = 2 }) }, true),
	}),
})
