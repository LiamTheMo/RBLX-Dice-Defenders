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
	local ok, bundle = Quests.SettleRun(p, 7, 3, false, 40, N)
	expect(ok and bundle.Gold == 15 and bundle.Xp == 30 and bundle.Materials.Fragment == 3, "paid 3 waves of a loss")
	expectEq(p.Daily.Kills, 40, "kills added")
	expectEq(p.Daily.Day, 20000, "day set")
	expectEq(p.RunsPlayed, 1, "run counted")
	local before = snap(p)
	local ok2, code = Quests.SettleRun(p, 7, 3, false, 40, N)
	expect(not ok2 and code == "AlreadyGranted", "replay refused")
	expectEq(snap(p), before, "replay changes nothing, kills not doubled")
	expect(Quests.SettleRun(p, 8, 1, false, 10, N + 1), "second run")
	expectEq(p.Daily.Kills, 50, "accumulates within a day")
end)

test("SettleRun rejects bad kills and now without touching the profile", function()
	local p = fresh()
	local before = snap(p)
	for _, kills in { -1, 1.5, 0 / 0, math.huge, 1e6 + 1, "5", {} } do
		local ok, code = Quests.SettleRun(p, 1, 1, false, kills, N)
		expect(not ok and code == "BadKills", "bad kills " .. tostring(kills))
	end
	for _, now in { -1, 0 / 0, math.huge, -math.huge, "x", {} } do
		local ok, code = Quests.SettleRun(p, 1, 1, false, 5, now)
		expect(not ok and code == "BadTime", "bad now " .. tostring(now))
	end
	expectEq(snap(p), before, "unchanged")
	expect(Quests.SettleRun(p, 1, 1, false, 1e6, N), "max kills accepted")
	expectEq(p.Daily.Kills, 1e6, "stored")
end)

test("daily quest: rolls to day N+1; yesterday's unclaimed daily is not claimable", function()
	local p = fresh()
	Quests.SettleRun(p, 1, 1, false, 150, N)
	expectEq(find(Quests.View(p, N), "D1").Progress, 150, "complete on day N")
	expectEq(find(Quests.View(p, N + DAY), "D1").Progress, 0, "new day empty in view")
	local before = snap(p)
	local ok, code = Quests.Claim(p, "D1", N + DAY)
	expect(not ok and code == "NotComplete", "yesterday's daily is gone")
	expectEq(snap(p), before, "Claim and View never rolled the day")
	expectEq(p.Daily.Day, 20000, "still day N")
	Quests.SettleRun(p, 2, 1, false, 20, N + DAY)
	expectEq(p.Daily.Day, 20001, "rolled by a run")
	expectEq(p.Daily.Kills, 20, "fresh count")
	expect(next(p.Daily.Claimed) == nil, "claims reset")

	local q = fresh()
	Quests.SettleRun(q, 1, 1, false, 150, N)
	expect(Quests.Claim(q, "D1", N + 100), "claim today")
	expectEq(q.Gold, 5 + 100, "run reward + quest gold")
	local _, again = Quests.Claim(q, "D1", N + 200)
	expectEq(again, "AlreadyClaimed", "once per day")
end)

test("a clock going backwards never reopens a claimed day", function()
	local p = fresh()
	Quests.SettleRun(p, 1, 1, false, 150, N + DAY) -- day N+1
	expect(Quests.Claim(p, "D1", N + DAY), "claimed on N+1")
	local gold = p.Gold
	local _, code = Quests.Claim(p, "D1", N) -- clock now says day N
	expectEq(code, "AlreadyClaimed", "still claimed")
	expectEq(find(Quests.View(p, N), "D1").Claimed, true, "view agrees")
	expectEq(Quests.View(p, N).DailyResetAt, 20002 * DAY, "reset uses effective day")
	Quests.SettleRun(p, 2, 1, false, 30, N) -- backwards clock must not roll back
	expectEq(p.Daily.Day, 20001, "day did not go back")
	expectEq(p.Daily.Kills, 180, "kills join the stored day")
	local _, code2 = Quests.Claim(p, "D1", N)
	expectEq(code2, "AlreadyClaimed", "still claimed after another run")
	expectEq(p.Gold, gold + 5, "only the run reward arrived")
end)

-- Moved from economy.spec with Economy.GrantRunReward.
test("SettleRun pays Gold 5/wave +30, Xp 10/wave +40, Fragments 1/wave +5 on a win, once per run id", function()
	local p = fresh()
	local ok, bundle = Quests.SettleRun(p, 7, 4, false, 0, N)
	expect(ok and bundle.Gold == 20 and bundle.Xp == 40 and bundle.Materials.Fragment == 4, "4-wave loss")
	expect(p.Gold == 20 and p.Xp == 40 and p.Materials.Fragment == 4, "paid onto the profile")
	expectEq(p.Gems, 50, "gems untouched")
	expect(p.BestWave == 4 and p.RunsPlayed == 1 and p.TrialCleared == false, "stats")
	expectEq(p.LastRewardRunId, 7, "run id recorded")

	local before = snap(p)
	local ok2, code2 = Quests.SettleRun(p, 7, 10, true, 5, N)
	expect(not ok2 and code2 == "AlreadyGranted", "same run id refused")
	expectEq(snap(p), before, "replay changes nothing")

	local ok3, win = Quests.SettleRun(p, 8, 10, true, 0, N)
	expect(ok3 and win.Gold == 80 and win.Xp == 140 and win.Materials.Fragment == 15, "10-wave win")
	expect(p.Gold == 100 and p.Xp == 180 and p.Materials.Fragment == 19, "sums")
	expect(p.BestWave == 10 and p.TrialCleared == true, "best wave raised, cleared")

	Quests.SettleRun(p, 9, 1, false, 0, N)
	expect(p.BestWave == 10 and p.TrialCleared == true, "best wave never lowered, cleared never unset")
end)

test("a wave-0 loss pays nothing but still counts the run and its kills", function()
	local p = fresh()
	local ok, bundle = Quests.SettleRun(p, 3, 0, false, 12, N)
	expect(ok and next(bundle) == nil, "empty bundle")
	expect(p.Gold == 0 and p.Xp == 0 and p.Gems == 50 and next(p.Materials) == nil, "nothing paid")
	expect(p.RunsPlayed == 1 and p.LastRewardRunId == 3 and p.Daily.Kills == 12, "run counted once")
	local _, code = Quests.SettleRun(p, 3, 0, false, 12, N)
	expectEq(code, "AlreadyGranted", "still once per run id")
	local _, zeroWin = Quests.SettleRun(p, 4, 0, true, 0, N)
	expect(zeroWin.Gold == 30 and zeroWin.Xp == 40 and zeroWin.Materials.Fragment == 5, "a win pays its bonus")
end)

test("SettleRun rejects bad run input and leaves the profile unchanged", function()
	local p = fresh()
	local before = snap(p)
	local cases = {
		{ nil, 1, false, "BadRun" },
		{ 0, 1, false, "BadRun" },
		{ 1.5, 1, false, "BadRun" },
		{ NAN, 1, false, "BadRun" },
		{ "1", 1, false, "BadRun" },
		{ 2 ^ 31, 1, false, "BadRun" },
		{ 1, -1, false, "BadWaves" },
		{ 1, 1.5, false, "BadWaves" },
		{ 1, NAN, false, "BadWaves" },
		{ 1, INF, false, "BadWaves" },
		{ 1, 1001, false, "BadWaves" },
		{ 1, 1, "yes", "BadResult" },
		{ 1, 1, nil, "BadResult" },
	}
	for index, args in cases do
		local ok, code = Quests.SettleRun(p, args[1], args[2], args[3], 5, N)
		expect(not ok and code == args[4], "case " .. index .. " -> " .. args[4] .. " (got " .. tostring(code) .. ")")
	end
	expectEq(snap(p), before, "profile unchanged")
end)

test("a full counter refuses the whole run: Overflow, nothing changes, run id not written", function()
	for _, field in { "Gold", "Xp" } do
		local p = fresh()
		p[field] = Economy.MAX
		local before = snap(p)
		local ok, code = Quests.SettleRun(p, 1, 5, true, 40, N)
		expect(not ok and code == "Overflow", field .. " at MAX: Overflow")
		expectEq(snap(p), before, field .. ": no partial payment, stats or kills")
		expectEq(p.LastRewardRunId, 0, field .. ": run id not written")
	end
	local q = fresh()
	q.Materials.Fragment = Economy.MAX
	local before = snap(q)
	local _, code = Quests.SettleRun(q, 1, 5, true, 40, N)
	expectEq(code, "Overflow", "fragments at MAX")
	expectEq(snap(q), before, "fragments: unchanged")
end)
