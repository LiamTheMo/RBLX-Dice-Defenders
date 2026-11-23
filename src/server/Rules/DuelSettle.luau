-- Applies a finished Duel (docs/DICE_RATING.md sections 2 and 4) to the two seats' profiles. Pure: no Roblox services.
-- Every seat is judged against the opponent's DR from BEFORE the match (`duelDr`, captured at the start), so the order
-- the seats are applied in never matters. A nil profile (a player whose profile is gone) is skipped.

local Balance = require(script.Parent.Parent.Config.Balance)
local Economy = require(script.Parent.Economy)
local Rating = require(script.Parent.Rating)

local DuelSettle = {}

-- A Duel always has a winner (docs/DICE_RATING.md section 9): Win or Loss, never a Draw.
function DuelSettle.OutcomeFor(duel, seat: number): string
	return if duel.Winner == seat then "Win" else "Loss"
end

-- profiles = {[1] = profile?, [2] = profile?}, duelDr = {dr1, dr2}. Returns results = {[1] = DuelResult?, [2] = ...}
-- (Rating.Apply's table plus Why), the Gold already credited to the profile. A seat that was not applied
-- (no profile such as a bot seat, AlreadyApplied, a bad record) has no result. goldFactor (default 1) scales the
-- winner's Gold, floored (bot matches); opponentIsBot marks results with VsBot = true for the caller.
function DuelSettle.Run(
	profiles: { any },
	duelDr: { number },
	duel,
	runId: number,
	wavesCompleted: number?,
	goldFactor: number?,
	opponentIsBot: boolean?
)
	local results = {}
	local factor = if type(goldFactor) == "number"
			and goldFactor == goldFactor
			and goldFactor >= 0
		then goldFactor
		else 1
	-- Win-trading guard: a forfeit or surrender before MinWavesForRewards cleared waves costs the leaver a normal Loss,
	-- but the winner gets no DR, streak or Gold (shown as a Win with a zero delta and Why = "EarlyForfeit").
	local early = (duel.Why == "Forfeit" or duel.Why == "Surrender")
		and (wavesCompleted or 0) < Balance.Duel.MinWavesForRewards
	for seat = 1, 2 do
		local profile = profiles[seat]
		if profile and early and duel.Winner == seat and profile.Rating.LastDuelRunId ~= runId then
			profile.Rating.LastDuelRunId = runId -- once per match, like Rating.Apply
			local dr, rank = profile.Rating.DR, Rating.RankOf(profile.Rating.DR).Name
			results[seat] = {
				Outcome = "Win",
				Why = "EarlyForfeit",
				DRBefore = dr,
				DRAfter = dr,
				DRDelta = 0,
				StreakBonus = 0,
				Streak = profile.Rating.Streak,
				RankBefore = rank,
				RankAfter = rank,
				Gold = 0,
				VsBot = if opponentIsBot then true else nil,
			}
		elseif profile then
			local ok, result = Rating.Apply(profile, DuelSettle.OutcomeFor(duel, seat), duelDr[3 - seat], runId)
			if ok then
				result.Why = if early then "EarlyForfeit" else duel.Why
				result.VsBot = if opponentIsBot then true else nil
				result.Gold = math.floor(result.Gold * factor)
				if result.Gold > 0 then
					local paid = Economy.TryChange(profile, "Gold", result.Gold)
					if not paid then
						result.Gold = 0 -- an overflowing balance forfeits the reward, never the DR
					end
				end
				results[seat] = result
			end
		end
	end
	return results
end

return DuelSettle
