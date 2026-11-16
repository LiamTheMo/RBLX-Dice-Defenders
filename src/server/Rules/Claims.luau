-- The ClaimQuest router (docs/MVP.md "Other claims" and Remotes) and the small claim domains: the
-- LOGIN calendar, play milestones, achievements and die mastery. Pure: callers pass
-- `now` (os.time() seconds). Each claim validates fully, then pays one Rewards.Apply
-- bundle and writes its own once-only flag, with no yield between and the flag only
-- after Apply succeeded, so a rejection changes nothing.
-- Id spaces (disjoint, see claims.spec): quest ids (Config/Quests), "LOGIN",
-- milestone ids (Config/Milestones), achievement ids (Config/Achievements) and
-- mastery "<dieId>:<level>" for a milestone level of Progression.Mastery.
local Achievements = require(script.Parent.Parent.Config.Achievements)
local Daily = require(script.Parent.Parent.Config.Daily)
local Dice = require(script.Parent.Parent.Config.Dice)
local Milestones = require(script.Parent.Parent.Config.Milestones)
local Progression = require(script.Parent.Parent.Config.Progression)
local QuestConfig = require(script.Parent.Parent.Config.Quests)
local Quests = require(script.Parent.Quests)
local Rewards = require(script.Parent.Rewards)

local Claims = {}

local DAY = 86400
local MASTERY = Progression.Mastery

-- Derived achievement progress, by Config/Achievements Stat.
local STAT = {
	RunsPlayed = function(p)
		return p.RunsPlayed
	end,
	TrialCleared = function(p)
		return if p.TrialCleared then 1 else 0
	end,
	Kills = function(p)
		return p.Stats.Kills
	end,
	Level = function(p)
		return (Progression.Level(p.Xp, Progression.Account))
	end,
	DiceOwned = function(p)
		local owned = 0
		for id in Dice.Types do
			if p.Dice[id] ~= nil then
				owned += 1
			end
		end
		return owned
	end,
}
for _, a in Achievements.List do
	assert(STAT[a.Stat], "Claims: no progress for achievement " .. a.Id)
end

local function validNow(now: any): boolean
	return type(now) == "number" and now == now and now ~= math.huge and now >= 0
end

-- (dieId, level) for "<dieId>:<level>" with a known die and a milestone level; the
-- level must be written plainly ("C01:05" is not an id).
local function masteryId(id: string): (string?, number?)
	local die, digits = string.match(id, "^(%w+):(%d+)$")
	if die == nil or Dice.Types[die] == nil then
		return nil, nil
	end
	local level = tonumber(digits)
	if tostring(level) ~= digits or MASTERY.Rewards[level] == nil then
		return nil, nil
	end
	return die, level
end

-- "Quest", "Login", "Milestone", "Achievement", "Mastery", or nil for an unknown id.
function Claims.Kind(id: any): string?
	if type(id) ~= "string" then
		return nil
	elseif QuestConfig.ById[id] then
		return "Quest"
	elseif id == "LOGIN" then
		return "Login"
	elseif Milestones.ById[id] then
		return "Milestone"
	elseif Achievements.ById[id] then
		return "Achievement"
	elseif masteryId(id) then
		return "Mastery"
	end
	return nil
end

-- Pays `bundle`, then sets flags[key]; nothing changes on a refusal.
local function pay(profile, bundle, flags, key: string): (boolean, string?)
	local ok, code = Rewards.Apply(profile, bundle)
	if not ok then
		return false, code
	end
	flags[key] = true
	return true, nil
end

local function achievementProgress(profile, a): number
	return math.min(a.Goal, STAT[a.Stat](profile))
end

local function masteryEntry(profile, die: string)
	return if profile.Dice[die] ~= nil then profile.Mastery[die] else nil -- owned dice only
end

-- Claimable once per UTC day after LastDay. A claim the day after LastDay continues
-- the streak (after Day 7 comes Day 1); a missed day starts again at Day 1.
local function claimLogin(profile, now: number): (boolean, string?)
	local login, today = profile.Login, Quests.Day(now)
	if today <= login.LastDay then
		return false, "AlreadyClaimed" -- also a clock behind LastDay or a far-future LastDay
	end
	local streak = if login.LastDay == today - 1 then login.Streak % 7 + 1 else 1
	local ok, code = Rewards.Apply(profile, Daily.Days[streak].Reward)
	if not ok then
		return false, code
	end
	login.Streak, login.LastDay = streak, today
	return true, nil
end

-- Routes one ClaimQuest id. Codes: BadTime, UnknownQuest, AlreadyClaimed,
-- NotComplete, or a Rewards.Apply code (Overflow).
function Claims.Claim(profile: any, id: any, now: any): (boolean, string?)
	if not validNow(now) then
		return false, "BadTime"
	end
	local kind = Claims.Kind(id)
	if kind == "Quest" then
		return Quests.Claim(profile, id, now)
	elseif kind == "Login" then
		return claimLogin(profile, now)
	elseif kind == "Milestone" then
		local m = Milestones.ById[id]
		if profile.Milestones[id] then
			return false, "AlreadyClaimed"
		elseif not m.Reachable or profile.BestWave < m.Wave then
			return false, "NotComplete"
		end
		return pay(profile, m.Reward, profile.Milestones, id)
	elseif kind == "Achievement" then
		local a = Achievements.ById[id]
		if profile.Achievements[id] then
			return false, "AlreadyClaimed"
		elseif achievementProgress(profile, a) < a.Goal then
			return false, "NotComplete"
		end
		return pay(profile, a.Reward, profile.Achievements, id)
	elseif kind == "Mastery" then
		local die, level = masteryId(id)
		local key, entry = tostring(level), masteryEntry(profile, die)
		if entry ~= nil and entry.Claimed[key] then
			return false, "AlreadyClaimed"
		elseif entry == nil or Progression.Level(entry.Xp, MASTERY) < level then
			return false, "NotComplete"
		end
		return pay(profile, MASTERY.Rewards[level], entry.Claimed, key)
	end
	return false, "UnknownQuest"
end

-- Lobby display for the Meta push. Arrays only, read-only:
--   Login = {Streak, ClaimedToday, NextClaimAt, NextDay?}: Streak counts the days of
--     the current cycle already claimed, NextDay the calendar day a claim now pays
--   Milestones = {{Id, Claimed, Claimable}}, Achievements = {{Id, Progress, Claimed}}
--   Mastery = {{Id, Level, Xp, XpGoal, Claimed = {levels}}} for owned dice, by Id
function Claims.View(profile: any, now: number)
	local login, today = profile.Login, Quests.Day(now)
	local open = today > login.LastDay
	local streak = if not open then login.Streak elseif login.LastDay == today - 1 then login.Streak % 7 else 0

	local milestones = {}
	for _, m in Milestones.List do
		local claimed = profile.Milestones[m.Id] == true
		table.insert(milestones, {
			Id = m.Id,
			Claimed = claimed,
			Claimable = not claimed and m.Reachable and profile.BestWave >= m.Wave,
		})
	end

	local achievements = {}
	for _, a in Achievements.List do
		table.insert(achievements, {
			Id = a.Id,
			Progress = achievementProgress(profile, a),
			Claimed = profile.Achievements[a.Id] == true,
		})
	end

	local mastery = {}
	for id in Dice.Types do
		if profile.Dice[id] ~= nil then
			local entry = profile.Mastery[id]
			local level, into, need = Progression.Level(if entry then entry.Xp else 0, MASTERY)
			local claimed = {}
			for _, lv in MASTERY.Milestones do
				if entry and entry.Claimed[tostring(lv)] then
					table.insert(claimed, lv)
				end
			end
			table.insert(mastery, { Id = id, Level = level, Xp = into, XpGoal = need, Claimed = claimed })
		end
	end
	table.sort(mastery, function(a, b)
		return a.Id < b.Id
	end)

	return {
		Login = {
			Streak = streak,
			ClaimedToday = not open,
			NextClaimAt = (math.max(today - 1, login.LastDay) + 1) * DAY,
			NextDay = if open then streak + 1 else nil,
		},
		Milestones = milestones,
		Achievements = achievements,
		Mastery = mastery,
	}
end

return Claims
