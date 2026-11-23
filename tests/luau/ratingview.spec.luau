-- Duel / DR display logic: rank chip, progress, 1v1 button state, Duel HUD line, result card. Missing fields never error.

local RatingLogic = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.RatingLogic)

test("rating: nil and junk give nil; values normalised", function()
	expectEq(RatingLogic.rating(nil), nil, "nil")
	expectEq(RatingLogic.rating("x"), nil, "string")
	local r = RatingLogic.rating({ DR = -5, Rank = "Weird", Streak = 2.9, NextRankAt = 300 })
	expectEq(r.DR, 0, "negative DR clamps")
	expectEq(r.Rank, "Bronze", "unknown rank falls back")
	expectEq(r.Streak, 2, "streak floors")
end)

test("progress: Bronze, Silver, Gold", function()
	local p = RatingLogic.progress({ DR = 150, Rank = "Bronze", NextRankAt = 300 })
	expectEq(p.Frac, 0.5, "half way")
	expectEq(p.Text, "150 / 300 DR", "text")
	p = RatingLogic.progress({ DR = 500, Rank = "Silver", NextRankAt = 700 })
	expectEq(p.Frac, 0.5, "silver is relative to its floor")
	p = RatingLogic.progress({ DR = 950, Rank = "Gold" })
	expectEq(p.Frac, 1, "gold full")
	expectEq(p.Text, "950 DR  MAX RANK", "gold text")
	expectEq(RatingLogic.progress(nil).Text, "", "nil")
end)

test("texts", function()
	expectEq(RatingLogic.deltaText(34), "+34 DR", "gain")
	expectEq(RatingLogic.deltaText(-20), "-20 DR", "loss")
	expectEq(RatingLogic.deltaText(0), "+0 DR", "zero")
	expectEq(RatingLogic.deltaText(nil), "+0 DR", "nil")
	expectEq(RatingLogic.streakText(3), "3 WIN STREAK", "streak")
	expectEq(RatingLogic.streakText(0), "", "none")
	expectEq(RatingLogic.rankName("Silver"), "SILVER", "name")
end)

test("clock: m:ss", function()
	expectEq(RatingLogic.clock(7), "0:07", "seconds")
	expectEq(RatingLogic.clock(65.9), "1:05", "minutes")
	expectEq(RatingLogic.clock(-3), "0:00", "negative")
	expectEq(RatingLogic.clock(nil), "0:00", "nil")
end)

test("queueButton: states, labels and the live timer", function()
	local off = RatingLogic.queueButton(nil, false, false, 0)
	expectEq(off.State, "Disabled", "no snapshot")
	expectEq(off.Label, "FIND MATCH", "label")
	local blocked = RatingLogic.queueButton({ CanQueue = false }, false, false, 0)
	expectEq(blocked.State, "Disabled", "cannot queue")
	expectEq(blocked.Note ~= nil, true, "note")
	expectEq(RatingLogic.queueButton({}, false, false, 0).State, "Disabled", "old snapshot")
	local find = RatingLogic.queueButton({ CanQueue = true }, false, false, 0)
	expectEq(find.State, "Find", "find")
	expectEq(find.On, true, "queues")
	expectEq(RatingLogic.queueButton({ CanQueue = true }, true, false, 0).State, "Disabled", "busy")
	expectEq(RatingLogic.queueButton({ CanQueue = true }, false, true, 0).State, "Disabled", "tutorial")
	local s = RatingLogic.queueButton({ QueueState = "Searching", QueueSince = 100 }, false, false, 107.4)
	expectEq(s.State, "Searching", "searching")
	expectEq(s.Label, "SEARCHING 0:07 - CANCEL", "timer")
	expectEq(s.On, false, "cancels")
	expectEq(
		RatingLogic.queueButton({ QueueState = "Searching", QueueSince = 100 }, false, false, 172).Label,
		"SEARCHING 1:12 - CANCEL",
		"minute rollover"
	)
	expectEq(
		RatingLogic.queueButton({ QueueState = "Searching" }, false, false, 50).Label,
		"SEARCHING 0:00 - CANCEL",
		"no QueueSince"
	)
	local m = RatingLogic.queueButton({ QueueState = "Matched", CanQueue = true }, false, false, 0)
	expectEq(m.State, "Matched", "matched")
	expectEq(m.Label, "MATCH FOUND...", "matched label")
	expectEq(#RatingLogic.QUEUE_WIDEST >= #s.Label, true, "widest label bounds the timer")
end)

test("duelCodeText: wording for the queue codes", function()
	for _, c in { "FinishStarterRolls", "BadDeck", "Unavailable", "WrongPhase", "NotLoaded" } do
		expectEq(type(RatingLogic.duelCodeText(c)), "string", c)
	end
	expectEq(RatingLogic.duelCodeText("Nope"), nil, "unknown falls through")
end)

test("surrender: Duel and CanSurrender only", function()
	expectEq(RatingLogic.surrender(nil).Show, false, "nil")
	expectEq(RatingLogic.surrender({ Mode = "Solo", CanSurrender = true }).Show, false, "solo")
	expectEq(RatingLogic.surrender({ Mode = "Duel" }).Show, false, "no CanSurrender")
	expectEq(RatingLogic.surrender({ Mode = "Duel", CanSurrender = true }).Show, true, "shown")
	expectEq(RatingLogic.surrender({ Mode = "Duel", DuelWaiting = true }).Waiting, true, "waiting")
	expectEq(RatingLogic.surrender({ Mode = "Solo", DuelWaiting = true }).Waiting, false, "waiting only in a Duel")
end)

test("hud: Duel only", function()
	expectEq(RatingLogic.hud(nil).Show, false, "nil")
	expectEq(RatingLogic.hud({ Mode = "Solo", Lives = 3 }).Show, false, "solo")
	expectEq(RatingLogic.hud({ Mode = "Coop" }).Show, false, "coop")
	expectEq(RatingLogic.hud({}).Show, false, "old snapshot")
	local h = RatingLogic.hud({ Mode = "Duel", OpponentLives = 2, Opponent = { Name = "Bob", Rank = "Silver" } })
	expectEq(h.Show, true, "duel")
	expectEq(h.Lives, 2, "lives")
	expectEq(h.Rank, "SILVER", "rank")
	expectEq(string.find(h.Text, "Bob", 1, true) ~= nil, true, "name in text")
	expectEq(RatingLogic.hud({ Mode = "Duel" }).Text ~= "", true, "missing opponent still draws")
	expectEq(h.IsBot, false, "human")
	expectEq(RatingLogic.hud({ Mode = "Duel", Opponent = { Name = "Rex", IsBot = true } }).IsBot, true, "bot tag")
end)

test("result: card model", function()
	expectEq(RatingLogic.result(nil), nil, "nil")
	expectEq(RatingLogic.result({ Phase = "Ended" }), nil, "solo result untouched")
	local r = RatingLogic.result({
		DuelResult = {
			Outcome = "Win",
			DRBefore = 290,
			DRAfter = 324,
			DRDelta = 34,
			StreakBonus = 4,
			Streak = 3,
			RankBefore = "Bronze",
			RankAfter = "Silver",
			Gold = 300,
		},
	})
	expectEq(r.Title, "VICTORY", "title")
	expectEq(r.DeltaText, "+34 DR", "delta")
	expectEq(r.BonusText, "Streak bonus +4 DR", "bonus")
	expectEq(r.RankChanged, true, "rank change")
	expectEq(r.RankUp, true, "rank up")
	expectEq(r.RankChangeText, "RANK UP: BRONZE > SILVER", "change text")
	expectEq(r.GoldText, "+300 Gold", "gold")
	expectEq(r.StreakText, "3 win streak", "streak")
	local l = RatingLogic.result({
		DuelResult = { Outcome = "Loss", DRDelta = -20, RankBefore = "Gold", RankAfter = "Silver" },
	})
	expectEq(l.Title, "DEFEAT", "loss")
	expectEq(l.BonusText, nil, "no bonus")
	expectEq(l.RankUp, false, "rank down")
	expectEq(l.GoldText, nil, "no gold")
	expectEq(
		RatingLogic.result({ DuelResult = { Outcome = "Draw" } }).Title,
		"DEFEAT",
		"no draws: unknown outcome reads as a loss"
	)
	expectEq(RatingLogic.result({ DuelResult = { Outcome = "Loss" } }).RankChanged, false, "no change when absent")
end)

test("result: why lines, early forfeit, bot", function()
	local function r(d)
		return RatingLogic.result({ DuelResult = d })
	end
	expectEq(r({ Outcome = "Win", Why = "Surrender" }).Subtitle, "Opponent surrendered", "opponent surrendered")
	expectEq(r({ Outcome = "Loss", Why = "Surrender" }).Subtitle, "You surrendered", "you surrendered")
	expectEq(r({ Outcome = "Win", Why = "Forfeit" }).Subtitle, "Opponent left the match", "opponent left")
	expectEq(r({ Outcome = "Win", Why = "Lives" }).Subtitle, nil, "lives need no line")
	local e = r({ Outcome = "Loss", Why = "EarlyForfeit", DRDelta = 0 })
	expectEq(e.NoDR, true, "early quit awards no DR")
	expectEq(e.Subtitle ~= nil, true, "early quit line")
	expectEq(r({ Outcome = "Win", Why = "Lives" }).NoDR, false, "normal win")
	local b = r({ Outcome = "Win", VsBot = true, Gold = 150 })
	expectEq(b.BotText, "Practice match vs bot", "bot line")
	expectEq(b.GoldText, "+150 Gold", "gold kept")
	expectEq(r({ Outcome = "Win" }).BotText, nil, "human match")
end)
