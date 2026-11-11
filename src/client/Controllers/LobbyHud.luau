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
local GEM_TEXT = Color3.fromRGB(247, 142, 236)
local DESIGN = Vector2.new(1672, 941)
local CELL = Vector2.new(124, 114)
local MARGIN = 20 -- side safe margin
local PROFILE_H = 44 + 24 + 12 + 6 * 2
local DECK_H = 110
local BOTTOM_H = PROFILE_H + DECK_H + 6
local BOTTOM_GAP = 18 -- design px from the bottom edge to the Bottom block

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
	local content = make("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, btn)
	list(content, Enum.FillDirection.Vertical, 0)
	-- Fixed-size holder: the list lays out scaled sizes, so scaling the icon directly would move the label.
	local holder = make("Frame", {
		Name = "IconHolder",
		BackgroundTransparency = 1,
		Size = o.IconSize or UDim2.fromOffset(88, 78),
		LayoutOrder = 1,
	}, content)
	local icon = make("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Image = o.Icon,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, holder)
	local scale = make("UIScale", {}, icon)
	local label
	if o.Label then
		label = text({
			Name = "Label",
			Text = o.Label,
			TextColor3 = UiKit.WHITE,
			TextSize = 28,
			Size = UDim2.fromOffset(CELL.X, 30),
			LayoutOrder = 2,
		}, content)
		outline(label, 3)
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
		TextSize = 36,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 44),
		LayoutOrder = 2,
	}, box)
	outline(label, 3)
	return label
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
	local xpSize -- UITextSizeConstraint of the XP text, set below
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
			self:SetBagMode(true) -- re-apply the phone-height Bottom rule after a resize/rotation
		end
		if xpSize then
			-- The constraint works in on-screen px (after UIScale): 24 design px (glyphs ~60% of the
			-- reference's XP text), never under 11 px.
			xpSize.MinTextSize = 11
			xpSize.MaxTextSize = math.max(11, math.floor(24 * s + 0.5))
		end
	end
	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	parent:GetAttributeChangedSignal("EmulateSize"):Connect(rescale)
	rescale()

	local grid = make("Frame", {
		Name = "LeftGrid",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, MARGIN + CELL.X, 0.5, 0),
		Size = UDim2.fromOffset(CELL.X * 2, CELL.Y * 3),
	}, hud)
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(CELL.X, CELL.Y),
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
	for i, t in left do
		local btn =
			iconButton(grid, { Name = t[1], Order = i, Icon = t[2], Label = string.upper(t[1]), OnClick = t[3] })
		if t[1] == "Bag" then
			self.BagButton = btn
		end
	end

	local quests = iconButton(hud, {
		Name = "Quests",
		Icon = I.Quests,
		Label = "QUESTS",
		OnClick = function()
			open("Quests")
		end,
	})
	quests.Position = UDim2.new(1, -(MARGIN + CELL.X / 2), 0.5, 0)

	-- 88 px hit area, 60 px icon, no label.
	local gear = iconButton(hud, {
		Name = "Gear",
		Icon = I.Settings,
		IconSize = UDim2.fromOffset(60, 60),
		Size = UDim2.fromOffset(88, 88),
		OnClick = soon("Settings"),
	})
	gear.Position = UDim2.new(1, -60, 0, 60)

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
	list(profile, Enum.FillDirection.Vertical, 6)

	local currencies = make("Frame", {
		Name = "Currencies",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(416, 44), -- two 200 boxes mirrored about the axis; 200 fits "9,999,999"
		LayoutOrder = 1,
	}, profile)
	list(currencies, Enum.FillDirection.Horizontal, 16)
	self.GoldLabel = counter(currencies, 1, Sprites.Coin, formatGold(0), GOLD_TEXT)
	-- Placeholder: the server sends no gems yet.
	self.GemLabel = counter(currencies, 2, Sprites.Gem, "\u{2014}", GEM_TEXT)
	self.GemLabel:SetAttribute("Placeholder", true)

	-- Sits above the bar; TextScaled + the constraint set in rescale keep it >= 11 physical px.
	local xpText = text({
		Name = "XpLabel",
		Text = "LVL \u{2014}", -- Placeholder: no level/XP from the server yet
		TextColor3 = UiKit.WHITE,
		TextScaled = true,
		Size = UDim2.fromOffset(584, 24),
		LayoutOrder = 2,
	}, profile)
	xpSize = make("UITextSizeConstraint", {}, xpText)
	outline(xpText, 2)
	xpText:SetAttribute("Placeholder", true)
	rescale()

	local xp = make("Frame", {
		Name = "XpBar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(584, 12),
		LayoutOrder = 3,
	}, profile)
	make("ImageLabel", {
		Name = "Track",
		BackgroundTransparency = 1,
		Image = Sprites.XpTrack, -- 1024x47 export, pill caps ~23 px
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(24, 23, 1000, 24),
		SliceScale = 12 / 47,
		Size = UDim2.fromScale(1, 1),
	}, xp)
	local interior = make("Frame", {
		Name = "Interior",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
	}, xp)
	self.XpClip = make("Frame", {
		Name = "Fill",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.fromScale(0, 1), -- Placeholder: no XP data yet, so 0 fill
	}, interior)
	self.XpClip:SetAttribute("Placeholder", true)
	make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = Sprites.XpFill, -- 1016x32
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(16, 15, 1000, 16),
		SliceScale = 8 / 32,
		Size = UDim2.fromOffset(580, 8), -- full interior so the rounded cap never squashes
	}, self.XpClip)

	local deck = make("Frame", {
		Name = "DeckBar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(584, DECK_H),
		LayoutOrder = 2,
	}, bottom)
	self.DeckBar = deck
	list(deck, Enum.FillDirection.Horizontal, 6)
	self.Slots = {}
	for i = 1, 5 do
		local slot = make("ImageButton", {
			Name = "Slot" .. i,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Image = F.Normal,
			ScaleType = Enum.ScaleType.Stretch,
			Size = UDim2.fromOffset(112, DECK_H),
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

-- Bag open: the deck row hides, the currency/XP block drops to the bottom margin and BAG keeps the hover look.
function LobbyHud:SetBagMode(on: boolean)
	self.BagOn = on
	local h = if on then PROFILE_H else BOTTOM_H
	self.DeckBar.Visible = not on
	self.Bottom.Visible = not (on and UiKit.screenSize(self.Hud.Parent).Y < UiKit.PHONE_H) -- phones: the bag takes that strip too
	self.Bottom.Size = UDim2.fromOffset(584, h)
	self.Bottom.Position = UDim2.new(0.5, 0, 1, -(BOTTOM_GAP + h / 2))
	self.BagButton:SetAttribute("DebugState", if on then "Hover" else nil)
	self.BagButton.Content.Label.TextColor3 = if on then GOLD_TEXT else UiKit.WHITE -- selected: gold label + held hover scale
end

-- Real px (Root space) the bag window must stay clear of: icon columns on the left, the Bottom block's top in bag mode.
function LobbyHud:GetBagInsets()
	local size, s = UiKit.screenSize(self.Hud.Parent), self.UiScale.Scale
	return {
		leftReal = if size.Y < UiKit.PHONE_H then 144 * s - 2 else 245 * s,
		bottomTopReal = if size.Y < UiKit.PHONE_H then size.Y else size.Y - (BOTTOM_GAP + PROFILE_H) * s,
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
