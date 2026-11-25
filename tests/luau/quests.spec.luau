-- Quests rules: derived progress, claims, settle, daily rollover and clock safety.

local Server = game:GetService("ServerScriptService").Server
local Quests = require(Server.Rules.Quests)
local Config = require(Server.Config.Quests)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local Economy = require(Server.Rules.Economy)

local NAN, INF = 0 / 0, math.huge

local DAY = 86400
local N = 20000 * DAY -- start of day 20000

local function fresh()
	return ProfileSchema.Default()
end

local function find(view, id)
	for _, q in view.Quests do
		if q.Id == id then
			return q
		end
	end
	error("quest missing " .. id)
end

-- Deterministic dump of a profile (sorted keys) for before/after comparison.
local function snap(value)
	if type(value) ~= "table" then
		return tostring(value)
	end
	local keys = {}
	for k in value do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in keys do
		table.insert(parts, tostring(k) .. "=" .. snap(value[k]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

test("View is pure, ordered like the catalog, with derived and capped progress", function()
	local p = fresh()
	p.RunsPlayed, p.BestWave, p.TrialCleared = 4, 9, true
	local before = snap(p)
	local view = Quests.View(p, N + 5)
	expectEq(snap(p), before, "View did not mutate")
	expectEq(#view.Quests, #Config.List, "all quests")
	for i, q in Config.List do
		expectEq(view.Quests[i].Id, q.Id, "catalog order")
	end
	expectEq(find(view, "S1").Progress, 1, "capped at goal")
	expectEq(find(view, "S2").Progress, 5, "capped at goal 5")
	expectEq(find(view, "S3").Progress, 1, "boolean stat")
	expectEq(find(view, "D1").Daily, true, "daily flag")
	expectEq(view.DailyResetAt, 20001 * DAY, "reset at next UTC midnight")
end)

test("Claim: UnknownQuest, NotComplete, ok, AlreadyClaimed; stats never change", function()
	local p = fresh()
	for _, bad in { "ZZ", "", 5, {}, true } do
		local _, code = Quests.Claim(p, bad, N)
		expectEq(code, "UnknownQuest", "unknown " .. tostring(bad))
	end
	local before = snap(p)
	local _, notYet = Quests.Claim(p, "S1", N)
	expectEq(notYet, "NotComplete", "not complete")
	expectEq(snap(p), before, "unchanged")
	p.RunsPlayed = 1
	local stats = p.RunsPlayed .. p.BestWave .. tostring(p.TrialCleared) .. p.LastRewardRunId
	expect(Quests.Claim(p, "S1", N), "claimed")
	expectEq(p.Gold, 50, "gold paid")
	expect(find(Quests.View(p, N), "S1").Claimed, "view shows claimed")
	local _, again = Quests.Claim(p, "S1", N)
	expectEq(again, "AlreadyClaimed", "once")
	expectEq(p.Gold, 50, "no double pay")
	expectEq(p.RunsPlayed .. p.BestWave .. tostring(p.TrialCleared) .. p.LastRewardRunId, stats, "stats untouched")
end)

test("Claim near the Gold cap: Overflow leaves the profile unchanged", function()
	local p = fresh()
	p.RunsPlayed = 1
	p.Gold = 1e9 - 10
	local before = snap(p)
	local ok, code = Quests.Claim(p, "S1", N)
	expect(not ok and code == "Overflow", "Overflow")
	expectEq(snap(p), before, "unchanged")
	local ok2, code2 = Quests.Claim(p, "S1", 0 / 0)
	expect(not ok2 and code2 == "BadTime", "NaN time")
	expectEq(snap(p), before, "still unchanged")
end)

test("SettleRun pays once per runId and counts kills only when paid", function()
	local p = fresh()
	local ok, bundle = Quests.SettleRun(p, 7, 3, 40, N)
	expect(ok and bundle.Gold == 15 and bundle.Xp == 30 and bundle.Materials.Fragment == 3, "paid 3 waves of a loss")
	expectEq(p.Daily.Kills, 40, "kills added")
	expectEq(p.Daily.Day, 20000, "day set")
	expectEq(p.RunsPlayed, 1, "run counted")
	local before = snap(p)
	local ok2, code = Quests.SettleRun(p, 7, 3, 40, N)
	expect(not ok2 and code == "AlreadyGranted", "replay refused")
	expectEq(snap(p), before, "replay changes nothing, kills not doubled")
	expect(Quests.SettleRun(p, 8, 1, 10, N + 1), "second run")
	expectEq(p.Daily.Kills, 50, "accumulates within a day")
end)

test("SettleRun rejects bad kills and now without touching the profile", function()
	local p = fresh()
	local before = snap(p)
	for _, kills in { -1, 1.5, 0 / 0, math.huge, 1e6 + 1, "5", {} } do
		local ok, code = Quests.SettleRun(p, 1, 1, kills, N)
		expect(not ok and code == "BadKills", "bad kills " .. tostring(kills))
	end
	for _, now in { -1, 0 / 0, math.huge, -math.huge, "x", {} } do
		local ok, code = Quests.SettleRun(p, 1, 1, 5, now)
		expect(not ok and code == "BadTime", "bad now " .. tostring(now))
	end
	expectEq(snap(p), before, "unchanged")
	expect(Quests.SettleRun(p, 1, 1, 1e6, N), "max kills accepted")
	expectEq(p.Daily.Kills, 1e6, "stored")
end)

test("daily quest: rolls to day N+1; yesterday's unclaimed daily is not claimable", function()
	local p = fresh()
	Quests.SettleRun(p, 1, 1, 150, N)
	expectEq(find(Quests.View(p, N), "D1").Progress, 150, "complete on day N")
	expectEq(find(Quests.View(p, N + DAY), "D1").Progress, 0, "new day empty in view")
	local before = snap(p)
	local ok, code = Quests.Claim(p, "D1", N + DAY)
	expect(not ok and code == "NotComplete", "yesterday's daily is gone")
	expectEq(snap(p), before, "Claim and View never rolled the day")
	expectEq(p.Daily.Day, 20000, "still day N")
	Quests.SettleRun(p, 2, 1, 20, N + DAY)
	expectEq(p.Daily.Day, 20001, "rolled by a run")
	expectEq(p.Daily.Kills, 20, "fresh count")
	expect(next(p.Daily.Claimed) == nil, "claims reset")

	local q = fresh()
	Quests.SettleRun(q, 1, 1, 150, N)
	expect(Quests.Claim(q, "D1", N + 100), "claim today")
	expectEq(q.Gold, 5 + 100, "run reward + quest gold")
	local _, again = Quests.Claim(q, "D1", N + 200)
	expectEq(again, "AlreadyClaimed", "once per day")
end)

test("a clock going backwards never reopens a claimed day", function()
	local p = fresh()
	Quests.SettleRun(p, 1, 1, 150, N + DAY) -- day N+1
	expect(Quests.Claim(p, "D1", N + DAY), "claimed on N+1")
	local gold = p.Gold
	local _, code = Quests.Claim(p, "D1", N) -- clock now says day N
	expectEq(code, "AlreadyClaimed", "still claimed")
	expectEq(find(Quests.View(p, N), "D1").Claimed, true, "view agrees")
	expectEq(Quests.View(p, N).DailyResetAt, 20002 * DAY, "reset uses effective day")
	Quests.SettleRun(p, 2, 1, 30, N) -- backwards clock must not roll back
	expectEq(p.Daily.Day, 20001, "day did not go back")
	expectEq(p.Daily.Kills, 180, "kills join the stored day")
	local _, code2 = Quests.Claim(p, "D1", N)
	expectEq(code2, "AlreadyClaimed", "still claimed after another run")
	expectEq(p.Gold, gold + 5, "only the run reward arrived")
end)

-- Moved from economy.spec with Economy.GrantRunReward.
test("SettleRun pays Gold 5, Xp 10, Fragments 1 and Gems 10-30 a wave (no win bonus), once per run id", function()
	local p = fresh()
	local ok, bundle = Quests.SettleRun(p, 7, 4, 0, N)
	expect(ok and bundle.Gold == 20 and bundle.Xp == 40 and bundle.Materials.Fragment == 4, "4-wave loss")
	expectEq(bundle.Gems, 50, "gems for waves 1-4")
	expect(p.Gold == 20 and p.Xp == 40 and p.Materials.Fragment == 4, "paid onto the profile")
	expectEq(p.Gems, 100, "gems paid onto the profile")
	expect(p.BestWave == 4 and p.RunsPlayed == 1 and p.TrialCleared == false, "stats")
	expectEq(p.LastRewardRunId, 7, "run id recorded")

	local before = snap(p)
	local ok2, code2 = Quests.SettleRun(p, 7, 10, 5, N)
	expect(not ok2 and code2 == "AlreadyGranted", "same run id refused")
	expectEq(snap(p), before, "replay changes nothing")

	local ok3, win = Quests.SettleRun(p, 8, 10, 0, N)
	expect(ok3 and win.Gold == 50 and win.Xp == 100 and win.Materials.Fragment == 10, "10-wave trial clear")
	expect(p.Gold == 70 and p.Xp == 140 and p.Materials.Fragment == 14, "sums")
	expect(p.BestWave == 10 and p.TrialCleared == true, "best wave raised, cleared")

	Quests.SettleRun(p, 9, 1, 0, N)
	expect(p.BestWave == 10 and p.TrialCleared == true, "best wave never lowered, cleared never unset")
end)

test("a wave-0 loss pays nothing but still counts the run and its kills", function()
	local p = fresh()
	local ok, bundle = Quests.SettleRun(p, 3, 0, 12, N)
	expect(ok and next(bundle) == nil, "empty bundle")
	expect(p.Gold == 0 and p.Xp == 0 and p.Gems == 50 and next(p.Materials) == nil, "nothing paid")
	expect(p.RunsPlayed == 1 and p.LastRewardRunId == 3 and p.Daily.Kills == 12, "run counted once")
	local _, code = Quests.SettleRun(p, 3, 0, 12, N)
	expectEq(code, "AlreadyGranted", "still once per run id")
	expectEq(p.Stats.Wins, 0, "a zero-wave run is no win")
end)

test("a win is derived from the server's waves, not the caller", function()
	local p = fresh()
	Quests.SettleRun(p, 1, 9, 0, N)
	expect(p.TrialCleared == false and p.Stats.Wins == 0, "9 waves is no clear")
	Quests.SettleRun(p, 2, 10, 0, N)
	expect(p.TrialCleared == true and p.Stats.Wins == 1, "10 waves clears the trial")
end)

test("SettleRun rejects bad run input and leaves the profile unchanged", function()
	local p = fresh()
	local before = snap(p)
	local cases = {
		{ nil, 1, "BadRun" },
		{ 0, 1, "BadRun" },
		{ 1.5, 1, "BadRun" },
		{ NAN, 1, "BadRun" },
		{ "1", 1, "BadRun" },
		{ 2 ^ 31, 1, "BadRun" },
		{ 1, -1, "BadWaves" },
		{ 1, 1.5, "BadWaves" },
		{ 1, NAN, "BadWaves" },
		{ 1, INF, "BadWaves" },
		{ 1, 1001, "BadWaves" },
	}
	for index, args in cases do
		local ok, code = Quests.SettleRun(p, args[1], args[2], 5, N)
		expect(not ok and code == args[3], "case " .. index .. " -> " .. args[3] .. " (got " .. tostring(code) .. ")")
	end
	expectEq(snap(p), before, "profile unchanged")
end)

test("a full counter refuses the whole run: Overflow, nothing changes, run id not written", function()
	for _, field in { "Gold", "Xp" } do
		local p = fresh()
		p[field] = Economy.MAX
		local before = snap(p)
		local ok, code = Quests.SettleRun(p, 1, 5, 40, N)
		expect(not ok and code == "Overflow", field .. " at MAX: Overflow")
		expectEq(snap(p), before, field .. ": no partial payment, stats or kills")
		expectEq(p.LastRewardRunId, 0, field .. ": run id not written")
	end
	local q = fresh()
	q.Materials.Fragment = Economy.MAX
	local before = snap(q)
	local _, code = Quests.SettleRun(q, 1, 5, 40, N)
	expectEq(code, "Overflow", "fragments at MAX")
	expectEq(snap(q), before, "fragments: unchanged")
end)

local MON = 20003 * DAY -- a Monday 00:00 UTC (day % 7 == 4; 1970-01-05 was a Monday)

-- A refused quest claim leaves the profile deep-equal to before.
local function refuse(p, id, now, code, label)
	local before = snap(p)
	local ok, got = Quests.Claim(p, id, now)
	expect(not ok and got == code, label .. ": " .. code .. " (got " .. tostring(got) .. ")")
	expectEq(snap(p), before, label .. ": unchanged")
end

test("quest claims pay their Reward bundle (Gold and Gems) once; rows show Gold, Gems and Section", function()
	local p = fresh()
	p.RunsPlayed, p.BestWave, p.TrialCleared = 1, 5, true
	for _, id in { "S1", "S2", "S3" } do
		local reward = Config.ById[id].Reward
		local gold, gems = p.Gold, p.Gems
		expect(Quests.Claim(p, id, N), id .. " claimed")
		expect(p.Gold == gold + reward.Gold and p.Gems == gems + reward.Gems, id .. " paid Gold and Gems")
		refuse(p, id, N, "AlreadyClaimed", id .. " twice")
	end
	expectEq(p.Gold, 50 + 100 + 250, "story Gold")
	expectEq(p.Gems, 50 + 10 + 20 + 50, "story Gems")
	local view = Quests.View(p, N)
	for _, q in Config.List do
		local r = find(view, q.Id)
		expect(r.Gold == q.Reward.Gold and r.Gems == q.Reward.Gems, q.Id .. " row Gold and Gems")
		local section = if q.Daily then "Daily" elseif q.Weekly then "Weekly" else "Story"
		expectEq(r.Section, section, q.Id .. " section")
		expectEq(r.Daily, q.Daily == true, q.Id .. " Daily flag kept")
	end
	local rich = fresh()
	rich.RunsPlayed = 1
	rich.Gems = Economy.MAX
	refuse(rich, "S1", N, "Overflow", "Gems at the cap refuse the Gold too")
end)

test("Week starts Monday 00:00 UTC", function()
	expectEq(Quests.Week(4 * DAY), 1, "1970-01-05 starts week 1")
	expectEq(Quests.Week(4 * DAY - 1), 0, "the Sunday before is week 0")
	expectEq(Quests.Week(MON) - Quests.Week(MON - 1), 1, "Sunday -> Monday")
	expectEq(Quests.Week(MON + 7 * DAY - 1), Quests.Week(MON), "same week through Sunday")
	expectEq(Quests.View(fresh(), MON + 3 * DAY).WeeklyResetAt, MON + 7 * DAY, "reset at next Monday")
end)

test("weekly quests: progress only from settled runs, claim once, roll at the next Monday", function()
	local p = fresh()
	expectEq(find(Quests.View(p, MON), "W1").Progress, 0, "nothing yet")
	for run = 1, 9 do
		Quests.SettleRun(p, run, 1, 100, MON + run)
	end
	expectEq(find(Quests.View(p, MON + 50), "W1").Progress, 900, "W1 kills this week")
	expectEq(find(Quests.View(p, MON + 50), "W2").Progress, 9, "W2 runs this week")
	refuse(p, "W1", MON + 50, "NotComplete", "W1 at 900")
	refuse(p, "W2", MON + 50, "NotComplete", "W2 at 9")
	Quests.SettleRun(p, 10, 0, 100, MON + 10) -- a wave-0 loss still counts as a run
	local gold, gems = p.Gold, p.Gems
	expect(Quests.Claim(p, "W1", MON + 60), "W1 claimed")
	expect(Quests.Claim(p, "W2", MON + 60), "W2 claimed")
	expectEq(p.Gold, gold + 200 + 300, "weekly Gold")
	expectEq(p.Gems, gems + 30 + 30, "weekly Gems")
	expect(p.Weekly.Claimed.W1 and p.Weekly.Claimed.W2, "weekly flags")
	expect(p.Claimed.W1 == nil and p.Daily.Claimed.W1 == nil, "flags only in Weekly")
	refuse(p, "W1", MON + 70, "AlreadyClaimed", "W1 twice")
	expect(find(Quests.View(p, MON + 70), "W1").Claimed, "view shows claimed")

	local nextMon = MON + 7 * DAY
	local r = find(Quests.View(p, nextMon), "W1")
	expect(r.Progress == 0 and r.Claimed == false, "a new week starts empty in the view")
	refuse(p, "W1", nextMon, "NotComplete", "not rolled by Claim")
	expectEq(p.Weekly.Week, Quests.Week(MON), "View and Claim never roll")
	Quests.SettleRun(p, 11, 1, 5, nextMon - 1) -- Sunday 23:59:59
	expect(p.Weekly.Week == Quests.Week(MON) and p.Weekly.Kills == 1005, "Sunday joins the old week")
	Quests.SettleRun(p, 12, 1, 7, nextMon)
	expect(p.Weekly.Week == Quests.Week(nextMon) and p.Weekly.Kills == 7 and p.Weekly.Runs == 1, "rolled")
	expect(next(p.Weekly.Claimed) == nil, "claims reset")
end)

test("weekly: a clock going backwards never reopens a claimed week", function()
	local p = fresh()
	p.Weekly = { Week = Quests.Week(MON), Kills = 1000, Runs = 0, Claimed = {} }
	expect(Quests.Claim(p, "W1", MON), "claimed on Monday")
	refuse(p, "W1", MON - 1, "AlreadyClaimed", "clock back to Sunday")
	refuse(p, "W1", MON - 30 * DAY, "AlreadyClaimed", "clock a month back")
	expectEq(find(Quests.View(p, MON - 1), "W1").Claimed, true, "view agrees")
	expectEq(Quests.View(p, MON - 1).WeeklyResetAt, MON + 7 * DAY, "reset uses the effective week")
	Quests.SettleRun(p, 1, 1, 7, MON - 3 * DAY)
	expect(p.Weekly.Week == Quests.Week(MON) and p.Weekly.Kills == 1007, "the week did not go back")
	local q = fresh()
	q.Weekly = { Week = Quests.Week(MON) + 500, Kills = 5000, Runs = 50, Claimed = { W1 = true } }
	refuse(q, "W1", MON, "AlreadyClaimed", "far-future week stays claimed")
end)

test("SettleRun counts Stats.Kills and Stats.Wins once per run id", function()
	local p = fresh()
	Quests.SettleRun(p, 1, 10, 120, N)
	Quests.SettleRun(p, 2, 3, 30, N)
	expect(p.Stats.Kills == 150 and p.Stats.Wins == 1, "kills and wins")
	local before = snap(p)
	Quests.SettleRun(p, 2, 3, 30, N)
	expectEq(snap(p), before, "a replay counts nothing")
	local q = fresh()
	q.Gold = Economy.MAX
	local qBefore = snap(q)
	Quests.SettleRun(q, 1, 10, 120, N, { "C01" })
	expectEq(snap(q), qBefore, "a refused settle counts no stats, weekly or mastery")
end)

test("SettleRun adds Mastery Xp = waves to owned deck dice only, once per run id", function()
	local p = fresh()
	local deck = { "C01", "C02", "R01", "C01", "Z99" } -- R01 unowned, C01 twice, Z99 unknown
	expect(Quests.SettleRun(p, 1, 6, 0, N, deck), "settled")
	expectEq(p.Mastery.C01.Xp, 6, "owned deck die: once, even if listed twice")
	expectEq(p.Mastery.C02.Xp, 6, "second deck die")
	expect(p.Mastery.R01 == nil and p.Mastery.Z99 == nil, "unowned and unknown dice gain nothing")
	expectEq(p.Mastery.C03, nil, "dice outside the deck gain nothing")
	local before = snap(p)
	local ok, code = Quests.SettleRun(p, 1, 6, 0, N, deck)
	expect(not ok and code == "AlreadyGranted", "replay refused")
	expectEq(snap(p), before, "no Xp on a replay")
	Quests.SettleRun(p, 2, 4, 0, N, deck)
	expectEq(p.Mastery.C01.Xp, 10, "accumulates")
	expect(next(p.Mastery.C01.Claimed) == nil, "settle never claims")
	Quests.SettleRun(p, 3, 0, 0, N, { "C03" })
	expectEq(p.Mastery.C03, nil, "a wave-0 run adds nothing")
	expect(Quests.SettleRun(fresh(), 1, 2, 0, N), "no deck is fine")
end)
