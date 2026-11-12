-- Play menu view: three columns (worlds | first-time milestones | repeat rewards + START) drawn inside the shared Bag shell's content slot.
-- Visual only. Design px under the shell's UIScale; the slot's Size offset and "Compact" attribute pick the layout.
-- View.new(slot) -> :SetWorlds(list) :SetSelected(id) :SetMilestones(rows, worldClear) :SetRepeat(tiles, odds)
--   :SetStartState("Ready"|"Busy"|"Disabled") :OnSelect(cb(id)) :OnLocked(cb(id)) :OnStart(cb()) :SetScroll(0) :Destroy()
-- worlds = PlayLogic.worlds, rows = PlayLogic.milestones, tiles / odds = SampleData.get().

local TextService = game:GetService("TextService")

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Bag.Parts)
local Draw = require(script.Parent.Parent.QuestLog.Draw)
local Sprites = require(script.Parent.Parent.Sprites)
local PlaySprites = require(script.Parent.PlaySprites)

local Q, Bag = Draw.Q, Draw.Bag
local make = UiKit.make

local WHITE = Color3.new(1, 1, 1)
local YELLOW = Color3.fromRGB(255, 242, 0)
local YELLOW_HEX = "#FDEA0A"
local GREY = Color3.fromRGB(205, 205, 215)
local RIM_WHITE = Color3.fromRGB(254, 219, 244)
local RIM_ORANGE = Color3.fromRGB(248, 130, 20)
local BAR_SLICE = Rect.new(19, 65, 22, 227) -- narrow centre column of Bag.ScrollTrack: no horizontal stretch
local BAR_W = 14

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function measure(str: string, size: number): number
	return TextService:GetTextSize(str, size, Enum.Font.FredokaOne, Vector2.new(1e5, 1e5)).X
end

local function rec(name: string)
	return PlaySprites[name] or Q[name]
end

-- Centre-anchored (or left-anchored with ax = 0) live text in a box; shrinks to fit w (never under min).
local function label(parent, o)
	local l = Parts.text(parent, {
		Name = o.Name or "Text",
		Text = o.Text,
		RichText = o.Rich,
		TextSize = o.Size,
		TextColor3 = o.Color,
		AnchorPoint = Vector2.new(o.AX or 0.5, 0.5),
		Position = UDim2.fromOffset(round(o.X), round(o.Y)),
		Size = UDim2.fromOffset(round(o.W), round(o.H or o.Size * 1.2)),
		TextXAlignment = if o.AX == 0 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		ZIndex = o.Z,
	}, o.Stroke or 3)
	l.TextSize = Parts.fitSize(o.Plain or o.Text, o.W, o.Size, o.Min or 12)
	return l
end

-- Sprite drawn by its ink centred at (cx, cy), fitted into maxW x maxH at its own aspect.
local function icon(parent, r, cx, cy, maxW, maxH, z)
	local img = Draw.img(parent, { Name = "Icon", ZIndex = z })
	local w, h = Draw.fitIn(r, maxW, maxH)
	return Draw.apply(img, r, cx, cy, w, h)
end

local function clear(parent)
	for _, c in parent:GetChildren() do
		if not c:IsA("UIBase") and not c:GetAttribute("Keep") then
			c:Destroy()
		end
	end
end

-- Draw.apply keeps the 9-slice rim at design size k.
local function skin(parent, r, cx, cy, w, h, k, z, name)
	local img = Draw.img(parent, { Name = name or "Skin", ZIndex = z })
	return Draw.apply(img, r, cx, cy, w, h, k)
end

local function barSkin(inst, name: string, w: number)
	local s = Bag[name]
	inst.Image = s.Image
	inst.ScaleType = Enum.ScaleType.Slice
	inst.SliceCenter = if name == "ScrollTrack" then BAR_SLICE else Rect.new(20, 37, 22, 133)
	inst.SliceScale = w / s.Size.X
end

local View = {}
View.__index = View

-- Layout --------------------------------------------------------------------------------------------------

local function compute(W: number, H: number, compact: boolean)
	local L = { W = W, H = H, compact = compact }
	if compact then
		L.gap = 5
		L.leftW = if W >= 700 then 216 else 172
		L.rightW = if W >= 700 then 240 else 172
		L.midW = W - L.leftW - L.rightW - 2 * L.gap
		L.midX = L.leftW + L.gap
		L.rightX = L.midX + L.midW + L.gap
		L.panelH = H
	else
		L.leftW = round(W * 0.301)
		L.midW = round(W * 0.378)
		L.rightW = W - L.leftW - L.midW - 15
		L.midX = L.leftW + 9
		L.rightX = L.midX + L.midW + 6
		L.panelH = H - 6
	end
	return L
end

-- Left column ----------------------------------------------------------------------------------------------

local function cardPill(card, wd, L, s, h)
	local compact = L.compact
	local pw, ph = round(264 * s), round(43 * s)
	local cx, cy = round(9 * s) + pw / 2, h - round(5 * s) - ph / 2
	local z = card.ZIndex
	skin(card, Bag.PillGreen, cx, cy, pw, ph, nil, z + 1, "BestPill")
	icon(card, Bag.IconCrown, cx - pw / 2 + 32 * s, cy, 36 * s, 28 * s, z + 2)
	local tx0 = 56 * s
	local avail = pw - tx0 - 10 * s
	local size = math.max(if compact then 18 else 12, round(24 * s))
	local plain = `BEST WAVE {wd.Best} / {wd.Waves}`
	local rich = `BEST WAVE <font color="{YELLOW_HEX}">{wd.Best}</font> / {wd.Waves}`
	if compact and measure(plain, size) > avail then
		plain = `BEST {wd.Best}/{wd.Waves}`
		rich = `BEST <font color="{YELLOW_HEX}">{wd.Best}</font>/{wd.Waves}`
	end
	label(card, {
		Name = "BestText",
		Text = rich,
		Plain = plain,
		Rich = true,
		Size = size,
		Min = if compact then 14 else 12,
		X = cx - pw / 2 + tx0 + avail / 2,
		Y = cy + 1,
		W = avail,
		H = ph,
		Stroke = 2,
		Z = z + 2,
	})
end

local function buildCard(self, host, wd, x, y, w, h, sel, crop, s, L)
	local art = PlaySprites[wd.Art]
	local card = Draw.img(host, {
		Name = "Card_" .. wd.Id,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		Image = art.Image,
		ImageRectOffset = crop.Min,
		ImageRectSize = Vector2.new(crop.Width, crop.Height),
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = host.ZIndex + 3,
	}, "ImageButton")
	make("UICorner", { CornerRadius = UDim.new(0, round(22 * s)) }, card)
	make("UIStroke", {
		Color = if sel then WHITE else RIM_WHITE,
		Thickness = if sel then 2 else 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, card)
	if sel then
		local g = if L.compact then 4 else 6
		local glow =
			skin(host, Q.CellSelected, x + w / 2, y + h / 2, w + 2 * g, h + 2 * g, 0.2, host.ZIndex + 2, "Glow")
		glow.Interactable = false
	end
	label(card, {
		Name = "Title",
		Text = wd.Name,
		Size = math.max(if L.compact then 20 else 14, round(32 * s)),
		Min = 14,
		AX = 0,
		X = if L.compact then 10 else round(30 * s),
		Y = round(12 * s) + 17 * s,
		W = round(300 * s),
		Z = card.ZIndex + 1,
		Stroke = 3,
	})
	cardPill(card, wd, L, s, h)
	if wd.Locked then
		local lw, lh = 39 * s, 46 * s
		local lock = icon(card, Bag.Lock, w - 34 * s, h - 53 * s, lw, lh, card.ZIndex + 1)
		lock.Name = "Padlock"
	end
	Parts.interact(card)
	card.Activated:Connect(function()
		if wd.Locked then
			if self._onLocked then
				self._onLocked(wd.Id)
			end
		elseif self._onSelect then
			self._onSelect(wd.Id)
		end
	end)
	return card
end

function View:_buildLeft()
	local L = self._L
	clear(self._leftFrame)
	clear(self._leftScroll)
	local worlds = self._worlds
	local compact = L.compact
	self._leftFrame.Visible = not compact
	self._leftScroll.Visible = compact
	local host = if compact then self._leftScroll else self._leftFrame
	if compact then
		local cw = L.leftW - 12
		local ch = round(cw / 2.45)
		local pitch = ch + 8
		for i, wd in worlds do
			buildCard(
				self,
				host,
				wd,
				4,
				4 + (i - 1) * pitch,
				cw - 4,
				ch,
				wd.Id == self._selected,
				PlaySprites[wd.Art].Card,
				cw / 363,
				L
			)
		end
		host.CanvasSize = UDim2.fromOffset(0, 8 + #worlds * pitch)
	else
		local s = L.leftW / 363
		local f = math.min(1, (L.panelH - 3) / 659) -- short windows squash the card heights (crop keeps the art's aspect)
		for i, wd in worlds do
			local sel = wd.Id == self._selected
			local top = round((22 + 163 * (i - 1)) * f)
			local h = round(148 * f)
			local art = PlaySprites[wd.Art]
			if sel then
				buildCard(
					self,
					host,
					wd,
					0,
					top - round(19 * f),
					L.leftW,
					round(168 * f),
					true,
					art.CardSel,
					math.min(s, f),
					L
				)
			else
				buildCard(self, host, wd, 0, top, L.leftW, h, false, art.Card, math.min(s, f), L)
			end
		end
	end
	self:_updateBars()
end

-- Middle column --------------------------------------------------------------------------------------------

local function rewardLines(row, lines, cx, cy, w, sizes, z)
	local total = 0
	for i = 1, #lines do
		total += sizes[i] + 2
	end
	local y = cy - total / 2
	for i, str in lines do
		local sz = sizes[i]
		label(row, {
			Name = "Reward" .. i,
			Text = str,
			Size = sz,
			Min = 12,
			X = cx,
			Y = y + (sz + 2) / 2,
			W = w,
			H = sz + 2,
			Stroke = 2,
			Z = z,
		})
		y += sz + 2
	end
end

local function buildRow(host, row, x, y, w, h, compact, f)
	local frame = Draw.img(host, {
		Name = "Row" .. row.Wave,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		ZIndex = host.ZIndex + 1,
	}, "Frame")
	skin(frame, Q.Row, w / 2, h / 2, w, h, nil, frame.ZIndex + 1, "Skin")
	local z = frame.ZIndex + 3
	local d = if compact then 30 else 46
	local circle = Draw.img(frame, { Name = "Status", ZIndex = z })
	Draw.apply(
		circle,
		if row.Reached then Q.CheckCircle else PlaySprites.LockCircle,
		if compact then 2 else -9,
		h / 2,
		d,
		d
	)
	local wsize = if compact then 18 else 27
	label(frame, {
		Name = "Wave",
		Text = "WAVE " .. row.Wave,
		AX = 0,
		Size = wsize,
		Min = if compact then 16 else 20,
		X = if compact then 20 else 32,
		Y = h / 2,
		W = if compact then 78 else 118,
		Z = z,
		Stroke = 3,
	})
	local ix, dx, tx, tw = 200 * f, 254 * f, 327 * f, 134 * f
	if compact then
		if w >= 220 then
			ix, dx = 118, 140
		else -- narrow phones: no reward icon, the lines get the room
			ix, dx = nil, 100
		end
		tw = w - dx - 12
		tx = dx + 6 + tw / 2
	end
	local ibox = if compact then 36 else 64
	if ix and row.Icon == "CrownGems" then
		icon(frame, Q.IconCrown, ix, h / 2 - (if compact then 6 else 9), ibox * 0.95, ibox * 0.75, z)
		for i = -1, 1 do
			local gem = Draw.img(frame, {
				Name = "Gem",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(
					round(ix + i * (ibox * 0.28)),
					round(h / 2 + ibox * (if compact then 0.28 else 0.35))
				),
				Size = UDim2.fromOffset(ibox * 0.28, ibox * 0.28),
				Image = Sprites.Gem,
				ZIndex = z,
			})
			gem.ScaleType = Enum.ScaleType.Fit
		end
	elseif ix then
		icon(frame, rec(row.Icon), ix, h / 2, ibox, ibox, z)
	end
	local div = Draw.img(frame, {
		Name = "Divider",
		Position = UDim2.fromOffset(round(dx), round(h / 2 - (if compact then 18 else 27))),
		Size = UDim2.fromOffset(3, if compact then 36 else 55),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.05,
		ZIndex = z,
	}, "Frame")
	div.BorderSizePixel = 0
	local sizes = if compact
		then (if #row.Lines >= 3 then { 17, 15, 15 } else { 19, 17 })
		else (if #row.Lines >= 3 then { 26, 19, 19 } else { 28, 20 })
	if h < 72 and not compact then
		for i, v in sizes do
			sizes[i] = math.floor(v * math.max(0.85, h / 72))
		end
	end
	rewardLines(frame, row.Lines, tx, h / 2, tw, sizes, z)
end

function View:_buildMid()
	local L = self._L
	local mid = self._mid
	clear(mid)
	clear(self._rowScroll)
	local compact, midW = L.compact, L.midW
	mid.Position = UDim2.fromOffset(L.midX, 0)
	mid.Size = UDim2.fromOffset(midW, L.H)
	local base = mid.ZIndex
	skin(mid, Bag.LeftPanel, midW / 2, L.panelH / 2, midW, L.panelH, 0.5, base + 1, "Panel")
	-- ribbon + trophies + title
	local rw, rh, rcy = if compact then midW - 20 else 400, if compact then 36 else 72, if compact then 24 else 50
	skin(mid, Q.DetailRibbon, midW / 2, rcy, rw, rh, nil, base + 2, "Ribbon")
	local tsz = if compact then (if midW < 250 then 24 else 28) else 46
	local tdx = rw / 2 - tsz / 2 - (if compact then 14 else 20)
	icon(mid, Q.IconTabTrophy, midW / 2 - tdx, rcy - 1, tsz, tsz, base + 3)
	icon(mid, Q.IconTabTrophy, midW / 2 + tdx, rcy - 1, tsz, tsz, base + 3)
	local avail = 2 * tdx - tsz - 16
	local title, tsize = "FIRST-TIME MILESTONES", if compact then 18 else 28
	if compact and measure(title, tsize) > avail then
		title = "MILESTONES"
	end
	label(mid, {
		Name = "RibbonText",
		Text = title,
		Size = tsize,
		Min = 17,
		X = midW / 2,
		Y = rcy - 1,
		W = avail,
		Z = base + 4,
	})

	-- rows
	local rows = self._rows
	if compact then
		local sy, sh = 2 * rcy + 6, L.H - (2 * rcy + 6) - 62
		local scroll = self._rowScroll
		scroll.Visible = true
		local lead = if midW < 250 then 26 else 34
		scroll.Position = UDim2.fromOffset(lead, sy)
		scroll.Size = UDim2.fromOffset(midW - lead - 18, sh)
		scroll.ZIndex = base + 2
		local rowW, rowH, pitch = midW - lead - 18 - 14, 52, 58
		for i, row in rows do
			buildRow(scroll, row, 14, 4 + (i - 1) * pitch, rowW, rowH, true, 1)
		end
		scroll.CanvasSize = UDim2.fromOffset(0, 8 + #rows * pitch)
	else
		self._rowScroll.Visible = false
		local rowW = midW - 61
		local g = math.min(1, L.panelH / 673)
		for i, row in rows do
			buildRow(mid, row, 48, round((93 + 81.8 * (i - 1)) * g), rowW, round(72 * g), false, rowW / 395)
		end
	end

	-- WORLD CLEAR pill + sparkles
	local clearOn = self._worldClear
	local pw, ph = if compact then math.min(midW - 70, 176) else 309, if compact then 44 else 58
	local pcx, pcy = midW / 2, if compact then L.H - 30 else round(622 * math.min(1, L.panelH / 673))
	skin(mid, if clearOn then Bag.PillGold else Bag.PillGrey, pcx, pcy, pw, ph, nil, base + 3, "WorldClear")
	label(mid, {
		Name = "Text",
		Text = "WORLD CLEAR",
		Size = if compact then 22 else 37,
		Min = if compact then 17 else 20,
		Color = if clearOn then YELLOW else GREY,
		X = pcx,
		Y = pcy - 1,
		W = pw - (if compact then 24 else 60),
		Z = base + 4,
	})
	local sx = pw / 2 + (if compact then 12 else 22)
	for sgn = -1, 1, 2 do
		icon(mid, Q.Sparkle1, pcx + sgn * sx, pcy + 2, if compact then 18 else 28, if compact then 18 else 28, base + 3)
		if not compact then
			icon(mid, Q.Sparkle3, pcx + sgn * (sx - 6), pcy - 24, 14, 14, base + 3)
			icon(mid, Q.Sparkle3, pcx + sgn * (sx - 6), pcy + 20, 14, 14, base + 3)
		end
	end
	self:_updateBars()
end

-- Right column ---------------------------------------------------------------------------------------------

local function oddsText(line)
	local plain, rich = {}, {}
	for _, tok in line do
		table.insert(plain, tok)
		table.insert(rich, if tok:find("%%") then `<font color="{YELLOW_HEX}">{tok}</font>` else tok)
	end
	return table.concat(plain, " "), table.concat(rich, " ")
end

function View:_buildRight()
	local L = self._L
	local col = self._right
	clear(col)
	local compact, rw = L.compact, L.rightW
	local P, ohFull, thFull = 209, 144, 101 -- short windows (small desktops) shrink the preview first, then odds, then tiles
	if not compact then
		local deficit = math.max(0, P + 442 - L.panelH)
		local cut = math.min(deficit, 59)
		P -= cut
		deficit -= cut
		cut = math.min(deficit, 30)
		ohFull -= cut
		deficit -= cut
		thFull -= math.min(deficit, 15)
	end
	col.Position = UDim2.fromOffset(L.rightX, 0)
	col.Size = UDim2.fromOffset(rw, L.H)
	local base = col.ZIndex
	local y = 0
	if not compact then
		local wd
		for _, w in self._worlds do
			if w.Id == self._selected then
				wd = w
			end
		end
		wd = wd or self._worlds[1]
		if wd then
			local art = PlaySprites[wd.Art]
			local pv = Draw.img(col, {
				Name = "Preview",
				Size = UDim2.fromOffset(rw, P),
				Image = art.Image,
				ImageRectOffset = art.Preview.Min,
				ImageRectSize = Vector2.new(art.Preview.Width, art.Preview.Height),
				ScaleType = Enum.ScaleType.Crop,
				ZIndex = base + 1,
			})
			make("UICorner", { CornerRadius = UDim.new(0, 22) }, pv)
			make("UIStroke", { Color = RIM_ORANGE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pv)
		end
		y = P + 17
	end
	-- ribbon
	local rh = if compact then 32 else 56
	local rcy = y + rh / 2
	skin(col, Q.DetailRibbon, rw / 2, rcy, rw, rh, nil, base + 1, "Ribbon")
	label(col, {
		Name = "RibbonText",
		Text = if compact then "REPEAT REWARDS" else "REPEAT REWARDS \u{2022} EVERY 10 WAVES",
		Size = if compact then 18 else 22,
		Min = if compact then 17 else 14,
		X = rw / 2,
		Y = rcy - 1,
		W = rw - (if compact then 44 else 70),
		Z = base + 3,
		Stroke = 2,
	})
	y += rh + (if compact then 5 else 4)

	-- tiles
	local tiles = self._tiles
	local tw, th, tgap = 88, thFull, 6
	local cols = 4
	if compact then
		cols = 2
		tgap = 6
		tw, th = round((rw - tgap) / 2), 56
	end
	for i, tile in tiles do
		local c, r = (i - 1) % cols, (i - 1) // cols
		local tx, ty = c * (tw + tgap) + (if compact then 0 else 1), y + r * (th + tgap)
		local box = Draw.img(col, {
			Name = "Tile" .. i,
			Position = UDim2.fromOffset(tx, ty),
			Size = UDim2.fromOffset(tw, th),
			ZIndex = base + 1,
		}, "Frame")
		skin(box, PlaySprites.PurpleBox, tw / 2, th / 2, tw, th, if compact then 0.2 else 0.3, box.ZIndex + 1, "Skin")
		local hh = if compact then 22 else 25
		skin(box, Bag.PillPurple, tw / 2, hh / 2 + 3, tw - 8, hh, nil, box.ZIndex + 2, "Header")
		label(box, {
			Name = "Label",
			Text = tile.Label,
			Size = if compact then 17 else 19,
			Min = if compact then 13 else 11,
			X = tw / 2,
			Y = hh / 2 + 3,
			W = tw - 18,
			Stroke = 2,
			Z = box.ZIndex + 3,
		})
		local iy = hh + 3 + (th - hh - 3) / 2
		icon(box, rec(tile.Icon), tw / 2, iy, if compact then 34 else 58, if compact then 28 else 58, box.ZIndex + 2)
	end
	local rowsN = (#tiles + cols - 1) // cols
	y += rowsN * th + (rowsN - 1) * tgap + (if compact then 6 else 15)

	-- odds
	local oh = if compact then 98 else ohFull
	local odds = Draw.img(col, {
		Name = "Odds",
		Position = UDim2.fromOffset(if compact then 0 else 1, y),
		Size = UDim2.fromOffset(if compact then rw else rw - 2, oh),
		ZIndex = base + 1,
	}, "Frame")
	local ow = rw - (if compact then 0 else 2)
	skin(odds, PlaySprites.PurpleBox, ow / 2, oh / 2, ow, oh, 0.4, odds.ZIndex + 1, "Skin")
	local z = odds.ZIndex + 3
	local dieS = if compact then 52 else 90
	local dieX = if compact then 36 else 73
	icon(odds, Q.IconGalaxyDie, dieX, oh / 2 + 2, dieS, dieS, z)
	icon(
		odds,
		Q.Sparkle2,
		dieX - dieS / 2 + 2,
		oh / 2 - dieS * 0.12,
		if compact then 14 else 22,
		if compact then 14 else 22,
		z + 1
	)
	local dvx = if compact then 68 else 140
	local div = Draw.img(odds, {
		Name = "Divider",
		Position = UDim2.fromOffset(dvx, round(oh * 0.12)),
		Size = UDim2.fromOffset(if compact then 3 else 4, round(oh * 0.76)),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.05,
		ZIndex = z,
	}, "Frame")
	div.BorderSizePixel = 0
	local lines = self._odds
	local textCx = (dvx + 4 + ow - 6) / 2
	local textW = ow - 6 - (dvx + 8)
	local ys, sizes
	if compact then
		local n = math.min(#lines, 4)
		lines = { table.unpack(lines, 1, n) }
		ys, sizes = {}, {}
		for i = 1, n do
			ys[i] = oh / 2 + (i - (n + 1) / 2) * 21
			sizes[i] = 18
		end
	elseif #lines == 5 then
		ys, sizes = { 18, 46, 75, 103, 128 }, { 25, 25, 25, 22, 21 }
		for i = 1, 5 do
			ys[i] = ys[i] * oh / 144
		end
	else
		ys, sizes = {}, {}
		for i = 1, #lines do
			ys[i] = oh / 2 + (i - (#lines + 1) / 2) * 30
			sizes[i] = 25
		end
	end
	for i, line in lines do
		local plain, rich = oddsText(line)
		label(odds, {
			Name = "Line" .. i,
			Text = rich,
			Plain = plain,
			Rich = true,
			Size = sizes[i],
			Min = if compact then 14 else 12,
			X = textCx,
			Y = ys[i],
			W = textW,
			H = sizes[i] + 2,
			Stroke = 2,
			Z = z,
		})
	end
	y += oh + (if compact then 10 else 15)

	-- START
	local sw, sh = if compact then rw else 334, if compact then 58 else 90
	local bw, bh = Parts.inkBox("BtnGreen", sw, sh)
	local scy = if compact then math.min(L.H - sh / 2 - 2, y + sh / 2) else y + sh / 2
	local btn = Parts.button(col, {
		Name = "Start",
		Style = "Green",
		Label = "START",
		TextSize = if compact then 28 else 48,
		Icon = PlaySprites.PlayArrow,
		Size = UDim2.fromOffset(round(bw), round(bh)),
		Enabled = self._startState == "Ready",
	})
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.fromOffset(round(rw / 2), round(scy))
	self._startBtn = btn
	btn.Activated:Connect(function()
		if self._startState == "Ready" and self._onStart then
			self._onStart()
		end
	end)
	for sgn = -1, 1, 2 do
		icon(
			col,
			Q.Sparkle1,
			rw / 2 + sgn * (sw / 2 + 2 - (if compact then 10 else 6)),
			scy - sh * 0.3,
			20,
			20,
			base + 5
		)
		icon(col, Q.Sparkle1, rw / 2 + sgn * (sw / 2 + 2 - (if compact then 6 else 0)), scy + 4, 22, 22, base + 5)
	end
end

-- Scroll bars ----------------------------------------------------------------------------------------------

local function makeBar(holder, scroll)
	local track = Draw.img(holder, { Name = "ScrollTrack", AnchorPoint = Vector2.new(1, 0), Visible = false })
	track:SetAttribute("Keep", true)
	barSkin(track, "ScrollTrack", BAR_W)
	local thumb = Draw.img(track, { Name = "Thumb", ZIndex = track.ZIndex + 1 })
	return function()
		local win, maxY =
			scroll.AbsoluteWindowSize.Y, math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
		local h = scroll.Size.Y.Offset
		track.Visible = scroll.Visible and maxY > 1 and h > 0
		track.ZIndex = scroll.ZIndex + 3
		track.Position =
			UDim2.fromOffset(scroll.Position.X.Offset + scroll.Size.X.Offset + BAR_W, scroll.Position.Y.Offset)
		track.Size = UDim2.fromOffset(BAR_W, h)
		local canvas = math.max(1, scroll.AbsoluteCanvasSize.Y)
		local thumbH = math.clamp(math.floor(h * win / canvas), 40, math.max(40, h))
		Draw.thumb(
			thumb,
			BAR_W,
			thumbH,
			math.floor((h - thumbH) * (if maxY > 0 then scroll.CanvasPosition.Y / maxY else 0))
		)
	end
end

function View:_updateBars()
	for _, fn in self._bars do
		fn()
	end
end

-- Public ---------------------------------------------------------------------------------------------------

local function newScroll(parent, name)
	return make("ScrollingFrame", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		ScrollBarImageTransparency = 1,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
		ZIndex = parent.ZIndex + 1,
	}, parent)
end

function View.new(slot)
	local self = setmetatable({}, View)
	self._conns = {}
	self._worlds, self._selected, self._rows, self._worldClear = {}, nil, {}, false
	self._tiles, self._odds, self._startState = {}, {}, "Disabled"
	local root = make(
		"Frame",
		{ Name = "PlayView", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = slot.ZIndex + 1 },
		slot
	)
	self._root = root
	local function column(name)
		return make("Frame", { Name = name, BackgroundTransparency = 1, ZIndex = root.ZIndex + 1 }, root)
	end
	self._leftCol, self._mid, self._right = column("Left"), column("Mid"), column("Right")
	self._leftFrame = make(
		"Frame",
		{ Name = "Cards", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = self._leftCol.ZIndex + 1 },
		self._leftCol
	)
	self._leftScroll = newScroll(self._leftCol, "CardScroll")
	self._leftScroll.Size = UDim2.fromScale(1, 1)
	self._rowScroll = newScroll(self._mid, "RowScroll")
	self._rowScroll:SetAttribute("Keep", true)
	self._bars = { makeBar(self._leftCol, self._leftScroll), makeBar(self._mid, self._rowScroll) }
	for _, sf in { self._leftScroll, self._rowScroll } do
		table.insert(
			self._conns,
			sf:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
				self:_updateBars()
			end)
		)
		table.insert(
			self._conns,
			sf:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
				self:_updateBars()
			end)
		)
	end
	local pending = false
	local function relayout()
		local W, H = slot.Size.X.Offset, slot.Size.Y.Offset
		if W <= 0 or H <= 0 or pending then
			return
		end
		pending = true
		task.defer(function() -- Size and the Compact attribute change together in one Fit: build once
			pending = false
			if not self._root.Parent then
				return
			end
			local w, h = slot.Size.X.Offset, slot.Size.Y.Offset
			local compact = slot:GetAttribute("Compact") == true
			local L = self._L
			if L and L.W == w and L.H == h and L.compact == compact then
				return
			end
			self._L = compute(w, h, compact)
			self._leftCol.Size = UDim2.fromOffset(self._L.leftW, h)
			self._leftScroll.Position = UDim2.fromOffset(0, 0)
			self._leftScroll.Size = UDim2.fromOffset(self._L.leftW - BAR_W, h)
			self:_buildAll()
		end)
	end
	table.insert(self._conns, slot:GetPropertyChangedSignal("Size"):Connect(relayout))
	table.insert(self._conns, slot:GetAttributeChangedSignal("Compact"):Connect(relayout))
	relayout()
	return self
end

function View:_buildAll()
	if not self._L then
		return
	end
	self:_buildLeft()
	self:_buildMid()
	self:_buildRight()
end

function View:SetWorlds(list)
	self._worlds = list
	if self._L then
		self:_buildLeft()
		self:_buildRight()
	end
end

function View:SetSelected(id: string?)
	if self._selected == id then
		return
	end
	self._selected = id
	if self._L then
		self:_buildLeft()
		self:_buildRight()
	end
end

function View:SetMilestones(rows, worldClear: boolean?)
	self._rows, self._worldClear = rows, worldClear == true
	if self._L then
		self:_buildMid()
	end
end

function View:SetRepeat(tiles, odds)
	self._tiles, self._odds = tiles, odds
	if self._L then
		self:_buildRight()
	end
end

function View:SetStartState(state: string)
	self._startState = state
	if self._startBtn and self._startBtn.Parent then
		Parts.setButton(self._startBtn, { Enabled = state == "Ready" })
	end
end

function View:OnSelect(cb)
	self._onSelect = cb
end

function View:OnLocked(cb)
	self._onLocked = cb
end

function View:OnStart(cb)
	self._onStart = cb
end

function View:SetScroll(y: number)
	self._leftScroll.CanvasPosition = Vector2.new(0, y)
	self._rowScroll.CanvasPosition = Vector2.new(0, y)
end

function View:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	self._root:Destroy()
end

return View
