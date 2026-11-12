-- Quest Log, ACHIEVEMENTS tab: a grid of badge cells in one ScrollingFrame with the Bag's styled scrollbar.
-- Achievements.new(Slots.Grid) -> :SetItems(items) :SetSelected(id) :OnSelect(cb(id, item)) :OnClaim(cb(id, item)) (cells never claim)
-- :SetEmptyText(s) :SetVisible(b) :GetScroll() :SetScroll(n) :Destroy(). Achievements.pill(...) is the status pill the Detail reuses.
-- Design px. Columns = clamp(floor((W - 12) / 112), 2, 5); cells are 146x160 in the reference (CARD_W/H), 9-sliced at a fixed rim scale; content scales with the cell.

local TextService = game:GetService("TextService")

local UiKit = require(script.Parent.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Parent.Bag.Parts)
local QuestLogic = require(script.Parent.Parent.QuestLogic)
local Draw = require(script.Parent.Parent.Draw)

local make = UiKit.make
local Bag, Q = Draw.Bag, Draw.Q

local PAD_L, PAD_R, PAD_T, PAD_B = 10, 30, 11, 14 -- left/top >= the selected glow bleed; right = scrollbar gutter (only when the grid scrolls)
local GAP, GAP_Y, GLOW = 8, 13, 10 -- ref: cells ~152x160 on a 160 / 171 pitch -- cell gap; selected cell ink grows by GLOW (5 per side) inside the sprite's own margin
local CARD_W, CARD_H = 146, 160 -- reference card (visible rim); cell height = width * 160 / 146
local LOCKED_GREY = Color3.fromRGB(150, 146, 152) -- PillGrey toned toward the reference's dark charcoal pill; the rim stays light
local BAR = { ScrollTrack = Rect.new(19, 65, 22, 227) }

local function barSkin(inst, name: string, w: number)
	local s = Bag[name]
	inst.Image = s.Image
	inst.ScaleType = Enum.ScaleType.Slice
	inst.SliceCenter = BAR[name]
	inst.SliceScale = w / s.Size.X
end

local function isComplete(b): boolean
	return not b.Locked and b.Goal > 0 and b.Progress >= b.Goal
end

local Achievements = {}

-- Status pill w x h: COMPLETE (sliced green + check), progress (track + fill, "8 / 10" / "LVL 12 / 20") or locked (grey track).
-- pill.Frame; pill:Set(b) with b = { Progress, Goal, Unit?, Locked? }.
function Achievements.pill(
	parent,
	name: string,
	w: number,
	h: number,
	z: number,
	sizes: { Done: number, Prog: number }?
)
	local frame = Draw.img(parent, { Name = name, Size = UDim2.fromOffset(w, h), ZIndex = z }, "Frame")
	local skin = Draw.img(frame, { Name = "Skin", ZIndex = z + 1 })
	local fill = Draw.img(frame, { Name = "Fill", ZIndex = z + 2 })
	local check = Draw.img(frame, { Name = "Check", ZIndex = z + 3 })
	local size = math.max(12, math.floor(h * 0.55))
	local label = Parts.text(frame, {
		Name = "Text",
		TextSize = size,
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = z + 4,
	}, 2)
	local pill = { Frame = frame }
	function pill:Set(b)
		local done = isComplete(b)
		Draw.apply(
			skin,
			if done then Q.PillComplete elseif b.Locked then Bag.PillGrey else Q.BarTrackAch,
			w / 2,
			h / 2,
			w,
			h
		)
		skin.ImageColor3 = if b.Locked then LOCKED_GREY else Color3.new(1, 1, 1)
		local pct = if b.Locked then 0 else QuestLogic.percent(b.Progress, b.Goal)
		local inset = math.max(2, math.floor(h * 0.1))
		local fw = if done then 0 else math.floor((w - 2 * inset) * pct + 0.5)
		fill.Visible = fw > 0
		if fw > 0 then
			Draw.apply(fill, Q.BarFillAch, inset + fw / 2, h / 2, fw, h - 2 * inset)
		end
		local text = if done then "COMPLETE" else QuestLogic.progressText(b.Progress, b.Goal, b.Unit)
		local cs = if done then math.floor(h * 0.8) else 0
		local gap = if done then 4 else 0
		local avail = w - 12 - cs - gap
		label.Text = text
		label.TextSize =
			Parts.fitSize(text, avail, if sizes then (if done then sizes.Done else sizes.Prog) else size, 10)
		local tw = TextService:GetTextSize(text, label.TextSize, label.Font, Vector2.new(1e5, 1e5)).X + 2
		local x0 = (w - (cs + gap + tw)) / 2
		check.Visible = done
		if done then
			local iw, ih = Draw.fitIn(Bag.Check, cs, cs)
			Draw.apply(check, Bag.Check, x0 + cs / 2, h / 2, iw, ih)
		end
		label.Position = UDim2.fromOffset(math.floor(x0 + cs + gap), math.floor(h / 2))
		label.Size = UDim2.fromOffset(math.ceil(tw), h)
	end
	return pill
end

function Achievements.new(parent)
	local api, conns = {}, {}
	local items, selected, onSelect = {}, nil, nil
	local recs = {} -- recs[id] = { skin, w, h, locked }
	local barW = 21

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
	local grid = make("UIGridLayout", {
		CellPadding = UDim2.fromOffset(GAP, GAP_Y),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
	}, scroll)
	local empty = Parts.text(root, {
		Name = "EmptyLabel",
		Text = "No achievements yet",
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

	local function skinCell(rec, on: boolean)
		local spr = if on then Q.CellSelected elseif rec.locked then Q.CellLocked else Q.CellCopper
		local ex = if on then GLOW else 0
		-- rim keeps the thickness the whole-drawn 262 px ink had at this width (k = w / 262)
		Draw.apply(rec.skin, spr, rec.w / 2, rec.h / 2, rec.w + ex, rec.h + ex, rec.w / Q.CellCopper.Ink.Width)
		rec.glow.Visible = on
	end

	local function buildCell(item, order: number, cw: number, ch: number, nameSize: number)
		local btn = Draw.img(scroll, { Name = "Cell_" .. item.Id, LayoutOrder = order }, "ImageButton")
		Parts.interact(btn)
		local skin = Draw.img(btn, { Name = "Skin" })
		local rec = { skin = skin, w = cw, h = ch, locked = item.Locked }
		local z = skin.ZIndex + 1
		-- ref: the warm radial glow exists on the SELECTED cell only (Bag legendary glow, clipped to the cell's rounded interior)
		local box = Draw.img(
			btn,
			{ Name = "GlowBox", Size = UDim2.fromOffset(cw - 12, ch - 12), ClipsDescendants = true, ZIndex = z },
			"Frame"
		)
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromOffset(cw / 2, ch / 2)
		make("UICorner", { CornerRadius = UDim.new(0, math.floor(cw * 0.1)) }, box)
		local g = Draw.img(
			box,
			{ Name = "Glow", ImageTransparency = 0.05, ImageColor3 = Color3.fromRGB(255, 120, 25), ZIndex = z }
		)
		Draw.apply(g, Q.GlowRadial, (cw - 12) / 2, ch * 0.31 - 6, cw * 1.3, cw * 1.3)
		rec.glow = box
		recs[item.Id] = rec
		skinCell(rec, item.Id == selected)
		local badge = Draw.img(btn, { Name = "Badge", ZIndex = z + 1 })
		local brec = Q[item.Badge] or Q.BadgeKing
		local bw, bh = Draw.fitIn(brec, cw * 0.92, ch * 0.52) -- ref crown + laurels ~122 wide in a 146 cell
		Draw.apply(badge, brec, cw / 2, ch * 0.31, bw, bh)
		Parts.text(btn, {
			Name = "Name",
			Text = string.upper(item.Name),
			TextSize = nameSize,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cw / 2, math.floor(ch * 0.65)),
			Size = UDim2.fromOffset(cw - 6, 26),
			ZIndex = z,
		}, 2)
		local ph = math.floor((if isComplete(item) then 27 else 30) * ch / CARD_H + 0.5) -- ref pills: COMPLETE 27 tall, progress / locked 30
		local pw = math.floor(cw * 0.8)
		local pill = Achievements.pill(btn, "Status", pw, ph, z, { Done = 16, Prog = 19 }) -- ref ink widths 76 / 43
		pill.Frame.AnchorPoint = Vector2.new(0.5, 0.5)
		pill.Frame.Position = UDim2.fromOffset(cw / 2, math.floor(ch * 0.86))
		pill:Set(item)
		btn.Activated:Connect(function()
			if onSelect then
				onSelect(item.Id, item)
			end
		end)
	end

	local function rebuild()
		for _, c in scroll:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		table.clear(recs)
		local W = parent.Size.X.Offset
		if W <= 0 then
			return
		end
		barW = if W >= 360 then 21 else 12
		track.Size = UDim2.fromOffset(barW, parent.Size.Y.Offset)
		track.Position = UDim2.new(1, if W >= 360 then -7 else -6, 0, 0)
		barSkin(track, "ScrollTrack", barW)
		local cols = math.clamp(math.floor((W - 12) / 112), 2, 5)
		local padL = if W < 560 then 14 else PAD_L -- phone: selected glow clear of the list's left rim
		pad.PaddingLeft = UDim.new(0, padL)
		local function cell(padR: number): (number, number)
			local w = math.floor((W - padL - padR - (cols - 1) * GAP) / cols)
			return w, math.floor(w * CARD_H / CARD_W + 0.5)
		end
		local padR = 10 -- the scrollbar gutter is only reserved when the grid overflows (ref: 3 rows fill the panel)
		local cw, ch = cell(padR)
		local rowsN = math.ceil(#items / cols)
		if rowsN * ch + math.max(0, rowsN - 1) * GAP_Y + PAD_T + PAD_B > parent.Size.Y.Offset then
			padR = PAD_R
			cw, ch = cell(padR)
		end
		pad.PaddingRight = UDim.new(0, padR)
		grid.CellSize = UDim2.fromOffset(cw, ch)
		grid.FillDirectionMaxCells = cols
		-- ONE name size for every cell (overseer decision, our font is ~20% wider than the ref's): the largest that fits
		-- every name in cell width - 6, at most 21 (ref DICE KING = 21 pt)
		local nameSize = math.max(12, math.floor(21 * cw / CARD_W + 0.5))
		for _, item in items do
			nameSize = math.min(nameSize, Parts.fitSize(string.upper(item.Name), cw - 6, nameSize, 8))
		end
		for i, item in items do
			buildCell(item, i, cw, ch, nameSize)
		end
		empty.Visible = #items == 0
		updateBar()
	end
	table.insert(conns, parent:GetPropertyChangedSignal("Size"):Connect(rebuild))

	function api:SetItems(list)
		items = list or {}
		rebuild()
	end
	function api:SetSelected(id: string?)
		selected = id
		for rid, rec in recs do
			skinCell(rec, rid == id)
		end
	end
	function api:OnSelect(cb)
		onSelect = cb
	end
	function api:OnClaim(_cb) end -- reserved: cells have no claim control; the Detail button claims
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

return Achievements
