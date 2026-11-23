-- Dice Rating (docs/DICE_RATING.md): rank boundaries, win/loss deltas with the rank gap and clamps, the streak
-- bonus ladder (normal and top rank), floor at 0, draws, idempotence per run id, and the profile migration.

local Server = game:GetService("ServerScriptService").Server
local Rating = require(Server.Rules.Rating)
local ProfileSchema = require(Server.Rules.ProfileSchema)

local function profile(dr: number, streak: number?)
	local s = streak or 0
	return { Rating = { DR = dr, Streak = s, BestStreak = s, Wins = 0, Losses = 0, Draws = 0, LastDuelRunId = 0 } }
end

local runId = 0
local function apply(p, outcome, opponentDr)
	runId += 1
	local ok, result = Rating.Apply(p, outcome, opponentDr, runId)
	expect(ok, "apply ok: " .. tostring(result))
	return result
end

test("rank boundaries", function()
	for dr, expected in { [0] = 1, [299] = 1, [300] = 2, [699] = 2, [700] = 3, [5000] = 3 } do
		expectEq(Rating.RankOf(dr).Index, expected, "rank at " .. dr)
	end
	expectEq(Rating.RankOf(0).Name, "Bronze", "name")
	expectEq(Rating.RankOf(300).Name, "Silver", "name")
	expectEq(Rating.RankOf(700).Name, "Gold", "name")
	expectEq(Rating.NextRankAt(0), 300, "next from bronze")
	expectEq(Rating.NextRankAt(299), 300, "next 299")
	expectEq(Rating.NextRankAt(300), 700, "next from silver")
	expectEq(Rating.NextRankAt(700), nil, "none at gold")
end)

test("View snapshot", function()
	local p = profile(320, 2)
	p.Rating.Wins, p.Rating.Losses, p.Rating.Draws = 5, 4, 1
	local v = Rating.View(p.Rating)
	expectEq(v.DR, 320, "DR")
	expectEq(v.Rank, "Silver", "Rank")
	expectEq(v.RankIndex, 2, "RankIndex")
	expectEq(v.NextRankAt, 700, "NextRankAt")
	expectEq(v.Streak, 2, "Streak")
	expectEq(v.Wins + v.Losses + v.Draws, 10, "counts")
	expectEq(Rating.View(profile(900).Rating).NextRankAt, nil, "gold has none")
end)

test("win and loss deltas follow the rank gap", function()
	-- Silver (300) vs Bronze / Silver / Gold opponents.
	expectEq(apply(profile(300), "Win", 0).DRDelta, 27, "win vs lower rank")
	expectEq(apply(profile(300), "Win", 300).DRDelta, 30, "win vs same rank")
	expectEq(apply(profile(300), "Win", 700).DRDelta, 33, "win vs higher rank")
	expectEq(apply(profile(300), "Loss", 0).DRDelta, -23, "loss vs lower rank")
	expectEq(apply(profile(300), "Loss", 300).DRDelta, -20, "loss vs same rank")
	expectEq(apply(profile(300), "Loss", 700).DRDelta, -17, "loss vs higher rank")
	-- Bronze vs Gold (gap 2) and Gold vs Bronze (gap -2).
	expectEq(apply(profile(10), "Win", 800).DRDelta, 36, "win gap +2")
	expectEq(apply(profile(800), "Loss", 10).DRDelta, -26, "loss gap -2")
end)

test("clamp bounds are configured and bracket the gap range", function()
	local Config = require(Server.Config.Rating)
	-- Ranks give a gap of -2..2, which cannot reach the clamps by default; check the bounds themselves.
	expectEq(Config.WinMin, 15, "win floor")
	expectEq(Config.WinMax, 45, "win ceiling")
	expectEq(Config.LossMin, -35, "loss floor")
	expectEq(Config.LossMax, -5, "loss ceiling")
	expect(Config.WinMin <= Config.WinBase - 2 * Config.GapStep, "win floor below the gap range")
	expect(Config.WinMax >= Config.WinBase + 2 * Config.GapStep, "win ceiling above the gap range")
	expect(Config.LossMin <= Config.LossBase - 2 * Config.GapStep, "loss floor below the gap range")
	expect(Config.LossMax >= Config.LossBase + 2 * Config.GapStep, "loss ceiling above the gap range")
end)

test("streak bonus ladder to the cap, bronze/silver step 2", function()
	local p = profile(0)
	local expectedBonus = { 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 18, 18 }
	for i, bonus in expectedBonus do
		-- Keep the DR in Silver so the rank (and the gap against a Silver opponent) stays fixed.
		p.Rating.DR = 400
		local r = apply(p, "Win", 400)
		expectEq(r.StreakBonus, bonus, "bonus at win " .. i)
		expectEq(r.DRDelta, 30 + bonus, "delta at win " .. i)
		expectEq(r.Gold, 100 * math.min(i, 10), "gold at win " .. i)
	end
	expectEq(p.Rating.Streak, 12, "streak keeps counting")
	expectEq(p.Rating.BestStreak, 12, "best streak")
	expectEq(p.Rating.Wins, 12, "wins")
end)

test("gold rank streak step is 1", function()
	local p = profile(800)
	local expectedBonus = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 9 }
	for i, bonus in expectedBonus do
		p.Rating.DR = 800
		local r = apply(p, "Win", 800)
		expectEq(r.StreakBonus, bonus, "gold bonus at win " .. i)
		expectEq(r.DRDelta, 30 + bonus, "gold delta at win " .. i)
	end
end)

test("loss resets the streak and pays nothing", function()
	local p = profile(400, 5)
	p.Rating.BestStreak = 7
	local r = apply(p, "Loss", 400)
	expectEq(r.Streak, 0, "streak reset")
	expectEq(r.StreakBonus, 0, "no bonus")
	expectEq(r.Gold, 0, "no gold")
	expectEq(p.Rating.BestStreak, 7, "best streak kept")
	expectEq(p.Rating.Losses, 1, "losses")
	expectEq(apply(p, "Win", 400).StreakBonus, 0, "next win starts at 1")
end)

test("DR never drops below 0", function()
	local p = profile(5)
	local r = apply(p, "Loss", 0)
	expectEq(p.Rating.DR, 0, "floored")
	expectEq(r.DRAfter, 0, "DRAfter")
	expectEq(r.DRDelta, -5, "delta is the real change")
	r = apply(p, "Loss", 0)
	expectEq(r.DRDelta, 0, "no change at the floor")
end)

test("rank change is reported", function()
	local r = apply(profile(290), "Win", 0)
	expectEq(r.RankBefore, "Bronze", "before")
	expectEq(r.RankAfter, "Silver", "after")
	expectEq(r.DRAfter, 320, "290 + 30")
	r = apply(profile(300), "Loss", 300)
	expectEq(r.RankAfter, "Bronze", "dropped")
end)

test("a legacy draw changes nothing, not even the Draws counter", function()
	local p = profile(400, 3)
	local r = apply(p, "Draw", 900)
	expectEq(r.DRDelta, 0, "delta")
	expectEq(r.Gold, 0, "gold")
	expectEq(r.Streak, 3, "streak unchanged")
	expectEq(p.Rating.DR, 400, "DR")
	expectEq(p.Rating.Draws, 0, "draws never incremented")
	expectEq(p.Rating.LastDuelRunId, runId, "run id recorded")
end)

test("a run id applies once", function()
	local p = profile(400)
	local ok = Rating.Apply(p, "Win", 400, 77)
	expect(ok, "first")
	local ok2, code = Rating.Apply(p, "Win", 400, 77)
	expectEq(ok2, false, "second refused")
	expectEq(code, "AlreadyApplied", "code")
	expectEq(p.Rating.DR, 430, "no second change")
	expectEq(p.Rating.Wins, 1, "no second win")
end)

test("bad input is refused and changes nothing", function()
	local p = profile(400)
	local cases = {
		{ "Won", 400, 1 },
		{ "Win", -1, 1 },
		{ "Win", 0 / 0, 1 },
		{ "Win", "x", 1 },
		{ "Win", 400, 0 },
		{ "Win", 400, 1.5 },
		{ "Win", 400, 2 ^ 40 },
	}
	for i, case in cases do
		local ok = Rating.Apply(p, case[1], case[2], case[3])
		expectEq(ok, false, "refused case " .. i)
	end
	expectEq(Rating.Apply({}, "Win", 0, 1), false, "no Rating record")
	expectEq(p.Rating.DR, 400, "unchanged")
	expectEq(p.Rating.LastDuelRunId, 0, "run id unchanged")
end)

test("ProfileSchema: default and migration of an old profile", function()
	expectEq(ProfileSchema.Default().Rating.DR, 0, "default")
	local old = { Version = 13, Gold = 70, Rating = { DR = 9999 } }
	local p = ProfileSchema.Migrate(old)
	expect(p ~= nil, "migrates")
	expectEq(p.Version, ProfileSchema.VERSION, "current version")
	expectEq(p.Gold, 70, "other data kept")
	local r = p.Rating
	expect(r.DR == 0 and r.Streak == 0 and r.BestStreak == 0, "stray value dropped, zeros")
	expect(r.Wins == 0 and r.Losses == 0 and r.Draws == 0 and r.LastDuelRunId == 0, "counters zero")
	expectEq(old.Rating.DR, 9999, "stored data not mutated")
	expectEq(ProfileSchema.Migrate(nil).Rating.DR, 0, "new profile")
	expectEq(ProfileSchema.Migrate({ Version = 1, Gold = 5 }).Rating.Wins, 0, "v1 profile gets a record")
end)

test("ProfileSchema: a saved record round-trips and bad data is cleaned", function()
	local good = { DR = 450, Streak = 2, BestStreak = 6, Wins = 10, Losses = 7, Draws = 1, LastDuelRunId = 123 }
	local p = ProfileSchema.Migrate({ Version = ProfileSchema.VERSION, Rating = good })
	for key, value in good do
		expectEq(p.Rating[key], value, "kept " .. key)
	end
	local bad = ProfileSchema.Migrate({
		Version = ProfileSchema.VERSION,
		Rating = {
			DR = -5,
			Streak = 1.5,
			BestStreak = "x",
			Wins = 0 / 0,
			Losses = math.huge,
			Draws = -1,
			LastDuelRunId = 2 ^ 40,
		},
	})
	for key, value in bad.Rating do
		if key == "Recent" then
			expectEq(#value, 0, "reset Recent")
		else
			expectEq(value, 0, "reset " .. key)
		end
	end
	local over = ProfileSchema.Migrate({ Version = ProfileSchema.VERSION, Rating = { Streak = 9, BestStreak = 3 } })
	expectEq(over.Rating.Streak, 3, "streak cannot exceed the best")
	expectEq(ProfileSchema.Migrate({ Version = ProfileSchema.VERSION, Rating = "junk" }).Rating.DR, 0, "non-table")
end)
