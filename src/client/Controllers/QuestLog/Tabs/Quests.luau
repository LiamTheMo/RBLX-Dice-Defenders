-- Quest Log, QUESTS tab: sections (DAILY / WEEKLY / STORY) of quest rows in one ScrollingFrame with a code-drawn scrollbar.
-- Quests.new(grid) -> :SetRows(rows) :SetResetText(daily, weekly) :SetSelected(id) :OnSelect(cb(id, row)) :OnClaim(cb(id, row))
-- :SetEmptyText(s) :SetScroll(n) :SetVisible(b) :Destroy(). Visual only; rows come from QuestLogic.questRows (already filtered).
-- Design px; `grid` is the list panel's interior. Row layout keys on the width: full (>= 560) or narrow (phones: two lines, stacked rewards).
-- Name paths: QuestsTab.QuestScroll.Head_<Section> / Row_<Id> (.Claim / .Progress), QuestsTab.ScrollTrack.

local UiKit = require(script.Parent.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Parent.Bag.Parts)
local HudSprites = require(script.Parent.Parent.Parent.Sprites)
local QuestLogic = require(script.Parent.Parent.QuestLogic)
local Kit = require(script.Parent.Parent.Kit)

local make = UiKit.make
local WHITE = Color3.new(1, 1, 1)

local PAD_L, PAD_R, PAD_T, PAD_B = 8, 30, 6, 6 -- right = scrollbar gutter
local ROW_H, GAP, HEAD_H, SEC_GAP = 50, 5, 40, 12
local SECTIONS = {
	{ Id = "Daily", Title = "DAILY QUESTS", Icon = "QuestCalendar", Reset = true },
	{ Id = "Weekly", Title = "WEEKLY QUESTS", Icon = "QuestCalendarWeek", Reset = true, Mark = "7" },
	{ Id = "Story", Title = "STORY QUESTS", Icon = "IconQuestScroll", Reset = false },
}

local function icon(parent, ref, props)
	props.BackgroundTransparency = 1
	props.ZIndex = props.ZIndex or parent.ZIndex + 1
	local i = make("ImageLabel", props, parent)
	Kit.setIcon(i, ref)
	return i
end

local Quests = {}

function Quests.new(parent)
	local api, conns = {}, {}
	local rows, selected, onSelect, onClaim = {}, nil, nil, nil
	local resetText = { Daily = nil, Weekly = nil }
	local setOns, heads = {}, {} -- setOns[id](bool); heads[sectionId] = timer
	local narrow = false

	local root = make("Frame", {
		Name = "QuestsTab",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = parent.ZIndex,
	}, parent)
	local scroll = make("ScrollingFrame", {
		Name = "QuestScroll",
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
		Text = "No quests yet",
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

	local function buildHeader(sec, order: number, first: boolean, cw: number)
		local f = make("Frame", {
			Name = "Head_" .. sec.Id,
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Size = UDim2.fromOffset(cw, HEAD_H + (if first then 0 else SEC_GAP - GAP)),
			ZIndex = scroll.ZIndex + 1,
		}, scroll)
		local topPad = if first then 0 else SEC_GAP - GAP
		local strip = f -- plain header (mockup): title, large calendar icon, clock + "Resets in"
		local isz = if narrow then 36 else 44
		local ic = icon(f, sec.Icon, {
			Name = "Icon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(if narrow then 4 else 8, topPad + HEAD_H / 2),
			Size = UDim2.fromOffset(isz, isz),
			ZIndex = strip.ZIndex + 1,
		})
		if sec.Mark then -- the weekly calendar's page number (live text, the art is a blank page)
			make("TextLabel", {
				Name = "Mark",
				BackgroundTransparency = 1,
				Font = Enum.Font.FredokaOne,
				Text = sec.Mark,
				TextSize = math.floor(isz * 0.42),
				TextColor3 = Color3.fromRGB(215, 40, 52),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.64),
				Size = UDim2.fromScale(0.6, 0.4),
				ZIndex = ic.ZIndex + 1,
			}, ic)
		end
		local timerW = if narrow then 150 else 226
		local textL = (if narrow then 4 else 8) + isz + 8
		local timer
		if sec.Reset then
			timer = Kit.timer(f, {
				Name = "Reset",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromOffset(cw - 6, topPad + HEAD_H / 2),
				Size = UDim2.fromOffset(timerW, if narrow then 26 else 32),
				ZIndex = strip.ZIndex + 1,
			})
			heads[sec.Id] = timer
			if resetText[sec.Id] then
				timer:Set("Resets in:", resetText[sec.Id])
			end
		end
		local avail = cw - textL - (if sec.Reset then timerW + 12 else 8)
		local title = Kit.text(f, {
			Name = "Title",
			Text = sec.Title,
			TextSize = if narrow then 19 else 25,
			TextXAlignment = Enum.TextXAlignment.Left,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(textL, topPad + HEAD_H / 2),
			Size = UDim2.fromOffset(math.max(20, avail), HEAD_H),
			ZIndex = strip.ZIndex + 1,
		}, 2)
		Kit.fit(title, avail, title.TextSize, 12)
	end

	local function claimButton(btn, row, x: number, cy: number, w: number, h: number, textSize: number)
		local hitH = math.min(btn.Size.Y.Offset, math.max(h, Kit.minHit))
		local hit = make("TextButton", {
			Name = "ClaimHit",
			BackgroundTransparency = 1,
			Text = "",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(x - math.max(0, (Kit.minHit - w) / 2), cy),
			Size = UDim2.fromOffset(math.max(w, Kit.minHit), hitH),
			ZIndex = btn.ZIndex + 4,
		}, btn)
		local visual = Parts.button(hit, {
			Name = "Claim",
			Style = "Green",
			Label = "CLAIM",
			TextSize = textSize,
			Size = UDim2.fromOffset(w, h),
		})
		visual.AnchorPoint = Vector2.new(0.5, 0.5)
		visual.Position = UDim2.fromScale(0.5, 0.5)
		visual.Interactable = false -- the transparent hit button above takes the tap
		visual.Selectable = false
		UiKit.wire(hit, function(state)
			visual:SetAttribute("DebugState", if state == "Normal" then nil else state)
		end)
		hit.Activated:Connect(function()
			if onClaim then
				onClaim(row.Id, row)
			end
		end)
	end

	local function buildRow(row, order: number, cw: number)
		local state = QuestLogic.claimState(row)
		local rowH = math.max(if narrow then 56 else ROW_H, Kit.minHit)
		local btn, setOn = Kit.card(scroll, {
			Name = "Row_" .. row.Id,
			LayoutOrder = order,
			Size = UDim2.fromOffset(cw, rowH),
		}, { Radius = 10 })
		setOns[row.Id] = setOn
		setOn(row.Id == selected)
		btn.Activated:Connect(function()
			if onSelect then
				onSelect(row.Id, row)
			end
		end)
		local z = btn.ZIndex + 1
		local cy = rowH / 2
		local complete = row.Goal > 0 and row.Progress >= row.Goal

		-- Right to left: claim slot, gem, coin, bar; the left column keeps the rest.
		local claimW = if narrow then 72 else 93
		local claimH = if narrow then 32 else 34
		local claimX = cw - 8 - claimW
		if state == "Claim" then
			claimButton(btn, row, claimX, cy, claimW, claimH, if narrow then 17 else 21)
		elseif state == "Claimed" then
			local pill = Parts.Pill(btn, "Equipped", "CLAIMED", {
				Check = true,
				Name = "Claimed",
				InkW = claimW,
				InkH = if narrow then 26 else 30,
				TextSize = if narrow then 15 else 19,
				CheckLeft = true,
			})
			pill.AnchorPoint = Vector2.new(0, 0.5)
			pill.Position = UDim2.fromOffset(claimX, cy)
		end
		local noButton = state == "Progress"
		local reserve = if narrow then not noButton else not (row.Section ~= "Daily" and noButton) -- weekly / story rows run to the edge
		local right = if reserve then claimX - 14 else cw - 18
		local gold = "+" .. QuestLogic.format(row.Gold or 0)
		local gems = if row.Gems then "+" .. QuestLogic.format(row.Gems) else nil

		local barLeft, barW
		local textL = if narrow then 46 else 66
		local nameR
		if not narrow then
			local function reward(ref, text: string, color: Color3, edge: number): number
				local tw = math.ceil(Kit.measure(text, 22)) + 2
				local left = edge - (26 + 4 + tw)
				icon(btn, ref, {
					Name = "RewardIcon",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromOffset(left, cy),
					Size = UDim2.fromOffset(26, 26),
					ZIndex = z,
				})
				Kit.text(btn, {
					Name = "RewardText",
					Text = text,
					TextSize = 22,
					TextColor3 = color,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.None,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromOffset(left + 30, cy),
					Size = UDim2.fromOffset(tw, 28),
					ZIndex = z,
				}, 2)
				return left
			end
			local edge = right
			if gems then
				edge = reward(HudSprites.Gem, gems, WHITE, edge) - 14
			end
			edge = reward(HudSprites.Coin, gold, Kit.CoinText, edge) - 14
			barW = 150
			barLeft = edge - barW
			nameR = barLeft - 12
			local bar = Kit.bar(btn, {
				Name = "Progress",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(barLeft, cy),
				Size = UDim2.fromOffset(barW, 22),
				ZIndex = z,
			}, if complete then Kit.Green else Kit.Yellow, 17)
			bar:Set(
				QuestLogic.percent(row.Progress, row.Goal),
				QuestLogic.progressText(row.Progress, row.Goal),
				if complete then Kit.Green else Kit.Yellow
			)
		else
			-- phone: reward stack (coin over gem) right of the bar; the bar sits under the name
			local lines = { { HudSprites.Coin, gold, Kit.CoinText } }
			if gems then
				table.insert(lines, { HudSprites.Gem, gems, Color3.new(1, 1, 1) })
			end
			local widest = 0
			for _, l in lines do
				widest = math.max(widest, math.ceil(Kit.measure(l[2], 15)) + 2)
			end
			local left = right - (18 + 3 + widest)
			for i, l in lines do
				local y = cy + (if #lines == 1 then 0 else (i - 1.5) * 20)
				icon(btn, l[1], {
					Name = "RewardIcon",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromOffset(left, y),
					Size = UDim2.fromOffset(18, 18),
					ZIndex = z,
				})
				Kit.text(btn, {
					Name = "RewardText",
					Text = l[2],
					TextSize = 15,
					TextColor3 = l[3],
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.None,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromOffset(left + 21, y),
					Size = UDim2.fromOffset(widest, 20),
					ZIndex = z,
				}, 2)
			end
			nameR = left - 8
			barLeft, barW = textL, math.max(40, nameR - textL)
			local bar = Kit.bar(btn, {
				Name = "Progress",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(barLeft, cy + 13),
				Size = UDim2.fromOffset(barW, 16),
				ZIndex = z,
			}, if complete then Kit.Green else Kit.Yellow, 13)
			bar:Set(
				QuestLogic.percent(row.Progress, row.Goal),
				QuestLogic.progressText(row.Progress, row.Goal),
				if complete then Kit.Green else Kit.Yellow
			)
		end

		-- Left column: icon, name (+ desc).
		local isz = if narrow then 34 else 44
		icon(btn, row.Icon, {
			Name = "Icon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(if narrow then 8 else 14, cy),
			Size = UDim2.fromOffset(isz, isz),
			ZIndex = z,
		})
		local colW = math.max(40, nameR - textL)
		local name = Kit.text(btn, {
			Name = "Name",
			Text = row.Name,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(textL, if narrow then cy - 11 else 15),
			Size = UDim2.fromOffset(colW, 22),
			ZIndex = z,
		}, 2)
		Kit.fit(name, colW, 14, 9)
		if not narrow then
			local desc = Kit.text(btn, {
				Name = "Desc",
				Text = row.Desc,
				TextSize = 11,
				TextColor3 = Kit.Soft,
				TextXAlignment = Enum.TextXAlignment.Left,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(textL + 1, 37),
				Size = UDim2.fromOffset(colW, 16),
				ZIndex = z,
			}, 1)
			Kit.fit(desc, colW, 11, 8)
		end
	end

	-- Rebuilds every section and row (counts are tiny); the scroll offset is the controller's to keep.
	local function rebuild()
		for _, c in scroll:GetChildren() do
			if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
				c:Destroy()
			end
		end
		table.clear(setOns)
		table.clear(heads)
		local W, H = parent.Size.X.Offset, parent.Size.Y.Offset
		if W <= 0 then
			return
		end
		narrow = W - PAD_L - PAD_R < 560
		pad.PaddingRight = UDim.new(0, if narrow then 20 else PAD_R)
		local cw = W - PAD_L - (if narrow then 20 else PAD_R)
		sbar.Layout(H - 14, if narrow then 12 else 16, if narrow then 3 else 5, 7)
		local order, shown = 0, 0
		for _, sec in SECTIONS do
			local list = {}
			for _, row in rows do
				if row.Section == sec.Id then
					table.insert(list, row)
				end
			end
			if #list > 0 then
				order += 1
				buildHeader(sec, order, shown == 0, cw)
				shown += 1
				for _, row in list do
					order += 1
					buildRow(row, order, cw)
				end
			end
		end
		empty.Visible = #rows == 0
	end
	table.insert(conns, parent:GetPropertyChangedSignal("Size"):Connect(rebuild))

	function api:SetRows(list)
		rows = list or {}
		rebuild()
	end
	function api:SetResetText(daily: string?, weekly: string?)
		resetText.Daily, resetText.Weekly = daily, weekly
		for id, timer in heads do
			if resetText[id] and resetText[id] ~= "" then
				timer.Frame.Visible = true
				timer:Set("Resets in:", resetText[id])
			else
				timer.Frame.Visible = false
			end
		end
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
	function api:OnClaim(cb)
		onClaim = cb
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

return Quests
