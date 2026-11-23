--!strict
-- 1v1 Duel / DR display logic: pure, no Instances (unit-tested headless). Every snapshot field here is new and may be nil
-- on an old snapshot; each function degrades to "no Duel UI" instead of erroring. The server owns every number (ranks,
-- DR, deltas): this only formats what the snapshot says. Contract: docs/DICE_RATING.md section 7.

local RatingLogic = {}

-- Three ranks only. Colours are RGB triples (the views build Color3s) so this stays headless.
RatingLogic.RANKS = table.freeze({
	table.freeze({ Name = "Bronze", Color = table.freeze({ 205, 127, 50 }), Floor = 0 }),
	table.freeze({ Name = "Silver", Color = table.freeze({ 205, 212, 224 }), Floor = 300 }),
	table.freeze({ Name = "Gold", Color = table.freeze({ 255, 205, 60 }), Floor = 700 }),
})
local FALLBACK = RatingLogic.RANKS[1]

local function whole(n: any): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.floor(n)
end

local function rankRow(rank: any)
	for _, r in RatingLogic.RANKS do
		if r.Name == rank then
			return r
		end
	end
	return FALLBACK
end

function RatingLogic.rankName(rank: any): string
	return string.upper(rankRow(rank).Name)
end

function RatingLogic.rankColor(rank: any): { number }
	return rankRow(rank).Color
end

-- Normalised Rating snapshot, or nil when the server sent none (old snapshot).
function RatingLogic.rating(r: any)
	if type(r) ~= "table" then
		return nil
	end
	local next = if type(r.NextRankAt) == "number" and r.NextRankAt == r.NextRankAt
		then math.floor(r.NextRankAt)
		else nil
	return {
		DR = math.max(0, whole(r.DR)),
		Rank = rankRow(r.Rank).Name,
		NextRankAt = next,
		Streak = math.max(0, whole(r.Streak)),
		BestStreak = math.max(0, whole(r.BestStreak)),
		Wins = math.max(0, whole(r.Wins)),
		Losses = math.max(0, whole(r.Losses)),
	}
end

-- Progress toward the next rank: Frac 0..1 (1 at Gold, which has no next rank) and its caption.
function RatingLogic.progress(r: any): { Frac: number, Text: string }
	local v = RatingLogic.rating(r)
	if not v then
		return { Frac = 0, Text = "" }
	end
	if v.NextRankAt == nil then
		return { Frac = 1, Text = `{v.DR} DR  MAX RANK` }
	end
	local floor = rankRow(v.Rank).Floor
	local span = math.max(1, v.NextRankAt - floor)
	return {
		Frac = math.clamp((v.DR - floor) / span, 0, 1),
		Text = `{v.DR} / {v.NextRankAt} DR`,
	}
end

function RatingLogic.streakText(streak: any): string
	local n = math.max(0, whole(streak))
	return if n > 0 then `{n} WIN STREAK` else ""
end

function RatingLogic.deltaText(delta: any): string
	local n = whole(delta)
	return if n >= 0 then `+{n} DR` else `-{-n} DR`
end

-- m:ss for the search timer; negative / junk clamps to 0:00.
function RatingLogic.clock(seconds: any): string
	local n = math.max(0, whole(seconds))
	return `{n // 60}:{string.format("%02d", n % 60)}`
end

-- Widest label the button can show: the view sizes the text for this so the live timer never re-fits.
RatingLogic.QUEUE_WIDEST = "SEARCHING 0:00 - CANCEL"

-- Lobby 1v1 matchmaking button. State: "Find" (tap queues, On = true), "Searching" (tap cancels, On = false),
-- "Matched" (disabled), "Disabled" (+ Note why). `now` = workspace:GetServerTimeNow(); QueueSince is on the same clock.
function RatingLogic.queueButton(
	snap: any,
	busy: boolean,
	tutorialBlocked: boolean,
	now: number?
): { State: string, Label: string, Note: string?, On: boolean? }
	if type(snap) ~= "table" or tutorialBlocked then
		return { State = "Disabled", Label = "FIND MATCH" }
	end
	if snap.QueueState == "Matched" then
		return { State = "Matched", Label = "MATCH FOUND..." }
	end
	if snap.QueueState == "Searching" then
		local since = if type(snap.QueueSince) == "number" then snap.QueueSince else (now or 0)
		return {
			State = if busy then "Disabled" else "Searching",
			Label = `SEARCHING {RatingLogic.clock((now or since) - since)} - CANCEL`,
			On = false,
		}
	end
	if snap.CanQueue ~= true then
		return { State = "Disabled", Label = "FIND MATCH", Note = "Finish your starter rolls to play 1v1" }
	end
	return { State = if busy then "Disabled" else "Find", Label = "FIND MATCH", On = true }
end

-- Toast wording for a QueueDuel / Surrender / LeaveDuel refusal code; nil = fall back to the generic table.
local DUEL_CODES = {
	FinishStarterRolls = "Finish your starter rolls to play 1v1.",
	BadDeck = "Your deck is not ready for 1v1.",
	Unavailable = "1v1 is unavailable right now. Try again soon.",
	WrongPhase = "You can't do that right now.",
	NotLoaded = "Still loading your profile. Try again in a moment.",
}
function RatingLogic.duelCodeText(code: any): string?
	return DUEL_CODES[code]
end

-- Surrender button / confirm model for the in-match HUD.
function RatingLogic.surrender(snap: any): { Show: boolean, Waiting: boolean }
	if type(snap) ~= "table" or snap.Mode ~= "Duel" then
		return { Show = false, Waiting = false }
	end
	return { Show = snap.CanSurrender == true, Waiting = snap.DuelWaiting == true }
end
RatingLogic.SURRENDER_PROMPT = "Surrender? You will lose DR."
RatingLogic.WAITING_TEXT = "Waiting for opponent..."

-- In-match HUD. Show = true only for a Duel snapshot; Solo / Co-op (or Mode nil) show nothing extra.
function RatingLogic.hud(snap: any): { Show: boolean, Text: string, Rank: string?, Lives: number, IsBot: boolean }
	if type(snap) ~= "table" or snap.Mode ~= "Duel" then
		return { Show = false, Text = "", Lives = 0, IsBot = false }
	end
	local opp = if type(snap.Opponent) == "table" then snap.Opponent else {}
	local name = if type(opp.Name) == "string" and opp.Name ~= "" then opp.Name else "Opponent"
	local lives = math.max(0, whole(snap.OpponentLives))
	local rank = if opp.Rank ~= nil then RatingLogic.rankName(opp.Rank) else nil
	return {
		Show = true,
		Text = `VS {name}{if rank then "  " .. rank else ""}  LIVES {lives}`,
		Rank = rank,
		Lives = lives,
		IsBot = opp.IsBot == true,
	}
end

local OUTCOME = {
	Win = { Title = "VICTORY", Color = { 120, 230, 120 } },
	Loss = { Title = "DEFEAT", Color = { 240, 110, 100 } },
}

-- One line under the title from Outcome + Why; nil when the plain title says it all.
function RatingLogic.resultSubtitle(d: any): string?
	if type(d) ~= "table" then
		return nil
	end
	local win = d.Outcome == "Win"
	if d.Why == "EarlyForfeit" then
		return "Quit too early: no DR was awarded"
	elseif d.Why == "Surrender" then
		return if win then "Opponent surrendered" else "You surrendered"
	elseif d.Why == "Forfeit" then
		return if win then "Opponent left the match" else "You left the match"
	elseif d.Why == "Tiebreak" then
		return "Decided on kills"
	end
	return nil
end

-- Ended Duel card model, or nil when the snapshot has no DuelResult (Solo / Co-op results are untouched).
function RatingLogic.result(snap: any)
	local d = if type(snap) == "table" then snap.DuelResult else nil
	if type(d) ~= "table" then
		return nil
	end
	local o = OUTCOME[d.Outcome] or OUTCOME.Loss
	local bonus = math.max(0, whole(d.StreakBonus))
	local before, after = rankRow(d.RankBefore).Name, rankRow(d.RankAfter).Name
	local changed = d.RankBefore ~= nil and d.RankAfter ~= nil and before ~= after
	local streak = math.max(0, whole(d.Streak))
	local gold = math.max(0, whole(d.Gold))
	local up = false
	if changed then
		local bi, ai = 0, 0
		for i, r in RatingLogic.RANKS do
			if r.Name == before then
				bi = i
			end
			if r.Name == after then
				ai = i
			end
		end
		up = ai > bi
	end
	return {
		Title = o.Title,
		Color = o.Color,
		DeltaText = RatingLogic.deltaText(d.DRDelta),
		Delta = whole(d.DRDelta),
		BonusText = if bonus > 0 then `Streak bonus +{bonus} DR` else nil,
		RankText = RatingLogic.rankName(d.RankAfter),
		RankColor = RatingLogic.rankColor(d.RankAfter),
		RankChanged = changed,
		RankUp = up,
		RankChangeText = if changed
			then `{if up then "RANK UP" else "RANK DOWN"}: {string.upper(before)} > {string.upper(after)}`
			else nil,
		DRText = `{math.max(0, whole(d.DRAfter))} DR`,
		StreakText = if streak > 0 then `{streak} win streak` else "No win streak",
		GoldText = if gold > 0 then `+{gold} Gold` else nil,
		Subtitle = RatingLogic.resultSubtitle(d),
		NoDR = d.Why == "EarlyForfeit",
		VsBot = d.VsBot == true,
		BotText = if d.VsBot == true then "Practice match vs bot" else nil,
	}
end

return RatingLogic
