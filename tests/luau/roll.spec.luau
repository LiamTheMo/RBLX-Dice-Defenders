-- Roll menu logic: percent text, odds rows, pity, affordability, live-safe sample.

local Roll = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Roll
local RollLogic = require(Roll.RollLogic)
local SampleData = require(Roll.SampleData)
local Display = require(game:GetService("ReplicatedStorage").Shared.Display)

test("pctText", function()
	for n, want in { [0] = "0%", [0.2] = "0.2%", [4.8] = "4.8%", [31] = "31%", [63.79] = "63.79%", [0.01] = "0.01%" } do
		expectEq(RollLogic.pctText(n), want, tostring(n))
	end
	expectEq(RollLogic.pctText(0.0125), "0.0125%", "4 places by default")
	expectEq(RollLogic.pctText(66.7514991825, 2), "66.75%", "2 places")
end)

test("oddsRows order, zero-fill and Common = chance of reaching it", function()
	local rows = RollLogic.oddsRows({ Rare = 64, Epic = 31 })
	expectEq(#rows, 6, "count")
	for i, r in RollLogic.ORDER do
		expectEq(rows[i].Rarity, r, "order " .. i)
	end
	expectEq(rows[1].Pct, 0, "Secret zero")
	expectEq(rows[5].Text, "64%", "Rare text")
	expect(math.abs(rows[6].Pct - 0.69 * 0.36 * 100) < 1e-9, "Common reach " .. rows[6].Pct)
	expectEq(rows[6].Text, "24.84%", "Common text")
	expectEq(RollLogic.oddsRows({ Common = 5 })[6].Text, "5%", "explicit Common step")
end)

test("sample odds are the user's chain steps, shown exactly", function()
	local odds = SampleData.full.Odds
	expect(rawequal(odds, SampleData.live.Odds), "one odds table for Studio and live")
	local order = {}
	for _, r in RollLogic.ORDER do
		order[r] = true
	end
	for k in odds do
		expect(order[k] == true, "unknown odds key " .. k)
	end
	local text = {}
	for _, row in RollLogic.oddsRows(odds) do
		text[row.Rarity] = row.Text
	end
	for r, want in
		{ Secret = "0.01%", Mythic = "0.1%", Legendary = "1%", Epic = "10%", Rare = "25%", Common = "66.75%" }
	do
		expectEq(text[r], want, r)
	end
end)

test("sample prices for both buttons", function()
	for _, isStudio in { true, false } do
		local p = SampleData.get(isStudio).Prices
		expect(type(p[1]) == "number" and type(p[10]) == "number", "prices 1 and 10")
	end
end)

test("pityFraction", function()
	expectEq(RollLogic.pityFraction(40, 80), 0.5, "half")
	expectEq(RollLogic.pityFraction(200, 80), 1, "clamp high")
	expectEq(RollLogic.pityFraction(-5, 80), 0, "clamp low")
	expectEq(RollLogic.pityFraction(10, 0), 0, "zero max")
	expectEq(RollLogic.pityFraction(10, -3), 0, "negative max")
end)

test("canAfford", function()
	expectEq(RollLogic.canAfford(nil, 100), false, "nil")
	expectEq(RollLogic.canAfford(99, 100), false, "below")
	expectEq(RollLogic.canAfford(100, 100), true, "equal")
	expectEq(RollLogic.canAfford(101, 100), true, "above")
end)

test("featured ids exist with matching rarity", function()
	for _, f in SampleData.full.Featured do
		local rarity
		for _, d in Display.Locked do
			if d.Id == f.Id then
				rarity = d.Rarity
			end
		end
		expectEq(rarity, f.Rarity, "rarity " .. f.Id)
	end
end)

test("live sample has no rolls or balance", function()
	expectEq(SampleData.get(false).Pity.Count, 0, "pity")
	expectEq(SampleData.get(false).Gems, nil, "gems")
	expectEq(SampleData.get(true).Pity.Count, 32, "studio pity")
	expectEq(SampleData.get(true).Gems, 120, "studio gems")
end)
