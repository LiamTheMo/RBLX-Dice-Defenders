-- Bag shell: the one window every tab shares (banner, close, tab bar, panel slots) plus Fit(). Visual only.
-- Design px under one UIScale. Switching tabs never touches anything here except the tab sprites.
-- Shell.new(parent, { fit = () -> { leftReal, bottomTopReal } }) -> shell (see :methods below).

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parts)

local make = UiKit.make
local Z = 20 -- Bag root; Sibling ZIndex (descendants always >= their parent)

-- Window (frame, excluding the banner overhang). Full: 1160x725; compact (phones): shrinks to the space.
local FULL_W, FULL_H = 1160, 725
local TIER = {
	Full = {
		over = 90,
		banner = Vector2.new(400, 138),
		bannerText = 68,
		die = 64,
		tabTop = 52,
		tabH = 60,
		tabGap = 16,
		icon = 36,
		contentTop = 120,
		bottomPad = 17,
		pitch = 142,
	},
	Compact = {
		over = 44,
		banner = Vector2.new(200, 69),
		bannerText = 44,
		die = 40,
		tabTop = 30,
		tabH = 56,
		tabGap = 8,
		icon = 30,
		contentTop = 92,
		bottomPad = 16,
		pitch = 120,
	},
}
local SIDE, GAP = 27, 6 -- rim to panels; between left panel and detail
local TOOLBAR_H, FOOTER_H = 68, 92
local GRID_INSET = 12 -- GridScroll stops this far above the panel bottom so peeking cards clip inside the rim
local DETAIL_MAX, DETAIL_MIN = 380, 310
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
	Parts.skin(chrome, "Window", 0.78)

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

	-- Banner: ribbon + crowned die + live text, centred on the window axis.
	local banner = make("ImageLabel", {
		Name = "Banner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = Z + 10,
	}, window)
	Parts.skin(banner, "Ribbon")
	local group = frame("Group", banner, Z + 11)
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.48)
	group.Size = UDim2.fromScale(1, 0.5)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, group)
	local die =
		make("ImageLabel", { Name = "BagDie", BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = Z + 12 }, group)
	Parts.skin(die, "BagDie")
	local bannerText = Parts.text(group, {
		Name = "Text",
		Text = "BAG",
		TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		ZIndex = Z + 12,
	}, 3)
	self.Banner, self.BagDie = banner, die

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
		local availH = ins.bottomTopReal - 12 -- region [4, bottomTop - 8]
		local bs = math.clamp(math.min(availW / FULL_W, availH / (FULL_H + TIER.Full.over)), MIN_SCALE, MAX_SCALE)
		uiScale.Scale = bs
		scaled.Size = UDim2.fromScale(1 / bs, 1 / bs)
		local dw, dh = availW / bs, availH / bs -- design px that remain

		-- Tier: compact only for phone-class heights (as the HUD's 500 px rule); desktops stay full and the
		-- grid shows fewer rows (min about one row plus a peek) instead.
		local compact = size.Y < UiKit.PHONE_H
		local t = if compact then TIER.Compact else TIER.Full
		local hf = if compact then math.clamp(dh - t.over, 250, FULL_H) else math.clamp(dh - t.over, 440, FULL_H)
		local winW = math.min(FULL_W, dw)
		local cols = math.clamp(math.floor((winW - 2 * SIDE - GAP - DETAIL_MIN - 10) / t.pitch), 2, 5)
		local leftW = cols * t.pitch + 10
		local detailW = math.min(DETAIL_MAX, winW - 2 * SIDE - GAP - leftW)
		winW = 2 * SIDE + GAP + leftW + detailW
		local contentH = hf - t.contentTop - t.bottomPad
		local leftH = if compact then contentH else contentH - FOOTER_H - GAP -- compact: the footer overlays the panel bottom

		-- Window centred in the free region.
		local compH = (t.over + hf) * bs
		local top = 4 + ((ins.bottomTopReal - 8) - 4 - compH) / 2
		window.Size = UDim2.fromOffset(winW, hf)
		window.Position = UDim2.new(0.5, 0, 0, (top + t.over * bs + hf * bs / 2) / bs)

		content.Position = UDim2.fromOffset(SIDE, t.contentTop)
		content.Size = UDim2.fromOffset(winW - 2 * SIDE, contentH)
		left.Size = UDim2.fromOffset(leftW, contentH)
		leftPanel.Size = UDim2.fromOffset(leftW, leftH)
		toolbar.Size = UDim2.fromOffset(leftW, TOOLBAR_H)
		grid.Position = UDim2.fromOffset(3, TOOLBAR_H)
		grid.Size = UDim2.fromOffset(leftW - 6, leftH - TOOLBAR_H - GRID_INSET)
		-- Compact: an overlay (own strip background) over the panel bottom, wide enough for 5 slots + button;
		-- the controller decides when it is visible (Footer:SetVisible).
		footer.Position = UDim2.fromOffset(0, if compact then contentH - FOOTER_H else leftH + GAP)
		footer.Size = UDim2.fromOffset(leftW, FOOTER_H)
		detail.Position = UDim2.fromOffset(leftW + GAP, 0)
		detail.Size = UDim2.fromOffset(detailW, contentH)
		detailSlot.Size = UDim2.fromOffset(detailW, contentH) -- offsets: Parts read slot widths in design px
		for _, slotFrame in self.Slots do
			slotFrame:SetAttribute("Compact", compact)
		end
		self.Compact = compact

		banner.Position = UDim2.new(0.5, 0, 0, -t.over)
		banner.Size = UDim2.fromOffset(t.banner.X, t.banner.Y)
		die.Size = UDim2.fromOffset(t.die, t.die)
		bannerText.TextSize = t.bannerText
		bannerText.Size = UDim2.fromOffset(0, t.bannerText + 2)
		close.Position = UDim2.fromOffset(winW - 27, 6)

		-- Tabs: equal widths; label shrinks (>=15) and the icon drops when very narrow.
		local barW = winW - 94
		local n = math.max(1, #self._tabs)
		local tabW = math.floor((barW - (n - 1) * t.tabGap) / n)
		tabBar.Position = UDim2.new(0.5, 0, 0, t.tabTop)
		tabBar.Size = UDim2.fromOffset(barW, t.tabH)
		tabBar.UIListLayout.Padding = UDim.new(0, t.tabGap)
		for _, tab in self._tabButtons do
			tab.Size = UDim2.fromOffset(tabW, t.tabH)
			tab.Row.Icon.Size = UDim2.fromOffset(t.icon, t.icon)
			tab.Row.Icon.Visible = tabW >= 150
			local avail = tabW - 24 - (if tabW >= 150 then t.icon + 6 else 0)
			tab.Row.Label.UISizeConstraint.MaxSize = Vector2.new(avail, t.tabH)
			Parts.fit(tab.Row.Label, avail, if tabW < 170 then 18 else 24, 15)
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
