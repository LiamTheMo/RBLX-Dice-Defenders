-- Daily Rewards logic: card states, texts, claim state, coin tiers, timer, sample data sanity.

local Controllers = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers
local DailyLogic = require(Controllers.Daily.DailyLogic)
local SampleData = require(Controllers.Daily.SampleData)
local Sprites = require(Controllers.Sprites)

test("cardState", function()
	expectEq(DailyLogic.cardState(1, 0, false), "Today", "streak 0 day 1")
	expectEq(DailyLogic.cardState(2, 0, false), "Upcoming", "streak 0 day 2")
	expectEq(DailyLogic.cardState(1, 0, true), "Upcoming", "streak 0 claimed day 1")
	expectEq(DailyLogic.cardState(3, 3, false), "Claimed", "streak 3 day 3")
	expectEq(DailyLogic.cardState(4, 3, false), "Today", "streak 3 day 4")
	expectEq(DailyLogic.cardState(4, 3, true), "Upcoming", "streak 3 claimed day 4")
	expectEq(DailyLogic.cardState(5, 3, false), "Upcoming", "streak 3 day 5")
	expectEq(DailyLogic.cardState(7, 7, false), "Claimed", "streak 7 day 7")
	expectEq(DailyLogic.cardState(7, 99, false), "Claimed", "streak above range clamps")
	expectEq(DailyLogic.cardState(1, -4, false), "Today", "negative streak clamps")
end)

test("progressText", function()
	expectEq(DailyLogic.DAYS, 7, "DAYS")
	expectEq(DailyLogic.progressText(0), "0 / 7 DAYS", "0")
	expectEq(DailyLogic.progressText(3), "3 / 7 DAYS", "3")
	expectEq(DailyLogic.progressText(7), "7 / 7 DAYS", "7")
	expectEq(DailyLogic.progressText(12), "7 / 7 DAYS", "clamps high")
	expectEq(DailyLogic.progressText(-1), "0 / 7 DAYS", "clamps low")
end)

test("amountText", function()
	expectEq(DailyLogic.amountText({ Kind = "Coins", Amount = 750 }), "+750", "750")
	expectEq(DailyLogic.amountText({ Kind = "Coins", Amount = 1000 }), "+1,000", "1000")
	expectEq(DailyLogic.amountText({ Kind = "Coins", Amount = 5000 }), "+5,000", "5000")
	expectEq(DailyLogic.amountText({ Kind = "Die", Amount = 1 }), "\u{00D7}1", "die")
end)

test("claimState", function()
	expectEq(DailyLogic.claimState(nil), "Soon", "live")
	expectEq(DailyLogic.claimState({ Streak = 2, ClaimedToday = false }), "Ready", "ready")
	expectEq(DailyLogic.claimState({ Streak = 2, ClaimedToday = true }), "Claimed", "claimed today")
	expectEq(DailyLogic.claimState({ Streak = 7, ClaimedToday = false }), "Claimed", "streak 7")
	expectEq(DailyLogic.claimState(SampleData), "Ready", "sample")
end)

test("coinTier", function()
	for amount, want in { [0] = 1, [999] = 1, [1000] = 2, [1499] = 2, [1500] = 3, [5000] = 3 } do
		expectEq(DailyLogic.coinTier(amount), want, tostring(amount))
	end
end)

test("timerText", function()
	expectEq(DailyLogic.timerText(12 * 3600 + 34 * 60 + 59), "12h 34m", "12h34m59s")
	expectEq(DailyLogic.timerText(-30), "<1m", "negative")
	expectEq(DailyLogic.timerText(0), "<1m", "zero")
end)

test("sample data sanity", function()
	local kinds = { Coins = true, Gems = true, Potion = true, Die = true, Crystals = true }
	expectEq(#SampleData.Days, 7, "day count")
	for i, day in SampleData.Days do
		expectEq(day.Day, i, "order " .. i)
		expectEq(#day.Rewards, if i == 7 then 3 else 4, "reward count " .. i)
		expectEq(day.Chest ~= nil, i == 7, "chest only on day 7 " .. i)
		for _, r in day.Rewards do
			expectEq(kinds[r.Kind], true, "kind " .. i .. " " .. tostring(r.Kind))
			expectEq(r.Amount > 0, true, "amount " .. i)
			if r.Kind == "Die" then
				expectEq(Sprites.Dice[r.Die] ~= nil, true, "die sprite " .. tostring(r.Die))
			end
		end
	end
	expectEq(SampleData.Days[7].Chest, "ROYAL DICE CHEST", "chest name")
	expectEq(SampleData.Streak, 0, "streak")
	expectEq(SampleData.ClaimedToday, false, "claimed")
	expectEq(DailyLogic.progressText(SampleData.Streak), "0 / 7 DAYS", "mock-up progress")
end)
