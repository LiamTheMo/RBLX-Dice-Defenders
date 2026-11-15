-- Quest Log controller: one Shell (banner, close, three tabs), the shared Toolbar and Detail, and the Quests list.
-- QuestLog.new(parent, { hud = LobbyHud, toast = (string) -> () (unused) }) -> :Open(tab?) :Close() :Toggle() :IsOpen() :SetTab(n) :Destroy()
-- Rows come from NetClient.LastMeta (quests, achievement progress, mastery) joined with NetClient.LastCatalog (achievement and
-- mastery names, goals and rewards); re-rendered on NetClient.Meta.
-- Claim: a quest row, achievement or mastery milestone the client shows as claimable sends ClaimQuest (one in flight per id);
-- the server re-checks it and the next Meta decides the Claimed state.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local NetClient = require(script.Parent.Parent.NetClient)
local Shell = require(script.Parent.Parent.Bag.Shell)
local Q = require(script.Parent.QuestSprites)
local QuestLogic = require(script.Parent.QuestLogic)
local Toolbar = require(script.Parent.Toolbar)
local Detail = require(script.Parent.Detail)
local Quests = require(script.Parent.Tabs.Quests)
local Achievements = require(script.Parent.Tabs.Achievements)
local Mastery = require(script.Parent.Tabs.Mastery)

local ACTION = "QuestLogClose"
local DAY = 86400

local PLACEHOLDERS = { "Search quests...", "Search achievements...", "Search dice mastery..." }
local OPTIONS = {
	{ Id = "All", Label = "All Quests" },
	{ Id = "Daily", Label = "Daily" },
	{ Id = "Weekly", Label = "Weekly" },
	{ Id = "Story", Label = "Story" },
	{ Id = "Claimable", Label = "Claimable" },
}
local ACH_OPTIONS = {
	{ Id = "ProgressDesc", Label = "Progress (High → Low)" },
	{ Id = "ProgressAsc", Label = "Progress (Low → High)" },
	{ Id = "Name", Label = "Name (A → Z)" },
}
local MASTERY_OPTIONS = {
	{ Id = "LevelDesc", Label = "Level (High → Low)" },
	{ Id = "LevelAsc", Label = "Level (Low → High)" },
	{ Id = "Name", Label = "Name (A → Z)" },
}
local ACTION_LABEL = { Claim = "CLAIM", Claimed = "CLAIMED", Progress = "CLAIM" } -- Progress: a disabled CLAIM

-- Detail models carry ClaimId, the ClaimQuest id their button sends (nil: nothing to claim).
local function questModel(row, busy)
	local state = QuestLogic.claimState(row)
	return {
		Kind = "Quest",
		Title = "QUEST DETAILS",
		Name = row.Name,
		Icon = row.Icon,
		ClaimId = row.Id,
		Body = { Desc = row.Desc, Progress = row.Progress, Goal = row.Goal, Gold = row.Gold, Gems = row.Gems },
		Action = { Label = ACTION_LABEL[state], State = state, Enabled = state == "Claim" and not busy },
	}
end

local function achModel(item, busy)
	local state = QuestLogic.claimState(item)
	return {
		Kind = "Achievement",
		Title = "ACHIEVEMENT",
		Name = item.Name,
		ClaimId = item.Id,
		Body = item,
		Action = { Label = ACTION_LABEL[state], State = state, Enabled = state == "Claim" and not busy },
	}
end

local function masteryModel(row, pending)
	local id, state = QuestLogic.masteryClaim(row)
	return {
		Kind = "Mastery",
		Title = "DICE MASTERY",
		Name = row.Name,
		ClaimId = id,
		Body = row,
		Action = { Label = ACTION_LABEL[state], State = state, Enabled = id ~= nil and not pending[id] },
	}
end

local QuestLog = {}
QuestLog.__index = QuestLog

function QuestLog.new(parent, deps)
	local self = setmetatable({}, QuestLog)
	local hud = deps.hud
	local conns = {}
	local shell = Shell.new(parent, {
		fit = function()
			return hud:GetBagInsets()
		end,
		name = "QuestLog",
		banner = {
			text = "QUEST LOG",
			textW = 0.523,
			emblems = {
				{ sprite = Q.BannerSeal, box = { 0.1085, 0.1111, 0.1382, 0.8148 }, side = true },
				{ sprite = Q.BannerQuill, box = { 0.1925, -0.3827, 0.5904, 0.4938 } },
			},
		},
		detail = Q.DetailPanel,
		tabIconScale = 1.3, -- ref tab icon ink ~63-70 px (the Bag's 54.5 box shows ~45-51)
	})
	local toolbar = Toolbar.new(shell.Slots.Toolbar)
	local quests = Quests.new(shell.Slots.Grid)
	local achievements = Achievements.new(shell.Slots.Grid)
	local mastery = Mastery.new(shell.Slots.Grid)
	local detail = Detail.new(shell.Slots.Detail)

	local rows, selected = {}, nil
	local achItems, achSelected = {}, nil
	local masterySelected = nil
	local query, mode = "", "All"
	local pending = {} -- ids with a ClaimQuest in flight, held until the next Meta after a success
	local timerToken = 0

	local hooks
	local function refreshTimers()
		local meta = NetClient.LastMeta
		local now = workspace:GetServerTimeNow()
		local dailyAt = if meta and type(meta.DailyResetAt) == "number"
			then meta.DailyResetAt
			else (now // DAY + 1) * DAY
		local weeklyAt = meta and meta.WeeklyResetAt
		quests:SetResetText(
			QuestLogic.resetText(dailyAt - now),
			if type(weeklyAt) == "number" then QuestLogic.resetText(weeklyAt - now) else nil
		)
	end

	local function render()
		local meta = NetClient.LastMeta
		local all = QuestLogic.questRows(meta and meta.Quests)
		rows = QuestLogic.filterQuests(all, query, mode)
		quests:SetRows(rows)
		refreshTimers()
		local pick
		for _, row in rows do
			if row.Id == selected then
				pick = row
			end
		end
		pick = pick or rows[1]
		if pick then
			hooks.OnSelect(pick.Id, pick)
		else
			selected = nil
			quests:SetSelected(nil)
			detail:Show(nil)
		end
	end

	local function renderAch()
		local all = QuestLogic.achievementRows(NetClient.LastCatalog, NetClient.LastMeta)
		achItems = QuestLogic.sortAchievements(QuestLogic.filterByName(all, query), mode)
		achievements:SetItems(achItems)
		local done, total = QuestLogic.achievementCount(all) -- whole list, not the filtered view
		toolbar:SetCount(if total > 0 then done .. " / " .. total else nil)
		local pick
		for _, item in achItems do
			if item.Id == achSelected then
				pick = item
			end
		end
		pick = pick or achItems[1]
		if pick then
			hooks.OnAchSelect(pick.Id, pick)
		else
			achSelected = nil
			achievements:SetSelected(nil)
			detail:Show(nil)
		end
	end

	local function renderMastery()
		local all = QuestLogic.masteryRows(NetClient.LastCatalog, NetClient.LastMeta)
		local list = QuestLogic.sortMastery(QuestLogic.filterByName(all, query), mode)
		mastery:SetRows(list)
		local pick
		for _, row in list do
			if row.Id == masterySelected then
				pick = row
			end
		end
		pick = pick or list[1]
		if pick then
			hooks.OnMasterySelect(pick.Id, pick)
		else
			masterySelected = nil
			mastery:SetSelected(nil)
			detail:Show(nil)
		end
	end

	local function renderTab()
		local tab = shell:GetTab()
		if tab == 1 then
			render()
		elseif tab == 2 then
			renderAch()
		elseif tab == 3 then
			renderMastery()
		end
	end

	-- Sends ClaimQuest(id) once (`ok` = the button is live); the busy button shows until the reply, or the next Meta after a success.
	local function claim(id: string?, ok: boolean)
		if not id or not ok or pending[id] then
			return
		end
		pending[id] = true
		renderTab() -- re-show the detail with the busy button
		task.spawn(function()
			local sent = NetClient.Request("ClaimQuest", id) -- rejection toast comes from Lobby; Meta shows the result
			if not sent then
				pending[id] = nil
			end
			if shell:IsOpen() then
				renderTab()
			end
		end)
	end

	-- HOOKS ------------------------------------------------------------------------------------------------
	hooks = {
		OnSelect = function(id: string, row) -- default: highlight the row and show it in the detail panel
			selected = id
			quests:SetSelected(id)
			detail:Show(questModel(row, pending[id]))
		end,
		OnClaim = function(id: string, row)
			claim(id, QuestLogic.claimState(row) == "Claim")
		end,
		OnAchSelect = function(id: string, item) -- Achievements tab: highlight the cell and show it in the detail panel
			achSelected = id
			achievements:SetSelected(id)
			detail:Show(achModel(item, pending[id]))
		end,
		OnMasterySelect = function(id: string, row) -- Mastery tab: highlight the cell and show it in the detail panel
			masterySelected = id
			mastery:SetSelected(id)
			detail:Show(masteryModel(row, pending))
		end,
		OnSearch = function(q: string)
			query = q
			renderTab()
		end,
		OnOption = function(id: string)
			mode = id
			renderTab()
		end,
	}
	quests:OnSelect(function(id, row)
		hooks.OnSelect(id, row)
	end)
	quests:OnClaim(function(id, row)
		hooks.OnClaim(id, row)
	end)
	achievements:OnSelect(function(id, item)
		hooks.OnAchSelect(id, item)
	end)
	mastery:OnSelect(function(id, row)
		hooks.OnMasterySelect(id, row)
	end)
	toolbar:OnSearch(function(q)
		hooks.OnSearch(q)
	end)
	toolbar:OnOption(function(id)
		hooks.OnOption(id)
	end)
	detail:OnAction(function(_, model)
		claim(model.ClaimId, model.Action.Enabled)
	end)
	quests:SetEmptyText("No quests found")
	achievements:SetEmptyText("No achievements found")
	mastery:SetEmptyText("No dice found")

	local function showTab()
		local tab = shell:GetTab()
		toolbar:SetPlaceholder(PLACEHOLDERS[tab] or "Search...")
		local default = if tab == 2 then "ProgressDesc" elseif tab == 3 then "LevelDesc" else "All"
		query, mode = "", default
		achSelected, masterySelected = nil, nil
		toolbar:SetQuery("")
		if tab == 3 then
			toolbar:SetLabel("", "Sort: ")
		else
			toolbar:SetLabel(if tab == 2 then "SORT:" else "Show:")
		end
		toolbar:SetOptions(if tab == 1 then OPTIONS elseif tab == 2 then ACH_OPTIONS else MASTERY_OPTIONS, default)
		toolbar:SetCount(nil)
		quests:SetVisible(tab == 1)
		achievements:SetVisible(tab == 2)
		mastery:SetVisible(tab == 3)
		if tab == 1 then
			selected = nil
		end
		renderTab()
	end

	shell:SetTabs({
		{ Id = "Quests", Label = "QUESTS", Icon = Q.IconTabScroll },
		{ Id = "Achievements", Label = "ACHIEVEMENTS", Icon = Q.IconTabTrophy },
		{ Id = "Mastery", Label = "MASTERY", Icon = Q.Crown },
	})
	shell:OnTab(showTab)
	shell:OnClose(function()
		ContextActionService:UnbindAction(ACTION)
		timerToken += 1
		selected, achSelected, masterySelected, query, mode = nil, nil, nil, "", "All"
		quests:SetScroll(0)
		achievements:SetScroll(0)
		mastery:SetScroll(0)
		hud:SetBagMode(false)
	end)
	table.insert(
		conns,
		GuiService.MenuOpened:Connect(function()
			shell:Close()
		end)
	)
	table.insert(
		conns,
		shell.Bag:GetAttributeChangedSignal("DebugTab"):Connect(function()
			local n = shell.Bag:GetAttribute("DebugTab")
			if type(n) == "number" then
				shell:SetTab(n)
			end
		end)
	)

	table.insert(
		conns,
		NetClient.Meta:Connect(function()
			table.clear(pending)
			if shell:IsOpen() then
				renderTab()
			end
		end)
	)

	self._shell, self._conns = shell, conns
	self._parts = { toolbar, quests, achievements, mastery, detail }
	self._open = function(tab)
		local idx = tab or 1
		if shell:IsOpen() then
			shell:SetTab(idx)
			return
		end
		shell:Open()
		hud:SetBagMode(true, "Quests")
		timerToken += 1
		local token = timerToken
		task.spawn(function()
			while token == timerToken do
				task.wait(1)
				if token == timerToken and shell:GetTab() == 1 then
					refreshTimers()
				end
			end
		end)
		ContextActionService:BindActionAtPriority(ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				shell:Close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		if shell:GetTab() == idx then
			showTab()
		else
			shell:SetTab(idx)
		end
	end
	return self
end

function QuestLog:Open(tab: number?)
	self._open(tab)
end

function QuestLog:Close()
	self._shell:Close()
end

function QuestLog:Toggle()
	if self._shell:IsOpen() then
		self._shell:Close()
	else
		self._open(1)
	end
end

function QuestLog:IsOpen(): boolean
	return self._shell:IsOpen()
end

function QuestLog:SetTab(n: number)
	self._shell:SetTab(n)
end

function QuestLog:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	if self._shell:IsOpen() then
		self._shell:Close() -- unbinds ButtonB and restores the HUD
	end
	for _, p in self._parts do
		p:Destroy()
	end
	self._shell:Destroy()
end

return QuestLog
