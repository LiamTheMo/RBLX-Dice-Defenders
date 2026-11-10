-- The only code that changes Energy or Gold. A rejected change leaves the record
-- exactly as it was.
local Formulas = require(script.Parent.Formulas)
local Validate = require(script.Parent.Validate)

local Economy = {}

Economy.MAX = Validate.MAX_INT

-- Keys this module may change: the match's "energy" and the profile's "Gold".
local KEYS = { energy = true, Gold = true }

-- Adds integer `delta` to record[key]. Codes: BadKey, BadAmount (NaN, inf, fraction,
-- out of range or a corrupt current value), Insufficient (would go negative),
-- Overflow (would exceed MAX).
function Economy.TryChange(record: any, key: any, delta: any): (boolean, string?)
	if type(record) ~= "table" or KEYS[key] ~= true then
		return false, "BadKey"
	end
	local current = record[key]
	if not Validate.IsInt(delta, -Economy.MAX, Economy.MAX) or not Validate.IsInt(current, 0, Economy.MAX) then
		return false, "BadAmount"
	end
	local result = current + delta
	if result < 0 then
		return false, "Insufficient"
	elseif result > Economy.MAX then
		return false, "Overflow"
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
