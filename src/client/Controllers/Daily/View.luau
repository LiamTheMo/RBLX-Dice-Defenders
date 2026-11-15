-- Daily Rewards menu view: the claim strip, six day cards, the Day 7 chest card and the progress / CLAIM / timer bar, in the shared shell's slot.
-- Visual only: no NetClient, no game data. Design px under the shell's UIScale; the slot's Size offset and "Compact" attribute pick the layout.
-- View.new(slot) -> :SetDays(SampleData.Days) :SetStreak(streak, claimedToday) :SetTimer(prefix?, value?) :SetClaimState("Ready" | "Claimed" | "Soon")
--   :SetSoon(on) :OnAction(cb()) (a CLAIM press while "Ready") :Destroy()
-- Setters only store state; one deferred rebuild draws it (also on every slot size / Compact change).
-- Full = the reference in 1197 x 688 content units (x scaled by W / 1197, y by H / 688). Compact = fixed strip and bar, the cards on a
-- vertical Parts.scrollBar scroll (3 columns, Day 7 below). Card art is drawn WHOLE at one scale per card, placed by its rim centre / bottom.
-- Layers: cards 24, card content 25-26, text 27, strip and bar 24-27, scroll bar 31-32, Soon card 30-32.

local TextService = game:GetService("TextService")

local DailyLogic = require(script.Parent.DailyLogic)
local DailySprites = require(script.Parent.DailySprites)
local Draw = require(script.Parent.Parent.QuestLog.Draw)
local Parts = require(script.Parent.Parent.Bag.Parts)
local PlaySprites = require(script.Parent.Parent.Play.PlaySprites)
local RollSprites = require(script.Parent.Parent.Roll.RollSprites)
local Sprites = require(script.Parent.Parent.Sprites)
local UiKit = require(script.Parent.Parent.UiKit)

local Q = Draw.Q
local make = UiKit.make

local GOLD_HEX = "#FCD51A"
local GOLD = Color3.fromRGB(252, 213, 26)
local WHITE = Color3.fromRGB(250, 248, 245)
local LINE = Color3.fromRGB(45, 3, 8)
local PANEL_INS = { 4, 2, 4, 10 } -- visible insets (source px: left, top, right, bottom) of the LeftPanel sprite inside its Ink rect
local PANEL_K = 0.5 -- slice scale of every card (as the Shop)
local REF_W, REF_H = 1197, 688 -- the reference content box
local S_CARD, S_DAY7 = 0.828, 0.953 -- sprite px -> design px of the small cards / Day 7 at the reference size (text sizes scale with it)

-- The raw HUD Gem and Dice have transparent margins: Size / Ink (alpha >= 160) measured from their PNGs in Assets\UI\lobby HUD\export.
local GEM = { Image = Sprites.Gem, Size = Vector2.new(128, 124), Ink = Rect.new(4, 4, 124, 120) }
local function hud(id: string, w: number, h: number, r: number, b: number)
	return { Image = id, Size = Vector2.new(w, h), Ink = Rect.new(6, 6, r, b) }
end
local DICE = {
	Sun = hud(Sprites.Dice.Sun, 236, 254, 231, 248),
	Ice = hud(Sprites.Dice.Ice, 244, 253, 239, 248),
	Fire = hud(Sprites.Dice.Fire, 237, 254, 231, 248),
	Leaf = hud(Sprites.Dice.Leaf, 246, 253, 240, 248),
	Lightning = hud(Sprites.Dice.Lightning, 249, 252, 243, 246),
}
-- card art: the rim centre x and bottom (sprite px) every state is aligned by (the glow frames carry a bigger box)
-- the 4th value is the sprite's measured rim width: every state is scaled to the same VISIBLE rim (the glow frames' boxes are bigger)
local CARD = {
	Upcoming = { DailySprites.CardUpcoming, 168, 286, 308 },
	Today = { DailySprites.CardToday, 175, 286, 312.5 },
	Claimed = { DailySprites.CardClaimed, 171.5, 286, 312 },
}
local DAY7 = {
	Upcoming = { DailySprites.Day7, 203, 519, 380 },
	Today = { DailySprites.Day7Glow, 211.5, 521, 379 },
}
-- small card content: the cell x (sprite px from the rim centre); the icon / amount rows are laid out in _card
local CELL_X = 74
local TAB_Y = -243 -- DAY n on the red tab
-- reference columns / row bottoms / Day 7 (content units)
local COLS, ROWS = { 144.5, 413.5, 679 }, { 306.4, 541.3 } -- row bottoms put the tab tops at the reference y 245 / 480 (C 78 / 313)
local DAY7_REF = { cx = 1001, bottom = 537, w = 355 } -- rim width: the sprite is taller than the reference (aspect), so the width gives
local CARD_W = 252 -- a little (card 252 vs 262, Day 7 355 vs 365) to keep the crown and the rows' gap as in the reference

local function round(n: number): number
	return math.floor(n + 0.5)
end

local K = 1 -- real px per design px under the shell's UIScales (set per build)

local function measure(str: string, size: number): number
	return TextService:GetTextSize(str, size * K, Enum.Font.FredokaOne, Vector2.new(1e5, 1e5)).X / K
end

-- The largest size <= size at which str fits w (never under min).
local function fitText(str: string, w: number, size: number, min: number): number
	while size > min and measure(str, size) > w * 0.97 do
		size -= 1
	end
	return size
end

-- Live text centred at (x, y); fill / outline colour and outline px as the other menus' roles.
local function label(parent, name: string, text: string, size: number, x: number, y: number, z: number, o)
	o = o or {}
	local l = Parts.text(parent, {
		Name = name,
		Text = text,
		RichText = o.rich == true,
		TextSize = size,
		TextColor3 = o.fill or WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(x), round(y)),
		Size = UDim2.fromOffset(math.ceil(measure(text, size)) + 12, round(size * 1.2)),
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = z,
	}, o.px or 3)
	local stroke = l:FindFirstChildOfClass("UIStroke")
	if o.px == 0 then
		stroke:Destroy()
	else
		stroke.Color = o.line or LINE
	end
	return l
end

-- A record sprite, drawn by its ink fitted by aspect into w x h, centred at (cx, cy); raw ids as a Fit image.
local function sprite(parent, ref, cx: number, cy: number, w: number, h: number, z: number, name: string?)
	local i = Draw.img(parent, { Name = name or "Art", ZIndex = z })
	if type(ref) == "table" then
		local iw, ih = Draw.fitIn(ref, w, h)
		Draw.apply(i, ref, cx, cy, iw, ih)
	else
		i.Image, i.ScaleType = ref, Enum.ScaleType.Fit
		i.AnchorPoint, i.Position, i.Size =
			Vector2.new(0.5, 0.5), UDim2.fromOffset(round(cx), round(cy)), UDim2.fromOffset(round(w), round(h))
	end
	return i
end

-- A sprite drawn by its ink at exactly w x h centred at (cx, cy) (9-slice records keep their rim at the default scale).
local function skin(parent, rec, cx: number, cy: number, w: number, h: number, z: number, name: string, k: number?)
	return Draw.apply(Draw.img(parent, { Name = name, ZIndex = z }), rec, cx, cy, w, h, k)
end

-- The whole sprite at scale s with its rim point (rx, ry) (sprite px) at (px, py) in the parent.
local function whole(parent, rec, rx: number, ry: number, px: number, py: number, s: number, z: number, name: string)
	return Draw.img(parent, {
		Name = name,
		Image = rec.Image,
		ScaleType = Enum.ScaleType.Stretch,
		Position = UDim2.fromOffset(round(px - rx * s), round(py - ry * s)),
		Size = UDim2.fromOffset(round(rec.Size.X * s), round(rec.Size.Y * s)),
		ZIndex = z,
	})
end

-- LeftPanel skin by its VISIBLE box (x, y, w, h), slice scale PANEL_K as the Shop's cards.
local function panel(parent, x: number, y: number, w: number, h: number, z: number, name: string)
	local l, t, r, b = PANEL_INS[1], PANEL_INS[2], PANEL_INS[3], PANEL_INS[4]
	local k = PANEL_K
	Draw.apply(
		Draw.img(parent, { Name = name, ZIndex = z }),
		Draw.Bag.LeftPanel,
		x + w / 2 + (r - l) / 2 * k,
		y + h / 2 + (b - t) / 2 * k,
		w + (l + r) * k,
		h + (t + b) * k,
		k
	)
end

local function rewardRec(reward)
	local kind = reward.Kind
	if kind == "Coins" then
		return Draw.Bag.Coins
	elseif kind == "Gems" then
		return GEM
	elseif kind == "Potion" then
		return Q.Potion
	elseif kind == "Crystals" then
		return Draw.Bag.IconCrystals
	end
	return DICE[reward.Die] or DICE.Fire
end

-- One reward: the icon (fitted into bw x bh, coins by tier) standing on iconBottom (never over the amount) and its amount centred at (x, ay).
local function reward(
	parent,
	r,
	x: number,
	iconBottom: number,
	ay: number,
	bw: number,
	bh: number,
	size: number,
	z: number,
	px: number?
)
	local k = 1
	if r.Kind == "Coins" then
		k = ({ 0.86, 0.93, 1 })[DailyLogic.coinTier(r.Amount)]
	end
	local rec = rewardRec(r)
	local _, ih = Draw.fitIn(rec, bw * k, bh * k)
	sprite(parent, rec, x, iconBottom - ih / 2, bw * k, bh * k, z, "Icon")
	label(parent, "Amount", DailyLogic.amountText(r), size, x, ay, z + 2, { px = px })
end

local View = {}
View.__index = View

-- Layout ----------------------------------------------------------------------------------------------------

local function compute(W: number, H: number, compact: boolean)
	local L = { W = W, H = H, compact = compact }
	L.touch = math.ceil(44 / K) -- smallest button height that is >= 44 real px
	if compact then
		L.stripH, L.barH, L.gap, L.inset = 40, 76, 10, 10
		L.gutter = 16 -- the scroll bar (8 px + 4 + 4) is counted on both sides so the columns stay centred
		L.scrollTop = L.stripH + 4
		L.scrollH = H - L.scrollTop - L.barH - 6 - 4 -- down to 4 px above the bar
		L.pad = 6 -- the first row starts 10 px under the strip
		local sW = math.min(240, (W - 2 * L.gutter - 2 * L.gap) / 3) / 308 -- the widest the 3 columns allow
		-- Row 2 shows WHOLE tab plates (tab rim bottom at 62 px x scale) and no icon pixels, or nothing with <= 12 px left blank.
		-- Whichever the width allows: a card tall enough to fill the window (A: row 2 hidden), else row 2 peeks (B) at the gap, then the scale, that fit it.
		local sA = math.min(sW, (L.scrollH - L.pad - 8) / 273)
		local rowGap = L.gap
		if L.scrollH - L.pad - 273 * sA <= 12 then
			L.s = sA
			rowGap = math.max(L.gap, L.scrollH + 6 - L.pad - 273 * sA)
		else
			-- B: row 2's visible part ends exactly under its tab plates and above its icons (the icon tops sit 1.5 px above the tab plate's 62 px).
			L.s = sW
			rowGap = L.scrollH - L.pad - 335 * sW + 1.5
			if rowGap < 6 then
				rowGap = 6
				L.s = (L.scrollH - L.pad - 6 + 1.5) / 335
			end
		end
		L.colW, L.cardH = L.s * 308, L.s * 273
		L.rows = L.cardH + rowGap
		L.s7 = math.min(W - 2 * L.gutter, 340) / 380
		L.canvasH = math.ceil(L.pad + 2 * L.rows + L.s7 * 519 + 8 + 4) -- Day 7's rim bottom + 4: ~12 px blank above the bar with the 4 px window gap
		L.barBtn = math.max(52, L.touch)
	else
		L.sx, L.sy = W / REF_W, H / REF_H
		L.s, L.s7 = CARD_W * L.sx / 308, DAY7_REF.w * L.sx / 380 -- rim widths 308 / 380 sprite px
		L.barBtn = math.max(69 * L.sy, L.touch)
	end
	L.tsc, L.f7 = L.s / S_CARD, L.s7 / S_DAY7
	return L
end

-- Build -----------------------------------------------------------------------------------------------------

function View:_card(L, parent, day, state: string, cx: number, bottom: number)
	local s = L.s
	local rec, rx, ry, rimW = table.unpack(CARD[state])
	whole(parent, rec, rx, ry, cx, bottom, s * 308 / rimW, 24, "Card" .. day.Day)
	local tsz = fitText("DAY 6", 140 * s, round(38 * L.tsc), if L.compact then 18 else math.ceil(12 / K))
	label(parent, "DayLabel", "DAY " .. day.Day, tsz, cx, bottom + TAB_Y * s + 1, 27, {})
	if state == "Claimed" then
		return -- the baked tick sits over the cells
	end
	local asz = fitText("+1,500", 100 * s * 1.2, round(35 * L.tsc), math.ceil(12 / K))
	-- Every tier: each cell is laid out bottom-up in design px from outline-aware budgets (measured, Fredoka One: the white ink of "+1,500"
	-- reaches 0.302 x size above and 0.438 x size (the comma) below the label centre, and the UIStroke adds its thickness all round):
	--   amount outline bottom = the cell's bottom limit (rim dark edge, or the cross rule's top edge) - 3.5 (5.5 on the bottom row: Today glow)
	--   icon ink bottom       = the amount's white-fill top - 2 (the amount draws above the icon, so the icon may run under its outline);
	--   the icon gets what is left up to the cell top (tab bottom / rule bottom) + 1.5.
	-- If that leaves < 60% of the cell on phones, the amount text shrinks (<= 2 px, never under the floor) before the icon does.
	local OUT = if L.compact then 2 else 3 -- the amount's outline px
	local function cellRow(row: number, size: number)
		local m1, m2 = if L.compact then 4.5 else 5.5, if L.compact then 6 else 8 -- design px of margin below the amount outline
		local lim = (if row == 1 then -122 - m1 / s else -10.8 - m2 / s) * s -- the Today glow ramps up from the rim early
		local ay = lim - 0.438 * size - OUT
		local ib = ay - 0.302 * size - 4 -- the icon may run under the amount's outline, never over its white fill
		local top = (if row == 1 then -214 else -119) * s + 1
		local cellH = (if row == 1 then 214 - 122 else 119 - 10.8) * s
		return ay, ib, ib - top, cellH
	end
	local size = asz
	if L.compact then
		for _ = 1, 2 do
			local _, _, h1, c1 = cellRow(1, size)
			local _, _, h2, c2 = cellRow(2, size)
			if math.min(h1 / c1, h2 / c2) >= 0.6 or size <= math.ceil(12 / K) then
				break
			end
			size -= 1
		end
	end
	for i, r in day.Rewards do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2) + 1
		local x = cx + (if col == 0 then -CELL_X else CELL_X) * s
		local ay, ib, h = cellRow(row, size)
		reward(parent, r, x, bottom + ib, bottom + ay, 140 * s, h, size, 25, OUT)
	end
end

function View:_day7(L, parent, day, state: string, cx: number, bottom: number)
	local s, f = L.s7, L.f7
	local rec, rx, ry, rimW = table.unpack(DAY7[if state == "Today" then "Today" else "Upcoming"])
	local sd = s * 380 / rimW
	whole(parent, rec, rx, ry, cx, bottom, sd, 24, "Day7")
	local ax = cx - 0.7 * f -- the content axis: the visible rim's centre (the frame's own padding is lopsided)
	local min = if L.compact then 18 else math.ceil(12 / K)
	label(parent, "DayLabel", "DAY 7", fitText("DAY 7", 150 * s, round(52 * f), min), ax, bottom - 410 * sd, 27, {})
	-- the name ribbon, then the chest from just under the DAY 7 tab (rim bottom at sprite y 151) down to behind the ribbon's top edge
	local rw = 327 * f
	local rh = rw * Draw.Bag.ItemsNameRibbon.Ink.Height / Draw.Bag.ItemsNameRibbon.Ink.Width
	local ribbonY = bottom - 159 * f
	local top, bot = bottom - (ry - 151) * sd + 3, ribbonY - rh / 2 + 18
	local cy, chH = (top + bot) / 2, bot - top
	for _, side in { -1, 1 } do -- laurels hug the chest's sides, partly behind it
		sprite(
			parent,
			if side < 0 then PlaySprites.LaurelL else PlaySprites.LaurelR,
			ax + side * (chH * 0.475), -- about half of each laurel shows beside the chest's lower half
			cy + 30 * f,
			56 * f,
			80 * f,
			25,
			if side < 0 then "LaurelL" else "LaurelR"
		)
	end
	sprite(parent, DailySprites.Chest, ax, cy, 1e4, chH, 25, "Chest")
	skin(parent, Draw.Bag.ItemsNameRibbon, ax, ribbonY, rw, rh, 26, "Ribbon")
	local name = day.Chest or "ROYAL DICE CHEST"
	-- one size on the purple plate (centre = the ribbon's, 7 px above its ink centre), >= 8 px clear of both plate ends
	label(parent, "RibbonText", name, fitText(name, 244 * f, round(34 * f), min), ax, ribbonY - 7 * f, 27, {})
	local bw, bh = 332 * f, 111 * f
	local by = bottom - 64.5 * f
	skin(parent, Draw.Bag.QtyField, ax, by, bw, bh, 25, "RewardBox")
	local asz = fitText("+5,000", bw / 3 * 0.9, round(35 * f), min)
	-- the same outline-aware stack: amount outline 3+ px above the box's inner rim dark edge (N = 15.5 above the card bottom; measured), icon 2.2 above
	-- the outline, icon top 6 px under the inner top rim
	local ayN = 24.5 * f + 0.438 * asz + 3
	local ibN = ayN + 0.302 * asz + 2
	local boxTop = 107.5 * f
	for i, r in day.Rewards do
		local x = ax + (i - 2) * bw / 3
		reward(parent, r, x, bottom - ibN, bottom - ayN, 100 * f, boxTop - ibN, asz, 26)
		if i < 3 then
			local d = make("Frame", {
				Name = "Divider",
				BackgroundColor3 = Color3.fromRGB(140, 88, 75),
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(round(x + bw / 6) - 2, round(by)), -- whole px: 1 soft + a 2 px core + 1 soft
				Size = UDim2.fromOffset(4, round(60 * f)),
				ZIndex = 26,
			}, parent)
			make("Frame", { -- the pale-gold core between two soft sides
				Name = "Core",
				BackgroundColor3 = Color3.fromRGB(255, 226, 183),
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(1, 0),
				Size = UDim2.new(0, 2, 1, 0),
				ZIndex = 27,
			}, d)
		end
	end
	if state == "Claimed" then
		sprite(parent, Draw.Bag.Check, ax, cy, chH * 1.05, chH * 1.05, 28, "Tick")
	end
end

-- The strip: Track + laurels + the live sentence ("7 days!" in gold), centred on the window axis; the laurels sit just outside the pill ends.
function View:_strip(L, parent)
	local W = L.W
	local text = "Claim rewards every day for 7 days!"
	local cx, cy, w, h, size, lw, lh, ly
	if L.compact then
		cx, cy, w, h, lw, lh, ly = W / 2, L.stripH / 2, W - 2 * 36, L.stripH - 4, 24, 32, L.stripH / 2
		size = fitText(text, w - 24, 26, math.ceil(14 / K))
	else
		cx, cy, w, h, lw, lh, ly = W / 2 + 1, 16 * L.sy, 814 * L.sx, 70 * L.sy, 63 * L.sx, 72 * L.sy, 14 * L.sy
		size = fitText(text, 661 * L.sx * 1.1, round(46.5 * L.sx), math.ceil(12 / K))
	end
	skin(parent, Q.Track, cx, cy, w, h, 24, "Strip")
	local iw = Draw.fitIn(PlaySprites.LaurelL, lw, lh) -- the laurel's ink width
	sprite(parent, PlaySprites.LaurelL, cx - w / 2 - iw / 2 - 2, ly, lw, lh, 25, "LaurelL")
	sprite(parent, PlaySprites.LaurelR, cx + w / 2 + iw / 2 + 2, ly, lw, lh, 25, "LaurelR")
	local rich = `Claim rewards every day for <font color="{GOLD_HEX}">7 days!</font>`
	label(parent, "StripText", rich, size, cx, cy + (if L.compact then 0 else 3 * L.sy), 27, { rich = true })
end

local function divider(parent, x: number, y: number, h: number)
	local d = make("Frame", {
		Name = "Divider",
		BackgroundColor3 = GOLD,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(x), round(y)),
		Size = UDim2.fromOffset(3, round(h)),
		ZIndex = 26,
	}, parent)
	d.BackgroundTransparency = 0
end

-- The bottom bar: calendar + PROGRESS + pill | CLAIM | stopwatch + timer. Full = the reference boxes; Compact = a proportioned row.
function View:_drawBar(L, parent)
	local c = L.compact
	local W, sx, sy = L.W, L.sx, L.sy
	local top = if c then L.H - L.barH - 6 else 556 * sy
	local bh = if c then L.barH else 120 * sy
	local mid = top + bh / 2
	local function by(refy: number)
		return refy * sy
	end
	-- the Row's visible rim sits ~1 sprite px left of its ink centre, and the reference bar is 3 units left of the content axis: centre it on W / 2
	local bcx = W / 2 + 1.4 * bh / 120
	skin(parent, Q.Row, bcx, mid, if c then W - 2 * L.inset else 1170 * sx, bh, 24, "Bar")
	local k = if c then 1 else sx
	local min = math.ceil(12 / K)
	-- Compact segment positions (design px): calendar | PROGRESS pill | divider | CLAIM | divider | stopwatch + timer
	local pw, px, div1, div2, cw, ccx, tl, tr
	if c then
		pw = math.clamp(0.2 * W, 88, 134)
		cw = math.clamp(0.24 * W, 110, 190)
		px = 70 + pw / 2
		div1 = 70 + pw + 12
		ccx = div1 + 10 + cw / 2
		div2 = ccx + cw / 2 + 10
		tl, tr = div2 + 6, W - L.inset - 8
	else
		pw, px, div1, div2 = 225 * sx, 242.5 * sx, 380.5 * sx, 798.5 * sx
		cw, ccx = 302 * sx, 588.5 * sx
	end
	sprite(
		parent,
		DailySprites.Calendar,
		if c then 46 else 88 * sx,
		if c then mid else by(613),
		(if c then 40 else 83 * sx),
		(if c then 44 else 74 * sy),
		25,
		"Calendar"
	)
	local ptext = DailyLogic.progressText(self._streak)
	local ph = if c then 26 else 41 * sy
	local ty, pyc = if c then mid - 17 else by(588), if c then mid + 14 else by(631.5)
	label(
		parent,
		"ProgressTitle",
		"PROGRESS",
		fitText("PROGRESS", pw * 0.8, if c then 18 else round(36 * k), min),
		px,
		ty,
		27,
		{}
	)
	skin(parent, Draw.Bag.PillGold, px, pyc, pw, ph, 25, "Pill")
	label(
		parent,
		"ProgressText",
		ptext,
		fitText(ptext, pw * 0.8, if c then 18 else round(35 * k), min),
		px,
		pyc + (if c then 0 else 0.5 * sy),
		27,
		{}
	)
	divider(parent, div1, if c then mid else by(615), if c then bh - 24 else 65 * sy)
	divider(parent, div2, if c then mid else by(615), if c then bh - 24 else 65 * sy)
	-- CLAIM / CLAIMED
	local state = self._claim
	if state ~= "Soon" then
		local ready = state == "Ready"
		local cy = if c then mid else by(613.5)
		local btn = Draw.img(parent, { Name = "Claim", ZIndex = 26 }, if ready then "ImageButton" else "ImageLabel")
		Draw.apply(btn, if ready then Draw.Bag.BtnGreen else RollSprites.BtnGrey, ccx, cy, cw, L.barBtn)
		local text = if ready then "CLAIM" else "CLAIMED"
		local tsz = fitText(text, cw * 0.84, if c then 28 else round(59 * k), min)
		local t = label(btn, "Label", text, tsz, btn.AbsoluteSize.X / 2, 0, 27, { px = if c then 3 else 4 })
		t.Position = UDim2.new(0.5, 0, 0.5, if c then -1 else -2)
		t.Size = UDim2.fromScale(1, 1)
		if ready then
			Parts.interact(btn)
			table.insert(
				self._connsBuild,
				btn.Activated:Connect(function()
					if self._claim == "Ready" and self._onAction then
						self._onAction()
					end
				end)
			)
		end
	end
	-- timer: the untinted stopwatch on a gold halo (the Quest Log timer pill's look) and the two lines, as one group when Compact
	if self._timer then
		local prefix, value = self._timer[1], self._timer[2]
		local sw, sh = if c then 38 else 66 * sx, if c then 40 else 69 * sy -- by ink: the visible gold is ~85% of it
		local fw, fh = Draw.fitIn(Q.Stopwatch, sw, sh)
		local psz = fitText(
			prefix,
			if c then math.max(60, tr - tl - fw - 10) else 186 * sx,
			if c then 18 else round(32 * k),
			min
		)
		local vw, vmax = if c then math.max(50, tr - tl - fw - 10) else 172 * sx, if c then 24 else round(50 * k)
		local vsz = fitText(value, vw, vmax, min)
		-- lay the group out for the widest timer text so SetTimer's in-place updates never need re-centring
		local textW = math.max(measure(prefix, psz), measure("00h 00m", fitText("00h 00m", vw, vmax, min)))
		local wx, tx
		if c then
			local gl = (tl + tr) / 2 - (fw + 10 + textW) / 2 -- the group is centred in its slot
			wx, tx = gl + fw / 2, gl + fw + 10 + textW / 2
		else
			wx, tx = 887 * sx, 1021 * sx
		end
		local wy = if c then mid else by(613)
		local halo -- a wide soft glow under a tighter, brighter one: reads clearly just outside the ink
		for _, g in { { 1.9, 0.05 }, { 1.35, 0.2 } } do
			halo = Draw.img(parent, {
				Name = "StopwatchGlow",
				Image = Q.GlowRadial.Image,
				ImageColor3 = Color3.fromRGB(255, 190, 40),
				ImageTransparency = g[2],
				Size = UDim2.fromOffset(round(fh * g[1]), round(fh * g[1])),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(round(wx), round(wy)),
				ZIndex = 25,
			})
		end
		local watch = Draw.img(parent, { Name = "Stopwatch", ZIndex = halo.ZIndex + 1 })
		Draw.apply(watch, Q.Stopwatch, wx, wy, fw, fh)
		label(parent, "TimerPrefix", prefix, psz, tx, if c then wy - 15 else by(588.5), 27, {})
		local vl = label(parent, "TimerValue", value, vsz, tx, if c then wy + 15 else by(627.5), 27, { fill = GOLD })
		self._timerLive = {
			Label = vl,
			Fit = function(v: string): number -- SetTimer's in-place text update
				return fitText(v, vw, vmax, min)
			end,
		}
	end
end

function View:_drawSoon(L)
	local c = L.compact
	local W, H = L.W, L.H
	local w, h = if c then 340 else 520, if c then 150 else 240
	local x, y = (W - w) / 2, (H - h) / 2
	panel(self._soon, x, y, w, h, 30, "SoonCard")
	local ih = if c then 60 else 100
	sprite(self._soon, Sprites.Icon.Daily, W / 2, y + (if c then 15 else 20) + ih / 2, ih * 2, ih, 31, "Icon")
	local min = if c then 18 else math.ceil(12 / K)
	label(
		self._soon,
		"Title",
		"DAILY REWARDS",
		fitText("DAILY REWARDS", w - 40, if c then 24 else 36, min),
		W / 2,
		y + (if c then 95 else 150),
		32,
		{}
	)
	label(
		self._soon,
		"Sub",
		"Coming soon",
		fitText("Coming soon", w - 40, if c then 18 else 26, min),
		W / 2,
		y + (if c then 122 else 190),
		32,
		{ fill = Color3.fromRGB(205, 210, 235) }
	)
end

function View:_build()
	local L = self._L
	if not L or not self._root.Parent then
		return
	end
	for _, conn in self._connsBuild do
		conn:Disconnect()
	end
	table.clear(self._connsBuild)
	for _, parent in { self._fixed, self._plain, self._canvas, self._soon } do
		for _, ch in parent:GetChildren() do
			ch:Destroy()
		end
	end
	local soon = self._soonOn
	self._fixed.Visible, self._soon.Visible = not soon, soon
	self._host.Visible = not soon
	self._bar.Layout(0, 8, 4)
	self._bar.Track.Visible = false
	if soon then
		self:_drawSoon(L)
		return
	end
	local c = L.compact
	self:_strip(L, self._fixed)
	self:_drawBar(L, self._fixed)
	local days = self._days
	local target = self._plain
	if c then
		self._host.Position = UDim2.fromOffset(0, L.scrollTop)
		self._host.Size = UDim2.fromOffset(L.W, L.scrollH)
		self._canvas.Size = UDim2.fromOffset(L.W, L.canvasH)
		self._scroll.CanvasSize = UDim2.fromOffset(0, L.canvasH)
		self._scroll.ClipsDescendants = true
		target = self._canvas
	else
		self._host.Position = UDim2.fromOffset(0, 0)
		self._host.Size = UDim2.fromScale(1, 1)
		self._scroll.ClipsDescendants = false
	end
	self._plain.Visible, self._scroll.Visible = not c, c
	for i = 1, 6 do
		local day = days[i]
		if day then
			local state = DailyLogic.cardState(i, self._streak, self._claimedToday)
			local cx, bottom
			if c then
				local x0 = (L.W - (3 * L.colW + 2 * L.gap)) / 2
				cx = x0 + L.colW / 2 + ((i - 1) % 3) * (L.colW + L.gap)
				bottom = L.pad + math.floor((i - 1) / 3) * L.rows + L.cardH
			else
				cx, bottom = COLS[(i - 1) % 3 + 1] * L.sx, ROWS[math.floor((i - 1) / 3) + 1] * L.sy
			end
			self:_card(L, target, day, state, cx, bottom)
		end
	end
	if days[7] then
		local state = DailyLogic.cardState(7, self._streak, self._claimedToday)
		local cx, bottom
		if c then
			cx, bottom = L.W / 2, L.pad + 2 * L.rows + L.s7 * 519 + 8
		else
			cx, bottom = DAY7_REF.cx * L.sx, DAY7_REF.bottom * L.sy
		end
		self:_day7(L, target, days[7], state, cx, bottom)
	end
	self._bar.Layout(if c then L.scrollH else 0, 8, 4)
	self._bar.Track.Visible = c and L.canvasH > L.scrollH
end

-- Public ----------------------------------------------------------------------------------------------------

function View.new(slot)
	local self = setmetatable({}, View)
	self._conns, self._connsBuild, self._days = {}, {}, {}
	self._streak, self._claimedToday, self._claim, self._soonOn = 0, false, "Ready", false
	local z = slot.ZIndex + 1
	local root = make(
		"Frame",
		{ Name = "DailyRoot", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z },
		slot
	)
	local fixed =
		make("Frame", { Name = "Fixed", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z }, root)
	local host = make(
		"Frame",
		{ Name = "CardsHost", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z },
		root
	)
	local plain =
		make("Frame", { Name = "Cards", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z }, host)
	local scroll = make("ScrollingFrame", {
		Name = "CardsScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0, -- the styled bar replaces the native one; wheel, touch and drag still scroll
		ScrollBarImageTransparency = 1,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = z,
	}, host)
	local canvas = make("Frame", { Name = "Canvas", BackgroundTransparency = 1, ZIndex = z }, scroll)
	local soon = make("Frame", {
		Name = "Soon",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = z,
	}, root)
	self._root, self._fixed, self._host, self._plain, self._scroll, self._canvas, self._soon =
		root, fixed, host, plain, scroll, canvas, soon
	self._bar = Parts.scrollBar(host, scroll, z + 8)
	local pending = false
	local scaleSeen = {}
	local function rebuild()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if not root.Parent then
				return
			end
			local w, h = slot.Size.X.Offset, slot.Size.Y.Offset
			if w <= 0 or h <= 0 then
				return
			end
			local k = 1
			local a = slot
			while a and a.Name ~= "Root" do -- real px per design px: every UIScale above the slot except the open animation's Pop
				for _, ch in a:GetChildren() do
					if ch:IsA("UIScale") and ch.Name ~= "Pop" then
						k *= ch.Scale
						if not scaleSeen[ch] then -- a later scale change (window resize) must rebuild: K sizes the hit boxes
							scaleSeen[ch] = true
							table.insert(self._conns, ch:GetPropertyChangedSignal("Scale"):Connect(rebuild))
						end
					end
				end
				a = a.Parent
			end
			K = k
			self._L = compute(w, h, slot:GetAttribute("Compact") == true)
			self:_build()
		end)
	end
	self._rebuild = rebuild
	table.insert(self._conns, slot:GetPropertyChangedSignal("Size"):Connect(rebuild))
	table.insert(self._conns, slot:GetAttributeChangedSignal("Compact"):Connect(rebuild))
	rebuild()
	return self
end

function View:SetDays(days)
	self._days = days
	self._rebuild()
end

function View:SetStreak(streak: number, claimedToday: boolean)
	self._streak, self._claimedToday = streak, claimedToday
	self._rebuild()
end

-- prefix / value nil hides the timer.
-- Same prefix while shown: only the value text changes, so it is updated in place (no rebuild per tick).
function View:SetTimer(prefix: string?, value: string?)
	local was = self._timer
	self._timer = if prefix and value then { prefix, value } else nil
	local live = self._timerLive
	if was and self._timer and was[1] == prefix and live and live.Label.Parent then
		local l = live.Label
		local size = live.Fit(value :: string)
		l.Text, l.TextSize = value :: string, size
		l.Size = UDim2.fromOffset(math.ceil(measure(value :: string, size)) + 12, round(size * 1.2))
		return
	end
	self._rebuild()
end

function View:SetClaimState(state: string)
	self._claim = state
	self._rebuild()
end

function View:SetSoon(on: boolean)
	self._soonOn = on
	self._rebuild()
end

function View:OnAction(cb)
	self._onAction = cb
end

function View:Destroy()
	for _, conn in self._conns do
		conn:Disconnect()
	end
	for _, conn in self._connsBuild do
		conn:Disconnect()
	end
	table.clear(self._conns)
	table.clear(self._connsBuild)
	self._bar.Track:Destroy()
	self._root:Destroy()
end

return View
