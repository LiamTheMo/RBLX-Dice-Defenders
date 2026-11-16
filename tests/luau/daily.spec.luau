-- Daily Rewards logic on the server's shapes: card states per Streak / NextDay (also driven through the real
-- Claims.View over a 7-day cycle), claim state, timer target, the Catalog reward mapping, texts and coin tiers.

local Controllers = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers
local Server = game:GetService("ServerScriptService").Server
local DailyLogic = require(Controllers.Daily.DailyLogic)
local Sprites = require(Controllers.Sprites)
local Display = require(game:GetService("ReplicatedStorage").Shared.Display)
local Catalog = require(Server.Rules.Catalog)
local Claims = require(Server.Rules.Claims)
local ProfileSchema = require(Server.Rules.ProfileSchema)

local DAY = 86400
local D = 20000 -- a UTC day number
local N = D * DAY + 3600 -- 01:00 on day D

-- "CCTUU..." for days 1..7.
local function states(login)
	local s = ""
	for day = 1, 7 do
		s ..= string.sub(DailyLogic.cardState(day, login), 1, 1)
	end
	return s
end

test("cardState: days 1..Streak claimed, NextDay today, the rest upcoming", function()
	expectEq(states({ Streak = 0, NextDay = 1 }), "TUUUUUU", "first day open")
	expectEq(states({ Streak = 0 }), "UUUUUUU", "nothing claimable")
	expectEq(states({ Streak = 3, NextDay = 4 }), "CCCTUUU", "day 4 open")
	expectEq(states({ Streak = 3 }), "CCCUUUU", "day 3 claimed today")
	expectEq(states({ Streak = 6, NextDay = 7 }), "CCCCCCT", "day 7 open")
	expectEq(states({ Streak = 7 }), "CCCCCCC", "day 7 claimed today")
	expectEq(states({ Streak = 99 }), "CCCCCCC", "streak above range clamps")
	expectEq(states({ Streak = -4, NextDay = 1 }), "TUUUUUU", "negative streak clamps")
	expectEq(states(nil), "UUUUUUU", "no Meta yet")
end)

test("claimState and timerTarget", function()
	expectEq(DailyLogic.claimState(nil), "Soon", "no Meta: loading card")
	expectEq(DailyLogic.claimState({ NextDay = 3 }), "Ready", "a day is open")
	expectEq(DailyLogic.claimState({}), "Claimed", "claimed today")
	expectEq(DailyLogic.timerTarget(nil), nil, "no Meta")
	expectEq(DailyLogic.timerTarget({ NextDay = 1, NextClaimAt = 5 }), nil, "no timer while claimable")
	expectEq(DailyLogic.timerTarget({ NextClaimAt = 12345 }), 12345, "counts to NextClaimAt")
	expectEq(DailyLogic.timerTarget({ NextClaimAt = "x" }), nil, "bad NextClaimAt")
end)

test("a 7-day cycle through the server's Claims.View, then Day 1 again", function()
	local p = ProfileSchema.Default()
	for i = 1, 7 do
		local now = N + (i - 1) * DAY
		local open = Claims.View(p, now).Login
		expectEq(open.ClaimedToday, false, "open " .. i)
		expectEq(states(open), string.rep("C", i - 1) .. "T" .. string.rep("U", 7 - i), "open states " .. i)
		expectEq(DailyLogic.claimState(open), "Ready", "ready " .. i)
		expectEq(DailyLogic.timerTarget(open), nil, "no timer " .. i)
		expectEq(DailyLogic.progressText(open.Streak), (i - 1) .. " / 7 DAYS", "progress before " .. i)
		expect(Claims.Claim(p, "LOGIN", now), "claim " .. i)
		local done = Claims.View(p, now + 60).Login
		expectEq(done.ClaimedToday, true, "claimed " .. i)
		expectEq(states(done), string.rep("C", i) .. string.rep("U", 7 - i), "claimed states " .. i)
		expectEq(DailyLogic.claimState(done), "Claimed", "button " .. i)
		expectEq(DailyLogic.progressText(done.Streak), i .. " / 7 DAYS", "progress after " .. i)
		expectEq(DailyLogic.timerTarget(done), (D + i) * DAY, "timer to the next UTC day " .. i)
	end
	local again = Claims.View(p, N + 7 * DAY).Login
	expectEq(states(again), "TUUUUUU", "after Day 7 comes Day 1")
	expectEq(DailyLogic.progressText(again.Streak), "0 / 7 DAYS", "progress restarts")
	local missed = Claims.View(p, N + 9 * DAY).Login
	expectEq(states(missed), "TUUUUUU", "a missed day restarts at Day 1")
end)

test("days: the Catalog calendar maps onto the view's reward kinds and fits the cards", function()
	local catalogDays = Catalog.Build().Daily.Days
	local days = DailyLogic.days(catalogDays)
	expectEq(#days, 7, "day count")
	local viewKinds = { Coins = true, Gems = true, Potion = true, Die = true, Crystals = true }
	for i, day in days do
		expectEq(day.Day, i, "order " .. i)
		expectEq(day.Chest == true, i == 7, "chest only on day 7 " .. i)
		expectEq(#day.Rewards, #catalogDays[i].Rewards, "nothing dropped " .. i)
		expect(#day.Rewards <= (if i == 7 then 3 else 4), "fits the card's cells " .. i)
		for _, r in day.Rewards do
			expect(viewKinds[r.Kind], "view kind " .. i .. " " .. tostring(r.Kind))
			expect(r.Amount > 0, "amount " .. i)
			if r.Kind == "Die" then
				-- art or the tinted Roll glyph, as the Bag DICE tab
				expect(Sprites.DieArt[r.Id] ~= nil or Display.Dice[r.Id] ~= nil, "die look " .. tostring(r.Id))
			end
		end
	end
	for kind, want in { Gold = "Coins", Gems = "Gems", Item = "Potion", Material = "Crystals", Die = "Die" } do
		expectEq(DailyLogic.KIND[kind], want, "kind " .. kind)
	end
	local mixed = DailyLogic.days({
		{
			Day = 1,
			Rewards = { { Kind = "Cosmetic", Id = "X", Amount = 1 }, { Kind = "Die", Id = "C01", Amount = 1 } },
		},
	})
	expectEq(#mixed[1].Rewards, 1, "unmapped kinds are not drawn")
	expectEq(mixed[1].Rewards[1].Id, "C01", "die keeps its id")
end)

test("progressText", function()
	expectEq(DailyLogic.DAYS, 7, "DAYS")
	expectEq(DailyLogic.progressText(0), "0 / 7 DAYS", "0")
	expectEq(DailyLogic.progressText(7), "7 / 7 DAYS", "7")
	expectEq(DailyLogic.progressText(12), "7 / 7 DAYS", "clamps high")
	expectEq(DailyLogic.progressText(-1), "0 / 7 DAYS", "clamps low")
end)

test("amountText", function()
	expectEq(DailyLogic.amountText({ Kind = "Coins", Amount = 750 }), "+750", "750")
	expectEq(DailyLogic.amountText({ Kind = "Coins", Amount = 1000 }), "+1,000", "1000")
	expectEq(DailyLogic.amountText({ Kind = "Die", Amount = 1 }), "\u{00D7}1", "die")
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
