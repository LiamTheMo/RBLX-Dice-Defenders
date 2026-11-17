-- Quest Log, MASTERY tab: one row per owned die (art, name, "Mastery Lv. n" pill, XP bar, four milestone reward slots) in a ScrollingFrame
-- with a code-drawn scrollbar. Mastery.new(grid) -> :SetRows(rows) :SetSelected(id) :OnSelect(cb(id, row)) :SetEmptyText(s) :SetVisible(b)
-- :SetScroll(n) :Destroy(). Mastery.pill(parent, w, h, level, textSize) builds the purple level pill (the Detail reuses it).
-- rows = QuestLogic.masteryRows (Id, Name, Level, Xp, XpGoal, Art, Tint?, Milestones), already sorted / filtered by the controller.
-- Slot states: Done = claimed (check badge), Claimable (gold rim, no badge), Locked (padlock badge).
-- Design px. Layout keys on the width: full (>= 560: pill + 4 slots) or narrow (phones: no pill, small slots).
-- Name paths: MasteryTab.MasteryScroll.Row_<DieId> (.Die .Name .Pill .XpBar .Slot<Lv>).

local UiKit = require(script.Parent.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Parent.Bag.Parts)
local Chrome = require(script.Parent.Parent.Parent.Bag.Chrome)
local Shared = require(script.Parent.Parent.Parent.SharedSprites)
local QuestLogic = require(script.Parent.Parent.QuestLogic)
local Kit = require(script.Parent.Parent.Kit)
local Q = require(script.Parent.Parent.QuestSprites)

local make = UiKit.make
local WHITE = Color3.new(1, 1, 1)

local PAD_L, PAD_R, PAD_T, PAD_B = 6, 30, 2, 0 -- right = scrollbar gutter
local ROW_H, GAP = 76, 6

local Mastery = {}

-- Purple "Mastery Lv. n" pill with the crown at the left (live text).
function Mastery.pill(parent, w: number, h: number, level: number, textSize: number)
	return Parts.Pill(
		parent,
		"Purple",
		"Mastery Lv. " .. level,
		{ Name = "LevelPill", InkW = w, InkH = h, TextSize = math.floor(textSize * Kit.S), Icon = Q.Crown }
	)
end

-- One milestone slot of s x s centred at (cx, cy) in `parent`: reward icon over "Lv. n", state badge top right.
function Mastery.slot(parent, m, s: number, cx: number, cy: number, z: number)
	local ready = m.State == "Claimable"
	local slot = Chrome.strip(parent, {
		Name = "Slot" .. m.Lv,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(s, s),
		BackgroundColor3 = Color3.fromRGB(35, 35, 37),
		Radius = 10,
		ZIndex = z,
	})
	if ready then
		local stroke = slot:FindFirstChildOfClass("UIStroke")
		stroke.Color, stroke.Thickness = Kit.Gold, 3
		stroke:SetAttribute("Rim", 3)
	end
	local ic = make("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, s * 0.08),
		Size = UDim2.fromOffset(s * 0.62, s * 0.58),
		ZIndex = z + 1,
	}, slot)
	Kit.setIcon(ic, m.Icon)
	local size = math.max(11, math.floor(s * 0.23))
	local label = Kit.text(slot, {
		Name = "Lv",
		Text = "Lv. " .. m.Lv,
		TextSize = size,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -s * 0.05),
		Size = UDim2.fromOffset(s - 4, size + 4),
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = z + 1,
	}, 2)
	Kit.fit(label, s - 6, size, 9)
	if not ready then
		local b = math.floor(s * 0.27)
		make("ImageLabel", {
			Name = "Badge",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -2, 0, 2),
			Size = UDim2.fromOffset(b, b),
			Image = (if m.State == "Done" then Shared.Tick else Shared.Padlock).Image,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = z + 3,
		}, slot)
	end
	return slot
end

function Mastery.new(parent)
	local api, conns = {}, {}
	local rows, selected, onSelect = {}, nil, nil
	local setOns = {}
	local narrow = false

	local root = make("Frame", {
		Name = "MasteryTab",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = parent.ZIndex,
	}, parent)
	local scroll = make("ScrollingFrame", {
		Name = "MasteryScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 0, -- the code-drawn bar below replaces the native one; wheel, touch and drag still scroll
		ScrollBarImageTransparency = 1, -- a 0-thickness bar still draws a 1 px hairline
		ZIndex = root.ZIndex + 1,
	}, root)
	local pad = make("UIPadding", {
		PaddingLeft = UDim.new(0, PAD_L),
		PaddingRight = UDim.new(0, PAD_R),
		PaddingTop = UDim.new(0, PAD_T),
		PaddingBottom = UDim.new(0, PAD_B),
	}, scroll)
	make("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	local empty = Kit.text(root, {
		Name = "EmptyLabel",
		Text = "No dice yet",
		TextSize = 24,
		TextWrapped = true,
		TextColor3 = Kit.Soft,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -60, 0, 80),
		Visible = false,
		ZIndex = scroll.ZIndex + 1,
	})
	local sbar = Kit.scrollbar(root, scroll, scroll.ZIndex + 2)

	local function buildRow(row, order: number, cw: number)
		local rh = math.max(if narrow then 64 else ROW_H, Kit.minHit)
		local btn, setOn = Kit.card(scroll, {
			Name = "Row_" .. row.Id,
			LayoutOrder = order,
			Size = UDim2.fromOffset(cw, rh),
		}, { Radius = 12 })
		setOns[row.Id] = setOn
		setOn(row.Id == selected)
		btn.Activated:Connect(function()
			if onSelect then
				onSelect(row.Id, row)
			end
		end)
		local z = btn.ZIndex + 1
		local cy = rh / 2
		local dieName = Kit.dieName(row.Name)

		local s = if narrow then 44 else 68 -- slot size
		local sGap = if narrow then 4 else 9
		local slotsW = 4 * s + 3 * sGap
		local slotsL = cw - 8 - slotsW
		local dieBox = if narrow then 42 else 68
		local dieL = if narrow then 6 else 14
		local die = make("ImageLabel", {
			Name = "Die",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(dieL, cy),
			Size = UDim2.fromOffset(dieBox, dieBox),
			ImageColor3 = row.Tint or WHITE,
			ZIndex = z,
		}, btn)
		Kit.setIcon(die, row.Art)
		local textL = dieL + dieBox + (if narrow then 6 else 14)

		if not narrow then
			local clusterW = 168
			local clusterL = slotsL - 20 - clusterW
			local nameW = math.max(40, clusterL - 8 - textL)
			local name = Kit.text(btn, {
				Name = "Name",
				Text = dieName,
				TextSize = 28,
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.None,
				TextXAlignment = Enum.TextXAlignment.Left,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(textL, cy),
				Size = UDim2.fromOffset(nameW, 68),
				ZIndex = z,
			}, 2)
			local longest = ""
			for word in string.gmatch(dieName, "%S+") do
				if #word > #longest then
					longest = word
				end
			end
			local one = Kit.fitSize(dieName, nameW, 28, 1)
			name.TextSize = if one >= 22 then one else Kit.fitSize(longest, nameW, 28, 12) -- one line, else two (never mid-word)
			local pill = Mastery.pill(btn, clusterW, 28, row.Level, 17)
			pill.AnchorPoint = Vector2.new(0, 0.5)
			pill.Position = UDim2.fromOffset(clusterL, cy - 17)
			pill.ZIndex = z
			local xp = Kit.bar(btn, {
				Name = "XpBar",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(clusterL, cy + 19),
				Size = UDim2.fromOffset(clusterW, 22),
				ZIndex = z,
			}, Kit.Yellow, 16)
			xp:Set(QuestLogic.percent(row.Xp, row.XpGoal), QuestLogic.progressText(row.Xp, row.XpGoal))
		else
			local colW = math.max(60, slotsL - 8 - textL)
			local name = Kit.text(btn, {
				Name = "Name",
				Text = `{dieName} <font color="#FFC833">Lv. {row.Level}</font>`,
				RichText = true,
				TextSize = 17,
				TextTruncate = Enum.TextTruncate.None,
				TextXAlignment = Enum.TextXAlignment.Left,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(textL, cy - 13),
				Size = UDim2.fromOffset(colW, 24),
				ZIndex = z,
			}, 2)
			name.TextSize = Kit.fitSize(`{dieName} Lv. {row.Level}`, colW, 17, 10)
			local xp = Kit.bar(btn, {
				Name = "XpBar",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(textL, cy + 14),
				Size = UDim2.fromOffset(colW, 18),
				ZIndex = z,
			}, Kit.Yellow, 13)
			xp:Set(QuestLogic.percent(row.Xp, row.XpGoal), QuestLogic.progressText(row.Xp, row.XpGoal))
		end
		for i, m in row.Milestones do
			Mastery.slot(btn, m, s, slotsL + (i - 1) * (s + sGap) + s / 2, cy, z)
		end
	end

	local function rebuild()
		for _, c in scroll:GetChildren() do
			if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
				c:Destroy()
			end
		end
		table.clear(setOns)
		local W, H = parent.Size.X.Offset, parent.Size.Y.Offset
		if W <= 0 then
			return
		end
		narrow = W - PAD_L - PAD_R < 560
		local padR = if narrow then 20 else PAD_R
		pad.PaddingRight = UDim.new(0, padR)
		sbar.Layout(H - 14, if narrow then 12 else 16, if narrow then 3 else 5, 7)
		for i, row in rows do
			buildRow(row, i, W - PAD_L - padR)
		end
		empty.Visible = #rows == 0
	end
	table.insert(conns, parent:GetPropertyChangedSignal("Size"):Connect(rebuild))

	function api:SetRows(list)
		rows = list or {}
		rebuild()
	end
	function api:SetSelected(id: string?)
		selected = id
		for rid, setOn in setOns do
			setOn(rid == id)
		end
	end
	function api:OnSelect(cb)
		onSelect = cb
	end
	function api:SetEmptyText(s: string)
		empty.Text = s
	end
	function api:SetScroll(n: number)
		scroll.CanvasPosition = Vector2.new(0, n)
	end
	function api:SetVisible(on: boolean)
		root.Visible = on
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

return Mastery
