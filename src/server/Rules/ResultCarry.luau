--!strict
-- Duel result carry: the reserved Duel server packs the Ended snapshot fields the result screen needs into TeleportData
-- (Build); the lobby server validates them on join (Parse) and shows them once. Cosmetic only: rewards are already granted
-- server-side, so a forged payload can at worst draw a fake screen. Pure; both sides strictly typed and size-capped.
-- TeleportData = { ResultCarry = Payload }; Payload is Ended-snapshot shaped (Phase = "Ended").
local Validate = require(script.Parent.Validate)

local ResultCarry = {}

ResultCarry.KEY = "ResultCarry"
local BIG = 2 ^ 31 - 1

local function int(v: any, lo: number?): boolean
	return Validate.IsInt(v, lo or 0, BIG)
end

local function str(v: any, max: number): boolean
	return type(v) == "string" and #v >= 1 and #v <= max
end

-- Optional field: nil passes, anything else must satisfy `ok`.
local function opt(v: any, ok: (any) -> boolean): boolean
	return v == nil or ok(v)
end

local OUTCOMES = { Win = true, Loss = true, Draw = true }

local function cleanDuel(d: any): any?
	if type(d) ~= "table" or not OUTCOMES[d.Outcome] then
		return nil
	end
	if
		not (
			int(d.DRBefore)
			and int(d.DRAfter)
			and int(d.DRDelta, -BIG)
			and int(d.StreakBonus)
			and int(d.Streak)
			and int(d.Gold)
		)
	then
		return nil
	end
	if not (str(d.RankBefore, 32) and str(d.RankAfter, 32) and opt(d.Why, function(v)
		return str(v, 24)
	end)) then
		return nil
	end
	return {
		Outcome = d.Outcome,
		Why = d.Why,
		DRBefore = d.DRBefore,
		DRAfter = d.DRAfter,
		DRDelta = d.DRDelta,
		StreakBonus = d.StreakBonus,
		Streak = d.Streak,
		RankBefore = d.RankBefore,
		RankAfter = d.RankAfter,
		Gold = d.Gold,
		VsBot = if d.VsBot == true then true else nil,
	}
end

local function cleanOpponent(o: any): any?
	if
		type(o) ~= "table"
		or not str(o.Name, 64)
		or not int(o.DR)
		or not str(o.Rank, 32)
		or type(o.IsBot) ~= "boolean"
	then
		return nil
	end
	return { Name = o.Name, DR = o.DR, Rank = o.Rank, IsBot = o.IsBot }
end

-- The compact payload from an Ended Duel snapshot, or nil when the snapshot is not an Ended Duel with a result.
function ResultCarry.Build(snap: any): any?
	if type(snap) ~= "table" or snap.Phase ~= "Ended" or snap.Mode ~= "Duel" then
		return nil
	end
	return ResultCarry.Parse({
		Phase = "Ended",
		Mode = "Duel",
		Result = snap.Result,
		Wave = snap.Wave,
		WavesCompleted = snap.WavesCompleted,
		Kills = snap.Kills,
		DurationSec = snap.DurationSec,
		RewardGold = snap.RewardGold,
		RewardXp = snap.RewardXp,
		RewardGems = snap.RewardGems,
		XpFrom = snap.XpFrom,
		LevelFrom = snap.LevelFrom,
		XpNeedFrom = snap.XpNeedFrom,
		RatingBefore = snap.RatingBefore,
		OpponentUserId = snap.OpponentUserId,
		Opponent = snap.Opponent,
		DuelResult = snap.DuelResult,
	})
end

-- A clean copy of an untrusted payload (only known fields, checked types and sizes) or nil when anything is off.
function ResultCarry.Parse(p: any): any?
	if type(p) ~= "table" or p.Phase ~= "Ended" or p.Mode ~= "Duel" then
		return nil
	end
	local duel, opponent = cleanDuel(p.DuelResult), cleanOpponent(p.Opponent)
	if duel == nil or opponent == nil then
		return nil
	end
	if not (str(p.Result, 16) and int(p.Wave) and int(p.Kills) and int(p.DurationSec)) then
		return nil
	end
	if not (int(p.RewardGold) and int(p.RewardXp) and int(p.RewardGems)) then
		return nil
	end
	if not (int(p.XpFrom) and int(p.LevelFrom, 1) and int(p.XpNeedFrom) and int(p.RatingBefore)) then
		return nil
	end
	if
		not opt(p.WavesCompleted, int)
		or not opt(p.OpponentUserId, function(v)
			return Validate.IsInt(v, 1, 2 ^ 53)
		end)
	then
		return nil
	end
	return {
		Phase = "Ended",
		Mode = "Duel",
		Result = p.Result,
		Wave = p.Wave,
		WavesCompleted = p.WavesCompleted,
		Kills = p.Kills,
		DurationSec = p.DurationSec,
		RewardGold = p.RewardGold,
		RewardXp = p.RewardXp,
		RewardGems = p.RewardGems,
		XpFrom = p.XpFrom,
		LevelFrom = p.LevelFrom,
		XpNeedFrom = p.XpNeedFrom,
		RatingBefore = p.RatingBefore,
		OpponentUserId = p.OpponentUserId,
		Opponent = opponent,
		DuelResult = duel,
	}
end

-- Reads JoinData (`player:GetJoinData()`): the validated payload or nil.
function ResultCarry.FromJoinData(joinData: any): any?
	local data = if type(joinData) == "table" then joinData.TeleportData else nil
	return if type(data) == "table" then ResultCarry.Parse(data[ResultCarry.KEY]) else nil
end

return ResultCarry
