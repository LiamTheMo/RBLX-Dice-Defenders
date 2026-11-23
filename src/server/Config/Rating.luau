-- Dice Rating (DR) tuning for the 1v1 Duel (docs/DICE_RATING.md section 2). All values are *tuned*
-- except the streak shape (+2 DR per streak step, +100 gold per step, cap 10; 1 DR per step at the top rank).
local function rank(index: number, name: string, min: number)
	return table.freeze({ Index = index, Name = name, Min = min })
end

return table.freeze({
	-- Ascending by Min; DR above the last Min keeps counting (no rank 4).
	Ranks = table.freeze({
		rank(1, "Bronze", 0),
		rank(2, "Silver", 300),
		rank(3, "Gold", 700),
	}),
	WinBase = 30,
	LossBase = -20,
	GapStep = 3, -- per rank of (opponent - mine)
	WinMin = 15, -- the base part of a win, after the gap
	WinMax = 45,
	LossMin = -35, -- a loss after the gap (more negative = costlier)
	LossMax = -5,
	StreakStep = 2, -- DR per streak step beyond the first win
	TopRankStreakStep = 1, -- the same in the top rank
	StreakCap = 10,
	WinGold = 100, -- gold per streak step (n capped at StreakCap)
})
