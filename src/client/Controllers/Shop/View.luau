-- Shop menu view: a hero pack, headed card rows and a "coming soon" card, drawn inside the shared shell's content slot.
-- Visual only: no NetClient, no game data. Design px under the shell's UIScale; the slot's Size offset and "Compact" attribute pick the layout.
-- View.new(slot) -> :SetSections(ShopLogic.sectionsFor(...)) :OnAction(cb(productId)) :Destroy()
-- Setters only store state; one deferred rebuild draws it (also on every slot size / Compact change).
-- One ScrollingFrame (AutomaticCanvasSize Y) holds everything; the styled bar is Parts.scrollBar. Layers: scroll 23, card skin 24,
-- card content 25-28, heading plates and rules 30, text 31, bar 31-32, Soon card 30-32 (slot z 22).

local TextService = game:GetService("TextService")

local BagSprites = require(script.Parent.Parent.Bag.BagSprites)
local Parts = require(script.Parent.Parent.Bag.Parts)
local Draw = require(script.Parent.Parent.QuestLog.Draw)
local RollSprites = require(script.Parent.Parent.Roll.RollSprites)
local ShopLogic = require(script.Parent.ShopLogic)
local ShopSprites = require(script.Parent.ShopSprites)
local Sprites = require(script.Parent.Parent.Sprites)
local UiKit = require(script.Parent.Parent.UiKit)

local Q, Bag = Draw.Q, Draw.Bag
local make = UiKit.make

local GOLD = Color3.fromRGB(255, 200, 60)
local DIM = Color3.fromRGB(205, 210, 235)
local SPARK = Color3.fromRGB(255, 230, 150)
local PANEL_INS = { 4, 2, 4, 10 } -- visible insets (source px: left, top, right, bottom) of the LeftPanel sprite inside its Ink rect
local PANEL_K = 0.5 -- slice scale of every card (as the Roll and Play panels)
local PLATE_Z, TEXT_Z = 30, 31

-- text roles: size, fit minimum, fill, outline colour, outline px (plan section d); c = the Compact tier
local ROLE = {
	head = {
		size = 40,
		min = 22,
		cs = 22,
		cmin = 18,
		fill = Color3.fromRGB(250, 248, 245),
		line = Color3.fromRGB(45, 3, 8),
		px = 3,
	},
	name = {
		size = 36,
		min = 20,
		cs = 20,
		cmin = 18,
		fill = Color3.fromRGB(249, 248, 248),
		line = Color3.fromRGB(66, 9, 42),
		px = 3,
	},
	desc = {
		size = 22,
		min = 15,
		cs = 18,
		cmin = 15,
		fill = Color3.fromRGB(251, 251, 251),
		line = Color3.fromRGB(69, 8, 49),
		px = 2,
	},
	bullet = {
		size = 30,
		min = 18,
		cs = 18,
		cmin = 18,
		fill = Color3.fromRGB(250, 250, 250),
		line = Color3.fromRGB(69, 8, 46),
		px = 2,
	},
	price = {
		size = 56,
		min = 15,
		cs = 26,
		cmin = 15,
		fill = Color3.fromRGB(244, 242, 243),
		line = Color3.fromRGB(4, 11, 3),
		px = 3,
	},
	soon = { size = 36, min = 22, cs = 24, cmin = 18, fill = Color3.new(1, 1, 1), px = 3 },
	soonSub = { size = 26, min = 16, cs = 18, cmin = 15, fill = DIM, px = 3 },
}
-- price button tiers: box w x h, text size, Robux icon height, icon-to-number gap
-- (frames: the BtnGreen art sits ~3.4 px inside, so the visible ink is the ref 226 x 77 hero / 174 x 46 card)
local TIER = {
	hero = { w = 234, h = 83, size = 56, icon = 49, gap = 13 }, -- ink (outline + shadow) 226 x 75 = the reference button
	card = { w = 178, h = 50, size = 36, icon = 33, gap = 5 },
	compact = { w = 150, h = 56, size = 26, icon = 26, gap = 4 },
}
-- heading plates: sprite, ink box (fitted by aspect, never stretched), card top below the plate top
local HEAD = {
	STARTER = { rec = ShopSprites.StarterCap, w = 440, h = 78, drop = 8 },
	GAMEPASSES = { rec = ShopSprites.GPHeading, w = 468, h = 75, below = 77, drop = 10 },
	GEMS = { rec = ShopSprites.GemsHeading, w = 450, h = 50, below = 57 },
}
local RULE = Bag.DividerGold -- centre diamond with a line each side: the halves are cut so each keeps one whole diamond
local RULE_LEFT, RULE_RIGHT, RULE_LLEN, RULE_RLEN = 0, 334, 378, 375 -- source x / width of the left and right pieces: each ends at its own diamond rim
local ART = { -- product art keys (Shop\SampleData)
	HeroArt = ShopSprites.HeroArt,
	AutoRoll = Sprites.Icon.Roll,
	Crown = Q.Crown,
	Clover = ShopSprites.Clover,
	GemBag = ShopSprites.GemBag,
	ChestOpenGems = ShopSprites.ChestOpenGems,
	Gems3 = "Gems3", -- composed in art()
}
local GEM = { Image = Sprites.Gem, Size = Vector2.new(128, 124), Ink = Rect.new(3, 3, 125, 121) } -- the raw HUD gem has transparent margins (measured from its PNG)
local BULLET_BOX = { Gem = { 36, 31 }, Dice3 = { 44, 30 }, Potion = { 28, 32 }, Chest = { 48, 33 } } -- Full VISIBLE icon boxes (the ref's sizes), art fitted by aspect
local BULLET = { Gem = GEM, Dice3 = RollSprites.Dice3, Potion = Q.Potion, Chest = Q.IconChest }
local CARD_SPARKS = { -- per card art: x / y in art half-sizes from its centre, box
	{ Q.Sparkle1, -0.8, -0.6, 18, 18 },
	{ Q.Sparkle2, 0.85, -0.65, 18, 18 },
	{ Q.Sparkle3, -0.85, 0.55, 13, 13 },
	{ Q.Sparkle4, 0.9, 0.5, 13, 13 },
}

local function round(n: number): number
	return math.floor(n + 0.5)
end

local K = 1 -- real px per design px under the shell's UIScales (set per build)

local function measure(str: string, size: number): number
	return TextService:GetTextSize(str, size * K, Enum.Font.FredokaOne, Vector2.new(1e5, 1e5)).X / K
end

-- One text role = one size: the largest size <= size at which every string fits w (never under min).
local function roleSize(strs: { string }, w: number, size: number, min: number): number
	for _, s in strs do
		while size > min and measure(s, size) > w * 0.97 do
			size -= 1
		end
	end
	return size
end

local function role(name: string, compact: boolean)
	local r = ROLE[name]
	if compact then
		return r.cs, r.cmin
	end
	return r.size, math.max(r.min, math.ceil(12 / K)) -- Full tiers: never under 12 real px
end

-- Live text (ax 0 left, 0.5 centre) centred on y in a box w wide; the role size is fitted by the caller, this only guards a squeezed box.
local function label(
	parent,
	name: string,
	text: string,
	r,
	size: number,
	x: number,
	y: number,
	w: number,
	z: number,
	ax: number?
)
	ax = ax or 0.5
	local l = Parts.text(parent, {
		Name = name,
		Text = text,
		TextSize = size,
		TextColor3 = r.fill,
		AnchorPoint = Vector2.new(ax, 0.5),
		Position = UDim2.fromOffset(round(x), round(y)),
		Size = UDim2.fromOffset(round(w), round(size * 1.2)),
		TextXAlignment = if ax == 0 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = z,
	}, r.px)
	local stroke = l:FindFirstChildOfClass("UIStroke")
	if r.line then
		stroke.Color = r.line
	end
	local tw = measure(text, size)
	if tw > w * 0.97 then
		l.TextSize = math.max(math.min(size, math.ceil(12 / K)), math.floor(size * w * 0.97 / tw)) -- never under 12 real px
	end
	return l
end

-- A sprite fitted by aspect into w x h centred at (cx, cy): records by their ink, raw ids as a Fit image.
local function sprite(parent, ref, cx: number, cy: number, w: number, h: number, z: number, name: string?)
	local i = Draw.img(parent, { Name = name or "Art", ZIndex = z })
	if type(ref) == "table" then
		local iw, ih = Draw.fitIn(ref, w, h)
		Draw.apply(i, ref, cx, cy, iw, ih)
	else
		i.Image, i.ScaleType = ref, Enum.ScaleType.Fit
		i.AnchorPoint, i.Position, i.Size =
			Vector2.new(0.5, 0.5), UDim2.fromOffset(round(cx), round(cy)), UDim2.fromOffset(w, h)
	end
	return i
end

-- The whole source image (margins included) w wide at its own aspect, centred at (cx, cy).
local function whole(parent, rec, cx: number, cy: number, w: number, z: number, name: string)
	local i = Draw.img(parent, {
		Name = name,
		Image = rec.Image,
		ScaleType = Enum.ScaleType.Stretch,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(cx), round(cy)),
		Size = UDim2.fromOffset(round(w), round(w * rec.Size.Y / rec.Size.X)),
		ZIndex = z,
	})
	return i
end

local function art(parent, key: string, cx: number, cy: number, w: number, h: number, z: number)
	if key == "Gems3" then -- the reference trio: a big gem on top overlapping two smaller, darker ones tilted outwards behind it
		local u = h / 88
		local gl = sprite(parent, Sprites.Gem, cx - 36 * u, cy + 16 * u, 56 * u, 56 * u, z, "GemL")
		local gr = sprite(parent, Sprites.Gem, cx + 36 * u, cy + 16 * u, 56 * u, 56 * u, z, "GemR")
		gl.Rotation, gr.Rotation = -14, 14
		gl.ImageColor3, gr.ImageColor3 = Color3.fromRGB(205, 195, 225), Color3.fromRGB(205, 195, 225)
		sprite(parent, Sprites.Gem, cx, cy - 8 * u, 80 * u, 80 * u, z + 1, "GemC")
	else
		sprite(parent, ART[key], cx, cy, w, h, z)
	end
end

-- Card skin by its VISIBLE box (x, y, w, h); the returned frame is exactly that box (children use card-local px).
local function card(parent, name: string, x: number, y: number, w: number, h: number, z: number)
	local l, t, r, b = PANEL_INS[1], PANEL_INS[2], PANEL_INS[3], PANEL_INS[4]
	local k = PANEL_K
	local skin = Draw.img(parent, { Name = name .. "Skin", ZIndex = z })
	Draw.apply(
		skin,
		Bag.LeftPanel,
		x + w / 2 + (r - l) / 2 * k,
		y + h / 2 + (b - t) / 2 * k,
		w + (l + r) * k,
		h + (t + b) * k,
		k
	)
	return Draw.img(parent, {
		Name = name,
		Position = UDim2.fromOffset(round(x), round(y)),
		Size = UDim2.fromOffset(w, h),
		ZIndex = z + 1,
	}, "Frame")
end

-- A rarity glow (the whole soft-edged image, fading to nothing at its own edge) w x h centred at (cx, cy), kept inside its card.
local function glow(parent, key: string, cx: number, cy: number, w: number, h: number, z: number)
	return Draw.img(parent, {
		Name = "Glow",
		Image = BagSprites[key].Image,
		ScaleType = Enum.ScaleType.Stretch,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(cx), round(cy)),
		Size = UDim2.fromOffset(round(w), round(h)),
		ZIndex = z,
	})
end

local View = {}
View.__index = View
View.Art, View.Bullets = ART, BULLET -- the key tables (the spec checks SampleData against them)

-- Layout ----------------------------------------------------------------------------------------------------

-- Every number is design px; canvas y 0 = the top of the scroll's padding box. W x H = the content slot.
local function compute(W: number, H: number, compact: boolean)
	local L = { W = W, H = H, compact = compact }
	if compact then
		L.pad = { l = 20, r = 20, t = 10, b = 10 } -- symmetric: the cards and plates sit on the content axis
		L.barW, L.barInset, L.gap = 8, 8, 10
		L.inner = W - 40
		L.cols = if (L.inner - 20) / 3 >= 250 then 3 else 2
		L.plateK, L.ruleK = 0.64, 0.45
		L.heroArtW = math.floor(L.inner * 0.37) -- the hero art is ~37% of the hero frame; the bullets get what the art, divider and button leave
		L.heroBw = 126 -- narrower than the card buttons so the bullets keep 18 design px (14 real) text beside the art
		L.bulletW = L.inner - L.heroArtW - 80 - L.heroBw
	else
		L.pad = { l = 28, r = 28, t = 16, b = 16 }
		L.barW, L.barInset, L.gap = 12, 9, 15
		L.inner = W - 56
		L.cols = 3
		L.plateK, L.ruleK = 1, 0.85
	end
	L.colW = math.floor((L.inner - (L.cols - 1) * L.gap) / L.cols)
	L.rowW = L.cols * L.colW + (L.cols - 1) * L.gap
	L.x0 = math.floor((L.inner - L.rowW) / 2)
	L.touch = math.ceil(44 / K) -- smallest button height that is >= 44 real px
	L.btnH = function(tier)
		return math.max(TIER[tier].h, L.touch)
	end
	L.cardTier = if compact then "compact" else "card"
	L.heroTier = if compact then "compact" else "hero"
	-- card height: Full = the reference card (button grows past 45 for touch); Compact = vertical stack
	L.cardH = function(hasDesc: boolean)
		local bh = L.btnH(L.cardTier)
		if compact then
			return 8 + (if hasDesc then 56 else 50) + 22 + (if hasDesc then 46 else 0) + bh + 8
		end
		return (if hasDesc then 163 else 120) + bh - TIER.card.h
	end
	L.heroH = if compact then 150 else 208
	-- Full is drawn in the reference x units (card 373 wide, hero row 1149); a narrower slot scales every x with its card / row so
	-- nothing leaves it (heights, text sizes and the 44 px touch height are not scaled)
	L.fc = if compact then 1 else math.min(1, L.colW / 373)
	L.fh = if compact then 1 else math.min(1, L.rowW / 1149)
	return L
end

-- Price button: Parts.button Green (9-slice, interact) + Robux icon + live number as one centred group.
local function priceButton(
	parent,
	tierName: string,
	price: number,
	size: number,
	h: number,
	x: number,
	y: number,
	z: number,
	bw: number
)
	local t = TIER[tierName]
	local text = ShopLogic.priceText(price)
	local btn = Parts.button(parent, {
		Name = "Price",
		Style = "Green",
		Size = UDim2.fromOffset(bw, h),
		TextSize = size,
		Label = text,
	})
	btn.AnchorPoint, btn.Position, btn.ZIndex = Vector2.new(0, 0), UDim2.fromOffset(round(x), round(y)), z
	local ink = ShopSprites.Robux.Ink
	local iw = t.icon * ink.Width / ink.Height
	local tw = measure(text, size)
	local x0 = (bw - (iw + t.gap + tw)) / 2
	local l = btn.Label
	l.TextColor3, l.TextSize, l.TextXAlignment, l.TextTruncate =
		ROLE.price.fill, size, Enum.TextXAlignment.Left, Enum.TextTruncate.None
	l.Position, l.Size, l.ZIndex =
		UDim2.fromOffset(round(x0 + iw + t.gap), 0), UDim2.fromOffset(math.ceil(tw) + 4, h), z + 1
	local stroke = l:FindFirstChildOfClass("UIStroke")
	stroke.Color, stroke.Thickness = ROLE.price.line, ROLE.price.px
	sprite(btn, ShopSprites.Robux, x0 + iw / 2, h / 2, iw, t.icon, z + 1, "RobuxIcon")
	return btn
end

-- Build -----------------------------------------------------------------------------------------------------

-- Plate (whole sprite fitted by aspect) + live heading + side rules, centred on cx with its ink top at y; returns its ink height.
function View:_plate(L, key: string, text: string, cx: number, y: number, rules: boolean, right: number?)
	local h = HEAD[key] or HEAD.GEMS
	local c = self._canvas
	local pw, ph = Draw.fitIn(h.rec, h.w * L.plateK, h.h * L.plateK)
	local cy = y + ph / 2
	if right then
		cx = math.min(cx, right - pw / 2) -- a narrow slot: the plate stays inside the hero row
	end
	local plate = Draw.img(c, { Name = "Plate", ZIndex = PLATE_Z })
	Draw.apply(plate, h.rec, cx, cy, pw, ph)
	if rules then
		local k = L.ruleK
		local inner = pw / 2 + 7 -- the rules' inner ends: just outside the plate
		local fit = math.floor((cx - inner) / k) -- source px that fit before the content edge: the outer end is cut, never stretched
		if fit > 0 then
			for _, side in { -1, 1 } do
				local len = math.min(if side < 0 then RULE_LLEN else RULE_RLEN, fit)
				local rp = Draw.img(c, { Name = "Rule", ZIndex = PLATE_Z })
				rp.Image, rp.ScaleType = RULE.Image, Enum.ScaleType.Stretch
				rp.ImageRectOffset = Vector2.new(if side < 0 then RULE_LEFT + RULE_LLEN - len else RULE_RIGHT, 0)
				rp.ImageRectSize = Vector2.new(len, RULE.Size.Y)
				rp.AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5)
				rp.Position = UDim2.fromOffset(
					round(cx + side * inner),
					round(cy + (h.drop or 0) * L.plateK + self._headSize * 0.06)
				) -- on the heading glyph centre, not the text box or the crown-extended plate centre
				rp.Size = UDim2.fromOffset(round(len * k), round(RULE.Size.Y * k))
			end
		end
	end
	local hs = self._headSize
	if key == "STARTER" and not L.compact then
		hs = roleSize({ text }, pw * 0.7, 46, ROLE.head.min) -- the ref's STARTER PACK text is larger than the other headings
	end
	label(c, "Heading", text, ROLE.head, hs, cx, cy + (h.drop or 0) * L.plateK, pw * 0.7, TEXT_Z)
	return ph
end

function View:_drawHero(L, item, x: number, y: number, w: number)
	local c = L.compact
	local f = L.fh
	local h = L.heroH
	local holder = card(self._canvas, "Hero", x, y, w, h, 24)
	local z = 25
	local btnH = L.btnH(L.heroTier)
	local bw = if c then L.heroBw else round(TIER[L.heroTier].w * f)
	local bullets = item.Bullets or {}
	local bsize = self._bulletSize
	local pitch, top, iconCx, textX, textW, divX, btnX, btnY
	if c then
		local aw = L.heroArtW
		glow(holder, "GlowLegendary", (aw + 16) / 2, h / 2 + 4, aw + 10, h - 10, z)
		local frame = Draw.img(
			holder,
			{ Name = "ArtFrame", Size = UDim2.fromOffset(aw + 16, h), ZIndex = z, ClipsDescendants = true },
			"Frame"
		)
		whole(frame, ShopSprites.HeroArt, (aw + 16) / 2, h / 2 + 1, aw, z + 1, "Art")
		pitch, iconCx = 28, 8 + aw + 8 + 14
		top = h / 2 + 4 - 1.5 * pitch
		btnX = w - 12 - bw
		divX = btnX - 12
		textX = iconCx + 14 + 6
		textW = divX - 6 - textX
		btnY = h / 2 + 4 - btnH / 2
		local maxW = 0
		for _, b in bullets do
			maxW = math.max(maxW, measure(b.Text, bsize))
		end
		local slack = math.max(0, textW - maxW) / 2 -- centre the bullet block between the art and the divider
		iconCx, textX = iconCx + slack, textX + slack
	else
		for _, g in { { 600, 206 }, { 460, 200 }, { 340, 170 }, { 240, 140 } } do -- stacked: the reference glow is strong and orange to the art's edge
			glow(holder, "GlowLegendary", 255 * f, 104, g[1] * f, g[2], z)
		end
		local frame = Draw.img(holder, {
			Name = "ArtFrame",
			Size = UDim2.fromOffset(round(520 * f), h),
			ZIndex = z,
			ClipsDescendants = true,
		}, "Frame")
		whole(frame, ShopSprites.HeroArt, 246 * f, 90, 446 * f, z + 1, "Art") -- visible width incl. its baked sparkles = 684 of 710 source px = the ref's 430
		pitch, top, iconCx, textX, textW = 32.83, 77.5, 567 * f, 613 * f, 214 * f -- the ref bullet rows 77.5 / 110 / 142.5 / 176
		divX, btnX, btnY = round(845 * f), round(880 * f), 128 - btnH / 2 -- the button centred on the divider
	end
	for i, b in bullets do
		local cy = top + (i - 1) * pitch
		local bb = if c then { 28, 28 } else BULLET_BOX[b.Icon]
		sprite(holder, BULLET[b.Icon], iconCx, cy, bb[1], bb[2], z + 2, "BulletIcon")
		label(holder, "Bullet", b.Text, ROLE.bullet, bsize, textX, cy, textW, z + 2, 0)
	end
	local div = Draw.img(holder, {
		Name = "Divider",
		Position = UDim2.fromOffset(divX, if c then 20 else 77),
		Size = UDim2.fromOffset(4, if c then h - 40 else 120),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = z + 2,
	}, "Frame")
	div.BackgroundTransparency = 0
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(GOLD),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0),
			NumberSequenceKeypoint.new(0.8, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, div)
	self:_buy(holder, L.heroTier, item, self._priceHero, btnH, btnX, btnY, z + 3, bw)
end

function View:_buy(parent, tier: string, item, size: number, h: number, x: number, y: number, z: number, bw: number)
	local btn = priceButton(parent, tier, item.Price, size, h, x, y, z, bw)
	table.insert(
		self._connsBuild,
		btn.Activated:Connect(function()
			if self._onAction then
				self._onAction(item.Id)
			end
		end)
	)
end

-- One product card at (x, y) in the canvas; Full = the reference columns, Compact = a vertical stack.
function View:_drawCard(L, item, x: number, y: number, hasDesc: boolean)
	local c = L.compact
	local f = L.fc
	local w, h = L.colW, L.cardH(hasDesc)
	local holder = card(self._canvas, "Card", x, y, w, h, 24)
	local bw = round(TIER[L.cardTier].w * f)
	local bh = L.btnH(L.cardTier)
	local ns = self._nameSize
	local ds = self._descSize
	local cx, artCx, artCy, artW, artH, nameY, descY, btnX, btnY
	if c then
		artH = if hasDesc then 56 else 50
		artCx, artCy, artW = w / 2, 8 + artH / 2, math.min(w - 24, artH * 2)
		nameY = 8 + artH + 11
		descY = nameY + 11
		cx, btnX, btnY = w / 2, (w - bw) / 2, 8 + artH + 22 + (if hasDesc then 46 else 0)
	else
		artCx, artCy = (if hasDesc then 84 else 90) * f, if hasDesc then 79 else 60
		artW, artH = (if hasDesc then 135 else 138) * f, if hasDesc then 115 else 88 -- the ref's visible art sizes
		nameY, descY = if hasDesc then 26 else 34, 51
		cx = (if hasDesc then 253 else 273) * f -- the ref's text column sits left on the passes, right on the gem packs
		btnX, btnY = cx - bw / 2, if hasDesc then 101 else 58
	end
	-- the glow fades to nothing at its own edge, so it is made larger than the art (a halo shows around it) and kept inside the card rim
	local gw, gh = artW * 2.2, artH * 2.2
	gw, gh = math.min(gw, 2 * artCx - 2, 2 * (w - artCx) - 2), math.min(gh, 2 * artCy - 2, 2 * (h - artCy) - 2)
	if c then
		gw = math.min(gw, gh) -- phones: a round glow, never the art's 2:1 box
		gh = gw
	end
	local gk = if hasDesc then "GlowLegendary" else "GlowMythic"
	for _, k in { 1, 1, 0.85, 0.7 } do -- stacked layers: the reference glow is strong, with a clear ring around the art
		glow(holder, gk, artCx, artCy, gw * k, gh * k, 25)
	end
	art(holder, item.Art, artCx, artCy, artW, artH, 26)
	local sk = if c then 0.7 else 1
	for _, s in CARD_SPARKS do
		local sp =
			sprite(holder, s[1], artCx + s[2] * artW / 2, artCy + s[3] * artH / 2, s[4] * sk, s[5] * sk, 27, "Sparkle")
		sp.ImageColor3 = SPARK
	end
	local textW = if c then w - 24 else 186 * f
	label(holder, "Name", item.Name, ROLE.name, ns, cx, nameY, textW, 27)
	if item.Desc then
		local pitch = 23
		local first = if c then descY + 12 else descY + 8 -- two centred lines, full: centres y 59 / 82
		for i, line in string.split(item.Desc, "\n") do
			label(holder, "Desc" .. i, line, ROLE.desc, ds, cx, first + (i - 1) * pitch, textW, 27)
		end
	end
	self:_buy(holder, L.cardTier, item, self._priceCard, bh, btnX, btnY, 28, bw)
end

function View:_drawSoon(L, sec)
	local c = L.compact
	local W, H = L.W, L.H
	local w, h = if c then 340 else 520, if c then 150 else 240
	local holder = card(self._soon, "SoonCard", (W - w) / 2, (H - h) / 2, w, h, 30)
	local ih = if c then 60 else 100
	sprite(holder, ShopSprites.IconShards, w / 2, (if c then 15 else 20) + ih / 2, ih * 2, ih, 31, "Icon")
	local ts, tmin = role("soon", c)
	local ss, smin = role("soonSub", c)
	local title = string.upper(sec.Heading or "")
	label(
		holder,
		"Title",
		title,
		ROLE.soon,
		roleSize({ title }, w - 40, ts, tmin),
		w / 2,
		if c then 95 else 150,
		w - 40,
		32
	)
	local sub = "Coming soon"
	label(
		holder,
		"Sub",
		sub,
		ROLE.soonSub,
		roleSize({ sub }, w - 40, ss, smin),
		w / 2,
		if c then 122 else 190,
		w - 40,
		32
	)
end

-- One text size per role across everything it labels (fitted to the narrowest member).
function View:_roles(L)
	local c = L.compact
	local heads, names, descs, bullets, hero, cardP = {}, {}, {}, {}, {}, {}
	for _, sec in self._roleSample or self._sections do -- every tab's content, so a card is the same size on each tab
		table.insert(heads, string.upper(sec.Heading or ""))
		for _, item in sec.Items or {} do
			if sec.Kind == "Hero" then
				table.insert(hero, ShopLogic.priceText(item.Price))
				for _, b in item.Bullets or {} do
					table.insert(bullets, b.Text)
				end
			else
				table.insert(names, item.Name)
				table.insert(cardP, ShopLogic.priceText(item.Price))
				for _, line in string.split(item.Desc or "", "\n") do
					table.insert(descs, line)
				end
			end
		end
	end
	local function size(name, strs, w)
		local s, min = role(name, c)
		return roleSize(strs, w, s, min)
	end
	local function priceSize(strs, tier, f)
		local t = TIER[tier]
		local s, min = role("price", c)
		return roleSize(strs, t.w * f - 16 - t.icon * 0.88 - t.gap, math.min(s, t.size), min)
	end
	local plateW = HEAD.GAMEPASSES.w * L.plateK * 0.9 * 0.64 -- narrowest plate text width
	self._headSize = size("head", heads, if c then 150 else plateW)
	self._nameSize = size("name", names, if c then L.colW - 24 else 186 * L.fc)
	self._descSize = size("desc", descs, if c then L.colW - 24 else 186 * L.fc)
	self._bulletSize = size("bullet", bullets, if c then L.bulletW else 202 * L.fh)
	self._priceHero = priceSize(hero, L.heroTier, L.fh)
	self._priceCard = priceSize(cardP, L.cardTier, L.fc)
end

function View:_build()
	local L = self._L
	if not L or not self._canvas.Parent then
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
	local soon = self._sections[1] and self._sections[1].Kind == "Soon"
	self._scroll.Visible = not soon
	self._soon.Visible = soon
	self._bar.Layout(if soon then 0 else L.H, L.barW, L.barInset)
	self._bar.Track.Visible = not soon and #self._sections > 0
	if soon then
		self:_drawSoon(L, self._sections[1])
		return
	end
	self:_roles(L)
	local c = L.compact
	local cx = L.inner / 2
	local y = 0
	local afterHero = false
	for i, sec in self._sections do
		if sec.Kind == "Hero" then
			local ph = self:_plate(
				L,
				"STARTER",
				string.upper(sec.Heading or ""),
				if c then cx else L.x0 + 668,
				if c then y else y - 13,
				false,
				L.x0 + L.rowW
			)
			local top = if c then y + ph - 8 else y
			self:_drawHero(L, sec.Items[1], if c then 0 else L.x0, top, if c then L.inner else L.rowW)
			y = top + L.heroH
			afterHero = true
		else
			local headTop = if afterHero and not c then y - 13 else y + (if i > 1 then 10 else 0)
			local key = if HEAD[sec.Heading] then sec.Heading else "GEMS"
			local ph = self:_plate(L, key, string.upper(sec.Heading or ""), cx, headTop, true)
			y = headTop + (if c then ph + 6 else HEAD[key].below)
			local items = sec.Items or {}
			local hasDesc = items[1] ~= nil and items[1].Desc ~= nil
			local ch = L.cardH(hasDesc)
			for j, item in items do
				local row, col = math.ceil(j / L.cols), (j - 1) % L.cols
				local inRow = math.min(L.cols, #items - (row - 1) * L.cols)
				local x = L.x0 + (L.cols - inRow) * (L.colW + L.gap) / 2 + col * (L.colW + L.gap)
				self:_drawCard(L, item, x, y + (row - 1) * (ch + L.gap), hasDesc)
			end
			local rows = math.ceil(#items / L.cols)
			y += rows * ch + math.max(0, rows - 1) * L.gap
			afterHero = false
		end
	end
	self._canvas.Size = UDim2.new(1, 0, 0, math.ceil(y))
end

-- Public ----------------------------------------------------------------------------------------------------

function View.new(slot)
	local self = setmetatable({}, View)
	self._conns, self._connsBuild, self._sections = {}, {}, {}
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
	local pad = make("UIPadding", {}, scroll)
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
		ZIndex = scroll.ZIndex + 7,
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
			local L = compute(w, h, slot:GetAttribute("Compact") == true)
			pad.PaddingLeft, pad.PaddingRight = UDim.new(0, L.pad.l), UDim.new(0, L.pad.r)
			pad.PaddingTop, pad.PaddingBottom = UDim.new(0, L.pad.t), UDim.new(0, L.pad.b)
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

function View:SetSections(sections)
	self._sections = sections
	self._scroll.CanvasPosition = Vector2.zero
	self._rebuild()
end

-- The sections of every tab: role sizes are fitted across all of them.
function View:SetRoleSample(sections)
	self._roleSample = sections
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
