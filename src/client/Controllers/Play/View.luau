-- Play menu view, two pages in the shared window's content box (the Shell draws the title, close X and the WORLDS / 1v1 tabs):
--   WORLDS: world banner cards | first-time milestones | selected world, repeat rewards, START
--   1v1:    rank ladder | your record | your rank, DR, progress, streak, 1V1 RANKED ready button
-- Visual only. Design px under the shell's UIScale; one layout path from the slot's Size offset (1068 x 507 at the Full tier,
-- smaller on phones, where the lists and the right column scroll). Fixed-shape art is drawn whole at its native aspect.
-- View.new(slot) -> :SetPage(1|2) :SetWorlds(list) :SetSelected(id) :SetMilestones(rows) :SetRepeat(tiles, boss)
--   :SetStartState("Ready"|"Busy"|"Disabled") :OnSelect(cb(id)) :OnLocked(cb(id)) :OnStart(cb()) :OnClaim(cb(row))
--   :SetScroll(0) :Destroy()
-- worlds = PlayLogic.worlds, rows = PlayLogic.milestones, tiles / boss = PlayLogic.repeatTiles.

local TextService = game:GetService("TextService")

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Bag.Parts)
local Chrome = require(script.Parent.Parent.Bag.Chrome)
local Draw = require(script.Parent.Parent.QuestLog.Draw)
local Shared = require(script.Parent.Parent.SharedSprites)
local Sprites = require(script.Parent.Parent.Sprites)
local PlaySprites = require(script.Parent.PlaySprites)
local PlayLogic = require(script.Parent.PlayLogic)
local RatingLogic = require(script.Parent.Parent.RatingLogic)

local Q = Draw.Q
local make = UiKit.make

local WHITE = Color3.new(1, 1, 1)
local YELLOW_HEX = "#FDEA0A"
local GREY = Color3.fromRGB(150, 150, 160)
local ORANGE = Color3.fromRGB(248, 130, 20)
local GLOW_IN = Color3.fromRGB(253, 239, 10)
local GLOW_OUT = Color3.fromRGB(245, 119, 3)

local function whole(size: Vector2) -- sprite record whose ink is the whole (tight) export
	return { Size = size, Ink = Rect.new(0, 0, size.X, size.Y) }
end
-- Gold / Gems always draw the HUD's currency sprites (owner rule); the sizes are the Shared_Coin / Shared_Gem exports.
local COIN = { Image = Sprites.Coin, Size = Shared.Coin.Size, Ink = whole(Shared.Coin.Size).Ink }
local GEM = { Image = Sprites.Gem, Size = Shared.Gem.Size, Ink = whole(Shared.Gem.Size).Ink }
local ICON = { -- PlayLogic icon keys
	Coin = COIN,
	Gem = GEM,
	IconCrystals = PlaySprites.Crystals,
	Crown = PlaySprites.CrownGems,
	Potion = Q.Potion, -- no new-art potion, die or XP icon on the Play sheets: the existing ones stay
	IconGalaxyDie = Q.IconGalaxyDie,
	BadgeXp = Q.BadgeXp,
}
local BANNER = {
	DiceKingdom = "BannerDice",
	FrostPeaks = "BannerFrost",
	MagmaCitadel = "BannerMagma",
	ShadowRealm = "BannerShadow",
}
local ASP = 413 / 173 -- world banner aspect (w / h)
local START_ASP = 458 / 120
local MIN_CARD = 76 -- smallest card height before the list scrolls

local round = UiKit.round

local K = 1 -- real px per design px under the shell's UIScales (set per build): text is measured at its real size

local function measure(str: string, size: number): number
	return TextService:GetTextSize(str, size * K, Enum.Font.FredokaOne, Vector2.new(1e5, 1e5)).X / K
end

local function floorSize(): number -- the 12 real px text floor, in design px
	return math.min(math.ceil(12 / K), 14) -- capped: on a phone the text shrinks to fit rather than overflow
end

local function fitSize(str: string, w: number, size: number, min: number): number
	while size > min and measure(str, size) > w do
		size -= 1
	end
	return size
end

-- Live text in a box (centred, or left-anchored with AX = 0); shrinks to fit w, below Min only as a last resort (never "...").
local function label(parent, o)
	local l = Parts.text(parent, {
		Name = o.Name or "Text",
		Text = o.Text,
		RichText = o.Rich,
		TextSize = o.Size,
		TextColor3 = o.Color or WHITE,
		AnchorPoint = Vector2.new(o.AX or 0.5, 0.5),
		Position = UDim2.fromOffset(round(o.X), round(o.Y)),
		Size = UDim2.fromOffset(round(o.W), round(o.H or o.Size * 1.25)),
		TextXAlignment = if o.AX == 0 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		ZIndex = o.Z or parent.ZIndex + 1,
	}, o.Stroke or 3)
	l.TextTruncate = Enum.TextTruncate.None
	local plain = o.Plain or o.Text
	local size = if o.Fixed then o.Size else fitSize(plain, o.W * 0.95, o.Size, o.Min or floorSize())
	local w = measure(plain, size)
	if w > o.W * 0.97 then
		size = math.max(8, math.floor(size * o.W * 0.97 / w))
	end
	l.TextSize = size
	return l
end

-- Sprite drawn by its ink, centred at (cx, cy), fitted into maxW x maxH at its own aspect (never stretched).
local function icon(parent, r, cx, cy, maxW, maxH, z)
	if not r.Ink then -- Shared_* records carry only Image and Size: their exports are tight, so the ink is the whole image
		r = { Image = r.Image, Size = r.Size, Ink = Rect.new(0, 0, r.Size.X, r.Size.Y) }
	end
	local img = Draw.img(parent, { Name = "Icon", ZIndex = z or parent.ZIndex + 1 })
	local w, h = Draw.fitIn(r, maxW, maxH)
	return Draw.apply(img, r, cx, cy, w, h)
end

local function scroll(parent, name, x, y, w, h)
	return make("ScrollingFrame", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Chrome.Light,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		ZIndex = parent.ZIndex + 1,
	}, parent)
end

-- Selected card outline: one live stroke hugging the card (rounded like the art).
local function bloom(host, x, y, w, h, radius, z)
	local f = make("Frame", {
		Name = "Selected",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		ZIndex = z + 2,
	}, host)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, f)
	make("UIStroke", {
		Color = GLOW_IN:Lerp(GLOW_OUT, 0.4),
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, f)
end

-- The big green button (Play_Start art, live label): normal / hover / pressed (Parts.interact) and disabled (dim).
local function bigButton(
	parent,
	text: string,
	w: number,
	h: number,
	cx: number,
	cy: number,
	z: number,
	sizeText: string? -- the widest label a live button can show (the Duel timer); also means no play arrow
)
	w = round(w)
	h = math.min(round(h), round(w / START_ASP)) -- the old art's proportions: a slim pill, not a slab
	local size = fitSize(sizeText or text, w * (if sizeText then 0.8 else 0.55), math.floor(h * 0.5), 8)
	local btn = Parts.button(parent, {
		Name = "Start",
		Style = "Green",
		Label = text,
		Icon = if sizeText then nil else PlaySprites.PlayArrow,
		TextSize = size,
		Size = UDim2.fromOffset(w, h),
	})
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.fromOffset(round(cx), round(cy))
	btn.ZIndex = z
	btn.Label.ZIndex = z + 1 -- children were made at the default ZIndex: lift them above the button body
	local ic = btn:FindFirstChild("Icon")
	if ic then
		ic.ZIndex = z + 1
	end
	btn:SetAttribute("TextFixed", size) -- one size even when the label changes
	btn.Label.TextSize = size
	btn.Label.TextTruncate = Enum.TextTruncate.None
	return btn, function(on: boolean)
		Parts.setButton(btn, { Enabled = on })
	end, btn.Label
end

local View = {}
View.__index = View

-- Column shares of the free width, measured on the mockups (WORLDS 331 / 399 / 333, 1v1 308 / 420 / 330 of 1060).
local SHARE = { { 0.312, 0.316 }, { 0.291, 0.312 } }
local function compute(W: number, H: number, page: number)
	local gap = 8
	local lw, rw = round((W - 2 * gap) * SHARE[page][1]), round((W - 2 * gap) * SHARE[page][2])
	return {
		W = W,
		H = H,
		gap = gap,
		lw = lw,
		rw = rw,
		mid = W - lw - rw - 2 * gap,
		midX = lw + gap,
		rightX = W - rw,
		y = 3,
		h = H - 9,
	}
end

local function panel(self, name: string, x: number, w: number)
	local L = self._L
	return Chrome.panel(self._root, {
		Name = name,
		Position = UDim2.fromOffset(x, L.y),
		Size = UDim2.fromOffset(w, L.h),
		ZIndex = self._root.ZIndex + 1,
	})
end

-- Panel header: gold trophy + title, centred on the panel; the bar under it is the list's top.
local HEAD_H = 56
local function header(pnl, text: string, w: number)
	local size = fitSize(text, w - 90, 30, floorSize())
	local tw = measure(text, size)
	local ts = 38
	local cx = w / 2
	icon(pnl, PlaySprites.Trophy, cx - tw / 2 - ts / 2 - 6, HEAD_H / 2, ts, ts)
	label(pnl, { Name = "Title", Text = text, Size = size, Fixed = true, X = cx + ts / 2, Y = HEAD_H / 2, W = tw + 12 })
end

-- WORLDS: left column ---------------------------------------------------------------------------------------

local function bestPill(card, wd, h: number, z: number, maxW: number)
	local ph = round(h * 0.27)
	local size = math.min(round(ph * 0.62), 24)
	local crownW = round(ph * 0.95)
	local pad = 10
	local form
	for _, f in { "full", "short", "min" } do
		form = f
		if measure(PlayLogic.bestWaveText(wd.Best, f), size) + crownW + 2 * pad + 8 <= maxW then
			break
		end
	end
	local plain = PlayLogic.bestWaveText(wd.Best, form)
	local num = if wd.Best == "--" then wd.Best else `<font color="{YELLOW_HEX}">{wd.Best}</font>`
	local rich = PlayLogic.bestWaveText(wd.Best, form, num)
	size = fitSize(plain, maxW - crownW - 2 * pad - 8, size, 8)
	local pw = math.min(maxW, round(measure(plain, size) + crownW + 2 * pad + 8))
	local x, y = 8, h - ph - 8
	local pill = make("ImageLabel", {
		Name = "BestPill",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(pw, ph),
		ZIndex = z,
	}, card)
	Parts.skinH(pill, Shared.PillGreen, ph)
	icon(pill, PlaySprites.Crown, pad + crownW / 2, ph / 2, crownW, ph * 0.8, z + 1)
	label(pill, {
		Name = "BestText",
		Text = rich,
		Plain = plain,
		Rich = true,
		Size = size,
		Fixed = true,
		AX = 0,
		X = pad + crownW + 4,
		Y = ph / 2 - 1,
		W = pw - crownW - pad - 8,
		Stroke = 2,
		Z = z + 1,
	})
end

function View:_buildLeft(pnl)
	local L = self._L
	local worlds = self._worlds
	local pad, cgap = 15, 12
	local n = math.max(1, #worlds)
	local cw = L.lw - 2 * pad
	local fit = (L.h - 2 * pad - (n - 1) * cgap) / n
	local ch = math.min(cw / ASP, math.max(fit, MIN_CARD)) -- D4: the banner scales uniformly to the card width, the card clips its height
	local list = scroll(pnl, "Cards", 0, 0, L.lw, L.h)
	local x = (L.lw - cw) / 2
	local namesSize = round(ch * 0.22)
	for _, wd in worlds do
		namesSize = fitSize(wd.Name, cw - 24, namesSize, floorSize())
	end
	local sel = self._selected
	for i, wd in worlds do
		local y = pad + (i - 1) * (ch + cgap)
		local card = make("ImageButton", {
			Name = "Card_" .. wd.Id,
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(cw, ch),
			ZIndex = list.ZIndex + 3,
		}, list)
		make("UICorner", { CornerRadius = UDim.new(0, cw * 0.05) }, card)
		local banner = PlaySprites[BANNER[wd.Id]]
		local art = make("ImageLabel", {
			Name = "Art",
			BackgroundTransparency = 1,
			Image = banner.Image,
			-- top crop of the banner (the key art, Frost's die, sits in its top half) so the art itself carries the rounded corners
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.new(banner.Size.X, banner.Size.Y * math.min(1, ch / (cw / ASP))),
			Size = UDim2.fromOffset(cw, ch),
			ZIndex = card.ZIndex,
		}, card)
		make("UICorner", { CornerRadius = UDim.new(0, cw * 0.05) }, art)
		if wd.Id == sel then
			bloom(list, x, y, cw, ch, cw * 0.05, list.ZIndex + 2)
		end
		local zt = card.ZIndex + 1
		label(card, {
			Name = "Title",
			Text = wd.Name,
			Size = namesSize,
			Fixed = true,
			AX = 0,
			X = 12,
			Y = ch * 0.2,
			W = cw - 20,
			Z = zt,
		})
		local lockW = 0
		if wd.Locked then
			lockW = round(ch * 0.26)
			local lock = icon(card, Shared.Padlock, cw - 10 - lockW / 2, ch - 8 - lockW / 2, lockW, lockW, zt)
			lock.Name = "Padlock"
			lockW += 8
		end
		bestPill(card, wd, ch, zt, cw - 16 - lockW)
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
	end
	list.CanvasSize = UDim2.fromOffset(0, 2 * pad + n * ch + (n - 1) * cgap)
	self._scrolls.Cards = list
end

-- WORLDS: milestones ------------------------------------------------------------------------------------------

local function buildRow(list, row, y: number, w: number, h: number, R, onClaim, hitMin: number)
	local strip = Chrome.strip(list, {
		Name = "Row" .. row.Wave,
		Position = UDim2.fromOffset(4, y), -- inset: the strip stroke is half outside the strip, the list would clip it
		Size = UDim2.fromOffset(w, h),
		ZIndex = list.ZIndex + 1,
	})
	local z = strip.ZIndex + 1
	local claim, claimed = row.State == "Claimable", row.State == "Claimed"
	if claim then
		strip.UIStroke.Color = ORANGE
	end
	local tint = if row.State == "Soon" then GREY else WHITE
	local bd = R.bd
	local badge = if claimed then Shared.Tick elseif claim then PlaySprites.Trophy else Shared.Padlock
	local b = icon(strip, badge, R.badgeX or 10 + bd / 2, h / 2, bd, bd, z)
	b.Name = "Badge"
	local claimInSlot = claim and not R.noIcon -- the button takes the WAVE text's place; the reward icon stays
	if not claimInSlot then
		label(strip, {
			Name = "Wave",
			Text = "WAVE " .. row.Wave,
			Size = R.wave,
			Fixed = true,
			AX = 0,
			X = R.waveX,
			Y = h / 2,
			W = R.waveW + 8,
			Color = tint,
			Z = z,
		})
	end
	if claim then
		local hit = make("ImageButton", {
			Name = "Claim",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(round(if R.noIcon then w - 49 else R.waveX + R.slot / 2), round(h / 2)),
			Size = UDim2.fromOffset(78, math.max(h, hitMin)),
			ZIndex = z + 1,
		}, strip)
		Parts.interact(hit)
		local visual = Parts.button(hit, {
			Name = "Visual",
			Style = "Green",
			Label = "CLAIM",
			TextSize = 20,
			Size = UDim2.fromOffset(76, 38),
			Enabled = not row.Busy,
		})
		visual.AnchorPoint = Vector2.new(0.5, 0.5)
		visual.Position = UDim2.fromScale(0.5, 0.5)
		visual.Interactable = false -- the hit box takes the tap
		visual.Selectable = false
		visual.Label.TextTruncate = Enum.TextTruncate.None
		hit.Activated:Connect(function()
			if onClaim then
				onClaim(row)
			end
		end)
	end
	if not R.noIcon then
		icon(strip, ICON[row.Icon] or PlaySprites.Crystals, R.ix, h / 2, 46, math.min(46, h - 10), z)
	end
	Chrome.divider(strip, {
		Name = "Divider",
		Position = UDim2.fromOffset(round(R.dx), round(h / 2 - (h - 20) / 2)),
		Size = UDim2.fromOffset(3, h - 20),
		ZIndex = z,
	})
	local total = #row.Lines * (R.line + 1)
	local ty = h / 2 - total / 2
	for i, str in row.Lines do
		label(strip, {
			Name = "Reward" .. i,
			Text = str,
			Size = R.line,
			Fixed = true,
			X = R.tx,
			Y = ty + (R.line + 1) / 2,
			W = R.wr,
			Color = tint,
			Stroke = 2,
			Z = z,
		})
		ty += R.line + 1
	end
end

-- One size per text role for every row: the largest WAVE and reward-line sizes whose columns fit the row width.
local function rowRoles(rows, w: number, h: number, hasClaim: boolean, phone: boolean)
	local fl = floorSize()
	local bd = math.min(h - 14, 40)
	local waveX = 10 + bd + 10
	local maxLines = 1
	for _, r in rows do
		maxLines = math.max(maxLines, #r.Lines)
	end
	local half = 23
	local cmax = math.max(8, math.min(17, math.floor((h - 8) / maxLines) - 1)) -- reward lines fit the row height
	local function try(a: number, c: number, withIcon: boolean)
		local ww, wr = 0, 0
		for _, r in rows do
			ww = math.max(ww, measure("WAVE " .. r.Wave, a))
			for _, str in r.Lines do
				wr = math.max(wr, measure(str, c))
			end
		end
		local raw = wr
		wr += 14 -- slack: the stroked text is wider than measured, so it never touches the divider or the frame
		local ws = if hasClaim then math.max(ww, 76) else ww -- the CLAIM button sits in the WAVE slot
		if withIcon then -- badge | WAVE or CLAIM | icon | divider | rewards, the free width split into equal gaps (both ends too)
			local g = (w - (bd + ws + 46 + 3 + raw)) / 6
			if g < 6 then
				return nil
			end
			local dxe = 4 * g + bd + ws + 46
			return {
				bd = bd,
				badgeX = g + bd / 2,
				waveX = 2 * g + bd,
				waveW = ww,
				slot = ws,
				wave = a,
				line = c,
				wr = wr,
				dx = dxe,
				ix = 3 * g + bd + ws + 23,
				tx = dxe + 3 + g + raw / 2,
				noIcon = false,
			}
		end
		local dx = w - 10 - wr - 12
		local ix = (waveX + ws + dx) / 2
		if dx - (waveX + ws) < 6 or (withIcon and ix - half < waveX + ws + 6) then
			return nil
		end
		return {
			bd = bd,
			waveX = waveX,
			waveW = ww,
			slot = ws,
			wave = a,
			line = c,
			wr = wr,
			dx = dx,
			ix = ix,
			tx = (dx + w - 5) / 2, -- centred between the divider and the frame
			noIcon = not withIcon,
		}
	end
	for a = 22, if phone then 23 else math.min(fl, 22), -1 do -- phones: never a reward icon, so no icon pass
		for c = cmax, math.min(fl, cmax), -1 do
			local R = try(a, c, true)
			if R then
				return R
			end
		end
	end
	if phone or not hasClaim then -- a narrow row (phones) drops the reward icon: lock | WAVE n | reward text, measured, never overlapping
		for a = 22, 10, -1 do
			for c = cmax, math.min(8, cmax), -1 do
				local R = try(a, c, false)
				if R then
					return R
				end
			end
		end
	end
	return try(10, 8, false)
		or {
			bd = bd,
			waveX = waveX,
			waveW = 60,
			slot = 76,
			wave = 10,
			line = 8,
			wr = 70,
			dx = w - 82,
			ix = w / 2,
			tx = w - 47,
			noIcon = true,
		}
end

function View:_buildMid(pnl)
	local L = self._L
	local w = L.mid
	header(pnl, "FIRST-TIME MILESTONES", w)
	local rows = self._rows
	local n = math.max(1, #rows)
	local hasClaim = false
	for _, r in rows do
		hasClaim = hasClaim or r.State == "Claimable"
	end
	local listH = L.h - HEAD_H - 6
	local rh = 58 -- mockup rows: 58 tall on a 65 pitch (text shrinks to the row, never the reverse)
	local rw = w - 24
	local list = scroll(pnl, "Rows", 12, HEAD_H, rw + 12, listH)
	list.ScrollBarThickness = 4
	local R = rowRoles(rows, if L.h < 440 and hasClaim then rw - 84 else rw, rh, hasClaim, L.h < 440) -- phones: CLAIM takes the right 84 px
	local pitch = 65
	local hitMin = math.ceil(44 / K)
	for i, row in rows do
		buildRow(list, row, 3 + (i - 1) * pitch, rw, rh, R, function(r)
			if self._onClaim then
				self._onClaim(r)
			end
		end, hitMin)
	end
	list.CanvasSize = UDim2.fromOffset(0, 8 + (n - 1) * pitch + rh)
	self._scrolls.Rows = list
end

-- WORLDS: right column ----------------------------------------------------------------------------------------

function View:_buildRight(pnl)
	local L = self._L
	local rw = L.rw
	local pad = 12
	local aw = rw - 2 * pad
	local startH = math.clamp(math.max(round(L.h * 0.157), math.ceil(46 / K)), 56, 80) -- >= 44 real px tall
	local wd
	for _, w in self._worlds do
		if w.Id == self._selected then
			wd = w
		end
	end
	wd = wd or self._worlds[1]
	local availH = L.h - startH - pad - 10
	local info = scroll(pnl, "Info", 0, 0, rw, availH)
	local tight = L.h < 440 -- phones: no banner preview, shorter tiles, so the repeat rewards fit above START
	local y = if tight then 8 else pad
	if wd then
		local ah = aw / ASP
		local art = if tight
			then nil
			else make("ImageLabel", {
				Name = "Preview",
				BackgroundTransparency = 1,
				Image = PlaySprites[BANNER[wd.Id]].Image,
				ScaleType = Enum.ScaleType.Stretch,
				Position = UDim2.fromOffset(pad, y),
				Size = UDim2.fromOffset(aw, ah),
				ZIndex = info.ZIndex + 1,
			}, info)
		if art then
			make("UIAspectRatioConstraint", { AspectRatio = ASP }, art)
			y += ah + 6
		end
		local nameSize = fitSize(wd.Name, aw, 30, floorSize())
		label(
			info,
			{ Name = "WorldName", Text = wd.Name, Size = nameSize, Fixed = true, X = rw / 2, Y = y + 19, W = aw }
		)
		y += 40
		local bs = Chrome.strip(info, {
			Name = "BestStrip",
			Position = UDim2.fromOffset(pad, y),
			Size = UDim2.fromOffset(aw, 34),
			ZIndex = info.ZIndex + 1,
		})
		local plain = PlayLogic.bestWaveText(wd.Best, "full")
		local rich = PlayLogic.bestWaveText(
			wd.Best,
			"full",
			if wd.Best == "--" then wd.Best else `<font color="{YELLOW_HEX}">{wd.Best}</font>`
		)
		local bsz = fitSize(plain, aw - 70, 24, floorSize())
		local tw = measure(plain, bsz)
		icon(bs, PlaySprites.Crown, aw / 2 - tw / 2 - 18, 17, 30, 24)
		label(bs, {
			Name = "BestText",
			Text = rich,
			Plain = plain,
			Rich = true,
			Size = bsz,
			Fixed = true,
			X = aw / 2 + 16,
			Y = 16,
			W = tw + 14,
			Stroke = 2,
		})
		y += 34 + (if tight then 10 else 23)
	end
	local head = "REPEAT REWARDS \u{2022} EVERY WAVE"
	label(info, {
		Name = "RepeatHeading",
		Text = head:gsub("\u{2022}", `<font color="{YELLOW_HEX}">\u{2022}</font>`),
		Plain = head,
		Rich = true,
		Size = 18,
		X = rw / 2,
		Y = y + 10,
		W = aw,
		Stroke = 2,
	})
	y += if tight then 26 else 36
	local tiles = self._tiles
	local nt = #tiles
	if nt > 0 then
		local tgap = 6
		local tw2 = (aw - (nt - 1) * tgap) / nt
		local th = if tight then 76 else 100
		local lsize = if tight then 13 else 18
		local function lab(t) -- phones: the 4-wide tiles are ~50 px, "MATERIALS" cannot be legible there
			return if tight and t.Label == "MATERIALS" then "MATS" else t.Label
		end
		for _, t in tiles do
			lsize = math.min(lsize, fitSize(lab(t), tw2 - 8, lsize, 8))
		end
		for i, t in tiles do
			local tile = Chrome.panel(info, {
				Name = "Tile" .. i,
				Position = UDim2.fromOffset(round(pad + (i - 1) * (tw2 + tgap)), y),
				Size = UDim2.fromOffset(round(tw2), th),
				ZIndex = info.ZIndex + 1,
				Radius = 10,
				Rim = 2,
			})
			label(tile, {
				Name = "Label",
				Text = lab(t),
				Size = lsize,
				Fixed = true,
				X = tw2 / 2,
				Y = if tight then 12 else 15,
				W = tw2 - 4,
				Stroke = 2,
			})
			icon(
				tile,
				ICON[t.Icon] or PlaySprites.Crystals,
				tw2 / 2,
				if tight then 37 else 52,
				math.min(44, tw2 - 14),
				if tight then 28 else 40
			)
			label(tile, {
				Name = "Amount",
				Text = t.Text,
				Size = if tight then 16 else 20,
				X = tw2 / 2,
				Y = th - (if tight then 12 else 17),
				W = tw2 - 6,
				Stroke = 2,
			})
		end
		y += th + 8
	end
	if self._boss and y + 24 <= availH then -- hidden when it cannot sit fully above START
		label(
			info,
			{ Name = "Boss", Text = self._boss, Size = 16, X = rw / 2, Y = y + 9, W = aw, Color = GREY, Stroke = 2 }
		)
		y += 24
	end
	info.CanvasSize = UDim2.fromOffset(0, y + 4)
	self._scrolls.Info = info
	local buttonY = L.h - startH / 2 - 19
	local sideW = math.floor((rw - 28) / 2)
	local hit, setOn = bigButton(pnl, "SOLO", sideW, startH, rw / 2 - sideW / 2 - 4, buttonY, pnl.ZIndex + 5)
	hit.Activated:Connect(function()
		if self._startState == "Ready" and self._onStart then
			self._onStart()
		end
	end)
	self._startBtn, self._setStartOn = hit, setOn
	setOn(self._startState == "Ready")
	local mode = self._coopState
	local coop, setCoop = bigButton(
		pnl,
		if mode == "Waiting" then "CANCEL READY" else "CO-OP",
		sideW,
		startH,
		rw / 2 + sideW / 2 + 4,
		buttonY,
		pnl.ZIndex + 5
	)
	setCoop(mode == "Ready" or mode == "Waiting")
	coop.Activated:Connect(function()
		if self._onCoop and (mode == "Ready" or mode == "Waiting") then
			self._onCoop(mode ~= "Waiting")
		end
	end)
end

-- 1v1 ---------------------------------------------------------------------------------------------------------

function View:_buildRanks()
	local L = self._L
	local left = panel(self, "RanksPanel", 0, L.lw)
	local mid = panel(self, "RecordPanel", L.midX, L.mid)
	local right = panel(self, "RankPanel", L.rightX, L.rw)
	local rating = self._rating -- RatingLogic.rating(snap.Rating), nil on an old snapshot
	local mine = if rating then rating.Rank else "Bronze"
	local function tint(rank: string): Color3
		local c = RatingLogic.rankColor(rank)
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	-- rank ladder: the three ranks, the player's own highlighted and tagged YOU
	local ranks = PlayLogic.RANKS
	local y0, rgap = if L.h < 440 then 12 else 27, if L.h < 440 then 8 else 13
	local ch = math.clamp(math.floor((L.h - 2 * y0 - (#ranks - 1) * rgap) / #ranks), 40, 112) -- 112 at Full; shorter on phones
	local cw = L.lw - 24
	for i, rk in ranks do
		local y = y0 + (i - 1) * (ch + rgap)
		local sel = rk.Id == mine
		if sel then
			bloom(left, 12, y, cw, ch, 10, left.ZIndex + 1)
		end
		local card = Chrome.strip(left, {
			Name = "Rank_" .. rk.Id,
			Position = UDim2.fromOffset(12, y),
			Size = UDim2.fromOffset(cw, ch),
			ZIndex = left.ZIndex + 2,
			Radius = 12,
		})
		card.UIStroke.Color = if sel then ORANGE else Chrome.PanelRim
		local art = PlaySprites[rk.Art]
		local sw = math.min((ch - 16) * art.Size.X / art.Size.Y, cw * 0.3) -- narrow phone cards: the shield leaves the name room
		local sh = sw * art.Size.Y / art.Size.X
		icon(card, art, 10 + sw / 2, ch / 2, sw, sh, card.ZIndex + 1)
		local tx = 10 + sw + 12
		local tagW = if sel then 46 else 0
		local nameW = cw - tx - 12 - tagW
		label(card, {
			Name = "Name",
			Text = rk.Name,
			Size = math.min(36, math.floor(ch * 0.4)),
			Min = 8, -- label() shrinks the name to its box (floor 8), never cuts it
			AX = 0,
			X = tx,
			Y = ch / 2,
			W = nameW + 6,
			Color = tint(rk.Id),
		})
		if sel then
			label(card, {
				Name = "YouTag",
				Text = "YOU",
				Size = 16,
				Fixed = true,
				X = cw - 12 - tagW / 2,
				Y = ch / 2,
				W = tagW,
				Stroke = 2,
			})
		end
	end
	-- record: wins / losses / best streak
	header(mid, "YOUR RECORD", L.mid)
	local rec = scroll(mid, "Record", 0, HEAD_H, L.mid, L.h - HEAD_H)
	local rows = {
		{ "WINS", if rating then rating.Wins else 0 },
		{ "LOSSES", if rating then rating.Losses else 0 },
		{ "BEST STREAK", if rating then rating.BestStreak else 0 },
	}
	local rowH = if L.h < 440 then 34 else 46
	for i, r in rows do
		local ry = 8 + (i - 1) * rowH
		label(rec, {
			Name = "K" .. i,
			Text = r[1],
			Size = 20,
			AX = 0,
			X = 14,
			Y = ry + rowH / 2,
			W = L.mid * 0.6,
			Color = GREY,
			Stroke = 2,
		})
		label(rec, {
			Name = "V" .. i,
			Text = tostring(r[2]),
			Size = 24,
			AX = 0,
			X = L.mid * 0.66,
			Y = ry + rowH / 2,
			W = L.mid * 0.3,
		})
	end
	local noteY = 8 + #rows * rowH + 14
	local note = label(rec, {
		Name = "Note",
		Text = "Win 1v1 matches to earn DR and rank up. Win streaks pay bonus DR and gold.",
		Size = 16,
		Fixed = true,
		Color = GREY,
		X = L.mid / 2,
		Y = noteY + 30,
		W = L.mid - 28,
		H = 60,
		Stroke = 2,
	})
	note.TextWrapped = true
	rec.CanvasSize = UDim2.fromOffset(0, noteY + 70)
	self._scrolls.Record = rec
	-- your rank, DR, progress, streak, 1V1 button
	local rk
	for _, r in ranks do
		if r.Id == mine then
			rk = r
		end
	end
	rk = rk or ranks[1]
	local rw = L.rw
	local startH = math.clamp(math.max(round(L.h * 0.157), math.ceil(46 / K)), 56, 80) -- >= 44 real px tall
	local startW = math.min(rw - 24, startH * START_ASP)
	local availH = L.h - startH - 22
	local info = scroll(right, "Info", 0, 0, rw, availH)
	local art = PlaySprites[rk.Art]
	local sh = math.min(112, availH * 0.36)
	local glow = Draw.img(info, { Name = "Glow", ZIndex = info.ZIndex + 1 })
	Draw.apply(glow, Q.GlowRadial, rw / 2, 7 + sh / 2, sh * 2.2, sh * 2.2)
	glow.ImageColor3 = tint(rk.Id)
	icon(info, art, rw / 2, 7 + sh / 2, sh * art.Size.X / art.Size.Y, sh, info.ZIndex + 2).Name = "Shield"
	local y = 7 + sh + 2
	label(info, {
		Name = "RankName",
		Text = rk.Name,
		Size = fitSize(rk.Name, rw - 24, 36, floorSize()),
		Fixed = true,
		X = rw / 2,
		Y = y + 18,
		W = rw - 24,
		Color = tint(rk.Id),
	})
	y += 38
	local chip = Chrome.strip(info, {
		Name = "DrChip",
		Position = UDim2.fromOffset(round(rw / 2 - 90), y),
		Size = UDim2.fromOffset(180, 44),
		ZIndex = info.ZIndex + 1,
		Radius = 22,
	})
	icon(chip, PlaySprites.Trophy, 34, 22, 34, 32)
	label(chip, {
		Name = "DrCount",
		Text = `{if rating then rating.DR else 0} DR`,
		Size = 26,
		X = 112,
		Y = 21,
		W = 110,
	})
	y += 52
	local prog = RatingLogic.progress(self._ratingRaw)
	local bar = make("Frame", {
		Name = "ProgressBar",
		BackgroundColor3 = Color3.fromRGB(20, 22, 38),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(24, y),
		Size = UDim2.fromOffset(rw - 48, 16),
		ZIndex = info.ZIndex + 1,
	}, info)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, bar)
	make("UIStroke", { Color = Chrome.PanelRim, Thickness = 2 }, bar)
	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = tint(rk.Id),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(prog.Frac, 1),
		ZIndex = bar.ZIndex + 1,
	}, bar)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, fill)
	y += 16
	if prog.Text ~= "" then
		label(info, {
			Name = "ProgressText",
			Text = prog.Text,
			Size = 18,
			X = rw / 2,
			Y = y + 14,
			W = rw - 24,
			Color = GREY,
			Stroke = 2,
		})
		y += 28
	end
	local streak = RatingLogic.streakText(if rating then rating.Streak else 0)
	if streak ~= "" then
		label(info, { Name = "Streak", Text = streak, Size = 22, X = rw / 2, Y = y + 14, W = rw - 24, Color = ORANGE })
		y += 30
	end
	local duel = self._duel
	if duel.Note then
		label(info, {
			Name = "DuelNote",
			Text = duel.Note,
			Size = 18,
			X = rw / 2,
			Y = y + 14,
			W = rw - 24,
			Color = GREY,
			Stroke = 2,
		})
		y += 28
	end
	label(info, {
		Name = "MatchCaption",
		Text = "Opponents are within one rank of yours.",
		Size = 18,
		X = rw / 2,
		Y = y + 14,
		W = rw - 24,
		Color = GREY,
		Stroke = 2,
	})
	y += 28
	info.CanvasSize = UDim2.fromOffset(0, y + 8)
	self._scrolls.Info = info
	local hit, setOn, btnLabel = bigButton(
		right,
		duel.Label or "FIND MATCH",
		startW,
		startH,
		rw / 2,
		L.h - startH / 2 - 12,
		right.ZIndex + 5,
		RatingLogic.QUEUE_WIDEST
	)
	self._duelLabel = btnLabel
	setOn(duel.State == "Find" or duel.State == "Searching")
	hit.Activated:Connect(function()
		local s = self._duel
		if s.State == "Find" or s.State == "Searching" then
			if self._onDuel then
				self._onDuel(s.State == "Find")
			end
		elseif s.Note and self._onDuelBlocked then
			self._onDuelBlocked(s.Note) -- disabled: the controller answers with a toast
		end
	end)
end

-- Build -------------------------------------------------------------------------------------------------------

function View:_build()
	if not self._L or not self._root.Parent then
		return
	end
	local L = compute(self._L.W, self._L.H, self._page) -- the page picks the column widths
	self._L = L
	local keep = {}
	for name, s in self._scrolls do
		if s.Parent then
			keep[name] = s.CanvasPosition
		end
	end
	for _, c in self._root:GetChildren() do
		c:Destroy()
	end
	table.clear(self._scrolls)
	self._startBtn, self._setStartOn, self._duelLabel = nil, nil, nil
	if self._page == 2 then
		self:_buildRanks()
	else
		self:_buildLeft(panel(self, "WorldsPanel", 0, L.lw))
		self:_buildMid(panel(self, "MilestonesPanel", L.midX, L.mid))
		self:_buildRight(panel(self, "WorldPanel", L.rightX, L.rw))
	end
	for name, s in self._scrolls do
		if keep[name] then
			s.CanvasPosition = keep[name]
		end
	end
end

-- Setters arrive together on every render: one rebuild per frame.
function View:_queue()
	if self._queued then
		return
	end
	self._queued = true
	task.defer(function()
		self._queued = false
		self:_build()
	end)
end

function View.new(slot)
	local self = setmetatable({}, View)
	self._conns, self._scrolls = {}, {}
	self._page, self._worlds, self._selected, self._rows = 1, {}, nil, {}
	self._tiles, self._boss, self._startState = {}, nil, "Disabled"
	self._duel, self._ratingRaw, self._rating = { State = "Disabled", Label = "FIND MATCH" }, nil, nil
	self._root = make(
		"Frame",
		{ Name = "PlayView", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = slot.ZIndex + 1 },
		slot
	)
	local pending = false
	local function relayout()
		if pending or slot.Size.X.Offset <= 0 or slot.Size.Y.Offset <= 0 then
			return
		end
		pending = true
		task.defer(function() -- Size and the Compact attribute change together in one Fit: build once
			pending = false
			if not self._root.Parent then
				return
			end
			local w, h = slot.Size.X.Offset, slot.Size.Y.Offset
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
			if L and L.W == w and L.H == h and math.abs(K - k) < 1e-3 then
				return
			end
			K = k
			self._L = compute(w, h, self._page)
			self:_build()
		end)
	end
	table.insert(self._conns, slot:GetPropertyChangedSignal("Size"):Connect(relayout))
	table.insert(self._conns, slot:GetAttributeChangedSignal("Compact"):Connect(relayout))
	relayout()
	return self
end

function View:SetPage(i: number)
	if self._page ~= i then
		self._page = i
		self:_queue()
	end
end

function View:SetWorlds(list)
	self._worlds = list
	self:_queue()
end

function View:SetSelected(id: string?)
	if self._selected ~= id then
		self._selected = id
		self:_queue()
	end
end

function View:SetMilestones(rows)
	self._rows = rows
	self:_queue()
end

function View:SetRepeat(tiles, boss: string?)
	self._tiles, self._boss = tiles, boss
	self:_queue()
end

function View:SetStartState(state: string)
	self._startState = state
	if self._setStartOn and self._startBtn and self._startBtn.Parent then
		self._setStartOn(state == "Ready")
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

function View:SetCoopState(state: string)
	if self._coopState ~= state then
		self._coopState = state
		self:_queue()
	end
end

-- state = RatingLogic.queueButton(...) ({ State = "Find"|"Searching"|"Matched"|"Disabled", Label, Note }); rating = snap.Rating (nil on an old snapshot).
function View:SetDuel(state, rating)
	self._duel, self._ratingRaw, self._rating = state, rating, RatingLogic.rating(rating)
	self:_queue()
end

-- Live search timer: swaps the button text in place (no rebuild); the next build draws the state's own label.
function View:SetDuelLabel(str: string)
	local l = self._duelLabel
	if l and l.Parent and l.Text ~= str then
		l.Text = str
	end
end

function View:OnDuel(cb)
	self._onDuel = cb
end

function View:OnDuelBlocked(cb)
	self._onDuelBlocked = cb
end

function View:OnCoop(cb)
	self._onCoop = cb
end

function View:OnClaim(cb)
	self._onClaim = cb
end

function View:SetScroll(y: number)
	for _, s in self._scrolls do
		s.CanvasPosition = Vector2.new(0, y)
	end
end

function View:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	self._root:Destroy()
end

return View
