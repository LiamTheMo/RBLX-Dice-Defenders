-- Bag parts: Toolbar, Grid (+Card), Footer, Detail (+Pill, Button). Visual only: no NetClient, no game data.
-- Sizes are design px (the Bag shell scales them); slots read the "Compact" attribute the shell sets on their parent.
-- Sprite schema: BagSprites[Name] = { Image, Size, Slice? }; a missing key or Image = "" renders blank.

local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.Parent.UiKit)
local Sprites = require(script.Parent.BagSprites)

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
local GLOW_SCALE = 1.6 -- the burst spreads well past the item, as in the references
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

-- Pill: rarity / colour key -> sprite. o.W fixed width (text truncates) or auto from the measured text.
function Parts.Pill(parent, style: string, str: string, o)
	o = o or {}
	local h, size = o.H or 22, o.TextSize or 15
	local equipped = style == "Equipped" -- green pill with a check at the right; text sits left of it
	local pill = img(parent, {
		Name = o.Name or "Pill",
		Size = UDim2.fromOffset(o.W or math.max(o.MinW or 0, measure(str, size) + 28 + (if equipped then h else 0)), h),
		LayoutOrder = o.Order or 0,
	})
	Parts.skinH(pill, PILL[style] or "PillGrey", h)
	Parts.text(pill, {
		Name = "Label",
		Text = str,
		TextSize = size,
		Size = if equipped then UDim2.new(1, -(h + 4), 1, 0) else UDim2.fromScale(1, 1),
	}, 1.5)
	if equipped then
		-- EquippedPill's check sits inside its 9-slice centre (it would stretch), so draw the check separately.
		local check = img(pill, {
			Name = "Check",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(h - 8, h - 8),
		})
		Parts.image(check, "Check")
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
	if o.Label then
		label.Text = o.Label
		Parts.fit(label, btn.Size.X.Offset - 16, btn:GetAttribute("TextMax"), 15)
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

local CONTROL_H, SORT_ROW = 56, 56

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
		PaddingLeft = UDim.new(0, 20),
		PaddingRight = UDim.new(0, 20),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
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
		PlaceholderColor3 = Color3.fromRGB(170, 175, 205),
		Text = "",
		PlaceholderText = "Search",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = search.ZIndex + 1,
	}, search)
	local count = Parts.text(search, {
		Name = "Count",
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(78, 24),
		TextColor3 = SOFT,
		Visible = false,
	}, 1.5)

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
	local sortW = 224
	local placeholder = "Search"
	local function layout()
		local inner = parent.Size.X.Offset - 40 -- design px (the shell sets slot sizes in offsets)
		sortW = if inner >= 440 then 224 else 56
		if sortW == 224 then
			Parts.skinH(sort, "Sort", CONTROL_H)
			sort.ScaleType = Enum.ScaleType.Stretch -- the baked chevron must not meet a 9-slice edge
		else
			Parts.skinH(sort, "BtnPurple", CONTROL_H)
		end
		input.TextSize = if sortW == 224 then 22 else 18
		input.PlaceholderText = if sortW == 224 then placeholder else placeholder:match("%S+") or placeholder
		sort.Size = UDim2.fromOffset(sortW, CONTROL_H)
		sort.Position = UDim2.fromScale(1, 0)
		search.Size = UDim2.new(1, -(sortW + 16), 0, CONTROL_H)
		sortLabel.Visible = sortW == 224
		count.Visible = count.Text ~= "" and inner >= 500 -- the search box keeps its room on narrow panels
		arrows.Position = if sortW == 224 then UDim2.new(0, 14, 0.5, 0) else UDim2.new(0.5, -14, 0.5, 0)
		input.Position = UDim2.fromOffset(52, 0)
		input.Size = UDim2.new(1, -(52 + (if count.Visible then 90 else 16)), 1, 0)
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
				sortLabel.Text = o.Label
			end
		end
		Parts.fit(sortLabel, 130, 22, 15)
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
	function api:SetCount(str: string?)
		count.Text = str or ""
		layout()
	end
	function api:Destroy()
		disconnectAll(conns)
		root:Destroy()
	end
	return api
end

-- Grid ----------------------------------------------------------------------------------------------------

-- y/h per card slot inside the card; icon is square.
local CARD = {
	Full = {
		size = Vector2.new(134, 190),
		tag = { 6, 20 },
		icon = { 26, 88 },
		title = { 114, 22 },
		sub = { 138, 22 },
		foot = { 162, 20 },
		pillW = 110,
		text = 17,
		small = 15,
		badge = Vector2.new(30, 34),
	},
	Compact = {
		size = Vector2.new(112, 150),
		tag = { 4, 18 },
		icon = { 22, 62 },
		title = { 85, 18 },
		sub = { 104, 18 },
		foot = { 123, 18 },
		pillW = 96,
		text = 15,
		small = 15,
		badge = Vector2.new(24, 28),
	},
}

function Parts.Grid(parent)
	local api, conns = {}, {}
	local items, cards, selected, fallback = {}, {}, nil, nil
	local onSelect

	local root = make("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = parent.ZIndex,
	}, parent)
	local scroll = make("ScrollingFrame", {
		Name = "GridScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = GOLD,
		ZIndex = root.ZIndex + 1,
	}, root)
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
	local emptyText = "Nothing here yet"

	local function buildCard(item, order)
		local spec = if parent:GetAttribute("Compact") then CARD.Compact else CARD.Full
		local card = img(scroll, { Name = "Card_" .. item.Id, LayoutOrder = order }, "ImageButton")
		Parts.skin(card, item.Id == selected and "CardSelected" or "CardIdle", 0.5)
		Parts.interact(card)
		local function place(inst, row, w, h)
			inst.AnchorPoint = Vector2.new(0.5, 0)
			inst.Position = UDim2.new(0.5, 0, 0, row[1])
			inst.Size = UDim2.fromOffset(w, h or row[2])
		end
		if item.TopTag then
			local pill =
				Parts.Pill(card, if item.TopTagStyle == "Equipped" then "Equipped" else item.Rarity, item.TopTag, {
					Name = "TopTag",
					W = spec.pillW,
					H = spec.tag[2],
					TextSize = spec.small,
				})
			place(pill, spec.tag, spec.pillW)
		end
		local icon = img(card, { Name = "Icon" })
		place(icon, spec.icon, spec.icon[2], spec.icon[2])
		local has = item.Icon ~= nil and item.Icon ~= ""
		Parts.image(icon, if has then item.Icon else fallback)
		icon.ImageColor3 = if item.Locked
			then Color3.new(0.45, 0.45, 0.45)
			else item.Tint or (if has then WHITE else Parts.RarityColor[item.Rarity] or WHITE)
		local title = Parts.text(card, { Name = "Title", Text = item.Name, TextSize = spec.text })
		place(title, spec.title, spec.size.X - 12)
		if item.SubTag then
			local pill = Parts.Pill(card, item.Rarity, item.SubTag, {
				Name = "SubTag",
				W = spec.pillW,
				H = spec.sub[2],
				TextSize = spec.small,
			})
			place(pill, spec.sub, spec.pillW)
		end
		if item.Footer then
			local foot =
				Parts.text(card, { Name = "Footer", Text = item.Footer, TextSize = spec.small, TextColor3 = SOFT })
			place(foot, spec.foot, spec.size.X - 12)
		end
		if item.CornerBadge then
			local badge = img(card, {
				Name = "CornerBadge",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6, 0, 6),
				Size = UDim2.fromOffset(spec.badge.X, spec.badge.Y),
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
		local spec = if parent:GetAttribute("Compact") then CARD.Compact else CARD.Full
		layout.CellSize = UDim2.fromOffset(spec.size.X, spec.size.Y)
		-- Rows are left-aligned (a lone result sits in column 1); the whole column block is centred by padding.
		local cols = math.max(1, math.floor((parent.Size.X.Offset - 12 + 8) / (spec.size.X + 8)))
		local side = math.max(0, math.floor((parent.Size.X.Offset - (cols * spec.size.X + (cols - 1) * 8)) / 2))
		gridPad.PaddingLeft, gridPad.PaddingRight = UDim.new(0, side), UDim.new(0, side)
		for _, c in cards do
			c:Destroy()
		end
		table.clear(cards)
		for i, item in items do
			buildCard(item, i)
		end
		empty.Text = emptyText
		empty.Visible = #items == 0
	end
	connect(conns, parent:GetAttributeChangedSignal("Compact"), rebuild)
	connect(conns, parent:GetPropertyChangedSignal("Size"), rebuild)

	function api:SetItems(list)
		items = list
		rebuild()
	end
	function api:SetSelected(id: string?)
		selected = id
		for cid, card in cards do
			Parts.skin(card, if cid == id then "CardSelected" else "CardIdle", 0.5)
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
		Size = UDim2.new(1, 0, 0, 92), -- bottom-anchored: the compact overlay grows upward when slots wrap
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
	Parts.skinH(strip, "Strip", 92)
	local row = img(strip, { Name = "Row", Size = UDim2.fromScale(1, 1) }, "Frame")
	local rowLayout = make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 14),
	}, row)
	local label = Parts.text(row, {
		Name = "Label",
		Text = "LOADOUT",
		TextSize = 18,
		TextWrapped = true,
		Size = UDim2.fromOffset(120, 60),
		LayoutOrder = 1,
	})
	local slotsFrame =
		img(row, { Name = "Slots", Size = UDim2.fromOffset(5 * 68 + 4 * 8, 68), LayoutOrder = 2 }, "Frame")
	local slotsLayout = make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, slotsFrame)
	local icons, slots = {}, {}
	for i = 1, 5 do
		local slot =
			img(slotsFrame, { Name = "Slot" .. i, Size = UDim2.fromOffset(68, 68), LayoutOrder = i }, "ImageButton")
		Parts.skin(slot, "CardIdle", 0.3)
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
	local btn = Parts.button(row, {
		Name = "Unequip",
		Style = "Red",
		Label = "UNEQUIP ALL",
		TextSize = 20,
		Size = UDim2.fromOffset(160, 56),
		Order = 3,
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
		local d, labelW, btnW, gap = 68, 120, 160, 8
		if compact then
			gap, d = 4, 56 -- touch floor: wrap into rows (3+2 on a narrow panel) instead of shrinking
		elseif w < 700 then
			d, labelW, btnW, gap = 56, 84, 120, 6
		end
		label.Visible, btn.Visible, backing.Visible = not compact, not compact, compact
		label.Size = UDim2.fromOffset(labelW, 60)
		label.TextSize = if labelW == 120 then 18 else 15
		rowLayout.Padding = UDim.new(0, if compact then 0 elseif w < 700 then 8 else 14)
		slotsLayout.Padding = UDim.new(0, gap)
		local perRow = if compact then math.clamp(math.floor((w - 24 + gap) / (d + gap)), 1, 5) else 5
		local rows = math.ceil(5 / perRow)
		slotsLayout.Wraps = true
		slotsFrame.Size = UDim2.fromOffset(perRow * d + (perRow - 1) * gap, rows * d + (rows - 1) * gap)
		root.Size = UDim2.new(1, 0, 0, if rows > 1 then slotsFrame.Size.Y.Offset + 36 else 92)
		for i, slot in slots do
			slot.Size = UDim2.fromOffset(d, d)
			icons[i].Size = UDim2.fromOffset(d - 16, d - 16)
		end
		btn.Size = UDim2.fromOffset(btnW, 56)
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

local SIDE = 14
local STAT_PITCH = 33
-- Detail rows ({y, h}; name adds max/min text size). Compact keeps pill, preview, name and subline above the
-- pinned buttons without scrolling; only description and stats scroll.
local DETAIL = {
	Full = {
		tags = { 12, 30 },
		prev = { 46, 150 },
		icon = 112,
		name = { 198, 40, 34, 22 },
		sub = { 240, 26 },
		desc = { 270, 46 },
		extra = { 322, 162 },
		rowPad = 20,
	},
	Compact = {
		tags = { 2, 24 },
		prev = { 28, 48 },
		icon = 40,
		name = { 78, 28, 24, 20 },
		sub = { 108, 24 },
		desc = { 136, 40 },
		extra = { 180, 162 },
		rowPad = 8,
	},
}

function Parts.Detail(parent)
	local api, conns = {}, {}
	local onAction, onStep
	local fallback, lastModel
	local nameDy = 0 -- extra height when the full-tier name wraps to 2 lines
	local dy = 0 -- shifts the top block down to centre it when description and stats are empty
	local function L()
		return if parent:GetAttribute("Compact") then DETAIL.Compact else DETAIL.Full
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
		Size = UDim2.new(1, 0, 1, -76), -- refit by applyLayout
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = GOLD,
		ZIndex = root.ZIndex + 1,
	}, root)
	local body = img(
		scroll,
		{ Name = "Body", Size = UDim2.new(1, -2 * SIDE, 0, 490), Position = UDim2.fromOffset(SIDE, 0) },
		"Frame"
	)
	local function slot(name, y, h)
		return img(body, {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y),
			Size = UDim2.new(1, 0, 0, h),
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

	local tags = slot("TopTags", 12, 30)
	centredRow(tags, 12)
	local preview = slot("Preview", 46, 150)
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
	local name = Parts.text(body, {
		Name = "Name",
		TextSize = 34,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 198),
		Size = UDim2.new(1, 0, 0, 40),
	})
	local subline = slot("Subline", 240, 26)
	centredRow(subline, 8)
	local desc = Parts.text(body, {
		Name = "Description",
		TextSize = 17,
		TextWrapped = true,
		TextColor3 = SOFT,
		TextYAlignment = Enum.TextYAlignment.Top,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 270),
		Size = UDim2.new(1, 0, 0, 46),
	}, 1.5)
	local extra = slot("Extra", 322, 162)
	local actions = img(root, {
		Name = "ActionRow",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.new(1, -2 * SIDE, 0, 56),
		ZIndex = scroll.ZIndex + 1,
	}, "Frame")
	centredRow(actions, 11)
	local placeholder = Parts.text(root, {
		Name = "Placeholder",
		Text = "Select an item",
		TextSize = 24,
		TextColor3 = SOFT,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -2 * SIDE, 0, 40),
	})

	local function applyLayout()
		local l = L()
		local function put(inst, row)
			inst.Position = UDim2.new(0.5, 0, 0, row[1])
			inst.Size = UDim2.new(1, 0, 0, row[2])
		end
		put(tags, { l.tags[1] + dy, l.tags[2] })
		put(preview, { l.prev[1] + dy, l.prev[2] })
		put(name, { l.name[1] + dy, l.name[2] + nameDy })
		put(subline, { l.sub[1] + dy + nameDy, l.sub[2] })
		-- compact: the description box ends above the pinned buttons so AtEnd cuts a whole line, never a glyph
		local area = parent.Size.Y.Offset - (56 + l.rowPad)
		local descH = l.desc[2]
		if l == DETAIL.Compact then
			descH = math.max(0, math.min(descH, area - l.desc[1] - nameDy - 4))
		end
		put(desc, { l.desc[1] + nameDy, descH })
		desc.Visible = descH >= 17
		put(extra, { l.extra[1] + nameDy, l.extra[2] })
		glow.Size = UDim2.fromOffset(l.prev[2] * GLOW_SCALE, l.prev[2] * GLOW_SCALE)
		icon.Size = UDim2.fromOffset(l.icon, l.icon)
		actions.Position = UDim2.new(0.5, 0, 1, -l.rowPad)
		scroll.Size = UDim2.new(1, 0, 1, -(56 + l.rowPad))
	end
	applyLayout()

	local function renderSubline(s)
		clearChildren(subline, "UIListLayout")
		if not s then
			return
		end
		if s.Kind == "Level" then
			local track = img(subline, { Name = "LevelBar", Size = UDim2.fromOffset(250, 26) })
			Parts.skinH(track, "LevelTrack", 26)
			local clip = img(track, {
				Name = "Fill",
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.fromOffset(242 * math.clamp(s.Value / math.max(1, s.Max), 0, 1), 18),
				ClipsDescendants = true,
			}, "Frame")
			local fill = img(clip, { Name = "FillImage", Size = UDim2.fromOffset(242, 18) })
			Parts.skinH(fill, "LevelFill", 18)
			Parts.text(track, {
				Text = ("LV %d / %d"):format(s.Value, s.Max),
				TextSize = 17,
				Size = UDim2.fromScale(1, 1),
				ZIndex = clip.ZIndex + 2,
			}, 1.5)
		else
			Parts.Pill(
				subline,
				if s.Kind == "Qty" then "Blue" else "Purple",
				s.Text,
				{ H = 26, MinW = 90, TextSize = 17 }
			)
		end
	end

	local function renderExtra(model)
		for _, c in extra:GetChildren() do
			c:Destroy()
		end
		local list = model.Stats
		if list then
			Parts.text(extra, {
				Name = "StatsHeader",
				Text = "COMBAT STATS",
				TextSize = 20,
				Size = UDim2.new(1, 0, 0, 26),
				TextColor3 = GOLD,
			})
			for i = 1, math.min(#list, 4) do
				local st = list[i]
				local r = img(extra, {
					Name = "Stat" .. i,
					Position = UDim2.fromOffset(0, 26 + (i - 1) * STAT_PITCH),
					Size = UDim2.new(1, 0, 0, 30),
				}, "Frame")
				local ic = img(r, {
					Size = UDim2.fromOffset(24, 24),
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 6, 0.5, 0),
				})
				Parts.image(ic, st.Icon)
				Parts.text(r, {
					Text = st.Label,
					TextSize = 19,
					TextXAlignment = Enum.TextXAlignment.Left,
					Position = UDim2.fromOffset(40, 0),
					Size = UDim2.new(0.55, -40, 1, 0),
				})
				Parts.text(r, {
					Text = st.Value,
					TextSize = 21,
					TextXAlignment = Enum.TextXAlignment.Right,
					TextColor3 = st.Color or WHITE,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -6, 0, 0),
					Size = UDim2.fromScale(0.45, 1),
				})
			end
		elseif model.Stepper then
			local st = model.Stepper
			local r = img(extra, { Name = "Stepper", Size = UDim2.new(1, 0, 0, 56) }, "Frame")
			centredRow(r, 8)
			local on = st.Enabled ~= false
			local function stepBtn(nm, sprite, w, order, delta, str)
				local b = img(r, { Name = nm, Size = UDim2.fromOffset(w, 56), LayoutOrder = order }, "ImageButton")
				Parts.skinH(b, sprite, 56)
				b.ImageColor3 = if on then WHITE else DISABLED_TINT
				Parts.interact(b)
				if str then
					Parts.text(
						b,
						{ Text = str, TextSize = if str == "MAX" then 24 else 36, Size = UDim2.fromScale(1, 1) }
					)
				end
				b.Activated:Connect(function()
					if onStep then
						onStep(delta)
					end
				end)
			end
			stepBtn("Minus", "QtyMinus", 56, 1, -1, "-")
			local field = img(r, { Name = "Field", Size = UDim2.fromOffset(120, 56), LayoutOrder = 2 })
			Parts.skinH(field, "QtyField", 56)
			field.ImageColor3 = if on then WHITE else DISABLED_TINT
			Parts.text(field, { Text = tostring(st.Qty), TextSize = 26, Size = UDim2.fromScale(1, 1) })
			stepBtn("Plus", "QtyPlus", 56, 3, 1, "+")
			stepBtn("Max", "BtnGold", 88, 4, "max", "MAX")
		end
		extra.Visible = list ~= nil or model.Stepper ~= nil
		local ex = L().extra
		body.Size = UDim2.new(1, -2 * SIDE, 0, ex[1] + nameDy + 8 + (if extra.Visible then ex[2] else 0))
		scroll.CanvasSize = UDim2.fromOffset(0, body.Size.Y.Offset)
	end

	-- Buttons are 110x56 and shrink (equal widths) when the detail panel is narrower than 3 of them.
	local buttonList = {}
	local function layoutButtons()
		local n = math.max(1, #buttonList)
		local w = math.min(110, math.floor((parent.Size.X.Offset - 2 * SIDE - 11 * (n - 1)) / n))
		for _, btn in actions:GetChildren() do
			if btn:IsA("ImageButton") then
				btn.Size = UDim2.fromOffset(w, 56)
				Parts.setButton(btn, { Label = btn.Label.Text, Style = btn:GetAttribute("Style") })
			end
		end
	end
	connect(conns, parent:GetPropertyChangedSignal("Size"), layoutButtons)
	connect(conns, parent:GetAttributeChangedSignal("Compact"), function()
		applyLayout()
		if lastModel then
			api:Show(lastModel)
		end
	end)

	function api:SetButtons(list)
		clearChildren(actions, "UIListLayout")
		buttonList = list
		for i, b in list do
			local btn = Parts.button(actions, {
				Name = "Action" .. i,
				Style = b.Style,
				Label = b.Label,
				Enabled = b.Enabled,
				Order = i,
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
		clearChildren(tags, "UIListLayout")
		Parts.Pill(
			tags,
			model.Rarity,
			string.upper(model.Rarity),
			{ Name = "Rarity", H = L().tags[2], MinW = 116, TextSize = 17, Order = 1 }
		)
		if model.StatusTag then
			Parts.Pill(
				tags,
				"Equipped",
				model.StatusTag,
				{ Name = "Status", H = L().tags[2], MinW = 116, TextSize = 17, Order = 2 }
			)
		end
		Parts.skin(glow, GLOW[model.Rarity] or "GlowCommon")
		local has = model.Icon ~= nil and model.Icon ~= ""
		Parts.image(icon, if has then model.Icon else fallback)
		icon.ImageColor3 = model.Tint or (if has then WHITE else Parts.RarityColor[model.Rarity] or WHITE)
		name.Text = model.Name
		local l0 = L()
		local wrap = l0 == DETAIL.Full and measure(model.Name, l0.name[4]) > 350
		nameDy = if wrap then 20 else 0
		name.TextWrapped = wrap
		if wrap then
			Parts.fit(name, 2 * 340, 26, 20)
		else
			Parts.fit(name, 350, l0.name[3], l0.name[4])
		end
		renderSubline(model.Subline)
		desc.Text = model.Description
		renderExtra(model)
		local l = L()
		local free = parent.Size.Y.Offset - (56 + l.rowPad) - (l.sub[1] + l.sub[2]) - l.tags[1]
		dy = if (model.Description or "") == "" and not extra.Visible then math.max(0, math.floor(free / 2)) else 0
		applyLayout()
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
