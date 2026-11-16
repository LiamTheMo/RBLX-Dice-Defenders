-- Roll menu view: featured dice | rarity chances, pity row and the two ROLL buttons, drawn inside the shared shell's content slot.
-- Visual only: no NetClient, no game data. Design px under the shell's UIScale; the slot's Size offset and "Compact" attribute pick the layout.
-- View.new(slot) -> :SetPool("Standard"|"Event") :SetFeatured({ [1..3] = {Id, Rarity, Name}? }, title?) :SetOdds(RollLogic.oddsRows)
--   :SetPity({Count, Max, Rarity})
--   :SetButtons({ {Count, Price, Enabled} x2 }) :OnRoll(cb(count)) :OnInfo(cb()) :Destroy()
-- Setters only store state; one deferred rebuild draws it (also on every slot size / Compact change).
-- Compact (phones): the same stack with smaller dice and rows inside one ScrollingFrame (it scrolls only when the stack is taller).

local TextService = game:GetService("TextService")

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Bag.Parts)
local Draw = require(script.Parent.Parent.QuestLog.Draw)
local Sprites = require(script.Parent.Parent.Sprites)
local QuestLogic = require(script.Parent.Parent.QuestLog.QuestLogic)
local RollLogic = require(script.Parent.RollLogic)
local RollSprites = require(script.Parent.RollSprites)

local Q, Bag = Draw.Q, Draw.Bag
local make = UiKit.make

local YELLOW = "#FFF200"
local ROW_ART = { -- one art family for all six rows
	Secret = RollSprites.RowSecret,
	Mythic = RollSprites.RowMythic,
	Legendary = RollSprites.RowLegendary,
	Epic = RollSprites.RowEpic,
	Rare = RollSprites.RowRare,
	Common = RollSprites.RowCommon,
}
local ROW_ICON = {
	Secret = RollSprites.CrownSecret,
	Mythic = RollSprites.CrownMythic,
	Legendary = RollSprites.CrownGold,
	Epic = RollSprites.CrownEpic,
	Rare = RollSprites.StarsRare,
	Common = RollSprites.StarCommon,
}
-- icon boxes at the Full tier (visible px): crowns 41 x 25, Rare stars 50 x 20, Common star 24 x 23; phones scale them with the row
local ICON_BOX = { Rare = { 50, 20 }, Common = { 24, 23 } }
local CROWN_BOX = { 41, 25 }
local RIM_B = 3 -- the Rarity panel's inner face ends this far above its visible bottom (Bag_Detail: 14 source px from the ink, 8 of them outside the visible box, at slice scale 0.5)
local ROW_GAP_MIN = 8.5 -- design px between the plate, the rows and the rim's inner face
local ROW_GAP_COMPACT = 3.75 -- phones: 3 real px between the rows, the heading and the rim's inner face (text stays >= 14 real px, so the rows take the height)
local ROW_EDGE_MIN = 11.6 -- design px from the plate's visible bottom / the rim box edge (3 above the bottom rim) to the rows: >= 4.6 real px of bare face at 1235x681 (8 design px to the rim's first pixel)
local ROW_GAP_REAL = 3 -- phones: the least real px between two rows
local RIM_T_C, RIM_B_C = 8, 5.85 -- phones, Rarity panel (pixel scan of the 667 capture): rim bands 6.4 / 5.6 real px at UIScale 0.8, from the visible box edges; the rows end 1 real px lower (4.3 real px to the face) to widen the heading strip
local RIM_B_844 = 7.45 -- 844: the bottom rim's first pixel (highlight, not the dark face edge) sits 1.7 real px higher than at 667 (pixel scan); 1.75 less than that, the row block shares ROWS_DROP_844 with the top margin
local ROWS_DROP_844 = 1.75 -- 844: the block of rows sits this far lower (top margin 3.5 vs bottom 6.3 real px before: equal within 1 px now)
local FACE_SHIFT = 0.75 -- the Rarity panel's inner face centre sits this far right of its visible box centre (rim bands 13 / 12 source px at slice scale 0.5, minus the box insets 2 / 4)
local TEXT_LIFT = 0.0685 -- x text size: the label centre to the ink centre of ascender..descender text (ink -0.354 .. +0.491 em)
local MYTHIC_K = 1.14 -- the Mythic die is 1.14x the side dice (ref 204 vs 179)

local function round(n: number): number
	return math.floor(n + 0.5)
end

local K = 1 -- real px per design px under the shell's UIScales (set per build)

-- VISIBLE insets (source px: left, top, right, bottom) of each sprite inside its Ink rect: the Ink rect (alpha >= 160) still
-- contains a dark drop shadow (mostly at the bottom) and a faint outer glow. Measured on the exports as the box of opaque pixels
-- with luminance >= 110 (the rims, bodies and highlights the eye reads). Every layout number in this file is a VISIBLE size.
local INS = {
	[Bag.LeftPanel] = { 4, 2, 4, 10 },
	[Bag.Detail] = { 2, 2, 4, 8 },
	[RollSprites.HeaderPlate] = { 4, 1, 4, 7 },
	[RollSprites.RowSecret] = { 8, 3, 8, 9 },
	[RollSprites.RowMythic] = { 3, 1, 2, 6 },
	[RollSprites.RowLegendary] = { 5, 2, 2, 6 },
	[RollSprites.RowEpic] = { 3, 2, 2, 6 },
	[RollSprites.RowRare] = { 5, 2, 6, 7 },
	[RollSprites.RowCommon] = { 3, 2, 2, 7 },
	[RollSprites.PillLegendary] = { 3, 2, 4, 6 },
	[RollSprites.PillMythic] = { 4, 2, 6, 6 },
	[RollSprites.PityPill] = { 3, 3, 3, 8 },
	[RollSprites.BarTrack] = { 3, 3, 3, 4 },
	[RollSprites.BarFill] = { 3, 3, 3, 4 },
	[RollSprites.BtnGold] = { 3, 0, 1, 6 },
	[RollSprites.BtnPurple] = { 3, 1, 3, 6 },
	[RollSprites.BtnGrey] = { 3, 0, 2, 6 },
	[RollSprites.PriceChip] = { 1, 2, 2, 6 },
	[RollSprites.CrownGold] = { 4, 2, 4, 6 },
	[RollSprites.CrownSecret] = { 4, 2, 4, 6 }, -- same silhouette as CrownGold (cut from the same row)
	[RollSprites.CrownMythic] = { 4, 2, 4, 6 },
	[RollSprites.CrownEpic] = { 4, 2, 3, 6 },
	[RollSprites.StarsRare] = { 9, 6, 9, 11 },
	[RollSprites.StarCommon] = { 9, 7, 9, 11 },
	[RollSprites.Info] = { 5, 3, 5, 9 },
	[RollSprites.DieLegendary] = { 2, 2, 7, 13 },
	[RollSprites.DieMythic] = { 2, 2, 3, 9 },
	[RollSprites.Die1] = { 0, 0, 0, 0 }, -- black outline counts as visible
	[RollSprites.Dice3] = { 0, 0, 0, 0 },
}

-- Draw.apply by VISIBLE box: the sprite's visible part is visW x visH centred at (cx, cy). Sliced sprites keep their rim at
-- slice scale k (default: visible height / visible source height).
-- the pity frame on phones: the Bag panel's skin with short caps (35 design px, not 89), so its rim keeps the panels' slice scale in a 48 px frame
local PITY_FRAME = setmetatable({ Slice = Rect.new(232, 40, 473, 421) }, { __index = Bag.LeftPanel })
INS[PITY_FRAME] = { 4, 2, 4, 8 } -- short caps (35 px): the rim ends 8 source px above the ink edge (the Bag panel's skin keeps 10)

local function vis(inst, rec, cx: number, cy: number, visW: number, visH: number, k: number?, exact: Vector2?)
	local ins = INS[rec] or { 0, 0, 0, 0 }
	local l, t, r, b = ins[1], ins[2], ins[3], ins[4]
	local ink = rec.Ink
	local sx, sy
	if rec.Slice then
		k = k or visH / (ink.Height - t - b)
		-- the slice scale Draw.apply would cap to the caps: apply it here, so the ink box (and so the visible box) is the requested one
		local sl, size = rec.Slice, rec.Size
		local capX = sl.Min.X + size.X - sl.Max.X - (size.X - ink.Width) - (l + r)
		local capY = sl.Min.Y + size.Y - sl.Max.Y - (size.Y - ink.Height) - (t + b)
		if capX > 0 then
			k = math.min(k, visW / capX)
		end
		if capY > 0 then
			k = math.min(k, visH / capY)
		end
		sx, sy = k, k
	else
		sx, sy = visW / (ink.Width - l - r), visH / (ink.Height - t - b)
	end
	local inkW = visW + (l + r) * sx
	local inkH = visH + (t + b) * sy
	return Draw.apply(inst, rec, cx + (r - l) / 2 * sx, cy + (b - t) / 2 * sy, inkW, inkH, k, exact)
end

local function measure(str: string, size: number): number
	return TextService:GetTextSize(str, size * K, Enum.Font.FredokaOne, Vector2.new(1e5, 1e5)).X / K
end

local function fitSize(str: string, w: number, size: number, min: number): number
	while size > min and measure(str, size) > w do
		size -= 1
	end
	return size
end

-- One text role = one size: the largest size <= size at which every string fits w.
local function roleSize(strs: { string }, w: number, size: number, min: number): number
	for _, s in strs do
		size = fitSize(s, w, size, min)
	end
	return size
end

-- Live text in a box (ax 0 left, 0.5 centre, 1 right of x); `size` is the role size, `rich` an optional rich string.
local function label(parent, o)
	local l = Parts.text(parent, {
		Name = o.Name or "Text",
		Text = o.Rich or o.Text,
		RichText = o.Rich ~= nil,
		TextSize = o.Size,
		TextColor3 = o.Color,
		AnchorPoint = Vector2.new(o.AX or 0.5, 0.5),
		Position = if o.Exact
			then UDim2.fromScale(o.X / parent.Size.X.Offset, o.Y / parent.Size.Y.Offset) -- offsets are whole px: scales place the text at fractional ones
			else UDim2.fromOffset(round(o.X), round(o.Y)),
		Size = UDim2.fromOffset(round(o.W), round(o.Size * 1.2)),
		TextXAlignment = if o.AX == 0
			then Enum.TextXAlignment.Left
			elseif o.AX == 1 then Enum.TextXAlignment.Right
			else Enum.TextXAlignment.Center,
		ZIndex = o.Z,
	}, o.Stroke or 3)
	l.TextTruncate = Enum.TextTruncate.None
	local w = measure(o.Text, o.Size)
	if w > o.W * 0.97 then -- the role size was fitted by the caller; this only guards a squeezed box
		l.TextSize = math.max(8, math.floor(o.Size * o.W * 0.97 / w))
	end
	return l
end

local function clear(parent)
	for _, c in parent:GetChildren() do
		if not c:IsA("UIBase") then
			c:Destroy()
		end
	end
end

-- The panel at its VISIBLE rim box (x, y, w, h): the skin is drawn by visible box (slice scale 0.5 as the Bag's panels); the
-- returned frame is exactly that box (children use panel-local design px from the rim) and clips glows to it.
local function panelFrame(parent, name: string, x: number, y: number, w: number, h: number, rec, z: number, k: number?)
	local skin = Draw.img(parent, { Name = name .. "Skin", ZIndex = z })
	vis(skin, rec, x + w / 2, y + h / 2, w, h, k or 0.5)
	local holder = Draw.img(parent, {
		Name = name,
		Position = UDim2.fromOffset(round(x), round(y)),
		Size = UDim2.fromOffset(w, h),
		ZIndex = z + 1,
		ClipsDescendants = true,
	}, "Frame")
	return holder
end

local View = {}
View.__index = View

-- Layout ----------------------------------------------------------------------------------------------------

-- Layout: every number below is a VISIBLE (ink) box, in content design px (y 0 = the content top, just under the tab row).
-- Panels, plates, rows, pills, buttons, bar and icons are placed with Draw.apply (by ink), never by frame size.
local function compute(W: number, H: number, compact: boolean)
	local L = { W = W, H = H, compact = compact }
	if compact then
		L.padTop = 8 -- the scroll frame reaches this far above the content so the rule is never clipped
		L.ruleH, L.ruleY = 12, -1
		L.gap, L.btnGap, L.pad = 3.5, 3.5, 17 -- pad: >= 8 real px from the buttons to the window rim's inner face (face bottom 5.4 real px above the content bottom)
		L.plateTop, L.plateH, L.pityH, L.btnH = if W >= 700 then 13 else 8, if W >= 700 then 24 else 26, 55, 45 -- plateTop: >= 4 real px under the panel's double top rim at 844
		L.rimT, L.rimB = RIM_T_C, if W >= 700 then RIM_B_844 else RIM_B_C
		L.titleY = RIM_T_C + ROW_GAP_COMPACT + 7.15 -- the plain heading (667): >= 3 real px under the rim and above row 1 (rows start 2 real px lower), outline ~12.3 design px tall (caps 8.9 real + stroke 0.5)
		L.panelY = 4
		L.noRarPlate = W < 700 -- 667: the title can't clear the diamonds inside the row span, so it is plain outlined text
		L.panelH = math.max(150, H - L.panelY - L.pityH - L.btnH - L.gap - L.btnGap - L.pad)
		L.minText = math.max(math.ceil(14 / K), 12)
		L.sizes = {
			head = 20,
			headR = if W < 700 then 18 else 20,
			row = 18,
			pity = 18,
			count = 20,
			btn = 24,
			price = 18,
			pill = 18,
			msg = 28,
		}
		L.rowH = 20
		-- the three featured pills side by side: >= 8 px between them and >= 6 px to the panel rims
		local pillMargin = if W >= 700 then 17 else 18 -- design px to the panel box: ~6 real px to the rim's inner face
		local wide = round(measure("LEGENDARY", L.sizes.pill) + 18) -- the panel width stays what the 18 px padding gave
		L.fw = round(2 * (pillMargin + wide + 10 + wide / 2))
		L.pillW = round(measure("LEGENDARY", L.sizes.pill) + 16) -- narrower pills: the freed width goes into the gaps and the rim margins
		L.pillH = 34
		L.pillSpacing = L.pillW + 11 -- 8.8 real px between the pills
		L.fx = 2
		L.rx = L.fx + L.fw + 6
		L.rw = W - 2 - L.rx
		L.pityX, L.pityRowW = L.fx + 1, W - 4 - L.fx -- the compact skin draws ~1 real px wider each side
		local rowW = L.pityRowW
		local pillW = 104
		local barL = rowW * 0.02 + pillW + 62
		local infoX = rowW * 0.03 + pillW + 5 + round(34 * 0.7) / 2 -- 5 px ink gap from the PITY pill
		L.pity = {
			pillX = rowW * 0.03, -- = the bar's right margin
			pillW = pillW,
			pillH = 34,
			pillCy = 27.75,
			infoX = infoX,
			barL = barL,
			barW = rowW * 0.97 - barL,
			barH = 14,
			tY = 18.15, -- the text line (count shares its centre) and the bar are one group (outline top .. bar rim, 34.6 design px) centred in the inner face (7.6 .. H - 7.5; rims measured 6.1 / 6.0 real px)
			cY = 18.15,
			bY = 38.85,
			textX = 0.373,
			crown = 24,
		}
		L.btnW = math.min(250, round((W - 40) / 2))
		L.btnSpace = 40
		L.featPlateW = round(L.fw * 0.7)
		L.rowW = L.rw - (if W < 700 then 25 else 32) -- >= 6 real px to the rim's inner face (pixel scan: the rim face sits ~5 px inside the panel box); 667: 4.5-6 px, so Common name and percent keep >= 8 px
		L.rarPlateW = if L.noRarPlate then L.rowW + 2 * 18 else L.rowW - 6 -- the plate stays inside the row span (reference: plate 290 in rows 296)
		L.rowIcon, L.rowNameX, L.rowNameW, L.rowPctW =
			if W < 700 then 0.1066 else 0.1, if W < 700 then 0.2267 else 0.205, 0.6, 0.5 -- phones: name and percent share the narrow row (667: icon column 14.2 real px, names at 30: Rare stars (0.9x) 2 px inside the row cap and >= 3 px from the name)
		L.plateClear = 2 * 18 -- both plate ends (diamond + bevel) at plateH 28
	else
		L.padTop = 12 -- the scroll frame reaches this far above the content top, so the rule can sit just under the tabs
		L.ruleH = 32 -- the diamond (ink) height; the line is ~2.5 px at this scale (drawn twice: brighter)
		L.ruleY = 4 -- rule centre: ~15 below the tab row's visible bottom (content y -11); the diamond just clears the tabs
		L.gap, L.btnGap, L.pad = 10, 14, 14 -- panel -> pity reads 12 visible (the bottom rim sits 2 px inside)
		L.plateTop, L.plateH, L.pillH, L.pityH, L.btnH = 16, 46, 53, 88, 86 -- plateTop: ~7 px under the panel's top rim
		L.panelY = L.ruleY + 11 -- rule line -> panel rim 12 visible
		-- every spare design px goes into the panels
		L.panelH = H - L.panelY - L.gap - L.pityH - L.btnGap - L.btnH - L.pad
		L.minText = 14
		-- one size per text role; FredokaOne caps are 0.58 x TextSize (measured) and match the reference caps
		L.sizes = { head = 34, headR = 32, row = 28, pity = 27, count = 34, btn = 37, price = 28, pill = 33, msg = 40 }
		L.rowH = 33 -- visible row height at most; the room left by the plate and the rim is shared evenly
		-- the Bag's panel boxes (left box x + 1, width + 2, detail box right after it) inset by their 2.5 px sprite margin
		local leftW = round((W - 3) * 0.696)
		L.fx, L.fw = 3, leftW + 1 - 3
		L.rx = leftW + 10 -- the Bag's rim-to-rim gap between its two panels is 9 px (pixel scan of build_bag_1672)
		L.rw = W - 2 - L.rx
		-- the pity frame spans both panels' outer rims (the gold rule's span)
		L.pityX = L.fx
		L.pityRowW = W - 2 - L.fx
		local sx = L.pityRowW / 1099 -- the reference row is 1099 wide
		L.pity = {
			pillX = 62 * sx, -- = the bar's right margin (1099 - 290 - 747)
			pillW = 157,
			pillH = 51,
			pillCy = 44.4,
			infoX = 62 * sx + 157 + 5 + round(51 * 0.7) / 2, -- 5 px ink gap from the PITY pill
			barL = 290 * sx,
			barW = 747 * sx,
			barH = 30,
			tY = 25.3, -- group (outline top .. bar rim) centred in the inner face (7.5 .. H - 6.8)
			cY = 25.3,
			bY = 59.3,
			textX = (569 - 290) / 747,
			crown = 44,
		}
		L.btnW = 300
		L.btnSpace = 76
		L.featPlateW = round(L.fw * 0.45)
		L.rowW = round(296 * L.rw / 346)
		L.rarPlateW = L.rowW - 6 -- inside the row span (reference: plate 290 in rows 296)
		L.rowIcon, L.rowNameX, L.rowNameW, L.rowPctW = 0.142, 0.267, 0.5, 0.3
		L.plateClear = 2 * 46 -- plate end -> diamond -> text clearance (reference ~11 px)
	end
	-- six identical visible rows: as tall as fits with the minimum gap above, between and below them
	L.rimB = L.rimB or RIM_B
	L.rowsTop = if L.noRarPlate
		then L.rimT
			+ 2 * ROW_GAP_COMPACT
			+ 12.4 -- 667: the heading strip is 3.75 design px (3 real) deeper than the plain 3 + 3 px gaps
		else L.plateTop + L.plateH + (if L.compact and W >= 700 then ROWS_DROP_844 else 0)
	local gapMin = if compact then ROW_GAP_COMPACT else ROW_GAP_MIN
	local fitH = (L.panelH - L.rimB - L.rowsTop - 7 * gapMin) / 6
	L.rowH = math.max(12, math.min(L.rowH, if compact then fitH else math.floor(fitH))) -- phones: whole real px are snapped in _drawRarity
	L.sizes.row = math.min(L.sizes.row, math.floor((L.rowH - 3) / 0.58)) -- caps (0.58 x size) keep >= 1.5 px inside the row
	L.total = L.panelY + L.panelH + L.gap + L.pityH + L.btnGap + L.btnH + L.pad
	return L
end

-- The gold rule: the same DividerGold in six ImageRect pieces so only the plain line stretches; the tapered ends and the
-- centre diamond keep their native scale k (the Quest Log draws it ~330 wide, k ~ 0.47).
local function rule(parent, W: number, y: number, h: number, z: number)
	local rec = Bag.DividerGold
	local k = h / rec.Ink.Height
	local half = math.floor(rec.Size.X / 2)
	local cx = W / 2
	local function piece(name: string, x0: number, w: number, srcX: number, srcW: number)
		local img = Draw.img(parent, { Name = name, ZIndex = z })
		img.Image = rec.Image
		img.ImageRectOffset = Vector2.new(srcX, 0)
		img.ImageRectSize = Vector2.new(srcW, rec.Size.Y)
		img.ScaleType = Enum.ScaleType.Stretch
		img.AnchorPoint = Vector2.new(0, 0.5)
		img.Position = UDim2.fromOffset(round(x0), round(y))
		img.Size = UDim2.fromOffset(math.ceil(w), rec.Size.Y * k)
	end
	local tip, mid, knob = 150, 150, half - 300 -- source widths: taper, plain line, knob + half diamond
	local tipW, knobW = tip * k, knob * k
	local lineW = cx - tipW - knobW
	piece("TipL", 0, tipW, 0, tip)
	piece("LineL", tipW, lineW, tip, mid)
	piece("KnobL", cx - knobW, knobW, tip + mid, knob)
	piece("KnobR", cx, knobW, half + 1, knob)
	piece("LineR", cx + knobW, lineW, half + 1 + knob, mid)
	piece("TipR", W - tipW, tipW, half + 1 + knob + mid, tip)
end

-- Soft radial glow centred at (cx, cy), diameter d.
local function glow(parent, cx: number, cy: number, d: number, color: Color3, transparency: number, z: number)
	local g = Draw.img(parent, { Name = "Glow", ZIndex = z })
	Draw.apply(g, Q.GlowRadial, cx, cy, d, d)
	g.ImageColor3 = color
	g.ImageTransparency = transparency
	return g
end

-- Build -----------------------------------------------------------------------------------------------------

local DIE_CX = { 0.216, 0.512, 0.807 } -- reference die centres (fractions of the featured panel width)

function View:_drawFeatured(L, z, Pw: number, Ph: number)
	local panel = panelFrame(self._canvas, "Featured", L.fx, L.panelY, Pw, Ph, Bag.LeftPanel, z)
	local s = L.sizes
	-- header plate + live title
	local plate = Draw.img(panel, { Name = "Plate", ZIndex = z + 1 })
	local plateW = L.featPlateW
	vis(plate, RollSprites.HeaderPlate, Pw / 2, L.plateTop + L.plateH / 2, plateW, L.plateH)
	label(panel, {
		Name = "Title",
		Text = self._featuredTitle,
		Size = self._headF,
		X = Pw / 2,
		Y = L.plateTop + L.plateH / 2,
		W = plateW - L.plateClear,
		Z = z + 2,
	})
	local top = L.plateTop + L.plateH + 6
	local pillBot = if L.compact then 20 else 34 -- compact: >= 8 real px from the Mythic pill to the rim's inner face; full: reference pill bottom 315 of a 349 panel
	local pillTop = Ph - pillBot - L.pillH
	local dropM = if L.compact then 2 else 8
	local dy = if L.compact then 0 else Ph / 2 - 170.5 -- the dice + pills group (Mythic die top 75 .. Mythic pill bottom 321, reference) is centred between the plate and the rim
	local sideW, mythW
	if L.compact then
		sideW = math.min(0.26 * Pw, L.pillSpacing * 0.9, (pillTop + dropM + 8 - top) / 1.1)
		mythW = sideW * MYTHIC_K
	else
		sideW, mythW = 179, 204 -- reference ink widths
	end
	local f = self._featuredIds
	for i = 1, 3 do
		local item = f[i]
		if item == nil then
			continue -- an empty slot (a single roll result sits in the middle)
		end
		local cx = if L.compact then Pw / 2 + (i - 2) * L.pillSpacing else Pw * DIE_CX[i]
		local rarity = item.Rarity
		local mythic = rarity == "Mythic"
		local rec = RollSprites[if mythic then "DieMythic" else "DieLegendary"]
		local w, h = Draw.fitIn(rec, if mythic then mythW else sideW, 1e5)
		local pillH = if L.compact then L.pillH else (if mythic then 51 else 53)
		local pillCy = if L.compact
			then pillTop + L.pillH / 2 + (if mythic then dropM else 0)
			else (if mythic then 295.5 else 288.5) + dy
		local bottom = if L.compact
			then pillCy - pillH / 2 + (if mythic then 8 else 10)
			else (if mythic then 270 else 268) + dy
		-- the reference: a concentrated pink halo (radius ~100) behind the Mythic, a subtle warm orange behind the Legendaries
		local gd = math.max(w, h)
		local gcy = bottom - h / 2
		if mythic then -- bright, concentrated: radius ~100 around the die centre, no wide wash
			for _, d in { 1.9, 1.7, 1.5, 1.5, 1.3, 1.3, 1.1, 1.1, 0.9 } do
				glow(panel, cx, gcy, gd * d, Color3.fromRGB(235, 10, 105), 0, z + 1)
			end
		else -- orange ~15 px beyond the die's ink
			for _, d in { 0, 0, 0, -20, -20 } do
				glow(panel, cx, gcy, gd + 60 + d, Color3.fromRGB(255, 130, 20), 0, z + 1)
			end
		end
		-- the die's own art (Sprites.DieArt, else the roll glyph tinted with its colour, as the Bag DICE tab), fitted in the
		-- box the rarity art sizes
		local die = Draw.img(panel, { Name = "Die", ZIndex = z + 2 })
		local art, tint = QuestLogic.dieArt(item.Id)
		Draw.icon(die, art, cx, bottom - h / 2, w, h)
		die.ImageColor3 = tint or Color3.new(1, 1, 1)
		local pillRec = if mythic then RollSprites.PillMythic else RollSprites.PillLegendary
		local word = string.upper(item.Name or rarity)
		local pillW = if L.compact then L.pillW else (if mythic then 159 else 172)
		local pillPad = if L.compact then 12 else 14 -- label width = pill width - pad
		local bgp = Draw.img(panel, { Name = "RarityPill", ZIndex = z + 3 })
		vis(bgp, pillRec, cx, pillCy, pillW, pillH)
		label(panel, {
			Name = "Label",
			Text = word,
			Size = fitSize(word, pillW - pillPad, s.pill, L.minText),
			X = cx,
			Y = pillCy,
			W = pillW - pillPad,
			Z = z + 4,
			Stroke = 2,
		})
	end
end

function View:_drawRarity(L, z, Pw: number, Ph: number)
	local panel = panelFrame(self._canvas, "Rarity", L.rx, L.panelY, Pw, Ph, Bag.Detail, z)
	local plateW = L.rarPlateW
	if not L.noRarPlate then
		local plate = Draw.img(panel, { Name = "Plate", ZIndex = z + 1 })
		vis(plate, RollSprites.HeaderPlate, Pw / 2, L.plateTop + L.plateH / 2, plateW, L.plateH)
	end
	label(panel, {
		Name = "Title",
		Text = string.upper("Rarity Chances"),
		Stroke = if L.noRarPlate then 0.5 else nil, -- 0.5: the cap-height outline leaves >= 3 real px to the rim and to row 1 (the strip is 16.8 real px)
		Size = self._headR,
		X = Pw / 2,
		Y = if L.noRarPlate then L.titleY else L.plateTop + L.plateH / 2, -- plain title: in its own strip above the rows
		W = plateW - L.plateClear,
		Z = z + 2,
	})
	-- six rows: one visible height and ONE slice scale (equal outline weight). Rows are laid out in whole REAL px (the canvas'
	-- absolute origin is read back): identical heights, gaps differing by at most 1 px with equal top / bottom margins, and the
	-- block centred on the panel's inner face
	local canvas = self._canvas
	local baseX, baseY = canvas.AbsolutePosition.X, canvas.AbsolutePosition.Y
	local r0 = round(baseY + (L.panelY + L.rowsTop) * K)
	local r1 = if L.compact
		then math.floor(baseY + (L.panelY + Ph - L.rimB) * K)
		else round(baseY + (L.panelY + Ph - L.rimB) * K)
	local gMin = if L.compact then ROW_GAP_REAL else ROW_GAP_MIN * K
	local gEdge = if L.compact then 0 else math.ceil(ROW_EDGE_MIN * K) -- desktop: the least real px between the plate / rim and the rows
	local hr = math.min(math.floor(L.rowH * K), math.floor((r1 - r0 - 5 * gMin - 2 * gEdge) / 6)) -- real px
	local hMin = math.ceil(12 * K) -- compute()'s row floor
	if not L.compact and hr < hMin then -- short desktop window: the desktop margins give way to the phone minimums, never the rows
		gMin, gEdge = ROW_GAP_REAL, ROW_GAP_REAL
		hr = math.max(hMin, math.min(math.floor(L.rowH * K), math.floor((r1 - r0 - 7 * ROW_GAP_REAL) / 6)))
	end
	local free = r1 - r0 - 6 * hr
	local g = math.floor(free / 7)
	local gaps = { g, g, g, g, g, g, g }
	if g < gEdge or (L.compact and L.W >= 700) then -- tight: the rows keep their least gap, the plate / rim margins take the rest
		local gi = if L.compact then ROW_GAP_REAL else math.floor((free - 2 * gEdge) / 5)
		local e = free - 5 * gi
		gaps = { math.ceil(e / 2), gi, gi, gi, gi, gi, math.floor(e / 2) }
	else
		local rem = free - 7 * g
		for i = 1, 3 do -- the remainder pixels go to the outer pairs first, an odd one to the middle gap
			if rem >= 2 then
				gaps[i] += 1
				gaps[8 - i] += 1
				rem -= 2
			end
		end
		if rem == 1 then
			gaps[4] += 1
		end
	end
	local rowH = hr / K -- design px (snapped to whole real px)
	local rowK = rowH / 68 -- the rows' visible source heights are 62-73 px
	local rowWr = round(L.rowW * K)
	local faceCx = baseX + (L.rx + Pw / 2 + FACE_SHIFT) * K
	local leftR = round(faceCx - rowWr / 2)
	local rowW = rowWr / K
	local cxRow = (leftR + rowWr / 2 - baseX) / K - L.rx -- row centre, panel-local design px
	local inset = cxRow - rowW / 2
	local nameW, pctW = rowW * L.rowNameW, rowW * L.rowPctW
	local topR = r0
	local lift = if L.compact then TEXT_LIFT * self._rowSize else 0
	local stroke = if not L.compact then 2.5 elseif L.noRarPlate then 1 else 1.5
	local pctPad = if not L.compact then 5 elseif L.noRarPlate then 3.4 else 9 -- phones: inside the row's rounded end
	for i, row in self._rows do
		topR += gaps[i]
		local cy = (topR + hr / 2 - baseY) / K - L.panelY
		topR += hr
		local bg = Draw.img(panel, { Name = "Row_" .. row.Rarity, ZIndex = z + 1 })
		vis(bg, ROW_ART[row.Rarity] or RollSprites.RowCommon, cxRow, cy, rowW, rowH, rowK, Vector2.new(Pw, Ph))
		local icon = Draw.img(panel, { Name = "Icon", ZIndex = z + 2 })
		local rec = ROW_ICON[row.Rarity] or RollSprites.CrownGold
		local box = ICON_BOX[row.Rarity] or CROWN_BOX
		local f = if L.compact then rowH * 0.9 / 25 * (if L.noRarPlate and row.Rarity == "Rare" then 0.9 else 1) else 1
		local boxW, boxH = box[1] * f, box[2] * f
		-- ink-fitted into the box (width first), centred on the icon column
		local ins = INS[rec]
		local vw, vh = rec.Ink.Width - ins[1] - ins[3], rec.Ink.Height - ins[2] - ins[4]
		local iw = math.min(boxW, boxH * vw / vh)
		local ih = iw * vh / vw
		vis(icon, rec, inset + rowW * L.rowIcon, cy, iw, ih)
		label(panel, {
			Name = "Name",
			Text = row.Rarity,
			Size = self._rowSize,
			AX = 0,
			X = inset + rowW * L.rowNameX,
			Y = cy - lift,
			Exact = true,
			W = nameW,
			Z = z + 2,
			Stroke = stroke,
		})
		label(panel, {
			Name = "Pct",
			Text = row.Text,
			Size = self._rowSize,
			AX = 1,
			X = inset + rowW - pctPad,
			Y = cy - lift,
			Exact = true,
			W = pctW,
			Z = z + 2,
			Stroke = stroke,
		})
	end
end

function View:_drawPity(L, z, y: number)
	local H = L.pityH
	local P = L.pity
	local rowW = L.pityRowW
	local s = L.sizes
	local x0 = L.pityX
	panelFrame(self._canvas, "Pity", x0, y, rowW, H, if L.compact then PITY_FRAME else Bag.LeftPanel, z)
	local pity = self._pity
	local pillCx, pillCy = x0 + P.pillX + P.pillW / 2, y + P.pillCy
	local pillBg = Draw.img(self._canvas, { Name = "PityPill", ZIndex = z + 1 })
	vis(pillBg, RollSprites.PityPill, pillCx, pillCy, P.pillW, P.pillH)
	-- crown (~44 wide) + live "PITY", centred as one group
	local cw = P.crown
	local ch = cw * 123 / 201 -- visible crown 201 x 123 source px
	local word = "PITY"
	local tw = measure(word, s.pill)
	local gx = pillCx - (cw + 8 + tw) / 2
	local crown = Draw.img(self._canvas, { Name = "Crown", ZIndex = z + 2 })
	vis(crown, RollSprites.CrownGold, gx + cw / 2, pillCy, cw, ch)
	label(self._canvas, {
		Name = "Label",
		Text = word,
		Size = s.pill,
		AX = 0,
		X = gx + cw + 8,
		Y = pillCy,
		W = tw + 6,
		Z = z + 2,
		Stroke = 2,
	})
	-- info button: >= 44 real px hit area, art ~0.7x the PITY pill's visible height
	local hs = math.ceil(44 / K)
	local ia = round(P.pillH * 0.7)
	local hit = make("ImageButton", {
		Name = "Info",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(x0 + P.infoX), round(pillCy)),
		Size = UDim2.fromOffset(hs, hs),
		ZIndex = z + 1,
	}, self._canvas)
	local art =
		Draw.img(hit, { Name = "Art", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	vis(art, RollSprites.Info, hs / 2, hs / 2, ia, ia)
	Parts.interact(hit)
	table.insert(
		self._connsBuild,
		hit.Activated:Connect(function()
			if self._onInfo then
				self._onInfo()
			end
		end)
	)
	local barL = x0 + P.barL
	local barW = P.barW
	local barCx, barCy = barL + barW / 2, y + P.bY
	local track = Draw.img(self._canvas, { Name = "PityBar", ZIndex = z + 1 })
	vis(track, RollSprites.BarTrack, barCx, barCy, barW, P.barH)
	-- fill: inside the track, never narrower than its two caps; hidden at 0
	local frac = self._pityFraction
	if frac > 0 then
		local fr = RollSprites.BarFill
		local fillH = P.barH - 4
		local fk = fillH / (fr.Ink.Height - 7)
		local minW = (fr.Slice.Min.X + fr.Size.X - fr.Slice.Max.X - (fr.Size.X - fr.Ink.Width) - 6) * fk
		local fw = math.max(minW, (barW - 4) * frac)
		local fill = Draw.img(self._canvas, { Name = "PityFill", ZIndex = z + 2 })
		vis(fill, fr, barL + 2 + fw / 2, barCy, fw, fillH)
	end
	if pity then
		local color = Parts.RarityColor[pity.Rarity] or Color3.new(1, 1, 1)
		local plain = `Guaranteed {pity.Rarity} in {pity.Max} rolls!`
		label(self._canvas, {
			Name = "PityText",
			Text = plain,
			Rich = `Guaranteed <font color="#{color:ToHex()}">{pity.Rarity}</font> in {pity.Max} rolls!`,
			Size = self._pitySize,
			X = barL + barW * P.textX,
			Y = y + P.tY,
			Exact = true,
			W = barW * 0.7,
			Z = z + 2,
			Stroke = if L.compact then 1.5 else 2,
		})
		label(self._canvas, {
			Name = "Count",
			Text = RollLogic.pityText(pity.Count, pity.Max),
			Rich = `<font color="{YELLOW}">{pity.Count} /</font> {pity.Max}`, -- reference: the count and the slash are yellow
			Size = self._countSize,
			AX = 1,
			X = barL + barW + 0.03 * self._countSize, -- the digits' ink ends on the bar's right end (right bearing ~0.03 em)
			Y = y + P.cY,
			Exact = true,
			W = barW * 0.22,
			Z = z + 2,
			Stroke = if L.compact then 1.5 else nil,
		})
	end
end

function View:_drawButtons(L, z, y: number)
	local gap = L.btnSpace
	local bw, bh = L.btnW, L.btnH
	local defs = {
		{ Art = RollSprites.BtnGold, Dice = 1, X = L.W / 2 - gap / 2 - bw / 2 },
		{ Art = RollSprites.BtnPurple, Dice = 3, X = L.W / 2 + gap / 2 + bw / 2 },
	}
	local btnState = self._buttonState
	for i, d in defs do
		local st = btnState[i] or { Count = if i == 1 then 1 else 10, Price = 0, Enabled = false }
		-- disabled: the grey button art with its normal white label (legible), no glow
		local art = if st.Enabled then d.Art else RollSprites.BtnGrey
		local btn = Draw.img(self._canvas, { Name = "Roll" .. st.Count, ZIndex = z }, "ImageButton")
		vis(btn, art, d.X, y + bh / 2, bw, bh)
		Parts.interact(btn) -- hover / press scale and the gamepad focus rim
		local k = btn.SliceScale
		local ins = INS[art]
		-- origin of the VISIBLE box inside the button frame
		local ox, oy = (art.Ink.Min.X + ins[1]) * k, (art.Ink.Min.Y + ins[2]) * k
		-- dice icon over a soft glow: ROLL 1 die ~56 x 60 and the ROLL 10 cluster ~80 x 73 visible (reference), centred 73 px in
		local sc = math.min(bw / 300, bh / 86)
		local dieCx, dieCy = ox + 73 * sc, oy + bh / 2
		if st.Enabled then
			-- a burst on the face behind the dice: a CanvasGroup the size of the pill face (full-radius UICorner, 3 px inside the outline)
			local inset = 3
			local gw, gh = bw - 2 * inset, bh - 2 * inset
			local group = make("CanvasGroup", {
				Name = "GlowFace",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(round(ox + inset), round(oy + inset)),
				Size = UDim2.fromOffset(round(gw), round(gh)),
				ZIndex = z + 1,
				ClipsDescendants = true,
			}, btn)
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, group)
			local dieW, dieH = if d.Dice == 1 then 56 * sc else 80 * sc, if d.Dice == 1 then 60 * sc else 73 * sc
			local gx, gy = dieCx - ox - inset, dieCy - oy - inset
			local warm = d.Dice == 1
			-- wide ellipses inside the face (never taller than it): a soft wash, a ray burst ~1.3x the die, a bright near-white core
			local eh = gh - 2
			local function ellipse(rec, w, color, transparency)
				local g = Draw.img(group, { Name = "Glow", ZIndex = z + 1 })
				Draw.apply(g, rec, gx, gy, math.min(w, 2 * (gx - 1), 2 * (gw - gx - 1)), eh) -- inside the group on both sides
				g.ImageColor3 = color
				g.ImageTransparency = transparency
			end
			local wash = if warm then Color3.fromRGB(255, 235, 120) else Color3.fromRGB(255, 120, 255)
			ellipse(Q.GlowRadial, dieW * 3.4, wash, 0.1)
			ellipse(Q.GlowRadial, dieW * 2.4, wash, 0.1)
			ellipse(
				Q.RaysBurst,
				math.max(dieW, dieH) * 2.6,
				if warm then Color3.fromRGB(255, 245, 170) else Color3.fromRGB(255, 160, 255),
				0
			)
			ellipse(
				Q.GlowRadial,
				dieW * 1.7,
				if warm then Color3.fromRGB(255, 255, 240) else Color3.fromRGB(255, 225, 255),
				0.1
			)
		end
		local img = Draw.img(btn, { Name = "Dice", ZIndex = z + 3 })
		if d.Dice == 1 then
			vis(img, RollSprites.Die1, dieCx, dieCy, 56 * sc, 60 * sc)
		else
			vis(img, RollSprites.Dice3, dieCx, dieCy, 80 * sc, 73 * sc)
		end
		-- label above, price chip below
		local cx = ox + bw * 0.64
		label(btn, {
			Name = "Label",
			Text = `ROLL {st.Count}`,
			Size = self._btnSize,
			X = cx,
			Y = oy + bh * 0.285,
			W = bw * 0.46,
			Z = z + 2,
		})
		local chipW, chipH = bw * 0.45, 31 * bh / 86
		local chipCy = oy + bh * 0.705
		local chip = Draw.img(btn, { Name = "Chip", ZIndex = z + 1 })
		vis(chip, RollSprites.PriceChip, cx, chipCy, chipW, chipH)
		local gemS = chipH * 0.8
		local priceText = `x{st.Price}`
		local tw = measure(priceText, self._priceSize)
		local gx = cx - (gemS + 6 + tw) / 2
		local gem = Draw.img(btn, { Name = "Gem", Image = Sprites.Gem, ZIndex = z + 2 })
		gem.AnchorPoint = Vector2.new(0, 0.5)
		gem.Position = UDim2.fromOffset(round(gx), round(chipCy))
		gem.Size = UDim2.fromOffset(round(gemS), round(gemS))
		gem.ScaleType = Enum.ScaleType.Fit
		label(btn, {
			Name = "Price",
			Text = priceText,
			Size = self._priceSize,
			AX = 0,
			X = gx + gemS + 6,
			Y = chipCy,
			W = tw + 4,
			Z = z + 2,
			Stroke = 2,
		})
		btn:SetAttribute("Enabled", st.Enabled)
		table.insert(
			self._connsBuild,
			btn.Activated:Connect(function()
				if self._onRoll then
					self._onRoll(st.Count)
				end
			end)
		)
	end
end

function View:_build()
	local L = self._L
	if not L or not self._canvas.Parent then
		return
	end
	for _, c in self._connsBuild do
		c:Disconnect()
	end
	table.clear(self._connsBuild)
	clear(self._canvas)
	local z = self._canvas.ZIndex + 1
	local s = L.sizes
	local W = L.W
	if L.ruleH > 0 then
		rule(self._canvas, W, L.ruleY, L.ruleH, z)
		rule(self._canvas, W, L.ruleY, L.ruleH, z) -- twice: a brighter, fuller line
	end
	if self._pool == "Event" then
		local ew, eh = W - 5, L.H - L.panelY - L.pad
		-- slice scale 0.75 (rim ~3.8 px): the tall panel stretches the cap's middle band ~2x, not ~4x (which streaked)
		local panel =
			panelFrame(self._canvas, "Empty", 3, L.panelY, ew, eh, Bag.LeftPanel, z, if L.compact then 0.6 else 0.75)
		local msg = "No event right now"
		label(panel, {
			Name = "Message",
			Text = msg,
			Size = fitSize(msg, ew - 80, s.msg, L.minText),
			X = ew / 2,
			Y = eh / 2,
			W = ew - 80,
			Z = z + 2,
			Stroke = 3,
		})
		self._scroll.CanvasSize = UDim2.fromOffset(0, 0)
		return
	end
	-- text roles (one size each, fitted to every member)
	local rowNames, pcts = {}, {}
	for _, r in self._rows do
		table.insert(rowNames, r.Rarity)
		table.insert(pcts, r.Text)
	end
	local rowW = L.rowW
	self._rowSize = math.min(
		roleSize(rowNames, rowW * L.rowNameW, s.row, L.minText),
		roleSize(pcts, rowW * L.rowPctW, s.row, L.minText)
	)
	-- the plate titles: the reference sizes differ (FEATURED cap 20, RARITY cap 18), each fitted inside its own plate
	self._headF = fitSize(self._featuredTitle, L.featPlateW - L.plateClear, s.head, L.minText)
	self._headR = fitSize("RARITY CHANCES", L.rarPlateW - L.plateClear, s.headR, L.minText)
	local pity = self._pity
	local barW = L.pity.barW
	self._pitySize, self._countSize = s.pity, s.count
	if pity then
		self._pitySize = fitSize(`Guaranteed {pity.Rarity} in {pity.Max} rolls!`, barW * 0.7, s.pity, L.minText)
		self._countSize = fitSize(RollLogic.pityText(pity.Count, pity.Max), barW * 0.22, s.count, L.minText)
	end
	self._pityFraction = if pity then RollLogic.pityFraction(pity.Count, pity.Max) else 0
	local labels, prices = {}, {}
	for _, b in self._buttonState do
		table.insert(labels, `ROLL {b.Count}`)
		table.insert(prices, `x{b.Price}`)
	end
	self._btnSize = roleSize(labels, L.btnW * 0.46, s.btn, L.minText)
	self._priceSize = roleSize(prices, L.btnW * 0.45 * 0.6, s.price, L.minText)

	local Ph = L.panelH
	self:_drawFeatured(L, z, L.fw, Ph)
	self:_drawRarity(L, z, L.rw, Ph)
	local y = L.panelY + Ph + L.gap
	self:_drawPity(L, z, y)
	y += L.pityH + L.btnGap
	self:_drawButtons(L, z, y)
	self._scroll.CanvasSize = UDim2.fromOffset(0, math.max(L.H, L.total) + L.padTop)
end

-- Public ----------------------------------------------------------------------------------------------------

function View.new(slot)
	local self = setmetatable({}, View)
	self._conns, self._connsBuild = {}, {}
	self._pool = "Standard"
	self._featuredIds, self._featuredTitle, self._rows, self._pity = {}, "FEATURED DICE", {}, nil
	self._buttonState = {}
	local scroll = make("ScrollingFrame", {
		Name = "RollView",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		ScrollBarImageTransparency = 1,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		Size = UDim2.fromScale(1, 1),
		ZIndex = slot.ZIndex + 1,
	}, slot)
	local canvas = make(
		"Frame",
		{ Name = "Canvas", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = scroll.ZIndex },
		scroll
	)
	self._scroll, self._canvas = scroll, canvas
	local pending = false
	local scaleSeen = {}
	local function rebuild()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if not scroll.Parent then
				return
			end
			local w, h = slot.Size.X.Offset, slot.Size.Y.Offset
			if w <= 0 or h <= 0 then
				return
			end
			local k = 1
			local a = slot
			while a and a.Name ~= "Root" do -- real px per design px: every UIScale above the slot except the open animation's Pop
				for _, c in a:GetChildren() do
					if c:IsA("UIScale") and c.Name ~= "Pop" then
						k *= c.Scale
						if not scaleSeen[c] then -- a later scale change (window resize) must rebuild: K sizes the hit boxes
							scaleSeen[c] = true
							table.insert(self._conns, c:GetPropertyChangedSignal("Scale"):Connect(rebuild))
						end
					end
				end
				a = a.Parent
			end
			K = k
			local L = compute(w, h, slot:GetAttribute("Compact") == true)
			canvas.Size = UDim2.fromOffset(w, math.max(h, L.total))
			canvas.Position = UDim2.fromOffset(0, L.padTop)
			scroll.Position = UDim2.fromOffset(0, -L.padTop)
			scroll.Size = UDim2.new(1, 0, 1, L.padTop)
			self._L = L
			self:_build()
		end)
	end
	self._rebuild = rebuild
	table.insert(self._conns, slot:GetPropertyChangedSignal("Size"):Connect(rebuild))
	table.insert(self._conns, slot:GetAttributeChangedSignal("Compact"):Connect(rebuild))
	rebuild()
	return self
end

function View:SetPool(pool: string)
	self._pool = pool
	self._rebuild()
end

function View:SetFeatured(list, title: string?)
	self._featuredIds = list
	self._featuredTitle = title or "FEATURED DICE"
	self._rebuild()
end

function View:SetOdds(rows)
	self._rows = rows
	self._rebuild()
end

function View:SetPity(pity)
	self._pity = pity
	self._rebuild()
end

function View:SetButtons(list)
	self._buttonState = list
	self._rebuild()
end

function View:OnRoll(cb)
	self._onRoll = cb
end

function View:OnInfo(cb)
	self._onInfo = cb
end

function View:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	for _, c in self._connsBuild do
		c:Disconnect()
	end
	table.clear(self._conns)
	table.clear(self._connsBuild)
	self._scroll:Destroy()
end

return View
