-- Quest progress, claims, the run reward and daily/weekly tracking. Pure: callers
-- pass `now` (unix seconds). Every payment is one Rewards.Apply bundle. Progress
-- is derived, never stored: one-time quests read profile stats, the daily reads
-- profile.Daily.Kills, weeklies read profile.Weekly[quest.Weekly].
--
-- Effective day = max(Day(now), Daily.Day) and effective week = max(Week(now),
-- Weekly.Week) everywhere, so a clock that goes backwards can never reopen a claimed
-- day or week. Daily and Weekly roll only in SettleRun, and only when the effective
-- period is later than the stored one; View and Claim never roll.
local Balance = require(script.Parent.Parent.Config.Balance)
local Config = require(script.Parent.Parent.Config.Quests)
local Dice = require(script.Parent.Parent.Config.Dice)
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

-- Weeks start Monday 00:00 UTC (day 0, 1970-01-01, was a Thursday).
function Quests.Week(now: number): number
	return math.floor((Quests.Day(now) + 3) / 7)
end

local function effectiveDay(profile, now: number): number
	return math.max(Quests.Day(now), profile.Daily.Day)
end

local function effectiveWeek(profile, now: number): number
	return math.max(Quests.Week(now), profile.Weekly.Week)
end

-- (progress, claimed) for one quest on `day` / `week`; progress is capped at Goal.
local function status(profile, quest, day: number, week: number): (number, boolean)
	if quest.Weekly then
		if profile.Weekly.Week ~= week then
			return 0, false -- not rolled yet: a new week starts empty
		end
		return math.min(quest.Goal, profile.Weekly[quest.Weekly]), profile.Weekly.Claimed[quest.Id] == true
	end
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

-- { Quests = {{Id, Name, Desc, Goal, Progress, Gold, Gems, Claimed, Daily, Section}},
-- DailyResetAt, WeeklyResetAt } for the Meta push; Section is "Story", "Daily" or "Weekly".
function Quests.View(profile: any, now: number)
	local day, week = effectiveDay(profile, now), effectiveWeek(profile, now)
	local list = {}
	for _, quest in Config.List do
		local progress, claimed = status(profile, quest, day, week)
		table.insert(list, {
			Id = quest.Id,
			Name = quest.Name,
			Desc = quest.Desc,
			Goal = quest.Goal,
			Progress = progress,
			Gold = quest.Reward.Gold or 0,
			Gems = quest.Reward.Gems or 0,
			Claimed = claimed,
			Daily = quest.Daily == true,
			Section = if quest.Daily then "Daily" elseif quest.Weekly then "Weekly" else "Story",
		})
	end
	-- Week w starts on day 7w - 3 (a Monday).
	return { Quests = list, DailyResetAt = (day + 1) * DAY, WeeklyResetAt = ((week + 1) * 7 - 3) * DAY }
end

-- Pays the quest's Reward bundle, then writes its flag (Daily, Weekly or Claimed)
-- with no yield between. Codes: BadTime, UnknownQuest, AlreadyClaimed, NotComplete,
-- or a Rewards.Apply code (Overflow); a rejection changes nothing.
function Quests.Claim(profile: any, id: any, now: any): (boolean, string?)
	if not validNow(now) then
		return false, "BadTime"
	end
	local quest = if type(id) == "string" then Config.ById[id] else nil
	if quest == nil then
		return false, "UnknownQuest"
	end
	local progress, claimed = status(profile, quest, effectiveDay(profile, now), effectiveWeek(profile, now))
	if claimed then
		return false, "AlreadyClaimed"
	end
	if progress < quest.Goal then
		return false, "NotComplete"
	end
	local ok, code = Rewards.Apply(profile, quest.Reward)
	if not ok then
		return false, code
	end
	if quest.Weekly then
		profile.Weekly.Claimed[quest.Id] = true
	elseif quest.Daily then
		profile.Daily.Claimed[quest.Id] = true
	else
		profile.Claimed[quest.Id] = true
	end
	return true, nil
end

-- Pays the run reward once per run id as one Rewards bundle {Gold?, Xp?, Materials?}
-- (zero parts left out), then updates the stats, adds the run's kills to today's and
-- this week's totals and gives each owned die of the match `deck` Mastery Xp = waves.
-- Returns (true, bundle) or (false, code); codes: BadKills, BadTime, BadRun,
-- BadWaves, BadResult, AlreadyGranted (a replay: no kills), or a Rewards.Apply code
-- (Overflow): on any refusal nothing changes, LastRewardRunId included.
function Quests.SettleRun(profile: any, runId: any, waves: any, kills: any, now: any, deck: { string }?): (boolean, any)
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
	if profile.LastRewardRunId == runId then
		return false, "AlreadyGranted"
	end
	local gold, xp, fragments = Formulas.RewardGold(waves), Formulas.RewardXp(waves), Formulas.RewardFragments(waves)
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
	local won = waves >= Balance.TrialWave
	profile.TrialCleared = profile.TrialCleared or won
	local day = effectiveDay(profile, now)
	if day > profile.Daily.Day then
		profile.Daily = { Day = day, Kills = 0, Claimed = {} }
	end
	profile.Daily.Kills = math.min(Economy.MAX, profile.Daily.Kills + kills)
	local week = effectiveWeek(profile, now)
	if week > profile.Weekly.Week then
		profile.Weekly = { Week = week, Kills = 0, Runs = 0, Claimed = {} }
	end
	profile.Weekly.Kills = math.min(Economy.MAX, profile.Weekly.Kills + kills)
	profile.Weekly.Runs = math.min(Economy.MAX, profile.Weekly.Runs + 1)
	profile.Stats.Kills = math.min(Economy.MAX, profile.Stats.Kills + kills)
	profile.Stats.Wins = math.min(Economy.MAX, profile.Stats.Wins + (if won then 1 else 0))
	if waves > 0 and type(deck) == "table" then
		local seen = {}
		for _, id in deck do
			if type(id) == "string" and Dice.Types[id] ~= nil and profile.Dice[id] ~= nil and not seen[id] then
				seen[id] = true
				local mastery = profile.Mastery[id] or { Xp = 0, Claimed = {} }
				mastery.Xp = math.min(Economy.MAX, mastery.Xp + waves)
				profile.Mastery[id] = mastery
			end
		end
	end
	return true, bundle
end

return Quests
