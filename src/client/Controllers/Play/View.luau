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
local WARM = Color3.fromRGB(255, 248, 215) -- sparkle tint: near white, pale gold
local BLOOM = Color3.fromRGB(255, 115, 0) -- warm orange bloom behind the big sparkles
local GLOW_IN = Color3.fromRGB(253, 239, 10) -- selected card bloom: yellow #FDEF0A inside ...
local GLOW_OUT = Color3.fromRGB(245, 119, 3) -- ... to orange #F57703 outside
local RIM_WHITE = Color3.fromRGB(254, 219, 244)
local RIM_ORANGE = Color3.fromRGB(248, 130, 20)
local BAR = { ScrollTrack = Rect.new(19, 65, 22, 227), ScrollThumb = Rect.new(20, 37, 22, 133) } -- narrow centre columns: no horizontal stretch
local BAR_W = 10 -- track box; the Bag's sprites draw an 8 px ink bar at this width (the Bag's phone scrollbar)
local ASP = 79 / 391 -- DetailRibbon ink aspect (h / w): ribbons keep it, never stretched

local function round(n: number): number
	return math.floor(n + 0.5)
end

local K = 1 -- real px per design px under the shell's UIScales (set per build): text is measured at its real size, hinting widens it

local function measure(str: string, size: number): number
	return TextService:GetTextSize(str, size * K, Enum.Font.FredokaOne, Vector2.new(1e5, 1e5)).X / K
end

local function fitSize(
	str: string,
	w: number,
	size: number,
	min: number
): number -- largest size <= size whose real width fits w
	while size > min and measure(str, size) > w do
		size -= 1
	end
	return size
end

local function mpx(n: number): number -- n real px in design px (5 px clearance = 6.25 design px at the 0.8 scale clamp)
	return n / K
end

-- Text size: the reference cap height, capped by the reference ink width (the shared font is wider than the reference face); these are the reference ink widths (ref px).
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
	l.TextTruncate = Enum.TextTruncate.None -- a label shrinks to fit, it never shows "..."
	local plain = o.Plain or o.Text
	local fit = math.min(o.Fit or 1e5, o.W * 0.95) -- 5% spare: hinting at fractional UI scales widens text
	local size = if o.Fixed then o.Size else fitSize(plain, fit, o.Size, o.Min or math.ceil(mpx(12))) -- Fixed: a role size, fitted for every member by the caller
	local w = measure(plain, size)
	local hard = o.W * 0.97
	if w > hard then -- below Min only as a last resort (a column squeezed by a small window): smaller beats truncated
		size = math.max(8, math.floor(size * hard / w))
	end
	l.TextSize = size
	return l
end

-- Sprite drawn by its ink centred at (cx, cy), fitted into maxW x maxH at its own aspect.
local function icon(parent, r, cx, cy, maxW, maxH, z)
	local img = Draw.img(parent, { Name = "Icon", ZIndex = z })
	local w, h = Draw.fitIn(r, maxW, maxH)
	return Draw.apply(img, r, cx, cy, w, h)
end

-- Bright four-point sparkle (near white, pale gold); sizes >= 10 get a warm orange bloom behind them.
local function spark(parent, sprite, cx, cy, size, z, white)
	if size >= 10 then
		for _, k in { 2.1, 1.5 } do -- two stacked orange blooms: warmer and denser than one
			local g = Draw.img(parent, { Name = "SparkBloom", ZIndex = z - 1 })
			Draw.apply(g, Q.GlowRadial, cx, cy, size * k, size * k)
			g.ImageColor3 = BLOOM
			g.ImageTransparency = 0
		end
	end
	local sp = icon(parent, sprite, cx, cy, size, size, z)
	sp.ImageColor3 = if white then WHITE else WARM
	sp.ImageTransparency = 0
	return sp
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
		L.gap = if W >= 700 then 5 else 3 -- 667: the 4 px give the tile headers room for 18 px labels
		L.leftW = if W >= 700 then 216 else 172 -- 18 px labels need: titles 136 + 5 real px each side, tile headers 94
		L.rightW = if W >= 700 then 240 else 210
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

-- BEST pill geometry + its text (the compact variants drop words until the text fits).
local function pillGeom(wd, L, s, w, h)
	local compact = L.compact
	local pw, ph = round(255 * s), round(52 * s) -- 9-slice ink: visible width = pw + ~10, visible height = ph x 0.83 -> ref 266 x 43-46
	local bm = math.max(round(5 * s), math.ceil(mpx(5) + 0.3)) -- >= 5 real px from the card's inner rim
	local cx, cy = round(8 * s) + pw / 2, h - bm - ph / 2
	if compact then
		pw, ph = w - 16 - (if wd.Locked then 30 else 0), 33 -- a locked card keeps its padlock beside the pill; 33 holds the 18 px text with >= 5 real px
		cx, cy = 8 + pw / 2, h - bm - ph / 2
	end
	local crown = not compact or pw >= 150 -- narrowest phones drop the crown so the 18 px text fits
	local tx0 = if crown then 56 * s else 12
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
	return {
		pw = pw,
		ph = ph,
		cx = cx,
		cy = cy,
		crown = crown,
		tx0 = tx0,
		avail = avail,
		size = size,
		plain = plain,
		rich = rich,
	}
end

-- One BEST text size for every card (the largest that fits the longest text), desktop tiers.
local function pillRoleSize(worlds, L, s, w, h): number
	local size = 1e5
	for _, wd in worlds do
		local g = pillGeom(wd, L, s, w, h)
		size = math.min(size, fitSize(g.plain, g.avail * 0.95, g.size, 1))
	end
	return size
end

local function cardPill(card, wd, L, s, w, h, role, z)
	local g = pillGeom(wd, L, s, w, h)
	local cx, cy, pw, ph = g.cx, g.cy, g.pw, g.ph
	skin(card, if wd.Locked then Bag.PillGrey else Bag.PillGreen, cx, cy, pw, ph, nil, z + 1, "BestPill")
	if g.crown then
		icon(card, Bag.IconCrown, cx - pw / 2 + 32 * s, cy, 36 * s, 28 * s, z + 2)
	end
	label(card, {
		Name = "BestText",
		Text = g.rich,
		Plain = g.plain,
		Rich = true,
		Size = if L.compact then g.size else role,
		Fixed = true,
		X = cx - pw / 2 + g.tx0 + g.avail / 2,
		Y = cy,
		W = g.avail,
		H = ph,
		Stroke = 2,
		Z = z + 2,
	})
end

local MOON = { Min = Vector2.new(219, 7), Size = Vector2.new(73, 73) } -- the Shadow sheet's moon disc (WorldShadow export px)
local CARD_L, CARD_R = 8, 4 -- the bloom's outer ring then ends on the window's inner rim (never clipped) and short of the mid panel

-- Selected card bloom from live strokes (no texture): frames hugging the card, yellow inside to orange outside, fading out.
local function bloom(host, x, y, w, h, radius, z, compact)
	local n, step = if compact then 3 else 6, if compact then 1.3 else 1.9
	for i = 1, n do
		local t = (i - 1) / (n - 1)
		local e = 3 + (i - 1) * step -- the card's own 3 px white rim is the first 3 px
		local f = make("Frame", {
			Name = "Glow",
			Position = UDim2.fromOffset(x - e, y - e),
			Size = UDim2.fromOffset(w + 2 * e, h + 2 * e),
			BackgroundTransparency = 1,
			ZIndex = z,
		}, host)
		make("UICorner", { CornerRadius = UDim.new(0, radius + e) }, f)
		make("UIStroke", {
			Color = GLOW_IN:Lerp(GLOW_OUT, t),
			Transparency = 0.02 + 0.45 * t,
			Thickness = 2.4,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, f)
	end
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
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, card)
	if sel then
		bloom(host, x, y, w, h, round(22 * s), host.ZIndex + 2, L.compact)
	end
	local zt = card.ZIndex + (if wd.Locked then 2 else 0) -- locked: title / pill / padlock sit above the gray shade (card + 2)
	if wd.Locked then
		-- grays the art (and the Shadow moon) out: 25% of the art's colour shows through a neutral gray
		local shade = make("Frame", {
			Name = "LockShade",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(80, 80, 88),
			BackgroundTransparency = 0.25,
			ZIndex = card.ZIndex + 2,
		}, card)
		make("UICorner", { CornerRadius = UDim.new(0, round(22 * s)) }, shade)
	end
	label(card, {
		Name = "Title",
		Text = wd.Name,
		Size = if L.compact then 18 else titleSize(s), -- min(cap 23, ref ink width) = 33 at 1672
		Fixed = true,
		AX = 0,
		X = if L.compact then 10 else 12,
		Y = if L.compact then 18 else round(12 * s) + 17 * s,
		W = if L.compact then (w - 10 - mpx(5) - 3) / 0.95 else w - 16, -- phones: the title ends >= 5 real px from the card rim (3 px outline)
		Z = zt + 1,
		Stroke = 3,
	})
	cardPill(card, wd, L, s, w, h, L.pillSize, zt)
	if wd.Art == "WorldShadow" and not L.compact then
		-- the source art's moon is ~85 px at card scale (ref ~38): the card crop stops left of / below it and a small disc is cut from the same sheet
		local d = round(38 * s)
		local halo = Draw.img(card, { Name = "MoonHalo", ZIndex = card.ZIndex + 1 }) -- soft pale bloom: the disc's edge melts into the art
		Draw.apply(halo, Q.GlowRadial, round(w * 0.855), round(h * 0.2), d * 2, d * 2)
		halo.ImageColor3 = Color3.fromRGB(255, 226, 242)
		halo.ImageTransparency = 0.1
		local moon = Draw.img(card, {
			Name = "Moon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(round(w * 0.855), round(h * 0.2)),
			Size = UDim2.fromOffset(d, d),
			Image = art.Image,
			ImageRectOffset = MOON.Min,
			ImageRectSize = MOON.Size,
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = card.ZIndex + 1,
		})
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, moon)
		-- the sheet's tree crosses the disc's lower half: fade it into the card art instead of a hard circular cut
		make("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.45, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, moon)
	end
	if wd.Locked then
		-- right of the BEST pill (never over it or the art's die / castle); phones have no room: top-right corner
		local lock
		if L.compact then
			lock = icon(card, Bag.Lock, w - 20, h - 19, 18, 22, zt + 1)
		else
			lock = icon(card, Bag.Lock, w - 24 * s, h - 24 * s, 27 * s, 32 * s, zt + 1)
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
		local mt = math.ceil(mpx(5) + 0.3) -- card ink (3 px outward stroke) keeps >= 5 real px to the window rim
		local gap = 6 + mt -- ink gap between cards = gap - 2 x 3 px stroke
		local n = math.max(1, #worlds)
		local ch = math.max(62, (L.H - 2 * mt - (n - 1) * gap) // n) -- the cards fill the column (top / bottom aligned with the mid panel); scroll only when they cannot fit
		local pitch = ch + gap
		local y0 = mt
		for i, wd in worlds do
			buildCard(
				self,
				host,
				wd,
				mt,
				y0 + (i - 1) * pitch,
				cw - mt - 3,
				ch,
				wd.Id == self._selected,
				PlaySprites[wd.Art].CardC,
				cw / 363,
				L
			)
		end
		host.CanvasSize = UDim2.fromOffset(0, math.max(2 * mt + n * pitch - gap, 0))
	else
		local s = L.leftW / 363
		local f = math.min(1, (L.panelH - 3) / 659) -- short windows squash the card heights (crop keeps the art's aspect)
		L.pillSize = pillRoleSize(worlds, L, math.min(s, f), L.leftW - CARD_L - CARD_R, 100)
		local tops = { 22, 184, 347, 510 }
		for i, wd in worlds do
			if not tops[i] then
				break -- the full layout holds the reference's four cards
			end
			local sel = wd.Id == self._selected
			local top = round(tops[i] * f)
			local h = round(CARD_H[i] * f)
			local art = PlaySprites[wd.Art]
			if sel then
				local y = math.max(top - round(20 * f), math.ceil(mpx(5) + 0.3)) -- ink (3 px stroke) >= 5 real px under the window rim; the bottom edge stays
				buildCard(
					self,
					host,
					wd,
					CARD_L,
					y,
					L.leftW - CARD_L - CARD_R,
					top - round(20 * f) + round(168 * f) - y,
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
	IconCrystals = { 76, 66 }, -- boxes are sprite Ink sizes: the visible ink draws smaller, scaled so it lands on the ref ink (crystal 67x58, banner 107x62, crown)
	Potion = { 60, 62 },
	IconChest = { 84, 62 },
	RewardBanner = { 140, 64 }, -- ink <= 66 tall: every reward icon stays >= 3 px inside its 72 px row
	IconGalaxyDie = { 66, 66 },
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
			Fixed = true,
			X = cx,
			Y = y + (sz + 1) / 2,
			W = w,
			H = sz + 2,
			Stroke = 2,
			Z = z,
		})
		y += sz + 1
	end
end

local function iconInkW(row, h: number): number
	if row.Icon == "CrownGems" then
		return (Draw.fitIn(Q.IconCrown, 70, 46))
	end
	local box = ICON_BOX[row.Icon] or { 67, 59 }
	return (Draw.fitIn(rec(row.Icon), box[1], math.min(box[2], h - 2 * mpx(3) - 2.5)))
end

-- Desktop rows: ONE size per text role (WAVE labels, reward first lines, reward sub-lines) = the largest that fits every row (A-15: the
-- reference cap, <= 110% of the reference ink width); the icon / divider / text columns then follow from the sizes. Never under the 12 real px floor.
local function rowRoles(rows, w: number, h: number, f: number)
	local m5, fl = mpx(5), math.ceil(mpx(12))
	local three = false
	for _, r in rows do
		three = three or #r.Lines >= 3
	end
	local hs = if h < 72 then math.max(0.85, h / 72) else 1
	local sw, r1, rs = 26, math.floor((if three then 24 else 26) * hs), math.floor((if three then 18 else 20) * hs)
	local half = 0
	for _, row in rows do
		sw = math.min(sw, fitSize("WAVE " .. row.Wave, if tostring(row.Wave):len() >= 3 then 121 else 98, sw, 1))
		for i, str in row.Lines do
			local lim = (REW_REF[str] or 1e5) * 1.1
			if i == 1 then
				r1 = math.min(r1, fitSize(str, lim, r1, 1))
			else
				rs = math.min(rs, fitSize(str, lim, rs, 1))
			end
		end
		half = math.max(half, iconInkW(row, h) / 2)
	end
	local function place(a, b, c)
		local wr, ixMin = 0, 0
		for _, row in rows do
			ixMin = math.max(ixMin, 31 + measure("WAVE " .. row.Wave, a) + m5 + 3 + iconInkW(row, h) / 2)
			for i, str in row.Lines do
				wr = math.max(wr, measure(str, if i == 1 then b else c))
			end
		end
		wr += 5
		local txMax = w - m5 - 2 - wr / 2
		local dxMax = txMax - wr / 2 - 6 - m5
		local ixMax = dxMax - m5 - 1 - half
		if ixMin > ixMax then
			return nil
		end
		local ix = math.clamp(192 * f, ixMin, ixMax)
		local dx = math.clamp(250 * f, ix + half + m5 + 1, dxMax)
		return { ix = ix, dx = dx, tx = math.clamp(323 * f, dx + 6 + m5 + wr / 2, txMax), wr = wr }
	end
	local t = 1
	while true do
		local a, b, c =
			math.max(fl, math.floor(sw * t)), math.max(fl, math.floor(r1 * t)), math.max(fl, math.floor(rs * t))
		local pos = place(a, b, c)
		if pos or (a == fl and b == fl and c == fl) then
			pos = pos or { ix = 192 * f, dx = 250 * f, tx = 323 * f, wr = 130 }
			pos.sw, pos.r1, pos.rs = a, b, c
			return pos
		end
		t -= 0.03
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
	return math.max(48, 16 + 20 * (1 + #compactLines(row, rowW - 38)))
end

local function buildRow(host, row, x, y, w, h, compact, R)
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
		local avail = w - 38
		local lines = compactLines(row, avail)
		local y0 = h / 2 - (1 + #lines) * 10
		label(frame, {
			Name = "Wave",
			Text = "WAVE " .. row.Wave,
			AX = 0,
			Size = 20,
			Min = 18,
			X = 28,
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
				X = 28,
				Y = y0 + 10 + 20 * i,
				W = avail + 10,
				H = 20,
				Z = z,
				Stroke = 2,
			})
		end
		return
	end
	local ix, dx = R.ix, R.dx
	local box = ICON_BOX[row.Icon] or { 67, 59 }
	local iconH = math.min(box[2], h - 2 * mpx(3) - 2.5) -- icon ink >= 3 real px inside the row
	label(frame, {
		Name = "Wave",
		Text = "WAVE " .. row.Wave,
		AX = 0,
		Size = R.sw,
		Fixed = true,
		X = 31, -- ref text starts x 684
		Y = h / 2,
		W = 132,
		Z = z,
		Stroke = 3,
	})
	if row.Icon == "CrownGems" then
		icon(frame, Q.IconCrown, ix, h / 2 - 9, 70, 46, z)
		for i = -1, 1 do
			local gem = Draw.img(frame, {
				Name = "Gem",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(round(ix + i * 21), round(h - 11 - mpx(3) - 1)), -- gem bottoms >= 3 real px above the row rim
				Size = UDim2.fromOffset(20, 20),
				Image = Sprites.Gem,
				ZIndex = z + 1,
			})
			gem.ScaleType = Enum.ScaleType.Fit
		end
	else
		icon(frame, rec(row.Icon), ix, h / 2, box[1], iconH, z)
	end
	divider(frame, dx, h / 2 - 27.5, 4, 55, z)
	local sizes = {}
	for i = 1, #row.Lines do
		sizes[i] = if i == 1 then R.r1 else R.rs
	end
	rewardLines(frame, row.Lines, R.tx, h / 2, R.wr + 6, sizes, z)
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
	local rtop = if compact then 11 else 12
	local bodyCy = rtop + rh * 0.38
	skin(mid, Q.DetailRibbon, midW / 2, rtop + rh / 2, rw, rh, nil, base + 2, "Ribbon")
	local tsz = if compact then (if midW < 250 then 22 else 28) else 46 -- full: ref trophies 47-52 (46 keeps >= 5 px inside the ribbon ends)
	local tdx = if compact then rw / 2 - tsz / 2 - 8 else 164 -- full: ref centres +-172, at the ribbon body ends
	local tcy = bodyCy + (if compact then 3.5 else 2)
	icon(mid, Q.IconTabTrophy, midW / 2 - tdx, tcy, tsz, tsz, base + 3)
	icon(mid, Q.IconTabTrophy, midW / 2 + tdx, tcy, tsz, tsz, base + 3)
	local avail = 2 * tdx - tsz - (if compact then 10 else 4)
	local title, tsize = "FIRST-TIME MILESTONES", if compact then 18 else 27 -- ref ink 273 wide = size 26.8; <= 270 keeps >= 5 px to the trophies
	if compact and measure(title, tsize) > avail then
		title = "MILESTONES"
	end
	label(mid, {
		Name = "RibbonText",
		Text = title,
		Size = tsize,
		Min = if compact then 18 else 12,
		Fit = if compact then nil else 270,
		X = midW / 2,
		Y = bodyCy + 1,
		W = avail,
		Z = base + 4,
	})

	-- rows
	local rows = self._rows
	if compact then
		local sy = rtop + rh + 8
		local listH = L.H - sy - 62
		local scroll = self._rowScroll
		scroll.Visible = true
		local lead = if midW < 250 then 22 else 34
		local rowW = midW - lead - 22 - 20 -- >= 5 real px to the scroll bar
		-- A whole number of rows exactly fills the list: one pitch for every row, the slack goes into the pitch (never a cut row, never a dead band)
		local hmax = 48
		for _, row in rows do
			hmax = math.max(hmax, compactRowH(row, rowW))
		end
		local n = math.max(1, listH // (hmax + 6))
		local pitch = listH // n
		local sh = n * pitch
		scroll.Position = UDim2.fromOffset(lead, sy)
		scroll.Size = UDim2.fromOffset(midW - lead - 22, sh)
		scroll.ZIndex = base + 2
		for i, row in rows do
			buildRow(scroll, row, 14, (i - 1) * pitch + 3, rowW, pitch - 6, true)
		end
		scroll.CanvasSize = UDim2.fromOffset(0, #rows * pitch)
	else
		self._rowScroll.Visible = false
		local rowW = midW - 59
		local g = math.min(1, L.panelH / 673)
		local tops = { 101, 182, 263, 344, 427, 510 } -- row 1 sits ~9 px under the ribbon tails
		if #rows > 1 then -- thin orange line behind the status circles (ref x ~645), first to last circle
			local y1, y2 = round(tops[1] * g + 36 * g), round(tops[math.min(#rows, #tops)] * g + 36 * g)
			for _, gl in { { 14, 0.82 }, { 9, 0.6 } } do -- soft glow: wider, more transparent lines behind the 4 px connector
				local glow = make("Frame", {
					Name = "ConnGlow",
					Position = UDim2.fromOffset(36 - gl[1] / 2, y1),
					Size = UDim2.fromOffset(gl[1], y2 - y1),
					BackgroundColor3 = RIM_ORANGE,
					BackgroundTransparency = gl[2],
					BorderSizePixel = 0,
					ZIndex = base + 1,
				}, mid)
				make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, glow)
			end
			make("Frame", {
				Name = "Connector",
				Position = UDim2.fromOffset(34, y1),
				Size = UDim2.fromOffset(4, y2 - y1),
				BackgroundColor3 = RIM_ORANGE,
				BorderSizePixel = 0,
				ZIndex = base + 1,
			}, mid)
		end
		local R = rowRoles(rows, rowW, round(72 * g), rowW / 397)
		for i, row in rows do
			if not tops[i] then
				break -- the full layout holds the reference's six rows
			end
			buildRow(mid, row, 46, round(tops[i] * g), rowW, round(72 * g), false, R)
		end
	end

	-- WORLD CLEAR pill + sparkles
	local clearOn = self._worldClear
	local pw, ph = if compact then math.min(midW - 60, 176) else 309, if compact then 44 else 58
	local pcx = midW / 2 + (if compact then 0 else 1.5)
	local pcy = if compact then L.H - 34 else round(621 * math.min(1, L.panelH / 673))
	skin(mid, if clearOn then Bag.PillGold else Bag.PillGrey, pcx, pcy, pw, ph, nil, base + 3, "WorldClear")
	label(mid, {
		Name = "Text",
		Text = "WORLD CLEAR",
		Size = if compact then 22 else 39, -- ref ink 240 wide = size 39.8 (cap 47)
		Min = if compact then 18 else 12,
		Fit = if compact then nil else 240,
		Color = if clearOn then YELLOW else GREY,
		X = pcx,
		Y = pcy - 1,
		W = pw - (if compact then 14 else 60),
		Z = base + 4,
	})
	local sx = pw / 2 + (if compact then 13.5 else 22)
	for sgn = -1, 1, 2 do
		local big = if compact then 14 else 26
		spark(mid, Q.Sparkle1, pcx + sgn * sx, pcy - (if compact then 1 else 2), big, base + 3, true)
		if not compact then
			spark(mid, Q.Sparkle3, pcx + sgn * (sx - 6), pcy - 24, 12, base + 3, true)
			spark(mid, Q.Sparkle3, pcx + sgn * (sx - 6), pcy + 20, 12, base + 3, true)
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
	local floorD = math.ceil(mpx(12)) -- the 12 real px text floor, in design px
	local grid2 = false -- narrow desktops: the four tiles go 2x2 (compact tile) when their labels cannot reach the floor in one row
	if not compact then
		local tw4 = math.min(88, (rw - 8 - 12) // 4)
		local l4 = 24
		for _, tile in self._tiles do
			l4 = math.min(l4, fitSize(tile.Label, tw4 - 15, 24, 1))
		end
		grid2 = l4 < floorD
		local deficit = math.max(0, P + 441 - L.panelH + 8 + (if grid2 then 23 else 0)) -- 2x2 tiles: 2 x 60 + 4 = 124 tall instead of 101
		local cut = math.min(deficit, 62)
		P -= cut
		deficit -= cut
		cut = math.min(deficit, 30)
		ohFull -= cut
		deficit -= cut
		thFull -= if grid2 then 0 else math.min(deficit, 15)
	end
	col.Position = UDim2.fromOffset(L.rightX, 0)
	col.Size = UDim2.fromOffset(rw, L.H)
	local base = col.ZIndex
	local y = if compact then 8 else 0 -- phones: the ribbon ink keeps >= 5 real px under the window rim
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
				Position = UDim2.fromOffset(2, math.ceil(mpx(5) + 0.3)), -- the 3 px outward rim then keeps >= 5 real px to the window rim
				Size = UDim2.fromOffset(rw - 9, P - math.ceil(mpx(5) + 0.3) - 1), -- 3 px rim included: the right edge ends ~12 px short of the window band (mirrors the cards' inset)
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
	local rwR = if compact then rw - 8 else round(61 / ASP) -- phones: the ribbon ends >= 5 real px inside the window rim
	local rh = if compact then round(rwR * ASP) else 61
	local rx = rw / 2 - (if compact then 0 else 2)
	skin(col, Q.DetailRibbon, rx, y + rh / 2, rwR, rh, nil, base + 1, "Ribbon")
	local rtitle = if compact then "REPEAT REWARDS" else "REPEAT REWARDS \u{2022} EVERY 10 WAVES"
	local rwid = if compact then rw * 0.8 - 8 else rwR * 0.95
	if compact and measure(rtitle, 18) > rwid then
		rtitle = "REWARDS"
	end
	local rrich = if compact then rtitle else rtitle:gsub("\u{2022}", `<font color="{YELLOW_HEX}">\u{2022}</font>`)
	label(col, {
		Name = "RibbonText",
		Text = rrich,
		Plain = rtitle,
		Rich = true,
		Size = if compact then 18 else 21, -- ref ink 303 wide; fitted to the ribbon body
		Min = if compact then 18 else 12,
		X = rx,
		Y = y + rh * 0.38 + 1,
		W = rwid,
		Z = base + 3,
		Stroke = 2,
	})
	y += rh + (if compact then 6 else 13)

	-- tiles
	local tiles = self._tiles
	local tight = compact or grid2 -- compact tile: 2 x 2, 56 tall, 18 px labels
	local tw, th, tgap = 88, thFull, if compact then 6 else 4 -- full: 4 px gaps (the skins draw 3 px over each box; >= 5 real px skin to the next header)
	local cols = 4
	if compact then
		cols = 2
		tw, th = (rw - tgap - 3) // 2, if L.W < 700 then 56 else 60 -- the skins end >= 5 real px inside the window rim
	elseif grid2 then
		cols = 2
		tw, th = (rw - 8 - tgap) // 2, 60
	else
		tw = math.min(88, (rw - 8 - 3 * tgap) // 4) -- the skins draw 3 px over the box: boxes span x 2 .. rw - 6
	end
	local hh = if tight then 26 else 25
	local lsize = if tight then 18 else 24
	for _, tile in tiles do -- one label size for every tile: the largest that fits them all
		lsize = math.min(lsize, fitSize(tile.Label, tw - (if tight then 5 else 15), lsize, 1))
	end
	for i, tile in tiles do
		local c, r = (i - 1) % cols, (i - 1) // cols
		local tx, ty = c * (tw + tgap) + (if compact then 0 else 2), y + r * (th + tgap) - (if compact then 0 else 6)
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
			if tight then 0.2 else 0.3,
			box.ZIndex + 1,
			"Skin"
		)
		-- phones: tw - 1 gives COSMETICS (89 px at the 18 px floor) >= 3 real px to the pill ends; neighbour headers stay 7 px apart
		skin(
			box,
			Bag.PillPurple,
			tw / 2,
			hh / 2 + 1,
			tw - (if compact then 1 elseif tight then 2 else 4),
			hh,
			nil,
			box.ZIndex + 2,
			"Header"
		)
		label(box, {
			Name = "Label",
			Text = tile.Label,
			Size = lsize,
			Fixed = true,
			X = tw / 2,
			Y = if tight then hh / 2 - 0.5 else hh / 2 + 1, -- phones: equal >= 3 real px above and below the 18 px label
			W = tw - 3,
			Stroke = if tight then 1 else 2,
			Z = box.ZIndex + 3,
		})
		local top, bot = hh + 1, th - 4 -- the tile body between the header pill and the skin's inner rim
		local iy = if tight then (top + bot) / 2 else 61.2 * th / 101 -- icon ink >= 3 real px from the header pill and the skin rim
		icon(
			box,
			rec(tile.Icon),
			tw / 2,
			iy,
			if tight then tw - 12 else math.min(68, tw - 18),
			if tight then bot - top - 2 * mpx(3) - 1 else 62 * th / 101,
			box.ZIndex + 2
		)
	end
	local rowsN = (#tiles + cols - 1) // cols
	y += rowsN * th + (rowsN - 1) * tgap + (if compact then 6 else 9)

	-- odds
	local lines = self._odds
	local oh = if compact then math.max(70, round(18.2 * #lines + 19)) else ohFull
	local ow = if compact then rw - 4 else rw - 13 -- skin draws ~5 px over the box; phones: >= 5 real px to the window rim
	local odds = Draw.img(col, {
		Name = "Odds",
		Position = UDim2.fromOffset(if compact then 0 else 5, y),
		Size = UDim2.fromOffset(ow, oh),
		ZIndex = base + 1,
	}, "Frame")
	skin(odds, PlaySprites.PurpleBox, ow / 2, oh / 2, ow, oh, 0.4, odds.ZIndex + 1, "Skin")
	local z = odds.ZIndex + 3
	local textCx, textW = ow / 2, ow - 14
	local ys, sizes = {}, {}
	if compact then
		for i = 1, #lines do
			ys[i] = oh / 2 - 0.7 + (i - (#lines + 1) / 2) * 18.2
			sizes[i] = 18
		end
	else
		local dvx = if ow < 340 then 120 else 134 -- narrow desktops: the divider moves toward the die to widen the text block
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
		-- the text block sits between the divider and the right rim, >= 5 real px from each (rim 3 px + 2 px text outline per side)
		local m5 = mpx(5)
		local left, right = dvx + 4 + m5 + 2, ow - 3 - m5 - 2
		textCx = math.min(247, (left + right) / 2) -- ref line centre x 1325 (6 px left of the old 253)
		local free = 2 * math.min(textCx - left, right - textCx)
		textW = free + 4
		if #lines == 5 then
			-- two role sizes (A-15): lines 1-3 and lines 4-5 each take the largest size that fits every member, <= 110% of the reference ink width
			local refW = { 160, 160, 160, 207, 135 }
			local s13, s45 = 25, 21
			for i = 1, 5 do
				local plain = oddsText(lines[i])
				local lim = math.min(refW[i] * 1.1, free) * 0.95
				if i <= 3 then
					s13 = math.min(s13, fitSize(plain, lim, s13, 1))
				else
					s45 = math.min(s45, fitSize(plain, lim, s45, 1))
				end
			end
			sizes = { s13, s13, s13, s45, s45 }
			local y1, y5 = 13.3 + m5, oh - 14.2 - m5 -- cap centres: line 1 and line 5 keep >= 5 real px to the rim, even spacing between
			for i = 1, 5 do
				ys[i] = y1 + (i - 1) * (y5 - y1) / 4
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
			Fixed = true,
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
	-- full: the visible green body must be 330x86 (BtnGreen draws ~11.6 x 18 sprite-px-at-k less than its Ink box), centred on the ref centre
	local sw, sh = if compact then rw - 52 else math.min(339, rw - 8), if compact then 55 else 102 -- phones: 26 px bands each side hold the sparkles
	local bw, bh = Parts.inkBox("BtnGreen", sw, sh)
	local scy = if compact then math.min(L.H - sh / 2 - mpx(5) + 2, y + sh / 2) else math.min(y + 49, L.H - 49 - mpx(5)) -- the ink (102 tall) ends >= 5 real px above the window rim
	local scx = round((rw - 3) / 2) -- the centre of the column's visible span (-1 .. rw - 3.5): the sparkle pairs mirror about it
	local btn = Parts.button(col, {
		Name = "Start",
		Style = "Green",
		Label = "START",
		TextSize = if compact then 28 else 60, -- ref ink 161 wide = size 60 (cap 36 would be 63)
		Icon = if compact then PlaySprites.PlayArrow else nil,
		Size = UDim2.fromOffset(round(bw), round(bh)),
		Enabled = self._startState == "Ready",
	})
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.fromOffset(scx, round(scy))
	btn.Label.TextTruncate = Enum.TextTruncate.None
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
		l.Size = UDim2.fromOffset(190, 88)
		l.TextSize = 60
		self:SetStartState(self._startState)
	end
	btn.Activated:Connect(function()
		if self._startState == "Ready" and self._onStart then
			self._onStart()
		end
	end)
	if compact then -- 12 px sparkles in the 26 px bands beside the pill, mirrored, inside the column
		for sgn = -1, 1, 2 do
			local x = scx + sgn * (sw / 2 + 13)
			spark(col, Q.Sparkle1, x, scy - 12, 12, base + 20)
			spark(col, Q.Sparkle1, x, scy + 12, 12, base + 20)
		end
		return
	end
	-- Up to three sparkles a side like the reference, each >= 5 real px from the button's PIXELS (its dark rim included) and from the
	-- window rim / odds box. BtnGreen's alpha edge is its ink box with 32 px round corners (measured from Bag_BtnGreen.png at k = 1;
	-- conservative for both corners). A corner sparkle slides outward into the corner pocket, then shrinks; any that cannot fit is dropped.
	local bhw, bhh, rad, m5 = sw / 2, sh / 2, 32, mpx(5)
	local function gap(x, dy) -- distance from (x, dy) (relative to the button centre) to the button's pixels
		local qx, qy = math.abs(x) - (bhw - rad), math.abs(dy) - (bhh - rad)
		return math.sqrt(math.max(qx, 0) ^ 2 + math.max(qy, 0) ^ 2) + math.min(math.max(qx, qy), 0) - rad
	end
	for _, sp in { { -34, 18, true }, { -12, 10, false }, { 30, 16, true } } do
		for size = sp[2], 10, -2 do
			local half = size / 2
			local lo, hi = y - 8 + m5 + half - scy, L.H - 4.5 - half - scy -- >= 5 real px under the odds box, inside the window rim
			local x, dy = rw - 3 - m5 - half - scx, math.clamp(sp[1], lo, hi) -- as far from the button as the window rim allows
			local step = if sp[1] < 0 then -1 else 1
			while sp[3] and gap(x, dy) < half + m5 + 1 and dy + step >= lo and dy + step <= hi do
				dy += step
			end
			if gap(x, dy) >= half + m5 + 1 then -- +1: Draw.apply rounds the position and size to whole px
				for sgn = -1, 1, 2 do
					spark(col, Q.Sparkle1, scx + sgn * x, scy + dy, size, base + 20)
				end
				break
			end
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
			local L = self._L
			if L and L.W == w and L.H == h and L.compact == compact and math.abs(K - k) < 1e-3 then
				return
			end
			K = k
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
