-- Match HUD: display only. All state comes from NetClient snapshots; the server decides everything.
-- Thin view over HudLogic (hearts, texts, states, visibility). Laid out in design px (1672x941 mockup:
-- Assets/UI/new/game hud/mockup.png) under one root UIScale; groups hang off the top-centre, top-right and bottom
-- edges, so the centre of the screen (the board) stays clear. State looks (hover, pressed, insufficient, maxed) are
-- drawn in code on the blank tile / pill; no baked state art.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local NetClient = require(script.Parent.NetClient)
local Preload = require(script.Parent.Preload)
local Chrome = require(script.Parent.Bag.Chrome)
local HudLogic = require(script.Parent.HudLogic)
local BossPortraits = require(script.Parent.BossPortraitSprites)
local WaveTrackLogic = require(script.Parent.WaveTrackLogic)
local RatingLogic = require(script.Parent.RatingLogic)
local SharedSprites = require(script.Parent.SharedSprites)
local SettingsLogic = require(script.Parent.Settings.SettingsLogic)
local Sprites = require(script.Parent.Sprites)
local UiKit = require(script.Parent.UiKit)
local Display = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Display"))
local Bosses = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Bosses"))

local make, label = UiKit.make, UiKit.label
local WHITE, NAVY = UiKit.WHITE, UiKit.NAVY
local FONT = Enum.Font.FredokaOne
local PILL = SharedSprites.PillPurple

local TOASTS = {
	NoMP = "Not enough MP",
	Unavailable = "Not available right now",
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
local PHONE_FLOOR = 0.5 -- same floor as the lobby HUD
local MAX_SCALE = 1.5
local BAR_K = 717 / 660 -- status bar art (660x74) scaled uniformly
local SLOT_K = 158 / 140 -- upgrade tile art (128x140) scaled uniformly
local SLOT_W, SLOT_H, SLOT_GAP = 128 * SLOT_K, 158, 12
local SUMMON_W, SUMMON_H = 347, 122
local GROUP_K = 0.8 -- bar, slots and summon sit 10-20% over the lobby equivalents (hotbar slot 104x106 -> 115x126); owner: unify with the lobby
local GEAR_ART, GEAR_HIT, GEAR_RIGHT, GEAR_Y = 52, 88, 64.5, 51 -- the lobby gear exactly
local SURRENDER_W, SURRENDER_H, SURRENDER_Y = 176, 56, 150 -- under the gear (its hit box ends at y 95)
local CONFIRM_W, CONFIRM_H, CONFIRM_BTN_W, CONFIRM_BTN_H = 600, 300, 250, 92
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
local trackKey -- last wave-track state drawn (nil forces a rebuild, e.g. after a rescale)
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

-- Scalable art body: grows from its centre (hover 1.07, pressed 0.93).
local function body(parent: Instance, class: string, props: { [string]: any })
	props.BackgroundTransparency = 1
	props.AnchorPoint = Vector2.new(0.5, 0.5)
	props.Position = UDim2.fromScale(0.5, 0.5)
	props.Size = UDim2.fromScale(1, 1)
	local f = make(class, props, parent)
	return f, make("UIScale", {}, f)
end

-- Power-up strip: one tile per deck die, rebuilt only when the deck ids change. Legality is the server's;
-- the insufficient look is a hint from the snapshot's Cost and MP.
local function paintSlot(slot)
	local state = slot.State
	local mode = if state == "idle" then slot.Mode else "Normal"
	if state == "idle" then
		UiKit.feel(slot.Tile, slot.Scale, mode, true)
	else -- insufficient / maxed: no hover, the tile stays plain
		slot.Tile.ImageColor3, slot.Scale.Scale = WHITE, 1
	end
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
	local art, scale = body(hit, "Frame", { Name = "Art" })
	local tile = make("ImageLabel", {
		Name = "Tile",
		BackgroundTransparency = 1,
		Image = Sprites.Hud.UpgradeBlank,
		Size = UDim2.fromScale(1, 1),
	}, art)
	local content = make("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, art)
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
	local level = text(content, { Position = UDim2.fromOffset(SLOT_W / 2, 87 * SLOT_K) }, 34, SLOT_W - 16)
	local cost = text(content, { Position = UDim2.fromOffset(SLOT_W / 2, 110 * SLOT_K) }, 31, SLOT_W - 30)
	local underline = bar(content, 53, 5, SLOT_W / 2, 124 * SLOT_K)
	local slot = {
		Hit = hit,
		Tile = tile,
		Scale = scale,
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
	UiKit.feel(s.Art, s.Scale, mode, true)
	if insufficient then -- greyed purple, still pressable (the server answers with a toast)
		s.Art.ImageColor3 = if mode == "Pressed" then Color3.fromRGB(110, 95, 110) else Color3.fromRGB(150, 125, 150)
	end
	s.Content.Position = UDim2.fromOffset(0, if mode == "Pressed" then PRESS_NUDGE * 1.15 else 0)
	s.Icon.ImageColor3 = if insufficient then Color3.fromRGB(200, 195, 205) else WHITE
	s.Cost.TextColor3 = if insufficient then SALMON else CYAN
	s.Bar.Visible = insufficient
	s.Bar.BackgroundColor3 = Color3.fromRGB(225, 120, 120)
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
	make("UIScale", { Scale = GROUP_K }, top)
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
	ui.Wave = text(ui.Bar, { Position = UDim2.fromOffset(120 * BAR_K, 36 * BAR_K) }, 48, 190 * BAR_K)
	ui.MP = text(ui.Bar, {
		Position = UDim2.fromOffset(548 * BAR_K, 36 * BAR_K),
		TextColor3 = CYAN,
	}, 48, 190 * BAR_K)
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

	-- Duel only: the opponent's name, rank and lives under the status bar (hidden in Solo / Co-op).
	ui.OpponentBox, ui.Opponent = line(top, { Name = "Opponent", LayoutOrder = 2, Visible = false }, "", 22)
	ui.Opponent.LayoutOrder = 1
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
	}, ui.OpponentBox)
	-- Small BOT tag beside the name (bot opponents only).
	ui.BotTag = make("Frame", {
		Name = "BotTag",
		BackgroundColor3 = Color3.fromRGB(70, 110, 190),
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 2,
		Visible = false,
		ZIndex = 3,
	}, ui.OpponentBox)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, ui.BotTag)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 2),
	}, ui.BotTag)
	local botText = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		Text = "BOT",
		TextSize = 20,
		TextColor3 = WHITE,
		AutomaticSize = Enum.AutomaticSize.XY,
		ZIndex = 4,
	}, ui.BotTag)
	make("UIStroke", { Color = INK, Thickness = 2 }, botText):SetAttribute("Rim", 2)
	ui.WaitBox, ui.Wait =
		line(top, { Name = "DuelWait", LayoutOrder = 3, Visible = false }, RatingLogic.WAITING_TEXT, 24)
	ui.NextWaveBox, ui.NextWave = line(top, { Name = "NextWave", LayoutOrder = 5, Visible = false }, "", 26)
	-- Wave track under the status bar: a dot per wave, the boss waves as portrait circles (rebuilt on a wave change).
	ui.TrackBox = Chrome.strip(top, {
		Name = "WaveTrack",
		LayoutOrder = 4,
		Visible = false,
		AutomaticSize = Enum.AutomaticSize.XY,
	})
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
	}, ui.TrackBox)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, ui.TrackBox)

	-- Top right: gear. Draws idle / hover / pressed and does nothing: Settings only exists in the lobby and
	-- closes itself mid-match. The hit box grows to 44 real px on phones (see rescale).
	local gearHit = make("TextButton", {
		Name = "Gear",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -GEAR_RIGHT, 0, GEAR_Y),
		Size = UDim2.fromOffset(GEAR_HIT, GEAR_HIT),
	}, ui.Root)
	local gearImage = make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = Sprites.Hud.Gear,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(GEAR_ART, GEAR_ART),
	}, gearHit)
	make("UIAspectRatioConstraint", { AspectRatio = 166 / 162 }, gearImage)
	local gearScale = make("UIScale", {}, gearImage)
	ui.Gear = { Hit = gearHit }
	UiKit.wire(gearHit, function(mode)
		UiKit.feel(gearImage, gearScale, mode, true)
	end)

	-- Duel only: SURRENDER under the gear (top right: clear of the board, the dice hand and the Summon pill). Opens a
	-- confirm dialog; the server decides (Match.Forfeit). The strip is the look, the transparent hit box is >= 46 real px tall.
	ui.Surrender = Chrome.strip(ui.Root, {
		Name = "Surrender",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(1, -GEAR_RIGHT, 0, SURRENDER_Y),
		Size = UDim2.fromOffset(SURRENDER_W, SURRENDER_H),
		BackgroundColor3 = Color3.fromRGB(96, 36, 40),
		Visible = false,
		ZIndex = 2,
		Radius = 14,
	})
	ui.SurrenderText = text(ui.Surrender, {
		Position = UDim2.fromScale(0.5, 0.5),
		Text = "SURRENDER",
		ZIndex = 3,
	}, 24, SURRENDER_W - 16)
	ui.SurrenderHit = make("TextButton", {
		Name = "Hit",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, SURRENDER_H),
		ZIndex = 4,
	}, ui.Surrender)
	UiKit.wire(ui.SurrenderHit, function(mode)
		ui.Surrender.BackgroundColor3 = if mode == "Pressed"
			then Color3.fromRGB(70, 24, 28)
			elseif mode == "Hover" then Color3.fromRGB(128, 48, 52)
			else Color3.fromRGB(96, 36, 40)
	end)

	-- Confirm dialog: backdrop (tap = cancel) over the whole HUD; Cancel holds the default focus.
	ui.Confirm = make("TextButton", {
		Name = "SurrenderConfirm",
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Selectable = false,
	}, ui.Root)
	local card = Chrome.panel(ui.Confirm, {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CONFIRM_W, CONFIRM_H),
		Active = true, -- sinks taps so they do not reach the backdrop
		ZIndex = 21,
		Radius = 20,
	})
	local prompt = text(card, {
		Name = "Prompt",
		Position = UDim2.fromOffset(CONFIRM_W / 2, 90),
		ZIndex = 22,
	}, 36, CONFIRM_W - 48)
	setText(prompt, RatingLogic.SURRENDER_PROMPT)
	local function choice(name: string, str: string, x: number, color: Color3)
		local b = Chrome.strip(card, {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, CONFIRM_H - 70),
			Size = UDim2.fromOffset(CONFIRM_BTN_W, CONFIRM_BTN_H),
			BackgroundColor3 = color,
			ZIndex = 22,
			Radius = 14,
		})
		text(b, { Position = UDim2.fromScale(0.5, 0.5), Text = str, ZIndex = 23 }, 30, CONFIRM_BTN_W - 16)
		local hit = make("TextButton", {
			Name = "Hit",
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(CONFIRM_BTN_W, CONFIRM_BTN_H),
			ZIndex = 24,
			Selectable = true,
		}, b)
		UiKit.wire(hit, function(mode)
			b.BackgroundColor3 = if mode == "Pressed"
				then shade(color, 0.7)
				elseif mode == "Hover" then shade(color, 1.2)
				else color
		end)
		return hit
	end
	ui.ConfirmCancel = choice("Cancel", "CANCEL", CONFIRM_W * 0.27, Color3.fromRGB(58, 64, 96))
	ui.ConfirmOk = choice("Surrender", "SURRENDER", CONFIRM_W * 0.73, Color3.fromRGB(150, 48, 52))

	-- Bottom: upgrade tiles on the left, Summon on the right, one group centred on the screen.
	ui.Bottom = make("Frame", {
		Name = "Bottom",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 12, 1, -28), -- mockup centre sits 12 px right of the screen centre
		Size = UDim2.fromOffset(1152, SLOT_H),
	}, ui.Root)
	make("UIScale", { Scale = GROUP_K }, ui.Bottom)
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

	local summon = make("TextButton", {
		Name = "Summon",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, -2),
		Size = UDim2.fromOffset(SUMMON_W, SUMMON_H),
	}, ui.Bottom)
	ui.SummonButton = summon
	local art, scale = body(summon, "ImageLabel", {
		Name = "Art",
		Image = PILL.Image,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = PILL.Slice,
		SliceScale = SUMMON_H / PILL.Size.Y,
	})
	local content = make("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, art)
	local icon = make("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(73, 58),
		Size = UDim2.fromOffset(84, 84),
		Image = Sprites.Icon.Roll,
		ScaleType = Enum.ScaleType.Fit,
	}, content)
	text(content, { Position = UDim2.fromOffset(214, 36), Text = HudLogic.SUMMON_TEXT }, 48, 190)
	local recess = make("Frame", { -- faint dark recess behind the cost line, as in the mockup
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(214, 77),
		Size = UDim2.fromOffset(177, 36),
	}, content)
	make("UICorner", { CornerRadius = UDim.new(0, 18) }, recess)
	local cost = text(content, { Position = UDim2.fromOffset(214, 77), TextColor3 = CYAN }, 42, 190)
	ui.Summon = {
		State = "idle",
		Mode = "Normal",
		Art = art,
		Scale = scale,
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
	local aboveBottom = SLOT_H * GROUP_K + 28 + 14
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
	if screen.Y >= UiKit.PHONE_H then
		s *= SettingsLogic.get("uiScale") / 100 -- Settings UI Scale: desktop only, like the lobby HUD
	end
	ui.Scale.Scale = s
	ui.Root.Size = UDim2.fromOffset(screen.X / s, screen.Y / s) -- the emulated screen when EmulateSize is set
	local hit = math.max(GEAR_HIT, math.ceil(44 / s)) -- touch target >= 44 real px
	ui.Gear.Hit.Size = UDim2.fromOffset(hit, hit)
	ui.SurrenderHit.Size = UDim2.new(1, 0, 0, math.max(SURRENDER_H, math.ceil(46 / s))) -- touch targets >= 46 real px
	local choiceH = math.max(CONFIRM_BTN_H, math.ceil(46 / s))
	for _, choiceHit in { ui.ConfirmCancel, ui.ConfirmOk } do
		choiceHit.Size = UDim2.fromOffset(CONFIRM_BTN_W, choiceH)
	end
	Chrome.restroke(ui.Root, s * GROUP_K)
	-- Phones: real-px minimums (text >= 13, dots >= 8, portraits >= 22) are met by growing the design size and dropping
	-- passed waves from the track, never by shrinking art.
	ui.NextWave.TextSize = math.max(26, math.ceil(13 / (s * GROUP_K)))
	trackKey = nil
end

local surrendering = false -- a Surrender request is in flight or accepted: the button stays off until the match changes
local function closeConfirm()
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(ui.Confirm) then
		GuiService.SelectedObject = nil
	end
	ui.Confirm.Visible = false
end
local function openConfirm()
	if surrendering then
		return
	end
	ui.Confirm.Visible = true
	GuiService.SelectedObject = ui.ConfirmCancel -- default focus is the safe choice
end
local function paintSurrender()
	ui.SurrenderHit.Active = not surrendering
	ui.SurrenderText.TextTransparency = if surrendering then 0.5 else 0
end

-- Rebuilds the wave track: the dots up to the next boss and its portrait frame at the end (see WaveTrackLogic.window).
local TRACK_DIM = Color3.fromRGB(96, 96, 108)
local TRACK_MAX_W = 700 -- design px (the Top group is 717 wide)
local function buildTrack(snap)
	for _, c in ui.TrackBox:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local k = ui.Scale.Scale * GROUP_K
	local dotSize, bossSize = math.max(14, math.ceil(8 / k)), math.max(38, math.ceil(22 / k))
	local items = WaveTrackLogic.window(snap.Wave, snap.BossPlan)
	local function width(list)
		local w = 32 + 8 * (#list - 1)
		for _, it in list do
			w += if it.Boss then bossSize else dotSize
		end
		return w
	end
	while #items > 1 and width(items) > TRACK_MAX_W do -- drop passed waves first, then the far end
		table.remove(items, if items[1].Past then 1 else #items)
	end
	for i, it in items do
		local cell
		if it.Boss then
			local size = math.ceil(bossSize * 46 / 38)
			cell = make("Frame", {
				BackgroundColor3 = Chrome.FieldFill,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(size, size),
			}, ui.TrackBox)
			local rim = make("UIStroke", {
				Color = if it.Current then CYAN else GOLD_TEXT,
				Thickness = 4,
			}, cell)
			rim:SetAttribute("Rim", rim.Thickness)
			local info = Bosses.Info[it.Variant or snap.BossVariant] -- plan entry 1 = BossVariant: the boss frame is always the next boss
			local portrait = info and BossPortraits[info.Portrait]
			local art = portrait and portrait.Image or ""
			if art ~= "" then
				local img = make("ImageLabel", {
					BackgroundTransparency = 1,
					Image = art,
					ScaleType = Enum.ScaleType.Crop,
					Size = UDim2.fromScale(1, 1),
				}, cell)
				make("UICorner", { CornerRadius = UDim.new(1, 0) }, img)
			else
				-- No portrait art for this variant: a generic "?" in the HUD font.
				local q = make("TextLabel", {
					BackgroundTransparency = 1,
					Font = FONT,
					Text = "?",
					TextSize = math.floor(size * 0.6),
					TextColor3 = GOLD_TEXT,
					Size = UDim2.fromScale(1, 1),
				}, cell)
				make("UIStroke", { Color = INK, Thickness = 2 }, q):SetAttribute("Rim", 2)
			end
		else
			local size = if it.Current then math.ceil(dotSize * 20 / 14) else dotSize
			cell = make("Frame", {
				BackgroundColor3 = if it.Current then WHITE elseif it.Past then TRACK_DIM else Chrome.FieldFill,
				BackgroundTransparency = if it.Current or it.Past then 0 else 0.3,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(size, size),
			}, ui.TrackBox)
			local rim = make("UIStroke", {
				Color = if it.Current then CYAN elseif it.Past then TRACK_DIM else Chrome.PanelRim,
				Thickness = if it.Current then 3 else 2,
			}, cell)
			rim:SetAttribute("Rim", rim.Thickness)
		end
		cell.Name = "W" .. it.Wave
		cell.LayoutOrder = i
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, cell)
	end
	Chrome.restroke(ui.TrackBox, k)
end

local function updateCountdowns()
	local snap = NetClient.Last
	if not snap then
		return
	end
	local now = workspace:GetServerTimeNow()
	local nextIn = snap.NextWaveAt and snap.NextWaveAt - now
	ui.NextWaveBox.Visible = snap.Phase == "Playing" and nextIn ~= nil and nextIn > 0
	if ui.NextWaveBox.Visible then
		ui.NextWave.Text = ("Next wave in %ds"):format(math.ceil(nextIn))
	end
	local mode = snap.Mode
	local key = ("%s:%s:%s:%s"):format(
		tostring(snap.Wave),
		tostring(snap.BossWave),
		tostring(snap.BossVariant),
		tostring(mode)
	)
	if key ~= trackKey then
		trackKey = key
		buildTrack(snap)
	end
	ui.TrackBox.Visible = snap.Phase == "Playing" and mode ~= "Duel" -- a Duel has a boss every round: nothing to track
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
	local duel = RatingLogic.hud(snap)
	ui.OpponentBox.Visible = vis.Bar and duel.Show
	local sur = RatingLogic.surrender(snap)
	ui.Surrender.Visible = vis.Bar and sur.Show
	ui.WaitBox.Visible = vis.Bar and sur.Waiting
	ui.BotTag.Visible = duel.Show and duel.IsBot
	if not (vis.Bar and sur.Show) then
		surrendering = false -- the match ended or changed: re-arm for the next one
		closeConfirm()
	end
	paintSurrender()
	if duel.Show then
		ui.Opponent.Text = duel.Text
		local c = RatingLogic.rankColor(snap.Opponent and snap.Opponent.Rank)
		ui.Opponent.TextColor3 = Color3.fromRGB(c[1], c[2], c[3])
	end

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
	table.insert(
		connections,
		ui.SurrenderHit.Activated:Connect(function()
			openConfirm()
		end)
	)
	table.insert(connections, ui.ConfirmCancel.Activated:Connect(closeConfirm))
	table.insert(connections, ui.Confirm.Activated:Connect(closeConfirm))
	table.insert(
		connections,
		ui.ConfirmOk.Activated:Connect(function()
			if surrendering then
				return
			end
			surrendering = true
			closeConfirm()
			paintSurrender()
			task.spawn(function()
				local ok = NetClient.Request("Surrender")
				if not ok then
					surrendering = false -- refused (toasted): the button comes back
					paintSurrender()
				end
			end)
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
