-- Quest Log pure logic: row building, filtering, sorting, text formatting. No Instances (unit-tested headless).
-- Display only: claim states and targets just enable buttons; the server re-checks every ClaimQuest.

local Display = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Display"))
local Sprites = require(script.Parent.Parent.Sprites)

local QuestLogic = {}

local DAY, HOUR, MIN = 86400, 3600, 60
local REAL_ICONS = {
	D1 = "IconDie",
	S1 = "IconQuestScroll",
	S2 = "IconWings",
	S3 = "IconCrown",
	W1 = "IconGalaxyDie",
	W2 = "IconChest",
}
local SECTION_ORDER = { "Daily", "Weekly", "Story" }
-- Reward line Kind -> icon: a QuestSprites key, or the HUD coin / gem asset id (menus reuse the HUD currency icons).
local REWARD_ICON = {
	Gold = Sprites.Coin,
	Gems = Sprites.Gem,
	Xp = "BadgeXp",
	Material = "Crystals",
	Item = "Potion",
	Die = "IconDie",
	Cosmetic = "CrownPlain",
}
local COUNTER_LABEL = { Gold = "Gold", Gems = "Gems", Xp = "XP" }
local CATALOG_LIST = { Material = "Materials", Item = "Items", Cosmetic = "Cosmetics", Die = "Dice" }

-- 2,500 / -2,500
function QuestLogic.format(n: number): string
	n = math.floor(n)
	local s = tostring(math.abs(n))
	while true do
		local r, k = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2")
		s = r
		if k == 0 then
			break
		end
	end
	return (if n < 0 then "-" else "") .. s
end

function QuestLogic.percent(progress: number, goal: number): number
	if goal <= 0 then
		return 0
	end
	return math.clamp(progress / goal, 0, 1)
end

function QuestLogic.progressText(progress: number, goal: number): string
	return QuestLogic.format(progress) .. " / " .. QuestLogic.format(goal)
end

function QuestLogic.resetText(secondsLeft: number): string
	local s = math.floor(secondsLeft)
	if s >= DAY then
		return string.format("%dd %dh", s // DAY, s % DAY // HOUR)
	elseif s >= HOUR then
		return string.format("%dh %dm", s // HOUR, s % HOUR // MIN)
	elseif s >= MIN then
		return string.format("%dm", s // MIN)
	end
	return "<1m"
end

-- Next Monday 00:00 UTC strictly after `now` (epoch day 0 was a Thursday). The Roll sample rotation timer only.
function QuestLogic.weeklyResetAt(now: number): number
	local day = now // DAY
	return (day + 7 - (day + 3) % 7) * DAY
end

local function complete(row): boolean
	return row.Goal > 0 and row.Progress >= row.Goal
end

function QuestLogic.claimState(row): string
	if row.Claimed then
		return "Claimed"
	elseif complete(row) then
		return "Claim"
	end
	return "Progress"
end

local function realRow(q)
	if type(q) ~= "table" or type(q.Id) ~= "string" or type(q.Name) ~= "string" then
		return nil
	end
	if type(q.Goal) ~= "number" or type(q.Progress) ~= "number" then
		return nil
	end
	return {
		Id = q.Id,
		Name = q.Name,
		Desc = if type(q.Desc) == "string" then q.Desc else "",
		Icon = REAL_ICONS[q.Id] or "IconQuestScroll",
		Goal = q.Goal,
		Progress = q.Progress,
		Gold = if type(q.Gold) == "number" then q.Gold else 0,
		Gems = if type(q.Gems) == "number" and q.Gems > 0 then q.Gems else nil, -- nil hides the gems box
		Section = q.Section,
		Claimed = q.Claimed == true,
	}
end

-- Meta.Quests (may be nil/malformed) grouped Daily, Weekly, Story by their Section.
function QuestLogic.questRows(quests)
	local buckets = { Daily = {}, Weekly = {}, Story = {} }
	if type(quests) == "table" then
		for _, q in quests do
			local row = realRow(q)
			if row and buckets[row.Section] then
				table.insert(buckets[row.Section], row)
			end
		end
	end
	local out = {}
	for _, section in SECTION_ORDER do
		for _, row in buckets[section] do
			table.insert(out, row)
		end
	end
	return out
end

local function trimLower(query: string?): string
	return string.lower(string.match(query or "", "^%s*(.-)%s*$") or "")
end

local function matches(item, q: string): boolean
	return q == ""
		or string.find(string.lower(item.Name or ""), q, 1, true) ~= nil
		or string.find(string.lower(item.Desc or ""), q, 1, true) ~= nil
end

-- mode: All | Daily | Weekly | Story | Claimable
function QuestLogic.filterQuests(rows, query: string?, mode: string?)
	local q = trimLower(query)
	local out = {}
	for _, row in rows do
		local ok
		if mode == "Claimable" then
			ok = QuestLogic.claimState(row) == "Claim"
		else
			ok = mode == nil or mode == "All" or row.Section == mode
		end
		if ok and matches(row, q) then
			table.insert(out, row)
		end
	end
	return out
end

-- Name-only search for achievements / mastery.
function QuestLogic.filterByName(items, query: string?)
	local q = trimLower(query)
	local out = {}
	for _, item in items do
		if q == "" or string.find(string.lower(item.Name or ""), q, 1, true) then
			table.insert(out, item)
		end
	end
	return out
end

-- Stable copy sort: `before(a, b)` is the primary order, original index breaks ties.
local function stableSort(items, before)
	local list = {}
	for i, item in items do
		list[i] = { Item = item, Index = i }
	end
	table.sort(list, function(a, b)
		if before(a.Item, b.Item) then
			return true
		elseif before(b.Item, a.Item) then
			return false
		end
		return a.Index < b.Index
	end)
	local out = {}
	for i, entry in list do
		out[i] = entry.Item
	end
	return out
end

local function achPercent(a): number
	return QuestLogic.percent(a.Progress, a.Goal)
end

-- Complete first, then in progress.
local function achGroup(a): number
	return if achPercent(a) >= 1 then 1 else 2
end

local function nameLess(a, b): boolean
	return string.lower(a.Name or "") < string.lower(b.Name or "")
end

function QuestLogic.sortAchievements(items, key: string?)
	if key == "ProgressAsc" then
		return stableSort(items, function(a, b)
			return achPercent(a) < achPercent(b)
		end)
	elseif key == "Name" then
		return stableSort(items, nameLess)
	end
	return stableSort(items, function(a, b)
		local ga, gb = achGroup(a), achGroup(b)
		if ga ~= gb then
			return ga < gb
		end
		return ga == 2 and achPercent(a) > achPercent(b)
	end)
end

function QuestLogic.sortMastery(rows, key: string?)
	if key == "LevelAsc" then
		return stableSort(rows, function(a, b)
			return a.Level < b.Level
		end)
	elseif key == "Name" then
		return stableSort(rows, nameLess)
	end
	return stableSort(rows, function(a, b)
		return a.Level > b.Level
	end)
end

function QuestLogic.achievementCount(items): (number, number)
	local done = 0
	for _, a in items do
		if achPercent(a) >= 1 then
			done += 1
		end
	end
	return done, #items
end

-- Icon for one Catalog reward line {Kind, Id?, Amount}: a QuestSprites key or a raw asset id (draw with Draw.icon).
function QuestLogic.rewardIcon(line): string
	return REWARD_ICON[line and line.Kind] or "Crystals"
end

-- "30 Gems + XP Tome": Catalog reward lines as text; ids are named from the catalogue lists (" x2" when more than one).
function QuestLogic.rewardsText(lines, catalog): string
	local parts = {}
	for _, line in lines or {} do
		local text = COUNTER_LABEL[line.Kind]
		if text then
			text = QuestLogic.format(line.Amount) .. " " .. text
		else
			text = line.Id or line.Kind
			for _, entry in catalog and catalog[CATALOG_LIST[line.Kind]] or {} do
				if entry.Id == line.Id then
					text = entry.Name
				end
			end
			if line.Amount > 1 then
				text ..= " x" .. QuestLogic.format(line.Amount)
			end
		end
		table.insert(parts, text)
	end
	return table.concat(parts, " + ")
end

-- Catalog.Achievements (config order) joined with Meta.Achievements by Id; one missing from either side is left out.
-- { Id, Name, Desc, Goal, Badge, Rewards, Progress, Claimed }
function QuestLogic.achievementRows(catalog, meta)
	local state = {}
	for _, s in meta and meta.Achievements or {} do
		if type(s) == "table" and type(s.Id) == "string" and type(s.Progress) == "number" then
			state[s.Id] = s
		end
	end
	local out = {}
	for _, a in catalog and catalog.Achievements or {} do
		local s = state[a.Id]
		if s then
			table.insert(out, {
				Id = a.Id,
				Name = a.Name,
				Desc = a.Desc,
				Goal = a.Goal,
				Badge = a.Badge,
				Rewards = a.Rewards or {},
				Progress = s.Progress,
				Claimed = s.Claimed == true,
			})
		end
	end
	return out
end

-- Die art: the elemental Sprites.DieArt image, else the roll glyph tinted with the Display colour (the Bag DICE rule).
local function dieArt(id: string): (string, Color3?)
	local name = Sprites.DieArt[id]
	local art = name and Sprites.Dice[name]
	if art then
		return art, nil
	end
	local info = Display.Dice[id]
	return Sprites.Icon.Roll, info and info.Color
end

-- One row per Meta.Mastery entry (owned dice): { Id, Name, Level, Xp, XpGoal, Art, Tint?, Milestones }, each milestone
-- { Lv, Icon (its first reward line), Name (rewardsText), State = Done (claimed) | Claimable (Level >= Lv) | Locked }.
function QuestLogic.masteryRows(catalog, meta)
	local names = {}
	for _, d in catalog and catalog.Dice or {} do
		names[d.Id] = d.Name
	end
	local milestones = catalog and catalog.Mastery and catalog.Mastery.Milestones or {}
	local out = {}
	for _, m in meta and meta.Mastery or {} do
		if type(m) == "table" and type(m.Id) == "string" and type(m.Level) == "number" then
			local claimed = {}
			for _, lv in m.Claimed or {} do
				claimed[lv] = true
			end
			local list = {}
			for _, ms in milestones do
				table.insert(list, {
					Lv = ms.Lv,
					Icon = QuestLogic.rewardIcon(ms.Rewards[1]),
					Name = QuestLogic.rewardsText(ms.Rewards, catalog),
					State = if claimed[ms.Lv] then "Done" elseif m.Level >= ms.Lv then "Claimable" else "Locked",
				})
			end
			local art, tint = dieArt(m.Id)
			local info = Display.Dice[m.Id]
			table.insert(out, {
				Id = m.Id,
				Name = names[m.Id] or (info and info.Name) or m.Id,
				Level = m.Level,
				Xp = m.Xp or 0,
				XpGoal = m.XpGoal or 0,
				Art = art,
				Tint = tint,
				Milestones = list,
			})
		end
	end
	return out
end

-- The Mastery detail's CLAIM: ("<dieId>:<Lv>" of the lowest Claimable milestone or nil, state Claim | Claimed | Progress).
function QuestLogic.masteryClaim(row): (string?, string)
	local done = 0
	for _, m in row.Milestones do
		if m.State == "Claimable" then
			return row.Id .. ":" .. m.Lv, "Claim"
		elseif m.State == "Done" then
			done += 1
		end
	end
	return nil, if done > 0 and done == #row.Milestones then "Claimed" else "Progress"
end

-- The first two milestones not yet claimed.
function QuestLogic.nextRewards(row)
	local out = {}
	for _, m in row.Milestones do
		if m.State ~= "Done" and #out < 2 then
			table.insert(out, m)
		end
	end
	return out
end

return QuestLogic
