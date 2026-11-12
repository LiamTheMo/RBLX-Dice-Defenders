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
local WARM = Color3.fromRGB(255, 230, 170) -- sparkle tint
local RIM_WHITE = Color3.fromRGB(254, 219, 244)
local RIM_ORANGE = Color3.fromRGB(248, 130, 20)
local BAR = { ScrollTrack = Rect.new(19, 65, 22, 227), ScrollThumb = Rect.new(20, 37, 22, 133) } -- narrow centre columns: no horizontal stretch
local BAR_W = 10 -- track box; the Bag's sprites draw an 8 px ink bar at this width (the Bag's phone scrollbar)
local ASP = 79 / 391 -- DetailRibbon ink aspect (h / w): ribbons keep it, never stretched

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function measure(str: string, size: number): number
	return TextService:GetTextSize(str, size, Enum.Font.FredokaOne, Vector2.new(1e5, 1e5)).X
end

-- A-15: TextSize = min(size for the reference cap height, size whose ink width equals the reference ink width); these are the reference ink widths (ref px).
local TITLE_REF = { ["DICE KINGDOM"] = 213, ["FROST PEAKS"] = 192, ["MAGMA CITADEL"] = 239, ["SHADOW REALM"] = 233 }
local REW_REF = {
	["+250"] = 55,
	["+3"] = 27,
	["+1"] = 20,
	CRYSTALS = 79,
	["LUCK POTIONS"] = 122,
	["TREASURE CHEST"] = 121,
	EXCLUSIVE = 82,
	BANNER = 62,
	["RARE DIE"] = 78,
	["CROWN COSMETIC"] = 129,
	["+5,000 GEMS"] = 100,
}
local function titleSize(s: number): number -- one size for every card title: the tightest of the four ref widths
	local m = 40 * s
	for name, ref in TITLE_REF do
		m = math.min(m, ref * s * 100 / measure(name, 100))
	end
	return math.floor(m)
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
	l.TextSize = Parts.fitSize(o.Plain or o.Text, o.Fit or o.W * 0.95, o.Size, o.Min or 12) -- 5% spare: hinting at fractional UI scales widens text
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

-- Opaque white divider (Draw.img forces a clear background, which hid the old ones).
local function divider(parent, x: number, y: number, w: number, h: number, z: number)
	return make("Frame", {
		Name = "Divider",
		Position = UDim2.fromOffset(round(x), round(y)),
		Size = UDim2.fromOffset(w, round(h)),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
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
	inst.SliceCenter = BAR[name]
	inst.SliceScale = w / s.Size.X
end

local View = {}
View.__index = View

-- Layout --------------------------------------------------------------------------------------------------

local function compute(W: number, H: number, compact: boolean)
	local L = { W = W, H = H, compact = compact }
	if compact then
		L.gap = 5
		L.leftW = if W >= 700 then 216 else 164 -- 18 px labels need: titles 136, tile headers 94
		L.rightW = if W >= 700 then 240 else 206
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

local function cardPill(card, wd, L, s, w, h)
	local compact = L.compact
	local pw, ph = round(257 * s), round(43 * s) -- ink 266 draws ~275 visible: 257 lands the visible pill on the ref 266
	local cx, cy = round(8 * s) + pw / 2, h - round(5 * s) - ph / 2
	if compact then
		pw, ph = w - 16 - (if wd.Locked then 30 else 0), 26 -- a locked card keeps its padlock beside the pill
		cx, cy = 8 + pw / 2, h - 5 - ph / 2
	end
	local z = card.ZIndex
	skin(card, Bag.PillGreen, cx, cy, pw, ph, nil, z + 1, "BestPill")
	local crown = not compact or pw >= 150 -- narrowest phones drop the crown so the 18 px text fits
	local tx0 = if crown then 56 * s else 12
	if crown then
		icon(card, Bag.IconCrown, cx - pw / 2 + 32 * s, cy, 36 * s, 28 * s, z + 2)
	end
	local avail = pw - tx0 - (if compact then 12 else 10 * s)
	local size = if compact then 18 else round(25 * s)
	local num = if wd.Best == "--" then wd.Best else `<font color="{YELLOW_HEX}">{wd.Best}</font>`
	local plain = `BEST WAVE {wd.Best} / {wd.Waves}`
	local rich = `BEST WAVE {num} / {wd.Waves}`
	if compact and measure(plain, size) > avail then
		plain = `BEST {wd.Best}/{wd.Waves}`
		rich = `BEST {num}/{wd.Waves}`
	end
	if compact and measure(plain, size) > avail then
		plain = `{wd.Best}/{wd.Waves}`
		rich = `{num}/{wd.Waves}`
	end
	label(card, {
		Name = "BestText",
		Text = rich,
		Plain = plain,
		Rich = true,
		Size = size,
		Min = if compact then 18 else 12,
		X = cx - pw / 2 + tx0 + avail / 2,
		Y = cy,
		W = avail,
		H = ph,
		Stroke = 2,
		Z = z + 2,
	})
end

local GLOW_K = 0.56 -- CellSelected: ~22 sprite px of glow outside its bright line -> ~12 px bloom outside the card edge
local CARD_L, CARD_R = 8, 4 -- the 12 px glow then ends on the window's inner rim (never clipped) and 2 px short of the mid panel

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
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, card)
	if sel then
		local g = if L.compact then 5 else 12
		local gr = g
		local k = if L.compact then 0.3 else GLOW_K
		local glow = skin(host, Q.CellSelected, x + w / 2, y + h / 2, w + g + gr, h + 2 * g, k, host.ZIndex + 2, "Glow")
		glow.Interactable = false
	end
	label(card, {
		Name = "Title",
		Text = wd.Name,
		Size = if L.compact then 20 else titleSize(s), -- A-15: min(cap 23, ref ink width) = 33 at 1672
		Min = if L.compact then 18 else 14,
		AX = 0,
		X = if L.compact then 8 else 12,
		Y = if L.compact then 15 else round(12 * s) + 17 * s,
		W = if L.compact then w - 12 else w - 16,
		Z = card.ZIndex + 1,
		Stroke = 3,
	})
	cardPill(card, wd, L, s, w, h)
	if wd.Locked then
		-- right of the BEST pill (never over it or the art's die / castle); phones have no room: top-right corner
		local lock
		if L.compact then
			lock = icon(card, Bag.Lock, w - 20, h - 18, 20, 24, card.ZIndex + 1)
		else
			lock = icon(card, Bag.Lock, w - 24 * s, h - 24 * s, 27 * s, 32 * s, card.ZIndex + 1)
		end
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

local CARD_H = { 148, 148, 149, 144 } -- reference card heights (unselected); the selected one is 168 and grows upward

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
		local ch = math.max(62, round(cw / 2.45))
		local pitch = ch + 8
		local y0 = 4 + math.max(0, (L.H - (8 + #worlds * pitch)) // 2) -- short lists centre in the column
		for i, wd in worlds do
			buildCard(
				self,
				host,
				wd,
				4,
				y0 + (i - 1) * pitch,
				cw - 4,
				ch,
				wd.Id == self._selected,
				PlaySprites[wd.Art].Card,
				cw / 363,
				L
			)
		end
		host.CanvasSize = UDim2.fromOffset(0, math.max(8 + #worlds * pitch, 0))
	else
		local s = L.leftW / 363
		local f = math.min(1, (L.panelH - 3) / 659) -- short windows squash the card heights (crop keeps the art's aspect)
		local tops = { 22, 184, 347, 510 }
		for i, wd in worlds do
			local sel = wd.Id == self._selected
			local top = round(tops[i] * f)
			local h = round(CARD_H[i] * f)
			local art = PlaySprites[wd.Art]
			if sel then
				buildCard(
					self,
					host,
					wd,
					CARD_L,
					top - round(20 * f),
					L.leftW - CARD_L - CARD_R,
					round(168 * f),
					true,
					art.CardSel,
					math.min(s, f),
					L
				)
			else
				buildCard(self, host, wd, CARD_L, top, L.leftW - CARD_L - CARD_R, h, false, art.Card, math.min(s, f), L)
			end
		end
	end
	self:_updateBars()
end

-- Middle column --------------------------------------------------------------------------------------------

-- Per-icon fit boxes (ref ink sizes); the sprite keeps its own aspect inside the box.
local ICON_BOX = {
	IconCrystals = { 67, 59 },
	Potion = { 60, 62 },
	IconChest = { 84, 62 },
	RewardBanner = { 105, 58 },
	IconGalaxyDie = { 68, 68 },
}

local function rewardLines(row, lines, cx, cy, w, sizes, z)
	local total = 0
	for i = 1, #lines do
		total += sizes[i] + 1
	end
	local y = cy - total / 2 - 2 -- caps sit ~2 px low in their em box: keep >= 5 px clear of the rim top and bottom
	for i, str in lines do
		local sz = sizes[i]
		label(row, {
			Name = "Reward" .. i,
			Text = str,
			Size = sz,
			Min = 12,
			Fit = REW_REF[str],
			X = cx,
			Y = y + (sz + 1) / 2,
			W = w + 16, -- wider than the 126 text column so a ref-width line (CROWN COSMETIC 129) never truncates
			H = sz + 2,
			Stroke = 2,
			Z = z,
		})
		y += sz + 1
	end
end

-- Phone rows stack "WAVE n" over the reward, wrapped at 18 px so nothing truncates.
local function compactLines(row, avail: number): { string }
	local src, rew = row.Lines, {}
	local from = 1
	if #src >= 2 and src[1]:sub(1, 1) == "+" and measure(src[1], 18) < 60 then
		rew[1] = src[1] .. " " .. src[2]
		from = 3
	end
	for j = from, #src do
		table.insert(rew, src[j])
	end
	if measure(table.concat(rew, " "), 18) <= avail then
		return { table.concat(rew, " ") }
	end
	local out = {}
	for _, l in rew do
		local at, best = nil, 1e9
		if measure(l, 18) > avail then
			for pos in l:gmatch("()%s") do
				local d = math.abs(pos - #l / 2)
				if d < best then
					at, best = pos, d
				end
			end
		end
		if at then
			table.insert(out, l:sub(1, at - 1))
			table.insert(out, l:sub(at + 1))
		else
			table.insert(out, l)
		end
	end
	return out
end

local function compactRowH(row, rowW: number): number
	return math.max(48, 16 + 20 * (1 + #compactLines(row, rowW - 34)))
end

local function buildRow(host, row, x, y, w, h, compact, f)
	local frame = Draw.img(host, {
		Name = "Row" .. row.Wave,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		ZIndex = host.ZIndex + 1,
	}, "Frame")
	-- the Row sprite's ink includes ~3.7 sprite px of dark outer line each side: draw the ink bigger so the VISIBLE rim fills the row box (ref 397x72)
	skin(
		frame,
		Q.Row,
		w / 2,
		h / 2,
		w + (if compact then 0 else 7),
		h + (if compact then 0 else 7),
		nil,
		frame.ZIndex + 1,
		"Skin"
	)
	local z = frame.ZIndex + 3
	local d = if compact then 32 else 46
	local circle = Draw.img(frame, { Name = "Status", ZIndex = z })
	local cx = if compact then 2 else -10
	local ring = if row.Reached then 3 else 0 -- gold ring (#FDF201) round the checked circle; the circle shrinks so the total stays d
	if not compact then
		d = if row.Reached then 45 else 42.5 -- measured: the check draws ~2 over, the lock ~5 over its ink size; both land on ~47
	end
	Draw.apply(
		circle,
		if row.Reached then Q.CheckCircle else PlaySprites.LockCircle,
		cx,
		h / 2,
		d - 2 * ring,
		d - 2 * ring
	)
	if ring > 0 then
		local rf = make("Frame", {
			Name = "Ring",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, round(h / 2)),
			Size = UDim2.fromOffset(d - 2 * ring, d - 2 * ring),
			BackgroundTransparency = 1,
			ZIndex = z + 1,
		}, frame)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, rf)
		make(
			"UIStroke",
			{ Color = Color3.fromRGB(253, 242, 1), Thickness = ring, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
			rf
		)
	end
	if compact then
		local avail = w - 34
		local lines = compactLines(row, avail)
		local y0 = h / 2 - (1 + #lines) * 10
		label(frame, {
			Name = "Wave",
			Text = "WAVE " .. row.Wave,
			AX = 0,
			Size = 20,
			Min = 18,
			X = 24,
			Y = y0 + 10,
			W = avail,
			H = 20,
			Z = z,
			Stroke = 3,
		})
		for i, str in lines do
			label(frame, {
				Name = "Reward" .. i,
				Text = str,
				AX = 0,
				Size = 18,
				Min = 18,
				X = 24,
				Y = y0 + 10 + 20 * i,
				W = avail,
				H = 20,
				Z = z,
				Stroke = 2,
			})
		end
		return
	end
	label(frame, {
		Name = "Wave",
		Text = "WAVE " .. row.Wave,
		AX = 0,
		Size = 24, -- A-15: ref "WAVE 10" ink is 89 wide, which FredokaOne reaches at size 25 (cap 38 would be 2x too wide)
		Min = 12,
		X = 24,
		Y = h / 2,
		W = 132,
		Z = z,
		Stroke = 3,
	})
	local ix, dx, tx, tw = 192 * f, 250 * f, 323 * f, 126 * f
	local box = ICON_BOX[row.Icon] or { 67, 59 }
	if row.Icon == "CrownGems" then
		icon(frame, Q.IconCrown, ix, h / 2 - 8, 84, 62, z)
		for i = -1, 1 do
			local gem = Draw.img(frame, {
				Name = "Gem",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(round(ix + i * 27), round(h / 2 + 26)),
				Size = UDim2.fromOffset(26, 26),
				Image = Sprites.Gem,
				ZIndex = z + 1,
			})
			gem.ScaleType = Enum.ScaleType.Fit
		end
	else
		icon(frame, rec(row.Icon), ix, h / 2, box[1], box[2], z)
	end
	divider(frame, dx, h / 2 - 27.5, 4, 55, z)
	local sizes = if #row.Lines >= 3 then { 24, 18, 18 } else { 26, 20 }
	if h < 72 then
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
	if compact then
		skin(mid, Bag.LeftPanel, midW / 2, L.panelH / 2, midW, L.panelH, 0.5, base + 1, "Panel")
	else
		skin(mid, Bag.LeftPanel, midW / 2 - 2, L.panelH / 2 - 1, midW + 2, L.panelH, 0.5, base + 1, "Panel")
	end
	-- ribbon (kept at its own aspect; the body is its top 76%) + trophies + title
	local rw = if compact then midW - 20 else 392
	local rh = round(rw * ASP)
	local rtop = if compact then 6 else 12
	local bodyCy = rtop + rh * 0.38
	skin(mid, Q.DetailRibbon, midW / 2, rtop + rh / 2, rw, rh, nil, base + 2, "Ribbon")
	local tsz = if compact then (if midW < 250 then 24 else 28) else 40
	local tdx = if compact then rw / 2 - tsz / 2 - 8 else 160 -- full: the trophies sit inside the ribbon body ends
	local tcy = bodyCy + 2
	icon(mid, Q.IconTabTrophy, midW / 2 - tdx, tcy, tsz, tsz, base + 3)
	icon(mid, Q.IconTabTrophy, midW / 2 + tdx, tcy, tsz, tsz, base + 3)
	local avail = 2 * tdx - tsz - (if compact then 10 else 4)
	local title, tsize = "FIRST-TIME MILESTONES", if compact then 18 else 26 -- A-15: ref ink 273 wide = size 26.8
	if compact and measure(title, tsize) > avail then
		title = "MILESTONES"
	end
	label(mid, {
		Name = "RibbonText",
		Text = title,
		Size = tsize,
		Min = if compact then 18 else 12,
		X = midW / 2,
		Y = bodyCy + 1,
		W = avail,
		Z = base + 4,
	})

	-- rows
	local rows = self._rows
	if compact then
		local sy = rtop + rh + 4
		local sh = L.H - sy - 62
		local scroll = self._rowScroll
		scroll.Visible = true
		local lead = if midW < 250 then 26 else 34
		local rowW = midW - lead - 22 - 16
		local used = 4 -- the window ends on a whole row so no half row shows under WORLD CLEAR
		for _, row in rows do
			local nxt = used + compactRowH(row, rowW) + 6
			if nxt - 6 + 2 > sh then
				break
			end
			used = nxt
		end
		sh = math.min(sh, math.max(used - 6 + 2, compactRowH(rows[1] or { Lines = {} }, rowW) + 6))
		scroll.Position = UDim2.fromOffset(lead, sy)
		scroll.Size = UDim2.fromOffset(midW - lead - 22, sh)
		scroll.ZIndex = base + 2
		local y = 4
		for _, row in rows do
			local h = compactRowH(row, rowW)
			buildRow(scroll, row, 14, y, rowW, h, true, 1)
			y += h + 6
		end
		scroll.CanvasSize = UDim2.fromOffset(0, y + 2)
	else
		self._rowScroll.Visible = false
		local rowW = midW - 59
		local g = math.min(1, L.panelH / 673)
		local tops = { 92, 173, 254, 335, 418, 501 }
		for i, row in rows do
			buildRow(mid, row, 46, round(tops[i] * g), rowW, round(72 * g), false, rowW / 397)
		end
	end

	-- WORLD CLEAR pill + sparkles
	local clearOn = self._worldClear
	local pw, ph = if compact then math.min(midW - 70, 176) else 309, if compact then 44 else 58
	local pcx = midW / 2 + (if compact then 0 else 1.5)
	local pcy = if compact then L.H - 30 else round(621 * math.min(1, L.panelH / 673))
	skin(mid, if clearOn then Bag.PillGold else Bag.PillGrey, pcx, pcy, pw, ph, nil, base + 3, "WorldClear")
	label(mid, {
		Name = "Text",
		Text = "WORLD CLEAR",
		Size = if compact then 22 else 39, -- A-15: ref ink 240 wide = size 39.8 (cap 47)
		Min = if compact then 18 else 12,
		Fit = if compact then nil else 240,
		Color = if clearOn then YELLOW else GREY,
		X = pcx,
		Y = pcy - 1,
		W = pw - (if compact then 24 else 60),
		Z = base + 4,
	})
	local sx = pw / 2 + (if compact then 12 else 22)
	for sgn = -1, 1, 2 do
		local sp = icon(
			mid,
			Q.Sparkle1,
			pcx + sgn * sx,
			pcy - (if compact then 1 else 7),
			if compact then 18 else 26,
			if compact then 18 else 26,
			base + 3
		)
		sp.ImageColor3 = WARM
		if not compact then
			icon(mid, Q.Sparkle3, pcx + sgn * (sx - 6), pcy - 29, 12, 12, base + 3).ImageColor3 = WARM
			icon(mid, Q.Sparkle3, pcx + sgn * (sx - 6), pcy + 15, 12, 12, base + 3).ImageColor3 = WARM
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
	local P, ohFull, thFull = 203, 144, 101 -- short windows (small desktops) shrink the preview first, then odds, then tiles
	if not compact then
		local deficit = math.max(0, P + 441 - L.panelH + 8)
		local cut = math.min(deficit, 62)
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
				Position = UDim2.fromOffset(-1, -1),
				Size = UDim2.fromOffset(rw + 4, P),
				Image = art.Image,
				ImageRectOffset = art.Preview.Min,
				ImageRectSize = Vector2.new(art.Preview.Width, art.Preview.Height),
				ScaleType = Enum.ScaleType.Crop,
				ZIndex = base + 1,
			})
			make("UICorner", { CornerRadius = UDim.new(0, 22) }, pv)
			make("UIStroke", { Color = RIM_ORANGE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pv)
		end
		y = P - 1 + 15 -- ribbon ink top >= 12 px under the preview's outer rim (3 px stroke)
	end
	-- ribbon (own aspect; the body is its top 76%): full tier fixes the ink height at 61 so the tails end at ref y 434, clear of the tiles (441)
	local rh = if compact then round(rw * ASP) else 61
	local rwR = if compact then rw else round(rh / ASP)
	local rx = rw / 2 + (if compact then 0 else 2)
	skin(col, Q.DetailRibbon, rx, y + rh / 2, rwR, rh, nil, base + 1, "Ribbon")
	local rtitle = if compact then "REPEAT REWARDS" else "REPEAT REWARDS \u{2022} EVERY 10 WAVES"
	local rwid = if compact then rw * 0.75 - 14 else rwR * 0.9
	if compact and measure(rtitle, 18) > rwid then
		rtitle = "REWARDS"
	end
	local rrich = if compact then rtitle else rtitle:gsub("\u{2022}", `<font color="{YELLOW_HEX}">\u{2022}</font>`)
	label(col, {
		Name = "RibbonText",
		Text = rrich,
		Plain = rtitle,
		Rich = true,
		Size = if compact then 18 else 19, -- A-15: ref ink 303 wide = size 19.8; the shorter ribbon body fits ~18
		Min = if compact then 18 else 12,
		X = rx,
		Y = y + rh * 0.38 + 1,
		W = rwid,
		Z = base + 3,
		Stroke = 2,
	})
	y += rh + (if compact then 2 else 13)

	-- tiles
	local tiles = self._tiles
	local tw, th, tgap = 88, thFull, 6
	local cols = 4
	if compact then
		cols = 2
		tw, th = round((rw - tgap) / 2), 60
	end
	local hh = if compact then 24 else 25
	local lsize = if compact then 18 else 24
	for _, tile in tiles do -- one label size for every tile
		lsize = math.min(lsize, Parts.fitSize(tile.Label, tw - 5, lsize, if compact then 18 else 11))
	end
	for i, tile in tiles do
		local c, r = (i - 1) % cols, (i - 1) // cols
		local tx, ty = c * (tw + tgap) + (if compact then 0 else 4), y + r * (th + tgap) - (if compact then 0 else 6)
		local box = Draw.img(col, {
			Name = "Tile" .. i,
			Position = UDim2.fromOffset(tx, ty),
			Size = UDim2.fromOffset(tw, th),
			ZIndex = base + 1,
		}, "Frame")
		skin(
			box,
			PlaySprites.PurpleBox,
			tw / 2,
			th / 2,
			tw - 2,
			th - 2,
			if compact then 0.2 else 0.3,
			box.ZIndex + 1,
			"Skin"
		)
		skin(
			box,
			Bag.PillPurple,
			tw / 2,
			hh / 2 + 1,
			tw - (if compact then 2 else 4),
			hh,
			nil,
			box.ZIndex + 2,
			"Header"
		)
		label(box, {
			Name = "Label",
			Text = tile.Label,
			Size = lsize,
			Min = if compact then 18 else 11,
			Fit = tw - 5,
			X = tw / 2,
			Y = hh / 2 + 1,
			W = tw - 3,
			Stroke = 2,
			Z = box.ZIndex + 3,
		})
		local iy = if compact then hh + 1 + (th - hh - 1) / 2 else 62 * th / 101
		icon(box, rec(tile.Icon), tw / 2, iy, if compact then 34 else 68, if compact then 28 else 66, box.ZIndex + 2)
	end
	local rowsN = (#tiles + cols - 1) // cols
	y += rowsN * th + (rowsN - 1) * tgap + (if compact then 6 else 9)

	-- odds
	local lines = self._odds
	local oh = if compact then math.max(70, 20 * #lines + 8) else ohFull
	local ow = if compact then rw else rw - 1
	local odds = Draw.img(col, {
		Name = "Odds",
		Position = UDim2.fromOffset(if compact then 0 else 4, y),
		Size = UDim2.fromOffset(ow, oh),
		ZIndex = base + 1,
	}, "Frame")
	skin(odds, PlaySprites.PurpleBox, ow / 2, oh / 2, ow, oh, 0.4, odds.ZIndex + 1, "Skin")
	local z = odds.ZIndex + 3
	local textCx, textW = ow / 2, ow - 14
	local ys, sizes, fits = {}, {}, {}
	if compact then
		for i = 1, #lines do
			ys[i] = oh / 2 + (i - (#lines + 1) / 2) * 20
			sizes[i] = 20
		end
	else
		local dvx = 134
		local dcy = oh * 68.5 / 144
		for i, d in { 190, 140 } do -- two stacked pink blooms behind the die (the sprite is faint; tint set after apply: skin resets it)
			local glow = Draw.img(odds, { Name = "DieGlow" .. i, ZIndex = z - 1 })
			Draw.apply(glow, Q.GlowRadial, 68, dcy, d, d)
			glow.ImageColor3 = Color3.fromRGB(255, 80, 235)
			glow.ImageTransparency = 0
		end
		icon(odds, Q.IconGalaxyDie, 68, dcy, 85, 95, z)
		icon(odds, Q.Sparkle2, 29, oh * 0.38, 22, 22, z + 1).ImageColor3 = WARM
		divider(odds, dvx, oh * 13 / 144, 4, oh * 112 / 144, z)
		textCx, textW = 253, ow - 152 -- ref line centre x 1325
		if #lines == 5 then
			ys, sizes = { 18, 46, 75, 103, 128 }, { 25, 25, 25, 21, 20 } -- ref cap centres; A-15 sizes (ref inks 160 / 160 / 160 / 207 / 135 wide)
			fits = { 160, 160, 160, 207, 135 }
			for i = 1, 5 do
				ys[i] = ys[i] * oh / 144
			end
		else
			for i = 1, #lines do
				ys[i] = oh / 2 + (i - (#lines + 1) / 2) * 30
				sizes[i] = 25
			end
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
			Min = if compact then 18 else 12,
			Fit = fits[i],
			X = textCx,
			Y = ys[i],
			W = textW,
			H = sizes[i] + 2,
			Stroke = 2,
			Z = z,
		})
	end
	y += oh + (if compact then 8 else 17)

	-- START
	local sw, sh = if compact then rw else 326, if compact then 58 else 90 -- full: 8 px under the ref 334 so the sparkles fit between the button and the window rim
	local bw, bh = Parts.inkBox("BtnGreen", sw, sh)
	local scy = if compact then math.min(L.H - sh / 2 - 2, y + sh / 2) else y + sh / 2
	local scx = round(rw / 2) + (if compact then 0 else 2)
	local btn = Parts.button(col, {
		Name = "Start",
		Style = "Green",
		Label = "START",
		TextSize = if compact then 28 else 60, -- A-15: ref ink 161 wide = size 60 (cap 36 would be 63)
		Icon = if compact then PlaySprites.PlayArrow else nil,
		Size = UDim2.fromOffset(round(bw), round(bh)),
		Enabled = self._startState == "Ready",
	})
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.fromOffset(scx, round(scy))
	btn.Label:FindFirstChildOfClass("UIStroke").Thickness = if compact then 3 else 4.5 -- the reference outline is ~5 px
	self._startBtn = btn
	self._startArrow = nil
	if not compact then -- the button helper sizes its icon 45 px square: draw the 41x45 arrow and place the label by hand (ref: arrow -88, label +33 from centre)
		local bcx, bcy = round(bw) / 2, round(bh) / 2
		local arrow = Draw.img(btn, { Name = "Arrow", ZIndex = btn.Label.ZIndex })
		Draw.apply(arrow, PlaySprites.PlayArrow, bcx - 86, bcy, 40, 44) -- ref arrow reads ~45 wide; 34x37 looked far smaller
		self._startArrow = arrow
		local l = btn.Label
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromOffset(bcx + 32, bcy - 4) -- ref label centre sits 4.5 px higher than the button helper's
		l.Size = UDim2.fromOffset(190, round(bh) - 8)
		l.TextSize = 60
		self:SetStartState(self._startState)
	end
	btn.Activated:Connect(function()
		if self._startState == "Ready" and self._onStart then
			self._onStart()
		end
	end)
	for sgn = -1, 1, 2 do
		if compact then -- inside the column (the button is as wide as it), above the button in Z
			icon(col, Q.Sparkle1, scx + sgn * (sw / 2 - 12), scy - sh * 0.3, 14, 14, base + 20).ImageColor3 = WARM
			icon(col, Q.Sparkle1, scx + sgn * (sw / 2 - 12), scy + 6, 14, 14, base + 20).ImageColor3 = WARM
		else -- outside the button ink (+-163), >= 6 px inside the column edge (= the window's inner rim), above the button in Z
			icon(col, Q.Sparkle1, scx + sgn * 171, scy - 30, 14, 14, base + 20).ImageColor3 = WARM
			icon(col, Q.Sparkle1, scx + sgn * 172, scy - 6, 14, 14, base + 20).ImageColor3 = WARM
			icon(col, Q.Sparkle1, scx + sgn * 171, scy + 17, 12, 12, base + 20).ImageColor3 = WARM
		end
	end
end

-- Scroll bars ----------------------------------------------------------------------------------------------

local function makeBar(holder, scroll)
	local track = Draw.img(holder, { Name = "ScrollTrack", AnchorPoint = Vector2.new(1, 0), Visible = false })
	track:SetAttribute("Keep", true)
	barSkin(track, "ScrollTrack", BAR_W)
	local thumb = Draw.img(track, { Name = "Thumb", AnchorPoint = Vector2.new(0.5, 0), ZIndex = track.ZIndex + 1 })
	barSkin(thumb, "ScrollThumb", BAR_W)
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
		thumb.Size = UDim2.fromOffset(BAR_W, thumbH)
		thumb.Position =
			UDim2.new(0.5, 0, 0, math.floor((h - thumbH) * (if maxY > 0 then scroll.CanvasPosition.Y / maxY else 0)))
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
		local arrow = self._startArrow
		if arrow and arrow.Parent then
			local on = state == "Ready"
			arrow.ImageTransparency = if on then 0 else 0.55
			arrow.ImageColor3 = if on then WHITE else Color3.fromRGB(150, 150, 150)
		end
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
