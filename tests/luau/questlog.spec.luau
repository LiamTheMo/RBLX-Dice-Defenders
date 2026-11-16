-- Quest Log logic: formatting, reset timers, row building from Meta + Catalog, filters, stable sorts, milestones, claims.

local QL = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.QuestLog
local QuestLogic = require(QL.QuestLogic)
local Sprites = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Sprites)
local Display = require(game:GetService("ReplicatedStorage").Shared.Display)
local CATALOG = require(game:GetService("ServerScriptService").Server.Rules.Catalog).Build()

local function ids(list)
	local out = {}
	for i, it in list do
		out[i] = it.Id
	end
	return table.concat(out, ",")
end

-- QuestSprites needs Rect/Vector2 (not stubbed headless): check a key exists by scanning its source, as catalog.spec does.
local SPRITES_SRC = __sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/QuestLog/QuestSprites"]
local function isSprite(key: string): boolean
	return string.find(SPRITES_SRC, "\n\t" .. key .. " = {", 1, true) ~= nil
end

local function states(row)
	local out = {}
	for i, m in row.Milestones do
		out[i] = m.State
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

test("weeklyResetAt: next Monday 00:00 UTC (Roll's sample rotation)", function()
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
	expectEq(QuestLogic.claimState({ Goal = 5, Progress = 7 }), "Claim", "over goal")
	expectEq(QuestLogic.claimState({ Goal = 5, Progress = 2 }), "Progress", "progress")
	expectEq(QuestLogic.claimState({ Goal = 0, Progress = 0 }), "Progress", "goal 0 never claimable")
end)

-- Meta.Quests shape (Rules/Quests.View).
local REAL = {
	{
		Id = "S1",
		Name = "First Steps",
		Desc = "Win a wave",
		Goal = 1,
		Progress = 1,
		Gold = 50,
		Gems = 10,
		Section = "Story",
	},
	{
		Id = "D1",
		Name = "Pest Control",
		Desc = "Kill 50%",
		Goal = 50,
		Progress = 10,
		Gold = 100,
		Gems = 10,
		Section = "Daily",
	},
	{
		Id = "S3",
		Name = "Verdant Victor",
		Desc = "Win",
		Goal = 1,
		Progress = 0,
		Gold = 250,
		Gems = 0,
		Claimed = true,
		Section = "Story",
	},
	{
		Id = "W1",
		Name = "Weed Out",
		Desc = "Defeat 1000 enemies",
		Goal = 1000,
		Progress = 1000,
		Gold = 200,
		Gems = 30,
		Section = "Weekly",
	},
	{
		Id = "W2",
		Name = "Regular",
		Desc = "Finish 10 runs",
		Goal = 10,
		Progress = 3,
		Gold = 300,
		Gems = 30,
		Section = "Weekly",
	},
	{ Id = "X9", Name = "Mystery", Goal = 2, Progress = 0, Section = "Story" },
}

test("questRows: sections from Meta, order, icons, gems", function()
	local rows = QuestLogic.questRows(REAL)
	expectEq(ids(rows), "D1,W1,W2,S1,S3,X9", "Daily, Weekly, Story; config order inside")
	expectEq(rows[1].Icon, "IconDie", "D1 icon")
	expectEq(rows[2].Section, "Weekly", "weekly from Section")
	expectEq(rows[2].Icon, "IconGalaxyDie", "W1 icon")
	expectEq(rows[3].Icon, "IconChest", "W2 icon")
	expectEq(rows[2].Gems, 30, "real gems carried")
	expectEq(rows[4].Gold, 50, "gold carried")
	expectEq(rows[5].Gems, nil, "0 gems hides the box")
	expectEq(rows[5].Claimed, true, "claimed carried")
	expectEq(rows[6].Icon, "IconQuestScroll", "unknown id icon")
	expectEq(rows[6].Desc, "", "missing desc")
	expectEq(rows[6].Gold, 0, "missing gold")
	for _, row in rows do
		expect(isSprite(row.Icon), "icon sprite exists " .. row.Id)
	end
end)

test("questRows: nil and malformed meta", function()
	expectEq(#QuestLogic.questRows(nil), 0, "nil")
	expectEq(#QuestLogic.questRows("bad"), 0, "wrong type")
	local rows = QuestLogic.questRows({
		7,
		{},
		{ Id = "A", Name = "n" },
		{ Id = 1, Name = "n", Goal = 1, Progress = 0, Section = "Story" },
		{ Id = "B", Name = "n", Goal = 1, Progress = 0 }, -- no Section
		{ Id = "C", Name = "n", Goal = 1, Progress = 0, Section = "Bogus" },
	})
	expectEq(#rows, 0, "malformed skipped")
end)

test("filterQuests: modes and query", function()
	local rows = QuestLogic.questRows(REAL)
	expectEq(#QuestLogic.filterQuests(rows, "", "All"), 6, "all")
	expectEq(#QuestLogic.filterQuests(rows, nil, nil), 6, "nil mode is all")
	expectEq(#QuestLogic.filterQuests(rows, "", "Daily"), 1, "daily")
	expectEq(#QuestLogic.filterQuests(rows, "", "Weekly"), 2, "weekly")
	expectEq(#QuestLogic.filterQuests(rows, "", "Story"), 3, "story")
	expectEq(ids(QuestLogic.filterQuests(rows, "", "Claimable")), "W1,S1", "claimable: complete unclaimed only")
	expectEq(ids(QuestLogic.filterQuests(rows, "  PEST ", "All")), "D1", "mixed case + trim, name")
	expectEq(ids(QuestLogic.filterQuests(rows, "10 runs", "All")), "W2", "desc match")
	expectEq(ids(QuestLogic.filterQuests(rows, "%", "All")), "D1", "percent is literal")
	expectEq(#QuestLogic.filterQuests(rows, ".", "All"), 0, "dot is literal")
	expectEq(#QuestLogic.filterQuests(rows, "zzz", "All"), 0, "none")
	expectEq(#QuestLogic.filterQuests(rows, "regular", "Weekly"), 1, "query within mode")
end)

test("rewardIcon: HUD currencies and existing sprites only", function()
	expectEq(QuestLogic.rewardIcon({ Kind = "Gold", Amount = 1 }), Sprites.Coin, "gold = HUD coin")
	expectEq(QuestLogic.rewardIcon({ Kind = "Gems", Amount = 1 }), Sprites.Gem, "gems = HUD gem")
	expectEq(QuestLogic.rewardIcon({ Kind = "Xp", Amount = 1 }), "BadgeXp", "xp")
	expectEq(QuestLogic.rewardIcon({ Kind = "Material", Id = "Fragment", Amount = 1 }), "Crystals", "material")
	expectEq(QuestLogic.rewardIcon({ Kind = "Item", Id = "XpTome", Amount = 1 }), "Potion", "item")
	expectEq(QuestLogic.rewardIcon({ Kind = "Die", Id = "C01", Amount = 1 }), "IconDie", "die")
	expectEq(QuestLogic.rewardIcon({ Kind = "Cosmetic", Id = "SproutCap", Amount = 1 }), "CrownPlain", "cosmetic")
	expectEq(QuestLogic.rewardIcon({ Kind = "Bogus", Amount = 1 }), "Crystals", "unknown kind")
	expectEq(QuestLogic.rewardIcon(nil), "Crystals", "no line")
	for _, kind in { "Xp", "Material", "Item", "Die", "Cosmetic", "Bogus" } do
		expect(isSprite(QuestLogic.rewardIcon({ Kind = kind, Amount = 1 })), "existing QuestSprites key for " .. kind)
	end
	expect(not isSprite(Sprites.Coin) and not isSprite(Sprites.Gem), "HUD ids never read as QuestSprites keys")
end)

test("rewardsText: counters, catalogue names, amounts", function()
	expectEq(QuestLogic.rewardsText({ { Kind = "Gems", Amount = 20 } }, CATALOG), "20 Gems", "gems")
	expectEq(QuestLogic.rewardsText({ { Kind = "Gold", Amount = 1000 } }, CATALOG), "1,000 Gold", "gold grouped")
	expectEq(QuestLogic.rewardsText({ { Kind = "Xp", Amount = 100 } }, CATALOG), "100 XP", "xp")
	expectEq(
		QuestLogic.rewardsText(
			{ { Kind = "Gems", Amount = 30 }, { Kind = "Item", Id = "XpTome", Amount = 1 } },
			CATALOG
		),
		"30 Gems + XP Tome",
		"joined, item named from the catalogue"
	)
	expectEq(
		QuestLogic.rewardsText({ { Kind = "Material", Id = "Fragment", Amount = 5 } }, CATALOG),
		"Verdant Fragments x5",
		"amount > 1"
	)
	expectEq(
		QuestLogic.rewardsText({ { Kind = "Cosmetic", Id = "SproutCap", Amount = 1 } }, CATALOG),
		"Sprout Cap",
		"cosmetic"
	)
	expectEq(
		QuestLogic.rewardsText({ { Kind = "Item", Id = "Nope", Amount = 1 } }, nil),
		"Nope",
		"no catalogue: the id"
	)
	expectEq(QuestLogic.rewardsText(nil, CATALOG), "", "no lines")
end)

-- Meta.Achievements shape (Rules/Claims.View), against the real Catalog (A1..A5).
local META_ACH = {
	Achievements = {
		{ Id = "A1", Progress = 1, Claimed = true },
		{ Id = "A2", Progress = 1, Claimed = false },
		{ Id = "A3", Progress = 250, Claimed = false },
		{ Id = "A4", Progress = 2, Claimed = false },
		{ Id = "A5", Progress = 8, Claimed = false },
	},
}

test("achievementRows: Catalog joined with Meta", function()
	local rows = QuestLogic.achievementRows(CATALOG, META_ACH)
	expectEq(ids(rows), "A1,A2,A3,A4,A5", "config order")
	expectEq(rows[1].Name, "Trailblazer", "name from catalog")
	expectEq(rows[1].Claimed, true, "claimed from meta")
	expectEq(rows[3].Progress, 250, "progress from meta")
	expectEq(rows[3].Goal, 1000, "goal from catalog")
	expectEq(rows[2].Badge, "BadgeKing", "badge from catalog")
	expectEq(#rows[2].Rewards, 2, "rewards lines")
	expectEq(rows[2].Rewards[1].Kind, "Gems", "gems first")
	expectEq(QuestLogic.claimState(rows[1]), "Claimed", "A1 claimed")
	expectEq(QuestLogic.claimState(rows[2]), "Claim", "A2 claimable")
	expectEq(QuestLogic.claimState(rows[3]), "Progress", "A3 in progress")
	local done, total = QuestLogic.achievementCount(rows)
	expectEq(done .. "/" .. total, "3/5", "count: complete of all")
end)

test("achievementRows: missing sides and malformed meta", function()
	expectEq(#QuestLogic.achievementRows(nil, META_ACH), 0, "no catalog")
	expectEq(#QuestLogic.achievementRows(CATALOG, nil), 0, "no meta")
	local rows = QuestLogic.achievementRows(CATALOG, {
		Achievements = {
			7,
			{ Id = "A1" },
			{ Id = 2, Progress = 1 },
			{ Id = "A9", Progress = 1 },
			{ Id = "A3", Progress = 0 },
		},
	})
	expectEq(ids(rows), "A3", "only a well-formed, catalogued entry")
end)

local ACH = {
	{ Id = "a", Name = "Echo", Progress = 5, Goal = 10 },
	{ Id = "b", Name = "Alpha", Progress = 1, Goal = 1 },
	{ Id = "c", Name = "Delta", Progress = 9, Goal = 10 },
	{ Id = "d", Name = "Bravo", Progress = 0, Goal = 4 },
	{ Id = "e", Name = "Charlie", Progress = 3, Goal = 3, Claimed = true },
}

test("filterByName", function()
	expectEq(ids(QuestLogic.filterByName(ACH, " ALP ")), "b", "name substring, trimmed, any case")
	expectEq(#QuestLogic.filterByName(ACH, "%"), 0, "literal")
	expectEq(#QuestLogic.filterByName(ACH, ""), 5, "empty keeps all")
end)

test("sortAchievements: default, asc, name, stable, no mutation", function()
	local before = ids(ACH)
	local def = QuestLogic.sortAchievements(ACH, nil)
	expectEq(ids(def), "b,e,c,a,d", "default: complete first (stable), then percent desc")
	expectEq(ids(ACH), before, "input untouched")
	expect(def ~= ACH, "new array")
	expectEq(ids(QuestLogic.sortAchievements(ACH, "ProgressAsc")), "d,a,c,b,e", "asc, ties keep order")
	expectEq(ids(QuestLogic.sortAchievements(ACH, "Name")), "b,d,e,c,a", "name")
	expectEq(ids(QuestLogic.sortAchievements(ACH, "bogus")), ids(def), "unknown key = default")
end)

-- Meta.Mastery shape (Rules/Claims.View): owned dice only, Claimed = claimed milestone levels.
local META_MASTERY = {
	Mastery = {
		{ Id = "C01", Level = 12, Xp = 20, XpGoal = 60, Claimed = { 5 } },
		{ Id = "R01", Level = 3, Xp = 4, XpGoal = 15, Claimed = {} },
		{ Id = "E01", Level = 20, Xp = 0, XpGoal = 0, Claimed = { 5, 10, 15, 20 } },
		{ Id = "C02", Level = 15, Xp = 0, XpGoal = 75, Claimed = { 10 } },
	},
}

test("masteryRows: names, die art by the Bag rule, milestones", function()
	local rows = QuestLogic.masteryRows(CATALOG, META_MASTERY)
	expectEq(ids(rows), "C01,R01,E01,C02", "meta order")
	expectEq(rows[1].Name, "Pebble", "catalog name")
	expectEq(rows[1].Level .. ":" .. rows[1].Xp .. "/" .. rows[1].XpGoal, "12:20/60", "level and xp")
	expectEq(rows[1].Art, Sprites.Icon.Roll, "no DieArt: roll glyph")
	expect(rows[1].Tint == Display.Dice.C01.Color, "roll glyph tinted with the Display colour")
	expectEq(rows[2].Art, Sprites.Dice[Sprites.DieArt.R01], "DieArt die: its elemental art")
	expectEq(rows[2].Tint, nil, "elemental art untinted")
	expectEq(#rows[1].Milestones, 4, "Lv 5/10/15/20")
	expectEq(states(rows[1]), "Done,Claimable,Locked,Locked", "lv 12, 5 claimed")
	expectEq(states(rows[2]), "Locked,Locked,Locked,Locked", "lv 3")
	expectEq(states(rows[3]), "Done,Done,Done,Done", "maxed and claimed")
	expectEq(states(rows[4]), "Claimable,Done,Claimable,Locked", "lv 15, only 10 claimed")
	local m = rows[1].Milestones
	expectEq(m[1].Lv .. "," .. m[2].Lv .. "," .. m[3].Lv .. "," .. m[4].Lv, "5,10,15,20", "levels from catalog")
	expectEq(m[2].Name, "30 Gems + XP Tome", "Lv10 label from its catalog lines")
	expectEq(m[3].Name, "50 Gems", "Lv15 label from its catalog line (no dice skin special case)")
	expectEq(m[3].Icon, Sprites.Gem, "Lv15 icon: its first line, the HUD gem")
end)

test("masteryRows: missing sides and malformed meta", function()
	expectEq(#QuestLogic.masteryRows(CATALOG, nil), 0, "no meta")
	local rows = QuestLogic.masteryRows(nil, { Mastery = { { Id = "C03", Level = 6 } } })
	expectEq(rows[1].Name, "Hammer", "no catalog: Display name")
	expectEq(#rows[1].Milestones, 0, "no catalog: no milestones")
	expectEq(rows[1].Xp .. "/" .. rows[1].XpGoal, "0/0", "missing xp")
	expectEq(
		#QuestLogic.masteryRows(CATALOG, { Mastery = { 7, { Id = "C01" }, { Level = 3 } } }),
		0,
		"malformed skipped"
	)
	expectEq(QuestLogic.masteryRows(CATALOG, { Mastery = { { Id = "ZZ9", Level = 1 } } })[1].Name, "ZZ9", "unknown id")
end)

test("masteryClaim: lowest claimable, claimed, progress", function()
	local rows = QuestLogic.masteryRows(CATALOG, META_MASTERY)
	local id, state = QuestLogic.masteryClaim(rows[1])
	expectEq(id, "C01:10", "lv 12: the Lv10 milestone")
	expectEq(state, "Claim", "claim")
	id, state = QuestLogic.masteryClaim(rows[4])
	expectEq(id, "C02:5", "the lowest of several")
	id, state = QuestLogic.masteryClaim(rows[2])
	expectEq(tostring(id) .. ":" .. state, "nil:Progress", "nothing reached")
	id, state = QuestLogic.masteryClaim(rows[3])
	expectEq(tostring(id) .. ":" .. state, "nil:Claimed", "all claimed")
	id, state = QuestLogic.masteryClaim({ Id = "X", Milestones = {} })
	expectEq(tostring(id) .. ":" .. state, "nil:Progress", "no milestones")
end)

test("nextRewards: first two not yet claimed", function()
	local rows = QuestLogic.masteryRows(CATALOG, META_MASTERY)
	local nx = QuestLogic.nextRewards(rows[1])
	expectEq(#nx, 2, "two")
	expectEq(nx[1].Lv .. ":" .. nx[1].State .. "," .. nx[2].Lv .. ":" .. nx[2].State, "10:Claimable,15:Locked", "lv 12")
	nx = QuestLogic.nextRewards(rows[4])
	expectEq(nx[1].Lv .. "," .. nx[2].Lv, "5,15", "skips the claimed Lv10")
	expectEq(#QuestLogic.nextRewards(rows[3]), 0, "all claimed")
end)

test("sortMastery: default, asc, name, stable", function()
	local rows = QuestLogic.masteryRows(CATALOG, META_MASTERY)
	expectEq(ids(QuestLogic.sortMastery(rows, nil)), "E01,C02,C01,R01", "level desc")
	expectEq(ids(QuestLogic.sortMastery(rows, "LevelAsc")), "R01,C01,C02,E01", "asc")
	expectEq(QuestLogic.sortMastery(rows, "Name")[1].Name, "Emberstorm", "name")
	local ties = { { Id = "a", Level = 3 }, { Id = "b", Level = 3 }, { Id = "c", Level = 3 } }
	expectEq(ids(QuestLogic.sortMastery(ties, "LevelDesc")), "a,b,c", "stable desc")
	expectEq(ids(QuestLogic.sortMastery(ties, "LevelAsc")), "a,b,c", "stable asc")
	expectEq(ids(ties), "a,b,c", "input untouched")
end)
