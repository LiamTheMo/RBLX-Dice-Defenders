-- Quest Log toolbar, one geometry for all three tabs: search field, "Show:" / "SORT:" label, dropdown (+ optional "24 / 48" count).
-- Toolbar.new(Slots slot) -> :SetPlaceholder :SetQuery :OnSearch(cb) :SetLabel(text) :SetOptions(list, activeId) :OnOption(cb)
-- :SetCount(text|nil) :Destroy. Visual only. The slot is design px (QuestLog sets its size in offsets). Code-drawn (plan D1).
-- Name paths: QuestToolbar.Search (.Input), .Dropdown, .OptionMenu, .Count.

local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.Parent.UiKit)
local Chrome = require(script.Parent.Parent.Bag.Chrome)
local Kit = require(script.Parent.Kit)

local make = UiKit.make

local FIELD_H = 40 -- visible field height (mockup 230..270)
local PAD_L, PAD_R = 2, 9
local WHITE = Color3.new(1, 1, 1)

local Toolbar = {}

function Toolbar.new(parent)
	local api, conns = {}, {}
	local onSearch, onOption
	local options, active = {}, nil
	local placeholder, labelText, countText = "Search...", "Show:", nil
	local compactNow = false
	local muted = false
	local ddW, cy = 203, 26

	local root = make("Frame", {
		Name = "QuestToolbar",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = parent.ZIndex,
	}, parent)
	local z = root.ZIndex + 1

	local search = Chrome.field(root, { Name = "Search", AnchorPoint = Vector2.new(0, 0.5), Radius = 20, ZIndex = z })
	local mag = Kit.magnifier(
		search,
		{ Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(14, FIELD_H / 2), ZIndex = z + 1 }
	)
	local input = make("TextBox", {
		Name = "Input",
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		Font = Enum.Font.FredokaOne,
		TextSize = 26,
		TextColor3 = WHITE,
		PlaceholderColor3 = Color3.fromRGB(160, 160, 168),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = z + 2,
	}, root)
	local label = Kit.text(root, {
		Name = "ShowLabel",
		TextSize = 24,
		AnchorPoint = Vector2.new(1, 0.5),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = z,
	}, 2)
	local count = Kit.text(root, {
		Name = "Count",
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0.5),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.None,
		Visible = false,
		ZIndex = z,
	}, 2)

	-- Dropdown: a transparent touch-size button over the code-drawn pill.
	local hit = make("TextButton", {
		Name = "Dropdown",
		BackgroundTransparency = 1,
		Text = "",
		AnchorPoint = Vector2.new(1, 0.5),
		ZIndex = z + 3,
	}, root)
	local pill = Chrome.field(hit, { Name = "Pill", AnchorPoint = Vector2.new(0.5, 0.5), Radius = 20, ZIndex = z + 3 })
	pill.BackgroundColor3 = Color3.fromRGB(70, 69, 72)
	UiKit.wire(hit, function(state)
		pill.BackgroundColor3 = if state == "Pressed"
			then Color3.fromRGB(52, 51, 55)
			elseif state == "Hover" then Color3.fromRGB(84, 83, 88)
			else Color3.fromRGB(70, 69, 72)
	end)
	local ddText = Kit.text(pill, {
		Name = "Text",
		TextSize = 22,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(14, FIELD_H / 2),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = z + 4,
	}, 2)
	local chevron = Kit.chevron(pill, {
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(1, -22, 0.5, 0),
		ZIndex = z + 4,
	})

	local menu = Chrome.panel(root, {
		Name = "OptionMenu",
		Visible = false,
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Kit.PanelFill,
		Radius = 14,
		ZIndex = 45,
		Active = true,
	})
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	}, menu)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, menu)

	local function closeMenu()
		menu.Visible = false
	end
	local function setLabelText()
		ddText.Text = ""
		for _, o in options do
			if o.Id == active then
				-- compact: "Progress", not "Progress (High → Low)"
				ddText.Text = if compactNow
					then string.gsub(string.match(o.Label, "^[^(]+") or o.Label, "%s+$", "")
					else o.Label
			end
		end
		Kit.fit(ddText, ddText.Size.X.Offset, 22, if compactNow then 10 else 12)
	end

	local function layout()
		local W, H = parent.Size.X.Offset, parent.Size.Y.Offset
		if W <= 0 or H <= 0 then
			return
		end
		cy = H / 2
		local compact = W < 560
		compactNow = compact
		local hasLabel = labelText ~= "" and not compact
		ddW = if compact then (if W < 300 then 112 else 128) elseif labelText == "Show:" then 203 else 230
		local hitH = math.max(FIELD_H, Kit.minHit)
		hit.Size = UDim2.fromOffset(ddW + 8, hitH)
		pill.Size = UDim2.fromOffset(ddW, FIELD_H)
		pill.Position = UDim2.fromOffset((ddW + 8) / 2, hitH / 2)
		local edge = W - PAD_R
		local showCount = countText ~= nil and not compact
		count.Visible = showCount
		local right = edge
		if showCount then
			count.Text = countText
			count.Size = UDim2.fromOffset(74, H)
			count.Position = UDim2.fromOffset(edge, cy)
			right = edge - 74 - 10
		end
		hit.Position = UDim2.fromOffset(right + 4, cy)
		ddText.Size = UDim2.fromOffset(ddW - (if compact then 38 else 52), FIELD_H)
		chevron.Position = UDim2.new(1, -(if compact then 16 else 22), 0.5, 0)
		setLabelText()
		local left = right - ddW
		label.Visible = hasLabel
		label.Text = labelText
		if hasLabel then
			label.Size = UDim2.fromOffset(80, H)
			label.Position = UDim2.fromOffset(left - 12, cy)
			left -= 12 + 70
		end
		local want = if labelText == "SORT:" then 338 elseif labelText == "Sort:" then 423 else 424 -- mockup widths per tab
		local searchW = math.max(
			if compact then 70 else 120,
			if compact then left - 8 - PAD_L else math.min(want, left - 22 - PAD_L)
		)
		search.Position = UDim2.fromOffset(PAD_L, cy)
		search.Size = UDim2.fromOffset(searchW, FIELD_H)
		mag.Position = UDim2.fromOffset(if compact then 8 else 14, FIELD_H / 2)
		local pad = if compact then 36 else 50 -- text start inside the field
		input.Position = UDim2.fromOffset(PAD_L + pad, cy)
		input.Size = UDim2.fromOffset(searchW - pad - 12, math.max(FIELD_H, Kit.minHit))
		input.TextSize = if compact then 23 else 26
		-- phone: "Search..." when it fits, else just the magnifier
		input.PlaceholderText = if not compact then placeholder elseif searchW - pad - 8 >= 86 then "Search..." else ""
		menu.Position = UDim2.fromOffset(right + 4, cy + hitH / 2)
	end
	table.insert(conns, parent:GetPropertyChangedSignal("Size"):Connect(layout))
	layout()

	local function openMenu()
		for _, c in menu:GetChildren() do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		local rowH = math.max(44, Kit.minHit)
		local w = math.max(ddW + 8, 210)
		for i, o in options do
			local row, setOn = Kit.card(menu, {
				Name = "Option_" .. o.Id,
				Size = UDim2.fromOffset(w - 16, rowH),
				LayoutOrder = i,
			}, { Radius = 10 })
			setOn(o.Id == active)
			local text = Kit.text(row, {
				Name = "Label",
				Text = o.Label,
				TextSize = 22,
				Size = UDim2.fromScale(1, 1),
				TextColor3 = if o.Id == active then Kit.Gold else WHITE,
				ZIndex = row.ZIndex + 1,
			}, 2)
			Kit.fit(text, w - 40, 22, 12)
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
		menu.Size = UDim2.fromOffset(w, #options * rowH + (#options - 1) * 6 + 16)
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
		layout()
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
	function api:Relayout()
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
