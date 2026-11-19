-- Bag controller: one Shell, four tabs, per-tab view state until close. Reads NetClient, sends intents only
-- (EquipDeck, BagAction); the deck and inventory change when the server pushes Meta, never optimistically.
-- Bag.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> bag :Open(tab: number?) :Close() :Toggle() :IsOpen() :Destroy()

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local NetClient = require(script.Parent.Parent.NetClient)
local Shell = require(script.Parent.Shell)
local Parts = require(script.Parent.Parts)
local Sprites = require(script.Parent.BagSprites)
local BagLogic = require(script.Parent.BagLogic)
local Dice = require(script.Parent.Tabs.Dice)
local Materials = require(script.Parent.Tabs.Materials)
local Items = require(script.Parent.Tabs.Items)
local Cosmetics = require(script.Parent.Tabs.Cosmetics)

local ACTION = "BagClose"
local SEND_GAP = 1.0 -- server rate is 1/s: stay at or under it

local TABS = { Dice, Materials, Items, Cosmetics }

-- BagAction replies (NetClient refusals included) and successes, shown through the Bag's toast.
local REPLIES = {
	UnknownItem = "Unknown item",
	NotOwned = "You don't own that",
	Insufficient = "You don't have that many",
	Locked = "Unlock it first",
	NotSellable = "Can't be sold",
	NotUsable = "Can't be used",
	Overflow = "You can't hold that much",
	NotLoaded = "Still loading",
	NotOwner = "This server is in use",
	Throttled = "Slow down",
	Network = "Connection problem",
}
local UPGRADE_REPLIES = { -- UpgradeDie refusals; anything unlisted reads "Something went wrong", never a raw code
	MaxLevel = "Already max level",
	UnknownDie = "Unknown die",
	NotOwned = "You don't own that",
	WrongPhase = "Not during a match",
	RateLimited = "Slow down",
	Insufficient = "Not enough copies",
	NotLoaded = "Still loading",
	NotOwner = "This server is in use",
	Throttled = "Slow down",
	Network = "Connection problem",
}
local DONE =
	{ Sell = "Sold", Use = "Used", Lock = "Locked", Unlock = "Unlocked", Equip = "Equipped", Unequip = "Unequipped" }

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
		banner = {
			text = "BAG",
			textW = 0.525,
			emblems = {
				{
					sprite = Sprites.BannerEmblem,
					box = { full = { 0, 0, 0.1116, 0.805 }, compact = { 0, 0, 0.0868, 0.6266 } }, -- as tall as the Quest seal; the compact one clears the gem pin
					side = true,
				},
			},
		},
	})
	local toolbar, grid = Parts.Toolbar(shell.Slots.Toolbar), Parts.Grid(shell.Slots.Grid)
	local footer, detail = Parts.Footer(shell.Slots.Footer), Parts.Detail(shell.Slots.Detail)

	local meta -- latest Meta payload (NetClient.LastMeta)
	local catalog -- display catalogue (NetClient.LastCatalog)
	local state = {} -- per tab: query, sort, selected, scroll, qty (the stepper's pick)
	local cur = 1 -- tab index being shown
	local view = {} -- visible items (filtered + sorted)
	local model -- current detail model
	local footerButton -- current footer button model (DICE: UNEQUIP ALL)
	local pending -- die id waiting for a loadout slot
	local lastSend, inFlight = -math.huge, false
	local slotButtons = {}

	local function resetState()
		for i, tab in TABS do
			state[i] = { query = "", sort = tab.DefaultSort, selected = nil, scroll = 0, qty = 1 }
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
		footer:SetVisible(tab.Footer ~= nil)
		shell:SetFooter(tab.Footer ~= nil)
		if not tab.Footer then
			return
		end
		local f = tab.Footer(meta)
		footerButton = f.Button
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
			st.qty = BagLogic.stepQty(st.qty, 0, item.Quantity) -- a smaller stack (after a sale) clamps the pick
			model = tab.Detail(item, st.qty)
		end
		detail:Show(model)
	end

	-- Rebuilds the visible tab from state + meta. keepScroll: data refresh keeps the offset, filters reset it.
	local function render(keepScroll: boolean?)
		local tab, st = TABS[cur], state[cur]
		safe("render", function()
			local items = tab.GetItems(meta, catalog, Sprites)
			view = BagLogic.sort(BagLogic.filter(items, st.query), st.sort)
			local found = false
			for _, it in view do
				found = found or it.Id == st.selected
			end
			if not found then
				st.selected = if view[1] then view[1].Id else nil
				st.qty = 1
				pending = nil
			end
			grid:SetKind(tab.Grid)
			toolbar:SetKind(tab.Grid)
			grid:SetFallback(tab.Fallback)
			detail:SetFallback(tab.Fallback)
			toolbar:SetPlaceholder(tab.Placeholder)
			toolbar:SetQuery(st.query)
			toolbar:SetSortOptions(tab.SortOptions, st.sort)
			if toolbar.SetCount then -- Parts.Toolbar shows it once it has the slot (open request in notes)
				toolbar:SetCount(if tab.Count then tab.Count(meta, catalog) else nil)
			end
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

	-- One BagAction; the reply (or NetClient's own refusal) is toasted, the change itself arrives as Meta.
	local function sendBag(action: string, id: string, qty: number)
		task.spawn(function()
			local ok, code = NetClient.Request("BagAction", action, id, qty)
			toast(if ok then DONE[action] else REPLIES[code] or tostring(code))
		end)
	end

	-- One UpgradeDie intent (the server decides level, copies and cost); the new level comes back through Meta.
	local upgrading = false
	local function sendUpgrade(id: string)
		if upgrading then
			return
		end
		upgrading = true
		local function levelOf()
			for _, d in if meta then meta.Dice else {} do
				if d.Id == id and type(d.Level) == "number" then
					return d.Level
				end
			end
			return nil
		end
		local before = levelOf()
		task.spawn(function()
			local ok, code = NetClient.Request("UpgradeDie", id)
			upgrading = false
			if not ok then
				toast(UPGRADE_REPLIES[code] or "Something went wrong")
				return
			end
			local level = levelOf() -- the refreshed Meta may land after the reply: only a risen level is trusted
			toast(if level and before and level > before then ("Upgraded to Lv. %d"):format(level) else "Upgraded")
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
			if state[cur].selected ~= item.Id then
				state[cur].qty = 1
			end
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
			local st = state[cur]
			if btn.Send then -- a BagAction: the stepper's qty for Sell and Use, else 1
				sendBag(id, st.selected, if id == "Sell" or id == "Use" then st.qty else 1)
			elseif id == "Upgrade" then
				sendUpgrade(st.selected)
			elseif id == "ConvertShard" then
				task.spawn(function()
					local ok, code = NetClient.Request("TutorialAction", "Convert", st.selected)
					toast(
						if ok
							then "Converted a Dice Shard into one spare copy"
							elseif code == "Locked" then "Unlock your Dice Shards first"
							else "Could not use a Dice Shard"
					)
				end)
			elseif id == "Equip" then
				local deck = meta and meta.Deck
				if deck and #deck < 5 then
					pending = st.selected
					pickSlot(#deck + 1)
				elseif deck then
					pending = st.selected
					renderFooter()
					toast("Pick a loadout slot")
				end
			elseif id == "Unequip" and meta and meta.Deck then
				local slot = table.find(meta.Deck, st.selected)
				if slot then
					local ids = table.clone(meta.Deck)
					table.remove(ids, slot)
					pending = nil
					renderFooter()
					sendDeck(ids)
				end
			end
		end)
	end)
	detail:OnStep(function(delta)
		safe("step", function()
			local st = model and model.Stepper
			if not st then
				return
			end
			if not st.Enabled then
				toast(st.Hint or "Not available")
				return
			end
			state[cur].qty = BagLogic.stepQty(state[cur].qty, delta, st.Max)
			renderDetail()
		end)
	end)
	footer:OnButton(function(hint)
		safe("footer", function()
			if footerButton and footerButton.Enabled then
				pending = nil
				renderFooter()
				sendDeck({})
			else
				toast(hint or "Not available")
			end
		end)
	end)

	local function showTab()
		cur = shell:GetTab()
		pending = nil
		shell:SetDetailWidth(TABS[cur].DetailW)
		render(true)
	end
	shell:SetTabs((function()
		local list = {}
		for i, t in TABS do
			list[i] = { Id = t.Id, Label = t.Label }
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

	local function refresh()
		if shell:IsOpen() then
			state[cur].scroll = grid:GetScroll()
			render(true)
		end
	end
	table.insert(
		conns,
		NetClient.Meta:Connect(function(m)
			meta = m
			refresh()
		end)
	)
	table.insert(
		conns,
		NetClient.Catalog:Connect(function(c)
			catalog = c
			refresh()
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
		meta, catalog = NetClient.LastMeta, NetClient.LastCatalog
		if shell:IsOpen() then
			shell:SetTab(idx)
			return
		end
		shell:Open()
		hud:SetBagMode(true, "Bag")
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

-- Closes when open (on `tab`, or on any tab when none is given); otherwise opens or switches to `tab`.
function Bag:Toggle(tab: number?)
	if self._shell:IsOpen() and (tab == nil or self._shell:GetTab() == tab) then
		self._shell:Close()
	else
		self._open(tab)
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
