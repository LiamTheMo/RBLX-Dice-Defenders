-- Catalog.Build: the client-visible projection of the server catalogues. Arrays
-- only, sorted by Id, equal to config, never a redeem code.

local Server = game:GetService("ServerScriptService").Server
local Catalog = require(Server.Rules.Catalog)
local Dice = require(Server.Config.Dice)
local Inventory = require(Server.Config.Inventory)
local Codes = require(Server.Config.Codes)
local Rewards = require(Server.Rules.Rewards)
local Balance = require(Server.Config.Balance)
local DailyConfig = require(Server.Config.Daily)
local MilestoneConfig = require(Server.Config.Milestones)
local AchievementConfig = require(Server.Config.Achievements)
local Progression = require(Server.Config.Progression)

-- Deterministic text form; errors on a sparse or mixed table (it would not survive a remote).
local function dump(v)
	if type(v) ~= "table" then
		return tostring(v)
	end
	local keys, n = {}, 0
	for k in v do
		n += 1
		table.insert(keys, k)
	end
	if #v > 0 then
		assert(#v == n, "sparse or mixed table")
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in keys do
		table.insert(parts, tostring(k) .. "=" .. dump(v[k]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function sortedIds(list)
	for i = 2, #list do
		if not (list[i - 1].Id < list[i].Id) then
			return false
		end
	end
	return true
end

local function count(map)
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

test("every die appears once with config Name, Rarity, Damage and Rate; sorted by Id", function()
	local c = Catalog.Build()
	expectEq(#c.Dice, count(Dice.Types), "one row per die type")
	expect(sortedIds(c.Dice), "sorted, so ids are unique")
	for _, row in c.Dice do
		local t = Dice.Types[row.Id]
		expect(t ~= nil, "known die " .. tostring(row.Id))
		expect(row.Name == t.name and row.Rarity == t.rarity, row.Id .. " name and rarity")
		expect(row.Damage == t.base and row.Rate == t.rate, row.Id .. " damage and rate")
	end
end)

test("StarterDeck equals Config/Dice.Deck", function()
	local deck = Catalog.Build().StarterDeck
	expectEq(#deck, #Dice.Deck, "length")
	for i, id in Dice.Deck do
		expectEq(deck[i], id, "slot " .. i)
	end
end)

test("every Inventory entry appears once with equal display fields", function()
	local c = Catalog.Build()
	for _, kind in { "Materials", "Items", "Cosmetics" } do
		local rows = c[kind]
		expectEq(#rows, count(Inventory[kind]), kind .. " count")
		expect(sortedIds(rows), kind .. " sorted by Id")
		for _, row in rows do
			local entry = Inventory[kind][row.Id]
			expect(entry ~= nil, kind .. " known id " .. tostring(row.Id))
			for _, field in { "Name", "Rarity", "Description", "Sell", "Icon", "Type", "Slot" } do
				expectEq(row[field], entry[field], kind .. " " .. row.Id .. " " .. field)
			end
		end
	end
	local use = {}
	for _, row in c.Items do
		use[row.Id] = row.Use
	end
	expectEq(use.XpTome, "+100 XP", "XpTome use text")
	expectEq(use.GoldPouch, "+200 Gold", "GoldPouch use text")
end)

test("arrays only, no sparse keys, no functions, nothing shared with config", function()
	local c = Catalog.Build()
	local text = dump(c) -- asserts every table is a plain array or a plain record
	expect(not string.find(text, "function", 1, true), "no functions")
	for _, row in c.Items do
		expect(row.Use == nil or type(row.Use) == "string", "Use is display text")
	end
	expect(c.StarterDeck ~= Dice.Deck, "own copy of the deck")
	expectEq(dump(Catalog.Build()), text, "deterministic")
end)

test("no redeem code or code id appears anywhere in the Catalog", function()
	local text = dump(Catalog.Build())
	for _, entry in Codes.List do
		expect(not string.find(text, entry.Code, 1, true), "code text leaked: " .. entry.Code)
		expect(not string.find(text, entry.Id, 1, true), "code id leaked: " .. entry.Id)
	end
	local source = __sources["ServerScriptService/Server/Rules/Catalog"]
	expect(source ~= nil and not string.find(source, "Codes", 1, true), "Catalog never requires Config/Codes")
end)

test("Rewards.Lines: one {Kind, Id?, Amount} per part in a fixed order", function()
	local lines = Rewards.Lines({
		Gems = 5,
		Gold = 10,
		Xp = 3,
		Materials = { Fragment = 2 },
		Items = { XpTome = 1, GoldPouch = 2 },
		Dice = { C01 = 1 },
		Cosmetics = { SproutCap = true },
	})
	local want = {
		{ Kind = "Gold", Amount = 10 },
		{ Kind = "Gems", Amount = 5 },
		{ Kind = "Xp", Amount = 3 },
		{ Kind = "Material", Id = "Fragment", Amount = 2 },
		{ Kind = "Item", Id = "GoldPouch", Amount = 2 },
		{ Kind = "Item", Id = "XpTome", Amount = 1 },
		{ Kind = "Die", Id = "C01", Amount = 1 },
		{ Kind = "Cosmetic", Id = "SproutCap", Amount = 1 },
	}
	expectEq(dump(lines), dump(want), "lines")
	expectEq(#Rewards.Lines({}), 0, "empty bundle")
end)

test("Daily, Milestones, Achievements, Mastery and Repeat equal config", function()
	local c = Catalog.Build()
	expectEq(#c.Daily.Days, #DailyConfig.Days, "calendar days")
	for i, day in c.Daily.Days do
		local cfg = DailyConfig.Days[i]
		expect(day.Day == i and day.Chest == cfg.Chest, "day " .. i)
		expectEq(dump(day.Rewards), dump(Rewards.Lines(cfg.Reward)), "day " .. i .. " rewards")
	end
	expectEq(c.Daily.Days[7].Chest, true, "day 7 chest")
	expectEq(#c.Milestones, #MilestoneConfig.List, "milestones")
	for i, m in c.Milestones do
		local cfg = MilestoneConfig.List[i]
		expect(m.Id == cfg.Id and m.Wave == cfg.Wave and m.Reachable == cfg.Reachable, "milestone " .. cfg.Id)
		expectEq(m.Reachable, m.Wave <= Balance.Waves, cfg.Id .. " reachable")
		expectEq(dump(m.Rewards), dump(Rewards.Lines(cfg.Reward)), cfg.Id .. " rewards")
	end
	expectEq(#c.Achievements, #AchievementConfig.List, "achievements")
	for i, a in c.Achievements do
		local cfg = AchievementConfig.List[i]
		for _, field in { "Id", "Name", "Desc", "Goal", "Badge" } do
			expectEq(a[field], cfg[field], cfg.Id .. " " .. field)
		end
		expectEq(a.Stat, nil, cfg.Id .. " no server-side stat key")
		expectEq(dump(a.Rewards), dump(Rewards.Lines(cfg.Reward)), cfg.Id .. " rewards")
	end
	local curve = Progression.Mastery
	expectEq(c.Mastery.Max, curve.Max, "mastery max")
	expectEq(#c.Mastery.Need, curve.Max - 1, "one need per level below max")
	for level, need in c.Mastery.Need do
		expectEq(need, curve.Need(level), "need " .. level)
	end
	expectEq(#c.Mastery.Milestones, #curve.Milestones, "mastery milestones")
	for i, m in c.Mastery.Milestones do
		expectEq(m.Lv, curve.Milestones[i], "milestone level " .. i)
		expectEq(dump(m.Rewards), dump(Rewards.Lines(curve.Rewards[m.Lv])), "Lv" .. m.Lv .. " rewards")
	end
	local r = Balance.Reward
	local perWave = { Gold = r.goldPerWave, Xp = r.xpPerWave, Materials = { Fragment = r.fragmentsPerWave } }
	local win = { Gold = r.goldWin, Xp = r.xpWin, Materials = { Fragment = r.fragmentsWin } }
	expectEq(dump(c.Repeat.PerWave), dump(Rewards.Lines(perWave)), "repeat per wave")
	expectEq(dump(c.Repeat.Win), dump(Rewards.Lines(win)), "repeat win bonus")
end)

test("every achievement Badge is a sprite the Quest Log already has", function()
	local sprites = __sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/QuestLog/QuestSprites"]
	expect(sprites ~= nil, "QuestSprites scanned")
	for _, a in Catalog.Build().Achievements do
		expect(string.find(sprites, "\n\t" .. a.Badge .. " = {", 1, true) ~= nil, a.Id .. " badge " .. a.Badge)
	end
end)
