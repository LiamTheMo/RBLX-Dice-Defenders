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
	Wide = "PillWide",
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

-- Box size that draws sprite `name` with its VISIBLE ink (the Ink rect) at inkW x inkH: returns w, h, k.
-- 9-sliced sprites keep their margins at the slice scale k (default inkH / ink height); plain ones stretch to fit.
function Parts.inkBox(name: string, inkW: number, inkH: number, k: number?)
	local s = Sprites[name]
	local ink = s.Ink
	if not s.Slice then
		return s.Size.X * inkW / ink.Width, s.Size.Y * inkH / ink.Height, nil
	end
	k = k or inkH / ink.Height
	return inkW + (s.Size.X - ink.Width) * k, inkH + (s.Size.Y - ink.Height) * k, k
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
function Parts.fitSize(str: string, availW: number, maxSize: number, minSize: number): number
	local w = measure(str, maxSize)
	if w > availW and w > 0 then
		return math.max(minSize, math.floor(maxSize * availW / w))
	end
	return maxSize
end
function Parts.fit(label, availW: number, maxSize: number, minSize: number)
	label.TextSize = Parts.fitSize(label.Text, availW, maxSize, minSize)
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
	if o.InkH then -- Full tier: size by the visible ink (InkW, or measured text), not the sprite box
		local inkW = o.InkW or math.max(o.MinW or 0, measure(str, size) + 28 + (if deco then o.InkH else 0))
		w, h = Parts.inkBox(PILL[style] or "PillGrey", inkW, o.InkH)
	end
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
	if o.W or o.InkH then
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
		local fixed = btn:GetAttribute("TextFixed") -- action rows: one label size on every tab
		if fixed then
			label.TextSize = fixed
		else
			Parts.fit(label, btn.Size.X.Offset - 16 - inset, btn:GetAttribute("TextMax"), 15)
		end
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

-- Search/sort: visible ink 44 px tall as in the reference, so the box is 44 / ink fraction (49); menu rows stay touch-size.
local CONTROL_H, SORT_ROW = 49, 56
local SORT_W, SEARCH_W = 237, 443 -- box widths for ink 232 / 438

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
		PaddingRight = UDim.new(0, 16),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 9),
	}, root)

	local search = img(root, { Name = "Search" })
	Parts.skinH(search, "Search", CONTROL_H)
	local mag = img(search, {
		Name = "Magnifier",
		Size = UDim2.fromOffset(32, 32),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
	})
	Parts.image(mag, "Magnifier")
	local input = make("TextBox", {
		Name = "Input",
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		Font = FONT,
		TextSize = 28,
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
		Size = UDim2.fromOffset(32, 32),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
	})
	Parts.image(arrows, "SortArrows")
	local sortLabel = Parts.text(sort, {
		Name = "Label",
		TextSize = 28,
		Position = UDim2.fromOffset(62, 0),
		Size = UDim2.new(1, -100, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- Narrow left panels: the sort button becomes arrows only (a plain button sprite) and the placeholder
	-- shortens to its first word at 18 px, so the search box stays readable.
	local sortW = SORT_W
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
		TextSize = 26,
		Visible = false,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(64, CONTROL_H),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local function layout()
		local inner = parent.Size.X.Offset - 40 -- design px (the shell sets slot sizes in offsets)
		sortW = if inner >= 440 then SORT_W else 56
		if sortW == SORT_W then
			Parts.skinH(sort, "Sort", CONTROL_H)
			sort.ScaleType = Enum.ScaleType.Stretch -- the baked chevron must not meet a 9-slice edge
		else
			Parts.skinH(sort, "BtnPurple", CONTROL_H)
		end
		input.TextSize = if sortW == SORT_W then 28 else 18
		input.PlaceholderText = if sortW == SORT_W then placeholder else placeholder:match("%S+") or placeholder
		sort.Size = UDim2.fromOffset(sortW, CONTROL_H)
		sort.Position = UDim2.fromScale(1, 0)
		local tagW = if tabKind == "Cosmetics" and sortW == SORT_W then 72 else 0
		search.Size = UDim2.fromOffset(math.min(SEARCH_W, inner - sortW - tagW - 16), CONTROL_H) -- 440 as in the reference; spare width sits between the boxes
		sortTag.Visible = tagW > 0
		sortTag.Position = UDim2.new(1, -sortW - 8, 0, 0)
		local gapL, gapR = search.Size.X.Offset, inner - sortW - tagW
		divider.Visible = tabKind ~= "Cosmetics" and tabKind ~= "Dice" and sortW == SORT_W and gapR - gapL >= 24
		divider.Position = UDim2.fromOffset(math.floor((gapL + gapR) / 2), CONTROL_H / 2)
		sortLabel.Visible = sortW == SORT_W
		arrows.Position = if sortW == SORT_W then UDim2.new(0, 14, 0.5, 0) else UDim2.new(0.5, -14, 0.5, 0)
		input.Position = UDim2.fromOffset(60, 0)
		input.Size = UDim2.new(1, -(60 + 16), 1, 0)
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
		Parts.fit(sortLabel, 126, 28, 15)
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
-- Per-tab grid from the references (ink px): columns, rows (card height follows the slot), gaps, side margin.
-- aspect (w/h) only drives the Compact tier. Dice 5x2, Materials 4x3, Items 5x3, Cosmetics 4x3.
local GRIDS = {
	Dice = { cols = 5, rows = 2, aspect = 0.73, gx = 8, gy = 10, side = 22, icon = 0.68, iconY = 0.375 },
	Materials = { cols = 4, rows = 3, aspect = 1.05, gx = 14, gy = 8, side = 27, icon = 0.78, iconY = 0.51 },
	Items = { cols = 5, rows = 3, aspect = 0.98, gx = 8, gy = 16, side = 6, icon = 0.8, iconY = 0.53 },
	Cosmetics = { cols = 4, rows = 3, aspect = 1.15, gx = 8, gy = 14, side = 12, icon = 0.78, iconY = 0.51 },
}
local CARD_M = 5 -- card sprite transparent margin (both sides) at SliceScale 0.5: box = visible card + 5
local BOT, TOP = 4, 10 -- Full: first row starts TOP below the toolbar; visible rows end BOT above the slot bottom
local SELECTED_COPPER = { Items = "CardCopperSelectedMaroon", Cosmetics = "CardCopperSelected" }
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

	local cardW, cardH = 134, 190 -- visible (ink) card size; the cell adds CARD_M
	local compactNow, cellM = false, 0
	local function tsize(full: number, small: number): number -- Full tier text size vs the old size on phones
		return if compactNow then small else full
	end

	local function buildCard(item, order)
		local w, h = cardW + cellM, cardH + cellM
		local sc = math.clamp(cardW / 140, 0.72, 1)
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
		-- Selected, toggled by SetSelected: glowing copper card (Items/Cosmetics) or a thick gold rim ON the card rim
		-- (inset by the sprite margin) over the rarity fill.
		local sel
		local glowName = SELECTED_COPPER[kind]
		if glowName then
			local k, g = 0.4, 14 * 0.4 -- 14 source px of glow at slice scale 0.4
			local bw, bh = Parts.inkBox(glowName, cardW + 2 * g, cardH + 2 * g, k)
			local gs = Sprites[glowName]
			sel = img(card, {
				Name = "SelRim",
				AnchorPoint = Vector2.new(0.5, 0.5),
				-- the ink is not centred in the box: shift so the glowing card is centred
				Position = UDim2.new(
					0.5,
					(gs.Size.X / 2 - (gs.Ink.Min.X + gs.Ink.Max.X) / 2) * k,
					0.5,
					(gs.Size.Y / 2 - (gs.Ink.Min.Y + gs.Ink.Max.Y) / 2) * k
				),
				Size = UDim2.fromOffset(bw, bh),
				Visible = item.Id == selected,
			})
			Parts.skin(sel, glowName, k)
		else
			local t = if compactNow then 3 else 7
			sel = img(card, {
				Name = "SelRim",
				Position = UDim2.fromOffset(cellM / 2 + t, cellM / 2 + t),
				Size = UDim2.new(1, -(cellM + 2 * t), 1, -(cellM + 2 * t)),
				Visible = item.Id == selected,
			}, "Frame")
			make("UICorner", { CornerRadius = UDim.new(0, px(14)) }, sel)
			make("UIStroke", { Color = GOLD, Thickness = t }, sel)
		end
		if kind == "Materials" then -- gold check at the selected card's top-right
			local bw, bh = Parts.inkBox("CheckBadge", 36, 36)
			local badge = img(card, {
				Name = "SelBadge",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -2, 0, 5),
				Size = UDim2.fromOffset(bw, bh),
				Visible = item.Id == selected,
				ZIndex = card.ZIndex + 6,
			})
			Parts.image(badge, "CheckBadge")
			badge.ScaleType = Enum.ScaleType.Stretch
		end
		local function place(inst, y, pw, ph, anchorY)
			inst.AnchorPoint = Vector2.new(0.5, anchorY or 0)
			inst.Position = UDim2.new(0.5, 0, 0, y)
			inst.Size = UDim2.fromOffset(pw, ph)
		end
		-- top pill: EQUIPPED (dice) or the rarity tag, floating inset ~70% of the card width
		if item.TopTag then
			local eq = item.TopTagStyle == "Equipped"
			local pill = Parts.Pill(card, if eq then "Equipped" else item.Rarity, item.TopTag, {
				Name = "TopTag",
				InkW = if eq then px(100) else math.floor(cardW * 0.6),
				InkH = px(24),
				TextSize = px(tsize(20, 15)),
			})
			pill.AnchorPoint = if eq then Vector2.zero else Vector2.new(0.5, 0)
			-- Equipped: left-aligned 5 px inside the card; rarity tags centred
			pill.Position = UDim2.new(if eq then 0 else 0.5, if eq then 3 else 0, 0, px(7))
		end
		local icon = img(card, { Name = "Icon" })
		local isz, itop
		if compactNow then -- phone tier keeps the small icons clear of the tags
			if kind == "Dice" then
				isz, itop = math.floor(w * 0.62), math.floor(h * 0.16)
			elseif kind == "Materials" then
				isz, itop = math.floor(math.min(w * 0.62, h * 0.55)), math.floor(h * 0.27)
			elseif kind == "Items" then
				isz, itop = math.floor(h * 0.5), math.floor(h * 0.24)
			else
				isz, itop = math.floor(h * 0.54), math.floor(h * 0.2)
			end
		else
			if kind == "Dice" then
				isz = math.floor(w * GRIDS.Dice.icon)
			elseif kind == "Materials" then
				isz = math.floor(math.min(w * 0.7, h * GRIDS.Materials.icon))
			else
				isz = math.floor(h * GRIDS[kind].icon)
			end
			itop = math.floor(h * GRIDS[kind].iconY - isz / 2)
		end
		place(icon, itop, isz, isz)
		local has = item.Icon ~= nil and item.Icon ~= ""
		Parts.image(icon, if has then item.Icon else fallback)
		icon.ImageColor3 = if item.Locked
			then Color3.new(0.45, 0.45, 0.45)
			else item.Tint or (if has then WHITE else Parts.RarityColor[item.Rarity] or WHITE)
		if kind == "Dice" then
			local title = Parts.text(card, { Name = "Title", Text = item.Name, TextSize = px(tsize(25, 18)) })
			place(title, math.floor(h * 0.65), w - px(12), px(26), 0.5)
			Parts.fit(title, w - px(14), px(tsize(25, 18)), 11)
			if item.SubTag then
				local pill = Parts.Pill(card, item.Rarity, item.SubTag, {
					Name = "SubTag",
					InkW = math.floor(cardW * 0.8),
					InkH = px(tsize(24, 22)),
					TextSize = px(tsize(20, 15)),
				})
				pill.AnchorPoint = Vector2.new(0.5, 0.5)
				pill.Position = UDim2.new(0.5, 0, 0, math.floor(h * 0.8))
			end
			if item.Footer then
				local foot = Parts.text(
					card,
					{ Name = "Footer", Text = item.Footer, TextSize = px(tsize(22, 15)), TextColor3 = WHITE }
				)
				place(foot, math.floor(h * 0.895), w - px(12), px(24), 0.5)
			end
		elseif kind == "Cosmetics" then
			if item.Footer == "EQUIPPED" then
				local pill = Parts.Pill(card, "Equipped", "EQUIPPED", {
					Name = "Equipped",
					InkW = math.floor(cardW * 0.78),
					InkH = px(30),
					TextSize = px(tsize(22, 15)),
					CheckLeft = true,
				})
				pill.AnchorPoint = Vector2.new(0.5, 1)
				pill.Position = UDim2.new(0.5, 0, 0, h - px(10))
			else
				local nm =
					Parts.text(card, { Name = "Title", Text = string.upper(item.Name), TextSize = px(tsize(23, 16)) })
				place(nm, h - px(10), w - px(16), px(28), 1)
				Parts.fit(nm, w - px(18), px(tsize(23, 16)), 11)
			end
		elseif item.Footer then
			if kind == "Items" then
				local band = img(card, { Name = "QtyBand" }, "Frame")
				band.BackgroundTransparency = 0.5
				band.BackgroundColor3 = Color3.fromRGB(48, 16, 80)
				make("UICorner", { CornerRadius = UDim.new(0, px(14)) }, band)
				place(band, h - px(10), w - px(28), px(32), 1)
			end
			local qty = Parts.text(card, { Name = "Qty", Text = item.Footer, TextSize = px(tsize(34, 22)) })
			if kind == "Items" then
				place(qty, h - px(10), w - px(28), px(32), 1)
			else
				qty.AnchorPoint = Vector2.new(1, 1)
				qty.Position = UDim2.new(1, -math.floor(w * 0.13), 1, -px(8))
				qty.Size = UDim2.fromOffset(math.floor(w * 0.7), px(34))
				qty.TextXAlignment = Enum.TextXAlignment.Right
			end
		end
		if item.CornerBadge then
			local badge = img(card, {
				Name = "CornerBadge",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -px(14), 0, px(12)),
				Size = UDim2.fromOffset(px(28), px(31)),
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
		compactNow = compact == true
		local W, H = parent.Size.X.Offset, parent.Size.Y.Offset
		local side = if compact then 6 else g.side
		local gx, gy = if compact then 6 else g.gx, if compact then 6 else g.gy
		local m = if compact then 0 else CARD_M -- visible card + margin = cell
		cellM = m
		local inner = W - 2 * side
		local cols = math.min(g.cols, math.max(1, math.floor((inner + gx) / (MIN_CARD_W + gx))))
		cardW = math.min(190, math.floor((inner - (cols - 1) * gx) / cols))
		if compact then
			cardH = math.floor(cardW / g.aspect)
		else -- whole rows fill the slot: the last row ends BOT above it
			cardH = math.floor((H - BOT - TOP - m - (g.rows - 1) * gy) / g.rows)
		end
		layout.CellSize = UDim2.fromOffset(cardW + m, cardH + m)
		layout.CellPadding = UDim2.fromOffset(gx - m, gy - m)
		-- Rows are left-aligned (a lone result sits in column 1); the whole column block is centred by padding.
		local pad = math.max(0, math.floor((W - (cols * cardW + (cols - 1) * gx)) / 2 - m / 2))
		gridPad.PaddingLeft, gridPad.PaddingRight = UDim.new(0, pad), UDim.new(0, pad)
		barW = if compact then math.clamp(pad - 8, 6, 14) else 21 -- Full: thumb ink 17 px
		local pt = if compact then 2 else TOP
		gridPad.PaddingTop = UDim.new(0, pt)
		local pitch = cardH + gy
		local rows = math.max(1, math.floor((H - pt - 2 - m + gy) / pitch))
		visibleH = rows * pitch - gy + pt + 2 + m -- cells overhang the pitch by their margin -- leftover height stays inside the panel
		fade.Size = UDim2.new(1, 0, 0, visibleH)
		track.Size = UDim2.fromOffset(barW, visibleH)
		track.Position = UDim2.new(1, if compact then -3 else -7, 0, 0) -- Full: 5 px clear of the panel rim
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
			local badge = card:FindFirstChild("SelBadge")
			if badge then
				badge.Visible = cid == id
			end
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
	local rowPad = make("UIPadding", {}, row) -- Full: row contents sit 7 px left of the strip centre as in the reference
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
		TextSize = 26,
		TextWrapped = true,
		Size = UDim2.fromOffset(118, 78),
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
		local dw, dh, labelW, btnW, btnH, gap = 75, 78, 118, 151, 50, 9
		if compact then
			gap, dw, dh = 4, 56, 56 -- touch floor: wrap into rows (3+2 on a narrow panel) instead of shrinking
		elseif w < 700 then
			dw, dh, labelW, btnW, gap = 56, 58, 84, 120, 6
		end
		label.Visible, btn.Visible, backing.Visible = not compact, not compact, compact
		div1.Visible, div2.Visible = not compact, not compact
		label.Size = UDim2.fromOffset(labelW, 78)
		label.TextSize = if labelW == 118 then 26 else 15
		rowPad.PaddingRight = UDim.new(0, if compact then 0 else 14)
		rowLayout.Padding = UDim.new(0, if compact then 0 elseif w < 700 then 8 else 16)
		slotsLayout.Padding = UDim.new(0, gap)
		local perRow = if compact then math.clamp(math.floor((w - 24 + gap) / (dw + gap)), 1, 5) else 5
		local rows = math.ceil(5 / perRow)
		slotsLayout.Wraps = true
		slotsFrame.Size = UDim2.fromOffset(perRow * dw + (perRow - 1) * gap, rows * dh + (rows - 1) * gap)
		root.Size = if compact
			then UDim2.new(1, 0, 0, if rows > 1 then slotsFrame.Size.Y.Offset + 36 else 97)
			else UDim2.fromScale(1, 1) -- Full: the whole footer box is the strip (visible 242-1018 x 734-832)
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
local GOLD_TEXT = "#F9C735"
-- Action buttons: one size on every tab. Full: ink 120x70 (box 129x82), 8 px ink gap; Compact: 127x48, 8 px gap.
local BTN_W, BTN_H, BTN_GAP = 129, 82, -1 -- box overlaps by the sprite margins: ink 120x70, 8 px ink gap
local BTN_DROP = 12 -- Full: the sprite shadow rim hangs below the slot bottom

-- One template for every tab. Full tier: elements sit at reference offsets from the slot top (art overlaps the tag
-- row, name overlaps the art), later blocks flow with model.Gap; the action row is pinned to the slot bottom and the
-- content always fits (no scrollbar). Compact keeps the old stacked flow with a scroll.
function Parts.Detail(parent)
	local api, conns = {}, {}
	local onAction, onStep
	local fallback, lastModel
	local hasHeader, subH, descH, divH, extraH, nameH = false, 0, 0, 0, 0, 44
	local lay = {}
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
		return make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, gap),
		}, frame)
	end

	local tags = slot("TopTags")
	tags.ZIndex = body.ZIndex + 6 -- tags and the ribbon sit over the art glow
	local header = slot("Header")
	header.ZIndex = body.ZIndex + 6
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
	local flagL = img(body, { Name = "FlagLeft", AnchorPoint = Vector2.new(0.5, 0), Visible = false })
	Parts.image(flagL, "CosFlagLeft")
	local flagR = img(body, { Name = "FlagRight", AnchorPoint = Vector2.new(0.5, 0), Visible = false })
	Parts.image(flagR, "CosFlagRight")
	local preview = slot("Preview")
	local glow = img(preview, {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(150, 150),
	})
	local ring = img(preview, {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -3),
		Visible = false,
	})
	Parts.image(ring, "GlowRing")
	local icon = img(preview, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(112, 112),
		ZIndex = glow.ZIndex + 2,
	})
	local nameRibbon = img(
		body,
		{ Name = "NameRibbon", AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = body.ZIndex + 1 }
	)
	Parts.image(nameRibbon, "ItemsNameRibbon")
	local name =
		Parts.text(body, { Name = "Name", TextSize = 38, AnchorPoint = Vector2.new(0.5, 0), ZIndex = body.ZIndex + 2 })
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
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, -16, 0, BTN_H),
		ZIndex = scroll.ZIndex + 1,
	}, "Frame")
	local actionsList = centredRow(actions, BTN_GAP)
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

	local function stretchTo(inst, spriteName: string, inkW: number, inkH: number)
		local bw, bh = Parts.inkBox(spriteName, inkW, inkH)
		inst.Size = UDim2.fromOffset(bw, bh)
		inst.ScaleType = Enum.ScaleType.Stretch
	end

	local function relayoutFull()
		if not lay.topY then -- nothing shown yet
			return
		end
		local w = bodyW()
		local function at(inst, y, h)
			inst.AnchorPoint = Vector2.new(0.5, 0)
			inst.Position = UDim2.new(0.5, 0, 0, math.floor(y))
			inst.Size = UDim2.new(1, 0, 0, h)
		end
		scroll.Size = UDim2.fromScale(1, 1)
		scroll.ScrollBarThickness = 0
		actions.Size = UDim2.new(1, -16, 0, BTN_H)
		actions.Position = UDim2.new(0.5, 0, 1, BTN_DROP)
		body.Position = UDim2.fromOffset(side(), 0)
		divH = if divider.Visible then math.floor(w * 0.9 * 54 / 709) else 0
		tags.Visible, header.Visible = not hasHeader, hasHeader
		at(if hasHeader then header else tags, lay.topY, if hasHeader then 56 else 36)
		stretchTo(ribbon, "NameRibbon", 292, 56)
		ribbonText.Size = UDim2.fromScale(0.66, 0.6)
		Parts.fit(ribbonText, ribbon.Size.X.Offset * 0.66, 24, 12)
		at(preview, lay.artY, lay.artH)
		local g = math.min(lay.artH * 1.5, w)
		glow.Size = UDim2.fromOffset(g, g)
		icon.Size = UDim2.fromOffset(lay.artH, lay.artH)
		ring.Visible = lay.ring == true
		stretchTo(ring, "GlowRing", 280, 93)
		for i, flag in { flagL, flagR } do
			flag.Visible = lay.flags == true
			stretchTo(flag, if i == 1 then "CosFlagLeft" else "CosFlagRight", 77, 122)
			flag.Position = UDim2.new(0.5, if i == 1 then -156 else 156, 0, lay.flagY)
		end
		nameRibbon.Visible = lay.nameRibbon == true
		stretchTo(nameRibbon, "ItemsNameRibbon", 358, 64)
		nameRibbon.Position = UDim2.new(0.5, 0, 0, lay.nameY + nameH / 2)
		at(name, lay.nameY, nameH)
		local y = lay.nameY + nameH + lay.gap
		local bottom = y
		if subH > 0 then
			at(subline, y, subH)
			y += subH + lay.gap
		end
		if descH > 0 then
			at(descBox, y, descH)
			if descBox.Image ~= "" then -- boxed: reference box is 407 px wide, wider than the text column
				descBox.Size = UDim2.fromOffset(411, descH)
			end
			y += descH + lay.gap
		end
		if divH > 0 then
			at(divider, y, divH)
			divider.Size = UDim2.fromOffset(math.floor(w * 0.9), divH)
			y += divH + lay.gap
		end
		if extraH > 0 then
			y = lay.extraY or y
			at(extra, y, extraH)
			y += extraH
		end
		bottom = math.max(y, bottom)
		body.Size = UDim2.new(1, -2 * side(), 0, bottom)
		scroll.CanvasSize = UDim2.fromOffset(0, bottom)
		subline.Visible, descBox.Visible, extra.Visible = subH > 0, descH > 0, extraH > 0
	end

	local function relayout()
		if not compact() then
			relayoutFull()
			return
		end
		local btnH, pad = 48, 8
		local gap = 4
		local y0 = 6
		local viewH = parent.Size.Y.Offset - (btnH + pad + 4)
		local s = side()
		scroll.Size = UDim2.new(1, 0, 0, math.max(0, viewH))
		scroll.ScrollBarThickness = 4
		actions.Size = UDim2.new(1, -16, 0, btnH)
		actions.Position = UDim2.new(0.5, 0, 1, -pad)
		body.Position = UDim2.fromOffset(s, 0)
		local w = bodyW()
		divH = if divider.Visible then math.floor(w * 0.9 * 54 / 709) else 0
		local topH = if hasHeader then 34 else 24
		local heights = { topH, nameH, subH, descH, divH, extraH }
		local n, fixed = 1, 0 -- 1 = the art block
		for _, h in heights do
			if h > 0 then
				n += 1
				fixed += h
			end
		end
		local free = viewH - y0 - fixed - gap * (n - 1)
		local artH = math.clamp(free, 32, 170)
		local y = y0 -- clear of the panel rim
		local function put(inst, h)
			inst.AnchorPoint = Vector2.new(0.5, 0)
			inst.Position = UDim2.new(0.5, 0, 0, math.floor(y))
			inst.Size = UDim2.new(1, 0, 0, h)
			y += h + gap
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
		ring.Visible, flagL.Visible, flagR.Visible, nameRibbon.Visible = false, false, false, false
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
		local total = math.max(0, y - gap)
		body.Size = UDim2.new(1, -2 * s, 0, total)
		scroll.CanvasSize = UDim2.fromOffset(0, total)
		ribbon.Size = UDim2.fromOffset(math.floor(topH * 547 / 125), topH)
		ribbon.ScaleType = Enum.ScaleType.Fit
		ribbonText.Size = UDim2.fromScale(0.66, 0.6)
		Parts.fit(ribbonText, ribbon.Size.X.Offset * 0.66, 14, 10)
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
			local size = if c then 15 else 26
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
			-- dark pill with a copper rim (no sprite): "Quantity: x1,248"; Gold paints the count yellow
			subH = if c then 24 else (sub.H or 36)
			local size = if c then 15 else 24
			local pw = if c then math.max(150, measure(sub.Text, size) + 40) else (sub.W or 226)
			local pill = img(subline, { Name = "QtyPill", Size = UDim2.fromOffset(pw, subH) }, "Frame")
			pill.BackgroundTransparency = 0
			pill.BackgroundColor3 = Color3.fromRGB(75, 24, 62)
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
			make("UIStroke", { Color = COPPER, Thickness = 2 }, pill)
			local lbl = Parts.text(pill, { Text = sub.Text, TextSize = size, Size = UDim2.fromScale(1, 1) }, 2)
			if sub.Gold then
				local a, b = string.match(sub.Text, "^(.-)(x[%d,]+)$")
				if a then
					lbl.RichText = true
					lbl.Text = a .. '<font color="' .. GOLD_TEXT .. '">' .. b .. "</font>"
				end
			end
		elseif c then
			subH = 24
			Parts.Pill(subline, "Purple", sub.Text, { H = subH, MinW = 90, TextSize = 15, Icon = sub.Icon })
		else
			local pill =
				Parts.Pill(subline, "Wide", sub.Text, { InkW = 258, InkH = 38, TextSize = 23, Icon = sub.Icon })
			subH = pill.Size.Y.Offset
		end
	end

	local function renderStatsFull(list)
		-- header: 206x35 purple pill with diamonds + side lines; then ONE contiguous block of rows (ink pitch 33.5)
		local hp =
			Parts.Pill(extra, "Purple", "COMBAT STATS", { Name = "StatsHeader", InkW = 206, InkH = 35, TextSize = 24 })
		hp.AnchorPoint, hp.Position = Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0)
		for _, sx in { -1, 1 } do
			local d = img(hp, {
				Size = UDim2.fromOffset(9, 9),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, sx * 89, 0.5, 0),
				Rotation = 45,
			}, "Frame")
			d.BackgroundTransparency = 0
			d.BackgroundColor3 = WHITE
		end
		local hh = hp.Size.Y.Offset
		for i, nm in { "StatsLineL", "StatsLineR" } do
			local ln = img(extra, {
				Name = nm,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, if i == 1 then -142.5 else 142.5, 0, hh / 2),
			})
			Parts.image(ln, nm)
			stretchTo(ln, nm, 69, 8)
		end
		local n = math.min(#list, 4)
		local rw, rh, rk = Parts.inkBox("StatRow", 356, 32.5)
		for i = 1, n do
			local st = list[i]
			local r = img(extra, {
				Name = "Stat" .. i,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 31 + (i - 1) * 33.5),
				Size = UDim2.fromOffset(rw, rh),
			})
			Parts.skin(r, "StatRow", rk)
			local ic = img(r, {
				Size = UDim2.fromOffset(36, 36),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 18, 0.5, 0),
			})
			Parts.image(ic, st.Icon)
			Parts.text(r, {
				Text = st.Label,
				TextSize = 23,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(67, 0),
				Size = UDim2.new(0.55, -67, 1, 0),
			}, 2)
			Parts.text(r, {
				Text = st.Value,
				TextSize = 26,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = st.Color or STAT_GREEN,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -14, 0, 0),
				Size = UDim2.fromScale(0.4, 1),
			}, 2)
		end
		extraH = 31 + (n - 1) * 33.5 + rh
	end

	-- Materials: [-] [x1] [+] [MAX] (ink 61x53 / 141x45 / 60x53 / 99x53); Items: inline "Use Quantity:" row
	-- (43x42 buttons, borderless value, MAX 68x42). Both centred on the panel.
	local function renderStepperFull(model)
		local st = model.Stepper
		local on = st.Enabled ~= false
		local inline = model.StepInline == true
		local spec = if inline
			then {
				{ "Label", nil, 0, 124 },
				{ "Minus", "QtyMinus", 133, 43, 42, "\u{2212}", 38 },
				{ "Value", nil, 176, 61 },
				{ "Plus", "QtyPlus", 237, 43, 42, "+", 38 },
				{ "Max", "BtnPurple", 293, 68, 42, "MAX", 24 },
			}
			else {
				{ "Minus", "QtyMinus", 0, 61, 53, "\u{2212}", 40 },
				{ "Field", "QtyField", 70, 141, 45, "x" .. tostring(st.Qty), 36 },
				{ "Plus", "QtyPlus", 223, 60, 53, "+", 40 },
				{ "Max", "BtnPurple", 299, 99, 53, "MAX", 30 },
			}
		local span = if inline then 361 else 398
		local H = if inline then 46 else 58
		local r = img(extra, {
			Name = "Stepper",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(420, H),
		}, "Frame")
		local x0 = (420 - span) / 2
		for _, p in spec do
			local nm, sprite, x, iw, ih, str, tsz = p[1], p[2], p[3], p[4], p[5], p[6], p[7]
			if nm == "Label" then
				local l = Parts.text(r, {
					Name = "Label",
					Text = "Use Quantity:",
					TextXAlignment = Enum.TextXAlignment.Left,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, x0 + x, 0.5, 0),
					Size = UDim2.fromOffset(iw + 6, H),
				}, 2)
				Parts.fit(l, iw + 6, 24, 14)
			elseif nm == "Value" then
				Parts.text(r, {
					Name = "Value",
					Text = tostring(st.Qty),
					TextSize = 32,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, x0 + x, 0.5, 0),
					Size = UDim2.fromOffset(iw, H),
				}, 2)
			else
				local bw, bh, k = Parts.inkBox(sprite, iw, ih)
				local isField = nm == "Field"
				local b = img(r, {
					Name = nm,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, x0 + x - (bw - iw) / 2, 0.5, 0),
					Size = UDim2.fromOffset(bw, bh),
				}, if isField then "ImageLabel" else "ImageButton")
				Parts.skin(b, sprite, k)
				b.ImageColor3 = if on then WHITE else DISABLED_TINT
				if not isField then
					Parts.interact(b)
					b.Activated:Connect(function()
						if onStep then
							onStep(if nm == "Minus" then -1 elseif nm == "Plus" then 1 else "max")
						end
					end)
				end
				Parts.text(b, { Text = str, TextSize = tsz, Size = UDim2.fromScale(1, 1) })
			end
		end
		extraH = H
	end

	local function renderExtra(model)
		for _, ch in extra:GetChildren() do
			ch:Destroy()
		end
		local c = compact()
		extraH = 0
		local list = model.Stats
		if list and not c then
			renderStatsFull(list)
		elseif model.Stepper and not c then
			renderStepperFull(model)
		elseif list then
			local rowH, pitch = 26, 28
			local hp =
				Parts.Pill(extra, "Purple", "COMBAT STATS", { Name = "StatsHeader", H = 22, MinW = 190, TextSize = 15 })
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
					TextSize = 15,
					TextXAlignment = Enum.TextXAlignment.Left,
					Position = UDim2.fromOffset(rowH + 12, 0),
					Size = UDim2.new(0.55, -(rowH + 12), 1, 0),
				}, 2)
				Parts.text(r, {
					Text = st.Value,
					TextSize = 16,
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
			local rowH = 44
			local r = img(extra, { Name = "Stepper", Size = UDim2.new(1, 0, 0, rowH) }, "Frame")
			local k = math.min(1, bodyW() / 336)
			centredRow(r, math.floor(8 * k))
			local on = st.Enabled ~= false
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
				Parts.text(b, { Text = str, TextSize = if str == "MAX" then 22 else 34, Size = UDim2.fromScale(1, 1) })
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
			Parts.text(field, { Text = "x" .. tostring(st.Qty), TextSize = 20, Size = UDim2.fromScale(1, 1) })
			stepBtn("Plus", "QtyPlus", 56, 3, 1, "+")
			stepBtn("Max", "BtnPurple", 88, 4, "max", "MAX")
			extraH = rowH
		end
		extra.Visible = extraH > 0
	end

	-- Buttons: one size (Full 127x74 box = ink 120x67; Compact 127x48) shrunk equally when the panel is narrower than 3.
	local function layoutButtons()
		local c = compact()
		local w = if c then math.min(127, math.floor((parent.Size.X.Offset - 16 - 2 * 8) / 3)) else BTN_W
		local h = if c then 48 else BTN_H
		actionsList.Padding = UDim.new(0, if c then 8 else BTN_GAP)
		-- one label size on every tab and every row: what the longest label (UNEQUIP) needs
		local text = Parts.fitSize("UNEQUIP", w - 16, 30, 15)
		for _, btn in actions:GetChildren() do
			if btn:IsA("ImageButton") then
				btn.Size = UDim2.fromOffset(w, h)
				btn:SetAttribute("TextFixed", text)
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
				Size = UDim2.fromOffset(BTN_W, BTN_H),
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

	local function renderTags(model, c)
		clearChildren(tags, "UIListLayout")
		if c then
			local left =
				Parts.Pill(tags, model.Rarity, string.upper(model.Rarity), { Name = "Rarity", H = 24, TextSize = 14 })
			left.AnchorPoint, left.Position = Vector2.zero, UDim2.fromScale(0, 0)
			if model.StatusTag then
				local right = Parts.Pill(tags, "Equipped", model.StatusTag, { Name = "Status", H = 24, TextSize = 14 })
				right.AnchorPoint, right.Position = Vector2.new(1, 0), UDim2.fromScale(1, 0)
			end
			return
		end
		local centre = model.CenterTag == true
		local left = Parts.Pill(tags, model.Rarity, string.upper(model.Rarity), {
			Name = "Rarity",
			InkH = if centre then 40 else 29,
			InkW = if centre then 176 else nil,
			MinW = 100,
			TextSize = if centre then 28 else 20,
		})
		left.AnchorPoint = Vector2.new(if centre then 0.5 else 0, 0)
		left.Position = if centre then UDim2.fromScale(0.5, 0) else UDim2.fromOffset(6, 0)
		if model.StatusTag then
			local right = Parts.Pill(tags, "Equipped", model.StatusTag, {
				Name = "Status",
				InkW = if centre then 100 else 119,
				InkH = 31,
				TextSize = 19,
			})
			right.AnchorPoint, right.Position = Vector2.new(1, 0), UDim2.new(1, -2, 0, 0)
		end
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
		lay = {
			topY = model.TopY or 22,
			artY = model.ArtY or 36,
			artH = model.ArtH or 132,
			nameY = model.NameY or 154,
			gap = model.Gap or 12,
			ring = model.Ring,
			flags = model.Flags,
			flagY = 36,
			nameRibbon = model.NameRibbon,
			extraY = model.ExtraY,
		}
		renderTags(model, c)
		Parts.skin(glow, GLOW[model.Rarity] or "GlowCommon")
		local has = model.Icon ~= nil and model.Icon ~= ""
		Parts.image(icon, if has then model.Icon else fallback)
		icon.ImageColor3 = model.Tint or (if has then WHITE else Parts.RarityColor[model.Rarity] or WHITE)
		-- name: Title Case on Dice/Items, caps on Materials/Cosmetics; shrinks to fit one line, wraps only when it still does not fit
		local shown = if model.Upper then string.upper(model.Name) else model.Name
		local w = bodyW()
		local nameMax, nameMin = if c then 24 else 46, if c then 18 else 24
		local line = if c then 26 else 44
		name.Text = shown
		name.Size = UDim2.new(1, 0, 0, line)
		if measure(shown, nameMin) > w then
			name.TextWrapped = true
			name.TextSize = nameMin
			nameH = line + (if c then 18 else 24)
			name.Size = UDim2.new(1, 0, 0, nameH)
		else
			name.TextWrapped = false
			Parts.fit(name, w, nameMax, nameMin)
			nameH = line
		end
		renderSubline(model.Subline)
		-- description: boxed (QtyField) on materials, bare text elsewhere; at most 3 lines (2 compact)
		local text = model.Description or ""
		local dsize, lineH = if c then 15 else 21, if c then 18 else 24
		desc.TextSize = dsize
		desc.Text = text
		descBox.Visible = text ~= ""
		descH = 0
		if text ~= "" then
			local lines =
				math.min(if c then 2 else 3, math.max(1, math.ceil(measure(text, dsize) / math.max(1, w - 28))))
			descH = lines * lineH + (if model.DescBox then (if c then 10 else 20) else 6)
			if model.DescBox then
				Parts.skin(descBox, "QtyField", if c then math.clamp(descH / Sprites.QtyField.Size.Y, 0.3, 1) else 0.4)
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
