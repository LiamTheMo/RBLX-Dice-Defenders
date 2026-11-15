-- Quest progress, claims, the run reward and daily kill tracking. Pure: callers
-- pass `now` (unix seconds). Gold moves only through Economy and Rewards. Progress
-- is derived, never stored: one-time quests read profile stats, the daily reads
-- profile.Daily.Kills.
--
-- Effective day = max(Day(now), Daily.Day) everywhere, so a clock that goes
-- backwards can never reopen a claimed day. Daily state rolls only in SettleRun,
-- and only when the effective day is later than Daily.Day; View and Claim never roll.
local Config = require(script.Parent.Parent.Config.Quests)
local Economy = require(script.Parent.Economy)
local Formulas = require(script.Parent.Formulas)
local Rewards = require(script.Parent.Rewards)
local Validate = require(script.Parent.Validate)

local Quests = {}

local DAY = 86400
local MAX_KILLS_PER_RUN = 1_000_000

local function validNow(now: any): boolean
	return type(now) == "number" and now == now and now ~= math.huge and now >= 0
end

function Quests.Day(now: number): number
	return math.floor(now / DAY)
end

local function effectiveDay(profile, now: number): number
	return math.max(Quests.Day(now), profile.Daily.Day)
end

-- (progress, claimed) for one quest on `day`; progress is capped at Goal.
local function status(profile, quest, day: number): (number, boolean)
	if quest.Daily then
		if profile.Daily.Day ~= day then
			return 0, false -- not rolled yet: a new day starts empty
		end
		return math.min(quest.Goal, profile.Daily.Kills), profile.Daily.Claimed[quest.Id] == true
	end
	local stat = profile[quest.Stat]
	local value = if type(stat) == "boolean" then (if stat then 1 else 0) else stat
	return math.min(quest.Goal, value), profile.Claimed[quest.Id] == true
end

-- { Quests = {{Id, Name, Desc, Goal, Progress, Gold, Claimed, Daily}}, DailyResetAt } for the Meta push.
function Quests.View(profile: any, now: number)
	local day = effectiveDay(profile, now)
	local list = {}
	for _, quest in Config.List do
		local progress, claimed = status(profile, quest, day)
		table.insert(list, {
			Id = quest.Id,
			Name = quest.Name,
			Desc = quest.Desc,
			Goal = quest.Goal,
			Progress = progress,
			Gold = quest.Gold,
			Claimed = claimed,
			Daily = quest.Daily == true,
		})
	end
	return { Quests = list, DailyResetAt = (day + 1) * DAY }
end

-- Codes: BadTime, UnknownQuest, AlreadyClaimed, NotComplete, or an Economy code (Overflow).
function Quests.Claim(profile: any, id: any, now: any): (boolean, string?)
	if not validNow(now) then
		return false, "BadTime"
	end
	local quest = if type(id) == "string" then Config.ById[id] else nil
	if quest == nil then
		return false, "UnknownQuest"
	end
	local progress, claimed = status(profile, quest, effectiveDay(profile, now))
	if claimed then
		return false, "AlreadyClaimed"
	end
	if progress < quest.Goal then
		return false, "NotComplete"
	end
	local ok, code = Economy.TryChange(profile, "Gold", quest.Gold)
	if not ok then
		return false, code
	end
	if quest.Daily then
		profile.Daily.Claimed[quest.Id] = true
	else
		profile.Claimed[quest.Id] = true
	end
	return true, nil
end

-- Pays the run reward once per run id as one Rewards bundle {Gold?, Xp?, Materials?}
-- (zero parts left out), then updates the stats and adds the run's kills to today's
-- total. Returns (true, bundle) or (false, code); codes: BadKills, BadTime, BadRun,
-- BadWaves, BadResult, AlreadyGranted (a replay: no kills), or a Rewards.Apply code
-- (Overflow): on any refusal nothing changes, LastRewardRunId included.
function Quests.SettleRun(profile: any, runId: any, waves: any, won: any, kills: any, now: any): (boolean, any)
	if not Validate.IsInt(kills, 0, MAX_KILLS_PER_RUN) then
		return false, "BadKills"
	end
	if not validNow(now) then
		return false, "BadTime"
	end
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
	local gold, xp, fragments =
		Formulas.RewardGold(waves, won), Formulas.RewardXp(waves, won), Formulas.RewardFragments(waves, won)
	local bundle = {
		Gold = if gold > 0 then gold else nil,
		Xp = if xp > 0 then xp else nil,
		Materials = if fragments > 0 then { Fragment = fragments } else nil,
	}
	local ok, code = Rewards.Apply(profile, bundle)
	if not ok then
		return false, code
	end
	profile.LastRewardRunId = runId
	profile.BestWave = math.max(profile.BestWave, waves)
	profile.RunsPlayed = math.min(Economy.MAX, profile.RunsPlayed + 1)
	profile.TrialCleared = profile.TrialCleared or won
	local day = effectiveDay(profile, now)
	if day > profile.Daily.Day then
		profile.Daily = { Day = day, Kills = 0, Claimed = {} }
	end
	profile.Daily.Kills = math.min(Economy.MAX, profile.Daily.Kills + kills)
	return true, bundle
end

return Quests
