--!strict
-- Result card view model: pure, headless. Maps an Ended State snapshot (+ optional Meta payload) to what the Results UI
-- draws. The server owns every number; this only formats and decides what is hidden. Missing data hides a field, never errors.
--
-- ResultsLogic.view(snap, meta?, own?) -> View?   (nil unless snap.Phase == "Ended")
--   meta = NetClient.LastMeta ({ Level, XpInto, XpNeed }); own = { Name: string?, UserId: number? } (LocalPlayer, client only)
-- View = {
--   Kind: "Summary" | "Victory" | "Defeat",   Summary = Solo / Co-op (no DuelResult); Victory/Defeat = Duel from own Outcome
--   Mode: "Solo" | "Coop" | "Duel",           ModeText: "SOLO" | "COOP" | "1V1" (pill)
--   Title: "SUMMARY" | "VICTORY" | "DEFEAT",
--   OutcomeLine: string?,                     Solo/Co-op Aborted/Error line under the mode pill; nil when Lost
--   Wave: string?,                            "12" (Summary only)
--   RunTime: string?,                         "24:18" via RatingLogic.clock; nil when DurationSec missing
--   Kills: string?,                           "1,285"; nil when missing
--   Tiles: { Tile },   ordered reward tiles, one component for Summary and Victory/Defeat. Coins, Gems, Xp first (each whenever
--                      its amount is a number, 0 included; hidden only when absent), then one "Drop" tile per valid entry of snap.Drops (never invented).
--     Tile = { Kind = "Coins" | "Gems" | "Xp" | "Drop", Text = "+1,450" (Drop: its Name), Name: string?, Rarity: string?,
--              DieId: string?, ArtKey: string? }   Coins = DuelResult.Gold (Duel) / RewardGold; Gems/Xp = RewardGems/RewardXp.
--                      snap.Drops = { { Id?, Name?, Rarity?, ArtKey? } }; an entry needs a string Id or Name.
--   Level: { Level, XpInto, XpNeed, Frac, Text = "5,070 / 6,000 XP", LevelText = "Lv. 12",   final (after) state, from Meta
--            To = { Level, Frac }, From = { Level, Frac }?, LevelUps: number }?   nil without a valid Meta
--            From (count animation start): explicit snap.LevelFrom + snap.XpFrom (+ snap.XpNeedFrom, defaults to XpNeed when the
--            level is unchanged) else Meta after-state minus RewardXp when that stays inside the current level; else nil
--            (UI just shows To). LevelUps = To.Level - From.Level (0 when From is nil): the bar fills across each level.
--   Self: { Name: string?, UserId: number?, Winner: boolean }   Winner = own DuelResult.Outcome == "Win" (Duel only); false on a draw
--   Opponent: { Name, UserId: number?, DRText: string?, Winner: boolean, Silhouette: boolean }?   Duel only; Silhouette
--             when no UserId (bot or id missing); Winner = own Outcome == "Loss"; false on a draw
--   Draw: boolean,                            DuelResult.Outcome == "Draw": neither side is Winner (Kind stays Defeat)
--   Duel: {
--     Delta: number, DeltaText = "+28 DR", DeltaKind = "Gain" | "Loss" | "Zero",   (sign / colour kind)
--     TotalFrom, TotalTo: number (DR before / after; explicit snap.RatingBefore / TotalFrom, else TotalTo - Delta, floor 0),
--     Color: {r,g,b}, DRText = "1,248 DR", RankText, RankColor, RankChanged, RankChangeText?, BonusText?, StreakText,
--     NoDR: boolean, NoDRText: string?, Subtitle: string?, BotText: string?,
--     InfoLine: string?,     the one small line under the delta pill (rank change > streak bonus > NoDR)
--   }?
-- }
-- DR wording is kept (R4). No rule, price or reward is computed here.

local RatingLogic = require(script.Parent.Parent.RatingLogic)

local ResultsLogic = {}

local function whole(n: any): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.floor(n)
end

-- 1234567 -> "1,234,567"; junk -> "0".
function ResultsLogic.commas(n: any): string
	local v = whole(n)
	local s = string.reverse(tostring(math.abs(v)))
	s = string.gsub(s, "(%d%d%d)", "%1,")
	s = string.gsub(string.reverse(s), "^,", "")
	return (if v < 0 then "-" else "") .. s
end

local function plus(n: any): string?
	return if type(n) == "number" then "+" .. ResultsLogic.commas(math.max(0, n)) else nil
end

local MODE_TEXT = { Solo = "SOLO", Coop = "COOP", Duel = "1V1" }
local OUTCOME_LINE = { Aborted = "Run aborted", Error = "Run ended by an error" }

function ResultsLogic.view(snap: any, meta: any?, own: any?)
	if type(snap) ~= "table" or snap.Phase ~= "Ended" then
		return nil
	end
	local d = if type(snap.DuelResult) == "table" then snap.DuelResult else nil
	local mode = if d then "Duel" elseif snap.Mode == "Coop" then "Coop" else "Solo"
	local win = d ~= nil and d.Outcome == "Win"
	local ownInfo = if type(own) == "table" then own else {}
	local view: any = {
		Draw = d ~= nil and d.Outcome == "Draw",
		Kind = if d == nil then "Summary" elseif win then "Victory" else "Defeat",
		Mode = mode,
		ModeText = MODE_TEXT[mode],
		Title = if d == nil then "SUMMARY" elseif win then "VICTORY" else "DEFEAT",
		OutcomeLine = if d == nil then OUTCOME_LINE[snap.Result] else nil,
		Wave = if d == nil and type(snap.Wave) == "number" then ResultsLogic.commas(snap.Wave) else nil,
		RunTime = if type(snap.DurationSec) == "number" then RatingLogic.clock(snap.DurationSec) else nil,
		Kills = if type(snap.Kills) == "number" then ResultsLogic.commas(snap.Kills) else nil,
		Self = { Name = ownInfo.Name, UserId = ownInfo.UserId, Winner = win },
	}
	local tiles = {}
	local function amount(kind: string, n: any)
		if type(n) == "number" then -- a real 0 still shows; only an absent value hides
			table.insert(tiles, { Kind = kind, Text = plus(n) })
		end
	end
	amount("Coins", if d then d.Gold else snap.RewardGold)
	amount("Gems", snap.RewardGems)
	amount("Xp", snap.RewardXp)
	if type(snap.Drops) == "table" then
		for _, drop in snap.Drops do
			if type(drop) == "table" and (type(drop.Name) == "string" or type(drop.Id) == "string") then
				local name = if type(drop.Name) == "string" then drop.Name else drop.Id
				table.insert(tiles, {
					Kind = "Drop",
					Text = name,
					Name = name,
					Rarity = if type(drop.Rarity) == "string" then drop.Rarity else nil,
					DieId = if type(drop.Id) == "string" then drop.Id else nil,
					ArtKey = if type(drop.ArtKey) == "string"
						then drop.ArtKey
						elseif type(drop.Id) == "string" then drop.Id
						else nil,
				})
			end
		end
	end
	view.Tiles = tiles
	local m = if type(meta) == "table" then meta else nil
	if
		m
		and type(m.Level) == "number"
		and type(m.XpInto) == "number"
		and type(m.XpNeed) == "number"
		and m.XpNeed > 0
	then
		view.Level = {
			Level = whole(m.Level),
			XpInto = whole(m.XpInto),
			XpNeed = whole(m.XpNeed),
			Frac = math.clamp(m.XpInto / m.XpNeed, 0, 1),
			Text = `{ResultsLogic.commas(m.XpInto)} / {ResultsLogic.commas(m.XpNeed)} XP`,
			LevelText = `Lv. {whole(m.Level)}`,
			To = { Level = whole(m.Level), Frac = math.clamp(m.XpInto / m.XpNeed, 0, 1) },
			LevelUps = 0,
		}
		local lv = view.Level
		local from = nil
		if type(snap.LevelFrom) == "number" and type(snap.XpFrom) == "number" then
			local need = if type(snap.XpNeedFrom) == "number" then snap.XpNeedFrom else nil
			if need == nil and snap.LevelFrom == m.Level then
				need = m.XpNeed
			end
			if need and need > 0 then
				from = { Level = whole(snap.LevelFrom), Frac = math.clamp(snap.XpFrom / need, 0, 1) }
			end
		elseif type(snap.RewardXp) == "number" and snap.RewardXp >= 0 and snap.RewardXp <= m.XpInto then
			from = { Level = lv.Level, Frac = math.clamp((m.XpInto - snap.RewardXp) / m.XpNeed, 0, 1) }
		end
		if from then
			lv.From = from
			lv.LevelUps = math.max(0, lv.Level - from.Level)
		end
	end
	local r = RatingLogic.result(snap)
	if d and r then
		local opp = if type(snap.Opponent) == "table" then snap.Opponent else nil
		local oppId = if type(snap.OpponentUserId) == "number" then snap.OpponentUserId else nil
		view.Opponent = {
			Name = if opp and type(opp.Name) == "string" then opp.Name else "Opponent",
			UserId = oppId,
			DRText = if opp and type(opp.DR) == "number" then `{ResultsLogic.commas(opp.DR)} DR` else nil,
			Winner = d.Outcome == "Loss",
			Silhouette = oppId == nil or (opp ~= nil and opp.IsBot == true),
		}
		local to = math.max(0, whole(d.DRAfter))
		local explicit = if type(snap.RatingBefore) == "number" then snap.RatingBefore else snap.TotalFrom
		view.Duel = {
			TotalTo = to,
			TotalFrom = if type(explicit) == "number" then math.max(0, whole(explicit)) else math.max(0, to - r.Delta),
			Delta = r.Delta,
			DeltaText = `{if r.Delta < 0 then "-" else "+"}{ResultsLogic.commas(math.abs(r.Delta))} DR`,
			DeltaKind = if r.Delta > 0 then "Gain" elseif r.Delta < 0 then "Loss" else "Zero",
			Color = r.Color,
			DRText = `{ResultsLogic.commas(d.DRAfter)} DR`,
			RankText = r.RankText,
			RankColor = r.RankColor,
			RankChanged = r.RankChanged,
			RankChangeText = r.RankChangeText,
			BonusText = r.BonusText,
			StreakText = r.StreakText,
			NoDR = r.NoDR,
			NoDRText = if r.NoDR then r.Subtitle else nil,
			Subtitle = r.Subtitle,
			BotText = r.BotText,
			InfoLine = r.RankChangeText or r.BonusText or (if r.NoDR then r.Subtitle else nil),
		}
	end
	return view
end

return ResultsLogic
