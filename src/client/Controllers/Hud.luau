-- Match HUD: display only. All state comes from NetClient snapshots; the server decides everything.
-- Thin view over HudLogic (hearts, texts, states, visibility). Laid out in design px (1672x941 mockup:
-- Assets/UI/new/game hud/mockup.png) under one root UIScale; groups hang off the top-centre, top-right and bottom
-- edges, so the centre of the screen (the board) stays clear. State looks (hover, pressed, insufficient, maxed) are
-- drawn in code on the blank tile / pill; no baked state art.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local NetClient = require(script.Parent.NetClient)
local Preload = require(script.Parent.Preload)
local Chrome = require(script.Parent.Bag.Chrome)
local HudLogic = require(script.Parent.HudLogic)
local SharedSprites = require(script.Parent.SharedSprites)
local Sprites = require(script.Parent.Sprites)
local UiKit = require(script.Parent.UiKit)
local Display = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Display"))

local make, label = UiKit.make, UiKit.label
local WHITE, NAVY = UiKit.WHITE, UiKit.NAVY
local FONT = Enum.Font.FredokaOne
local PILL = SharedSprites.PillPurple

local TOASTS = {
	NoMP = "Not enough MP",
	BoardFull = "Board is full",
	IllegalMerge = "Those dice can't merge",
	MaxTier = "Already at max level",
	WrongPhase = "Not available now",
	NotInDeck = "That die isn't in your deck",
	Throttled = "Too fast, try again", -- client throttle is per remote, so a 2nd power-up tap within 0.5 s is dropped
}
local MESSAGES = {
	Loading = "Loading profile\u{2026}",
	Failed = "Couldn't load your save. Rejoin to try again.",
	NotOwner = "This server is in use. Join another server.",
}

-- Layout (design px). Positions are the mockup's pixel-scanned boxes.
local DESIGN = Vector2.new(1672, 941)
local PHONE_FLOOR = 0.55 -- phones: slots stay >= 44 real px and text legible (667x375 still fits the bottom group)
local MAX_SCALE = 1.5
local BAR_K = 717 / 660 -- status bar art (660x74) scaled uniformly
local SLOT_K = 158 / 140 -- upgrade tile art (128x140) scaled uniformly
local SLOT_W, SLOT_H, SLOT_GAP = 128 * SLOT_K, 158, 12
local SUMMON_W, SUMMON_H = 347, 122
local GEAR = 68
local PRESS_NUDGE = 3 -- sheet scale: the pressed row's text sits 3 px lower

local CYAN = Color3.fromRGB(80, 240, 244) -- sampled from the mockup MP text
local INK = Color3.fromRGB(14, 16, 30) -- text outline
local SALMON = Color3.fromRGB(255, 140, 130) -- insufficient MP text
local SALMON_BAR = Color3.fromRGB(206, 84, 84)
local GOLD_TEXT = Color3.fromRGB(250, 215, 130)
local GOLD_BAR = Color3.fromRGB(222, 170, 52)

local Hud = {}

local connections = {}
local gui, ui
local toastToken = 0

local function request(name: string)
	task.spawn(NetClient.Request, name)
end

local function shade(c: Color3, f: number): Color3
	return Color3.new(c.R * f, c.G * f, c.B * f)
end

-- Outlined label centred on its position; text is shrunk to fit maxW (design px) and never clips.
local function text(parent: Instance, props: { [string]: any }, size: number, maxW: number)
	props.BackgroundTransparency = 1
	props.Font = FONT
	props.TextSize = size
	props.TextColor3 = props.TextColor3 or WHITE
	props.AnchorPoint = Vector2.new(0.5, 0.5)
	props.Size = UDim2.fromOffset(maxW, size + 8)
	local t = make("TextLabel", props, parent)
	local stroke = make("UIStroke", { Color = INK, Thickness = 2 }, t)
	stroke:SetAttribute("Rim", 2)
	t:SetAttribute("Base", size)
	t:SetAttribute("MaxW", maxW)
	return t
end

local function setText(t: TextLabel, str: string)
	t.Text = str
	local size, maxW = t:GetAttribute("Base"), t:GetAttribute("MaxW")
	while size > 12 and TextService:GetTextSize(str, size, FONT, Vector2.new(1e5, 1e5)).X > maxW do
		size -= 1
	end
	t.TextSize = size
end

local function bar(parent: Instance, w: number, h: number, x: number, y: number)
	local f = make("Frame", {
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		Visible = false,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, h / 2) }, f)
	return f
end

local function dieIcon(id: string)
	local info = Display.Dice[id]
	local art = Sprites.DieArt[id]
	local mapped = art and Sprites.Dice[art]
	if mapped and mapped ~= "" then
		return mapped, WHITE
	end
	return Sprites.Icon.Roll, info and info.Color or WHITE
end

-- Hover overlay: a lighter wash and a bright rim (ImageColor3 can only darken).
local function glow(parent: Instance, radius: number, inset: number)
	local f = make("Frame", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.new(1, -2 * inset, 1, -2 * inset),
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, f)
	local s = make("UIStroke", { Color = WHITE, Thickness = 3, Transparency = 1 }, f)
	s:SetAttribute("Rim", 3)
	return f, s
end

-- Power-up strip: one tile per deck die, rebuilt only when the deck ids change. Legality is the server's;
-- the insufficient look is a hint from the snapshot's Cost and MP.
local function paintSlot(slot)
	local state = slot.State
	local mode = if state == "idle" then slot.Mode else "Normal"
	slot.Tile.ImageColor3 = if mode == "Pressed" then Color3.fromRGB(170, 170, 180) else WHITE
	slot.Glow.BackgroundTransparency = if mode == "Hover" then 0.88 else 1
	slot.GlowStroke.Transparency = if mode == "Hover" then 0 else 1
	slot.Content.Position = UDim2.fromOffset(0, if mode == "Pressed" then PRESS_NUDGE * SLOT_K else 0)
	slot.Icon.ImageColor3 = if state == "insufficient" then shade(slot.IconColor, 0.55) else slot.IconColor
	slot.Level.Visible = state ~= "maxed"
	slot.Cost.Position = UDim2.fromOffset(SLOT_W / 2, (if state == "maxed" then 102 else 110) * SLOT_K)
	slot.Cost.TextColor3 = if state == "maxed" then GOLD_TEXT elseif state == "insufficient" then SALMON else CYAN
	slot.Bar.Visible = state ~= "idle"
	slot.Bar.BackgroundColor3 = if state == "maxed" then GOLD_BAR else SALMON_BAR
end

local function buildSlot(i: number, id: string)
	local hit = make("TextButton", {
		Name = "PowerUp_" .. id,
		LayoutOrder = i,
		Size = UDim2.fromOffset(SLOT_W, SLOT_H),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	}, ui.Slots)
	local tile = make("ImageLabel", {
		Name = "Tile",
		BackgroundTransparency = 1,
		Image = Sprites.Hud.UpgradeBlank,
		Size = UDim2.fromScale(1, 1),
	}, hit)
	local glowFrame, glowStroke = glow(hit, 30, 4)
	local content = make("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, hit)
	local image, color = dieIcon(id)
	local icon = make("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(SLOT_W / 2, 46),
		Size = UDim2.fromOffset(86, 86),
		Image = image,
		ImageColor3 = color,
		ScaleType = Enum.ScaleType.Fit,
	}, content)
	local level = text(content, { Position = UDim2.fromOffset(SLOT_W / 2, 87 * SLOT_K) }, 32, SLOT_W - 16)
	local cost = text(content, { Position = UDim2.fromOffset(SLOT_W / 2, 110 * SLOT_K) }, 29, SLOT_W - 30)
	local underline = bar(content, 53, 5, SLOT_W / 2, 124 * SLOT_K)
	local slot = {
		Hit = hit,
		Tile = tile,
		Glow = glowFrame,
		GlowStroke = glowStroke,
		Content = content,
		Icon = icon,
		IconColor = color,
		Level = level,
		Cost = cost,
		Bar = underline,
		State = "idle",
		Mode = "Normal",
	}
	UiKit.wire(hit, function(mode)
		slot.Mode = mode
		paintSlot(slot)
	end)
	hit.Activated:Connect(function()
		task.spawn(NetClient.Request, "PowerUp", id)
	end)
	return slot
end

local function renderPowerUps(snap, show: boolean)
	local rows = snap.Tiers or {}
	ui.Slots.Visible = show
	local key = ""
	for _, row in rows do
		key ..= row.Id .. ","
	end
	if ui.SlotKey ~= key then
		ui.SlotKey = key
		for _, slot in ui.SlotList do
			slot.Hit:Destroy()
		end
		table.clear(ui.SlotList)
		for i, row in rows do
			ui.SlotList[row.Id] = buildSlot(i, row.Id)
		end
	end
	for _, row in rows do
		local slot, info = ui.SlotList[row.Id], HudLogic.slotInfo(row, snap.MP)
		slot.State = info.State
		slot.Hit.Active = info.State == "idle"
		setText(slot.Level, info.LevelText)
		setText(slot.Cost, info.CostText)
		paintSlot(slot)
	end
end

local function paintSummon()
	local s = ui.Summon
	local insufficient = s.State == "insufficient"
	local mode = s.Mode
	ui.SummonButton.ImageColor3 = if mode == "Pressed"
		then Color3.fromRGB(205, 190, 225)
		elseif insufficient then Color3.fromRGB(150, 125, 150)
		else WHITE
	s.Glow.BackgroundTransparency = if mode == "Hover" then 0.88 else 1
	s.GlowStroke.Transparency = if mode == "Hover" then 0.3 else 1
	s.Content.Position = UDim2.fromOffset(0, if mode == "Pressed" then PRESS_NUDGE * 1.15 else 0)
	s.Icon.ImageColor3 = if insufficient then Color3.fromRGB(200, 195, 205) else WHITE
	s.Cost.TextColor3 = if insufficient then SALMON else CYAN
	s.Bar.Visible = insufficient
	s.Bar.BackgroundColor3 = Color3.fromRGB(225, 120, 120)
end

local function paintGear()
	local g = ui.Gear
	g.Scale.Scale = if g.Mode == "Pressed" then 0.94 elseif g.Mode == "Hover" then 1.08 else 1
	g.Image.ImageColor3 = if g.Mode == "Pressed" then Color3.fromRGB(200, 200, 210) else WHITE
end

local function setHearts(full: number, empty: number)
	local key = full .. ":" .. empty
	if ui.HeartKey == key then
		return
	end
	ui.HeartKey = key
	for _, child in ui.Hearts:GetChildren() do
		if child:IsA("ImageLabel") then
			child:Destroy()
		end
	end
	local n = full + empty
	local pitch = math.min(41, 150 / math.max(n, 1)) * BAR_K
	local size = math.min(37 * BAR_K, pitch - 2)
	ui.HeartLayout.Padding = UDim.new(0, pitch - size)
	for i = 1, n do
		make("ImageLabel", {
			Name = "Heart" .. i,
			LayoutOrder = i,
			BackgroundTransparency = 1,
			Image = if i <= full then Sprites.Hud.HeartFull else Sprites.Hud.HeartEmpty,
			Size = UDim2.fromOffset(size, size),
		}, ui.Hearts)
	end
end

local function showToast(str: string)
	toastToken += 1
	local token = toastToken
	ui.Toast.Text = str
	ui.ToastFrame.Visible = true
	task.delay(2, function()
		if token == toastToken then
			ui.ToastFrame.Visible = false
		end
	end)
end

-- Dark chrome strip that grows with its one line of text (countdowns, toast, hint).
local function line(parent: Instance, props: { [string]: any }, str: string, size: number, color: Color3?)
	props.AutomaticSize = Enum.AutomaticSize.XY
	local strip = Chrome.strip(parent, props)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 18),
		PaddingRight = UDim.new(0, 18),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
	}, strip)
	local t = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		Text = str,
		TextSize = size,
		TextColor3 = color or WHITE,
		AutomaticSize = Enum.AutomaticSize.XY,
		ZIndex = (props.ZIndex or 1) + 1,
	}, strip)
	local stroke = make("UIStroke", { Color = INK, Thickness = 2 }, t)
	stroke:SetAttribute("Rim", 2)
	return strip, t
end

local function build()
	gui = make("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		DisplayOrder = 7, -- above the Lobby (6), so the full-screen message covers the lobby and menus
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		IgnoreGuiInset = true, -- deliberate: safe-area handled by DeviceSafeInsets; top bar is centred, clear of core buttons
	})
	ui = { SlotList = {} }

	ui.Root = make("Frame", { Name = "Root", BackgroundTransparency = 1 }, gui)
	ui.Scale = make("UIScale", {}, ui.Root)

	-- Top centre: status bar, then the wave / boss countdown lines.
	local top = make("Frame", {
		Name = "Top",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(717, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, ui.Root)
	make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, top)

	ui.Bar = make("ImageLabel", {
		Name = "StatusBar",
		BackgroundTransparency = 1,
		Image = Sprites.Hud.GameBar,
		Size = UDim2.fromOffset(660 * BAR_K, 74 * BAR_K),
		LayoutOrder = 1,
	}, top)
	ui.Wave = text(ui.Bar, { Position = UDim2.fromOffset(120 * BAR_K, 36 * BAR_K) }, 44, 190 * BAR_K)
	ui.MP = text(ui.Bar, {
		Position = UDim2.fromOffset(548 * BAR_K, 36 * BAR_K),
		TextColor3 = CYAN,
	}, 44, 190 * BAR_K)
	make("ImageLabel", {
		Name = "Divider",
		BackgroundTransparency = 1,
		Image = Sprites.Hud.GameDivider,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(430 * BAR_K, 37 * BAR_K),
		Size = UDim2.fromOffset(8 * BAR_K, 40 * BAR_K),
	}, ui.Bar)
	ui.Hearts = make("Frame", {
		Name = "Hearts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(328 * BAR_K, 35 * BAR_K),
		Size = UDim2.fromOffset(150 * BAR_K, 40 * BAR_K),
	}, ui.Bar)
	ui.HeartLayout = make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, ui.Hearts)

	ui.NextWaveBox, ui.NextWave = line(top, { Name = "NextWave", LayoutOrder = 2, Visible = false }, "", 26)
	ui.BossBox, ui.Boss =
		line(top, { Name = "Boss", LayoutOrder = 3, Visible = false }, "", 28, Color3.fromRGB(255, 150, 120))

	-- Top right: gear. Draws idle / hover / pressed and does nothing: Settings only exists in the lobby and
	-- closes itself mid-match. The hit box grows to 44 real px on phones (see rescale).
	local gearHit = make("TextButton", {
		Name = "Gear",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -26, 0, 20),
		Size = UDim2.fromOffset(GEAR, GEAR),
	}, ui.Root)
	local gearImage = make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = Sprites.Hud.Gear,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(GEAR, GEAR),
	}, gearHit)
	make("UIAspectRatioConstraint", { AspectRatio = 166 / 162 }, gearImage)
	ui.Gear = { Hit = gearHit, Image = gearImage, Scale = make("UIScale", {}, gearImage), Mode = "Normal" }
	UiKit.wire(gearHit, function(mode)
		ui.Gear.Mode = mode
		paintGear()
	end)

	-- Bottom: upgrade tiles on the left, Summon on the right, one group centred on the screen.
	ui.Bottom = make("Frame", {
		Name = "Bottom",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 12, 1, -28), -- mockup centre sits 12 px right of the screen centre
		Size = UDim2.fromOffset(1152, SLOT_H),
	}, ui.Root)
	ui.Slots = make("Frame", {
		Name = "PowerUps",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(5 * SLOT_W + 4 * SLOT_GAP, SLOT_H),
		Visible = false,
	}, ui.Bottom)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, SLOT_GAP),
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	}, ui.Slots)

	local summon = make("ImageButton", {
		Name = "Summon",
		BackgroundTransparency = 1,
		Image = PILL.Image,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = PILL.Slice,
		SliceScale = SUMMON_H / PILL.Size.Y,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, -2),
		Size = UDim2.fromOffset(SUMMON_W, SUMMON_H),
	}, ui.Bottom)
	ui.SummonButton = summon
	local glowFrame, glowStroke = glow(summon, SUMMON_H / 2, 3)
	local content =
		make("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, summon)
	local icon = make("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(73, 58),
		Size = UDim2.fromOffset(84, 84),
		Image = Sprites.Icon.Roll,
		ScaleType = Enum.ScaleType.Fit,
	}, content)
	text(content, { Position = UDim2.fromOffset(214, 36), Text = HudLogic.SUMMON_TEXT }, 46, 190)
	local recess = make("Frame", { -- faint dark recess behind the cost line, as in the mockup
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(214, 77),
		Size = UDim2.fromOffset(177, 36),
	}, content)
	make("UICorner", { CornerRadius = UDim.new(0, 18) }, recess)
	local cost = text(content, { Position = UDim2.fromOffset(214, 77), TextColor3 = CYAN }, 40, 190)
	ui.Summon = {
		State = "idle",
		Mode = "Normal",
		Glow = glowFrame,
		GlowStroke = glowStroke,
		Content = content,
		Icon = icon,
		Cost = cost,
		Bar = bar(content, 126, 5, 214, 100),
	}
	UiKit.wire(summon, function(mode)
		ui.Summon.Mode = mode
		paintSummon()
	end)
	summon.Activated:Connect(function()
		request("Summon")
	end)

	-- Above the bottom group: toast over the hint.
	local aboveBottom = SLOT_H + 28 + 14
	ui.HintBox = line(ui.Root, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -aboveBottom),
		Visible = false,
	}, "Tap a die, then a matching die to merge", 24)
	ui.ToastFrame, ui.Toast = line(ui.Root, {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(aboveBottom + 54)),
		Visible = false,
		ZIndex = 3,
	}, "", 26)

	-- Full-screen message (Loading / Failed / NotOwner); swallows input behind it. Outside the scaled root.
	ui.Message = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 10,
	}, gui)
	ui.MessageText = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.2),
		ZIndex = 11,
	}, ui.Message, 40)
end

-- One uniform scale for the whole HUD (same rule as the lobby HUD); EmulateSize honoured for captures.
local function rescale()
	local screen = UiKit.screenSize(gui)
	if screen.X <= 0 or screen.Y <= 0 then
		return
	end
	local s = math.min(screen.X / DESIGN.X, screen.Y / DESIGN.Y)
	if screen.Y < UiKit.PHONE_H then
		s = math.max(s, PHONE_FLOOR)
	end
	s = math.min(s, MAX_SCALE)
	ui.Scale.Scale = s
	ui.Root.Size = UDim2.fromOffset(screen.X / s, screen.Y / s) -- the emulated screen when EmulateSize is set
	local hit = math.max(GEAR, math.ceil(44 / s)) -- touch target >= 44 real px
	ui.Gear.Hit.Size = UDim2.fromOffset(hit, hit)
	Chrome.restroke(ui.Root, s)
end

local function updateCountdowns()
	local snap = NetClient.Last
	if not snap then
		return
	end
	local now = workspace:GetServerTimeNow()
	local nextIn = snap.NextWaveAt and snap.NextWaveAt - now
	local bossIn = snap.BossAt and snap.BossAt - now
	ui.NextWaveBox.Visible = snap.Phase == "Playing" and nextIn ~= nil and nextIn > 0
	if ui.NextWaveBox.Visible then
		ui.NextWave.Text = ("Next wave in %ds"):format(math.ceil(nextIn))
	end
	ui.BossBox.Visible = snap.Phase == "Playing" and bossIn ~= nil and bossIn > 0
	if ui.BossBox.Visible then
		ui.Boss.Text = ("%s approaches \u{2014} %ds"):format(Display.Enemies.Boss.Name, math.ceil(bossIn))
	end
end

local function render(snap)
	local phase = snap.Phase
	local message = MESSAGES[phase] or if Preload.Done then nil else "Loading\u{2026}" -- hold until every menu's art is in
	ui.Message.Visible = message ~= nil
	ui.Message.BackgroundTransparency = if Preload.Done then 0.1 else 0 -- opaque while menu art warms up beneath it
	ui.MessageText.Text = message or ""

	local vis = HudLogic.visibility(phase, snap.Wave, #(snap.Tiers or {}))
	ui.ToastFrame.Visible = ui.ToastFrame.Visible and vis.Bar -- match-only toasts: never over the Lobby's results card
	ui.Bar.Visible = vis.Bar
	ui.Gear.Hit.Visible = vis.Bar
	setText(ui.Wave, HudLogic.waveText(snap.Wave))
	setText(ui.MP, HudLogic.mpText(snap.MP))
	setHearts(HudLogic.hearts(snap.Lives, snap.MaxLives))

	ui.SummonButton.Visible = vis.Summon
	ui.Summon.State = HudLogic.summonState(snap.SummonCost, snap.MP)
	setText(ui.Summon.Cost, HudLogic.summonCostText(snap.SummonCost))
	paintSummon()

	renderPowerUps(snap, vis.Slots)
	ui.HintBox.Visible = vis.Hint

	updateCountdowns()
end

function Hud.Start()
	build()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	rescale()
	table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale))
	table.insert(connections, gui:GetAttributeChangedSignal("EmulateSize"):Connect(rescale))

	table.insert(
		connections,
		NetClient.State:Connect(function(snap)
			render(snap)
		end)
	)
	table.insert(
		connections,
		NetClient.Rejected:Connect(function(_, code)
			if TOASTS[code] then
				showToast(TOASTS[code])
			end
		end)
	)
	table.insert(connections, RunService.Heartbeat:Connect(updateCountdowns))
	table.insert(
		connections,
		Preload.Finished:Connect(function()
			render(NetClient.Last or { Phase = "Loading" })
		end)
	)

	render(NetClient.Last or { Phase = "Loading" })
end

function Hud.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if gui then
		gui:Destroy()
	end
end

return Hud
