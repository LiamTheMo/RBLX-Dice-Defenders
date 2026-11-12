-- Quest Log, MASTERY tab: one row per dice (die, name, mastery pill + XP bar, four reward slots) in a ScrollingFrame with the
-- Bag's styled scrollbar. Mastery.new(Slots.Grid) -> :SetRows(rows) :SetSelected(id) :OnSelect(cb(id, row)) :SetEmptyText(s)
-- :SetVisible(b) :GetScroll() :SetScroll(n) :Destroy(). Mastery.pill / Mastery.bar are shared with the Detail.
-- rows = SampleData.Mastery shape (Id, Name, Level, Xp, XpGoal, Die, Milestones), already sorted/filtered by the controller.
-- Design px. Layout keys on the content width: full (>= 700: pill + 4 slots), mid (360-700: no pill, small slots), tiny (< 360: no slots).

local UiKit = require(script.Parent.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Parent.Bag.Parts)
local QuestLogic = require(script.Parent.Parent.QuestLogic)
local Draw = require(script.Parent.Parent.Draw)

local make = UiKit.make
local Bag, Q = Draw.Bag, Draw.Q

local PAD_L, PAD_R, PAD_T, PAD_B = 14, 30, 10, 16 -- left/top >= the selected glow; right = scrollbar gutter
local GAP, SEL = 5, 8 -- ref: rows 96 tall on a 101 pitch
local BAR = { ScrollTrack = Rect.new(19, 65, 22, 227) }

local function barSkin(inst, name: string, w: number)
	local s = Bag[name]
	inst.Image = s.Image
	inst.ScaleType = Enum.ScaleType.Slice
	inst.SliceCenter = BAR[name]
	inst.SliceScale = w / s.Size.X
end

local Mastery = {}

-- "Mastery Lv. N" pill of width w (height by the sprite aspect, crown baked into the art). pill.Frame; pill:Set(level).
function Mastery.pill(parent, name: string, w: number, z: number)
	local rec = Q.PillMasteryBlank
	local h = w * rec.Ink.Height / rec.Ink.Width
	local frame = Draw.img(parent, { Name = name, Size = UDim2.fromOffset(w, h), ZIndex = z }, "Frame")
	local skin = Draw.img(frame, { Name = "Skin", ZIndex = z + 1 })
	Draw.apply(skin, rec, w / 2, h / 2, w, h)
	local size = math.max(11, math.floor(w * 0.112)) -- ref "Mastery Lv. 12" ink 114-126 wide
	local avail = math.floor(w * 0.66)
	local label = Parts.text(frame, {
		Name = "Text",
		TextSize = size,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(math.floor(w * 0.6), math.floor(h / 2)),
		Size = UDim2.fromOffset(avail, h),
		ZIndex = z + 2,
	}, 2)
	local pill = { Frame = frame, Height = h }
	function pill:Set(level: number)
		label.Text = "Mastery Lv. " .. level
		Parts.fit(label, avail, size, 10)
	end
	return pill
end

-- XP bar w x h: MasteryTrack + MasteryFill (sized by width) with "6,540 / 8,000" centred. bar.Frame; bar:Set(xp, goal).
function Mastery.bar(parent, name: string, w: number, h: number, z: number, textSize: number?)
	local frame = Draw.img(parent, { Name = name, Size = UDim2.fromOffset(w, h), ZIndex = z }, "Frame")
	local track = Draw.img(frame, { Name = "Track", ZIndex = z + 1 })
	Draw.apply(track, Q.MasteryTrack, w / 2, h / 2, w, h)
	local fill = Draw.img(frame, { Name = "Fill", ZIndex = z + 2 })
	local size = textSize or math.max(12, math.floor(h * 0.55))
	local label = Parts.text(frame, {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -12, 1, 0),
		TextSize = size,
		ZIndex = z + 3,
	}, 2)
	local bar = { Frame = frame }
	function bar:Set(xp: number, goal: number)
		local inset = math.max(2, math.floor(h * 0.14))
		local fw = math.floor((w - 2 * inset) * QuestLogic.percent(xp, goal) + 0.5)
		fill.Visible = fw > 0
		if fw > 0 then
			Draw.apply(fill, Q.MasteryFill, inset + fw / 2, h / 2, fw, h - 2 * inset)
		end
		label.Text = QuestLogic.progressText(xp, goal)
		Parts.fit(label, w - 12, size, 10)
	end
	return bar
end

function Mastery.new(parent)
	local api, conns = {}, {}
	local rows, selected, onSelect = {}, nil, nil
	local recs = {} -- recs[id] = { skin, w, h, next = { skin, s, cx, cy } | nil }
	local barW = 21

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
		ScrollBarThickness = 0, -- the styled bar below replaces the native one; wheel, touch and drag still scroll
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
	local empty = Parts.text(root, {
		Name = "EmptyLabel",
		Text = "No dice yet",
		TextSize = 24,
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(205, 210, 235),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -60, 0, 80),
		Visible = false,
		ZIndex = scroll.ZIndex + 1,
	})
	local track = Draw.img(root, {
		Name = "ScrollTrack",
		AnchorPoint = Vector2.new(1, 0),
		Visible = false,
		ZIndex = scroll.ZIndex + 2,
	})
	local thumb = Draw.img(track, { Name = "Thumb", ZIndex = track.ZIndex + 1 })

	local function updateBar()
		local h = parent.Size.Y.Offset
		local y, maxY = scroll.CanvasPosition.Y, math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
		track.Visible = maxY > 1 and h > 0
		local win, canvas = scroll.AbsoluteWindowSize.Y, math.max(1, scroll.AbsoluteCanvasSize.Y)
		local thumbH = math.clamp(math.floor(h * win / canvas), 40, math.max(40, h))
		Draw.thumb(thumb, barW, thumbH, math.floor((h - thumbH) * (if maxY > 0 then y / maxY else 0)))
	end
	table.insert(conns, scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(updateBar))
	table.insert(conns, scroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(updateBar))

	local function skinRow(rec, on: boolean)
		local ex = if on then SEL else 0
		Draw.apply(rec.skin, if on then Q.RowSelected else Q.Row, rec.w / 2, rec.h / 2, rec.w + ex, rec.h + ex)
		local n = rec.next -- the Next slot gets the gold cell only while its row is selected
		if n then
			Draw.apply(
				n.skin,
				if on then Q.CellSelected else Q.SlotCopper,
				n.cx,
				n.cy,
				n.s + (if on then 8 else 0),
				n.s + (if on then 8 else 0)
			)
		end
	end

	local function buildSlot(btn, m, s: number, cx: number, cy: number, z: number, rec)
		local skin = Draw.img(btn, { Name = "Slot" .. m.Lv, ZIndex = z })
		Draw.apply(skin, Q.SlotCopper, cx, cy, s, s)
		if m.State == "Next" then
			rec.next = { skin = skin, s = s, cx = cx, cy = cy }
		end
		local icon = Draw.img(btn, { Name = "Icon" .. m.Lv, ZIndex = z + 2 })
		local irec = Q[m.Icon] or Q.Crystals
		local iw, ih = Draw.fitIn(irec, s * 0.64, s * 0.56)
		Draw.apply(icon, irec, cx, cy - s * 0.12, iw, ih)
		local size = math.max(11, math.floor(s * 0.25)) -- ref tile label ink 33 wide
		local label = Parts.text(btn, {
			Name = "Lv" .. m.Lv,
			Text = "Lv. " .. m.Lv,
			TextSize = size,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(math.floor(cx), math.floor(cy + s * 0.32)),
			Size = UDim2.fromOffset(s - 4, size + 4),
			ZIndex = z + 2,
		}, 2)
		Parts.fit(label, s - 4, size, 9)
		local done = m.State == "Done"
		local brec = if done then Q.CheckCircle else Bag.Lock
		local b = math.floor(s * 0.36)
		local bw, bh = Draw.fitIn(brec, b, b)
		local badge = Draw.img(btn, { Name = "Badge" .. m.Lv, ZIndex = z + 3 })
		Draw.apply(badge, brec, cx + s / 2 - b / 2 + 2, cy - s / 2 + b / 2 - 2, bw, bh)
	end

	local function buildRow(row, order: number, cw: number, mode: string)
		local full, tiny = mode == "full", mode == "tiny"
		local rh = if full then 96 else 72
		local btn = Draw.img(
			scroll,
			{ Name = "Row_" .. row.Id, LayoutOrder = order, Size = UDim2.fromOffset(cw, rh) },
			"ImageButton"
		)
		Parts.interact(btn)
		local skin = Draw.img(btn, { Name = "Skin" })
		local rec = { skin = skin, w = cw, h = rh }
		recs[row.Id] = rec
		local z = skin.ZIndex + 1
		local cy = rh / 2

		local s = if full then 78 else 44 -- ref: slots ~80x82, 7 apart (a hair less: the panel is 20 px narrower)
		local sGap = if full then 6 else 4
		local slotsW = if tiny then 0 else 4 * s + 3 * sGap
		local slotsL = cw - (if full then 14 else 8) - slotsW
		local dieBox = if full then 82 else 46 -- ref: die ~80x83, 22 from the row edge
		local dieL = if full then 20 else 8
		local die = Draw.img(btn, { Name = "Die", ZIndex = z })
		local drec = Q[row.Die] or Q.DieFire
		local dw, dh = Draw.fitIn(drec, dieBox, dieBox)
		Draw.apply(die, drec, dieL + dieBox / 2, cy, dw, dh)

		local textL = dieL + dieBox + (if full then 11 else 8)
		local clusterR = if tiny then cw - 8 else slotsL - (if full then 10 else 8)
		local clusterW, clusterL
		local nameW
		if full then
			clusterW = 180
			clusterL = clusterR - clusterW
			nameW = math.max(40, clusterL - 8 - textL)
		else
			clusterL, clusterW = textL, math.max(60, clusterR - textL)
		end

		local nameLabel
		if full then
			nameLabel = Parts.text(btn, {
				Name = "Name",
				Text = row.Name,
				TextSize = 27,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(textL, cy),
				Size = UDim2.fromOffset(nameW, 52),
				ZIndex = z,
			}, 3)
			local longest = ""
			for word in string.gmatch(row.Name, "%S+") do
				if #word > #longest then
					longest = word
				end
			end
			local one = Parts.fitSize(row.Name, nameW, 27, 1)
			nameLabel.TextSize = if one >= 19 then one else Parts.fitSize(longest, nameW, 27, 12) -- one line, else two (never mid-word)
		else
			nameLabel = Parts.text(btn, {
				Name = "Name",
				Text = row.Name,
				TextSize = if tiny then 15 else 17,
				TextXAlignment = Enum.TextXAlignment.Left,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(clusterL, cy - 16),
				Size = UDim2.fromOffset(clusterW, 24),
				ZIndex = z,
			}, 2)
			Parts.fit(nameLabel, clusterW, nameLabel.TextSize, 11)
		end

		if full then
			local pill = Mastery.pill(btn, "Pill", clusterW, z)
			pill.Frame.AnchorPoint = Vector2.new(0.5, 0.5)
			pill.Frame.Position = UDim2.fromOffset(clusterL + clusterW / 2, cy - 18)
			pill:Set(row.Level)
			local bar = Mastery.bar(btn, "XpBar", clusterW, 25, z, 21)
			bar.Frame.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Frame.Position = UDim2.fromOffset(clusterL + clusterW / 2, cy + 21)
			bar:Set(row.Xp, row.XpGoal)
		else
			local bar = Mastery.bar(btn, "XpBar", clusterW, 20, z)
			bar.Frame.AnchorPoint = Vector2.new(0, 0.5)
			bar.Frame.Position = UDim2.fromOffset(clusterL, cy + 16)
			bar:Set(row.Xp, row.XpGoal)
		end

		if not tiny then
			for i, m in QuestLogic.masteryMilestones(row) do
				local cx = slotsL + (i - 1) * (s + sGap) + s / 2
				buildSlot(btn, m, s, cx, cy, z, rec)
			end
		end
		skinRow(rec, row.Id == selected)
		btn.Activated:Connect(function()
			if onSelect then
				onSelect(row.Id, row)
			end
		end)
	end

	local function rebuild()
		for _, c in scroll:GetChildren() do
			if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
				c:Destroy()
			end
		end
		table.clear(recs)
		local W = parent.Size.X.Offset
		if W <= 0 then
			return
		end
		local cw = W - PAD_L - PAD_R
		local mode = if cw >= 700 then "full" elseif cw >= 360 then "mid" else "tiny"
		-- the scrollbar gutter is only reserved when the rows overflow (ref: the 5 rows fill the panel width)
		local rh = if mode == "full" then 96 else 72
		local overflow = #rows * rh + math.max(0, #rows - 1) * GAP + PAD_T + PAD_B > parent.Size.Y.Offset
		local padR = if overflow then PAD_R else 16
		pad.PaddingRight = UDim.new(0, padR)
		cw = W - PAD_L - padR
		barW = if cw >= 360 then 21 else 12
		track.Size = UDim2.fromOffset(barW, parent.Size.Y.Offset)
		track.Position = UDim2.new(1, if cw >= 360 then -7 else -6, 0, 0)
		barSkin(track, "ScrollTrack", barW)
		for i, row in rows do
			buildRow(row, i, cw, mode)
		end
		empty.Visible = #rows == 0
		updateBar()
	end
	table.insert(conns, parent:GetPropertyChangedSignal("Size"):Connect(rebuild))

	function api:SetRows(list)
		rows = list or {}
		rebuild()
	end
	function api:SetSelected(id: string?)
		selected = id
		for rid, rec in recs do
			skinRow(rec, rid == id)
		end
	end
	function api:OnSelect(cb)
		onSelect = cb
	end
	function api:SetEmptyText(s: string)
		empty.Text = s
	end
	function api:GetScroll(): number
		return scroll.CanvasPosition.Y
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
