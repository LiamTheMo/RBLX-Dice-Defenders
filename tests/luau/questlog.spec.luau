-- Quest Log logic: formatting, reset timers, row building, filters, stable sorts, milestones.

local QL = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.QuestLog
local QuestLogic = require(QL.QuestLogic)
local SampleData = require(QL.SampleData)

local function ids(list)
	local out = {}
	for i, it in list do
		out[i] = it.Id
	end
	return table.concat(out, ",")
end

test("format: grouping and negatives", function()
	expectEq(QuestLogic.format(0), "0", "0")
	expectEq(QuestLogic.format(999), "999", "999")
	expectEq(QuestLogic.format(1000), "1,000", "1000")
	expectEq(QuestLogic.format(1234567), "1,234,567", "1234567")
	expectEq(QuestLogic.format(-2500), "-2,500", "-2500")
	expectEq(QuestLogic.format(-999), "-999", "-999")
end)

test("percent and progressText", function()
	expectEq(QuestLogic.percent(5, 10), 0.5, "half")
	expectEq(QuestLogic.percent(15, 10), 1, "clamp high")
	expectEq(QuestLogic.percent(-3, 10), 0, "clamp low")
	expectEq(QuestLogic.percent(5, 0), 0, "goal 0")
	expectEq(QuestLogic.percent(5, -1), 0, "goal negative")
	expectEq(QuestLogic.progressText(50, 50), "50 / 50", "plain")
	expectEq(QuestLogic.progressText(10, 10, "LVL"), "LVL 10 / 10", "unit")
	expectEq(QuestLogic.progressText(1500, 2500), "1,500 / 2,500", "grouped")
end)

test("resetText boundaries", function()
	expectEq(QuestLogic.resetText(-5), "<1m", "negative")
	expectEq(QuestLogic.resetText(0), "<1m", "0")
	expectEq(QuestLogic.resetText(59), "<1m", "59")
	expectEq(QuestLogic.resetText(60), "1m", "60")
	expectEq(QuestLogic.resetText(3599), "59m", "3599")
	expectEq(QuestLogic.resetText(3600), "1h 0m", "3600")
	expectEq(QuestLogic.resetText(86399), "23h 59m", "86399")
	expectEq(QuestLogic.resetText(86400), "1d 0h", "86400")
	expectEq(QuestLogic.resetText(6 * 86400 + 12 * 3600), "6d 12h", "6d12h")
end)

test("weeklyResetAt: next Monday 00:00 UTC", function()
	local monday = 1767571200 -- 2026-01-05 00:00 UTC, a Monday
	local nextMonday = monday + 7 * 86400
	expectEq(QuestLogic.weeklyResetAt(monday), nextMonday, "monday 00:00 rolls a full week")
	expectEq(QuestLogic.weeklyResetAt(monday - 1), monday, "sunday 23:59:59")
	expectEq(QuestLogic.weeklyResetAt(monday + 3 * 86400 + 5000), nextMonday, "mid-week")
	expectEq(QuestLogic.weeklyResetAt(monday + 6 * 86400 + 23 * 3600 + 59 * 60), nextMonday, "sunday 23:59")
end)

test("claimState", function()
	expectEq(QuestLogic.claimState({ Goal = 5, Progress = 5, Claimed = true }), "Claimed", "claimed")
	expectEq(QuestLogic.claimState({ Goal = 5, Progress = 5 }), "Claim", "claim")
	expectEq(QuestLogic.claimState({ Goal = 5, Progress = 5, Sample = true }), "Soon", "sample complete")
	expectEq(QuestLogic.claimState({ Goal = 5, Progress = 2 }), "Progress", "progress")
	expectEq(QuestLogic.claimState({ Goal = 5, Progress = 2, Sample = true }), "Progress", "sample progress")
end)

local REAL = {
	{ Id = "S1", Name = "First Steps", Desc = "Win a wave", Goal = 1, Progress = 1, Gold = 100, Claimed = false },
	{ Id = "D1", Name = "Pest Control", Desc = "Kill 50%", Goal = 50, Progress = 10, Gold = 200, Daily = true },
	{ Id = "S3", Name = "Verdant Victor", Desc = "Win", Goal = 1, Progress = 0, Gold = 900, Claimed = true },
	{ Id = "X9", Name = "Mystery", Goal = 2, Progress = 0 },
}

test("questRows: order, sections, icons", function()
	local rows = QuestLogic.questRows(REAL, SampleData.Quests)
	expectEq(
		ids(rows),
		"D1,sample_roll,sample_collect,sample_chests,sample_dailies,sample_craft,sample_towers,S1,S3,X9",
		"order"
	)
	expectEq(rows[1].Section, "Daily", "real daily")
	expectEq(rows[1].Icon, "IconDie", "D1 icon")
	expectEq(rows[1].Sample, false, "real not sample")
	expectEq(rows[1].Gems, nil, "real has no gems")
	expectEq(rows[2].Gems, 25, "sample gems")
	expectEq(rows[5].Section, "Weekly", "weekly")
	expectEq(rows[8].Section, "Story", "one-time is story")
	expectEq(rows[8].Icon, "IconQuestScroll", "S1 icon")
	expectEq(rows[9].Claimed, true, "claimed carried")
	expectEq(rows[10].Icon, "IconQuestScroll", "unknown id icon")
	expectEq(rows[10].Desc, "", "missing desc")
end)

test("questRows: nil and malformed meta", function()
	expectEq(#QuestLogic.questRows(nil, nil), 0, "nil")
	expectEq(#QuestLogic.questRows("bad", 5), 0, "wrong types")
	local rows =
		QuestLogic.questRows({ 7, {}, { Id = "A", Name = "n" }, { Id = 1, Name = "n", Goal = 1, Progress = 0 } }, nil)
	expectEq(#rows, 0, "malformed skipped")
	expectEq(#QuestLogic.questRows(nil, SampleData.Quests), 6, "sample only")
end)

test("filterQuests: modes and query", function()
	local rows = QuestLogic.questRows(REAL, SampleData.Quests)
	expectEq(#QuestLogic.filterQuests(rows, "", "All"), 10, "all")
	expectEq(#QuestLogic.filterQuests(rows, nil, nil), 10, "nil mode is all")
	expectEq(#QuestLogic.filterQuests(rows, "", "Daily"), 4, "daily")
	expectEq(#QuestLogic.filterQuests(rows, "", "Weekly"), 3, "weekly")
	expectEq(#QuestLogic.filterQuests(rows, "", "Story"), 3, "story")
	expectEq(ids(QuestLogic.filterQuests(rows, "", "Claimable")), "S1", "claimable: real complete unclaimed only")
	expectEq(ids(QuestLogic.filterQuests(rows, "  PEST ", "All")), "D1", "mixed case + trim, name")
	expectEq(ids(QuestLogic.filterQuests(rows, "craft 5", "All")), "sample_craft", "desc match")
	expectEq(ids(QuestLogic.filterQuests(rows, "%", "All")), "D1", "percent is literal")
	expectEq(#QuestLogic.filterQuests(rows, ".", "All"), 0, "dot is literal")
	expectEq(#QuestLogic.filterQuests(rows, "zzz", "All"), 0, "none")
	expectEq(#QuestLogic.filterQuests(rows, "dice", "Weekly"), 1, "query within mode")
end)

local ACH = SampleData.Achievements

test("sample data shape", function()
	expectEq(#ACH, 15, "achievements")
	expectEq(#SampleData.Mastery, 5, "mastery")
	expectEq(#SampleData.Quests, 6, "quests")
	for _, list in { SampleData.Quests, ACH, SampleData.Mastery } do
		for _, r in list do
			expect(r.Sample == true, "Sample flag " .. r.Id)
		end
	end
end)

test("achievementCount and filterByName", function()
	local done, total = QuestLogic.achievementCount(ACH)
	expectEq(done, 3, "done")
	expectEq(total, 15, "total")
	expectEq(ids(QuestLogic.filterByName(ACH, " dice ")), "sample_king,sample_crafter", "name substring")
	expectEq(#QuestLogic.filterByName(ACH, "%"), 0, "literal")
	expectEq(#QuestLogic.filterByName(ACH, ""), 15, "empty keeps all")
end)

test("sortAchievements: default, asc, name, stable, no mutation", function()
	local before = ids(ACH)
	local def = QuestLogic.sortAchievements(ACH, nil)
	expectEq(
		ids(def),
		"sample_king,sample_royal,sample_material,sample_crafter,sample_hoarder,sample_treasure,sample_tower,sample_xp,sample_battle,sample_rift,"
			.. "sample_galaxy,sample_divine,sample_mythic,sample_kingdom,sample_true",
		"default: complete, percent desc, locked last"
	)
	expectEq(ids(ACH), before, "input untouched")
	expect(def ~= ACH, "new array")
	local asc = QuestLogic.sortAchievements(ACH, "ProgressAsc")
	expectEq(asc[1].Id, "sample_galaxy", "asc starts at lowest, ties keep order")
	expectEq(asc[6].Id, "sample_rift", "asc next")
	local byName = QuestLogic.sortAchievements(ACH, "Name")
	expectEq(byName[1].Id, "sample_battle", "name first")
	expectEq(byName[15].Id, "sample_xp", "name last")
	expectEq(ids(QuestLogic.sortAchievements(ACH, "bogus")), ids(def), "unknown key = default")
end)

test("sortMastery: default, asc, name, stable", function()
	local M = SampleData.Mastery
	expectEq(
		ids(QuestLogic.sortMastery(M, nil)),
		"sample_Fire,sample_Ice,sample_Leaf,sample_Lightning,sample_Sun",
		"level desc"
	)
	expectEq(QuestLogic.sortMastery(M, "LevelAsc")[1].Id, "sample_Sun", "asc")
	expectEq(QuestLogic.sortMastery(M, "Name")[1].Id, "sample_Fire", "name")
	local ties = { { Id = "a", Level = 3 }, { Id = "b", Level = 3 }, { Id = "c", Level = 3 } }
	expectEq(ids(QuestLogic.sortMastery(ties, "LevelDesc")), "a,b,c", "stable desc")
	expectEq(ids(QuestLogic.sortMastery(ties, "LevelAsc")), "a,b,c", "stable asc")
	expectEq(ids(ties), "a,b,c", "input untouched")
end)

test("masteryMilestones and nextRewards", function()
	local fire = SampleData.Mastery[1] -- level 12
	local ms = QuestLogic.masteryMilestones(fire)
	expectEq(#ms, 4, "four")
	expectEq(ms[1].State .. ms[2].State .. ms[3].State .. ms[4].State, "DoneDoneNextLocked", "lv 12")
	expectEq(ms[3].Icon, "SkinFire", "skin icon")
	local nx = QuestLogic.nextRewards(fire)
	expectEq(#nx, 2, "two next")
	expectEq(nx[1].Name .. "," .. nx[2].Name, "Dice Skin,Mastery Crown", "next names")
	local sun = QuestLogic.masteryMilestones(SampleData.Mastery[5]) -- level 7
	expectEq(sun[1].State .. sun[2].State .. sun[3].State, "DoneNextLocked", "lv 7")
	local maxed = { Level = 20, Milestones = SampleData.Mastery[1].Milestones }
	expectEq(#QuestLogic.nextRewards(maxed), 0, "all done")
	expectEq(#QuestLogic.masteryMilestones({ Level = 1 }), 0, "no milestones")
end)
