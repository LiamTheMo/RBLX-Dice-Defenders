-- Quest Log toolbar, one geometry for all three tabs: search box, "Show:" label, dropdown (+ optional count text).
-- Toolbar.new(Slots.Toolbar) -> :SetPlaceholder :SetQuery :OnSearch(cb) :SetLabel :SetOptions(list, activeId) :OnOption(cb)
-- :SetCount(text|nil) :Destroy. Visual only. The slot is design px (the shell sets its size in offsets).

local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Bag.Parts)
local Draw = require(script.Parent.Draw)

local make = UiKit.make
local Bag, Q = Draw.Bag, Draw.Q

local CY = 34 -- control centre line in the 68 px slot (reference: search centre 33.5 below the panel top)
local INK_H = 43 -- visible control height (reference)
local PAD_L, PAD_R = 24, 20
local HIT_H, ROW_H = 56, 56
local WHITE = Color3.new(1, 1, 1)

local Toolbar = {}

function Toolbar.new(parent)
	local api, conns = {}, {}
	local onSearch, onOption
	local options, active = {}, nil
	local placeholder, labelText, countText = "Search...", "Show:", nil
	local muted = false
	local ddW = 203

	local root = make("Frame", {
		Name = "QuestToolbar",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = parent.ZIndex,
	}, parent)

	local search = Draw.img(root, { Name = "Search" })
	local mag = Draw.img(root, { Name = "Magnifier", ZIndex = search.ZIndex + 1 })
	local input = make("TextBox", {
		Name = "Input",
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		Font = Enum.Font.FredokaOne,
		TextSize = 20,
		TextColor3 = WHITE,
		PlaceholderColor3 = Color3.fromRGB(196, 169, 180),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = search.ZIndex + 2,
	}, root)
	local label = Parts.text(root, {
		Name = "ShowLabel",
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0.5),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, 2)
	local count = Parts.text(root, {
		Name = "Count",
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0.5),
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
	}, 2)

	-- Dropdown: a transparent touch-size button (hover/press scale applies to its children) over the sliced sprite.
	local hit = Draw.img(root, { Name = "Dropdown", AnchorPoint = Vector2.new(1, 0.5) }, "ImageButton")
	Parts.interact(hit)
	local skin = Draw.img(hit, { Name = "Skin" })
	local ddText = Parts.text(
		hit,
		{ Name = "Text", TextSize = 22, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = skin.ZIndex + 1 },
		2
	)
	local chevron =
		Draw.img(hit, { Name = "Chevron", Size = UDim2.fromOffset(22, 16), ZIndex = skin.ZIndex + 1 }, "Frame")
	chevron.AnchorPoint = Vector2.new(0.5, 0.5)
	for i = 1, 2 do -- two rounded bars rotated into a "v"
		local arm = Draw.img(chevron, {
			Name = "Arm" .. i,
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(if i == 1 then 6.5 else 15.5, 8),
			Size = UDim2.fromOffset(13, 4),
			Rotation = if i == 1 then 45 else -45,
		}, "Frame")
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, arm)
		make("UIStroke", { Color = Color3.fromRGB(9, 14, 24), Thickness = 1.5 }, arm)
	end

	local menu = Draw.img(root, {
		Name = "OptionMenu",
		Visible = false,
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 45,
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
	local function setLabelText()
		ddText.Text = ""
		for _, o in options do
			if o.Id == active then
				ddText.Text = o.Label
			end
		end
		Parts.fit(ddText, ddText.Size.X.Offset, 22, 13)
	end

	local function layout()
		local W = parent.Size.X.Offset
		if W <= 0 then
			return
		end
		local inner = W - PAD_L - PAD_R
		local compact = inner < 560
		ddW = if compact then math.min(120, math.floor(inner * 0.45)) else 203
		label.Visible = not compact
		label.Text = labelText
		label.Size = UDim2.fromOffset(60, HIT_H)
		local right = W - PAD_R -- ink right edge of the dropdown
		hit.Size = UDim2.fromOffset(ddW + 8, HIT_H)
		hit.Position = UDim2.fromOffset(right + 4, CY)
		Draw.apply(skin, Q.Dropdown, (ddW + 8) / 2, HIT_H / 2, ddW, INK_H)
		chevron.Position = UDim2.fromOffset(4 + ddW - 28, HIT_H / 2)
		ddText.Position = UDim2.fromOffset(4 + 12 + (ddW - 62) / 2, HIT_H / 2)
		ddText.Size = UDim2.fromOffset(ddW - 62, INK_H)
		setLabelText()
		local left = right - ddW -- running left edge of the right cluster
		if not compact then
			label.Position = UDim2.fromOffset(left - 14, CY)
			left -= 14 + 58
		end
		count.Visible = countText ~= nil
		if countText then
			count.Text = countText
			count.Size = UDim2.fromOffset(84, HIT_H)
			count.Position = UDim2.fromOffset(left - 12, CY)
			left -= 12 + 70
		end
		local searchW = math.max(120, left - (if compact then 10 else 24) - PAD_L)
		Draw.apply(search, Bag.Search, PAD_L + searchW / 2, CY, searchW, INK_H)
		Draw.apply(mag, Bag.Magnifier, PAD_L + 16 + 13, CY, 26, 26)
		input.Position = UDim2.fromOffset(PAD_L + 52, CY)
		input.Size = UDim2.fromOffset(searchW - 52 - 14, HIT_H)
		input.PlaceholderText = placeholder
		menu.Position = UDim2.fromOffset(right + 4, CY + HIT_H / 2 + 2)
	end
	table.insert(conns, parent:GetPropertyChangedSignal("Size"):Connect(layout))
	layout()

	local function openMenu()
		for _, c in menu:GetChildren() do
			if c:IsA("ImageButton") then
				c:Destroy()
			end
		end
		local w = math.max(ddW + 8, 200)
		for i, o in options do
			local row = Parts.button(menu, {
				Name = "Option_" .. o.Id,
				Style = if o.Id == active then "Gold" else "Purple",
				Label = o.Label,
				TextSize = 22,
				Size = UDim2.fromOffset(w - 20, ROW_H),
				Order = i,
			})
			row.Activated:Connect(function()
				closeMenu()
				if o.Id ~= active then
					active = o.Id
					setLabelText()
					if onOption then
						onOption(o.Id)
					end
				end
			end)
		end
		menu.Size = UDim2.fromOffset(w, #options * ROW_H + (#options - 1) * 8 + 20)
		menu.Visible = #options > 0
	end
	table.insert(
		conns,
		hit.Activated:Connect(function()
			if menu.Visible then
				closeMenu()
			else
				openMenu()
			end
		end)
	)
	-- An outside tap closes the menu (the tap still reaches whatever is under it).
	table.insert(
		conns,
		UserInputService.InputBegan:Connect(function(io)
			if
				menu.Visible
				and (
					io.UserInputType == Enum.UserInputType.MouseButton1
					or io.UserInputType == Enum.UserInputType.Touch
				)
			then
				local p = Vector2.new(io.Position.X, io.Position.Y)
				for _, g in { menu, hit } do
					local a, s = g.AbsolutePosition, g.AbsoluteSize
					if p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y then
						return
					end
				end
				closeMenu()
			end
		end)
	)
	table.insert(
		conns,
		input:GetPropertyChangedSignal("Text"):Connect(function()
			if not muted and onSearch then
				onSearch(input.Text)
			end
		end)
	)

	function api:SetPlaceholder(s: string)
		placeholder = s
		input.PlaceholderText = s
	end
	function api:SetQuery(s: string)
		muted = true
		input.Text = s
		muted = false
	end
	function api:OnSearch(cb)
		onSearch = cb
	end
	function api:SetLabel(s: string)
		labelText = s
		label.Text = s
	end
	function api:SetOptions(list, activeId: string?)
		options, active = list, activeId or (list[1] and list[1].Id)
		setLabelText()
		closeMenu()
	end
	function api:OnOption(cb)
		onOption = cb
	end
	function api:SetCount(text: string?)
		countText = text
		layout()
	end
	function api:Destroy()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		root:Destroy()
	end
	return api
end

return Toolbar
