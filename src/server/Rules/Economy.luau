-- Counter arithmetic for MP, Gold, Gems and Xp (Rules/Rewards applies bundles
-- through Sum). A rejected change leaves the record exactly as it was.
local Formulas = require(script.Parent.Formulas)
local Validate = require(script.Parent.Validate)

local Economy = {}

Economy.MAX = Validate.MAX_INT

-- Keys TryChange may change: the match's "mp" and the profile's "Gold". Gems and
-- Xp change only through Rules/Rewards, so one rule set guards them.
local KEYS = { mp = true, Gold = true }

-- current + delta as (true, result), or (false, code): BadAmount (delta not an int
-- in ±MAX, or current not in 0..MAX), Insufficient (below 0), Overflow (above MAX).
function Economy.Sum(current: any, delta: any): (boolean, any)
	if not Validate.IsInt(delta, -Economy.MAX, Economy.MAX) or not Validate.IsInt(current, 0, Economy.MAX) then
		return false, "BadAmount"
	end
	local result = current + delta
	if result < 0 then
		return false, "Insufficient"
	elseif result > Economy.MAX then
		return false, "Overflow"
	end
	return true, result
end

-- Adds integer `delta` to record[key]. Codes: BadKey, or a Sum code.
function Economy.TryChange(record: any, key: any, delta: any): (boolean, string?)
	if type(record) ~= "table" or KEYS[key] ~= true then
		return false, "BadKey"
	end
	local ok, result = Economy.Sum(record[key], delta)
	if not ok then
		return false, result
	end
	record[key] = result
	return true, nil
end

-- Pays the end-of-match reward once per run id. Returns (true, gold) or
-- (false, code): BadRun, BadWaves, BadResult, AlreadyGranted, or a TryChange code.
function Economy.GrantRunReward(profile: any, runId: any, waves: any, won: any): (boolean, any)
	if not Validate.IsInt(runId, 1, 2 ^ 31 - 1) then
		return false, "BadRun"
	end
	if not Validate.IsInt(waves, 0, 1000) then
		return false, "BadWaves"
	end
	if type(won) ~= "boolean" then
		return false, "BadResult"
	end
	if profile.LastRewardRunId == runId then
		return false, "AlreadyGranted"
	end
	local gold = Formulas.RewardGold(waves)
	local ok, code = Economy.TryChange(profile, "Gold", gold)
	if not ok then
		return false, code
	end
	profile.LastRewardRunId = runId
	profile.BestWave = math.max(profile.BestWave, waves)
	profile.RunsPlayed = math.min(Economy.MAX, profile.RunsPlayed + 1)
	profile.TrialCleared = profile.TrialCleared or won
	return true, gold
end

return Economy
