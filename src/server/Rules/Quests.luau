-- Quest progress, claims and daily kill tracking. Pure: callers pass `now` (unix
-- seconds). Gold only moves through Economy. Progress is derived, never stored:
-- one-time quests read profile stats, the daily reads profile.Daily.Kills.
--
-- Effective day = max(Day(now), Daily.Day) everywhere, so a clock that goes
-- backwards can never reopen a claimed day. Daily state rolls only in SettleRun,
-- and only when the effective day is later than Daily.Day; View and Claim never roll.
local Config = require(script.Parent.Parent.Config.Quests)
local Economy = require(script.Parent.Economy)
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

-- Pays the run reward (Economy.GrantRunReward) and, only if that was paid, adds the
-- run's kills to today's total. Returns (true, gold) or (false, code); codes: BadKills,
-- BadTime, or a GrantRunReward code (a replayed runId is AlreadyGranted: no kills).
function Quests.SettleRun(profile: any, runId: any, waves: any, won: any, kills: any, now: any): (boolean, any)
	if not Validate.IsInt(kills, 0, MAX_KILLS_PER_RUN) then
		return false, "BadKills"
	end
	if not validNow(now) then
		return false, "BadTime"
	end
	local ok, gold = Economy.GrantRunReward(profile, runId, waves, won)
	if not ok then
		return false, gold
	end
	local day = effectiveDay(profile, now)
	if day > profile.Daily.Day then
		profile.Daily = { Day = day, Kills = 0, Claimed = {} }
	end
	profile.Daily.Kills = math.min(Economy.MAX, profile.Daily.Kills + kills)
	return true, gold
end

return Quests
