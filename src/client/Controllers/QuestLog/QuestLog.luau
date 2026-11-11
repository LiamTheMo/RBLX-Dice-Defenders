-- Quest Log controller: one Shell (banner, close, three tabs), the shared Toolbar and Detail, and the Quests list.
-- QuestLog.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open(tab?) :Close() :Toggle() :IsOpen() :SetTab(n) :Destroy()
-- Rows come from NetClient.LastMeta.Quests plus the client-only SampleData; re-rendered on NetClient.Meta while open.
-- Claim: only real "Claim" rows send ClaimQuest (one in flight per id); the next Meta decides the Claimed state.
-- Hooks (self.Hooks): the single place live behaviour plugs in; replace a field to change what a part does.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local NetClient = require(script.Parent.Parent.NetClient)
local Shell = require(script.Parent.Parent.Bag.Shell)
local Q = require(script.Parent.QuestSprites)
local QuestLogic = require(script.Parent.QuestLogic)
local SampleData = require(script.Parent.SampleData)
local Toolbar = require(script.Parent.Toolbar)
local Detail = require(script.Parent.Detail)
local Quests = require(script.Parent.Tabs.Quests)

local ACTION = "QuestLogClose"
local DAY = 86400

local PLACEHOLDERS = { "Search quests...", "Search achievements...", "Search mastery..." }
local OPTIONS = {
	{ Id = "All", Label = "All Quests" },
	{ Id = "Daily", Label = "Daily" },
	{ Id = "Weekly", Label = "Weekly" },
	{ Id = "Story", Label = "Story" },
	{ Id = "Claimable", Label = "Claimable" },
}
local ACTION_LABEL = { Claim = "CLAIM", Claimed = "CLAIMED", Soon = "SOON", Progress = "CLAIM" }

local function questModel(row, busy)
	local state = QuestLogic.claimState(row)
	return {
		Kind = "Quest",
		Title = "QUEST DETAILS",
		Name = row.Name,
		Icon = row.Icon,
		Body = { Desc = row.Desc, Progress = row.Progress, Goal = row.Goal, Gold = row.Gold, Gems = row.Gems },
		Action = { Label = ACTION_LABEL[state], State = state, Enabled = state == "Claim" and not busy },
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
			sprite = Q.Banner,
			full = Vector2.new(511, 160), -- 0.813x the 629x197 art: ink 500 wide as the reference scroll
			compact = Vector2.new(230, 72),
			top = -99.4, -- ink top 4 px below the reference canvas top (window box top = reference y 92)
			text = "QUEST LOG",
			textPos = UDim2.fromScale(0.538, 0.646), -- purple plate centre (reference 841.5, 96)
			textSize = UDim2.fromScale(0.5, 0.26),
			textFull = 34,
			textCompact = 20,
		},
		detail = Q.DetailPanel,
		fullDetail = true,
	})
	local toolbar = Toolbar.new(shell.Slots.Toolbar)
	local quests = Quests.new(shell.Slots.Grid)
	local detail = Detail.new(shell.Slots.Detail)

	local rows, selected = {}, nil
	local query, mode = "", "All"
	local pending = {} -- ids with a ClaimQuest request in flight
	local timerToken = 0

	local hooks
	local function refreshTimers()
		local meta = NetClient.LastMeta
		local now = workspace:GetServerTimeNow()
		local dailyAt = if meta and meta.DailyResetAt then meta.DailyResetAt else (now // DAY + 1) * DAY
		quests:SetResetText(
			QuestLogic.resetText(dailyAt - now),
			QuestLogic.resetText(QuestLogic.weeklyResetAt(now) - now)
		)
	end

	local function render()
		local meta = NetClient.LastMeta
		local all = QuestLogic.questRows(meta and meta.Quests, SampleData.Quests)
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

	-- HOOKS ------------------------------------------------------------------------------------------------
	hooks = {
		OnSelect = function(id: string, row) -- default: highlight the row and show it in the detail panel
			selected = id
			quests:SetSelected(id)
			detail:Show(questModel(row, pending[id]))
		end,
		OnClaim = function(id: string, row)
			if row.Sample then
				deps.toast("Coming soon!")
				return
			end
			if QuestLogic.claimState(row) ~= "Claim" or pending[id] then
				return
			end
			pending[id] = true
			hooks.OnSelect(id, row) -- re-show the detail with the busy button
			task.spawn(function()
				NetClient.Request("ClaimQuest", id) -- rejection toast comes from Lobby; Meta shows the result
				pending[id] = nil
				if shell:IsOpen() and shell:GetTab() == 1 then
					render()
				end
			end)
		end,
		OnSearch = function(q: string)
			query = q
			render()
		end,
		OnOption = function(id: string)
			mode = id
			render()
		end,
	}
	self.Hooks = hooks
	quests:OnSelect(function(id, row)
		hooks.OnSelect(id, row)
	end)
	quests:OnClaim(function(id, row)
		hooks.OnClaim(id, row)
	end)
	toolbar:OnSearch(function(q)
		hooks.OnSearch(q)
	end)
	toolbar:OnOption(function(id)
		hooks.OnOption(id)
	end)
	detail:OnAction(function(state)
		if state == "Claim" and selected then
			for _, row in rows do
				if row.Id == selected then
					hooks.OnClaim(row.Id, row)
				end
			end
		end
	end)

	local function showTab()
		local tab = shell:GetTab()
		toolbar:SetPlaceholder(PLACEHOLDERS[tab] or "Search...")
		query, mode = "", "All"
		toolbar:SetQuery("")
		toolbar:SetLabel("Show:")
		toolbar:SetOptions(if tab == 1 then OPTIONS else {}, "All")
		quests:SetVisible(tab == 1)
		if tab == 1 then
			selected = nil
			quests:SetEmptyText("No quests found")
			render()
		else
			detail:Show(nil) -- Achievements and Mastery: empty list area until built
		end
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
		selected, query, mode = nil, "", "All"
		quests:SetScroll(0)
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
			if shell:IsOpen() and shell:GetTab() == 1 then
				render()
			end
		end)
	)

	self._shell, self._hud, self._conns = shell, hud, conns
	self._parts = { toolbar, quests, detail }
	self._open = function(tab)
		local idx = tab or 1
		if shell:IsOpen() then
			shell:SetTab(idx)
			return
		end
		shell:Open()
		hud:SetBagMode(true)
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
