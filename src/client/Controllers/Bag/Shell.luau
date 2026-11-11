-- Bag shell: the one window every tab shares (banner, close, tab bar, panel slots) plus Fit(). Visual only.
-- Design px under one UIScale. Switching tabs never touches anything here except the tab sprites.
-- Shell.new(parent, { fit = () -> { leftReal, bottomTopReal } }) -> shell (see :methods below).

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parts)

local make = UiKit.make
local Z = 20 -- Bag root; Sibling ZIndex (descendants always >= their parent)

-- Window frame (excluding the banner overhang). Full tier = the 1672x941 reference: rim box 1248x761 (x 212, y 97)
-- plus the sprite's transparent margin mx/my. Compact (phones) shrinks to the space. mx/my double as offsets.
-- rim = Window SliceScale (1.0: orange band ~16 px as in the reference; corner radius ~38 vs 45, the art's limit).
local TIER = {
	Full = {
		mx = 6,
		my = 5,
		rim = 1.0,
		over = 88, -- banner top to window frame top
		banner = Vector2.new(406, 144), -- 0.66x the 615x218 art: ribbon ~307x96 vs ref 338x88 (art aspect differs)
		bannerText = 76,
		tabTop = 44, -- from the rim box top (all Full values below are rim-box relative)
		tabH = 62,
		tabGap = 12,
		icon = 38,
		tabText = 34,
		contentTop = 122,
		bottomPad = 28,
		pitch = 142,
	},
	Compact = {
		mx = 0,
		my = 1,
		rim = 0.78,
		over = 46,
		banner = Vector2.new(214, 76),
		bannerText = 34,
		tabText = 24,
		tabTop = 30,
		tabH = 56,
		tabGap = 8,
		icon = 30,
		contentTop = 92,
		bottomPad = 16,
		pitch = 120,
	},
}
local SIDE, GAP = 27, 10 -- rim to panels; between left panel and detail
local FULL_INK = Vector2.new(1248, 761)
local TOOLBAR_H, FOOTER_H = 68, 97
local DETAIL_INSET = 8 -- detail content stops this far above the panel bottom (14 px to the inner rim, as in the reference)
local GRID_INSET = 12 -- GridScroll stops this far above the panel bottom so peeking cards clip inside the rim
local DETAIL_MAX, DETAIL_MIN = 410, 310
local MIN_SCALE, MAX_SCALE = 0.8, 1.5

local Shell = {}
Shell.__index = Shell

function Shell.new(parent, deps)
	local self = setmetatable({}, Shell)
	local conns = {}
	self._conns, self._deps = conns, deps
	self._tab, self._tabs, self._tabButtons = 0, {}, {}
	self._onTab, self._onClose = {}, {}

	local bag = make("Frame", {
		Name = "Bag",
		BackgroundTransparency = 1,
		Active = false,
		Visible = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z,
	}, parent)
	local scaled = make("Frame", { Name = "Scaled", BackgroundTransparency = 1, ZIndex = Z }, bag)
	local uiScale = make("UIScale", { Name = "BagScale" }, scaled)
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

	local chrome = make("ImageLabel", {
		Name = "Chrome",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z + 1,
	}, window)
	Parts.skin(chrome, "Window", TIER.Full.rim)
	self.Chrome = chrome

	-- Content: left column (toolbar, grid, footer) + detail.
	local content = frame("Content", window, Z + 2)
	local left = frame("Left", content, Z + 3)
	local leftPanel = make("ImageLabel", {
		Name = "LeftPanel",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z + 2,
	}, left)
	Parts.skin(leftPanel, "LeftPanel", 0.5)
	local toolbar = frame("Toolbar", left, Z + 5)
	local grid = frame("Grid", left, Z + 3)
	local footer = frame("Footer", left, Z + 14) -- above grid and detail (Global ZIndex gui); below popups (45)
	local detail = make("ImageLabel", {
		Name = "Detail",
		BackgroundTransparency = 1,
		ZIndex = Z + 2,
	}, content)
	Parts.skin(detail, "Detail", 0.5)
	local detailSlot = frame("Slot", detail, Z + 3)
	detailSlot.Size = UDim2.fromScale(1, 1)
	self.LeftPanel, self.Content, self.Left = leftPanel, content, left
	self.Slots = { Toolbar = toolbar, Grid = grid, Footer = footer, Detail = detailSlot }
	self._detail = detail

	-- Tab bar.
	local tabBar = frame("TabBar", window, Z + 3)
	tabBar.AnchorPoint = Vector2.new(0.5, 0)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabBar)
	self.TabBar = tabBar

	-- Banner: one baked sprite (laurels, ribbon, crowned die); only the "BAG" text is live, in the art's free box
	-- (export px x 236-490, y 86-174 of 615x218).
	local banner = make("ImageLabel", {
		Name = "Banner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = Z + 10,
	}, window)
	Parts.skin(banner, "Banner")
	local bannerText = Parts.text(banner, {
		Name = "Text",
		Text = "BAG",
		TextTruncate = Enum.TextTruncate.None,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(354 / 615, 114 / 218), -- ref: BAG ink centre 30 px right of, 7 px above the ribbon centre
		Size = UDim2.fromScale(254 / 615, 88 / 218),
		ZIndex = Z + 11,
	}, 3)
	self.Banner = banner

	local close = make("ImageButton", {
		Name = "Close",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(72, 68),
		ZIndex = Z + 11,
	}, window)
	Parts.skin(close, "Close")
	Parts.interact(close)
	table.insert(
		conns,
		close.Activated:Connect(function()
			self:Close()
		end)
	)
	self.CloseButton = close

	-- Fit ------------------------------------------------------------------------------------------------
	local function fit()
		local size = UiKit.screenSize(parent)
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local ins = deps.fit()
		local availW = size.X - 2 * (ins.leftReal + 8)
		local availH = ins.bottomTopReal - 10 -- region [4, bottomTop - 6]
		local full = TIER.Full
		local fullW, fullH = FULL_INK.X + 2 * full.mx, FULL_INK.Y + 2 * full.my
		local bs = math.clamp(math.min(availW / fullW, availH / (fullH + full.over)), MIN_SCALE, MAX_SCALE)
		uiScale.Scale = bs
		scaled.Size = UDim2.fromScale(1 / bs, 1 / bs)
		local dw, dh = availW / bs, availH / bs -- design px that remain

		-- Tier: compact only for phone-class heights (as the HUD's 500 px rule); desktops stay full and the
		-- grid shows fewer rows (min about one row plus a peek) instead.
		local compact = size.Y < UiKit.PHONE_H
		local t = if compact then TIER.Compact else TIER.Full
		local hf = if compact then math.clamp(dh - t.over, 250, 725) else math.clamp(dh - t.over, 440, fullH)
		local winW = math.min(if compact then 1160 else fullW, dw)
		local side = SIDE + t.mx
		local inner = winW - 2 * side
		local cols = math.clamp(math.floor((inner - GAP - DETAIL_MIN - 10) / t.pitch), 2, 5)
		local leftW = cols * t.pitch + 10
		local detailW = math.min(DETAIL_MAX, inner - GAP - leftW)
		if detailW == DETAIL_MAX then
			leftW = inner - GAP - detailW -- spare width goes to the grid panel (the grid centres its cards)
		else
			winW = 2 * side + GAP + leftW + detailW
		end
		local contentTop, bottomPad = t.contentTop + t.my, t.bottomPad + (if compact then 0 else t.my)
		local contentH = hf - contentTop - bottomPad
		-- Left column is one box on every tab: the panel fills it, minus the footer strip when the Dice footer shows
		-- (compact: the footer overlays the panel bottom).
		local leftH = if compact or not self._footerOn then contentH else contentH - FOOTER_H - GAP

		-- Window centred in the free region.
		local compH = (t.over + hf) * bs
		local top = 4 + ((ins.bottomTopReal - 8) - 4 - compH) / 2
		window.Size = UDim2.fromOffset(winW, hf)
		window.Position = UDim2.new(0.5, 0, 0, (top + t.over * bs + hf * bs / 2) / bs)
		chrome.SliceScale = t.rim

		content.Position = UDim2.fromOffset(side, contentTop)
		content.Size = UDim2.fromOffset(winW - 2 * side, contentH)
		left.Size = UDim2.fromOffset(leftW, contentH)
		leftPanel.Size = UDim2.fromOffset(leftW, leftH)
		toolbar.Size = UDim2.fromOffset(leftW, TOOLBAR_H)
		grid.Position = UDim2.fromOffset(3, TOOLBAR_H)
		grid.Size = UDim2.fromOffset(leftW - 6, leftH - TOOLBAR_H - GRID_INSET)
		-- Compact: an overlay (own strip background) over the panel bottom, wide enough for 5 slots + button;
		-- the controller decides when it is visible (Footer:SetVisible).
		footer.Position = UDim2.fromOffset(0, contentH - FOOTER_H)
		footer.Size = UDim2.fromOffset(leftW, FOOTER_H)
		detail.Position = UDim2.fromOffset(leftW + GAP, 0)
		detail.Size = UDim2.fromOffset(detailW, contentH)
		detailSlot.Size = UDim2.fromOffset(detailW, contentH - DETAIL_INSET) -- offsets: Parts read slot widths in design px
		for _, slotFrame in self.Slots do
			slotFrame:SetAttribute("Compact", compact)
		end
		self.Compact = compact

		banner.Position = UDim2.new(0.5, 0, 0, -t.over)
		banner.Size = UDim2.fromOffset(t.banner.X, t.banner.Y)
		bannerText.TextSize = t.bannerText
		close.Position = UDim2.fromOffset(winW - t.mx - 27, t.my + 5)

		-- Tabs: equal widths; label shrinks (>=15) and the icon drops when very narrow.
		local barW = winW - 2 * (t.mx + 47)
		local n = math.max(1, #self._tabs)
		local tabW = math.floor((barW - (n - 1) * t.tabGap) / n)
		tabBar.Position = UDim2.new(0.5, 0, 0, t.tabTop + t.my)
		tabBar.Size = UDim2.fromOffset(barW, t.tabH)
		tabBar.UIListLayout.Padding = UDim.new(0, t.tabGap)
		for _, tab in self._tabButtons do
			tab.Size = UDim2.fromOffset(tabW, t.tabH)
			tab.Row.Icon.Size = UDim2.fromOffset(t.icon, t.icon)
			tab.Row.Icon.Visible = tabW >= 150
			local avail = tabW - 24 - (if tabW >= 150 then t.icon + 6 else 0)
			tab.Row.Label.UISizeConstraint.MaxSize = Vector2.new(avail, t.tabH)
			Parts.fit(tab.Row.Label, avail, if tabW < 170 then 18 else t.tabText, 15)
		end
		self:_skinTabs()
	end
	self._fit = fit
	table.insert(conns, parent:GetAttributeChangedSignal("EmulateSize"):Connect(fit))
	table.insert(
		conns,
		bag:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:Fit()
		end)
	)
	return self
end

-- The Dice footer strip shows/hides: the left panel gives it room (full tier) or fills the column again.
function Shell:SetFooter(on: boolean)
	if self._footerOn ~= on then
		self._footerOn = on
		self:Fit()
	end
end

function Shell:Fit()
	self._fit()
end

function Shell:_skinTabs()
	local h = TIER[if self.Compact then "Compact" else "Full"].tabH
	for i, tab in self._tabButtons do
		Parts.skinH(tab, if i == self._tab then "TabGold" else "TabPurple", h)
	end
end

-- tabs: { {Id, Label, Icon (BagSprites key or id)} }
function Shell:SetTabs(tabs)
	for _, b in self._tabButtons do
		b:Destroy()
	end
	table.clear(self._tabButtons)
	self._tabs = tabs
	for i, tab in tabs do
		local btn = make("ImageButton", {
			Name = "Tab" .. i,
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Size = UDim2.fromOffset(254, 60),
			ZIndex = Z + 4,
		}, self.TabBar)
		Parts.interact(btn)
		local row = make(
			"Frame",
			{ Name = "Row", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Z + 5 },
			btn
		)
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
			Size = UDim2.fromOffset(36, 36),
			LayoutOrder = 1,
			ZIndex = Z + 6,
		}, row)
		Parts.image(icon, tab.Icon)
		local label = Parts.text(row, {
			Name = "Label",
			Text = tab.Label,
			TextSize = 24,
			LayoutOrder = 2,
			ZIndex = Z + 6,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 40),
		})
		make("UISizeConstraint", {}, label) -- caps the width so long labels truncate; the icon+label group stays centred
		table.insert(
			self._conns,
			btn.Activated:Connect(function()
				self:SetTab(i)
			end)
		)
		self._tabButtons[i] = btn
	end
	self._tab = 0
	self:Fit()
end

-- Cheap and idempotent: only the two tab sprites change; callbacks fire when the index changes.
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
	self:Fit()
	self._pop.Scale = 0.94
	self.Bag.Visible = true
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
