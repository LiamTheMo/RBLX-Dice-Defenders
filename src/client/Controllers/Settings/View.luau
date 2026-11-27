-- Settings menu view: a code-drawn panel of setting rows (icon, name, description, toggle / slider / selector) and the RESET DEFAULTS
-- block, drawn inside the shared shell's content slot. Visual only: no input handling, no store writes.
-- Design px under the shell's UIScale; the slot's Size offset and "Compact" attribute pick the tier (Full = the 1672x941 mockups,
-- measured numbers are from mockup.png / gameplay.png / graphics.png / misc.png; Compact = phones, rows scroll).
-- View.new(slot, deps) -> :SetTab(tabId) :SetValue(id, value) :OnBuilt(cb(rows)) :Destroy()
-- view.Rows[id] = { Row, Hit?, Track?, Knob?, Fraction?, Left?, Right? } for the active tab (same table, refilled on every build) and
-- view.ResetButton (an ImageButton) are the coder's handles. Instances are rebuilt on tab, slot size, scale and Compact changes (one
-- deferred build), so connect input inside an OnBuilt callback. Values and ON / OFF / NN% text come live from SettingsLogic.
-- GUI paths: SettingsRoot.Panel.List.Row_<id>.{Icon,Name,Desc,Toggle|Track,Knob,Pill|Capsule,Hit}, SettingsRoot.Panel.Reset.

local Chrome = require(script.Parent.Parent.Bag.Chrome)
local Parts = require(script.Parent.Parent.Bag.Parts)
local SettingsLogic = require(script.Parent.SettingsLogic)
local SettingsSprites = require(script.Parent.SettingsSprites)
local Shared = require(script.Parent.Parent.SharedSprites)
local UiKit = require(script.Parent.Parent.UiKit)

local S = SettingsSprites
local make = UiKit.make

local GOLD = Color3.fromRGB(255, 200, 60)
local ICON = {
	autoSkipWaves = "AutoSkip",
	damageNumbers = "DamageNumbers",
	waveAnnouncements = "Announce",
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
}
-- Descriptions use Nunito ExtraBold (the mockups' face): DESC_K x as wide as Fredoka One at equal size.
local DESC_FONT = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold)
local DESC_K = 0.87
local TOGGLE_X = { [true] = 0.385, [false] = 0.636 } -- ON / OFF text centre as a fraction of the toggle art's ink width (the knob is baked in)
local WHITE = Color3.new(1, 1, 1)

-- Colours sampled from the mockups.
local PANEL_FILL, PANEL_RIM = Color3.fromRGB(36, 37, 42), Color3.fromRGB(190, 190, 196)
local ROW_FILL, ROW_RIM = Color3.fromRGB(39, 39, 44), Color3.fromRGB(150, 149, 155)
local PILL_FILL, PILL_RIM = Color3.fromRGB(10, 11, 13), Color3.fromRGB(94, 94, 99)
local TRACK_RIM = Color3.fromRGB(225, 190, 10)
local FLANK = Color3.fromRGB(175, 174, 178)
local PURPLE_TOP, PURPLE_BOT = Color3.fromRGB(170, 60, 240), Color3.fromRGB(115, 15, 205)
-- Full tier: slider track left edge per row (row px = mockup x - 318) where the mockups differ from the Audio 535.
local TRACK_LEFT = { uiScale = 515, effectScale = 587 }

local round = UiKit.round

local K = 1 -- real px per design px under the shell's UIScales (set per build)

-- Text size <= size at which `text` (Fredoka width x k) fits w; never under 12 real px (unless size itself is smaller).
local function fitted(text: string, size: number, w: number, k: number?): number
	return Parts.fitSize(text, w / (k or 1), size, math.min(size, math.ceil(12 / K)))
end

-- Live text on y centred (ax 0.5) or left (ax 0) in a box w wide, outlined; strokeless when stroke is 0.
local function label(parent, name: string, text: string, o)
	local ax = o.ax or 0.5
	local l = Parts.text(parent, {
		Name = name,
		Text = text,
		TextSize = o.size,
		TextColor3 = o.color or WHITE,
		AnchorPoint = Vector2.new(ax, 0.5),
		Position = UDim2.fromOffset(round(o.x), round(o.y)),
		Size = UDim2.fromOffset(round(o.w), round(o.h or o.size * 1.25)),
		TextXAlignment = if ax == 0 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = o.z,
	}, o.stroke or 2)
	if o.stroke == 0 then
		l.UIStroke.Enabled = false
	end
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

-- Ink size (w, h) of a sprite record fitted by aspect into maxW x maxH.
local function fitIn(rec, maxW: number, maxH: number): (number, number)
	local s = math.min(maxW / rec.Ink.Width, maxH / rec.Ink.Height)
	return rec.Ink.Width * s, rec.Ink.Height * s
end

-- Sets image `i` to a whole sprite drawn so its visible ink is inkW x inkH, centred at (cx, cy); never sliced (callers keep the aspect, fitIn).
local function place(i, rec, cx: number, cy: number, inkW: number, inkH: number)
	local ink, size = rec.Ink, rec.Size
	local sx, sy = inkW / ink.Width, inkH / ink.Height
	i.Image, i.ScaleType, i.AnchorPoint = rec.Image, Enum.ScaleType.Stretch, Vector2.new(0.5, 0.5)
	i.Size = UDim2.fromOffset(round(size.X * sx), round(size.Y * sy))
	i.Position = UDim2.fromOffset(
		round(cx + (size.X / 2 - (ink.Min.X + ink.Max.X) / 2) * sx),
		round(cy + (size.Y / 2 - (ink.Min.Y + ink.Max.Y) / 2) * sy)
	)
	return i
end

local function art(parent, rec, cx: number, cy: number, inkW: number, inkH: number, name: string, z: number)
	local i = make("ImageLabel", { Name = name, BackgroundTransparency = 1, ZIndex = z }, parent)
	return place(i, rec, cx, cy, inkW, inkH)
end

local View = {}
View.__index = View

-- Layout ----------------------------------------------------------------------------------------------------

-- Every number is design px. Full (slot 1068 x 507): panel 1065 x 500 at (2, 2); rows 70 tall at pitch 80.25 (Audio, 5 rows), x 14..1051;
-- RESET DEFAULTS pill 340 x 52 centred 45 px above the panel bottom, flank lines either side.
local function compute(W: number, H: number, compact: boolean)
	local L = { W = W, H = H, compact = compact, touch = math.ceil(44 / K) }
	if compact then
		L.panelW, L.panelH = W - 4, H - 4
		L.nameSize, L.descSize, L.pillSize, L.toggleSize, L.resetSize = 22, 16, 22, 20, 18
		L.rowH, L.gap, L.top, L.padX, L.bottomPad = 60, 8, 8, 8, 8
		L.iconCx, L.iconBox, L.textLeft, L.tgap = 34, { 50, 40 }, 68, 10
		L.pillW, L.pillH, L.pillRight = 66, 32, 8
		L.tglH, L.tglFromRight = 38, 68
		L.selW, L.selH, L.selRight = 190, 34, 10
		L.trackH, L.knob, L.trackMax, L.trackMin, L.trackGap = 18, 27, 300, 90, 14
		L.resetH, L.resetW = math.max(44, L.touch), 250
		L.iconD = 26
	else
		L.panelW, L.panelH = W - 3, H - 7
		L.nameSize, L.descSize, L.pillSize, L.toggleSize, L.resetSize = 31, 21, 30, 28, 25
		L.rowH, L.gap, L.top, L.padX, L.bottomPad = 70, 10.25, 19, 14, 19
		L.iconCx, L.iconBox, L.textLeft, L.tgap = 63, { 72, 58 }, 130, 12
		L.pillW, L.pillH, L.pillRight = 85, 40, 13
		L.tglH, L.tglFromRight = 52, 114
		L.selW, L.selH, L.selRight = 262, 38, 22
		L.trackH, L.knob, L.trackMax, L.trackMin, L.trackGap = 24, 36, 373, 200, 28
		L.resetH, L.resetW = 52, 340
		L.iconD = 30
	end
	L.listH = L.panelH - L.resetH - L.bottomPad - (if compact then L.bottomPad else 0)
	L.resetCy = L.panelH - L.bottomPad - L.resetH / 2
	L.rowW = L.panelW - 2 * L.padX
	return L
end

-- Left edge (row px) of the control column for a def; the slider track's is the tab's trackLeft.
local function controlLeft(L, def, trackLeft: number): number
	if def.kind == "toggle" then
		return L.rowW - L.tglFromRight - L.tglH * 335 / 116 / 2
	elseif def.kind == "select" then
		return L.rowW - L.selRight - L.selW
	end
	return trackLeft
end

-- Rows -------------------------------------------------------------------------------------------------------

local function drawToggle(L, row, def, rowH: number, z: number, updaters)
	local h = L.tglH
	local wOn, wOff = h * 326 / 116, h * 335 / 116
	local cx = L.rowW - L.tglFromRight
	local hit = hitButton(row, cx, rowH / 2, math.max(wOff, L.touch), math.max(rowH, L.touch), z + 9)
	local holder = make("Frame", {
		Name = "Holder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(round(wOff), round(h)),
		ZIndex = hit.ZIndex + 1,
	}, hit)
	local sprite =
		make("ImageLabel", { Name = "Toggle", BackgroundTransparency = 1, ZIndex = holder.ZIndex + 1 }, holder)
	local text = label(holder, "Label", "", {
		size = L.toggleSize,
		x = 0,
		y = h / 2,
		w = wOff * 0.4,
		z = holder.ZIndex + 3,
		stroke = if L.compact then 2 else 2.5,
	})
	bind(hit, holder, 1.03, 0.96)
	updaters[def.id] = function(value)
		local on = value == true
		local w = if on then wOn else wOff
		place(sprite, if on then S.ToggleOn else S.ToggleOff, wOff / 2, h / 2, w, h)
		text.Text = SettingsLogic.format(def.id, on)
		text.Position = UDim2.fromOffset(round(wOff / 2 + (TOGGLE_X[on] - 0.5) * w), round(h / 2))
	end
	return { Hit = hit }
end

local function drawSlider(L, row, def, rowH: number, z: number, updaters, trackLeft: number)
	local cy = rowH / 2
	local trackRight = L.rowW - L.pillRight - L.pillW - L.trackGap
	local trackW, r = trackRight - trackLeft, L.knob / 2
	local track, fill = Chrome.track(row, {
		Name = "Track",
		Position = UDim2.fromOffset(round(trackLeft), round(cy - L.trackH / 2)),
		Size = UDim2.fromOffset(round(trackW), L.trackH),
		ZIndex = z + 3,
	})
	track.UIStroke.Color = TRACK_RIM
	local knob = make("ImageLabel", { Name = "Knob", BackgroundTransparency = 1, ZIndex = z + 6 }, row)
	local kw, kh = fitIn(S.Knob, L.knob, L.knob)
	local pill = Chrome.field(row, {
		Name = "Pill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(L.rowW - L.pillRight - L.pillW / 2), round(cy)),
		Size = UDim2.fromOffset(L.pillW, L.pillH),
		Radius = L.pillH / 2,
		ZIndex = z + 3,
	})
	pill.BackgroundColor3 = PILL_FILL
	pill.UIStroke.Color = PILL_RIM
	local text = label(pill, "Text", "", {
		size = L.pillSize,
		x = L.pillW / 2,
		y = L.pillH / 2,
		w = L.pillW - 12,
		z = z + 4,
		stroke = if L.compact then 2 else 2.5,
	})
	local hit = hitButton(row, 0, cy, trackW + 2 * 4, math.max(rowH, L.touch), z + 9)
	hit.AnchorPoint, hit.Position = Vector2.new(0, 0.5), UDim2.fromOffset(round(trackLeft - 4), round(cy))
	bind(hit, knob, 1.08, 1.08)
	updaters[def.id] = function(value)
		local v = math.clamp((value - def.min) / (def.max - def.min), 0, 1)
		local travel = r + v * (trackW - 2 * r) -- knob centre along the track
		place(knob, S.Knob, trackLeft + travel, cy, kw, kh)
		fill.Size = UDim2.fromScale(travel / trackW, 1)
		text.Text = SettingsLogic.format(def.id, value)
		text.TextSize = fitted(text.Text, L.pillSize, L.pillW - 12)
	end
	-- Fraction(screenX) -> 0..1 along the knob travel (the track inset by the knob radius), from the hit's live real-px rect.
	local function fraction(screenX: number): number
		local scale = hit.AbsoluteSize.X / hit.Size.X.Offset
		local w = (hit.Size.X.Offset - 2 * 4 - 2 * r) * scale
		return if w > 0 then math.clamp((screenX - hit.AbsolutePosition.X - (4 + r) * scale) / w, 0, 1) else 0
	end
	return { Hit = hit, Track = track, Knob = knob, Fraction = fraction }
end

local function drawSelect(L, row, def, rowH: number, z: number, updaters)
	local cy = rowH / 2
	local right = L.rowW - L.selRight
	local left = right - L.selW
	local arm, tuck = round(L.selH * 1.45), 6
	local bodyW = L.selW - 2 * arm + 2 * tuck
	local bodyCx = left + L.selW / 2
	local cap = make("Frame", {
		Name = "Capsule",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(bodyCx), round(cy)),
		Size = UDim2.fromOffset(L.selW, L.selH),
		ZIndex = z + 2,
	}, row)
	make("UICorner", { CornerRadius = UDim.new(0, 999) }, cap)
	make("UIGradient", { Color = ColorSequence.new(PURPLE_TOP, PURPLE_BOT), Rotation = 90 }, cap)
	Chrome.stroke(cap, Color3.fromRGB(20, 0, 40), 2)
	local body = make("Frame", {
		Name = "Body",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(bodyCx), round(cy)),
		Size = UDim2.fromOffset(round(bodyW), round(L.selH - 4)),
		ZIndex = z + 3,
	}, row)
	make("UICorner", { CornerRadius = UDim.new(0, 999) }, body)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 218, 60), Color3.fromRGB(240, 160, 0)),
		Rotation = 90,
	}, body)
	Chrome.stroke(body, Color3.fromRGB(60, 30, 0), 2)
	local function chevron(text: string, cx: number, name: string)
		return label(row, name, text, { size = L.pillSize, x = cx, y = cy, w = arm - 4, z = z + 5, stroke = 2.5 })
	end
	local artL, artR = chevron("<", left + (arm - tuck) / 2, "ArrowL"), chevron(">", right - (arm - tuck) / 2, "ArrowR")
	local text = label(row, "Value", "", {
		size = L.pillSize,
		x = bodyCx,
		y = cy,
		w = bodyW - 2 * tuck - 8,
		z = z + 5,
		color = Color3.fromRGB(30, 15, 0),
		stroke = 0,
	})
	local function arrow(target, cx: number, w: number, name: string)
		local hit = hitButton(row, cx, cy, math.max(w, L.touch), math.max(rowH, L.touch), z + 9)
		hit.Name = name
		bind(hit, target, 1.03, 0.96)
		return hit
	end
	local leftHit = arrow(artL, left + (arm - tuck) / 2, arm - tuck, "Left")
	local rightHit = arrow(artR, right - (arm - tuck) / 2, arm - tuck, "Right")
	-- a single option looks and presses like any selector; Settings toasts "coming soon" instead of cycling
	updaters[def.id] = function(value)
		text.Text = SettingsLogic.format(def.id, value)
		text.TextSize = fitted(text.Text, L.pillSize, bodyW - 2 * tuck - 8)
	end
	return { Left = leftHit, Right = rightHit }
end

local DRAW = { toggle = drawToggle, slider = drawSlider, select = drawSelect }

function View:_drawRow(L, list, def, y: number, rowH: number, lines: number, trackLeft: number)
	local z = list.ZIndex + 1
	local row = Chrome.panel(list, {
		Name = "Row_" .. def.id,
		BackgroundColor3 = ROW_FILL,
		NoGradient = true,
		Radius = 12,
		Rim = 2,
		Position = UDim2.fromOffset(round(L.padX), round(y)),
		Size = UDim2.fromOffset(round(L.rowW), round(rowH)),
		ZIndex = z,
	})
	row.UIStroke.Color = ROW_RIM
	local rec = S[ICON[def.id]]
	local iw, ih = fitIn(rec, L.iconBox[1], L.iconBox[2])
	art(row, rec, L.iconCx, rowH / 2, iw, ih, "Icon", z + 1)
	local colW = controlLeft(L, def, trackLeft) - L.tgap - L.textLeft
	local nameSize = fitted(def.name, L.nameSize, colW)
	local descSize = fitted(def.desc, L.descSize, colW, DESC_K)
	local nameH, lineH = round(nameSize * 1.2), round(descSize * 1.2)
	local nameCy, descCy
	if lines == 1 then -- the mockups set the block high in the row: name 18 above the centre, description 12.5 below (70 tall)
		nameCy, descCy = rowH / 2 - rowH * 18 / 70, rowH / 2 + rowH * 12.5 / 70
	else
		local top = (rowH - nameH - lines * lineH) / 2
		nameCy, descCy = top + nameH / 2, top + nameH + lines * lineH / 2
	end
	label(row, "Name", def.name, {
		size = nameSize,
		x = L.textLeft,
		y = nameCy,
		w = math.min(colW, Parts.measure(def.name, nameSize) + 6),
		h = nameH,
		ax = 0,
		z = z + 2,
		stroke = if L.compact then 2 else 2.8,
	})
	local desc = label(row, "Desc", def.desc, {
		size = descSize,
		x = L.textLeft,
		y = descCy,
		w = if lines == 1 then math.min(colW, Parts.measure(def.desc, descSize) * DESC_K + 6) else colW,
		h = lines * lineH,
		ax = 0,
		z = z + 2,
		stroke = 0.75,
	})
	desc.FontFace, desc.TextWrapped, desc.TextYAlignment = DESC_FONT, true, Enum.TextYAlignment.Center
	local handles = DRAW[def.kind](L, row, def, rowH, z, self._update, trackLeft)
	handles.Row = row
	self.Rows[def.id] = handles
	self._update[def.id](SettingsLogic.get(def.id))
end

-- Reset block -----------------------------------------------------------------------------------------------

-- A tapered flank line (transparent at its outer end), thickness 2.
local function flank(panel, name: string, x: number, w: number, cy: number, leftEnd: boolean)
	local f = make("Frame", {
		Name = name,
		BackgroundColor3 = FLANK,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(round(x), round(cy)),
		Size = UDim2.fromOffset(round(w), 3),
		ZIndex = panel.ZIndex + 2,
	}, panel)
	local fade = if leftEnd
		then { NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0), NumberSequenceKeypoint.new(1, 0) }
		else {
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.65, 0),
			NumberSequenceKeypoint.new(1, 1),
		}
	make("UIGradient", { Transparency = NumberSequence.new(fade) }, f)
end

local function drawReset(L, panel)
	local text = "RESET DEFAULTS"
	local w, h = math.min(L.resetW, L.panelW - 16), L.resetH
	local btn = make("ImageButton", {
		Name = "Reset",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(L.panelW / 2), round(L.resetCy)),
		Size = UDim2.fromOffset(round(w), round(h)),
		ZIndex = panel.ZIndex + 3,
	}, panel)
	Parts.skinH(btn, Shared.PillGrey, h) -- 3-slice pill (approved X2): height maps to the sprite height, caps never stretch
	Parts.interact(btn)
	local iconD = L.iconD
	local iw, ih = fitIn(S.RefreshWhite, iconD, iconD)
	local textW = math.min(Parts.measure(text, L.resetSize), w - iconD - 40)
	local gap = if L.compact then 8 else 16
	local x0 = (w - (iw + gap + textW)) / 2 -- icon and label centred as one group
	art(btn, S.RefreshWhite, x0 + iw / 2, h / 2, iw, ih, "Icon", btn.ZIndex + 1)
	label(btn, "Label", text, {
		size = fitted(text, L.resetSize, w - iconD - 40),
		x = x0 + iw + gap,
		y = h / 2,
		w = textW + 24,
		ax = 0,
		z = btn.ZIndex + 1,
		stroke = if L.compact then 2 else 2.5,
	})
	local room = L.panelW / 2 - w / 2 - 21 - 36
	if room >= 40 then
		flank(panel, "FlankL", 36, room, L.resetCy, true)
		flank(panel, "FlankR", L.panelW - 36 - room, room, L.resetCy, false)
	end
	return btn
end

function View:_build()
	local L = self._L
	K = L.K
	local root = self._root
	local keepY = if self._resetScroll then 0 else self._list and self._list.CanvasPosition.Y or 0
	self._resetScroll = false
	root:ClearAllChildren()
	table.clear(self.Rows)
	table.clear(self._update)
	if not L.compact and self._tab == "GRAPHICS" then
		L.tglFromRight = 140 -- the Graphics mockup sets its toggles 26 px left of the Gameplay ones
	end
	local defs = {}
	for _, def in SettingsLogic.DEFS do
		if def.tab == self._tab then
			table.insert(defs, def)
		end
	end
	local z = root.ZIndex
	local panel = Chrome.panel(root, {
		Name = "Panel",
		BackgroundColor3 = PANEL_FILL,
		Radius = 20,
		Rim = 2,
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.fromOffset(round(L.panelW), round(L.panelH)),
		ZIndex = z,
	})
	panel.UIStroke.Color = PANEL_RIM
	local list = make("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Color3.fromRGB(150, 150, 156),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		Active = true,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(round(L.panelW), round(L.listH)),
		ZIndex = z + 1,
	}, panel)
	self._list = list

	-- Row heights: a description that cannot fit one line at the minimum size wraps to a second line (the row grows to hold it).
	local n = #defs
	local rowH, gap = L.rowH, L.gap
	local avail = L.listH - 2 * L.top
	if not L.compact and n * rowH + (n - 1) * gap > avail then
		rowH, gap = 60, 9 -- Graphics: the mockup's 70 px pitch; the list ends exactly at the last row
	end
	local minSize = math.ceil(12 / K)
	local sliderEnd = 0
	for _, def in defs do
		if def.kind == "slider" then
			sliderEnd = math.max(sliderEnd, L.textLeft + Parts.measure(def.desc, L.descSize) * DESC_K)
		end
	end
	-- One track per tab: as long as the longest slider description leaves room for (max trackMax, min trackMin).
	local trackRight = L.rowW - L.pillRight - L.pillW - L.trackGap
	local trackLeft = math.clamp(sliderEnd + L.tgap + 12, trackRight - L.trackMax, trackRight - L.trackMin)
	local heights, lines, total = {}, {}, 0
	local function trackOf(def)
		return if L.compact then trackLeft else TRACK_LEFT[def.id] or trackLeft
	end
	for i, def in defs do
		local colW = controlLeft(L, def, trackOf(def)) - L.tgap - L.textLeft
		lines[i] = if Parts.measure(def.desc, math.max(minSize, L.descSize)) * DESC_K > colW * 0.98
				and fitted(def.desc, L.descSize, colW, DESC_K) <= minSize
			then 2
			else 1
		heights[i] = math.max(rowH, if lines[i] == 2 then round(L.nameSize * 1.2 + 2 * L.descSize * 1.2 + 8) else 0)
		total += heights[i] + (if i > 1 then gap else 0)
	end
	local canvasH = math.max(L.listH, L.top + total + (if L.compact then L.top else 0))
	local y = L.top + math.max(0, math.floor((L.listH - 2 * L.top - total) / 2)) -- centred while it fits
	if canvasH > L.listH then
		L.rowW -= 8 -- the scroll bar gets its own strip: it never touches a row
	end
	for i, def in defs do
		self:_drawRow(L, list, def, y, heights[i], lines[i], trackOf(def))
		y += heights[i] + gap
	end
	list.CanvasSize = UDim2.fromOffset(0, canvasH)
	list.CanvasPosition = Vector2.new(0, keepY)
	self.ResetButton = drawReset(L, panel)
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
