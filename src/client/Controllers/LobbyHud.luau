-- Lobby HUD: sprite tiles laid out in design px (1672x941) under one UIScale (no Init/Start).
-- LobbyHud.build(parent, { open = (panel) -> (), toast = (text) -> () }) -> hud; hud:SetGold(n), hud:SetDeck(ids).

local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")

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
local TILE = 108

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
	return make("TextLabel", props, parent)
end

-- One sprite button: transparent hit area (btn) holding the frame art (frame) with icon + label.
-- Hover (mouse only), press (mouse and touch) and Interactable=false swap the frame sprite.
local function tile(parent, o)
	local btn = make("ImageButton", {
		Name = o.Name,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(TILE, TILE),
		LayoutOrder = o.Order or 0,
		ZIndex = 2,
	}, parent)
	local frame = make("ImageLabel", {
		Name = "Frame",
		BackgroundTransparency = 1,
		Image = Sprites.Frame.Normal,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = o.FrameSize or UDim2.fromScale(1, 1),
	}, btn)
	local scale = make("UIScale", {}, frame)
	local icon = make("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Image = o.Icon or "",
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = o.IconAnchor or Vector2.new(0.5, 0),
		Position = o.IconPos or UDim2.fromScale(0.5, 0.1),
		Size = o.IconSize or UDim2.fromScale(0.6, 0.5),
	}, frame)
	if o.Label then
		local label = text({
			Name = "Label",
			Text = o.Label,
			TextColor3 = UiKit.WHITE,
			TextSize = 26,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -9),
			Size = UDim2.new(1, -8, 0, 30),
		}, frame)
		make("UIStroke", { Color = STROKE, Thickness = 3 }, label)
	end

	local hover, down = false, false
	local function refresh()
		local state = Sprites.Frame.Normal
		if not btn.Interactable then
			state = Sprites.Frame.Disabled
		elseif down then
			state = Sprites.Frame.Pressed
		elseif hover then
			state = Sprites.Frame.Highlighted
		end
		frame.Image = state
		icon.ImageTransparency = if btn.Interactable then 0 else 0.45
		local label = frame:FindFirstChild("Label")
		if label then
			label.TextTransparency = if btn.Interactable then 0 else 0.4
		end
		scale.Scale = (btn.Interactable and down and 0.94) or (btn.Interactable and hover and 1.04) or 1
	end
	local mouseOnly = not UserInputService.TouchEnabled or UserInputService.MouseEnabled
	btn.MouseEnter:Connect(function()
		hover = mouseOnly
		refresh()
	end)
	btn.MouseLeave:Connect(function()
		hover, down = false, false
		refresh()
	end)
	btn.MouseButton1Down:Connect(function()
		down = true
		refresh()
	end)
	btn.MouseButton1Up:Connect(function()
		down = false
		refresh()
	end)
	btn:GetPropertyChangedSignal("Interactable"):Connect(refresh)
	btn.Activated:Connect(o.OnClick)
	return btn, icon
end

local function counter(parent, order, iconId, str, color)
	local box = make("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 46),
		LayoutOrder = order,
	}, parent)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, box)
	make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = iconId,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(46, 46),
		LayoutOrder = 1,
	}, box)
	local label = text({
		Text = str,
		TextColor3 = color,
		TextSize = 40,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 46),
		LayoutOrder = 2,
	}, box)
	make("UIStroke", { Color = STROKE, Thickness = 3 }, label)
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
	local function rescale()
		local size = parent.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local s = math.min(size.X / DESIGN.X, size.Y / DESIGN.Y)
		-- Phone floor: 108-px tiles stay 54 px and labels ~13 px; the regions still clear each other down to 568x276.
		if size.Y < 500 then
			s = math.max(s, 0.5)
		end
		s = math.min(s, 1.5)
		uiScale.Scale = s
		hud.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	rescale()

	local grid = make("Frame", {
		Name = "LeftGrid",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 24, 0.5, 31),
		Size = UDim2.fromOffset(TILE * 2 + 10, TILE * 3 + 8),
	}, hud)
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(TILE, TILE),
		CellPadding = UDim2.fromOffset(10, 4),
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
				open("Collection")
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
		tile(grid, { Name = t[1], Order = i, Icon = t[2], Label = string.upper(t[1]), OnClick = t[3] })
	end

	local quests = tile(hud, {
		Name = "Quests",
		Icon = I.Quests,
		Label = "QUESTS",
		OnClick = function()
			open("Quests")
		end,
	})
	quests.AnchorPoint = Vector2.new(1, 0.5)
	quests.Position = UDim2.new(1, -19, 0.5, 10)

	-- Frame is 56 design px; the transparent 108 button around it is the touch target.
	local gear = tile(hud, {
		Name = "Gear",
		FrameSize = UDim2.fromOffset(56, 56),
		Icon = I.Settings,
		IconAnchor = Vector2.new(0.5, 0.5),
		IconPos = UDim2.fromScale(0.5, 0.5),
		IconSize = UDim2.fromScale(0.64, 0.64),
		OnClick = soon("Settings"),
	})
	gear.AnchorPoint = Vector2.new(1, 0)
	gear.Position = UDim2.new(1, -10, 0, 4) -- visual: right 36, top 30

	local bottom = make("Frame", {
		Name = "Bottom",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -21),
		Size = UDim2.fromOffset(573, 221),
	}, hud)
	-- One hit area over currencies + XP bar opens Profile.
	make("TextButton", {
		Name = "ProfileHit",
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.new(1, 0, 0, 103),
		ZIndex = 1,
	}, bottom).Activated:Connect(function()
		open("Profile")
	end)

	local currencies = make("Frame", {
		Name = "Currencies",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 46),
	}, bottom)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 55),
	}, currencies)
	self.GoldLabel = counter(currencies, 1, Sprites.Coin, formatGold(0), GOLD_TEXT)
	-- Placeholder: the server sends no gems yet.
	self.GemLabel = counter(currencies, 2, Sprites.Gem, "\u{2014}", GEM_TEXT)
	self.GemLabel:SetAttribute("Placeholder", true)

	local xp = make("ImageLabel", {
		Name = "XpBar",
		BackgroundTransparency = 1,
		Image = Sprites.XpTrack,
		ScaleType = Enum.ScaleType.Stretch,
		Position = UDim2.fromOffset(3, 68),
		Size = UDim2.fromOffset(567, 35),
	}, bottom)
	local interior = make("Frame", {
		Name = "Interior",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
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
		Image = Sprites.XpFill,
		ScaleType = Enum.ScaleType.Stretch,
		Size = UDim2.fromOffset(555, 23), -- full interior so the rounded cap never squashes
	}, self.XpClip)
	local xpText = text({
		Name = "Text",
		Text = "LVL \u{2014}", -- Placeholder: no level/XP from the server yet
		TextColor3 = UiKit.WHITE,
		TextSize = 22,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, xp)
	make("UIStroke", { Color = STROKE, Thickness = 2 }, xpText)
	xpText:SetAttribute("Placeholder", true)

	local deck = make("Frame", {
		Name = "DeckBar",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 113),
		Size = UDim2.fromOffset(573, TILE),
	}, bottom)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, deck)
	self.Slots = {}
	for i = 1, 5 do
		local _, icon = tile(deck, {
			Name = "Slot" .. i,
			Order = i,
			IconAnchor = Vector2.new(0.5, 0.5),
			IconPos = UDim2.fromScale(0.5, 0.5),
			IconSize = UDim2.fromScale(0.66, 0.66),
			OnClick = function()
				open("Deck")
			end,
		})
		self.Slots[i] = icon
	end
	return self
end

function LobbyHud:SetGold(gold: number?)
	self.GoldLabel.Text = formatGold(gold)
end

-- ids: array of up to 5 die ids. Mapped dice use their art; others show Icon.Roll tinted by Display colour.
function LobbyHud:SetDeck(ids)
	for i, icon in self.Slots do
		local id = ids and ids[i]
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
