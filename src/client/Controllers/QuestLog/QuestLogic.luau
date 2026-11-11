-- Quest Log pure logic: row building, filtering, sorting, text formatting. No Roblox APIs (unit-tested headless).

local QuestLogic = {}

local DAY, HOUR, MIN = 86400, 3600, 60
local REAL_ICONS = { D1 = "IconDie", S1 = "IconQuestScroll", S2 = "IconWings", S3 = "IconCrown" }
local SECTION_ORDER = { "Daily", "Weekly", "Story" }

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

function QuestLogic.progressText(progress: number, goal: number, unit: string?): string
	local prefix = if unit then unit .. " " else ""
	return prefix .. QuestLogic.format(progress) .. " / " .. QuestLogic.format(goal)
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

-- Next Monday 00:00 UTC strictly after `now` (epoch day 0 was a Thursday). Sample timer only.
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
		return if row.Sample then "Soon" else "Claim"
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
		Section = if q.Daily then "Daily" else "Story",
		Claimed = q.Claimed == true,
		Sample = false,
	}
end

-- Real quests (server meta, may be nil/malformed) then sample rows, grouped Daily, Weekly, Story.
function QuestLogic.questRows(quests, sample)
	local buckets = { Daily = {}, Weekly = {}, Story = {} }
	local function add(row)
		if row and buckets[row.Section] then
			table.insert(buckets[row.Section], row)
		end
	end
	if type(quests) == "table" then
		for _, q in quests do
			add(realRow(q))
		end
	end
	if type(sample) == "table" then
		for _, row in sample do
			add(row)
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

-- Complete first, then in progress, locked last.
local function achGroup(a): number
	if a.Locked then
		return 3
	end
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
		if not a.Locked and achPercent(a) >= 1 then
			done += 1
		end
	end
	return done, #items
end

-- {Lv, Icon, Name, State = Done | Next | Locked}
function QuestLogic.masteryMilestones(row)
	local out, nextFound = {}, false
	for _, m in row.Milestones or {} do
		local state = "Locked"
		if row.Level >= m.Lv then
			state = "Done"
		elseif not nextFound then
			state, nextFound = "Next", true
		end
		table.insert(out, { Lv = m.Lv, Icon = m.Icon, Name = m.Name, State = state })
	end
	return out
end

-- The first two milestones not yet reached.
function QuestLogic.nextRewards(row)
	local out = {}
	for _, m in QuestLogic.masteryMilestones(row) do
		if m.State ~= "Done" and #out < 2 then
			table.insert(out, m)
		end
	end
	return out
end

return QuestLogic
