-- Claims: one ClaimQuest remote over disjoint id spaces (quests, LOGIN, play
-- milestones, achievements, die mastery). The login calendar, milestones,
-- achievements and mastery claims; every rejection leaves the profile deep-equal.

local Server = game:GetService("ServerScriptService").Server
local Claims = require(Server.Rules.Claims)
local Rewards = require(Server.Rules.Rewards)
local Economy = require(Server.Rules.Economy)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local RemoteGuard = require(Server.Infrastructure.RemoteGuard)
local QuestConfig = require(Server.Config.Quests)
local Daily = require(Server.Config.Daily)
local Milestones = require(Server.Config.Milestones)
local Achievements = require(Server.Config.Achievements)
local Progression = require(Server.Config.Progression)
local Dice = require(Server.Config.Dice)

local DAY = 86400
local D = 20000 -- a UTC day number
local N = D * DAY + 3600 -- 01:00 on day D

local function fresh()
	return ProfileSchema.Default()
end

-- A refused claim must return `code` and leave the profile deep-equal to before.
local function reject(p, id, now, code, label)
	local before = snap(p)
	local ok, got = Claims.Claim(p, id, now)
	expect(not ok and got == code, label .. ": " .. code .. " (got " .. tostring(got) .. ")")
	expectEq(snap(p), before, label .. ": profile unchanged")
end

local function row(list, id)
	for _, r in list do
		if r.Id == id then
			return r
		end
	end
	return nil
end

-- Total account Xp at the start of `level`.
local function accountXp(level)
	local total = 0
	for l = 1, level - 1 do
		total += Progression.Account.Need(l)
	end
	return total
end

test("id spaces are disjoint, fit the ClaimQuest remote and route to their own kind", function()
	local seen, n = {}, 0
	local function add(id, kind)
		n += 1
		expect(seen[id] == nil, "unique id " .. id .. " (also " .. tostring(seen[id]) .. ")")
		seen[id] = kind
		expect(RemoteGuard.Specs.ClaimQuest.check(id) == true, "fits the remote: " .. id)
		expectEq(Claims.Kind(id), kind, "routed " .. id)
	end
	for _, q in QuestConfig.List do
		add(q.Id, "Quest")
	end
	add("LOGIN", "Login")
	for _, m in Milestones.List do
		add(m.Id, "Milestone")
	end
	for _, a in Achievements.List do
		add(a.Id, "Achievement")
	end
	for id in Dice.Types do
		for _, level in Progression.Mastery.Milestones do
			add(id .. ":" .. level, "Mastery")
		end
	end
	for _, id in { "S1", "S2", "S3", "D1", "W1", "W2" } do
		expectEq(seen[id], "Quest", "quest " .. id)
	end
	for _, id in { "P10", "P20", "P30", "P40", "P50", "P100" } do
		expectEq(seen[id], "Milestone", "milestone " .. id)
	end
	for _, id in { "A1", "A2", "A3", "A4", "A5" } do
		expectEq(seen[id], "Achievement", "achievement " .. id)
	end
	expectEq(seen["C01:5"], "Mastery", "mastery C01:5")
	local dice = 0
	for _ in Dice.Types do
		dice += 1
	end
	expectEq(n, 6 + 1 + 6 + 5 + dice * #Progression.Mastery.Milestones, "every id counted once")
end)

test("quest ids claim through the router: paid once, then AlreadyClaimed", function()
	local p = fresh()
	p.RunsPlayed = 1
	p.Weekly = { Week = math.floor((D + 3) / 7), Kills = 1000, Runs = 0, Claimed = {} }
	for _, id in { "S1", "W1" } do
		local reward = QuestConfig.ById[id].Reward
		local gold, gems = p.Gold, p.Gems
		expect(Claims.Claim(p, id, N), id .. " claimed")
		expect(p.Gold == gold + reward.Gold and p.Gems == gems + reward.Gems, id .. " paid")
		reject(p, id, N, "AlreadyClaimed", id .. " twice")
	end
	reject(p, "W2", N, "NotComplete", "W2 not done")
end)

test("unknown ids and non-strings are UnknownQuest and change nothing", function()
	local p = fresh()
	p.BestWave, p.RunsPlayed, p.TrialCleared, p.Xp = 10, 5, true, 1e6
	p.Mastery.C01 = { Xp = 950, Claimed = {} }
	for _, id in
		{
			"",
			"ZZ",
			"login",
			"Login",
			"P5",
			"P11",
			"P1000",
			"A0",
			"A6",
			"a1",
			"w1",
			"C01",
			"C01:",
			":5",
			"C01:4",
			"C01:05",
			"C01:25",
			"C01:5:5",
			"Z99:5",
			"c01:5",
			"C01: 5",
			"C01:5 ",
			"Fragment:5",
		}
	do
		reject(p, id, N, "UnknownQuest", "id '" .. id .. "'")
		expectEq(Claims.Kind(id), nil, "no kind for '" .. id .. "'")
	end
	for _, id in { 5, true, {}, NAN } do
		reject(p, id, N, "UnknownQuest", "non-string " .. type(id))
	end
end)

test("every config bundle is a non-empty valid Rewards bundle that only gives", function()
	local function check(bundle, label)
		expect(type(bundle) == "table" and next(bundle) ~= nil and Rewards.Valid(bundle), label)
		for _, line in Rewards.Lines(bundle) do
			expect(line.Amount >= 1, label .. " gives, never takes: " .. line.Kind .. " " .. tostring(line.Id))
		end
	end
	for _, q in QuestConfig.List do
		check(q.Reward, "quest " .. q.Id)
	end
	for _, m in Milestones.List do
		check(m.Reward, "milestone " .. m.Id)
	end
	for _, a in Achievements.List do
		check(a.Reward, "achievement " .. a.Id)
	end
	local levels = 0
	for level, bundle in Progression.Mastery.Rewards do
		levels += 1
		expect(table.find(Progression.Mastery.Milestones, level) ~= nil, "reward level is a milestone " .. level)
		check(bundle, "mastery Lv" .. level)
	end
	expectEq(levels, #Progression.Mastery.Milestones, "one reward per milestone level")
	expectEq(#Daily.Days, 7, "seven calendar days")
	for i, day in Daily.Days do
		expectEq(day.Day, i, "day order " .. i)
		check(day.Reward, "day " .. i)
		expectEq(day.Chest == true, i == 7, "chest only on day 7 (" .. i .. ")")
		for key, value in day.Reward do
			expect(
				key == "Gold" or key == "Gems" or key == "Items" or key == "Materials" or key == "Dice",
				"kind " .. key
			)
			if key == "Dice" then
				for id in value do
					expect(table.find(Dice.Deck, id) ~= nil, "day " .. i .. " die is a starter: " .. id)
				end
			end
		end
	end
	local seven = Daily.Days[7].Reward
	expect(seven.Gems == 100 and seven.Gold == 1000 and seven.Items.XpTome == 2, "day 7 chest bundle")
end)

test("LOGIN: first claim pays Day 1, the next UTC day Day 2; the same day twice is AlreadyClaimed", function()
	local p = fresh()
	expect(Claims.Claim(p, "LOGIN", N), "first claim")
	expect(p.Login.Streak == 1 and p.Login.LastDay == D, "day 1 recorded")
	expectEq(p.Gold, Daily.Days[1].Reward.Gold, "day 1 Gold")
	expectEq(p.Gems, 50 + Daily.Days[1].Reward.Gems, "day 1 Gems")
	reject(p, "LOGIN", N + 3000, "AlreadyClaimed", "same day")
	reject(p, "LOGIN", (D + 1) * DAY - 1, "AlreadyClaimed", "last second of the day")
	local gold = p.Gold
	expect(Claims.Claim(p, "LOGIN", (D + 1) * DAY), "next day at midnight")
	expect(p.Login.Streak == 2 and p.Login.LastDay == D + 1, "day 2 recorded")
	expectEq(p.Gold, gold + Daily.Days[2].Reward.Gold, "day 2 Gold")
end)

test("LOGIN: a missed day resets to Day 1; after Day 7 comes Day 1", function()
	local p = fresh()
	for i = 1, 7 do
		expect(Claims.Claim(p, "LOGIN", N + (i - 1) * DAY), "day " .. i)
		expectEq(p.Login.Streak, i, "streak " .. i)
	end
	expect(Claims.Claim(p, "LOGIN", N + 7 * DAY), "the day after day 7")
	expectEq(p.Login.Streak, 1, "back to day 1 after day 7")
	expect(Claims.Claim(p, "LOGIN", N + 9 * DAY), "after a missed day")
	expectEq(p.Login.Streak, 1, "a missed day resets")

	local q = fresh()
	for i = 1, 3 do
		Claims.Claim(q, "LOGIN", N + (i - 1) * DAY)
	end
	local gold = q.Gold
	expect(Claims.Claim(q, "LOGIN", N + 4 * DAY), "skipped day 4")
	expectEq(q.Login.Streak, 1, "mid-streak miss resets to day 1")
	expectEq(q.Gold, gold + Daily.Days[1].Reward.Gold, "pays day 1 again")
end)

test("LOGIN: Day 7 pays the whole chest bundle", function()
	local p = fresh()
	p.Login = { Streak = 6, LastDay = D - 1 }
	local gold, gems = p.Gold, p.Gems
	expect(Claims.Claim(p, "LOGIN", N), "day 7")
	expectEq(p.Login.Streak, 7, "streak 7")
	expectEq(p.Gold - gold, 1000, "1000 Gold")
	expectEq(p.Gems - gems, 100, "100 Gems")
	expectEq(p.Items.XpTome, 2, "2 XP Tomes")
end)

test("LOGIN: a clock going backwards or a far-future LastDay never pays; bad time is BadTime", function()
	local p = fresh()
	expect(Claims.Claim(p, "LOGIN", N + DAY), "claimed on day D+1")
	reject(p, "LOGIN", N, "AlreadyClaimed", "clock went back a day")
	reject(p, "LOGIN", N - 100 * DAY, "AlreadyClaimed", "clock went far back")
	local q = fresh()
	q.Login = { Streak = 3, LastDay = D + 10000 }
	reject(q, "LOGIN", N, "AlreadyClaimed", "far-future LastDay")
	reject(q, "LOGIN", N + 30 * DAY, "AlreadyClaimed", "still locked a month later")
	for _, bad in { NAN, INF, -1, "x", {} } do
		reject(fresh(), "LOGIN", bad, "BadTime", "now " .. tostring(bad))
	end
end)

test("LOGIN: Overflow refuses the whole day and leaves it claimable", function()
	local p = fresh()
	p.Gold = Economy.MAX
	reject(p, "LOGIN", N, "Overflow", "Gold at the cap")
	p.Gold = 0
	expect(Claims.Claim(p, "LOGIN", N), "claimable once there is room")
	expectEq(p.Login.Streak, 1, "day 1")
end)

test("View.Login: Streak, ClaimedToday, NextClaimAt and NextDay; View is pure", function()
	local p = fresh()
	local before = snap(p)
	local v = Claims.View(p, N).Login
	expectEq(snap(p), before, "View did not mutate")
	expect(v.Streak == 0 and v.ClaimedToday == false and v.NextDay == 1, "fresh: day 1 claimable")
	expect(v.NextClaimAt <= N, "claimable now")
	Claims.Claim(p, "LOGIN", N)
	v = Claims.View(p, N).Login
	expect(v.Streak == 1 and v.ClaimedToday == true and v.NextDay == nil, "claimed today")
	expectEq(v.NextClaimAt, (D + 1) * DAY, "next claim at the next UTC midnight")
	v = Claims.View(p, N + DAY).Login
	expect(v.Streak == 1 and v.ClaimedToday == false and v.NextDay == 2, "tomorrow pays day 2")
	v = Claims.View(p, N + 2 * DAY).Login
	expect(v.Streak == 0 and v.NextDay == 1, "a missed day shows day 1")
	p.Login = { Streak = 7, LastDay = D }
	v = Claims.View(p, N + DAY).Login
	expect(v.Streak == 0 and v.NextDay == 1, "after day 7 shows day 1")
	p.Login = { Streak = 2, LastDay = D + 50 }
	v = Claims.View(p, N).Login
	expect(v.ClaimedToday == true and v.NextDay == nil and v.NextClaimAt == (D + 51) * DAY, "far future: locked")
end)

test("milestones: P10 pays once after BestWave >= 10; every milestone is claimable at its wave", function()
	local p = fresh()
	p.BestWave = 9
	reject(p, "P10", N, "NotComplete", "wave 9")
	p.BestWave = 10
	local gems = p.Gems
	expect(Claims.Claim(p, "P10", N), "P10 claimed")
	expectEq(p.Gems, gems + 50, "50 Gems")
	expectEq(p.Dice.R01 and p.Dice.R01.Level, 1, "the tutorial's Frost die unlocked")
	expectEq(p.Milestones.P10, true, "flag written")
	reject(p, "P10", N, "AlreadyClaimed", "P10 twice")
	for _, m in Milestones.List do
		local q = fresh()
		q.BestWave = m.Wave - 1
		reject(q, m.Id, N, "NotComplete", m.Id .. " below its wave")
		q.BestWave = m.Wave
		expect(Claims.Claim(q, m.Id, N), m.Id .. " claimable at its wave")
	end
	for _, m in Milestones.List do
		expectEq(m.Reachable, true, m.Id .. " reachable: runs are endless")
	end
	p.BestWave = 10
	local view = Claims.View(p, N).Milestones
	expectEq(#view, #Milestones.List, "one row per milestone")
	for i, m in Milestones.List do
		expectEq(view[i].Id, m.Id, "config order")
	end
	expect(row(view, "P10").Claimed == true and row(view, "P10").Claimable == false, "P10 claimed")
	expect(row(view, "P20").Claimed == false and row(view, "P20").Claimable == false, "P20 locked")
	local q = fresh()
	q.BestWave = 10
	expect(row(Claims.View(q, N).Milestones, "P10").Claimable == true, "P10 claimable")
end)

test("achievements: each derived condition pays once, cosmetics included", function()
	local p = fresh()
	for _, a in Achievements.List do
		reject(p, a.Id, N, "NotComplete", a.Id .. " on a new profile")
	end
	local function claim(id, label)
		local gems = p.Gems
		expect(Claims.Claim(p, id, N), label)
		expectEq(p.Gems, gems + Achievements.ById[id].Reward.Gems, id .. " Gems")
		expectEq(p.Achievements[id], true, id .. " flag")
		reject(p, id, N, "AlreadyClaimed", id .. " twice")
	end
	p.RunsPlayed = 1
	claim("A1", "A1 after one run")
	p.TrialCleared = true
	claim("A2", "A2 after clearing the Trial")
	expectEq(p.Cosmetics.Owned.SproutCap, true, "Sprout Cap granted")
	p.Stats.Kills = 999
	reject(p, "A3", N, "NotComplete", "999 kills")
	p.Stats.Kills = 1000
	claim("A3", "A3 at 1000 kills")
	p.Xp = accountXp(5) - 1
	reject(p, "A4", N, "NotComplete", "one Xp short of level 5")
	p.Xp += 1
	claim("A4", "A4 at level 5")
	expectEq(p.Cosmetics.Owned.ThornDice, true, "Thornbark Dice granted")
	p.Dice.R01 = { Level = 1, Copies = 0 }
	p.Dice.R02 = { Level = 1, Copies = 0 }
	reject(p, "A5", N, "NotComplete", "7 dice")
	p.Dice.E01 = { Level = 1, Copies = 0 }
	claim("A5", "A5 at 8 dice")
	expectEq(p.Cosmetics.Owned.FireflyTrail, true, "Firefly Trail granted")

	local view = Claims.View(p, N).Achievements
	expectEq(#view, #Achievements.List, "one row per achievement")
	for _, a in Achievements.List do
		local r = row(view, a.Id)
		expect(r ~= nil and r.Claimed == true and r.Progress == a.Goal, a.Id .. " view: claimed, progress capped")
	end
	local q = fresh()
	q.Stats.Kills = 250
	expectEq(row(Claims.View(q, N).Achievements, "A3").Progress, 250, "partial progress")
	expectEq(row(Claims.View(q, N).Achievements, "A5").Progress, 5, "the five starters")
end)

test("achievements: Overflow pays nothing and writes no flag", function()
	local p = fresh()
	p.RunsPlayed = 1
	p.Gems = Economy.MAX
	reject(p, "A1", N, "Overflow", "Gems at the cap")
end)

test("mastery: NotComplete before the level, once per level, owned dice only", function()
	local p = fresh()
	reject(p, "C01:5", N, "NotComplete", "no mastery yet")
	p.Mastery.C01 = { Xp = 49, Claimed = {} } -- level 4
	reject(p, "C01:5", N, "NotComplete", "level 4")
	p.Mastery.C01.Xp = 50 -- level 5
	local gems = p.Gems
	expect(Claims.Claim(p, "C01:5", N), "Lv5")
	expectEq(p.Gems, gems + 20, "20 Gems")
	expectEq(p.Mastery.C01.Claimed["5"], true, "level flag")
	reject(p, "C01:5", N, "AlreadyClaimed", "Lv5 twice")
	reject(p, "C01:10", N, "NotComplete", "Lv10 at level 5")
	reject(p, "C02:5", N, "NotComplete", "another die has its own mastery")
	p.Mastery.C01.Xp = 950 -- max level
	expect(Claims.Claim(p, "C01:10", N), "Lv10")
	expectEq(p.Items.XpTome, 1, "Lv10 XP Tome")
	expect(Claims.Claim(p, "C01:15", N) and Claims.Claim(p, "C01:20", N), "Lv15 and Lv20")
	p.Mastery.R01 = { Xp = 950, Claimed = {} } -- a die the profile does not own
	reject(p, "R01:5", N, "NotComplete", "unowned die")
	p.Mastery.C02 = { Xp = 950, Claimed = {} }
	p.Gems = Economy.MAX
	reject(p, "C02:20", N, "Overflow", "Gems at the cap")

	local view = Claims.View(p, N).Mastery
	expectEq(#view, 5, "owned dice only")
	for i = 2, #view do
		expect(view[i - 1].Id < view[i].Id, "sorted by Id")
	end
	local c01 = row(view, "C01")
	expect(c01.Level == 20 and c01.Xp == 0 and c01.XpGoal == 0, "max level")
	expectEq(table.concat(c01.Claimed, ","), "5,10,15,20", "claimed levels as a sorted array")
	local c03 = row(view, "C03")
	expect(c03.Level == 1 and c03.Xp == 0 and c03.XpGoal == 5 and #c03.Claimed == 0, "no mastery yet")
	p.Mastery.C03 = { Xp = 7, Claimed = {} }
	c03 = row(Claims.View(p, N).Mastery, "C03")
	expect(c03.Level == 2 and c03.Xp == 2 and c03.XpGoal == 10, "Xp into the level")
end)

-- Asserts every table is a plain array or a plain record (nothing a remote would mangle).
local function remoteSafe(v, path)
	if type(v) ~= "table" then
		expect(type(v) ~= "function", path .. " is data")
		return
	end
	local n = 0
	for k, inner in v do
		n += 1
		expect(type(k) == "string" or type(k) == "number", path .. " key type")
		remoteSafe(inner, path .. "." .. tostring(k))
	end
	if #v > 0 then
		expectEq(#v, n, path .. " is a dense array")
	end
	if n > 0 and #v == 0 then
		for k in v do
			expect(type(k) == "string", path .. " record keys are strings")
		end
	end
end

test("the Meta views are remote-safe: arrays and string-keyed records only", function()
	local Quests = require(Server.Rules.Quests)
	local p = fresh()
	p.Mastery.C01 = { Xp = 950, Claimed = { ["5"] = true, ["15"] = true } }
	p.Login = { Streak = 3, LastDay = D }
	remoteSafe(Claims.View(p, N), "View")
	remoteSafe(Claims.View(fresh(), N), "fresh View")
	remoteSafe(Quests.View(p, N), "Quests.View")
end)
