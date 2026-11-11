-- Bag parts: Toolbar, Grid (+Card), Footer, Detail (+Pill, Button). Visual only: no NetClient, no game data.
-- Sizes are design px (the Bag shell scales them); slots read the "Compact" attribute the shell sets on their parent.
-- Sprite schema: BagSprites[Name] = { Image, Size, Slice? }; a missing key or Image = "" renders blank.

local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.Parent.UiKit)
local Sprites = require(script.Parent.BagSprites)
local SlotFrame = require(script.Parent.Parent.Sprites).Frame

local make = UiKit.make
local FONT = Enum.Font.FredokaOne
local STROKE = Color3.fromRGB(9, 14, 24)
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(249, 199, 53)
local SOFT = Color3.fromRGB(205, 210, 235)
local DISABLED_TINT = Color3.new(0.55, 0.55, 0.6)

local Parts = {}

Parts.RarityColor = {
	Common = Color3.fromRGB(170, 170, 185),
	Uncommon = Color3.fromRGB(90, 205, 125),
	Rare = Color3.fromRGB(80, 150, 255),
	Epic = Color3.fromRGB(170, 100, 240),
	Legendary = GOLD,
	Mythic = Color3.fromRGB(247, 142, 236),
}
local PILL = {
	Common = "PillGrey",
	Uncommon = "PillGreen",
	Rare = "PillBlue",
	Epic = "PillPurple",
	Legendary = "PillGold",
	Mythic = "PillPink",
	Equipped = "PillGreen",
	Grey = "PillGrey",
	Green = "PillGreen",
	Blue = "PillBlue",
	Purple = "PillPurple",
	Gold = "PillGold",
	Pink = "PillPink",
}
local GLOW = {
	Common = "GlowCommon",
	Uncommon = "GlowUncommon",
	Rare = "GlowRare",
	Epic = "GlowEpic",
	Legendary = "GlowLegendary",
	Mythic = "GlowMythic",
	Secret = "GlowSecret",
}

-- Sprites ------------------------------------------------------------------------------------------------

-- 9-slice sprites use SliceScale so the rim keeps its design size; others just fit.
function Parts.skin(inst, name: string, sliceScale: number?)
	local s = Sprites[name]
	inst.Image = s and s.Image or ""
	if s and s.Slice then
		inst.ScaleType = Enum.ScaleType.Slice
		inst.SliceCenter = s.Slice
		inst.SliceScale = sliceScale or 0.5
	else
		inst.ScaleType = Enum.ScaleType.Fit
	end
end

-- Fixed-height sliced sprite: the sprite height maps to designH.
function Parts.skinH(inst, name: string, designH: number)
	local s = Sprites[name]
	Parts.skin(inst, name, designH / (s and s.Size.Y > 0 and s.Size.Y or designH))
end

-- ref is a BagSprites key or a raw asset id; nil/"" renders blank.
function Parts.image(inst, ref: string?)
	if ref and Sprites[ref] then
		Parts.skin(inst, ref)
	else
		inst.Image = ref or ""
		inst.ScaleType = Enum.ScaleType.Fit
	end
end

-- Builders -------------------------------------------------------------------------------------------------

local function img(parent, props, class)
	props.BackgroundTransparency = 1
	props.ZIndex = props.ZIndex or parent.ZIndex + 1
	return make(class or "ImageLabel", props, parent)
end

function Parts.text(parent, props, strokeThickness: number?)
	props.BackgroundTransparency = 1
	props.Font = FONT
	props.TextColor3 = props.TextColor3 or WHITE
	props.TextTruncate = props.TextTruncate or Enum.TextTruncate.AtEnd
	props.ZIndex = props.ZIndex or parent.ZIndex + 1
	local label = make("TextLabel", props, parent)
	make(
		"UIStroke",
		{ Color = STROKE, Thickness = strokeThickness or 2, LineJoinMode = Enum.LineJoinMode.Round },
		label
	)
	return label
end

local function measure(str: string, size: number): number
	return TextService:GetTextSize(str, size, FONT, Vector2.new(1e5, 1e5)).X
end

-- Shrinks the label's TextSize from maxSize until the text fits availW (never under minSize; AtEnd handles the rest).
function Parts.fit(label, availW: number, maxSize: number, minSize: number)
	local size = maxSize
	local w = measure(label.Text, maxSize)
	if w > availW and w > 0 then
		size = math.max(minSize, math.floor(maxSize * availW / w))
	end
	label.TextSize = size
end

local rim
-- Hover / press scale for mouse and touch, a gold focus rim for gamepad. extra(state) adds per-widget looks.
function Parts.interact(btn, extra)
	if not rim then
		rim = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
		make("UIStroke", { Color = GOLD, Thickness = 3 }, rim)
	end
	btn.AutoButtonColor = false
	btn.SelectionImageObject = rim
	local scale = make("UIScale", {}, btn)
	return UiKit.wire(btn, function(state)
		scale.Scale = if state == "Pressed" then 0.96 elseif state == "Hover" then 1.03 else 1
		if extra then
			extra(state)
		end
	end)
end

-- Pill: rarity / colour key -> sprite. o.W fixed width (text fits/truncates) or auto from the measured text.
-- "Equipped" style draws the white check (right, or left with o.CheckLeft); o.Icon (BagSprites key) draws a left icon.
function Parts.Pill(parent, style: string, str: string, o)
	o = o or {}
	local h, size = o.H or 22, o.TextSize or 15
	local equipped = style == "Equipped"
	local deco = equipped or o.Icon ~= nil
	local left = o.CheckLeft or o.Icon ~= nil
	local w = o.W or math.max(o.MinW or 0, measure(str, size) + 28 + (if deco then h else 0))
	local pill = img(parent, {
		Name = o.Name or "Pill",
		Size = UDim2.fromOffset(w, h),
		LayoutOrder = o.Order or 0,
	})
	Parts.skinH(pill, PILL[style] or "PillGrey", h)
	local label = Parts.text(pill, {
		Name = "Label",
		Text = str,
		TextSize = size,
		Position = UDim2.fromOffset(if deco and left then h - 2 else 0, 0),
		Size = if deco then UDim2.new(1, -(h + 4), 1, 0) else UDim2.fromScale(1, 1),
	}, 2)
	if o.W then
		Parts.fit(label, w - (if deco then h + 4 else 0) - 12, size, 11)
	end
	if deco then
		-- the check / icon sits outside the 9-slice centre (it would stretch), so draw it separately.
		local mark = img(pill, {
			Name = if equipped then "Check" else "Icon",
			AnchorPoint = Vector2.new(if left then 0 else 1, 0.5),
			Position = UDim2.new(if left then 0 else 1, if left then 6 else -6, 0.5, 0),
			Size = UDim2.fromOffset(h - 8, h - 8),
		})
		Parts.image(mark, if equipped then "Check" else o.Icon)
	end
	return pill
end

-- Buttons: one style for every action. Disabled still fires Activated (the controller toasts the hint).
local BTN = { Green = "BtnGreen", Red = "BtnRed", Gold = "BtnGold", Purple = "BtnPurple" }
local refreshers = setmetatable({}, { __mode = "k" })

function Parts.setButton(btn, o)
	local label = btn.Label
	if o.Style then
		Parts.skinH(btn, BTN[o.Style] or "BtnGreen", btn.Size.Y.Offset)
	end
	local ic = btn:FindFirstChild("Icon") -- padlock / coins left of the label
	local inset = 0
	if ic then
		local s = math.floor(btn.Size.Y.Offset * 0.5)
		ic.Size = UDim2.fromOffset(s, s)
		ic.Position = UDim2.new(0, 10, 0.5, 0)
		inset = s + 6
		label.Position = UDim2.fromOffset(8 + inset, 4)
		label.Size = UDim2.new(1, -(16 + inset), 1, -8)
	end
	if o.Label then
		label.Text = o.Label
		Parts.fit(label, btn.Size.X.Offset - 16 - inset, btn:GetAttribute("TextMax"), 15)
	end
	if o.Enabled ~= nil then
		btn:SetAttribute("Enabled", o.Enabled)
	end
	refreshers[btn]()
end

function Parts.refresherCount(): number -- debug: live button refreshers (leak check)
	local n = 0
	for _ in refreshers do
		n += 1
	end
	return n
end

function Parts.button(parent, o)
	local btn = img(parent, {
		Name = o.Name or "Button",
		Size = o.Size or UDim2.fromOffset(110, 56),
		LayoutOrder = o.Order or 0,
	}, "ImageButton")
	btn:SetAttribute("TextMax", o.TextSize or 26)
	local label =
		Parts.text(btn, { Name = "Label", Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4) })
	if o.Icon then
		local ic = img(btn, { Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), ZIndex = label.ZIndex })
		Parts.image(ic, o.Icon)
	end
	local stroke = label:FindFirstChildOfClass("UIStroke")
	btn.Destroying:Connect(function()
		refreshers[btn] = nil -- the refresh closure holds btn strongly: drop it when the button dies
	end)
	refreshers[btn] = Parts.interact(btn, function()
		local on = btn:GetAttribute("Enabled") ~= false
		btn.ImageColor3 = if on then WHITE else DISABLED_TINT
		label.TextTransparency = if on then 0 else 0.35
		stroke.Transparency = if on then 0 else 0.35
	end)
	Parts.setButton(btn, { Style = o.Style, Label = o.Label, Enabled = o.Enabled ~= false })
	return btn
end

local function clearChildren(parent, keepClass)
	for _, c in parent:GetChildren() do
		if not c:IsA(keepClass) then
			c:Destroy()
		end
	end
end

local function connect(conns, signal, fn)
	table.insert(conns, signal:Connect(fn))
end

local function disconnectAll(conns)
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
end

-- Toolbar -----------------------------------------------------------------------------------------------

local CONTROL_H, SORT_ROW = 44, 56 -- search/sort boxes are 44 px tall as in the reference (menu rows stay touch-size)

function Parts.Toolbar(parent)
	local api, conns = {}, {}
	local onSearch, onSort
	local options, active = {}, nil
	local muted = false

	local root = make("Frame", {
		Name = "Toolbar",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = parent.ZIndex,
	}, parent)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 24),
		PaddingRight = UDim.new(0, 24),
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
	}, root)

	local search = img(root, { Name = "Search" })
	Parts.skinH(search, "Search", CONTROL_H)
	local mag = img(search, {
		Name = "Magnifier",
		Size = UDim2.fromOffset(28, 28),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
	})
	Parts.image(mag, "Magnifier")
	local input = make("TextBox", {
		Name = "Input",
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		Font = FONT,
		TextSize = 22,
		TextColor3 = WHITE,
		PlaceholderColor3 = Color3.fromRGB(196, 169, 180), -- light mauve (reference #C4A9B4)
		Text = "",
		PlaceholderText = "Search",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = search.ZIndex + 1,
	}, search)
	local sort = img(root, { Name = "Sort", AnchorPoint = Vector2.new(1, 0) }, "ImageButton")
	Parts.skinH(sort, "Sort", CONTROL_H)
	Parts.interact(sort)
	local arrows = img(sort, {
		Name = "Arrows",
		Size = UDim2.fromOffset(28, 28),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
	})
	Parts.image(arrows, "SortArrows")
	local sortLabel = Parts.text(sort, {
		Name = "Label",
		TextSize = 22,
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.new(1, -92, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- Narrow left panels: the sort button becomes arrows only (a plain button sprite) and the placeholder
	-- shortens to its first word at 18 px, so the search box stays readable.
	local sortW = 234
	local placeholder = "Search"
	local tabKind = "Dice" -- Materials/Items draw the search|sort divider, Cosmetics a "SORT:" label
	local divider = img(
		root,
		{ Name = "Divider", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(3, 32), Visible = false },
		"Frame"
	)
	divider.BackgroundTransparency = 0
	divider.BackgroundColor3 = Color3.fromRGB(192, 102, 58)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, divider)
	local sortTag = Parts.text(root, {
		Name = "SortTag",
		Text = "SORT:",
		TextSize = 22,
		Visible = false,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(64, CONTROL_H),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local function layout()
		local inner = parent.Size.X.Offset - 48 -- design px (the shell sets slot sizes in offsets)
		sortW = if inner >= 440 then 234 else 56
		if sortW == 234 then
			Parts.skinH(sort, "Sort", CONTROL_H)
			sort.ScaleType = Enum.ScaleType.Stretch -- the baked chevron must not meet a 9-slice edge
		else
			Parts.skinH(sort, "BtnPurple", CONTROL_H)
		end
		input.TextSize = if sortW == 234 then 22 else 18
		input.PlaceholderText = if sortW == 234 then placeholder else placeholder:match("%S+") or placeholder
		sort.Size = UDim2.fromOffset(sortW, CONTROL_H)
		sort.Position = UDim2.fromScale(1, 0)
		local tagW = if tabKind == "Cosmetics" and sortW == 234 then 72 else 0
		search.Size = UDim2.fromOffset(math.min(440, inner - sortW - tagW - 16), CONTROL_H) -- 440 as in the reference; spare width sits between the boxes
		sortTag.Visible = tagW > 0
		sortTag.Position = UDim2.new(1, -sortW - 8, 0, 0)
		local gapL, gapR = search.Size.X.Offset, inner - sortW - tagW
		divider.Visible = tabKind ~= "Cosmetics" and tabKind ~= "Dice" and sortW == 234 and gapR - gapL >= 24
		divider.Position = UDim2.fromOffset(math.floor((gapL + gapR) / 2), CONTROL_H / 2)
		sortLabel.Visible = sortW == 234
		arrows.Position = if sortW == 234 then UDim2.new(0, 14, 0.5, 0) else UDim2.new(0.5, -14, 0.5, 0)
		input.Position = UDim2.fromOffset(52, 0)
		input.Size = UDim2.new(1, -(52 + 16), 1, 0)
	end
	connect(conns, parent:GetPropertyChangedSignal("Size"), layout)
	layout()

	local menu = img(root, {
		Name = "SortMenu",
		Visible = false,
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 45, -- above the compact footer overlay (slot icons reach 40)
		Active = true,
	}, "ImageButton")
	menu.AutoButtonColor = false
	Parts.skin(menu, "LeftPanel", 0.5)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
	}, menu)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, menu)

	local function closeMenu()
		menu.Visible = false
	end
	local function setSortText()
		sortLabel.Text = ""
		for _, o in options do
			if o.Id == active then
				sortLabel.Text = (if tabKind == "Cosmetics" then "" else "Sort: ") .. o.Label
			end
		end
		Parts.fit(sortLabel, 140, 22, 15)
	end
	local function openMenu()
		for _, c in menu:GetChildren() do
			if c:IsA("ImageButton") then
				c:Destroy()
			end
		end
		local w = math.max(sortW, 200)
		for i, o in options do
			local row = Parts.button(menu, {
				Name = "Option_" .. o.Id,
				Style = if o.Id == active then "Gold" else "Purple",
				Label = o.Label,
				TextSize = 22,
				Size = UDim2.fromOffset(w - 20, SORT_ROW),
				Order = i,
			})
			row.Activated:Connect(function()
				closeMenu()
				if o.Id ~= active then
					active = o.Id
					setSortText()
					if onSort then
						onSort(o.Id)
					end
				end
			end)
		end
		menu.Size = UDim2.fromOffset(w, #options * SORT_ROW + (#options - 1) * 8 + 20)
		menu.Position = UDim2.new(1, 0, 0, CONTROL_H + 4)
		menu.Visible = true
	end
	connect(conns, sort.Activated, function()
		if menu.Visible then
			closeMenu()
		else
			openMenu()
		end
	end)
	-- Outside tap closes the menu (the tap still reaches whatever is under it).
	connect(conns, UserInputService.InputBegan, function(io)
		if
			menu.Visible
			and (io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch)
		then
			local p = Vector2.new(io.Position.X, io.Position.Y)
			for _, g in { menu, sort } do
				local a, s = g.AbsolutePosition, g.AbsoluteSize
				if p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y then
					return
				end
			end
			closeMenu()
		end
	end)
	connect(conns, input:GetPropertyChangedSignal("Text"), function()
		if not muted and onSearch then
			onSearch(input.Text)
		end
	end)

	function api:SetKind(k: string)
		tabKind = k
		layout()
	end
	function api:SetPlaceholder(s: string)
		placeholder = s
		layout()
	end
	function api:SetQuery(s: string)
		muted = true
		input.Text = s
		muted = false
	end
	function api:OnSearch(cb)
		onSearch = cb
	end
	function api:SetSortOptions(list, activeId: string?)
		options, active = list, activeId or (list[1] and list[1].Id)
		setSortText()
		closeMenu()
	end
	function api:OnSort(cb)
		onSort = cb
	end
	function api:Destroy()
		disconnectAll(conns)
		root:Destroy()
	end
	return api
end

-- Grid ----------------------------------------------------------------------------------------------------

local GRID_FADE = 14 -- edge fade (design px)
local MIN_CARD_W = 96
-- Per-tab grid from the references: columns, card aspect (w/h), gap, side margin. Dice 5x2, Materials 4x3, Items 5x3, Cosmetics 4x3.
local GRIDS = {
	Dice = { cols = 5, aspect = 0.73, gap = 8, side = 18 },
	Materials = { cols = 4, aspect = 1.05, gap = 14, side = 27 },
	Items = { cols = 5, aspect = 0.98, gap = 8, side = 16 },
	Cosmetics = { cols = 4, aspect = 1.15, gap = 8, side = 12 },
}
local RARITY_CARD = {
	Common = "CardCommon",
	Uncommon = "CardUncommon",
	Rare = "CardRare",
	Epic = "CardEpic",
	Legendary = "CardLegendary",
	Mythic = "CardMythic",
	Secret = "CardSecret",
}
local COPPER_CARD = { Items = "CardCopperMaroon", Cosmetics = "CardCopper" }
-- Scrollbar sprites span their full width, so slice only a narrow centre column (no horizontal stretch).
local BAR = {
	ScrollTrack = Rect.new(19, 65, 22, 227),
	ScrollThumb = Rect.new(20, 37, 22, 133),
}

local function barSkin(inst, name: string, w: number)
	local s = Sprites[name]
	inst.Image = s.Image
	inst.ScaleType = Enum.ScaleType.Slice
	inst.SliceCenter = BAR[name]
	inst.SliceScale = w / s.Size.X
end

function Parts.Grid(parent)
	local api, conns = {}, {}
	local items, cards, selected, fallback, kind = {}, {}, nil, nil, "Dice"
	local onSelect

	local root = make("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = parent.ZIndex,
	}, parent)
	-- Whole rows at rest (sized in rebuild); the CanvasGroup's gradient fades the cut edges while scrolling.
	local fade = make("CanvasGroup", {
		Name = "Fade",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = root.ZIndex + 1,
	}, root)
	local fadeGradient = make("UIGradient", { Rotation = 90 }, fade)
	local scroll = make("ScrollingFrame", {
		Name = "GridScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 0, -- the styled bar below replaces the native one; wheel, touch and drag still scroll
		ZIndex = root.ZIndex + 1,
	}, fade)
	local gridPad = make("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 2),
	}, scroll)
	local layout = make("UIGridLayout", {
		CellSize = UDim2.fromOffset(134, 190),
		CellPadding = UDim2.fromOffset(8, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, scroll)
	local empty = Parts.text(root, {
		Name = "EmptyLabel",
		Text = "Nothing here yet",
		TextSize = 24,
		TextWrapped = true,
		Size = UDim2.new(1, -60, 0, 80),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		TextColor3 = SOFT,
		Visible = false,
		ZIndex = scroll.ZIndex + 1,
	})
	local track = img(root, {
		Name = "ScrollTrack",
		AnchorPoint = Vector2.new(1, 0),
		Visible = false,
		ZIndex = scroll.ZIndex + 2,
	})
	local thumb = img(track, { Name = "Thumb", AnchorPoint = Vector2.new(0.5, 0), ZIndex = track.ZIndex + 1 })
	local emptyText = "Nothing here yet"
	local visibleH, barW = 0, 12
	local updateFade

	-- Edges fade only where content is cut off: nothing at rest on the top row, nothing at the end of the list.
	-- The styled scrollbar shows only when the content overflows.
	function updateFade()
		local y, maxY = scroll.CanvasPosition.Y, math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
		local f = GRID_FADE / math.max(visibleH, 2 * GRID_FADE + 1)
		local top, bot = f * math.clamp(y / GRID_FADE, 0, 1), f * math.clamp((maxY - y) / GRID_FADE, 0, 1)
		local pts = {}
		table.insert(pts, if top > 0 then NumberSequenceKeypoint.new(0, 1) else NumberSequenceKeypoint.new(0, 0))
		if top > 0 then
			table.insert(pts, NumberSequenceKeypoint.new(top, 0))
		end
		if bot > 0 then
			table.insert(pts, NumberSequenceKeypoint.new(1 - bot, 0))
		end
		table.insert(pts, if bot > 0 then NumberSequenceKeypoint.new(1, 1) else NumberSequenceKeypoint.new(1, 0))
		fadeGradient.Transparency = NumberSequence.new(pts)
		track.Visible = maxY > 1 and visibleH > 0
		local win, canvas = scroll.AbsoluteWindowSize.Y, math.max(1, scroll.AbsoluteCanvasSize.Y)
		local thumbH = math.clamp(math.floor(visibleH * win / canvas), 40, math.max(40, visibleH))
		thumb.Size = UDim2.fromOffset(barW, thumbH)
		thumb.Position = UDim2.new(0.5, 0, 0, math.floor((visibleH - thumbH) * (if maxY > 0 then y / maxY else 0)))
	end
	connect(conns, scroll:GetPropertyChangedSignal("CanvasPosition"), updateFade)
	connect(conns, scroll:GetPropertyChangedSignal("AbsoluteCanvasSize"), updateFade)

	local cardW, cardH = 134, 190

	local function buildCard(item, order)
		local w, h = cardW, cardH
		local sc = math.clamp(w / 140, 0.72, 1)
		local function px(n: number): number
			return math.max(1, math.floor(n * sc + 0.5))
		end
		local card = img(scroll, { Name = "Card_" .. item.Id, LayoutOrder = order }, "ImageButton")
		local copper = COPPER_CARD[kind]
		Parts.skin(card, copper or RARITY_CARD[item.Rarity] or "CardCommon", if copper then 0.4 else 0.5)
		if item.Locked then
			card.ImageColor3 = Color3.fromRGB(140, 140, 150)
		end
		Parts.interact(card)
		-- Selected: gold rim over the card (the rarity fill stays visible), toggled by SetSelected.
		local sel = img(card, {
			Name = "SelRim",
			Position = UDim2.fromOffset(3, 3),
			Size = UDim2.new(1, -6, 1, -6),
			Visible = item.Id == selected,
		}, "Frame")
		make("UICorner", { CornerRadius = UDim.new(0, px(20)) }, sel)
		make("UIStroke", { Color = GOLD, Thickness = 4 }, sel)
		local function place(inst, y, pw, ph, anchorY)
			inst.AnchorPoint = Vector2.new(0.5, anchorY or 0)
			inst.Position = UDim2.new(0.5, 0, 0, y)
			inst.Size = UDim2.fromOffset(pw, ph)
		end
		-- top pill: EQUIPPED (dice) or the rarity tag, floating inset ~70% of the card width
		if item.TopTag then
			local eq = item.TopTagStyle == "Equipped"
			local pw = if eq then px(100) else math.floor(w * 0.7)
			local ph = if eq then px(25) else px(26)
			local pill = Parts.Pill(card, if eq then "Equipped" else item.Rarity, item.TopTag, {
				Name = "TopTag",
				W = pw,
				H = ph,
				TextSize = px(15),
			})
			place(pill, px(8), pw, ph)
		end
		local icon = img(card, { Name = "Icon" })
		local isz, itop
		if kind == "Dice" then
			isz, itop = math.floor(w * 0.62), math.floor(h * 0.16)
		elseif kind == "Materials" then
			isz, itop = math.floor(math.min(w * 0.62, h * 0.55)), math.floor(h * 0.27)
		elseif kind == "Items" then
			isz, itop = math.floor(h * 0.5), math.floor(h * 0.24)
		else
			isz, itop = math.floor(h * 0.54), math.floor(h * 0.2)
		end
		place(icon, itop, isz, isz)
		local has = item.Icon ~= nil and item.Icon ~= ""
		Parts.image(icon, if has then item.Icon else fallback)
		icon.ImageColor3 = if item.Locked
			then Color3.new(0.45, 0.45, 0.45)
			else item.Tint or (if has then WHITE else Parts.RarityColor[item.Rarity] or WHITE)
		if kind == "Dice" then
			local title = Parts.text(card, { Name = "Title", Text = item.Name, TextSize = px(18) })
			place(title, math.floor(h * 0.65), w - px(12), px(22), 0.5)
			if item.SubTag then
				local pw = math.floor(w * 0.8)
				local pill = Parts.Pill(card, item.Rarity, item.SubTag, {
					Name = "SubTag",
					W = pw,
					H = px(27),
					TextSize = px(15),
				})
				place(pill, math.floor(h * 0.8), pw, px(27), 0.5)
			end
			if item.Footer then
				local foot =
					Parts.text(card, { Name = "Footer", Text = item.Footer, TextSize = px(15), TextColor3 = WHITE })
				place(foot, math.floor(h * 0.92), w - px(12), px(18), 0.5)
			end
		elseif kind == "Cosmetics" then
			if item.Footer == "EQUIPPED" then
				local pw = math.floor(w * 0.78)
				local pill = Parts.Pill(card, "Equipped", "EQUIPPED", {
					Name = "Equipped",
					W = pw,
					H = px(27),
					TextSize = px(15),
					CheckLeft = true,
				})
				place(pill, h - px(10), pw, px(27), 1)
			else
				local nm = Parts.text(card, { Name = "Title", Text = string.upper(item.Name), TextSize = px(16) })
				place(nm, h - px(10), w - px(16), px(24), 1)
				Parts.fit(nm, w - px(20), px(16), 11)
			end
		elseif item.Footer then
			if kind == "Items" then
				local band = img(card, { Name = "QtyBand" }, "Frame")
				band.BackgroundTransparency = 0.35
				band.BackgroundColor3 = Color3.fromRGB(48, 16, 80)
				make("UICorner", { CornerRadius = UDim.new(0, px(10)) }, band)
				place(band, h - px(10), w - px(28), px(30), 1)
			end
			local qty = Parts.text(card, { Name = "Qty", Text = item.Footer, TextSize = px(22) })
			if kind == "Items" then
				place(qty, h - px(10), w - px(28), px(30), 1)
			else
				qty.AnchorPoint = Vector2.new(1, 1)
				qty.Position = UDim2.new(1, -math.floor(w * 0.13), 1, -px(8))
				qty.Size = UDim2.fromOffset(math.floor(w * 0.7), px(28))
				qty.TextXAlignment = Enum.TextXAlignment.Right
			end
		end
		if item.CornerBadge then
			local badge = img(card, {
				Name = "CornerBadge",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -px(14), 0, px(12)),
				Size = UDim2.fromOffset(px(25), px(28)),
			})
			Parts.image(badge, item.CornerBadge) -- "Lock" | "Check"
		end
		card.Activated:Connect(function()
			if onSelect then
				onSelect(item)
			end
		end)
		cards[item.Id] = card
	end

	local function rebuild()
		local g = GRIDS[kind]
		local compact = parent:GetAttribute("Compact")
		local W, H = parent.Size.X.Offset, parent.Size.Y.Offset
		local side, gap = if compact then 6 else g.side, if compact then 6 else g.gap
		local inner = W - 2 * side
		local cols = math.min(g.cols, math.max(1, math.floor((inner + gap) / (MIN_CARD_W + gap))))
		cardW = math.min(190, math.floor((inner - (cols - 1) * gap) / cols))
		cardH = math.floor(cardW / g.aspect)
		layout.CellSize = UDim2.fromOffset(cardW, cardH)
		layout.CellPadding = UDim2.fromOffset(gap, gap)
		-- Rows are left-aligned (a lone result sits in column 1); the whole column block is centred by padding.
		local pad = math.max(0, math.floor((W - (cols * cardW + (cols - 1) * gap)) / 2))
		gridPad.PaddingLeft, gridPad.PaddingRight = UDim.new(0, pad), UDim.new(0, pad)
		barW = math.clamp(pad - 8, 6, 14)
		local pitch = cardH + gap
		local rows = math.max(1, math.floor((H - 4 + gap) / pitch))
		visibleH = rows * pitch - gap + 4 -- leftover height stays inside the panel
		fade.Size = UDim2.new(1, 0, 0, visibleH)
		track.Size = UDim2.fromOffset(barW, visibleH)
		track.Position = UDim2.new(1, -3, 0, 0)
		barSkin(track, "ScrollTrack", barW)
		barSkin(thumb, "ScrollThumb", barW)
		updateFade()
		for _, c in cards do
			c:Destroy()
		end
		table.clear(cards)
		for i, item in items do
			buildCard(item, i)
		end
		empty.Text = emptyText
		empty.Visible = #items == 0
		updateFade()
	end
	connect(conns, parent:GetAttributeChangedSignal("Compact"), rebuild)
	connect(conns, parent:GetPropertyChangedSignal("Size"), rebuild)

	function api:SetKind(k: string)
		kind = if GRIDS[k] then k else "Dice"
	end
	function api:SetItems(list)
		items = list
		rebuild()
	end
	function api:SetSelected(id: string?)
		selected = id
		for cid, card in cards do
			card.SelRim.Visible = cid == id
		end
	end
	function api:OnSelect(cb)
		onSelect = cb
	end
	function api:SetEmptyText(s: string?)
		emptyText = s or "Nothing here yet"
		empty.Text = emptyText
	end
	-- Glyph (BagSprites key or id) for items without art; tinted by rarity.
	function api:SetFallback(ref: string?)
		fallback = ref
	end
	function api:ResetScroll()
		scroll.CanvasPosition = Vector2.zero
	end
	function api:GetScroll(): number
		return scroll.CanvasPosition.Y
	end
	function api:SetScroll(y: number)
		scroll.CanvasPosition = Vector2.new(0, y)
	end
	function api:Destroy()
		disconnectAll(conns)
		root:Destroy()
	end
	return api
end

-- Footer (loadout strip) ------------------------------------------------------------------------------------

function Parts.Footer(parent)
	local api, conns = {}, {}
	local onButton, onSlot, hint

	local root = make("Frame", {
		Name = "FooterStrip",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 97), -- bottom-anchored: the compact overlay grows upward when slots wrap
		ZIndex = parent.ZIndex,
	}, parent)
	-- Opaque backing for the compact overlay (it sits over the card grid).
	local backing = img(root, {
		Name = "Backing",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
		Visible = false,
	}, "Frame")
	backing.BackgroundTransparency = 0
	backing.BackgroundColor3 = Color3.fromRGB(58, 22, 84)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, backing)
	local strip = img(root, { Name = "Strip", Size = UDim2.fromScale(1, 1), ZIndex = backing.ZIndex + 1 })
	Parts.skinH(strip, "Strip", 97)
	local row = img(strip, { Name = "Row", Size = UDim2.fromScale(1, 1) }, "Frame")
	local rowLayout = make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 16),
	}, row)
	local label = Parts.text(row, {
		Name = "Label",
		Text = "LOADOUT",
		TextSize = 22,
		TextWrapped = true,
		Size = UDim2.fromOffset(112, 78),
		LayoutOrder = 1,
	})
	-- Native dividers (no sprite fits): white after the label, copper before the button.
	local function divider(name, w, color, order)
		local d = img(row, { Name = name, Size = UDim2.fromOffset(w, 65), LayoutOrder = order }, "Frame")
		d.BackgroundTransparency = 0
		d.BackgroundColor3 = color
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, d)
		return d
	end
	local div1 = divider("DividerWhite", 4, Color3.fromRGB(242, 240, 244), 2)
	local slotsFrame =
		img(row, { Name = "Slots", Size = UDim2.fromOffset(5 * 75 + 4 * 9, 78), LayoutOrder = 3 }, "Frame")
	local slotsLayout = make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 9),
	}, slotsFrame)
	local icons, slots = {}, {}
	for i = 1, 5 do
		local slot =
			img(slotsFrame, { Name = "Slot" .. i, Size = UDim2.fromOffset(75, 78), LayoutOrder = i }, "ImageButton")
		slot.Image = SlotFrame.Normal -- lobby deck-slot frame, drawn whole
		slot.ScaleType = Enum.ScaleType.Stretch
		Parts.interact(slot)
		slot.Activated:Connect(function()
			if onSlot then
				onSlot(i)
			end
		end)
		slots[i] = slot
		icons[i] = img(slot, {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(52, 52),
			Visible = false,
		})
	end
	local div2 = divider("DividerCopper", 3, Color3.fromRGB(192, 102, 58), 4)
	local btn = Parts.button(row, {
		Name = "Unequip",
		Style = "Purple",
		Label = "UNEQUIP ALL",
		TextSize = 20,
		Size = UDim2.fromOffset(151, 50),
		Order = 5,
	})
	btn.Activated:Connect(function()
		if onButton then
			onButton(hint)
		end
	end)
	-- Sizes by panel width: roomy (>=700), narrow full (label wraps, smaller slots/button) and compact overlay
	-- (slots only, fitted to the left panel width).
	local function layoutFooter()
		local w = parent.Size.X.Offset
		local compact = parent:GetAttribute("Compact")
		local dw, dh, labelW, btnW, btnH, gap = 75, 78, 112, 151, 50, 9
		if compact then
			gap, dw, dh = 4, 56, 56 -- touch floor: wrap into rows (3+2 on a narrow panel) instead of shrinking
		elseif w < 700 then
			dw, dh, labelW, btnW, gap = 56, 58, 84, 120, 6
		end
		label.Visible, btn.Visible, backing.Visible = not compact, not compact, compact
		div1.Visible, div2.Visible = not compact, not compact
		label.Size = UDim2.fromOffset(labelW, 78)
		label.TextSize = if labelW == 112 then 22 else 15
		rowLayout.Padding = UDim.new(0, if compact then 0 elseif w < 700 then 8 else 16)
		slotsLayout.Padding = UDim.new(0, gap)
		local perRow = if compact then math.clamp(math.floor((w - 24 + gap) / (dw + gap)), 1, 5) else 5
		local rows = math.ceil(5 / perRow)
		slotsLayout.Wraps = true
		slotsFrame.Size = UDim2.fromOffset(perRow * dw + (perRow - 1) * gap, rows * dh + (rows - 1) * gap)
		root.Size = UDim2.new(1, 0, 0, if rows > 1 then slotsFrame.Size.Y.Offset + 36 else 97)
		for i, slot in slots do
			slot.Size = UDim2.fromOffset(dw, dh)
			local ic = if dw == 75 then 55 else dw - 16
			icons[i].Size = UDim2.fromOffset(ic, ic)
		end
		btn.Size = UDim2.fromOffset(btnW, btnH)
		Parts.setButton(btn, { Label = btn.Label.Text })
	end
	connect(conns, parent:GetPropertyChangedSignal("Size"), layoutFooter)
	connect(conns, parent:GetAttributeChangedSignal("Compact"), layoutFooter)
	layoutFooter()

	function api:SetVisible(b: boolean)
		root.Visible = b
	end
	function api:SetSlots(ids)
		for i, icon in icons do
			local id = ids and ids[i]
			icon.Visible = id ~= nil and id ~= ""
			Parts.image(icon, id)
		end
	end
	function api:SetLabel(s: string)
		label.Text = s
	end
	function api:SetButton(o)
		hint = o.Hint
		Parts.setButton(btn, { Label = o.Label, Enabled = o.Enabled })
	end
	function api:OnSlot(cb)
		onSlot = cb
	end
	-- Pick mode: slots glow gold while the controller waits for the player to choose one.
	function api:SetSlotHighlight(on: boolean)
		for _, slot in slots do
			slot.ImageColor3 = if on then GOLD else WHITE
		end
	end
	function api:OnButton(cb)
		onButton = cb
	end
	function api:Destroy()
		disconnectAll(conns)
		root:Destroy()
	end
	return api
end

-- Detail ----------------------------------------------------------------------------------------------------

local STAT_GREEN = Color3.fromRGB(110, 222, 70)
local COPPER = Color3.fromRGB(201, 122, 90)
local BTN_W, BTN_GAP = 127, 8 -- action buttons: one size on every tab (3 per row, a 2-button row is centred)

-- One template for every tab, stacked top to bottom: top (rarity pill + status pill, or the ribbon header), art
-- (takes the spare height), name, subline, description, divider, extra (stats or stepper); action buttons are pinned.
function Parts.Detail(parent)
	local api, conns = {}, {}
	local onAction, onStep
	local fallback, lastModel
	local hasHeader, subH, descH, divH, extraH, nameH = false, 0, 0, 0, 0, 44
	local function compact(): boolean
		return parent:GetAttribute("Compact") == true
	end
	local function side(): number
		return if compact() then 10 else 20
	end

	local root = make("Frame", {
		Name = "DetailBody",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = parent.ZIndex,
	}, parent)
	local scroll = make("ScrollingFrame", {
		Name = "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -76), -- refit by relayout
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = GOLD,
		ZIndex = root.ZIndex + 1,
	}, root)
	local body =
		img(scroll, { Name = "Body", Size = UDim2.new(1, -40, 0, 490), Position = UDim2.fromOffset(20, 0) }, "Frame")
	local function slot(name, parentFrame)
		return img(parentFrame or body, {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.new(1, 0, 0, 30),
		}, "Frame")
	end
	local function centredRow(frame, gap)
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, gap),
		}, frame)
	end

	local tags = slot("TopTags")
	local header = slot("Header")
	local ribbon =
		img(header, { Name = "Ribbon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	Parts.image(ribbon, "NameRibbon")
	local ribbonText = Parts.text(ribbon, {
		Name = "Label",
		TextSize = 20,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.6, 0.6),
	}, 2)
	local preview = slot("Preview")
	local glow = img(preview, {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(150, 150),
	})
	local icon = img(preview, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(112, 112),
		ZIndex = glow.ZIndex + 1,
	})
	local name = Parts.text(body, { Name = "Name", TextSize = 38, AnchorPoint = Vector2.new(0.5, 0) })
	local subline = slot("Subline")
	centredRow(subline, 10)
	local descBox =
		img(body, { Name = "Description", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(1, 0, 0, 30) }) -- QtyField inset box when boxed, bare text otherwise
	local desc = Parts.text(descBox, {
		Name = "Text",
		TextSize = 18,
		TextWrapped = true,
		TextColor3 = WHITE,
		Size = UDim2.new(1, -28, 1, -12),
		Position = UDim2.fromOffset(14, 6),
	}, 2)
	local divider = img(body, { Name = "Divider", AnchorPoint = Vector2.new(0.5, 0) })
	Parts.image(divider, "DividerGold")
	local extra = slot("Extra")
	local actions = img(root, {
		Name = "ActionRow",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.new(1, -16, 0, 67),
		ZIndex = scroll.ZIndex + 1,
	}, "Frame")
	centredRow(actions, BTN_GAP)
	local placeholder = Parts.text(root, {
		Name = "Placeholder",
		Text = "Select an item",
		TextSize = 24,
		TextColor3 = SOFT,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -40, 0, 40),
	})

	local function bodyW(): number
		return parent.Size.X.Offset - 2 * side()
	end

	local function relayout()
		local c = compact()
		local btnH, pad = if c then 48 else 67, if c then 8 else 22
		local gap = if c then 4 else 6
		local y0 = if c then 6 else 16
		local viewH = parent.Size.Y.Offset - (btnH + pad + (if c then 4 else 8))
		local s = side()
		scroll.Size = UDim2.new(1, 0, 0, math.max(0, viewH))
		actions.Size = UDim2.new(1, -16, 0, btnH)
		actions.Position = UDim2.new(0.5, 0, 1, -pad)
		body.Position = UDim2.fromOffset(s, 0)
		local w = bodyW()
		divH = if divider.Visible then math.floor(w * 0.9 * 54 / 709) else 0
		local topH = if hasHeader then (if c then 34 else 64) else (if c then 24 else 30)
		local heights = { topH, nameH, subH, descH, divH, extraH }
		local n, fixed = 1, 0 -- 1 = the art block
		for _, h in heights do
			if h > 0 then
				n += 1
				fixed += h
			end
		end
		local free = viewH - y0 - fixed - gap * (n - 1)
		local artH = math.clamp(free, if c then 32 else 110, 170)
		local g = gap + (if c then 0 else math.clamp((free - artH) / math.max(1, n - 1), 0, 14))
		local y = y0 -- clear of the panel rim
		local function put(inst, h)
			inst.AnchorPoint = Vector2.new(0.5, 0)
			inst.Position = UDim2.new(0.5, 0, 0, math.floor(y))
			inst.Size = UDim2.new(1, 0, 0, h)
			y += h + g
		end
		tags.Visible, header.Visible = not hasHeader, hasHeader
		put(if hasHeader then header else tags, topH)
		local artY = y
		put(preview, artH)
		glow.Size = UDim2.fromOffset(
			math.min(artH * 1.5, 2 * (artY + artH / 2), w),
			math.min(artH * 1.5, 2 * (artY + artH / 2), w)
		)
		icon.Size = UDim2.fromOffset(artH * 0.92, artH * 0.92)
		put(name, nameH)
		if subH > 0 then
			put(subline, subH)
		end
		if descH > 0 then
			put(descBox, descH)
		end
		if divH > 0 then
			put(divider, divH)
			divider.Size = UDim2.fromOffset(math.floor(w * 0.9), divH)
		end
		if extraH > 0 then
			put(extra, extraH)
		end
		local total = math.max(0, y - g)
		body.Size = UDim2.new(1, -2 * s, 0, total)
		scroll.CanvasSize = UDim2.fromOffset(0, total)
		ribbon.Size = UDim2.fromOffset(math.floor(topH * 547 / 125), topH)
		ribbonText.Size = UDim2.fromScale(0.66, 0.6)
		Parts.fit(ribbonText, ribbon.Size.X.Offset * 0.66, if c then 14 else 20, 10)
		-- the Description frame/text is wholly inside body width
		subline.Visible, descBox.Visible, extra.Visible = subH > 0, descH > 0, extraH > 0
	end

	local function renderSubline(sub)
		clearChildren(subline, "UIListLayout")
		local c = compact()
		subH = 0
		if not sub then
			return
		end
		if sub.Kind == "Level" then
			subH = if c then 24 else 28
			local txt = ("Lv. %d / %d"):format(sub.Value, sub.Max)
			local size = if c then 15 else 20
			local tw = measure(txt, size) + 6
			Parts.text(subline, { Text = txt, TextSize = size, Size = UDim2.fromOffset(tw, subH), LayoutOrder = 1 }, 2)
			local barW = math.clamp(bodyW() - tw - 12, 100, 218)
			local track = img(subline, { Name = "LevelBar", Size = UDim2.fromOffset(barW, 26), LayoutOrder = 2 })
			Parts.skinH(track, "LevelTrack", 26)
			-- Fill is sized to the value (never cropped): same SliceScale as the track, never narrower than its caps.
			local ts, fs = Sprites.LevelTrack, Sprites.LevelFill
			local k = 26 / ts.Size.Y
			local fh = fs.Size.Y * k
			local capsW = fs.Slice and (fs.Size.X - (fs.Slice.Max.X - fs.Slice.Min.X)) * k or 0
			local fillW = math.max(capsW, (barW - 8) * math.clamp(sub.Value / math.max(1, sub.Max), 0, 1))
			local fill = img(track, {
				Name = "Fill",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 4, 0.5, 0),
				Size = UDim2.fromOffset(fillW, fh),
				Visible = sub.Value > 0,
			})
			Parts.skin(fill, "LevelFill", k)
		elseif sub.Kind == "Qty" then
			-- dark pill with a copper rim (no sprite): "Quantity: x1,248"
			subH = if c then 24 else 30
			local size = if c then 15 else 19
			local pill = img(subline, {
				Name = "QtyPill",
				Size = UDim2.fromOffset(math.max(150, measure(sub.Text, size) + 40), subH),
			}, "Frame")
			pill.BackgroundTransparency = 0
			pill.BackgroundColor3 = Color3.fromRGB(75, 24, 62)
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
			make("UIStroke", { Color = COPPER, Thickness = 2 }, pill)
			Parts.text(pill, { Text = sub.Text, TextSize = size, Size = UDim2.fromScale(1, 1) }, 2)
		else
			subH = if c then 24 else 28
			Parts.Pill(
				subline,
				"Purple",
				sub.Text,
				{ H = subH, MinW = 90, TextSize = if c then 15 else 17, Icon = sub.Icon }
			)
		end
	end

	local function renderExtra(model)
		for _, ch in extra:GetChildren() do
			ch:Destroy()
		end
		local c = compact()
		extraH = 0
		local list = model.Stats
		if list then
			local rowH, pitch = if c then 26 else 30, if c then 28 else 33
			local hp = Parts.Pill(
				extra,
				"Purple",
				"COMBAT STATS",
				{ Name = "StatsHeader", H = if c then 22 else 26, MinW = 190, TextSize = if c then 15 else 17 }
			)
			hp.AnchorPoint, hp.Position = Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0)
			local top = hp.Size.Y.Offset + 4
			for i = 1, math.min(#list, 4) do
				local st = list[i]
				local r = img(extra, {
					Name = "Stat" .. i,
					Position = UDim2.fromOffset(0, top + (i - 1) * pitch),
					Size = UDim2.new(1, 0, 0, rowH),
				})
				Parts.skinH(r, "StatRow", rowH)
				local ic = img(r, {
					Size = UDim2.fromOffset(rowH - 4, rowH - 4),
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 8, 0.5, 0),
				})
				Parts.image(ic, st.Icon)
				Parts.text(r, {
					Text = st.Label,
					TextSize = if c then 15 else 19,
					TextXAlignment = Enum.TextXAlignment.Left,
					Position = UDim2.fromOffset(rowH + 12, 0),
					Size = UDim2.new(0.55, -(rowH + 12), 1, 0),
				}, 2)
				Parts.text(r, {
					Text = st.Value,
					TextSize = if c then 16 else 22,
					TextXAlignment = Enum.TextXAlignment.Right,
					TextColor3 = st.Color or STAT_GREEN,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -12, 0, 0),
					Size = UDim2.fromScale(0.4, 1),
				}, 2)
			end
			extraH = top + (math.min(#list, 4) - 1) * pitch + rowH
		elseif model.Stepper then
			local st = model.Stepper
			local rowH = if c then 44 else 56
			local labH = if c then 0 else 22 -- the label is dropped on short screens
			Parts.text(extra, {
				Name = "Label",
				Text = "Use Quantity:",
				TextSize = 19,
				Size = UDim2.new(1, 0, 0, labH),
				Visible = not c,
			}, 2)
			local r = img(extra, {
				Name = "Stepper",
				Position = UDim2.fromOffset(0, if c then 0 else labH + 4),
				Size = UDim2.new(1, 0, 0, rowH),
			}, "Frame")
			centredRow(r, math.floor(8 * math.min(1, bodyW() / 336)))
			local on = st.Enabled ~= false
			local k = math.min(1, bodyW() / 336)
			local function stepBtn(nm, sprite, w, order, delta, str)
				local b = img(
					r,
					{ Name = nm, Size = UDim2.fromOffset(math.floor(w * k), rowH), LayoutOrder = order },
					"ImageButton"
				)
				Parts.skinH(b, sprite, rowH)
				b.ScaleType = Enum.ScaleType.Stretch -- whole art at its aspect, no slicing
				b.ImageColor3 = if on then WHITE else DISABLED_TINT
				Parts.interact(b)
				if str then
					Parts.text(
						b,
						{ Text = str, TextSize = if str == "MAX" then 22 else 34, Size = UDim2.fromScale(1, 1) }
					)
				end
				b.Activated:Connect(function()
					if onStep then
						onStep(delta)
					end
				end)
			end
			stepBtn("Minus", "QtyMinus", 56, 1, -1, "\u{2212}")
			local field =
				img(r, { Name = "Field", Size = UDim2.fromOffset(math.floor(112 * k), rowH), LayoutOrder = 2 })
			Parts.skinH(field, "QtyField", rowH)
			field.ImageColor3 = if on then WHITE else DISABLED_TINT
			Parts.text(
				field,
				{ Text = "x" .. tostring(st.Qty), TextSize = if c then 20 else 24, Size = UDim2.fromScale(1, 1) }
			)
			stepBtn("Plus", "QtyPlus", 56, 3, 1, "+")
			stepBtn("Max", "BtnPurple", 88, 4, "max", "MAX")
			extraH = (if c then 0 else labH + 4) + rowH
		end
		extra.Visible = extraH > 0
	end

	-- Buttons: one size (127x67, 127x56 compact) shrunk equally when the panel is narrower than 3 of them.
	local function layoutButtons()
		local w = math.min(BTN_W, math.floor((parent.Size.X.Offset - 16 - 2 * BTN_GAP) / 3))
		local h = if compact() then 48 else 67
		for _, btn in actions:GetChildren() do
			if btn:IsA("ImageButton") then
				btn.Size = UDim2.fromOffset(w, h)
				Parts.setButton(btn, { Label = btn.Label.Text, Style = btn:GetAttribute("Style") })
			end
		end
	end
	local function refresh()
		relayout()
		layoutButtons()
	end
	connect(conns, parent:GetPropertyChangedSignal("Size"), function()
		if lastModel then
			api:Show(lastModel)
		else
			refresh()
		end
	end)
	connect(conns, parent:GetAttributeChangedSignal("Compact"), function()
		if lastModel then
			api:Show(lastModel)
		end
	end)

	function api:SetButtons(list)
		clearChildren(actions, "UIListLayout")
		for i, b in list do
			local btn = Parts.button(actions, {
				Name = "Action" .. i,
				Style = b.Style,
				Label = b.Label,
				Enabled = b.Enabled,
				Icon = b.Icon,
				Order = i,
				TextSize = 30,
				Size = UDim2.fromOffset(BTN_W, 67),
			})
			btn:SetAttribute("Style", b.Style)
			btn.Activated:Connect(function()
				if onAction then
					onAction(b.Id, b.Hint)
				end
			end)
		end
		layoutButtons()
	end

	function api:Show(model)
		lastModel = model
		local on = model ~= nil
		scroll.Visible, actions.Visible, placeholder.Visible = on, on, not on
		if not on then
			return
		end
		local c = compact()
		hasHeader = model.Header ~= nil
		ribbonText.Text = model.Header or ""
		clearChildren(tags, "UIListLayout")
		local th = if c then 24 else 30
		local left = Parts.Pill(
			tags,
			model.Rarity,
			string.upper(model.Rarity),
			{ Name = "Rarity", H = th, MinW = if c then 0 else 116, TextSize = if c then 14 else 17 }
		)
		left.AnchorPoint, left.Position = Vector2.zero, UDim2.fromScale(0, 0)
		if model.StatusTag then
			local right = Parts.Pill(
				tags,
				"Equipped",
				model.StatusTag,
				{ Name = "Status", H = th, MinW = if c then 0 else 116, TextSize = if c then 14 else 17 }
			)
			right.AnchorPoint, right.Position = Vector2.new(1, 0), UDim2.fromScale(1, 0)
		end
		Parts.skin(glow, GLOW[model.Rarity] or "GlowCommon")
		local has = model.Icon ~= nil and model.Icon ~= ""
		Parts.image(icon, if has then model.Icon else fallback)
		icon.ImageColor3 = model.Tint or (if has then WHITE else Parts.RarityColor[model.Rarity] or WHITE)
		-- name: caps, 38 px; shrinks to fit one line, wraps to two only when it still does not fit
		local up, w = string.upper(model.Name), bodyW()
		local nameMax, nameMin = if c then 24 else 38, if c then 18 else 24
		name.Text = up
		name.Size = UDim2.new(1, 0, 0, if c then 26 else 44)
		if measure(up, nameMin) > w then
			name.TextWrapped = true
			name.TextSize = nameMin
			nameH = (if c then 26 else 44) + (if c then 18 else 24)
			name.Size = UDim2.new(1, 0, 0, nameH)
		else
			name.TextWrapped = false
			Parts.fit(name, w, nameMax, nameMin)
			nameH = if c then 26 else 44
		end
		renderSubline(model.Subline)
		-- description: boxed (QtyField) on materials/items, bare text elsewhere; at most 3 lines (2 compact)
		local text = model.Description or ""
		local dsize, lineH = if c then 15 else 18, if c then 18 else 22
		desc.TextSize = dsize
		desc.Text = text
		descBox.Visible = text ~= ""
		descH = 0
		if text ~= "" then
			local lines =
				math.min(if c then 2 else 3, math.max(1, math.ceil(measure(text, dsize) / math.max(1, w - 28))))
			descH = lines * lineH + (if model.DescBox then (if c then 10 else 22) else 6)
			if model.DescBox then
				Parts.skin(descBox, "QtyField", math.clamp(descH / Sprites.QtyField.Size.Y, 0.3, 1))
			else
				descBox.Image = ""
			end
		end
		divider.Visible = model.Divider == true
		renderExtra(model)
		refresh()
		self:SetButtons(model.Buttons)
	end
	function api:OnAction(cb)
		onAction = cb
	end
	function api:OnStep(cb)
		onStep = cb
	end
	function api:SetFallback(ref: string?)
		fallback = ref
	end
	function api:Destroy()
		disconnectAll(conns)
		root:Destroy()
	end
	api:Show(nil)
	return api
end

return Parts
