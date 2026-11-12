-- Lobby HUD: borderless icons, inline counters, XP line and framed dice slots laid out in design px (1672x941) under one UIScale (no Init/Start).
-- LobbyHud.build(parent, { open = (panel) -> (), toast = (text) -> () }) -> hud; hud:SetGold(n), hud:SetDeck(ids).

local ContentProvider = game:GetService("ContentProvider")

local UiKit = require(script.Parent.UiKit)
local Sprites = require(script.Parent.Sprites)
local Display = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Display"))

local make = UiKit.make
local FONT = Enum.Font.FredokaOne
-- Sampled from reference.png: near-black outline on all HUD text, gold / pink currency numbers.
local STROKE = Color3.fromRGB(9, 14, 24)
local GOLD_TEXT = Color3.fromRGB(249, 199, 53)
local GEM_TEXT = Color3.fromRGB(243, 89, 232)
local DIM = Color3.fromRGB(180, 180, 182) -- ~70% tint of the HUD icons/labels behind the bag (ref #B1B1B3 / #B4AFB4)
local SELECTED_LABEL = Color3.fromRGB(236, 234, 236) -- the open menu's label stays light (ref #ECEAEC)
local DESIGN = Vector2.new(1672, 941)
-- XP bar: design height / track export height (24) is the slice scale; the fill uses the same scale.
local XP_FILL_CAPS = 112 - (89 - 24) -- narrowest fill: both caps, export px
local XP_FILL_PAD = 3.95 -- fill box inset from each end of the track, export px, so the pill sits inside the rim (manifest XpFill.pad)
local BAG_ROW = Vector2.new(880, 50) -- bag-mode bottom row (reference x 405-1285, y 872-922)
local CELL = Vector2.new(124, 114)
-- Left grid and QUESTS always use the menu references' size (pitch 104x110, centre x 114): nothing moves when a menu opens.
local BAG_CELL, BAG_GRID_X, BAG_ICON_SCALE = UDim2.fromOffset(104, 110), 114, 0.88
-- Icon art drawn at ref ink size: design px per export px (export 256 wide; the sprite margin is ~5 export px).
local ICON_ART = {
	Roll = Vector2.new(256, 185) * 0.415,
	Bag = Vector2.new(256, 239) * 0.345,
}
local LABEL_Y = 89.5 -- label centre in the 114 px cell (ref label rows y 432 / 547 / 660)
local PROFILE_H = 44 + 36 + 12 -- currencies, gap, XP bar (LVL / XP text overlays the bar)
local DECK_H = 105
local BOTTOM_H = PROFILE_H + DECK_H + 6
local BOTTOM_GAP = 21 -- design px from the bottom edge to the Bottom block

local LobbyHud = {}
LobbyHud.__index = LobbyHud

-- 2450 -> "2,450"; from 10,000,000 up 12.3M / 1.2B (decimal drops when 0, rounded down).
local function formatGold(value: number?): string
	local n = math.max(0, math.floor(value or 0))
	if n < 1e7 then
		return (tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
	end
	local div, suffix = 1e6, "M"
	if n >= 1e9 then
		div, suffix = 1e9, "B"
	end
	local tenths = math.floor(n / div * 10) / 10
	return (if tenths >= 100 or tenths % 1 == 0 then ("%d"):format(tenths) else ("%.1f"):format(tenths)) .. suffix
end

local function text(props, parent)
	props.BackgroundTransparency = 1
	props.Font = FONT
	props.TextXAlignment = Enum.TextXAlignment.Center
	props.TextYAlignment = Enum.TextYAlignment.Center
	return make("TextLabel", props, parent)
end

local function outline(label, thickness)
	make("UIStroke", { Color = STROKE, Thickness = thickness, LineJoinMode = Enum.LineJoinMode.Round }, label)
end

-- Centre-out stack: every layout centres its children on both axes.
local function list(parent, direction, padding)
	make("UIListLayout", {
		FillDirection = direction,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, padding),
	}, parent)
end

-- Borderless icon + outlined label. The transparent button is the whole touch target; Icon scales.
local function iconButton(parent, o)
	local btn = make("ImageButton", {
		Name = o.Name,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = o.Size or UDim2.fromOffset(CELL.X, CELL.Y),
		LayoutOrder = o.Order or 0,
		ZIndex = 2,
	}, parent)
	local content = make("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, btn)
	make("UIScale", { Name = "BagScale", Scale = o.Scale or 1 }, content)
	-- Fixed-size holder, absolutely placed: scaling the icon directly would move the label.
	local holder = make("Frame", {
		Name = "IconHolder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = if o.Label then UDim2.new(0.5, 0, 0, 40) else UDim2.fromScale(0.5, 0.5),
		Size = o.IconSize or UDim2.fromOffset(88, 78),
	}, content)
	local icon = make("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Image = o.Icon,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = if o.Art then UDim2.fromOffset(o.Art.X, o.Art.Y) else UDim2.fromScale(1, 1),
	}, holder)
	local scale = make("UIScale", {}, icon)
	local label
	if o.Label then
		label = text({
			Name = "Label",
			Text = o.Label,
			TextColor3 = UiKit.WHITE,
			TextSize = 37,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, LABEL_Y + (o.LabelDrop or 0)),
			Size = UDim2.fromOffset(o.LabelW or CELL.X, 40),
		}, content)
		outline(label, 4)
	end
	UiKit.wire(btn, function(state)
		local on = btn.Interactable
		icon.ImageTransparency = if on then 0 else 0.45
		if label then
			label.TextTransparency = if on then 0 else 0.4
		end
		scale.Scale = if not on then 1 elseif state == "Pressed" then 0.92 elseif state == "Hover" then 1.06 else 1
	end)
	btn.Activated:Connect(o.OnClick)
	return btn
end

local function counter(parent, order, iconId, str, color)
	local box =
		make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 44), LayoutOrder = order }, parent)
	list(box, Enum.FillDirection.Horizontal, 8)
	make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = iconId,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(44, 44),
		LayoutOrder = 1,
	}, box)
	local label = text({
		Text = str,
		TextColor3 = color,
		TextSize = 43,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 44),
		LayoutOrder = 2,
	}, box)
	outline(label, 3)
	return label, box
end

function LobbyHud.build(parent, cb)
	local self = setmetatable({}, LobbyHud)
	local open, toast = cb.open, cb.toast
	local function soon(name)
		return function()
			toast(name .. ": coming soon")
		end
	end

	-- State frames aren't on screen until hover/press: preload so the first swap doesn't flash blank.
	local F = Sprites.Frame
	task.spawn(ContentProvider.PreloadAsync, ContentProvider, { F.Pressed, F.Highlighted, F.Disabled })

	local hud = make("Frame", { Name = "Hud", BackgroundTransparency = 1 }, parent)
	self.Hud = hud
	local uiScale = make("UIScale", {}, hud)
	self.UiScale = uiScale
	local function rescale()
		local size = UiKit.screenSize(parent)
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local s = math.min(size.X / DESIGN.X, size.Y / DESIGN.Y)
		-- Phone floor: 124x114 cells stay 62x57 and labels ~14 px; the regions still clear each other down to 568x276.
		if size.Y < UiKit.PHONE_H then
			s = math.max(s, 0.5)
		end
		s = math.min(s, 1.5)
		uiScale.Scale = s
		hud.Size = UDim2.fromScale(1 / s, 1 / s)
		if self.BagOn then
			self:SetBagMode(true, self.BagMenu) -- re-apply the phone-height Bottom rule after a resize/rotation
		end
	end
	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	parent:GetAttributeChangedSignal("EmulateSize"):Connect(rescale)
	rescale()

	local grid = make("Frame", {
		Name = "LeftGrid",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, BAG_GRID_X, 0.5, 38),
		Size = UDim2.fromOffset(CELL.X * 2, CELL.Y * 3),
	}, hud)
	self.LeftGrid = grid
	self.LeftCells = make("UIGridLayout", {
		CellSize = BAG_CELL,
		CellPadding = UDim2.fromOffset(0, 0),
		FillDirectionMaxCells = 2,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	local I = Sprites.Icon
	local left = {
		{ "Shop", I.Shop, soon("Shop") },
		{ "Roll", I.Roll, soon("Roll") },
		{
			"Bag",
			I.Bag,
			function()
				open("Bag")
			end,
		},
		{
			"Play",
			I.Play,
			function()
				open("Play")
			end,
		},
		{ "Codes", I.Codes, soon("Codes") },
		{ "Daily", I.Daily, soon("Daily") },
	}
	local buttons = {} -- by name: the open menu's button is highlighted (SetBagMode)
	for i, t in left do
		buttons[t[1]] = iconButton(grid, {
			Name = t[1],
			Order = i,
			Icon = t[2],
			Label = string.upper(t[1]),
			OnClick = t[3],
			Art = ICON_ART[t[1]],
			Scale = BAG_ICON_SCALE,
		})
	end

	local quests = iconButton(hud, {
		Name = "Quests",
		Icon = I.Quests,
		Label = "QUESTS",
		LabelW = 140, -- QUESTS at 37 px is wider than the cell: the box needs slack for TextFits
		Size = BAG_CELL, -- same cell, icon box and scale as the left grid icons
		Scale = BAG_ICON_SCALE,
		OnClick = function()
			open("Quests")
		end,
	})
	-- mirrors the left grid's outer column; QUESTS is ~16 px wider than CODES, so +8 keeps the same outer label gap
	quests.Position = UDim2.new(1, -(BAG_GRID_X - BAG_CELL.X.Offset / 2 + 8), 0.5, 20)
	buttons.Quests = quests
	self.Buttons = buttons

	-- 88 px hit area, 60 px icon, no label.
	local gear = iconButton(hud, {
		Name = "Gear",
		Icon = I.Settings,
		IconSize = UDim2.fromOffset(60, 59.4), -- visible gold 51x52 (the recoloured cog shows ~0.86 of its box)
		Size = UDim2.fromOffset(88, 88),
		OnClick = soon("Settings"),
	})
	gear.Position = UDim2.new(1, -60, 0, 60.5)
	self.Gear, self.Quests = gear, quests

	local bottom = make("Frame", {
		Name = "Bottom",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -(BOTTOM_GAP + BOTTOM_H / 2)),
		Size = UDim2.fromOffset(584, BOTTOM_H),
	}, hud)
	self.Bottom = bottom
	list(bottom, Enum.FillDirection.Vertical, 6)

	-- One hit area over currencies + XP bar opens Profile.
	local profile = make("TextButton", {
		Name = "ProfileHit",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(584, PROFILE_H),
		LayoutOrder = 1,
		ZIndex = 1,
	}, bottom)
	profile.Activated:Connect(function()
		open("Profile")
	end)
	list(profile, Enum.FillDirection.Vertical, 36)

	local currencies = make("Frame", {
		Name = "Currencies",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(416, 44), -- two 200 boxes mirrored about the axis; 200 fits "9,999,999"
		LayoutOrder = 1,
	}, profile)
	list(currencies, Enum.FillDirection.Horizontal, 16)
	local goldBox, gemBox
	self.GoldLabel, goldBox = counter(currencies, 1, Sprites.Coin, formatGold(0), GOLD_TEXT)
	-- Placeholder: the server sends no gems yet.
	self.GemLabel, gemBox = counter(currencies, 2, Sprites.Gem, "\u{2014}", GEM_TEXT)
	self.GemLabel:SetAttribute("Placeholder", true)

	local xp = make("Frame", {
		Name = "XpBar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(584, 12),
		LayoutOrder = 2,
	}, profile)
	self.XpTrack = make("ImageLabel", {
		Name = "Track",
		BackgroundTransparency = 1,
		Image = Sprites.XpTrack, -- 143x24 export, caps 22 / 49 px (the right cap keeps the rim's glints)
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(22, 10, 94, 14),
		Size = UDim2.fromScale(1, 1),
	}, xp)
	-- Fill is sized to the value (never cropped), at the track's SliceScale and never narrower than its caps.
	self.XpFill = make("ImageLabel", {
		Name = "Fill",
		BackgroundTransparency = 1,
		Image = Sprites.XpFill, -- 112x16 export
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(24, 7, 89, 9),
		AnchorPoint = Vector2.new(0, 0.5),
		Visible = false,
	}, xp)
	self.XpFill:SetAttribute("Placeholder", true)
	self.XpFraction = 0 -- Placeholder: no XP data yet, so 0 fill (hidden)
	self.XpBar = xp

	-- LVL / XP text: one centred group. HUD: overlaid on the thin bar (reference y 784-806); bag row: inline, left of the bar.
	local xpText = make("Frame", {
		Name = "XpText",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -9.5),
		Size = UDim2.fromOffset(584, 30),
		ZIndex = 3,
	}, xp)
	list(xpText, Enum.FillDirection.Horizontal, 32)
	local function xpLabel(name, str, order)
		local l = text({
			Name = name,
			Text = str,
			TextColor3 = UiKit.WHITE,
			TextSize = 37, -- white-fill ~23 as in the HUD ref; bag mode drops to 32
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 40),
			LayoutOrder = order,
			ZIndex = 3,
		}, xpText)
		outline(l, 3)
		l:SetAttribute("Placeholder", true) -- no level/XP from the server yet
		return l
	end
	self.LvlLabel = xpLabel("LvlLabel", "LVL \u{2014}", 1)
	self.XpLabel = xpLabel("XpLabel", "\u{2014} / \u{2014} XP", 2)

	-- Bag-mode bottom row: the same objects re-parented into one inline centred row (SetBagMode). It is a
	-- hit area like ProfileHit, so tapping the currencies / XP opens Profile with the bag open too.
	local row = make("TextButton", {
		Name = "BagRow",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -(BOTTOM_GAP - 2 + BAG_ROW.Y / 2) - 4.5), -- ref content centre y 893.5
		Size = UDim2.fromOffset(BAG_ROW.X, BAG_ROW.Y),
		Visible = false,
	}, hud)
	list(row, Enum.FillDirection.Horizontal, 43)
	row.Activated:Connect(function()
		open("Profile")
	end)
	local divider = make("Frame", {
		Name = "Divider",
		BackgroundColor3 = Color3.fromRGB(240, 240, 240),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(4, 36),
		LayoutOrder = 2,
	}, row)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, divider)
	-- LVL / XP text and bar sit 10 px apart (the row's own 43 px padding is for the other gaps).
	local group = make("Frame", {
		Name = "XpGroup",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 50),
		LayoutOrder = 3,
		Visible = false,
	}, row)
	list(group, Enum.FillDirection.Horizontal, 9)
	self.XpGroup = group
	self.BagRow, self.Profile, self.Currencies, self.XpText = row, profile, currencies, xpText
	self.CounterBoxes = { goldBox, gemBox }
	self:_layoutXp(584, 12)

	local deck = make("Frame", {
		Name = "DeckBar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(584, DECK_H),
		LayoutOrder = 2,
	}, bottom)
	self.DeckBar = deck
	list(deck, Enum.FillDirection.Horizontal, -2.2) -- pitch 116.5; boxes overlap their transparent margins
	self.Slots = {}
	for i = 1, 5 do
		local slot = make("ImageButton", {
			Name = "Slot" .. i,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Image = F.Normal,
			ScaleType = Enum.ScaleType.Stretch,
			Size = UDim2.fromOffset(118.7, 116), -- visible rim 110x105 (the sprite shows 0.927 x 0.905 of its box)
			LayoutOrder = i,
			ZIndex = 2,
		}, deck)
		slot:SetAttribute("Empty", true)
		local icon = make("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(80, 80),
			Visible = false,
			ZIndex = 3, -- Lobby gui uses Global ZIndex: must beat the slot's 2 to draw over its frame
		}, slot)
		local refresh = UiKit.wire(slot, function(state)
			slot.Image = if slot:GetAttribute("Empty")
				then F.Disabled
				elseif state == "Pressed" then F.Pressed
				elseif state == "Hover" then F.Highlighted
				else F.Normal
		end)
		slot:GetAttributeChangedSignal("Empty"):Connect(refresh)
		slot.Activated:Connect(function()
			open("Deck")
		end)
		self.Slots[i] = icon
	end
	return self
end

-- XP track + fill for a w x h bar (design px): slice scale = h / 24 (track export height), fill inset by the manifest pad.
function LobbyHud:_layoutXp(w: number, h: number)
	local k = h / 24
	self.XpTrack.SliceScale = k
	self.XpFill.SliceScale = k
	self.XpFill.Position = UDim2.new(0, XP_FILL_PAD * k, 0.5, 0)
	self.XpFill.Size = UDim2.fromOffset(math.max(XP_FILL_CAPS * k, (w - 2 * XP_FILL_PAD * k) * self.XpFraction), 16 * k)
	self.XpFill.Visible = self.XpFraction > 0
end

-- A menu open: the deck row and Bottom block hide; currencies, LVL / XP text and the XP bar are re-parented into one
-- inline centred row (reference y 872-922). Phones: the menu takes that strip too, so the row hides.
-- menu = the HUD button of the open menu ("Bag", "Play", "Quests", "Roll"): it keeps the hover look, the rest dim.
function LobbyHud:SetBagMode(on: boolean, menu: string?)
	self.BagOn, self.BagMenu = on, menu
	local phone = UiKit.screenSize(self.Hud.Parent).Y < UiKit.PHONE_H
	self.DeckBar.Visible = not on
	self.Bottom.Visible = not on
	self.BagRow.Visible = on and not phone
	local currencies, xpText, xp = self.Currencies, self.XpText, self.XpBar
	local currencyList = currencies:FindFirstChildOfClass("UIListLayout")
	if on then
		currencies.Parent, xpText.Parent, xp.Parent = self.BagRow, self.XpGroup, self.XpGroup
		self.XpGroup.Visible = true
		currencies.LayoutOrder, xpText.LayoutOrder, xp.LayoutOrder = 1, 1, 2
		currencies.AutomaticSize, currencies.Size = Enum.AutomaticSize.X, UDim2.fromOffset(0, 44)
		currencyList.Padding = UDim.new(0, 54)
		for _, box in self.CounterBoxes do
			box.AutomaticSize, box.Size = Enum.AutomaticSize.X, UDim2.fromOffset(0, 44)
		end
		xpText.AutomaticSize, xpText.Size = Enum.AutomaticSize.X, UDim2.fromOffset(0, 40)
		self.LvlLabel.TextSize, self.XpLabel.TextSize = 32, 32
		xpText.Position = UDim2.new()
		xpText.UIListLayout.Padding = UDim.new(0, 30)
		xp.Size = UDim2.fromOffset(189.3, 29.3) -- ink 182x22 (export margin 3 px, slice scale 1.22)
		self:_layoutXp(189.3, 29.3)
	else
		currencies.Parent, xp.Parent = self.Profile, self.Profile
		xpText.Parent = xp
		self.XpGroup.Visible = false
		self.LvlLabel.TextSize, self.XpLabel.TextSize = 37, 37
		for _, l in { self.LvlLabel, self.XpLabel } do -- AutomaticSize keeps the old TextSize width: force a re-measure
			l.AutomaticSize = Enum.AutomaticSize.None
			l.Size = UDim2.fromOffset(l.TextBounds.X, 40)
			task.defer(function()
				l.AutomaticSize = Enum.AutomaticSize.X
			end)
		end
		currencies.LayoutOrder, xp.LayoutOrder = 1, 2
		currencies.AutomaticSize, currencies.Size = Enum.AutomaticSize.None, UDim2.fromOffset(416, 44)
		currencyList.Padding = UDim.new(0, 16)
		for _, box in self.CounterBoxes do
			box.AutomaticSize, box.Size = Enum.AutomaticSize.None, UDim2.fromOffset(200, 44)
		end
		xpText.AutomaticSize, xpText.Size = Enum.AutomaticSize.None, UDim2.fromOffset(584, 40)
		xpText.Position = UDim2.new(0.5, 0, 0.5, -9.5)
		xpText.UIListLayout.Padding = UDim.new(0, 32)
		xp.Size = UDim2.fromOffset(584, 12)
		self:_layoutXp(584, 12)
	end
	self.LeftGrid.Visible = not (on and phone) -- the modal menu covers column 2 on phones: hide the grid, restore on close
	-- HUD behind the menu is dimmed to ~70%; the open menu's label stays light and holds the hover scale.
	local selected = on and menu and self.Buttons[menu]
	local all = self.LeftGrid:GetChildren()
	table.insert(all, self.Gear)
	table.insert(all, self.Quests)
	for _, btn in all do
		local c = btn:FindFirstChild("Content")
		if c then
			c.IconHolder.Icon.ImageColor3 = if on and btn ~= selected then DIM else UiKit.WHITE
			local label = c:FindFirstChild("Label")
			if label then
				label.TextColor3 = if btn == selected then SELECTED_LABEL elseif on then DIM else UiKit.WHITE
			end
			btn:SetAttribute("DebugState", if btn == selected then "Hover" else nil)
		end
	end
end

-- Real px (Root space) the bag window must stay clear of: icon columns on the left (the window overlaps the
-- second column's edge as in the reference), the bag-mode row's top at the bottom.
function LobbyHud:GetBagInsets()
	local size, s = UiKit.screenSize(self.Hud.Parent), self.UiScale.Scale
	return {
		leftReal = if size.Y < UiKit.PHONE_H then 144 * s - 2 else 198 * s,
		bottomTopReal = if size.Y < UiKit.PHONE_H then size.Y else size.Y - (BOTTOM_GAP - 2 + BAG_ROW.Y) * s,
	}
end

function LobbyHud:SetGold(gold: number?)
	self.GoldLabel.Text = formatGold(gold)
end

-- ids: array of up to 5 die ids. Mapped dice use their art; others show Icon.Roll tinted by Display colour.
function LobbyHud:SetDeck(ids)
	for i, icon in self.Slots do
		local id = ids and ids[i]
		icon.Parent:SetAttribute("Empty", not id)
		if not id then
			icon.Visible = false
		else
			local art = Sprites.DieArt[id]
			local mapped = art and Sprites.Dice[art]
			if mapped == "" then
				mapped = nil -- not uploaded yet
			end
			local info = Display.Dice[id]
			icon.Visible = true
			icon.Image = mapped or Sprites.Icon.Roll
			icon.ImageColor3 = mapped and UiKit.WHITE or (info and info.Color or UiKit.WHITE)
		end
	end
end

return LobbyHud
