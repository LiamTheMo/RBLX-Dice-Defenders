-- Dice Rating (docs/DICE_RATING.md section 2). Pure: no Roblox services. Apply mutates profile.Rating once
-- per duel run id and returns the DuelResult numbers; the caller credits the returned Gold.

local Config = require(script.Parent.Parent.Config.Rating)

local Rating = {}

local MAX_INT = 2 ^ 31 - 1

export type Rank = { Index: number, Name: string }

function Rating.RankOf(dr: number): Rank
	local best = Config.Ranks[1]
	for _, rank in Config.Ranks do
		if dr >= rank.Min then
			best = rank
		end
	end
	return { Index = best.Index, Name = best.Name }
end

-- DR of the next rank, or nil at the top rank.
function Rating.NextRankAt(dr: number): number?
	for _, rank in Config.Ranks do
		if rank.Min > dr then
			return rank.Min
		end
	end
	return nil
end

-- The snapshot sent to clients (docs section 7).
function Rating.View(record)
	local dr = record.DR
	local rank = Rating.RankOf(dr)
	return {
		DR = dr,
		Rank = rank.Name,
		RankIndex = rank.Index,
		NextRankAt = Rating.NextRankAt(dr),
		Streak = record.Streak,
		BestStreak = record.BestStreak,
		Wins = record.Wins,
		Losses = record.Losses,
		Draws = record.Draws,
	}
end

local function bump(n: number): number
	return math.min(MAX_INT, n + 1)
end

-- "Draw" is kept only for old callers: Match/DuelSettle never produce it (docs section 9).
function Rating.Apply(profile, outcome: string, opponentDr: number, runId: number)
	local record = profile.Rating
	if type(record) ~= "table" then
		return false, "NoRating"
	end
	if outcome ~= "Win" and outcome ~= "Loss" and outcome ~= "Draw" then
		return false, "BadOutcome"
	end
	if type(opponentDr) ~= "number" or opponentDr ~= opponentDr or opponentDr < 0 then
		return false, "BadOpponent"
	end
	if type(runId) ~= "number" or runId ~= runId or runId < 1 or runId > MAX_INT or runId % 1 ~= 0 then
		return false, "BadRunId"
	end
	if record.LastDuelRunId == runId then
		return false, "AlreadyApplied"
	end

	local before = record.DR
	local rankBefore = Rating.RankOf(before)
	local gap = Rating.RankOf(opponentDr).Index - rankBefore.Index
	local delta, bonus, gold = 0, 0, 0

	if outcome == "Win" then
		local n = math.min(record.Streak + 1, Config.StreakCap)
		local step = if rankBefore.Index >= #Config.Ranks then Config.TopRankStreakStep else Config.StreakStep
		bonus = step * (n - 1)
		delta = math.clamp(Config.WinBase + Config.GapStep * gap, Config.WinMin, Config.WinMax) + bonus
		gold = Config.WinGold * n
		record.Streak = math.min(record.Streak + 1, MAX_INT)
		record.BestStreak = math.max(record.BestStreak, record.Streak)
		record.Wins = bump(record.Wins)
	elseif outcome == "Loss" then
		delta = math.clamp(Config.LossBase + Config.GapStep * gap, Config.LossMin, Config.LossMax)
		record.Streak = 0
		record.Losses = bump(record.Losses)
	end -- "Draw": no change (the Draws counter is legacy and never incremented)

	local after = math.clamp(before + delta, 0, MAX_INT)
	record.DR = after
	record.LastDuelRunId = runId

	return true,
		{
			Outcome = outcome,
			DRBefore = before,
			DRAfter = after,
			DRDelta = after - before,
			StreakBonus = bonus,
			Streak = record.Streak,
			RankBefore = rankBefore.Name,
			RankAfter = Rating.RankOf(after).Name,
			Gold = gold,
		}
end

return Rating
