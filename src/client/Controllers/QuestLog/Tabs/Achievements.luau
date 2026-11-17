-- Quest Log, ACHIEVEMENTS tab: a grid of laurel-badge cards in one ScrollingFrame with a code-drawn scrollbar.
-- Achievements.new(grid) -> :SetItems(items) :SetSelected(id) :OnSelect(cb(id, item)) :SetEmptyText(s) :SetVisible(b) :SetScroll(n) :Destroy()
-- Achievements.status(parent, props, textSize) -> { Frame, Set(item) }: COMPLETE pill or progress bar ("8 / 10"); the Detail reuses it.
-- Card states: complete (green COMPLETE pill), in progress (gold bar), locked (nothing earned yet: grey badge, padlock, empty bar).
-- Design px. Columns = clamp(floor((W - 12) / 112), 2, 5). Name paths: AchievementsTab.AchievementScroll.Cell_<Id> (.Badge .Name .Status).

local UiKit = require(script.Parent.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Parent.Bag.Parts)
local Shared = require(script.Parent.Parent.Parent.SharedSprites)
local QuestLogic = require(script.Parent.Parent.QuestLogic)
local Kit = require(script.Parent.Parent.Kit)
local Q = require(script.Parent.Parent.QuestSprites)

local make = UiKit.make

local PAD_L, PAD_T, PAD_B = 4, 4, 6
local GAP, GAP_Y = 5, 5
local RATIO = 0.95 -- card height / width (mockup 145 / 148; slightly shorter so three rows fit the list height)

local function isComplete(b): boolean
	return b.Goal > 0 and b.Progress >= b.Goal
end

local function isLocked(b): boolean
	return b.Progress <= 0 and not isComplete(b)
end

local Achievements = {}

function Achievements.status(parent, props, textSize: number)
	local w, h = props.Size.X.Offset, props.Size.Y.Offset
	props.BackgroundTransparency = 1
	props.ZIndex = props.ZIndex or parent.ZIndex + 1
	local frame = make("Frame", props, parent)
	local done =
		Parts.button(frame, { -- the shared saturated green pill (as Codes / Play), not the muted rarity-tag green
			Name = "Complete",
			Style = "Green",
			Label = "COMPLETE",
			Icon = Parts.CheckKey,
			TextSize = math.max(9, math.min(math.floor(textSize * Kit.S), h - 10)), -- the line must fit the pill's label height
			Size = UDim2.fromOffset(w, h),
		})
	done.Interactable, done.Selectable = false, false
	local bar = Kit.bar(frame, {
		Name = "Progress",
		Size = UDim2.fromOffset(w, h),
		ZIndex = frame.ZIndex + 1,
	}, Kit.Yellow, textSize)
	local status = { Frame = frame }
	function status:Set(item)
		local complete = isComplete(item)
		done.Visible, bar.Frame.Visible = complete, not complete
		if not complete then
			bar:Set(QuestLogic.percent(item.Progress, item.Goal), QuestLogic.progressText(item.Progress, item.Goal))
		end
	end
	return status
end

function Achievements.new(parent)
	local api, conns = {}, {}
	local items, selected, onSelect = {}, nil, nil
	local setOns = {}

	local root = make("Frame", {
		Name = "AchievementsTab",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = parent.ZIndex,
	}, parent)
	local scroll = make("ScrollingFrame", {
		Name = "AchievementScroll",
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
		PaddingTop = UDim.new(0, PAD_T),
		PaddingBottom = UDim.new(0, PAD_B),
	}, scroll)
	local grid = make("UIGridLayout", {
		CellPadding = UDim2.fromOffset(GAP, GAP_Y),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
	}, scroll)
	local empty = Kit.text(root, {
		Name = "EmptyLabel",
		Text = "No achievements yet",
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

	local function buildCell(item, order: number, cw: number, ch: number)
		local btn, setOn = Kit.card(scroll, { Name = "Cell_" .. item.Id, LayoutOrder = order }, { Radius = 12 })
		setOns[item.Id] = setOn
		setOn(item.Id == selected)
		btn.Activated:Connect(function()
			if onSelect then
				onSelect(item.Id, item)
			end
		end)
		local z = btn.ZIndex + 1
		local locked = isLocked(item)
		local badge = make("ImageLabel", {
			Name = "Badge",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cw / 2, ch * 0.3),
			Size = UDim2.fromOffset(cw * 0.96, ch * 0.54),
			ImageColor3 = if locked then Color3.fromRGB(105, 105, 112) else Color3.new(1, 1, 1),
			ZIndex = z,
		}, btn)
		Kit.setIcon(badge, Q[item.Badge] or Q.BadgeKing)
		if locked then
			local lk = math.floor(cw * 0.17)
			make("ImageLabel", {
				Name = "Lock",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromOffset(cw - 6, 6),
				Size = UDim2.fromOffset(lk, lk),
				Image = Shared.Padlock.Image,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = z + 1,
			}, btn)
		end
		local nameSize = math.max(9, math.floor(15 * cw / 146 + 0.5))
		local nameLabel = Kit.text(btn, {
			Name = "Name",
			Text = string.upper(item.Name),
			TextSize = nameSize,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cw / 2, ch * 0.66),
			Size = UDim2.fromOffset(cw - 8, math.floor(ch * 0.3)),
			ZIndex = z,
		}, 2)
		while nameLabel.TextBounds.Y > nameLabel.AbsoluteSize.Y and nameLabel.TextSize > 10 do -- wrap to 2 lines, then shrink until it fits
			nameLabel.TextSize -= 1
		end
		local ph = math.floor(ch * 0.17)
		local status = Achievements.status(btn, {
			Name = "Status",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cw / 2, ch * 0.88),
			Size = UDim2.fromOffset(math.floor(cw * 0.8), ph),
			ZIndex = z,
		}, math.max(11, math.floor(ph * 0.62)))
		status:Set(item)
	end

	local function rebuild()
		for _, c in scroll:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		table.clear(setOns)
		local W, H = parent.Size.X.Offset, parent.Size.Y.Offset
		if W <= 0 then
			return
		end
		local cols = math.clamp(math.floor((W - 12) / 112), 2, 5)
		local function cell(padR: number): (number, number)
			local w = math.floor((W - PAD_L - padR - (cols - 1) * GAP) / cols)
			return w, math.max(math.floor(w * RATIO + 0.5), Kit.minHit)
		end
		local padR = 4 -- the scrollbar gutter is only reserved when the grid overflows
		local cw, ch = cell(padR)
		local rowsN = math.ceil(#items / cols)
		local overflow = rowsN * ch + math.max(0, rowsN - 1) * GAP_Y + PAD_T + PAD_B > H
		if overflow then
			padR = 24
			cw, ch = cell(padR)
		end
		pad.PaddingRight = UDim.new(0, padR)
		grid.CellSize = UDim2.fromOffset(cw, ch)
		grid.FillDirectionMaxCells = cols
		sbar.Layout(H - 8, 16, 2, 4)
		for i, item in items do
			buildCell(item, i, cw, ch)
		end
		empty.Visible = #items == 0
	end
	table.insert(conns, parent:GetPropertyChangedSignal("Size"):Connect(rebuild))

	function api:SetItems(list)
		items = list or {}
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

return Achievements
