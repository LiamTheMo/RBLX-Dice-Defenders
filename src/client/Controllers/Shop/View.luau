-- Shop menu view: the Starter hero, a row of offer cards and a row of gem packs (or a "Coming soon" card), drawn inside the shared
-- shell's content slot to the shop mockup. Visual only: no NetClient, no game data. Design px under the shell's UIScale; the slot's
-- Size picks the layout (one code path: the mockup's x positions scale with the row width, heights and text sizes do not).
-- View.new(slot) -> :SetSections(ShopLogic.sectionsFor(...), keepScroll?) :OnAction(cb(offerId)) :Destroy()
-- Setters only store state; one deferred rebuild draws it (also on every slot size change).
-- Layers (slot z 22): scroll 23, panels 24, art and glow 25-27, text and buttons 28-31, scroll bar 31-32, Soon card 29-31.
-- Coordinates are slot-relative: mockup (x, y) minus (302, 225) at 1672x941.

local BagSprites = require(script.Parent.Parent.Bag.BagSprites)
local Chrome = require(script.Parent.Parent.Bag.Chrome)
local Parts = require(script.Parent.Parent.Bag.Parts)
local QuestSprites = require(script.Parent.Parent.QuestLog.QuestSprites)
local Shared = require(script.Parent.Parent.SharedSprites)
local ShopLogic = require(script.Parent.ShopLogic)
local ShopSprites = require(script.Parent.ShopSprites)
local Sprites = require(script.Parent.Parent.Sprites)
local UiKit = require(script.Parent.Parent.UiKit)
local Display = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Display"))

local make = UiKit.make

local SPARK = Color3.fromRGB(255, 230, 150)
local LINE = Color3.fromRGB(170, 170, 178)
local ROW_W = 1058 -- the mockup's panel width (x 308..1366)
local HERO_H, OFFER_H, PACK_H, BTN_H = 183, 155, 126, 42 -- panel heights and the unscaled price button height
local ROW_GAP, BAR_W = 14, 10
-- text roles: size (design px), minimum, outline px (cap heights measured on the mockup)
local ROLE = {
	title = { 31, 20, 3, { "STARTER PACK", 242 } }, -- 4th = mockup string and its measured text width: the size is calibrated to it
	bullet = { 24, 15, 2, { "1,200 Gems", 119 } },
	name = { 27, 15, 3, { "AUTO ROLL", 145 } }, -- offer name
	pack = { 22, 15, 2, { "1,200 Gems", 120 } }, -- gem pack name
	heroPrice = { 40, 15, 3, { "399", 65 } },
	price = { 34, 15, 2, { "299", 58 } },
	soon = { 40, 20, 3 },
	soonSub = { 26, 15, 2 },
}
local ICON = { -- price and bullet currency icons: the HUD coin and gem
	Gems = { Image = Sprites.Gem, Size = Shared.Gem.Size },
	Gold = { Image = Sprites.Coin, Size = Shared.Coin.Size },
	Robux = ShopSprites.Robux,
}
local ROLL = { Image = Sprites.Icon.Roll, Size = Vector2.new(256, 185), Ink = Rect.new(4, 7, 252, 181) } -- dice without art, tinted
local Q = QuestSprites
local ART = { -- product art per ShopLogic ART key
	HeroArt = ShopSprites.HeroArt,
	Potion = Q.Potion,
	Clover = ShopSprites.Clover,
	GemBag = ShopSprites.GemBag,
	ChestOpenGems = ShopSprites.ChestOpenGems,
}
local BULLET = { Gem = ICON.Gems, Coin = ICON.Gold, Potion = Q.Potion, Chest = Q.IconChest }
local SPARKS = { -- x / y in art half sizes from its centre, box
	{ Q.Sparkle1, -0.85, -0.6, 20 },
	{ Q.Sparkle2, 0.85, -0.65, 20 },
	{ Q.Sparkle3, -0.9, 0.55, 14 },
	{ Q.Sparkle4, 0.9, 0.5, 14 },
}

local K = 1 -- real px per design px of the current build

local function round(n: number): number
	return math.floor(n + 0.5)
end

-- A sprite record fitted by aspect into bw x bh centred at (cx, cy), by its ink; a raw id is a Fit image in that box.
local function pic(parent, rec, cx: number, cy: number, bw: number, bh: number, z: number, name: string?)
	local i = make("ImageLabel", {
		Name = name or "Art",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z,
	}, parent)
	if type(rec) == "string" then
		i.Image, i.ScaleType = rec, Enum.ScaleType.Fit
		i.Position, i.Size = UDim2.fromOffset(round(cx), round(cy)), UDim2.fromOffset(round(bw), round(bh))
		return i
	end
	local ink = rec.Ink or Rect.new(0, 0, rec.Size.X, rec.Size.Y)
	local s = math.min(bw / ink.Width, bh / ink.Height)
	i.Image, i.ScaleType = rec.Image, Enum.ScaleType.Stretch
	i.Size = UDim2.fromOffset(round(rec.Size.X * s), round(rec.Size.Y * s))
	i.Position = UDim2.fromOffset(
		round(cx + (rec.Size.X / 2 - (ink.Min.X + ink.Max.X) / 2) * s),
		round(cy + (rec.Size.Y / 2 - (ink.Min.Y + ink.Max.Y) / 2) * s)
	)
	return i
end

-- Soft round rarity glow (fades to nothing at its own edge), d wide at its own aspect.
local function glow(parent, key: string, cx: number, cy: number, d: number, z: number)
	local rec = BagSprites[key]
	local g = make("ImageLabel", {
		Name = "Glow",
		BackgroundTransparency = 1,
		Image = rec.Image,
		ScaleType = Enum.ScaleType.Stretch,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(cx), round(cy)),
		Size = UDim2.fromOffset(round(d), round(d * rec.Size.Y / rec.Size.X)),
		ZIndex = z,
	}, parent)
	return g
end

local function sparkles(parent, cx: number, cy: number, w: number, h: number, z: number)
	for _, s in SPARKS do
		local p = pic(parent, s[1], cx + s[2] * w / 2, cy + s[3] * h / 2, s[4], s[4], z, "Sparkle")
		p.ImageColor3 = SPARK
	end
end

local View = {}
View.__index = View

-- Text ------------------------------------------------------------------------------------------------------

-- Live text centred (ax 0.5) or left (ax 0) on y in a box w wide, one-line. size is already fitted by roleSize.
local function label(
	parent,
	name: string,
	text: string,
	role,
	size: number,
	x: number,
	y: number,
	w: number,
	z: number,
	ax: number?
)
	ax = ax or 0.5
	return Parts.text(parent, {
		Name = name,
		Text = text,
		TextSize = size,
		AnchorPoint = Vector2.new(ax, 0.5),
		Position = UDim2.fromOffset(round(x), round(y)),
		Size = UDim2.fromOffset(math.min(round(w), math.ceil(Parts.measure(text, size)) + 2), round(size * 0.75)), -- tight box: cap height
		TextXAlignment = if ax == 0 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = z,
	}, role[3])
end

-- One text role = one size: the largest <= role size at which every string fits w (never under the minimum, 12 real px at least).
local function roleSize(role, strs: { string }, w: number, k: number): number
	local min = math.max(role[2], math.ceil(12 / k))
	local size = role[1]
	if role[4] then -- Roblox TextSize is the line height (cap ~0.7 x size): match the mockup text width instead
		size = math.floor(100 * role[4][2] / Parts.measure(role[4][1], 100))
	end
	for _, s in strs do
		size = math.min(size, Parts.fitSize(s, w, size, min))
	end
	return size
end

-- Price button: Parts.button Green (shared pill) + the currency icon + the live number (or status label) as one centred group.
local function priceButton(
	parent,
	item,
	role,
	size: number,
	icon: number,
	x: number,
	y: number,
	w: number,
	h: number,
	z: number
)
	local text = item.Label or ShopLogic.priceText(item.Price)
	if item.Label then -- a status label never has to fit beside an icon: the price's size class, shorter wording when it would be tiny
		local one = Parts.fitSize(text, w - 16, size, 12)
		if text == "Not available yet" then -- the first wording that fits one line at >= 16 real px
			for _, cand in { "Not available yet", "Unavailable", "Soon" } do
				text = cand
				one = Parts.fitSize(text, w - 16, size, 12)
				if one * K >= 16 then
					break
				end
			end
		end
		size = one
	end
	local btn = Parts.button(parent, {
		Name = "Price",
		Style = "Green",
		Size = UDim2.fromOffset(w, h),
		TextSize = size,
		Label = text,
	})
	btn.AnchorPoint, btn.Position, btn.ZIndex = Vector2.new(0, 0), UDim2.fromOffset(round(x), round(y)), z
	local ref = ICON[item.Currency]
	local iw, gap = 0, 0
	if ref and not item.Label then
		iw, gap = icon * ref.Size.X / ref.Size.Y, math.max(4, icon * 0.2)
	end
	local tw = Parts.measure(text, size)
	local x0 = (w - (iw + gap + tw)) / 2
	local l = btn.Label
	l.TextSize, l.TextXAlignment, l.TextTruncate = size, Enum.TextXAlignment.Left, Enum.TextTruncate.None
	l.Position, l.Size, l.ZIndex =
		UDim2.fromOffset(round(x0 + iw + gap), 0), UDim2.fromOffset(math.ceil(tw) + 4, h), z + 1
	l.UIStroke.Thickness = role[3]
	if iw > 0 then
		pic(btn, ref, x0 + iw / 2, h / 2, iw, icon, z + 1, "CurrencyIcon")
	end
	btn:SetAttribute("Enabled", item.Enabled ~= false)
	return btn
end

-- Build -----------------------------------------------------------------------------------------------------

function View:_buy(btn, item)
	table.insert(
		self._connsBuild,
		btn.Activated:Connect(function()
			if self._onAction then
				self._onAction(item.Id)
			end
		end)
	)
end

-- Die bullet art: the elemental art (Sprites.DieArt) else the Roll glyph tinted with the Display colour.
local function bulletIcon(parent, b, cx: number, cy: number, z: number)
	if b.Icon == "Dice3" then
		local art = Sprites.Dice[Sprites.DieArt[b.DieId or ""] or ""]
		if art then
			return pic(parent, art, cx, cy, 40, 30, z, "BulletIcon")
		end
		local info = Display.Dice[b.DieId or ""]
		local i = pic(parent, ROLL, cx, cy, 40, 30, z, "BulletIcon")
		if info then
			i.ImageColor3 = info.Color
		end
		return i
	end
	return pic(parent, BULLET[b.Icon] or Q.IconChest, cx, cy, 40, 30, z, "BulletIcon")
end

function View:_drawHero(L, item, y: number)
	local fx = L.fx
	local panel = Chrome.panel(self._canvas, {
		Name = "Hero",
		Position = UDim2.fromOffset(L.x0, y),
		Size = UDim2.fromOffset(L.rowW, HERO_H),
		ZIndex = 24,
		Radius = 18,
	})
	local cy = HERO_H / 2
	local artCx = 242 * fx
	for _, g in { { 0, 330 }, { 0, 250 } } do -- warm glow behind the art, kept inside the panel
		glow(panel, "GlowLegendary", artCx + g[1], cy, math.min(g[2], 2 * (artCx - 8)), 25)
	end
	local nh = math.floor(ShopSprites.HeroArt.Size.Y / 1.5) -- never above native at 2560x1440 (scale 1.5): 211 x 121
	pic(panel, ART.HeroArt, artCx, cy + 2, 400 * fx, nh, 26, "Art")
	sparkles(panel, artCx, cy, 330 * fx, 158, 27)
	local function rule(x: number)
		local d = Chrome.divider(panel, {
			Name = "Divider",
			Position = UDim2.fromOffset(round(x), 19),
			Size = UDim2.fromOffset(2, HERO_H - 38),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 28,
		})
		make("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(LINE),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.15, 0),
				NumberSequenceKeypoint.new(0.85, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, d)
	end
	rule(456 * fx)
	rule(786 * fx)
	local textX, textW = 550 * fx, 224 * fx
	label(panel, "Title", string.upper(item.Name), ROLE.title, L.titleSize, 481 * fx, 28, 300 * fx, 29, 0)
	local bullets = item.Bullets or {}
	local pitch = 30
	for i, b in bullets do
		local by = cy + (i - (#bullets + 1) / 2) * pitch + 6
		bulletIcon(panel, b, 505 * fx, by, 28)
		label(panel, "Bullet" .. i, b.Text, ROLE.bullet, L.bulletSize, textX, by, textW, 29, 0)
	end
	local bw = L.heroBw
	local btn = priceButton(
		panel,
		item,
		ROLE.heroPrice,
		L.heroPriceSize,
		L.heroIcon,
		(786 * fx + (L.rowW - 786 * fx - bw) / 2),
		cy - L.heroBtnH / 2,
		bw,
		L.heroBtnH,
		30
	)
	self:_buy(btn, item)
end

-- A card: Full offer panel (tall, text column right of the art) or a gem pack (short).
-- Card height: the mockup's (offer 155, pack 126) with the price pill fixed at its top (offer 97, pack 61); taller only for a 44 real px pill.
local function cardH(L, pack: boolean): number
	return if pack then math.max(PACK_H, 61 + L.btnH + 14) else math.max(OFFER_H, 97 + L.btnH + 12)
end

function View:_drawCard(L, item, x: number, y: number, pack: boolean, w: number, bw: number)
	local fx = L.fx
	local h = cardH(L, pack)
	local panel = Chrome.panel(self._canvas, {
		Name = (if pack then "Pack_" else "Offer_") .. item.Id,
		Position = UDim2.fromOffset(round(x), y),
		Size = UDim2.fromOffset(round(w), h),
		ZIndex = 24,
		Radius = 16,
	})
	panel:SetAttribute("OfferId", item.Id)
	local artZone = (if pack then 129 else 162) * fx -- the pill and text column start here (mockup card x 129 / 162)
	local colCx = artZone + (w - (if pack then 8 else 15) - artZone) / 2
	local artCx = artZone / 2 + 2
	local cy = h / 2
	local gd = math.min(if pack then 150 else 190, 2 * (artCx - 6))
	for _ = 1, 2 do
		glow(panel, if pack then "GlowMythic" else "GlowLegendary", artCx, cy, gd, 25)
	end
	local aw, ah = (if pack then 108 else 133) * fx, if pack then 96 else 123
	if item.Art == "Gems3" then -- three HUD gems: the big one over two tilted, darker ones
		local u = 0.77 -- the mockup's trio: 98 x 69
		local gl = pic(panel, ICON.Gems, artCx - 36 * u, cy + 16 * u, 56 * u, 56 * u, 26, "GemL")
		local gr = pic(panel, ICON.Gems, artCx + 36 * u, cy + 16 * u, 56 * u, 56 * u, 26, "GemR")
		gl.Rotation, gr.Rotation = -14, 14
		gl.ImageColor3, gr.ImageColor3 = Color3.fromRGB(205, 195, 225), Color3.fromRGB(205, 195, 225)
		pic(panel, ICON.Gems, artCx, cy - 8 * u, 80 * u, 80 * u, 27, "Art")
	else
		pic(panel, ART[item.Art] or ART.GemBag, artCx, cy, aw, ah, 26)
	end
	sparkles(panel, artCx, cy, aw, ah, 27)
	local role = if pack then ROLE.pack else ROLE.name
	local nameY = if pack then 33 else 25
	label(
		panel,
		"Name",
		if pack then item.Name else string.upper(item.Name),
		role,
		if pack then L.packSize else L.nameSize,
		colCx,
		nameY,
		w - artZone + 12 * fx,
		29
	)
	for n, line in string.split(item.Desc or "", "\n") do -- the Catalog gives no description today; the mockup's two lines at y 57 / 77
		if line ~= "" then
			label(panel, "Desc" .. n, line, ROLE.bullet, 20, colCx, 57 + (n - 1) * 20, w - artZone, 29)
		end
	end
	local btn = priceButton(
		panel,
		item,
		ROLE.price,
		L.priceSize,
		L.cardIcon,
		colCx - bw / 2,
		if pack then 61 else 97,
		bw,
		L.btnH,
		30
	)
	self:_buy(btn, item)
end

function View:_drawSoon(L, sec)
	local W, H = L.W, L.H
	local w, h = math.min(460, W - 40), math.min(220, H - 16)
	local panel = Chrome.panel(self._soon, {
		Name = "SoonCard",
		Position = UDim2.fromOffset(round((W - w) / 2), round((H - h) / 2)),
		Size = UDim2.fromOffset(w, h),
		ZIndex = 29,
		Radius = 18,
	})
	local ih = math.floor(h * 0.42)
	pic(
		panel,
		if sec.Tab == "GAMEPASSES" then ShopSprites.Crown else ShopSprites.Robux,
		w / 2,
		14 + ih / 2,
		ih * 2,
		ih,
		30,
		"Icon"
	)
	local title = string.upper(sec.Heading or "")
	local ts = roleSize(ROLE.soon, { title }, w - 40, L.k)
	local ss = roleSize(ROLE.soonSub, { "Coming soon" }, w - 40, L.k)
	label(
		panel,
		"Title",
		title,
		ROLE.soon,
		math.min(ts, math.floor(h * 0.17)),
		w / 2,
		14 + ih + (h - 14 - ih) * 0.38,
		w - 40,
		31
	)
	label(panel, "Sub", "Coming soon", ROLE.soonSub, ss, w / 2, h - (h - 14 - ih) * 0.24, w - 40, 31)
end

local function strings(items, f)
	local out = {}
	for _, it in items do
		table.insert(out, f(it))
	end
	return out
end

-- One layout for every size: the slot's width scales the x positions (fx), heights and text sizes stay; price buttons grow to 44 real px.
function View:_build()
	local slot, k = self._slot, self._k
	K = k
	local W, H = slot.Size.X.Offset, slot.Size.Y.Offset
	if W <= 0 or H <= 0 or not self._canvas.Parent then
		return
	end
	for _, conn in self._connsBuild do
		conn:Disconnect()
	end
	table.clear(self._connsBuild)
	for _, parent in { self._canvas, self._soon } do
		for _, ch in parent:GetChildren() do
			ch:Destroy()
		end
	end
	local sections = self._sections
	local soon = sections[1] ~= nil and sections[1].Kind == "Soon"
	self._scroll.Visible = not soon
	self._soon.Visible = soon
	self._bar.Layout(if soon then 0 else H, BAR_W, 4)
	local L = { W = W, H = H, k = k }
	if soon then
		self:_drawSoon(L, sections[1])
		return
	end
	local reserve = if W < 1068 then 18 else 0 -- narrower slots keep a lane for the scroll bar
	L.rowW = math.min(ROW_W, W - 10 - reserve)
	L.fx = L.rowW / ROW_W
	L.x0 = if reserve > 0 then 5 else math.floor((W - L.rowW) / 2)
	L.btnH = math.max(BTN_H, math.ceil(44 / k)) -- >= 44 real px
	L.heroBtnH = math.max(68, L.btnH)
	L.heroBw = math.floor(211 * L.fx)
	L.cols = 3
	L.colW = (L.rowW - 2 * ROW_GAP) / 3
	-- text sizes: one per role across everything it labels
	local hero, offers, packs = nil, {}, {}
	for _, sec in sections do
		if sec.Kind == "Hero" then
			hero = sec.Items[1]
		elseif sec.Heading == "GEMS" and #sections > 1 then
			packs = sec.Items
		else
			offers = sec.Items
		end
	end
	local fx = L.fx
	if hero then
		L.titleSize = roleSize(ROLE.title, { string.upper(hero.Name) }, 300 * fx, k)
		L.bulletSize = roleSize(
			ROLE.bullet,
			strings(hero.Bullets or {}, function(b)
				return b.Text
			end),
			224 * fx,
			k
		)
		L.heroIcon = math.floor(L.heroBtnH * 0.6)
		L.heroPriceSize =
			roleSize(ROLE.heroPrice, { ShopLogic.priceText(hero.Price) }, L.heroBw - 20 - L.heroIcon * 1.3, k)
	end
	L.packW = (L.rowW - 3 * 12.33) / 4 -- the mockup's 4 pack columns
	local textW = L.colW - 8 - 150 * fx
	local packTextW = L.packW - 8 - 129 * fx
	L.nameSize = roleSize(
		ROLE.name,
		strings(offers, function(i)
			return string.upper(i.Name)
		end),
		textW,
		k
	)
	L.packSize = roleSize(
		ROLE.pack,
		strings(packs, function(i)
			return i.Name
		end),
		packTextW,
		k
	)
	local all = {}
	for _, i in offers do
		table.insert(all, ShopLogic.priceText(i.Price))
	end
	for _, i in packs do
		table.insert(all, ShopLogic.priceText(i.Price))
	end
	L.cardIcon = math.floor(L.btnH * 0.64)
	L.priceSize = roleSize(ROLE.price, all, 118 * fx - 16 - L.cardIcon * 1.3, k)
	local totalH, rowsH = 0, {}
	local single = #sections == 1
	for _, sec in sections do
		local h = if sec.Kind == "Hero" then HERO_H else cardH(L, sec.Heading == "GEMS" and not single)
		table.insert(rowsH, h)
		totalH += h
	end
	totalH += (#sections - 1) * ROW_GAP
	local y = if single and not self._compactish then math.max(1, math.floor((H - totalH) / 2)) else 1
	local gap = ROW_GAP
	for i, sec in sections do
		if sec.Kind == "Hero" then
			self:_drawHero(L, sec.Items[1], y)
		else
			local items = sec.Items or {}
			local pack = sec.Heading == "GEMS" and not single
			local labelW = 0
			for _, it in items do
				if it.Label then
					labelW = math.max(labelW, Parts.measure(it.Label, 18) + 28)
				end
			end
			local cw = if pack then L.packW else L.colW
			local colText = cw - (if pack then 8 else 15) - (if pack then 129 else 162) * fx
			local bw = math.floor(math.min(colText, math.max((if pack then 118 else 167) * fx, labelW)))
			for j, item in items do
				local x = if pack
					then L.x0 + (j - 1) * (cw + 12.33) -- filled from the left
					else L.x0 + (3 - #items) * (L.colW + ROW_GAP) / 2 + (j - 1) * (L.colW + ROW_GAP)
				self:_drawCard(L, item, x, y, pack, cw, bw)
			end
		end
		gap = if sec.Kind == "Hero" then 16 else ROW_GAP -- mockup: hero to offers 16, offers to packs 14
		y += rowsH[i] + gap
	end
	local canvasH = math.ceil(y - gap + 4)
	self._canvas.Size = UDim2.new(1, 0, 0, canvasH)
	self._bar.Track.Visible = canvasH > H
end

-- Public ----------------------------------------------------------------------------------------------------

function View.new(slot)
	local self = setmetatable({}, View)
	self._conns, self._connsBuild, self._sections, self._slot, self._k = {}, {}, {}, slot, 1
	local scroll = make("ScrollingFrame", {
		Name = "ShopScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0, -- the styled bar replaces the native one; wheel, touch and drag still scroll
		ScrollBarImageTransparency = 1,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 1),
		ZIndex = slot.ZIndex + 1,
	}, slot)
	local canvas = make(
		"Frame",
		{ Name = "Canvas", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), ZIndex = scroll.ZIndex },
		scroll
	)
	local soon = make("Frame", {
		Name = "Soon",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = scroll.ZIndex + 6,
	}, slot)
	self._scroll, self._canvas, self._soon = scroll, canvas, soon
	self._bar = Parts.scrollBar(slot, scroll, scroll.ZIndex + 8)
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
			local k = 1
			local a = slot
			while a and a.Name ~= "Root" do -- real px per design px: every UIScale above the slot except the open animation's Pop
				for _, ch in a:GetChildren() do
					if ch:IsA("UIScale") and ch.Name ~= "Pop" then
						k *= ch.Scale
						if not scaleSeen[ch] then -- a later scale change (window resize) must rebuild: k sizes the hit boxes
							scaleSeen[ch] = true
							table.insert(self._conns, ch:GetPropertyChangedSignal("Scale"):Connect(rebuild))
						end
					end
				end
				a = a.Parent
			end
			self._k = math.max(k, 0.01)
			self._compactish = slot:GetAttribute("Compact") == true
			self:_build()
		end)
	end
	self._rebuild = rebuild
	table.insert(self._conns, slot:GetPropertyChangedSignal("Size"):Connect(rebuild))
	table.insert(self._conns, slot:GetAttributeChangedSignal("Compact"):Connect(rebuild))
	rebuild()
	return self
end

function View:SetSections(sections, keepScroll: boolean?)
	self._sections = sections
	if not keepScroll then
		self._scroll.CanvasPosition = Vector2.zero
	end
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
	self._soon:Destroy()
	self._scroll:Destroy()
end

return View
