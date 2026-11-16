-- Settings menu view: gold rule, a panel of setting rows (toggle / slider / selector) and the Reset block, drawn inside the shared shell's content slot.
-- Visual only: no input handling, no store writes. Design px under the shell's UIScale; the slot's Size offset and "Compact" attribute pick the layout.
-- View.new(slot, deps) -> :SetTab(tabId) :SetValue(id, value) :OnBuilt(cb(rows)) :Destroy()
-- view.Rows[id] = { Row, Hit?, Track?, Knob?, Fraction?, Left?, Right? } for the active tab (same table, refilled on every build) and view.ResetButton
-- (the pill, an ImageButton) are the coder's handles. Instances are rebuilt on tab, slot size, scale and Compact changes (one deferred build), so
-- connect input inside an OnBuilt callback. Shown values and ON / OFF / NN% text come live from SettingsLogic.get / format.
-- Layers (slot z 22): panel 23-24, list 25, rows 26-35 (skin 27, icon 28, text 29, art 29-32, hit 35), bar 33-34, rule and Reset block 23-27.

local TextService = game:GetService("TextService")

local Draw = require(script.Parent.Parent.QuestLog.Draw)
local Parts = require(script.Parent.Parent.Bag.Parts)
local QuestSprites = require(script.Parent.Parent.QuestLog.QuestSprites)
local RollSprites = require(script.Parent.Parent.Roll.RollSprites)
local SettingsLogic = require(script.Parent.SettingsLogic)
local SettingsSprites = require(script.Parent.SettingsSprites)
local UiKit = require(script.Parent.Parent.UiKit)

local Bag = Draw.Bag
local S = SettingsSprites
local make = UiKit.make

local GOLD = Color3.fromRGB(255, 200, 60)
local DIAMOND_INK_W, BALL = 158, 62 -- Diamond ink width and the inner rule ball's distance from the ink centre (source px)
local FLANK = { left = 335, right = 378, bead = 328, bead2 = 385 } -- DividerGold source x: the left half (tapered tip to its bead, centre 328) ends at 335; the right half (bead centre 385, to tip) starts at 378
local ICON = {
	autoSkipWaves = "AutoSkip",
	damageNumbers = "DamageNumbers",
	rangeRings = "RangeRings",
	waveAnnouncements = "Announce",
	placementGrid = "PlacementGrid",
	autoCloseMenus = "AutoClose",
	effectsQuality = "EffectsQuality",
	projectileEffects = "Projectile",
	shadows = "Shadows",
	screenShake = "ScreenShake",
	uiScale = "UiScale",
	effectScale = "EffectScale",
	masterVolume = "MasterVolume",
	musicVolume = "Music",
	sfxVolume = "SoundEffects",
	interfaceVolume = "InterfaceSounds",
	ambienceVolume = "Ambience",
	reducedMotion = "ReducedMotion",
	highContrast = "HighContrast",
	showFps = "ShowFps",
	hideOthersEffects = "HideOthers",
	notifications = "Notifications",
	language = "Language",
}

-- Full-tier icon ink size (w, h) in reference px per setting (measured on the four references); fitted by aspect, centre unchanged.
local ICON_PX = {
	autoSkipWaves = { 58, 41 },
	damageNumbers = { 80, 62 },
	rangeRings = { 65, 58 },
	waveAnnouncements = { 72, 57 },
	placementGrid = { 59, 56 },
	autoCloseMenus = { 69, 55 },
	effectsQuality = { 60, 48 },
	projectileEffects = { 58, 47 },
	shadows = { 53, 49 },
	screenShake = { 84, 44 },
	uiScale = { 54, 53 },
	effectScale = { 54, 52 },
	masterVolume = { 68, 54 },
	musicVolume = { 53, 51 },
	sfxVolume = { 63, 52 },
	interfaceVolume = { 56, 54 },
	ambienceVolume = { 69, 55 },
	reducedMotion = { 61, 37 },
	highContrast = { 48, 48 },
	showFps = { 56, 48 },
	hideOthersEffects = { 67, 54 },
	notifications = { 66, 50 },
	language = { 56, 56 },
}
local PX_TO_DU = 1.09 / 0.9693 -- reference px -> design px at the 1620 window, x1.09: the sprite ink box includes a soft glow beyond the measured bright part

-- Text roles (calibrated to the reference widths): size / fit minimum, c = the Compact tier, fill, outline colour, outline px.
local ROLE = {
	name = {
		size = 34,
		min = 22,
		cs = 20,
		cmin = 18,
		fill = Color3.fromRGB(249, 248, 248),
		line = Color3.fromRGB(3, 0, 2),
		px = 2.8,
		cpx = 2,
	},
	desc = {
		size = 24, -- matches the reference widths (25 ran 3-8% wide)
		min = 17,
		cs = 18,
		cmin = 15,
		fill = Color3.fromRGB(251, 251, 251),
		line = Color3.fromRGB(40, 4, 24),
		px = 1,
		cpx = 2,
	},
	toggle = {
		size = 30,
		min = 14,
		cs = 18,
		cmin = 14,
		fill = Color3.new(1, 1, 1),
		line = Color3.fromRGB(20, 20, 20),
		px = 3,
		cpx = 2,
	},
	pill = {
		size = 34,
		min = 14,
		cs = 18,
		cmin = 14,
		fill = Color3.new(1, 1, 1),
		line = Color3.fromRGB(25, 5, 15),
		px = 3,
		cpx = 2,
	},
	reset = {
		size = 31,
		min = 16,
		cs = 20,
		cmin = 16,
		fill = Color3.new(1, 1, 1),
		line = Color3.fromRGB(12, 4, 2),
		px = 3,
		cpx = 2,
	},
}
-- Descriptions use Nunito ExtraBold: taller and lighter than Fredoka One at the same width (the reference's face). Its text is DESC_K x as wide as Fredoka's at equal size.
local DESC_FONT = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold)
local DESC_K = 0.870
local TOGGLE_X = { [true] = 0.385, [false] = 0.636 } -- ON / OFF text centre as a fraction of the toggle ink width (the knob is baked in)

local function round(n: number): number
	return math.floor(n + 0.5)
end

local K = 1 -- real px per design px under the shell's UIScales (set per build)
local COMPACT = false -- the tier being built

local function measure(str: string, size: number): number
	return TextService:GetTextSize(str, size * K, Enum.Font.FredokaOne, Vector2.new(1e5, 1e5)).X / K
end

local function measureDesc(str: string, size: number): number
	return measure(str, size) * DESC_K
end

local function role(name: string, compact: boolean): (number, number, number)
	local r = ROLE[name]
	if compact then
		return r.cs, r.cmin, r.cpx
	end
	return r.size, math.max(r.min, math.ceil(12 / K)), r.px -- Full tiers: never under 12 real px
end

-- Text size <= size at which `text` fits w (never under 12 real px unless size itself is smaller).
local function fitted(text: string, size: number, w: number): number
	local tw = measure(text, size)
	if tw > w * 0.97 then
		return math.max(math.min(size, math.ceil(12 / K)), math.floor(size * w * 0.97 / tw))
	end
	return size
end

-- Live text centred (ax 0.5) or left (ax 0) on y in a box w wide; the size is fitted to w.
local function label(
	parent,
	name: string,
	text: string,
	rname: string,
	size: number,
	x: number,
	y: number,
	w: number,
	z: number,
	ax: number?
)
	local r = ROLE[rname]
	local px = if COMPACT then r.cpx else r.px
	ax = ax or 0.5
	local l = Parts.text(parent, {
		Name = name,
		Text = text,
		TextSize = fitted(text, size, w),
		TextColor3 = r.fill,
		AnchorPoint = Vector2.new(ax, 0.5),
		Position = UDim2.fromOffset(round(x), round(y)),
		Size = UDim2.fromOffset(round(w), round(size * 1.2)),
		TextXAlignment = if ax == 0 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = z,
	}, px)
	l:FindFirstChildOfClass("UIStroke").Color = r.line
	return l
end

local rim
-- Hover / press scale of `target` for mouse and touch (the hit keeps its size), a shared gold focus rim for gamepad. A disabled hit shows no state.
local function bind(hit, target, hoverScale: number, pressScale: number)
	if not rim then
		rim = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
		make("UIStroke", { Color = GOLD, Thickness = 3 }, rim)
	end
	hit.AutoButtonColor = false
	hit.SelectionImageObject = rim
	local scale = make("UIScale", { Name = "Press" }, target)
	UiKit.wire(hit, function(state)
		scale.Scale = if not hit.Interactable
			then 1
			elseif state == "Pressed" then pressScale
			elseif state == "Hover" then hoverScale
			else 1
	end)
end

local function hitButton(parent, cx: number, cy: number, w: number, h: number, z: number)
	return make("TextButton", {
		Name = "Hit",
		Text = "",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(cx), round(cy)),
		Size = UDim2.fromOffset(round(w), round(h)),
		ZIndex = z,
	}, parent)
end

-- A sprite record drawn by its ink, fitted by aspect into w x h, centred at (cx, cy).
local function fitIn(parent, rec, cx: number, cy: number, w: number, h: number, z: number, name: string)
	local i = Draw.img(parent, { Name = name, ZIndex = z })
	local iw, ih = Draw.fitIn(rec, w, h)
	return Draw.apply(i, rec, cx, cy, iw, ih)
end

local View = {}
View.__index = View

-- Layout ----------------------------------------------------------------------------------------------------

-- Every number is design px; slot W x H = the shell's content box (Full 1206 x 618.5 at the reference).
local function compute(W: number, H: number, compact: boolean)
	local L = { W = W, H = H, compact = compact, touch = math.ceil(44 / K), fit = if compact then 0.97 else 0.995 } -- fit: share of a column a text may fill
	if compact then
		L.ruleY, L.ruleMargin, L.diamondW = 3.3, 8, 18
		L.panelK, L.ins, L.gutterR = 0.5, 5, 8 -- panel (RowFrame art) slice scale, the list's inset from the panel (the tube's inner edge), gutter corner radius
		L.rowH, L.pitch, L.top, L.padL, L.padR, L.bottom = 63, 67, 8, 10, 6, 8
		L.barW = 8
		L.iconBox, L.iconCx, L.textLeft, L.gap = { 34, 34 }, 30, 58, 12
		L.tgl = { w = 102, h = 36, right = 12 }
		L.sel = { w = 220, right = 12, bodyH = 32, armH = 36, tuck = 4 }
		local narrow = W <= 700
		L.sld = {
			maxW = if narrow then 130 else 150,
			trackH = 18,
			knob = 36,
			pillW = if narrow then 60 else 64,
			pillH = 30,
			pillRight = 12,
			pillGap = 14,
		}
		L.resetH = math.max(46, math.ceil(44 / 1.2 / K)) -- the Reset box (1.2x the pill's ink height) stays >= 44 real px tall
		L.resetBottom = H - 0.38 * L.resetH -- the footer's clearance below the pill, as on desktop
		L.panelX, L.panelY, L.panelW, L.panelH = 4, 12, W - 8, math.max(60, H - 16 - 1.38 * L.resetH)
	else
		L.ruleY, L.ruleMargin, L.diamondW = 9.3, 3, 70
		L.panelK, L.ins, L.gutterR = 0.9, 10, 16 -- the reference tube is ~9 px thick, corner radius ~29
		L.panelX, L.panelY, L.panelW, L.panelH = 13.3, 24.1, W - 23.6, math.max(60, H - 114.7)
		L.rowH, L.pitch, L.top, L.padL, L.padR, L.bottom = 76, 77.5, 4.5, 12.4, 13.4, 5 -- the rows keep their positions: pads are the old ones less (ins - 3, ins - 5)
		L.nameDy, L.descDy = 0.6, -6.1 -- the reference sets its name / description block high in the row
		L.barW = 12
		L.iconBox, L.iconCx, L.textLeft, L.gap = { 78, 70 }, 77, 149.9, 6
		L.tgl = { w = 152.5, h = 49.2, right = 88 }
		L.sel = { w = 287.4, right = 26.6, bodyH = 44.5, armH = 41, tuck = 6.5 }
		L.sld =
			{ maxW = 361.2, trackH = 26.9, knob = 42.3, pillW = 105.8, pillH = 47.8, pillRight = 16.4, pillGap = 16.1 }
		L.resetH, L.resetBottom = 61.6, H - 15.8
	end
	L.listW, L.listH = L.panelW - 2 * L.ins, L.panelH - 2 * L.ins
	L.rowW = L.listW - L.padL - L.padR
	return L
end

-- Left edge (row px) of the control column for a def; set after the slider track width is known.
local function controlLeft(L, def): number
	if def.kind == "toggle" then
		return L.rowW - L.tgl.right - L.tgl.w
	elseif def.kind == "select" then
		return L.rowW - L.sel.right - L.sel.w
	end
	return L.sld.trackLeft - L.sld.boxMargin
end

-- The slider track: right edge fixed by the pill; Full shortens it (down to 180) so the longest slider description stays on one line.
local function layoutSlider(L, descSize: number)
	local s = L.sld
	s.boxMargin = 4 -- the track sprite's box is wider than its ink (11 source px at the slider scale)
	s.trackRight = L.rowW - s.pillRight - s.pillW - s.pillGap
	s.trackW = s.maxW
	if not L.compact then
		local widest = 0
		for _, def in SettingsLogic.DEFS do
			if def.kind == "slider" then
				widest = math.max(widest, measureDesc(def.desc, descSize) * 1.02) -- DESC_K is an estimate: keep slack
			end
		end
		s.trackW = math.clamp(s.trackRight - (L.textLeft + widest + L.gap + s.boxMargin), 180, s.maxW)
	end
	s.trackLeft = s.trackRight - s.trackW
end

-- One text size per role across every tab (so tabs never jump): the largest at which every string fits its column;
-- descriptions that cannot fit one line even at the minimum wrap to two lines instead.
local function roleSizes(L)
	local nameSize, nameMin = role("name", L.compact)
	local descSize, descMin = role("desc", L.compact)
	layoutSlider(L, descSize)
	for _, def in SettingsLogic.DEFS do
		local colW = controlLeft(L, def) - L.gap - L.textLeft
		while nameSize > nameMin and measure(def.name, nameSize) > colW * 0.97 do
			nameSize -= 1
		end
		if measureDesc(def.desc, descMin) <= colW * L.fit then
			while descSize > descMin and measureDesc(def.desc, descSize) > colW * L.fit do
				descSize -= 1
			end
		end
	end
	layoutSlider(L, descSize) -- the track may now be longer at the final description size
	L.nameSize, L.descSize = nameSize, descSize
end

-- Rows ------------------------------------------------------------------------------------------------------

local function drawToggle(L, row, def, z: number, updaters)
	local tg, rowH = L.tgl, L.rowH
	local hit = hitButton(row, L.rowW - tg.right - tg.w / 2, rowH / 2, math.max(tg.w, L.touch), rowH, z + 9)
	local holder = make("Frame", {
		Name = "Holder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(round(tg.w), round(tg.h)),
		ZIndex = hit.ZIndex + 1,
	}, hit)
	local sprite = Draw.img(holder, { Name = "Toggle" })
	local size = role("toggle", L.compact)
	local text = label(holder, "Label", "", "toggle", size, 0, tg.h / 2, tg.w * 0.4, holder.ZIndex + 2)
	bind(hit, holder, 1.03, 0.96)
	updaters[def.id] = function(value)
		local on = value == true
		local rec = if on then S.ToggleOn else S.ToggleOff
		Draw.apply(sprite, rec, tg.w / 2, tg.h / 2, tg.w, tg.h)
		text.Text = SettingsLogic.format(def.id, on)
		text.Position = UDim2.fromOffset(round(tg.w / 2 + (TOGGLE_X[on] - 0.5) * tg.w), round(tg.h / 2))
	end
	return { Hit = hit }
end

local function drawSlider(L, row, def, z: number, updaters)
	local s, rowH = L.sld, L.rowH
	local cy = rowH / 2
	local tx0, tx1, r = s.trackLeft, s.trackRight, s.knob / 2
	local trackRec, fillRec = RollSprites.BarTrack, RollSprites.BarFill
	local k = s.trackH / trackRec.Ink.Height -- the fill uses the same scale: its caps never distort
	local track = Draw.img(row, { Name = "Track", ZIndex = z + 3 })
	Draw.apply(track, trackRec, (tx0 + tx1) / 2, cy, tx1 - tx0, s.trackH)
	local fill = Draw.img(row, { Name = "Fill", ZIndex = z + 4 })
	Parts.skin(fill, fillRec, k)
	fill.AnchorPoint = Vector2.new(0, 0.5)
	local fillH = fillRec.Size.Y * k
	local fillCy = cy + (fillRec.Size.Y / 2 - (fillRec.Ink.Min.Y + fillRec.Ink.Max.Y) / 2) * k
	local capSum = (fillRec.Slice.Min.X + fillRec.Size.X - fillRec.Slice.Max.X) * k
	local marginSum = (fillRec.Ink.Min.X + fillRec.Size.X - fillRec.Ink.Max.X) * k
	local boxLeft = tx0 - fillRec.Ink.Min.X * k
	local knob = Draw.img(row, { Name = "Knob", ZIndex = z + 6 })
	local kw, kh = Draw.fitIn(S.Knob, s.knob, s.knob)
	Draw.apply(knob, S.Knob, tx0 + r, cy, kw, kh)
	local pill = Draw.img(row, { Name = "Pill", ZIndex = z + 3 })
	local pillCx = L.rowW - s.pillRight - s.pillW / 2
	Draw.apply(pill, S.ValuePill, pillCx, cy, s.pillW, s.pillH)
	local size = role("pill", L.compact)
	local text = label(
		pill,
		"Text",
		"",
		"pill",
		size,
		pill.Size.X.Offset / 2,
		pill.Size.Y.Offset / 2,
		s.pillW - 16,
		pill.ZIndex + 1
	)
	local hitL = tx0 - s.boxMargin
	local hit = hitButton(row, 0, cy, tx1 - tx0 + 2 * s.boxMargin, rowH, z + 9)
	hit.AnchorPoint, hit.Position = Vector2.new(0, 0.5), UDim2.fromOffset(round(hitL), round(cy))
	bind(hit, knob, 1.08, 1.08)
	updaters[def.id] = function(value)
		local min, max = def.min :: number, def.max :: number
		local v = math.clamp((value - min) / (max - min), 0, 1)
		local cx = tx0 + r + v * (tx1 - tx0 - 2 * r)
		Draw.apply(knob, S.Knob, cx, cy, kw, kh)
		fill.Position = UDim2.fromOffset(round(boxLeft), round(fillCy))
		fill.Size = UDim2.fromOffset(round(math.max(capSum, cx - tx0 + marginSum)), round(fillH))
		text.Text = SettingsLogic.format(def.id, value)
		text.TextSize = fitted(text.Text, size, s.pillW - 16)
	end
	-- Fraction(screenX) -> 0..1 along the knob travel (the track ink inset by the knob radius), from the hit's live real-px rect.
	local function fraction(screenX: number): number
		local scale = hit.AbsoluteSize.X / hit.Size.X.Offset
		local w = (hit.Size.X.Offset - 2 * s.boxMargin - 2 * r) * scale
		return if w > 0 then math.clamp((screenX - hit.AbsolutePosition.X - (s.boxMargin + r) * scale) / w, 0, 1) else 0
	end
	return { Hit = hit, Track = track, Knob = knob, Fraction = fraction }
end

local function drawSelect(L, row, def, z: number, updaters)
	local sel, rowH = L.sel, L.rowH
	local cy = rowH / 2
	local right = L.rowW - sel.right
	local left = right - sel.w
	local armL, armR = S.ArrowLeft, S.ArrowRight
	local aL, aR = sel.armH * armL.Ink.Width / armL.Ink.Height, sel.armH * armR.Ink.Width / armR.Ink.Height
	local bodyW = sel.w - aL - aR + 2 * sel.tuck
	local bodyCx = left + aL - sel.tuck + bodyW / 2
	local cap = Draw.img(row, { Name = "Capsule", ZIndex = z + 2 }) -- one continuous purple capsule behind the arrow pills and the gold body
	Draw.apply(cap, Bag.PillPurple, left + sel.w / 2, cy, sel.w, sel.armH, sel.armH / Bag.PillPurple.Ink.Height)
	local artL = Draw.img(row, { Name = "ArrowL", ZIndex = z + 3 }) -- the arrow pills tuck under the gold body
	Draw.apply(artL, armL, left + aL / 2, cy, aL, sel.armH)
	local artR = Draw.img(row, { Name = "ArrowR", ZIndex = z + 3 })
	Draw.apply(artR, armR, right - aR / 2, cy, aR, sel.armH)
	local body = Draw.img(row, { Name = "Body", ZIndex = z + 4 })
	Draw.apply(body, Bag.PillGold, bodyCx, cy, bodyW, sel.bodyH)
	local size = role("pill", L.compact)
	local text = label(row, "Value", "", "pill", size, bodyCx, cy, bodyW - 16, z + 6)
	local function arrow(art, cx: number, w: number, name: string)
		local hit = hitButton(row, cx, cy, math.max(w, L.touch), rowH, z + 9)
		hit.Name = name
		bind(hit, art, 1.03, 0.96)
		return hit
	end
	local leftHit, rightHit = arrow(artL, left + aL / 2, aL, "Left"), arrow(artR, right - aR / 2, aR, "Right")
	-- a single option (Language) looks and presses like any selector; Settings toasts "coming soon" instead of cycling
	updaters[def.id] = function(value)
		text.Text = SettingsLogic.format(def.id, value)
		text.TextSize = fitted(text.Text, size, math.min(bodyW - 16, 117))
	end
	return { Left = leftHit, Right = rightHit }
end

local DRAW = { toggle = drawToggle, slider = drawSlider, select = drawSelect }

-- 1 or 2: a description that cannot fit one line at the minimum size wraps (as the engine lays it out, in design px).
local function descLines(L, def): number
	local colW = controlLeft(L, def) - L.gap - L.textLeft
	local one = TextService:GetTextSize(def.desc, L.descSize * DESC_K, Enum.Font.FredokaOne, Vector2.new(1e5, 1e5)).Y
	local wrapped =
		TextService:GetTextSize(def.desc, L.descSize * DESC_K, Enum.Font.FredokaOne, Vector2.new(round(colW), 1e5)).Y
	return if wrapped > one * 1.5 then 2 else 1
end

function View:_drawRow(L, list, def, y: number, lines: number)
	local baseH, z = L.rowH, list.ZIndex
	local rowH = baseH + (lines - 1) * round(L.descSize * 1.2) -- a wrapped description grows its row by one line
	L.rowH = rowH -- shortcut: the control drawers read L.rowH; restored at the end of this row
	local row = Draw.img(list, {
		Name = "Row_" .. def.id,
		Position = UDim2.fromOffset(round(L.padL), round(y)),
		Size = UDim2.fromOffset(round(L.rowW), round(rowH)),
		ZIndex = z + 1,
	}, "Frame")
	local skin = Draw.img(row, { Name = "RowFrame", ZIndex = row.ZIndex + 1 })
	Draw.apply(
		skin,
		S.RowFrame,
		L.rowW / 2,
		rowH / 2,
		L.rowW,
		rowH,
		rowH / S.RowFrame.Ink.Height * (if L.compact then 1 else 0.85)
	) -- Full: thinner rim, smaller corners
	local px = ICON_PX[def.id]
	local k = if L.compact then L.iconBox[2] / 70 else 1 -- Compact keeps the desktop icon proportions in its smaller box
	local bw, bh = px[1] * PX_TO_DU * k, px[2] * PX_TO_DU * k
	fitIn(row, S[ICON[def.id]], L.iconCx, rowH / 2, bw, bh, row.ZIndex + 2, "Icon")
	-- name + description block, centred in the row
	local colW = controlLeft(L, def) - L.gap - L.textLeft
	local nameH, lineH = round(L.nameSize * 1.2), round(L.descSize * 1.2)
	local top = (rowH - nameH - lines * lineH) / 2 + (L.nameDy or 0)
	local tz = row.ZIndex + 3
	label(row, "Name", def.name, "name", L.nameSize, L.textLeft, top + nameH / 2, colW, tz, 0)
	local desc = label(
		row,
		"Desc",
		def.desc,
		"desc",
		L.descSize,
		L.textLeft,
		top + nameH + lines * lineH / 2 + (L.descDy or 0) - (L.nameDy or 0),
		colW,
		tz,
		0
	)
	desc.Size = UDim2.fromOffset(round(colW), lines * lineH)
	desc.TextWrapped, desc.TextYAlignment, desc.TextTruncate = true, Enum.TextYAlignment.Center, Enum.TextTruncate.AtEnd
	desc.FontFace, desc.TextSize = DESC_FONT, L.descSize
	local handles = DRAW[def.kind](L, row, def, row.ZIndex, self._update)
	handles.Row = row
	self.Rows[def.id] = handles
	self._update[def.id](SettingsLogic.get(def.id))
	L.rowH = baseH
end

-- Rule, panel, list, Reset block ----------------------------------------------------------------------------

-- One half of Bag.DividerGold (tapered tip -> line -> bead), stretched along x only: src x range [srcX, srcX + srcW), thickness = source height * fk.
local function divider(
	root,
	name: string,
	x0: number,
	w: number,
	srcX: number,
	srcW: number,
	cy: number,
	fk: number,
	z: number
)
	local div = Bag.DividerGold
	local p = Draw.img(root, { Name = name, ZIndex = z })
	p.Image, p.ScaleType = div.Image, Enum.ScaleType.Stretch
	p.ImageRectOffset, p.ImageRectSize = Vector2.new(srcX, 0), Vector2.new(srcW, div.Size.Y)
	p.AnchorPoint = Vector2.new(0, 0.5)
	p.Position = UDim2.fromOffset(round(x0), round(cy))
	p.Size = UDim2.fromOffset(math.ceil(w), round(div.Size.Y * fk))
end

local function drawRule(L, root, z: number)
	local k = L.diamondW / DIAMOND_INK_W
	local cx, cy = L.W / 2, L.ruleY
	local diamond = Draw.img(root, { Name = "Diamond", ZIndex = z + 1 })
	Draw.apply(diamond, S.Diamond, cx, cy, L.diamondW, S.Diamond.Ink.Height * k)
	local fk = if L.compact then 0.3 else 0.8 -- the line thickens from a point at the window edge to its bead beside the Diamond
	local bead = BALL * k -- the line's bead sits under the Diamond's own ball
	local x0 = L.ruleMargin
	local lEnd = cx - bead + (FLANK.left - FLANK.bead) * fk
	divider(root, "RuleL", x0, lEnd - x0, 0, FLANK.left, cy, fk, z)
	local rStart = cx + bead - (FLANK.bead2 - FLANK.right) * fk
	divider(root, "RuleR", rStart, L.W - x0 - rStart, FLANK.right, Bag.DividerGold.Size.X - FLANK.right, cy, fk, z)
end

local function drawPanel(L, root, z: number)
	local panel = Draw.img(root, {
		Name = "Panel",
		Position = UDim2.fromOffset(round(L.panelX), round(L.panelY)),
		Size = UDim2.fromOffset(round(L.panelW), round(L.panelH)),
		ZIndex = z,
	}, "Frame")
	local skin = Draw.img(panel, { Name = "Skin" })
	Draw.apply(skin, S.RowFrame, L.panelW / 2, L.panelH / 2, L.panelW, L.panelH, L.panelK)
	return panel
end

local function drawReset(L, root, z: number): any
	local rec = Bag.PillGold
	local u = L.resetH / 61.6
	local text = "RESET DEFAULTS"
	local size = role("reset", L.compact)
	local labelW = measure(text, size)
	if not L.compact then
		labelW = math.max(labelW, 211)
	end
	local pillW = math.min(139 * u + labelW, L.W - 16)
	local cx, cy = L.W / 2, L.resetBottom - L.resetH / 2
	local k = L.resetH / rec.Ink.Height
	local btn = Draw.img(root, { Name = "Reset", ZIndex = z + 3 }, "ImageButton")
	Draw.apply(btn, rec, cx, cy, pillW, L.resetH, k)
	Parts.interact(btn)
	local ox, oy = rec.Ink.Min.X * k, rec.Ink.Min.Y * k -- the ink's origin inside the pill's box (the box is >= 44 real px tall at every scale)
	local iconD = if L.compact then 27 else 41 * u -- Compact: ~1.9x the label's cap height
	local icon = Draw.img(btn, { Name = "Icon", ZIndex = btn.ZIndex + 1 })
	local ir = S.RefreshWhite
	local iw, ih = Draw.fitIn(ir, iconD, iconD)
	Draw.apply(icon, ir, ox + 59.9 * u, oy + L.resetH / 2, iw, ih)
	label(
		btn,
		"Label",
		text,
		"reset",
		size,
		ox + 103.4 * u + (pillW - 139 * u) / 2,
		oy + L.resetH / 2,
		(pillW - 139 * u) / 0.9, -- a roomy box: the label keeps its size and stays centred
		btn.ZIndex + 1
	)
	-- gold sparkles and tapered flank lines (DividerGold halves), only where there is room
	local sparkOff = pillW / 2 + 34.5 * u
	-- No sheet has the Reset star: reuse Quest.Sparkle2 tinted gold; the rect starts below a stray speck above the star.
	local spark = { Image = QuestSprites.Sparkle2.Image, Size = Vector2.new(112, 91), Ink = Rect.new(29, 8, 77, 63) }
	local sk = if L.compact then 0.9 else 1 -- Compact sparkles are a smaller share of the pill
	local sw, sh = 30 * u * sk, 62 * u * sk -- the sprite's ink includes its glow: the bright core is about 24 x 41
	if L.W / 2 - sparkOff - sw / 2 >= 6 then
		for _, sx in { cx - sparkOff, cx + sparkOff } do
			local s = Draw.img(root, { Name = "Spark", ZIndex = z + 2 })
			Draw.apply(s, spark, sx, cy - 3.6 * u, sw, sh)
			s.ImageRectOffset, s.ImageRectSize = Vector2.new(0, 40), spark.Size
			s.ImageColor3 = Color3.fromRGB(255, 214, 64)
		end
	end
	local fk = 0.6 * u
	local len = math.min((if L.compact then 302.6 else 296) * u, L.W / 2 - sparkOff - 19 * u - 20)
	if len >= 40 then
		local lx = cx - sparkOff - 19 * u - len -- left flank outer end
		local rx = cx + sparkOff + 19 * u -- right flank inner end
		divider(root, "FlankL", lx, len, 0, FLANK.left, cy, fk, z + 1)
		divider(root, "FlankR", rx, len, FLANK.right, Bag.DividerGold.Size.X - FLANK.right, cy, fk, z + 1)
	end
	return btn
end

function View:_build()
	local L = self._L
	K, COMPACT = L.K, L.compact
	local root = self._root
	local keepY = if self._resetScroll then 0 else self._list and self._list.CanvasPosition.Y or 0
	self._resetScroll = false
	root:ClearAllChildren()
	table.clear(self.Rows)
	table.clear(self._update)
	local defs = {}
	for _, def in SettingsLogic.DEFS do
		if def.tab == self._tab then
			table.insert(defs, def)
		end
	end
	local pitch = if not L.compact and self._tab == "AUDIO" then 87.5 else L.pitch -- Audio keeps the wider pitch
	local canvasH = math.ceil(L.top + math.max(0, #defs - 1) * pitch + L.rowH + L.bottom)
	L.rowW = L.listW - L.padL - L.padR
	if canvasH > L.listH then
		L.rowW -= if L.compact then L.barW - 2 else L.barW / 2 + 2 -- the scroll bar gets its own strip: it never touches a row
	end
	roleSizes(L)
	local z = root.ZIndex
	drawRule(L, root, z)
	local panel = drawPanel(L, root, z)
	local gutter = make("Frame", { -- the reference's gutter between the rows, kept inside the tube's rounded corners
		Name = "Gutter",
		BackgroundColor3 = Color3.fromRGB(66, 8, 15),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(L.ins, L.ins),
		Size = UDim2.fromOffset(round(L.listW), round(L.listH)),
		ZIndex = panel.ZIndex + 1,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, L.gutterR) }, gutter)
	local list = make("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0, -- the styled bar replaces the native one; wheel, touch and drag still scroll
		ScrollBarImageTransparency = 1,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		Active = true,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(L.ins, L.ins),
		Size = UDim2.fromOffset(round(L.listW), round(L.listH)),
		ZIndex = panel.ZIndex + 2,
	}, panel)
	self._list = list
	local y = L.top
	for _, def in defs do
		local lines = descLines(L, def)
		self:_drawRow(L, list, def, y, lines)
		y += pitch + (lines - 1) * round(L.descSize * 1.2)
	end
	canvasH = math.max(canvasH, math.ceil(y - pitch + L.rowH + L.bottom))
	list.CanvasSize = UDim2.fromOffset(0, canvasH)
	list.CanvasPosition = Vector2.new(0, keepY)
	local host = Draw.img(panel, {
		Name = "BarHost",
		Position = UDim2.fromOffset(0, L.ins + L.gutterR),
		Size = UDim2.fromOffset(round(L.panelW), round(L.listH - 2 * L.gutterR)),
		ZIndex = list.ZIndex,
	}, "Frame")
	local bar = Parts.scrollBar(host, list, list.ZIndex + 8)
	bar.Layout(L.listH - 2 * L.gutterR, L.barW, L.ins + 1) -- right edge just inside the tube, ends clear of the corner curves
	bar.Track.Visible = canvasH > L.listH
	self.ResetButton = drawReset(L, root, z)
	for _, cb in self._onBuilt do
		cb(self.Rows)
	end
end

-- Public ----------------------------------------------------------------------------------------------------

-- deps is reserved (nothing is injected yet: values come from SettingsLogic).
function View.new(slot, _deps)
	local self = setmetatable({}, View)
	self._conns, self._update, self._onBuilt = {}, {}, {}
	self._tab, self._resetScroll = SettingsLogic.TABS[1], true
	self.Rows = {}
	local root = make("Frame", {
		Name = "SettingsRoot",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = slot.ZIndex + 1,
	}, slot)
	self._root = root
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
			self._L.K = k
			self:_build()
		end)
	end
	self._rebuild = rebuild
	table.insert(self._conns, slot:GetPropertyChangedSignal("Size"):Connect(rebuild))
	table.insert(self._conns, slot:GetAttributeChangedSignal("Compact"):Connect(rebuild))
	rebuild()
	return self
end

-- Shows the rows of one tab (a SettingsLogic.TABS id) and returns the list to the top.
function View:SetTab(tabId: string)
	self._tab, self._resetScroll = tabId, true
	self._rebuild()
end

-- Updates one control of the active tab in place (toggle sprite + ON/OFF, slider fill / knob / NN%, selector label); other tabs read the store on build.
function View:SetValue(id: string, value: any)
	local update = self._update[id]
	if update then
		update(value)
	end
end

-- cb(rows) runs after every build, with view.Rows filled: the place to connect input (the instances are replaced on each build).
function View:OnBuilt(cb)
	table.insert(self._onBuilt, cb)
	if next(self.Rows) then
		cb(self.Rows)
	end
end

function View:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	table.clear(self._onBuilt)
	self._root:Destroy()
end

return View
