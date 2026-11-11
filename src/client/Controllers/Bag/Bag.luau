-- Bag controller: one Shell, four tabs, per-tab view state until close. Reads NetClient, sends intents only
-- (EquipDeck); the deck changes when the server pushes Meta, never optimistically.
-- Bag.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> bag :Open(tab: number?) :Close() :Toggle() :IsOpen() :Destroy()

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local NetClient = require(script.Parent.Parent.NetClient)
local Shell = require(script.Parent.Shell)
local Parts = require(script.Parent.Parts)
local BagLogic = require(script.Parent.BagLogic)
local Dice = require(script.Parent.Tabs.Dice)
local Materials = require(script.Parent.Tabs.Materials)
local Items = require(script.Parent.Tabs.Items)
local Cosmetics = require(script.Parent.Tabs.Cosmetics)

local ACTION = "BagClose"
local SEND_GAP = 1.0 -- server rate is 1/s: stay at or under it

local TABS = { Dice, Materials, Items, Cosmetics }

local Bag = {}
Bag.__index = Bag

function Bag.new(parent, deps)
	local self = setmetatable({}, Bag)
	local hud, toast = deps.hud, deps.toast
	local conns = {}
	local shell = Shell.new(parent, {
		fit = function()
			return hud:GetBagInsets()
		end,
	})
	local toolbar, grid = Parts.Toolbar(shell.Slots.Toolbar), Parts.Grid(shell.Slots.Grid)
	local footer, detail = Parts.Footer(shell.Slots.Footer), Parts.Detail(shell.Slots.Detail)

	local meta -- latest Meta payload (NetClient.LastMeta)
	local state = {} -- per tab: query, sort, selected, scroll
	local cur = 1 -- tab index being shown
	local view = {} -- visible items (filtered + sorted)
	local model -- current detail model
	local pending -- die id waiting for a loadout slot
	local lastSend, inFlight = -math.huge, false
	local slotButtons = {}

	local function resetState()
		for i, tab in TABS do
			state[i] = { query = "", sort = tab.DefaultSort, selected = nil, scroll = 0 }
		end
		pending = nil
	end
	resetState()

	local function safe(label: string, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			warn(("[Bag] %s failed: %s"):format(label, tostring(err)))
		end
		return ok
	end

	local function renderFooter()
		local tab = TABS[cur]
		-- Loadout strip: DICE tab only; on short screens (Compact) it is an overlay shown just while picking a slot.
		footer:SetVisible(tab.Footer ~= nil and (not shell.Compact or pending ~= nil))
		shell:SetFooter(tab.Footer ~= nil)
		if not tab.Footer then
			return
		end
		local f = tab.Footer(meta)
		footer:SetLabel(if pending then "PICK A SLOT TO REPLACE" else f.Label)
		footer:SetSlots(f.Slots)
		for i, s in slotButtons do
			local icon = s:FindFirstChild("Icon")
			if icon and f.Tints and f.Tints[i] then
				icon.ImageColor3 = f.Tints[i]
			end
		end
		footer:SetSlotHighlight(pending ~= nil)
		footer:SetButton(f.Button)
	end

	local function renderDetail()
		local tab, st = TABS[cur], state[cur]
		model = nil
		local item
		for _, it in view do
			if it.Id == st.selected then
				item = it
			end
		end
		if item and tab.Detail then
			model = tab.Detail(item)
		end
		detail:Show(model)
	end

	-- Rebuilds the visible tab from state + meta. keepScroll: data refresh keeps the offset, filters reset it.
	local function render(keepScroll: boolean?)
		local tab, st = TABS[cur], state[cur]
		safe("render", function()
			local items = tab.GetItems(meta)
			view = BagLogic.sort(BagLogic.filter(items, st.query), st.sort)
			local found = false
			for _, it in view do
				found = found or it.Id == st.selected
			end
			if not found then
				st.selected = if view[1] then view[1].Id else nil
				pending = nil
			end
			grid:SetKind(tab.Grid)
			toolbar:SetKind(tab.Grid)
			grid:SetFallback(tab.Fallback)
			detail:SetFallback(tab.Fallback)
			toolbar:SetPlaceholder(tab.Placeholder)
			toolbar:SetQuery(st.query)
			toolbar:SetSortOptions(tab.SortOptions, st.sort)
			grid:SetEmptyText(if st.query ~= "" then "No results" else tab.EmptyText)
			grid:SetItems(view)
			grid:SetSelected(st.selected)
			renderDetail()
			renderFooter()
		end)
		if keepScroll then
			task.defer(function()
				if shell:IsOpen() and TABS[cur] == tab then
					grid:SetScroll(st.scroll)
				end
			end)
		else
			grid:ResetScroll()
			st.scroll = 0
		end
	end

	local function sendDeck(ids)
		if inFlight or os.clock() - lastSend < SEND_GAP then
			toast("Please wait")
			return
		end
		inFlight, lastSend = true, os.clock()
		task.spawn(function()
			-- A rejection is toasted by Lobby's NetClient.Rejected handler; success arrives as Meta.
			NetClient.Request("EquipDeck", ids)
			inFlight = false
		end)
	end

	local function pickSlot(i: number)
		if not pending then
			return
		end
		local owned = {}
		for _, d in if meta then meta.Dice else {} do
			table.insert(owned, d.Id)
		end
		local ids = BagLogic.replaceSlot(meta and meta.Deck, owned, pending, i)
		pending = nil
		if not ids then
			render(true)
			return
		end
		renderFooter()
		sendDeck(ids)
	end

	for i = 1, 5 do
		slotButtons[i] = shell.Slots.Footer:FindFirstChild("Slot" .. i, true)
	end
	footer:OnSlot(function(i)
		safe("slot", pickSlot, i)
	end)
	table.insert(
		conns,
		shell.Slots.Footer:GetAttributeChangedSignal("Compact"):Connect(function()
			if shell:IsOpen() then
				safe("footer", renderFooter)
			end
		end)
	)

	-- Callbacks -----------------------------------------------------------------------------------------
	toolbar:OnSearch(function(q)
		if q == state[cur].query then -- SetQuery echoes our own write back
			return
		end
		state[cur].query = q
		render(false)
	end)
	toolbar:OnSort(function(id)
		state[cur].sort = id
		render(false)
	end)
	grid:OnSelect(function(item)
		safe("select", function()
			state[cur].selected = item.Id
			pending = nil
			grid:SetSelected(item.Id)
			renderDetail()
			renderFooter()
		end)
	end)
	detail:OnAction(function(id, hint)
		safe("action", function()
			local btn
			for _, b in if model then model.Buttons else {} do
				if b.Id == id then
					btn = b
				end
			end
			if not btn or not btn.Enabled then
				toast(hint or "Not available")
				return
			end
			if id == "Equip" then
				pending = state[cur].selected
				renderFooter()
				toast("Pick a loadout slot")
			end
		end)
	end)
	detail:OnStep(function()
		toast("Coming soon") -- every stepper is a disabled preview for now
	end)
	footer:OnButton(function(hint)
		toast(hint or "Coming soon")
	end)

	local function showTab()
		cur = shell:GetTab()
		pending = nil
		render(true)
	end
	shell:SetTabs((function()
		local list = {}
		for i, t in TABS do
			list[i] = { Id = t.Id, Label = t.Label, Icon = t.Icon }
		end
		return list
	end)())
	shell:OnTab(function()
		state[cur].scroll = grid:GetScroll() -- leaving: remember the offset
		showTab()
	end)
	shell:OnClose(function()
		ContextActionService:UnbindAction(ACTION)
		resetState()
		grid:ResetScroll()
		hud:SetBagMode(false)
	end)

	table.insert(
		conns,
		NetClient.Meta:Connect(function(m)
			meta = m
			if shell:IsOpen() then
				state[cur].scroll = grid:GetScroll()
				render(true)
			end
		end)
	)
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

	self._shell, self._hud, self._conns = shell, hud, conns
	self._parts = { toolbar, grid, footer, detail }
	self._open = function(tab)
		local idx = tab or 1
		meta = NetClient.LastMeta
		if shell:IsOpen() then
			shell:SetTab(idx)
			return
		end
		shell:Open()
		hud:SetBagMode(true)
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

function Bag:Open(tab: number?)
	self._open(tab)
end

function Bag:Close()
	self._shell:Close()
end

function Bag:Toggle()
	if self._shell:IsOpen() then
		self._shell:Close()
	else
		self._open(1)
	end
end

function Bag:IsOpen(): boolean
	return self._shell:IsOpen()
end

function Bag:Destroy()
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

return Bag
