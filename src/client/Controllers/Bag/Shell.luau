-- Shell: the one window every menu shares (code-drawn chrome, title, close X, tab row, panel slots) plus Fit(). Visual only.
-- Design px under one UIScale (1672x941 reference, scaled uniformly; phones below UiKit.PHONE_H use the Compact tier).
-- Shell.new(parent, deps) -> shell. deps: fit = () -> { leftReal, bottomTopReal, placeRow? } (required), name (root name, default "Bag"),
-- banner = { text } (the title; other banner fields are ignored), free (no left/detail panels: one Slots.Content box),
-- tabW (tabs keep this design-px width, shrunk to leave deps.tabReserve free on phones), tabIconScale. size / popupScale / detail /
-- fullDetail are accepted and ignored: every menu, Codes included, gets the same window.
-- Fields: Bag (root), Scaled, Window, Banner (invisible title anchor), TabBar (Tab<i>.Row.Icon / .Label), CloseButton, Content, Slots, Compact.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parts)
local Chrome = require(script.Parent.Chrome)
local SettingsLogic = require(script.Parent.Parent.Settings.SettingsLogic)
local Shared = require(script.Parent.Parent.SharedSprites)
local UiSounds = require(script.Parent.Parent.UiSounds)

local make = UiKit.make
local Z = 20 -- root; Sibling ZIndex (descendants always >= their parent)
local MIN_HIT = 44 -- real px: every touch target

-- Full = the 1672x941 mockup: window box 1112x666 (outer dark edge x 280..1392, y 86..752); numbers are window-relative.
local TIER = {
	Full = {
		W = 1112,
		H = 666,
		side = 22, -- window edge to panels (panel rim at x 302)
		gap = 7,
		tabX = 52, -- tab row left (first tab outline x 332)
		tabTop = 67, -- visible tab top (y 153)
		tabH = 54, -- visible tab 54 tall (y 153..207)
		tabGap = 8,
		tabText = 29, -- round-2 capture: 32 rendered ~10% wider than the mockup labels (MATERIALS 115 vs 106)
		icon = 30,
		iconGap = 8,
		contentTop = 139, -- panels start y 225
		freeTop = 64,
		bottomPad = 20,
		pitch = 142,
		title = { size = 60, stroke = 5, cy = 33 }, -- ROLL: white cap height 33, centre y 119 (size 46 measured 27 px tall, 92 wide vs 124 in engine)
		close = { w = 52, h = 48, dx = 44.5, cy = 34 }, -- visible 52x48, centre (1347.5, 120)
	},
	Compact = {
		W = 1160,
		side = 16,
		gap = 8,
		tabX = 24,
		tabTop = 52,
		tabH = 40,
		tabGap = 6,
		tabText = 23,
		icon = 24,
		iconGap = 6,
		contentTop = 102,
		freeTop = 52,
		bottomPad = 12,
		pitch = 120,
		title = { size = 38, stroke = 3, cy = 24 },
		close = { w = 44, h = 41, dx = 32, cy = 26 },
	},
}
local GAP = 10 -- vertical gap left panel to footer
local TOOLBAR_H, FOOTER_H = 63, 83 -- mockup: grid top y 288 (content y 63), loadout strip 682x83 at y 651
local GRID_INSET = 13
local LINE_Y = -2 -- Full: the search / sort / action row sits this far from the content top (was 4)
local FRAME_TOP, GRID_PAD = 50, 10 -- framed card grid: top below the search row; cards sit GRID_PAD inside the frame's sides
local DETAIL_MAX, DETAIL_MIN = 368, 310 -- mockup detail panel 368 wide
local LEFT_PANEL_BOTTOM_INSET = 41 -- left panel inset on desktop tabs without a footer
local MIN_SCALE, MAX_SCALE = 0.8, 1.5

local Shell = {}
Shell.__index = Shell

function Shell.new(parent, deps)
	local self = setmetatable({}, Shell)
	local conns = {}
	self._conns, self._deps = conns, deps
	self._tab, self._tabs, self._tabButtons = 0, {}, {}
	self._onTab, self._onClose = {}, {}

	local rootName = deps.name or "Bag"
	local bag = make("Frame", {
		Name = rootName,
		BackgroundTransparency = 1,
		Active = false,
		Visible = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z,
	}, parent)
	local scaled = make("Frame", { Name = "Scaled", BackgroundTransparency = 1, ZIndex = Z }, bag)
	local uiScale = make("UIScale", { Name = rootName .. "Scale" }, scaled)
	local window = make("Frame", {
		Name = "Window",
		BackgroundTransparency = 1,
		Active = true, -- sinks clicks on the window only
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = Z + 1,
	}, scaled)
	local pop = make("UIScale", { Name = "Pop" }, window)
	self.Bag, self.Scaled, self.Window, self._uiScale, self._pop = bag, scaled, window, uiScale, pop

	local function frame(name, par, z)
		return make("Frame", { Name = name, BackgroundTransparency = 1, ZIndex = z }, par)
	end

	self.Chrome = Chrome.window(window, Z + 1)

	-- Content: left column (toolbar, grid, footer) + detail panel; free mode: the bare content box only.
	local free = deps.free
	local content = frame("Content", window, Z + 2)
	self.Content, self.Slots = content, { Content = content }
	local left, leftPanel, toolbar, grid, footer, detail, detailSlot
	if not free then
		left = frame("Left", content, Z + 3)
		leftPanel = frame("LeftPanel", left, Z + 2) -- the Bag mockup draws no frame around the grid column
		leftPanel.Size = UDim2.fromScale(1, 1)
		toolbar = frame("Toolbar", left, Z + 5)
		self.GridFrame = Chrome.panel(left, { Name = "GridFrame", ZIndex = Z + 2 })
		grid = frame("Grid", left, Z + 3)
		footer = frame("Footer", left, Z + 14) -- above grid and detail (Global ZIndex gui); below popups (45)
		detail = Chrome.panel(content, { Name = "Detail", ZIndex = Z + 2 })
		detailSlot = frame("Slot", detail, Z + 3)
		detailSlot.Size = UDim2.fromScale(1, 1)
		local topBar = frame("TopBar", content, Z + 5) -- action row above the detail panel (tabs that ask for it: SetTopBar)
		topBar.Visible = false
		self.LeftPanel, self.Left = leftPanel, left
		self.Slots = { Toolbar = toolbar, Grid = grid, Footer = footer, Detail = detailSlot, TopBar = topBar }
		self._detail = detail
	end

	-- Tab row (left-aligned like the mockups; other children with a high LayoutOrder share the row).
	local tabBar = frame("TabBar", window, Z + 3)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabBar)
	self.TabBar = tabBar

	-- Title: white text, dark outline, centred at the top; Banner is the invisible box that holds it.
	local banner = frame("Banner", window, Z + 10)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	self.Banner = banner
	local titleText = Parts.text(banner, {
		Name = "Text",
		Text = (deps.banner and deps.banner.text) or "BAG",
		TextTruncate = Enum.TextTruncate.None,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z + 12,
	}, 4)

	-- Close X: whole art (normal / hover / pressed), a hit box of at least 44 real px on top.
	local close = make("ImageButton", {
		Name = "Close",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = Z + 11,
	}, window)
	close.Image, close.ScaleType = Shared.Close.Image, Enum.ScaleType.Fit
	Parts.interact(close, function(state)
		close.Image = Shared[if state == "Pressed"
			then "ClosePressed"
			elseif state == "Hover" then "CloseHover"
			else "Close"].Image
	end)
	self.CloseButton = close
	local closeHit = make("TextButton", {
		Name = "Hit",
		BackgroundTransparency = 1,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = Z + 12,
		Selectable = false, -- the X stays the one gamepad stop
	}, close)
	-- Hit covers the X, so its hover/press drives the X's own feedback (Parts.interact reads DebugState)
	UiKit.wire(closeHit, function(state)
		close:SetAttribute("DebugState", if state == "Normal" then nil else state)
	end)
	table.insert(
		conns,
		closeHit.Activated:Connect(function()
			self:Close()
		end)
	)
	table.insert(
		conns,
		close.Activated:Connect(function()
			self:Close()
		end)
	)
	self._closeHit = closeHit

	-- Fit ------------------------------------------------------------------------------------------------
	local function fit()
		local size = UiKit.screenSize(parent)
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local ins = deps.fit()
		local phone = size.Y < UiKit.PHONE_H
		local availW = size.X - 2 * (ins.leftReal + if phone then 8 else 6)
		local vpad = if phone then 0 else 4 -- the window box may reach the bag row: its bottom margin is transparent
		local availH = ins.bottomTopReal - 10 + vpad -- region [4, bottomTop - 6 + vpad]
		local full = TIER.Full
		-- Full tier: the HUD's own uniform design scale (LobbyHud rescale), window at its design rect. Phones: fill the free region.
		local bs = if phone
			then math.clamp(math.min(availW / full.W, availH / full.H), MIN_SCALE, MAX_SCALE)
			else math.min(size.X / 1672, size.Y / 941, MAX_SCALE)
		-- Settings UI Scale: Full tier only, es = bs at 100% (design layout below still uses bs)
		local es = if phone then bs else bs * (SettingsLogic.get("uiScale") / 100)
		uiScale.Scale = es
		scaled.Size = UDim2.fromScale(1 / es, 1 / es)
		local dw, dh = availW / bs, availH / bs -- design px that remain (phones)
		Chrome.restroke(window, es)

		local compact = phone
		local t = if compact then TIER.Compact else full
		local winW = if compact then math.min(t.W, dw) else t.W
		local hf = if compact then math.clamp(dh, 250, full.H) else full.H
		local side, gap = t.side, t.gap
		local inner = winW - 2 * side
		local cols = math.clamp(math.floor((inner - gap - DETAIL_MIN - 10) / t.pitch), 2, 5)
		local leftW = cols * t.pitch + 10
		local detailW = math.min(DETAIL_MAX, inner - gap - leftW)
		if not compact then -- mockup: the detail panel's right edge is fixed, its width differs per tab (SetDetailWidth)
			detailW = self._detailW or DETAIL_MAX
			leftW = inner + 4 - gap - detailW
		elseif detailW == DETAIL_MAX then
			leftW = inner - gap - detailW + (if compact then 0 else 4) -- spare width goes to the grid column (the mockup panel ends 18 px from the window edge)
		else
			winW = 2 * side + gap + leftW + detailW
		end
		local contentTop = if free and #self._tabs == 0 then t.freeTop else t.contentTop
		local contentH = hf - contentTop - t.bottomPad
		local leftH = if compact
			then contentH
			elseif self._footerOn then contentH - FOOTER_H - GAP
			else contentH - LEFT_PANEL_BOTTOM_INSET

		-- Phones: centred in the free region. Full: horizontally centred at design y 86 (the 1672x941 mockup); on a taller-than-16:9
		-- screen the spare height splits evenly; the window is never lower than the bag row's top nor higher than 4 real px.
		local top
		if compact then
			top = 4 + ((ins.bottomTopReal - 8 + vpad) - 4 - hf * bs) / 2
		else
			top = 86 * es + math.max(0, size.Y - 941 * es) / 2
			top = math.max(4, math.min(top, ins.bottomTopReal - 8 - hf * es))
		end
		local real = if compact then bs else es
		local minD = math.ceil(MIN_HIT / es) -- round design pixels up for the 44 px touch target
		window.Size = UDim2.fromOffset(winW, hf)
		window.Position = UDim2.new(0.5, 0, 0, (top + hf * real / 2) / es)
		if ins.placeRow and self.Bag.Visible then -- the shared bag row follows the OPEN menu only (closed ones refit on resize too)
			ins.placeRow(top + hf * real)
		end

		content.Position = UDim2.fromOffset(side, contentTop)
		content.Size = UDim2.fromOffset(winW - 2 * side, contentH)
		if not free then
			left.Size = UDim2.fromOffset(leftW, contentH)
			leftPanel.Size = UDim2.fromOffset(leftW, leftH)
			toolbar.Size = UDim2.fromOffset(leftW, TOOLBAR_H)
			toolbar.Position = UDim2.fromOffset(0, if compact then 0 else LINE_Y - 4) -- the toolbar pads 4 px above its controls
			grid:SetAttribute("FooterInset", FOOTER_H + GAP - LEFT_PANEL_BOTTOM_INSET) -- Cosmetics sizes its cards as if the Dice footer were shown
			local fx = if compact then 0 else 7 -- mockup: grid x 313, strip x 309 (panel x 302)
			local footerY = contentH - FOOTER_H + (if compact then 0 else 2)
			-- Full: the card grid sits inside a framed panel under the search row (same top and bottom as the detail panel).
			local frameY = FRAME_TOP
			local frameH = contentH - frameY
			local gridFrame = self.GridFrame
			gridFrame.Visible = not compact
			gridFrame.Position = UDim2.fromOffset(fx, frameY)
			gridFrame.Size = UDim2.fromOffset(leftW - 15, frameH)
			grid.Position = if compact
				then UDim2.fromOffset(3, TOOLBAR_H)
				else UDim2.fromOffset(fx + GRID_PAD, frameY + 2)
			grid.Size = if compact
				then UDim2.fromOffset(leftW - 6, leftH - TOOLBAR_H - (if self._footerOn then minD + 12 else GRID_INSET))
				else UDim2.fromOffset(leftW - 15 - 2 * GRID_PAD, frameH - 6)
			footer.Position = UDim2.fromOffset(fx, footerY) -- compact: an overlay on the panel bottom
			footer.Size = UDim2.fromOffset(if compact then leftW else leftW - 15, FOOTER_H)
			local topOn = self._topOn == true and not compact
			local topBar = self.Slots.TopBar
			topBar.Visible = topOn
			-- With a top bar the detail panel drops below it and ends where the card grid ends (same height as the inventory).
			local detailY = if topOn then FRAME_TOP else 0
			local detailH = contentH - detailY
			topBar.Position = UDim2.fromOffset(leftW + gap, LINE_Y)
			topBar.Size = UDim2.fromOffset(detailW, 42)
			detail.Position = UDim2.fromOffset(leftW + gap, detailY)
			detail.Size = UDim2.fromOffset(detailW, detailH)
			detailSlot.Size = UDim2.fromOffset(detailW, detailH - 8) -- offsets: Parts read slot widths in design px
		end
		for _, slotFrame in self.Slots do
			slotFrame:SetAttribute("Compact", compact)
		end
		self.Compact = compact

		-- Title: shrinks (>= 14) to stay clear of the close X on both sides.
		local tt = t.title
		local closeBox = t.close
		local avail = winW - 2 * (closeBox.dx + closeBox.w / 2 + 8)
		local ts = Parts.fitSize(titleText.Text, avail, tt.size, 14)
		banner.Position = UDim2.fromOffset(winW / 2, tt.cy)
		banner.Size = UDim2.fromOffset(avail, math.ceil(ts * 1.25))
		titleText.TextSize = ts
		titleText.UIStroke.Thickness = tt.stroke

		-- Close X: visible art at its measured size, hit box >= 44 real px.
		close.Size = UDim2.fromOffset(closeBox.w, closeBox.h)
		close.Position = UDim2.fromOffset(winW - closeBox.dx, closeBox.cy)
		closeHit.Size = UDim2.fromOffset(math.max(closeBox.w, minD), math.max(closeBox.h, minD))

		-- Tabs: equal widths filling the row (or deps.tabW); the label shrinks (>= 15) and the icon drops when narrow.
		local n = math.max(1, #self._tabs)
		local barW = winW - 2 * t.tabX
		local hitH = math.max(t.tabH, minD)
		tabBar.Position = UDim2.fromOffset(t.tabX, t.tabTop - (hitH - t.tabH) / 2)
		tabBar.Size = UDim2.fromOffset(barW, hitH)
		tabBar.UIListLayout.Padding = UDim.new(0, t.tabGap)
		local equal = (barW - (n - 1) * t.tabGap) / n
		local tabW = equal
		if deps.tabW then
			tabW = if compact
				then math.min(deps.tabW * t.tabH / full.tabH, (barW - (deps.tabReserve or 0) - (n - 1) * t.tabGap) / n)
				else math.min(deps.tabW, equal)
		end
		tabW = math.floor(tabW)
		local icon = t.icon * (if compact then 1 else deps.tabIconScale or 1)
		local labelSize = math.huge -- one text size for the whole bar: the largest every label fits at
		for i, tab in self._tabButtons do
			local hasIcon = self._tabs[i].Icon ~= nil
			tab.Size = UDim2.fromOffset(tabW, hitH)
			tab.Art.Size = UDim2.fromOffset(tabW, t.tabH)
			tab.Row.Size = UDim2.fromOffset(tabW, t.tabH)
			tab.Row.Position = UDim2.new(0, 0, 0.5, if compact then 0 else -3) -- label cap centre y 177: 3 px above the tab centre
			tab.Row.UIListLayout.Padding = UDim.new(0, t.iconGap)
			tab.Row.Icon.Size = UDim2.fromOffset(icon, icon)
			tab.Row.Icon.Visible = hasIcon and tabW >= 150
			local room = tabW - (if compact then 16 else 24) - (if hasIcon and tabW >= 150 then icon + t.iconGap else 0)
			tab.Row.Label.UISizeConstraint.MaxSize = Vector2.new(room, t.tabH)
			labelSize = math.min(labelSize, Parts.fitSize(tab.Row.Label.Text, room, t.tabText, 15))
		end
		for _, tab in self._tabButtons do
			tab.Row.Label.TextSize = labelSize
		end
		self._tabH = t.tabH
		self:_skinTabs()
	end
	self._fit = fit
	table.insert(conns, {
		Disconnect = SettingsLogic.onChanged(function(id)
			if id == "uiScale" and bag.Visible then
				fit()
			end
		end),
	})
	table.insert(conns, parent:GetAttributeChangedSignal("EmulateSize"):Connect(fit))
	table.insert(
		conns,
		bag:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:Fit()
		end)
	)
	return self
end

-- Per-tab detail panel width (Full tier); nil = the default.
function Shell:SetDetailWidth(w: number?)
	if self._detailW ~= w then
		self._detailW = w
		self:Fit()
	end
end

-- The action row above the detail panel shows/hides (Full tier only; phones keep the full-height panel).
function Shell:SetTopBar(on: boolean)
	if self._topOn ~= on then
		self._topOn = on
		self:Fit()
	end
end

function Shell:Fit()
	self._fit()
end

-- One tab's art: selected (underline) wins; else pressed / hover / normal. tab.Disabled uses the disabled art.
function Shell:_skinTab(i: number)
	local btn, def = self._tabButtons[i], self._tabs[i]
	local key = if def.Disabled
		then "TabDisabled"
		elseif i == self._tab then "TabSelected"
		elseif self._tabState[i] == "Pressed" then "TabPressed"
		elseif self._tabState[i] == "Hover" then "TabHover"
		else "Tab"
	local h = self._tabH or TIER.Full.tabH
	Parts.skinH(btn.Art, Shared[key], h) -- height = shown height: SliceScale = h / native h, nothing stretches vertically
end

function Shell:_skinTabs()
	for i in self._tabButtons do
		self:_skinTab(i)
	end
end

-- tabs: { {Id, Label, Icon (BagSprites key or id), Disabled?} }
function Shell:SetTabs(tabs)
	for _, b in self._tabButtons do
		b:Destroy()
	end
	table.clear(self._tabButtons)
	self._tabs, self._tabState = tabs, {}
	for i, tab in tabs do
		local btn = make("ImageButton", {
			Name = "Tab" .. i,
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Size = UDim2.fromOffset(254, 54),
			ZIndex = Z + 4,
		}, self.TabBar)
		make("ImageLabel", {
			Name = "Art",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(254, 54),
			ZIndex = Z + 4,
		}, btn)
		self._tabButtons[i] = btn
		Parts.interact(btn, function(state)
			self._tabState[i] = state
			if self._tabButtons[i] == btn then
				self:_skinTab(i)
			end
		end)
		local row = make("Frame", {
			Name = "Row",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = Z + 5,
		}, btn)
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}, row)
		local icon = make("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(30, 30),
			LayoutOrder = 1,
			ZIndex = Z + 6,
		}, row)
		if tab.Icon then
			Parts.image(icon, tab.Icon)
		end
		local label = Parts.text(row, {
			Name = "Label",
			Text = tab.Label,
			TextSize = 24,
			LayoutOrder = 2,
			ZIndex = Z + 6,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 40),
		}, 3)
		make("UISizeConstraint", {}, label) -- caps the width so long labels truncate; the icon+label group stays centred
		table.insert(
			self._conns,
			btn.Activated:Connect(function()
				self:SetTab(i)
			end)
		)
	end
	self._tab = 0
	self:Fit()
end

-- Cheap and idempotent: only the tab sprites change; callbacks fire when the index changes.
function Shell:SetTab(i: number)
	if i == self._tab or not self._tabButtons[i] then
		return
	end
	self._tab = i
	self:_skinTabs()
	for _, cb in self._onTab do
		cb(i)
	end
end

function Shell:GetTab(): number
	return self._tab
end

function Shell:OnTab(cb)
	table.insert(self._onTab, cb)
end

function Shell:OnClose(cb)
	table.insert(self._onClose, cb)
end

function Shell:IsOpen(): boolean
	return self.Bag.Visible
end

function Shell:Open()
	if self.Bag.Visible then
		return
	end
	UiSounds.MenuOpened()
	self.Bag.Visible = true -- before Fit (same frame, no flash): only a visible menu places the shared bag row
	self:Fit()
	if SettingsLogic.get("reducedMotion") then
		self._pop.Scale = 1
		return
	end
	self._pop.Scale = 0.94
	self._popTween = TweenService:Create(self._pop, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1 })
	self._popTween:Play()
end

function Shell:Close()
	if not self.Bag.Visible then
		return
	end
	if self._popTween then
		self._popTween:Cancel()
	end
	self._pop.Scale = 1
	local focused = UserInputService:GetFocusedTextBox()
	if focused and focused:IsDescendantOf(self.Bag) then
		focused:ReleaseFocus()
	end
	self.Bag.Visible = false
	UiSounds.MenuClosed()
	self.CloseButton:SetAttribute("DebugState", nil) -- a hidden Hit may miss MouseLeave: never reopen with the X stuck in Hover / Pressed
	for _, cb in self._onClose do
		cb()
	end
end

function Shell:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	if self._popTween then
		self._popTween:Cancel()
	end
	self.Bag:Destroy()
end

return Shell
