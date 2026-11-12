-- Roll menu view: featured dice | rarity chances, pity row and the two ROLL buttons, drawn inside the shared shell's content slot.
-- Visual only: no NetClient, no game data. Design px under the shell's UIScale; the slot's Size offset and "Compact" attribute pick the layout.
-- View.new(slot) -> :SetPool("Standard"|"Event") :SetFeatured({ {Id, Rarity} x3 }) :SetOdds(RollLogic.oddsRows) :SetPity({Count, Max, Rarity})
--   :SetButtons({ {Count, Price, Enabled} x2 }) :OnRoll(cb(count)) :OnInfo(cb()) :Destroy()
-- Setters only store state; one deferred rebuild draws it (also on every slot size / Compact change).
-- Compact (phones): the same stack with smaller dice and rows inside one ScrollingFrame (it scrolls only when the stack is taller).

local TextService = game:GetService("TextService")

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Bag.Parts)
local Draw = require(script.Parent.Parent.QuestLog.Draw)
local Sprites = require(script.Parent.Parent.Sprites)
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
	Secret = RollSprites.CrownGold,
	Mythic = RollSprites.CrownGold,
	Legendary = RollSprites.CrownGold,
	Epic = RollSprites.CrownEpic,
	Rare = RollSprites.StarsRare,
	Common = RollSprites.StarCommon,
}
local ICON_W = { Rare = 46, Common = 23 } -- desktop icon box widths (scaled with the 34 px bar); the crowns (Epic too) share the 38 x 24 box
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
local function vis(inst, rec, cx: number, cy: number, visW: number, visH: number, k: number?)
	local ins = INS[rec] or { 0, 0, 0, 0 }
	local l, t, r, b = ins[1], ins[2], ins[3], ins[4]
	local ink = rec.Ink
	local sx, sy
	if rec.Slice then
		k = k or visH / (ink.Height - t - b)
		sx, sy = k, k
	else
		sx, sy = visW / (ink.Width - l - r), visH / (ink.Height - t - b)
	end
	local inkW = visW + (l + r) * sx
	local inkH = visH + (t + b) * sy
	return Draw.apply(inst, rec, cx + (r - l) / 2 * sx, cy + (b - t) / 2 * sy, inkW, inkH, k)
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
		Position = UDim2.fromOffset(round(o.X), round(o.Y)),
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
		L.gap, L.btnGap, L.pad = 4, 6, 19 -- pad: >= 8 real px from the buttons to the window rim's inner face
		L.plateTop, L.plateH, L.pityH, L.btnH = if W >= 700 then 13 else 8, if W >= 700 then 24 else 26, 44, 56 -- plateTop: >= 4 real px under the panel's double top rim at 844
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
		L.rowH, L.rowGapTop, L.rowBot = 15, 5, 8
		-- the bar is as tall as the room allows once the five gaps keep >= 5 design (4 real) px between the INK edges (the outline + glow add ~3.5 design to the visible-box height)
		local rowsTop = if L.noRarPlate then L.plateTop + 22 else L.plateTop + L.plateH + L.rowGapTop
		L.rowH = math.clamp(math.round((L.panelH - rowsTop - L.rowBot - 42.5) / 6), 12, 20)
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
		L.pityX, L.pityRowW = 4, W - 8
		local rowW = L.pityRowW
		local pillW = 104
		local barL = rowW * 0.02 + pillW + 62
		local infoX = rowW * 0.02 + pillW + 5 + round(34 * 0.7) / 2 -- 5 px ink gap from the PITY pill
		L.pity = {
			pillX = rowW * 0.02,
			pillW = pillW,
			pillH = 34,
			pillCy = 22,
			infoX = infoX,
			barL = barL,
			barW = rowW * 0.97 - barL,
			barH = 18,
			tY = 11,
			cY = 11,
			bY = 30,
			textX = 0.373,
			crown = 24,
		}
		L.btnW = math.min(250, round((W - 40) / 2))
		L.btnSpace = 40
		L.featPlateW = round(L.fw * 0.7)
		L.rowW = L.rw - 32 -- >= 6 real px to the rim's inner face (pixel scan: the rim face sits ~5 px inside the panel box)
		L.rarPlateW = if L.noRarPlate then L.rowW + 2 * 18 else L.rowW - 6 -- the plate stays inside the row span (reference: plate 290 in rows 296)
		L.rowIcon, L.rowNameX, L.rowNameW, L.rowPctW = 0.1, 0.205, 0.6, 0.5 -- phones: name and percent share the narrow row
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
		L.rowH, L.rowGapTop, L.rowBot = 33, 6, 6 -- ink height; rows spread evenly, the visible-edge gap is ~17 (outline + glow included)
		-- the Bag's panel boxes (left box x + 1, width + 2, detail box right after it) inset by their 2.5 px sprite margin
		local leftW = round((W - 3) * 0.696)
		L.fx, L.fw = 3, leftW + 1 - 3
		L.rx = leftW + 10 -- the Bag's rim-to-rim gap between its two panels is 9 px (pixel scan of build_bag_1672)
		L.rw = W - 2 - L.rx
		-- the reference pity row sits 23 px / 27 px inside the panel span (x1.04 for our width)
		L.pityX = L.fx + 24
		L.pityRowW = W - 2 - 28 - L.pityX
		local sx = L.pityRowW / 1099 -- the reference row is 1099 wide
		L.pity = {
			pillX = 53 * sx,
			pillW = 157,
			pillH = 51,
			pillCy = 43,
			infoX = 53 * sx + 157 + 5 + round(51 * 0.7) / 2, -- 5 px ink gap from the PITY pill
			barL = 290 * sx,
			barW = 747 * sx,
			barH = 30,
			tY = 20,
			cY = 22,
			bY = 54,
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
		Text = string.upper("Featured Dice"),
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
		local cx = if L.compact then Pw / 2 + (i - 2) * L.pillSpacing else Pw * DIE_CX[i]
		local rarity = if item then item.Rarity else (if i == 2 then "Mythic" else "Legendary")
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
		local die = Draw.img(panel, { Name = "Die", ZIndex = z + 2 })
		vis(die, rec, cx, bottom - h / 2, w, h)
		local pillRec = if mythic then RollSprites.PillMythic else RollSprites.PillLegendary
		local word = string.upper(rarity)
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
		Stroke = if L.noRarPlate then 2 else nil,
		Size = self._headR,
		X = Pw / 2,
		Y = if L.noRarPlate then L.plateTop + 9 else L.plateTop + L.plateH / 2, -- plain title: sits above the rows
		W = plateW - L.plateClear,
		Z = z + 2,
	})
	-- six rows spread evenly between the plate and the panel bottom: row height fixed, the gap is what is left
	local top = if L.noRarPlate then L.plateTop + 22 else L.plateTop + L.plateH + L.rowGapTop
	local rowH = L.rowH
	local pitch = (Ph - top - L.rowBot - rowH) / 5
	local rowW = L.rowW
	local rowShift = if L.compact then 2 else 0 -- the rim face sits ~1.5 real px closer on the left
	local inset = (Pw - rowW) / 2 + rowShift
	local nameW, pctW = rowW * L.rowNameW, rowW * L.rowPctW
	for i, row in self._rows do
		local cy = top + (i - 1) * pitch + rowH / 2
		local textLift = if L.compact then 2.5 else 0 -- phones: descenders (g y p) sit in the bar, not on its edge
		local bg = Draw.img(panel, { Name = "Row_" .. row.Rarity, ZIndex = z + 1 })
		vis(bg, ROW_ART[row.Rarity] or RollSprites.RowCommon, Pw / 2 + rowShift, cy, rowW, rowH)
		local icon = Draw.img(panel, { Name = "Icon", ZIndex = z + 2 })
		local rec = ROW_ICON[row.Rarity] or RollSprites.CrownGold
		local boxW, boxH = ICON_W[row.Rarity] or 38, 24
		if L.compact then
			boxW, boxH = ({ Rare = 29, Common = 14 })[row.Rarity] or 24, 15
		end
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
			Y = cy - textLift,
			W = nameW,
			Z = z + 2,
			Stroke = 2.5,
		})
		label(panel, {
			Name = "Pct",
			Text = row.Text,
			Size = self._rowSize,
			AX = 1,
			X = inset + rowW - (if L.compact then 5 else 5), -- phones: >= 4 real px inside the row's rounded end
			Y = cy - textLift,
			W = pctW,
			Z = z + 2,
			Stroke = 2.5,
		})
	end
end

function View:_drawPity(L, z, y: number)
	local H = L.pityH
	local P = L.pity
	local rowW = L.pityRowW
	local s = L.sizes
	local x0 = L.pityX
	panelFrame(self._canvas, "Pity", x0, y, rowW, H, Bag.LeftPanel, z)
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
			W = barW * 0.7,
			Z = z + 2,
			Stroke = 2,
		})
		label(self._canvas, {
			Name = "Count",
			Text = `{pity.Count} / {pity.Max}`,
			Rich = `<font color="{YELLOW}">{pity.Count} /</font> {pity.Max}`, -- reference: the count and the slash are yellow
			Size = self._countSize,
			AX = 1,
			X = barL + barW - 6,
			Y = y + P.cY,
			W = barW * 0.22,
			Z = z + 2,
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
	self._headF = fitSize("FEATURED DICE", L.featPlateW - L.plateClear, s.head, L.minText)
	self._headR = fitSize("RARITY CHANCES", L.rarPlateW - L.plateClear, s.headR, L.minText)
	local pity = self._pity
	local barW = L.pity.barW
	self._pitySize, self._countSize = s.pity, s.count
	if pity then
		self._pitySize = fitSize(`Guaranteed {pity.Rarity} in {pity.Max} rolls!`, barW * 0.7, s.pity, L.minText)
		self._countSize = fitSize(`{pity.Count} / {pity.Max}`, barW * 0.22, s.count, L.minText)
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
	self._featuredIds, self._rows, self._pity = {}, {}, nil
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

function View:SetFeatured(list)
	self._featuredIds = list
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
