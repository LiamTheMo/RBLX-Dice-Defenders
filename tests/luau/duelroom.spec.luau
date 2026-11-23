-- Rules/DuelRoom: reading the TeleportData of a reserved Duel server and deciding start / wait / abort.

local Server = game:GetService("ServerScriptService").Server
local Config = require(Server.Config.Matchmaking)
local DuelRoom = require(Server.Rules.DuelRoom)
local RatingConfig = require(Server.Config.Rating)

local function human(id, dr)
	return { UserId = id, DR = dr or 0, RankIndex = 1, Rank = "Bronze", Name = "P" .. id }
end

local function botDescriptor(deck)
	return { Name = "Bot", DR = 120, RankIndex = 1, Deck = deck or { "C01", "C02", "C03", "C04", "C05" }, IsBot = true }
end

local function data(players, bot)
	return { Mode = "Duel", MatchId = "m", Players = players, Bot = bot }
end

test("Parse accepts two humans, or one human and a bot", function()
	local two = DuelRoom.Parse(data({ human(1), human(2, 350) }))
	expect(two ~= nil, "two humans")
	expectEq(two.Players[2].Rank, "Silver", "rank recomputed from DR")
	expectEq(DuelRoom.SeatOf(two, 2), 2, "seat of user 2")
	expectEq(DuelRoom.SeatOf(two, 9), nil, "unexpected user")
	local solo = DuelRoom.Parse(data({ human(1) }, botDescriptor()))
	expect(solo ~= nil and solo.Bot.IsBot == true, "human and a bot")
end)

test("Parse rejects bad data", function()
	local cases = {
		{ "not a table", nil },
		{ "wrong mode", { Mode = "Solo", MatchId = "m", Players = { human(1), human(2) } } },
		{ "no match id", { Mode = "Duel", Players = { human(1), human(2) } } },
		{ "one human without a bot", data({ human(1) }) },
		{ "two humans and a bot", data({ human(1), human(2) }, botDescriptor()) },
		{ "three humans", data({ human(1), human(2), human(3) }) },
		{ "same user twice", data({ human(1), human(1) }) },
		{ "negative DR", data({ human(1), human(2, -5) }) },
		{ "bad user id", data({ human(0), human(2) }) },
		{ "bot with an unknown die", data({ human(1) }, botDescriptor({ "C01", "C02", "C03", "C04", "ZZZ" })) },
		{ "bot with a short deck", data({ human(1) }, botDescriptor({ "C01" })) },
		{ "bot with a duplicate die", data({ human(1) }, botDescriptor({ "C01", "C01", "C03", "C04", "C05" })) },
	}
	for _, case in cases do
		expectEq(DuelRoom.Parse(case[2]), nil, case[1])
	end
end)

test("Decide: start when everyone loaded, wait, abort on timeout or load failure", function()
	local desc = DuelRoom.Parse(data({ human(1), human(2) }))
	local t0 = 500
	expectEq(DuelRoom.Decide(desc, {}, {}, t0, t0), "Wait", "nobody yet")
	expectEq(DuelRoom.Decide(desc, { [1] = true }, {}, t0, t0 + 10), "Wait", "second player still missing")
	expectEq(DuelRoom.Decide(desc, { [1] = true, [2] = true }, {}, t0, t0 + 1), "Start", "both loaded")
	expectEq(
		DuelRoom.Decide(desc, { [1] = true }, {}, t0, t0 + Config.SecondPlayerTimeoutSeconds - 1),
		"Wait",
		"just before the timeout"
	)
	expectEq(
		DuelRoom.Decide(desc, { [1] = true }, {}, t0, t0 + Config.SecondPlayerTimeoutSeconds),
		"Abort",
		"timeout: no DR, back to the lobby"
	)
	expectEq(DuelRoom.Decide(desc, { [1] = true, [2] = true }, {}, t0, t0 + 999), "Start", "all loaded wins even late")
	expectEq(DuelRoom.Decide(desc, { [1] = true }, { [2] = true }, t0, t0 + 1), "Abort", "profile failed to load")
	local solo = DuelRoom.Parse(data({ human(1) }, botDescriptor()))
	expectEq(DuelRoom.Decide(solo, { [1] = true }, {}, t0, t0), "Start", "one human and a bot starts at once")
end)

test("the bot rank limit follows the configured ranks", function()
	local top = #RatingConfig.Ranks
	local ok = botDescriptor()
	ok.RankIndex = top
	expect(DuelRoom.Parse(data({ human(1) }, ok)) ~= nil, "top rank accepted")
	local over = botDescriptor()
	over.RankIndex = top + 1
	expectEq(DuelRoom.Parse(data({ human(1) }, over)), nil, "one above the top rank rejected")
end)
