-- Rules/ResultCarry: the Duel result payload built by the Duel server and validated by the lobby.

local Server = game:GetService("ServerScriptService").Server
local ResultCarry = require(Server.Rules.ResultCarry)

local function snap()
	return {
		Phase = "Ended",
		Mode = "Duel",
		Result = "Duel",
		Wave = 9,
		WavesCompleted = 8,
		Kills = 120,
		DurationSec = 700,
		RewardGold = 100,
		RewardXp = 80,
		RewardGems = 90,
		XpFrom = 40,
		LevelFrom = 3,
		XpNeedFrom = 500,
		RatingBefore = 250,
		OpponentUserId = 12345,
		Opponent = { Name = "Rival", DR = 260, Rank = "Bronze", IsBot = false },
		DuelResult = {
			Outcome = "Win",
			Why = "Lives",
			DRBefore = 250,
			DRAfter = 278,
			DRDelta = 28,
			StreakBonus = 0,
			Streak = 1,
			RankBefore = "Bronze",
			RankAfter = "Bronze",
			Gold = 100,
		},
		Board = { "junk" }, -- fields outside the payload are dropped
	}
end

test("build keeps the view-model fields and drops the rest", function()
	local p = ResultCarry.Build(snap())
	expect(p ~= nil, "built")
	expectEq(p.Phase, "Ended", "phase")
	expectEq(p.RewardGems, 90, "gems")
	expectEq(p.XpNeedFrom, 500, "xp need")
	expectEq(p.DuelResult.DRDelta, 28, "delta")
	expectEq(p.Board, nil, "no board")
	expectEq(ResultCarry.FromJoinData({ TeleportData = { ResultCarry = p } }).Opponent.Name, "Rival", "join data")
end)

test("only an Ended Duel snapshot builds", function()
	local s = snap()
	s.Mode = "Solo"
	expectEq(ResultCarry.Build(s), nil, "solo")
	s = snap()
	s.Phase = "Playing"
	expectEq(ResultCarry.Build(s), nil, "playing")
	s = snap()
	s.DuelResult = nil
	expectEq(ResultCarry.Build(s), nil, "no result")
end)

test("parse rejects wrong types, sizes and shapes", function()
	local function bad(mutate, why)
		local s = snap()
		mutate(s)
		expectEq(ResultCarry.Parse(s), nil, why)
	end
	bad(function(s)
		s.RewardXp = "80"
	end, "string number")
	bad(function(s)
		s.RewardGems = -1
	end, "negative")
	bad(function(s)
		s.RewardGold = 0.5
	end, "fraction")
	bad(function(s)
		s.Wave = 0 / 0
	end, "nan")
	bad(function(s)
		s.LevelFrom = 0
	end, "level zero")
	bad(function(s)
		s.XpNeedFrom = math.huge
	end, "inf")
	bad(function(s)
		s.Opponent.Name = string.rep("x", 65)
	end, "long name")
	bad(function(s)
		s.Opponent.Name = ""
	end, "empty name")
	bad(function(s)
		s.Opponent = nil
	end, "no opponent")
	bad(function(s)
		s.DuelResult.Outcome = "Won"
	end, "outcome")
	bad(function(s)
		s.DuelResult.Why = string.rep("w", 40)
	end, "long why")
	bad(function(s)
		s.OpponentUserId = -4
	end, "user id")
	bad(function(s)
		s.Phase = "Lobby"
	end, "phase")
	expectEq(ResultCarry.Parse("x"), nil, "not a table")
	expectEq(ResultCarry.FromJoinData(nil), nil, "no join data")
	expectEq(ResultCarry.FromJoinData({ TeleportData = { ResultCarry = 5 } }), nil, "not a payload")
end)

test("parse copies: extra and nested junk never survives", function()
	local s = snap()
	s.Opponent.Evil = { 1 }
	s.DuelResult.Evil = { 1 }
	s.Extra = "x"
	local p = ResultCarry.Parse(s)
	expect(p ~= nil, "valid")
	expectEq(p.Extra, nil, "top")
	expectEq(p.Opponent.Evil, nil, "opponent")
	expectEq(p.DuelResult.Evil, nil, "duel")
end)

test("a max-level player (XpNeedFrom 0) still parses", function()
	local s = snap()
	s.XpNeedFrom = 0
	local p = ResultCarry.Parse(s)
	expect(p ~= nil, "valid")
	expectEq(p.XpNeedFrom, 0, "need")
end)
