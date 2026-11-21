-- Lobby HUD (Assets/UI/new/lobby hud/mockup.png): Lv. pill + XP bar, gear, tile grid, coin / gem pills and the 5 deck slots,
-- laid out in design px (1672x941) under one UIScale (no Init/Start). Menu open: the coin / gem row and the slots move down and the slots shrink.
-- LobbyHud.build(parent, { open = (panel, tab?) -> (), toast = (text) -> () }) -> hud; hud:SetGold(n), hud:SetGems(n), hud:SetXp(level, into, need),
-- hud:SetDeck(ids), hud:SetBagMode(on, menu), hud:GetBagInsets().

local UserInputService = game:GetService("UserInputService")

local Sprites = require(script.Parent.Sprites)
local SettingsLogic = require(script.Parent.Settings.SettingsLogic)
local UiKit = require(script.Parent.UiKit)
local Chrome = require(script.Parent.Bag.Chrome)
local Display = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Display"))

local make = UiKit.make
local FONT = Enum.Font.FredokaOne
local WHITE = UiKit.WHITE
local STROKE = Color3.fromRGB(9, 14, 24) -- near-black outline on all HUD text
local DESIGN = Vector2.new(1672, 941)

-- Sampled from the mockup: dark translucent pills, navy XP track, purple fill.
local PILL = Color3.fromRGB(36, 35, 42)
local TRACK = Color3.fromRGB(20, 28, 48)
local FILL = Color3.fromRGB(190, 95, 248) -- mockup fill: top (195,94,248) .. bottom (161,69,247)

-- Measured on the mockup (design px). Tiles: export px x 0.389 (80 x 84 on screen), never upscaled past native.
local TILE_K = 0.389
local NATIVE = { -- export size per HUD sprite (manifest.json)
	Shop = { 206, 215 },
	Roll = { 202, 215 },
	Bag = { 201, 214 },
	Play = { 201, 215 },
	Codes = { 201, 215 },
	Daily = { 203, 216 },
	Quests = { 203, 216 },
	Gear = { 166, 162 },
	Plus = { 187, 187 },
	Slot = { 244, 249 },
	SlotGlow = { 251, 255 },
}
local GRID = { { "Shop", "Roll" }, { "Bag", "Play" }, { "Codes", "Daily" } }
local GRID_X, GRID_PITCH, GRID_Y = 75, 95, 385 -- first tile centre x / y (y at 941 tall), pitch both ways
local QUESTS_POS = { 1595, 491.5 } -- centre x, y (y at 941 tall)
local GEAR_RIGHT, GEAR_Y = 64.5, 51 -- gear centre: from the right edge / the top
local HIT = 95 -- touch box of every tile (>= 44 real px down to the 0.5 phone floor)

local XP_X, XP_Y = 38, 30 -- Lv. pill top-left
local TRACK_X, TRACK_RIGHT, TRACK_Y, TRACK_H = 110, 518, 35, 33 -- the track runs under the pill
local PILL_END = 148 -- visible bar starts here: fill = under-pill part + fraction of the visible bar
local FILL_H = 30

-- Closed / menu open: coin row centre and slot centre as distance above the bottom edge, slot width, slot pitch.
-- Closed uses the menu-open look too, so the bottom row never shifts when a menu opens.
local OPEN = { row = 154.5, deck = 71, slot = 104, pitch = 112 }
local CLOSED = OPEN
-- The Shell window (1112x666) sits at y 86..752 at 941 tall: its region ends 103 design px above the bottom.
local WINDOW_BOTTOM_GAP, WINDOW_LEFT = 103, 274

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
	props.TextColor3 = props.TextColor3 or WHITE
	local stroke = props.StrokeColor or STROKE
	props.StrokeColor = nil
	local l = make("TextLabel", props, parent)
	make("UIStroke", { Color = stroke, Thickness = 2, LineJoinMode = Enum.LineJoinMode.Round }, l)
	return l
end

local function corner(inst, radius)
	make("UICorner", { CornerRadius = radius }, inst)
end

local function size(name: string, k: number): UDim2
	local n = NATIVE[name]
	return UDim2.fromOffset(n[1] * k, n[2] * k)
end

-- Tile / gear button: a transparent hit box with the whole art inside. Normal, hover (scale), pressed (scale + dim), disabled (grey).
local function artButton(parent, o)
	local btn = make("ImageButton", {
		Name = o.Name,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = o.Position,
		Size = UDim2.fromOffset(o.Hit, o.Hit),
		ZIndex = 2,
	}, parent)
	local art = make("ImageLabel", {
		Name = "Art",
		BackgroundTransparency = 1,
		Image = Sprites.Hud[o.Name],
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size(o.Name, o.K),
		ZIndex = 3,
	}, btn)
	local scale = make("UIScale", {}, art)
	UiKit.wire(btn, function(state)
		UiKit.feel(art, scale, state, btn.Interactable)
	end)
	btn.Activated:Connect(o.OnClick)
	return btn
end

-- Coin / gem box: icon over a dark pill that starts at the icon's centre; the pill grows with the number.
local function counter(parent, order, name, icon, iconSize: Vector2)
	local box = make("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 44),
		LayoutOrder = order,
		ZIndex = 2,
	}, parent)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, -iconSize.X / 2),
	}, box)
	make("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Image = icon,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(iconSize.X, iconSize.Y),
		LayoutOrder = 1,
		ZIndex = 4,
	}, box)
	local pill = make("Frame", {
		Name = "Pill",
		BackgroundColor3 = PILL,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		LayoutOrder = 2,
		ZIndex = 3,
	}, box)
	corner(pill, UDim.new(0.5, 0))
	make("UIPadding", { PaddingLeft = UDim.new(0, iconSize.X / 2 + 19), PaddingRight = UDim.new(0, 22) }, pill)
	return text({
		Name = "Value",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		TextSize = 31, -- FredokaOne renders ~0.7 of its nominal size: 31 gives the mockup width (~81 px for "12,480")
		ZIndex = 5,
	}, pill)
end

function LobbyHud.build(parent, cb)
	local self = setmetatable({}, LobbyHud)
	local open = cb.open

	local hud = make("Frame", { Name = "Hud", BackgroundTransparency = 1 }, parent)
	self.Hud = hud
	local uiScale = make("UIScale", {}, hud)
	self.UiScale = uiScale
	local function rescale()
		local screen = UiKit.screenSize(parent)
		if screen.X <= 0 or screen.Y <= 0 then
			return
		end
		local s = math.min(screen.X / DESIGN.X, screen.Y / DESIGN.Y)
		-- Phone floor: tiles stay ~40 px, the regions still clear each other down to 568x276.
		if screen.Y < UiKit.PHONE_H then
			s = math.max(s, 0.5)
		end
		s = math.min(s, 1.5)
		-- Settings UI Scale: desktop only, phones are already at the touch-size floor (same rule as Shell).
		if screen.Y >= UiKit.PHONE_H then
			s *= SettingsLogic.get("uiScale") / 100
		end
		uiScale.Scale = s
		hud.Size = UDim2.fromScale(1 / s, 1 / s)
		if self.BagOn then
			self:SetBagMode(true, self.BagMenu) -- re-apply the phone rule after a resize/rotation
		end
	end
	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	parent:GetAttributeChangedSignal("EmulateSize"):Connect(rescale)
	-- Registered before any menu Shell, so the insets they read are already rescaled.
	hud.Destroying:Connect(SettingsLogic.onChanged(function(id)
		if id == "uiScale" then
			rescale()
		end
	end))
	rescale()

	-- Left grid: six tiles at the mockup's pitch, centred on the same line as QUESTS.
	local grid = make("Frame", {
		Name = "LeftGrid",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, GRID_Y - DESIGN.Y / 2 + GRID_PITCH),
		Size = UDim2.fromOffset(2 * GRID_X + GRID_PITCH, 0),
	}, hud)
	self.LeftGrid = grid
	local buttons = {}
	for r, rowNames in GRID do
		for c, name in rowNames do
			buttons[name] = artButton(grid, {
				Name = name,
				K = TILE_K,
				Hit = HIT,
				Radius = 18,
				Position = UDim2.fromOffset(GRID_X + (c - 1) * GRID_PITCH, (r - 2) * GRID_PITCH),
				OnClick = function()
					open(name)
				end,
			})
		end
	end
	local quests = artButton(hud, {
		Name = "Quests",
		K = TILE_K,
		Hit = HIT,
		Radius = 18,
		Position = UDim2.new(1, QUESTS_POS[1] - DESIGN.X, 0.5, QUESTS_POS[2] - DESIGN.Y / 2),
		OnClick = function()
			open("Quests")
		end,
	})
	local gear = artButton(hud, {
		Name = "Gear",
		K = 52 / NATIVE.Gear[1], -- 52 x 51 on screen
		Hit = 88,
		Radius = 12,
		Position = UDim2.new(1, -GEAR_RIGHT, 0, GEAR_Y),
		OnClick = function()
			open("Settings")
		end,
	})
	buttons.Quests, buttons.Settings = quests, gear
	self.Buttons, self.Gear, self.Quests = buttons, gear, quests

	-- Lv. pill + XP bar (top left). One hit box opens Profile.
	local xp = make("Frame", {
		Name = "XpBar",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(TRACK_RIGHT + 20, 100),
	}, hud)
	self.XpBar = xp
	local xpHit = make("TextButton", {
		Name = "XpHit",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(XP_X - 10, 4),
		Size = UDim2.fromOffset(TRACK_RIGHT - XP_X + 20, 88),
		ZIndex = 1,
	}, xp)
	xpHit.Activated:Connect(function()
		open("Profile")
	end)
	local track = make("Frame", {
		Name = "Track",
		BackgroundColor3 = TRACK,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(TRACK_X, TRACK_Y),
		Size = UDim2.fromOffset(TRACK_RIGHT - TRACK_X, TRACK_H),
		ZIndex = 2,
	}, xp)
	corner(track, UDim.new(0.5, 0))
	Chrome.stroke(track, Color3.fromRGB(10, 14, 28), 1.5)
	self.XpFill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = FILL,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(TRACK_X, TRACK_Y + (TRACK_H - FILL_H) / 2),
		Size = UDim2.fromOffset(0, FILL_H),
		Visible = false,
		ZIndex = 3,
	}, xp)
	corner(self.XpFill, UDim.new(0.5, 0))
	make(
		"UIGradient",
		{ Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 190, 252)), Rotation = 90 },
		self.XpFill
	)
	self.XpLabel = text({
		Name = "XpLabel",
		Text = "\u{2014} / \u{2014} XP",
		TextSize = 24,
		StrokeColor = Color3.fromRGB(40, 12, 70),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(340, TRACK_Y + TRACK_H / 2),
		Size = UDim2.fromOffset(240, 26),
		ZIndex = 5,
	}, xp)
	local pill = make("Frame", {
		Name = "LvPill",
		BackgroundColor3 = PILL,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(XP_X, XP_Y),
		Size = UDim2.fromOffset(110, 43),
		ZIndex = 4,
	}, xp)
	corner(pill, UDim.new(0.5, 0))
	self.LvlLabel = text({
		Name = "LvlLabel",
		Text = "Lv. \u{2014}",
		TextSize = 36,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	}, pill)
	self.XpFraction = 0 -- until the first Meta (SetXp): 0 fill (hidden)

	-- Coin / gem row (bottom centre): one hit box opens Profile.
	local currencies = make("TextButton", {
		Name = "Currencies",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 88),
		ZIndex = 1,
	}, hud)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 51),
	}, currencies)
	currencies.Activated:Connect(function()
		open("Profile")
	end)
	self.Currencies = currencies
	self.GoldLabel = counter(currencies, 1, "Gold", Sprites.Coin, Vector2.new(57, 59))
	self.GemLabel = counter(currencies, 2, "Gems", Sprites.Gem, Vector2.new(63, 61))
	self.GemLabel.Text = "\u{2014}" -- until the first Meta (SetGems)
	self.GoldLabel.Text = formatGold(0)

	-- Deck slots: a zero-size anchor centred above the bottom edge; each slot is placed from its centre.
	local deck = make("Frame", {
		Name = "DeckBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
	}, hud)
	self.DeckBar = deck
	self.Slots, self.SlotParts = {}, {}
	self._dragEnd, self._pick, self._ghost, self._onSwap = -math.huge, nil, nil, nil
	for i = 1, 5 do
		local slot = make("ImageButton", {
			Name = "Slot" .. i,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 2,
		}, deck)
		local body = make("Frame", {
			Name = "Body",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
		}, slot)
		local bodyScale = make("UIScale", {}, body)
		local frame = make("ImageLabel", {
			Name = "Frame",
			BackgroundTransparency = 1,
			Image = Sprites.Hud.SlotGrey, -- loading until the first Meta (SetDeck)
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
		}, body)
		local plus = make("ImageLabel", {
			Name = "Plus",
			BackgroundTransparency = 1,
			Image = Sprites.Hud.Plus,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.375, 0.375),
			Visible = false,
			ZIndex = 5,
		}, body)
		local icon = make("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.74, 0.74),
			Visible = false,
			ZIndex = 5,
		}, body)
		slot:SetAttribute("Empty", true)
		slot:SetAttribute("Loading", true)
		local refresh = UiKit.wire(slot, function(state)
			local loading = slot:GetAttribute("Loading")
			frame.Image = if loading then Sprites.Hud.SlotGrey else Sprites.Hud.Slot
			UiKit.feel(frame, bodyScale, state, true)
			if loading then -- the grey frame is the loading look: no tint, no hover
				frame.ImageColor3, bodyScale.Scale = WHITE, 1
			end
			plus.Visible = not loading and slot:GetAttribute("Empty") == true
		end)
		slot:GetAttributeChangedSignal("Empty"):Connect(refresh)
		slot:GetAttributeChangedSignal("Loading"):Connect(refresh)
		-- Replace-a-slot mode (the Bag asks for it): a gold ring on every slot.
		local ring = make("Frame", {
			Name = "PickRing",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 6,
		}, body)
		make("UICorner", { CornerRadius = UDim.new(0, 14) }, ring)
		make("UIStroke", { Color = Color3.fromRGB(252, 205, 10), Thickness = 4 }, ring)
		slot.Activated:Connect(function()
			if os.clock() - self._dragEnd < 0.3 then -- the release that dropped a dragged die is not a click
				return
			end
			if self._pick then
				self._pick(i)
			else
				open("Bag", 1)
			end
		end)
		-- Hold (or drag) a filled slot to pick its die up as a ghost; drop it on another slot to swap them.
		slot.InputBegan:Connect(function(input)
			local t = input.UserInputType
			if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
				return
			end
			if slot:GetAttribute("Empty") or slot:GetAttribute("Loading") or self._ghost then
				return
			end
			self:_armDrag(i, input)
		end)
		self.Slots[i], self.SlotParts[i] = icon, slot
	end
	self:_layoutBottom(CLOSED)
	return self
end

local HOLD_TIME, DRAG_PX = 0.25, 10 -- hold this long, or move this far, with the button down to lift a die

-- A press on filled slot `from`: after HOLD_TIME or DRAG_PX of travel the die lifts as a ghost that follows the pointer.
function LobbyHud:_armDrag(from: number, input: InputObject)
	local startPos = input.Position
	local armed = true
	local conns = {}
	local function stop()
		armed = false
		for _, c in conns do
			c:Disconnect()
		end
	end
	local function lift()
		if not armed then
			return
		end
		stop()
		self:_lift(from, startPos)
	end
	table.insert(
		conns,
		UserInputService.InputChanged:Connect(function(changed)
			local t = changed.UserInputType
			if
				(t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch)
				and (changed.Position - startPos).Magnitude >= DRAG_PX
			then
				lift()
			end
		end)
	)
	table.insert(
		conns,
		UserInputService.InputEnded:Connect(function(ended)
			local t = ended.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				stop()
			end
		end)
	)
	task.delay(HOLD_TIME, lift)
end

function LobbyHud:_lift(from: number, startPos: Vector3)
	local slot, icon = self.SlotParts[from], self.Slots[from]
	if not icon.Visible then
		return
	end
	local root = self.Hud.Parent
	local box = slot.AbsoluteSize
	local origin = slot.AbsolutePosition + box / 2
	local ghost = make("ImageLabel", {
		Name = "DragGhost",
		BackgroundTransparency = 1,
		Image = icon.Image,
		ImageColor3 = icon.ImageColor3,
		ImageTransparency = 0.15,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(box.X * 0.8, box.Y * 0.8),
		ZIndex = 200,
		Active = false,
	}, root)
	icon.ImageTransparency = 0.65 -- the slot the die left shows it faded
	self._ghost = ghost
	local center = origin
	local function place(pos: Vector3)
		center = origin + Vector2.new(pos.X - startPos.X, pos.Y - startPos.Y)
		ghost.Position = UDim2.fromOffset(center.X - root.AbsolutePosition.X, center.Y - root.AbsolutePosition.Y)
	end
	place(startPos)
	local conns = {}
	local function finish(drop: boolean)
		for _, c in conns do
			c:Disconnect()
		end
		ghost:Destroy()
		self._ghost = nil
		icon.ImageTransparency = 0
		self._dragEnd = os.clock()
		if not drop then
			return
		end
		for j, other in self.SlotParts do
			local p, s = other.AbsolutePosition, other.AbsoluteSize
			if
				j ~= from
				and center.X >= p.X
				and center.X <= p.X + s.X
				and center.Y >= p.Y
				and center.Y <= p.Y + s.Y
			then
				if self._onSwap then
					self._onSwap(from, j)
				end
				return
			end
		end
	end
	table.insert(
		conns,
		UserInputService.InputChanged:Connect(function(changed)
			local t = changed.UserInputType
			if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
				place(changed.Position)
			end
		end)
	)
	table.insert(
		conns,
		UserInputService.InputEnded:Connect(function(ended)
			local t = ended.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				finish(true)
			end
		end)
	)
end

-- cb(from, to) when a die is dropped from one filled slot onto another.
function LobbyHud:OnSwap(cb)
	self._onSwap = cb
end

-- cb(slotIndex) takes over slot clicks (the Bag's replace-a-slot flow) and rings the slots; nil restores "click opens the Bag".
function LobbyHud:SetPickMode(cb)
	self._pick = cb
	for _, slot in self.SlotParts do
		local ring = slot:FindFirstChild("PickRing", true)
		if ring then
			ring.Visible = cb ~= nil
		end
	end
end

-- Coin row, deck anchor and the 5 slots for the closed (CLOSED) or menu-open (OPEN) look.
function LobbyHud:_layoutBottom(m)
	self.Currencies.Position = UDim2.new(0.5, 0, 1, -m.row)
	self.DeckBar.Position = UDim2.new(0.5, 0, 1, -m.deck)
	for i, slot in self.SlotParts do
		slot.Size = UDim2.fromOffset(m.slot, m.slot * NATIVE.Slot[2] / NATIVE.Slot[1])
		slot.Position = UDim2.fromOffset((i - 3) * m.pitch, 0)
	end
end

-- Fill = the part under the Lv. pill + the fraction of the visible bar (0 = hidden).
function LobbyHud:_layoutXp()
	local f = self.XpFraction
	self.XpFill.Size = UDim2.fromOffset(PILL_END - TRACK_X + f * (TRACK_RIGHT - PILL_END), FILL_H)
	self.XpFill.Visible = f > 0
end

-- A menu open: the coin row and the slots move down and the slots shrink (mockups). Phones: the menu takes that strip and the
-- left grid's columns, so both hide; they return on close. menu = the HUD button of the open menu.
function LobbyHud:SetBagMode(on: boolean, menu: string?)
	self.BagOn, self.BagMenu = on, menu
	local phone = UiKit.screenSize(self.Hud.Parent).Y < UiKit.PHONE_H
	self:_layoutBottom(if on then OPEN else CLOSED)
	self.Currencies.Visible = not (on and phone)
	self.DeckBar.Visible = not (on and phone)
	self.LeftGrid.Visible = not (on and phone)
end

-- Real px (Root space) the menu window must stay clear of: icon columns on the left (the window overlaps column 2's edge as
-- in the mockup), and the bottom (window region ends WINDOW_BOTTOM_GAP design px above the bottom: the mockup's window y 86..752).
function LobbyHud:GetBagInsets()
	local screen, s = UiKit.screenSize(self.Hud.Parent), self.UiScale.Scale
	return {
		leftReal = if screen.Y < UiKit.PHONE_H then 144 * s - 2 else WINDOW_LEFT * s,
		bottomTopReal = if screen.Y < UiKit.PHONE_H then screen.Y else screen.Y - WINDOW_BOTTOM_GAP * s,
	}
end

function LobbyHud:SetGold(gold: number?)
	self.GoldLabel.Text = formatGold(gold)
end

function LobbyHud:SetGems(gems: number?)
	self.GemLabel.Text = formatGold(gems)
end

-- Meta Level / XpInto / XpNeed; XpNeed = 0 at max level: full bar, "MAX".
function LobbyHud:SetXp(level: number?, into: number?, need: number?)
	into, need = into or 0, need or 0
	self.LvlLabel.Text = "Lv. " .. tostring(level or 1)
	self.XpLabel.Text = if need > 0 then ("%s / %s XP"):format(formatGold(into), formatGold(need)) else "MAX"
	self.XpFraction = if need > 0 then math.clamp(into / need, 0, 1) else 1
	self:_layoutXp()
end

-- ids: array of up to 5 die ids. Dice with art use it; others show Icon.Roll tinted by their Display colour; no id = the "+" slot.
function LobbyHud:SetDeck(ids)
	for i, icon in self.Slots do
		local id = ids and ids[i]
		local slot = self.SlotParts[i]
		slot:SetAttribute("Loading", nil)
		slot:SetAttribute("Empty", not id)
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
			icon.ImageColor3 = mapped and WHITE or (info and info.Color or WHITE)
		end
	end
end

return LobbyHud
