-- Roll menu view: featured dice | rarity chances, pity row and the two ROLL buttons, drawn inside the shared shell's content slot.
-- Visual only: no NetClient, no game data. Design px under the shell's UIScale; the slot's Size offset picks the layout.
-- View.new(slot) -> :SetPool("Standard"|"Event") :SetFeatured({ [1..3] = {Id, Rarity, Name}? }, title?) :SetOdds(RollLogic.oddsRows)
--   :SetPity({Count, Max, Rarity}) :SetButtons({ {Count, Price, Enabled} x2 }) :SetNotice("gems"|"region"?) :OnRoll(cb(count)) :OnInfo(cb()) :Destroy()
-- :SetRolling({ Count, Still }?) shows the placeholder roll animation (neutral dice, grey buttons) until nil; :SetPop(bool) fades the next result tiles in.
-- shortcut: placeholder roll animation, replace with real VFX later
-- Setters only store state; one deferred rebuild draws it (also on every slot size change).
-- One layout path (plan 1672x941 design: content 1068 x 507): vertical sizes scale by f = H / 507 (0.5 .. 1), horizontal ones by W / 1068,
-- text never drops under 14 real px; under the f floor the stack scrolls. Panels / rows / chip / bar are Chrome (code), art is whole.

local TweenService = game:GetService("TweenService")

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Bag.Parts)
local Chrome = require(script.Parent.Parent.Bag.Chrome)
local Draw = require(script.Parent.Parent.QuestLog.Draw)
local Sprites = require(script.Parent.Parent.Sprites)
local QuestLogic = require(script.Parent.Parent.QuestLog.QuestLogic)
local RollLogic = require(script.Parent.RollLogic)
local RollSprites = require(script.Parent.RollSprites)

local make = UiKit.make

local YELLOW = "#FFF200"
local ROLLING = "ROLLING..."
local NOTICE =
	{ -- chip text of a disabled button, longest first: the first that fits the chip at the 14 real px floor is used
		gems = { "Not enough Gems", "Need Gems", "Gems" },
		region = { "Not in your region", "Region locked", "N/A" },
		starter = { "Starter rolls are single", "Single roll", "N/A" },
	} -- chip text of a disabled button; the toast carries the full sentence
-- Row colours sampled from the mockup: { top, bottom, rim }.
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local ROW = {
	Secret = { rgb(203, 16, 29), rgb(127, 7, 14), rgb(244, 70, 70) },
	Mythic = { rgb(252, 20, 130), rgb(213, 12, 98), rgb(255, 150, 205) },
	Legendary = { rgb(251, 116, 5), rgb(179, 82, 1), rgb(253, 200, 40) },
	Epic = { rgb(125, 6, 240), rgb(93, 2, 212), rgb(205, 150, 255) },
	Rare = { rgb(3, 117, 250), rgb(2, 87, 168), rgb(110, 235, 255) },
	Common = { rgb(109, 108, 109), rgb(78, 76, 78), rgb(235, 235, 235) },
}
local ROW_ICON = { -- { sprite, box w, box h } at f = 1
	Secret = { RollSprites.CrownSecret, 41, 25 },
	Mythic = { RollSprites.CrownMythic, 41, 25 },
	Legendary = { RollSprites.CrownGold, 41, 25 },
	Epic = { RollSprites.CrownEpic, 41, 25 },
	Rare = { RollSprites.StarsRare, 50, 20 },
	Common = { RollSprites.StarCommon, 24, 23 },
}
local BUTTON = {
	{ rgb(217, 144, 23), rgb(143, 75, 11), rgb(255, 217, 133), rgb(66, 36, 2) },
	{ rgb(127, 68, 217), rgb(70, 34, 130), rgb(206, 158, 255), rgb(36, 9, 72) },
	{ rgb(220, 20, 60), rgb(139, 0, 30), rgb(255, 130, 150), rgb(66, 0, 14) }, -- ROLL MAX: crimson
}
local DISABLED = { rgb(91, 90, 104), rgb(54, 52, 63), rgb(151, 150, 167), rgb(30, 30, 34) }
local GEM_YELLOW = Color3.fromRGB(254, 229, 1)

local round = UiKit.round

local function aspect(rec): number
	return rec.Ink.Width / rec.Ink.Height
end

local K = 1 -- real px per design px under the shell's UIScales (set per build)

local function clear(parent)
	for _, c in parent:GetChildren() do
		if not c:IsA("UIBase") then
			c:Destroy()
		end
	end
end

local View = {}
View.__index = View

-- Layout ----------------------------------------------------------------------------------------------------

local function compute(W: number, H: number, vip: boolean)
	W -= 14 -- inset panel rims and reserve the scrollbar lane
	local f = math.clamp(H / 507, 0.5, 1)
	local w = math.clamp(W / 1068, 0.4, 1.3)
	local L = { W = W, H = H, f = f, w = w }
	L.tmin = math.max(8, math.ceil(14 / K)) -- design px of the 14 real px text floor
	L.gap = round(10 * w)
	L.pityH = math.max(round(80 * f), math.ceil(44 / K) + 8, 3 * L.tmin + 18)
	L.btnH = math.max(round(87 * f), math.ceil(44 / K)) -- hit area >= 44 real px
	L.btnW = math.min(math.max(L.btnH * 3.48, 235 * w), (W - 2 * L.gap) / 3)
	L.btnGap = round(11 * f)
	-- the panel never gets shorter than six rows of the 14 real px text under the heading: below that the stack scrolls
	local panelMin = round(61 * f) + 6 * (L.tmin + 4) + 5 * round(2 * f) + round(12 * f)
	local stacked = W * K < 530
	L.vipH = if vip then math.max(round(40 * f), math.ceil(44 / K)) + L.btnGap else 0 -- the VIP offer row under the buttons
	L.panelH = math.max(panelMin, H - L.pityH - L.btnH - 2 * L.btnGap - 8 - L.vipH)
	L.fw = if stacked then W else round(W * 0.64)
	L.featureH = if stacked then math.max(round(198 * f), 4 * L.tmin + 70) else L.panelH
	L.rx = if stacked then 0 else L.fw + L.gap
	L.ry = if stacked then L.featureH + L.btnGap else 0
	L.rw = W - L.rx
	L.total = L.ry + L.panelH + L.pityH + L.btnH + 2 * L.btnGap + 8 + L.vipH
	return L
end

-- Size of a text role: base x f, floored at the 14 real px, then shrunk to fit w.
local function textSize(L, base: number, str: string?, w: number?): number
	local s = math.max(math.floor(base * L.f + 0.5), L.tmin)
	if str and w then
		s = Parts.fitSize(str, w, s, L.tmin)
	end
	return s
end

-- Live text centred (or left / right anchored: ax 0 / 1) at (x, y) in a box of width w.
local function label(parent, L, o)
	local size = o.Size or textSize(L, o.Base, o.Plain or o.Text, o.W)
	local l = Parts.text(parent, {
		Name = o.Name or "Text",
		Text = o.Rich or o.Text,
		RichText = o.Rich ~= nil,
		TextSize = size,
		TextColor3 = o.Color,
		AnchorPoint = Vector2.new(o.AX or 0.5, 0.5),
		Position = UDim2.fromOffset(round(o.X), round(o.Y)),
		Size = UDim2.fromOffset(round(o.W), (L.f >= 1 and o.H) or math.ceil(size * 1.25)),
		TextXAlignment = if o.AX == 0
			then Enum.TextXAlignment.Left
			elseif o.AX == 1 then Enum.TextXAlignment.Right
			else Enum.TextXAlignment.Center,
		ZIndex = o.Z,
	}, o.Stroke or 2)
	l.TextTruncate = Enum.TextTruncate.AtEnd
	return l
end

-- A whole sprite at its native aspect: height h, centred at (cx, cy).
local function whole(parent, rec, name: string, cx: number, cy: number, h: number, z: number)
	local img = Draw.img(parent, { Name = name, ZIndex = z })
	Draw.apply(img, rec, cx, cy, h * aspect(rec), h)
	return img
end

-- Heading: the diamond plate (native aspect) with live text between the diamonds.
local function heading(parent, L, text: string, cx: number, top: number, h: number, z: number)
	h = math.min(h, (2 * cx - 18) / aspect(RollSprites.HeaderPlate))
	local pw = h * aspect(RollSprites.HeaderPlate)
	whole(parent, RollSprites.HeaderPlate, "Plate", cx, top + h / 2, h, z)
	label(parent, L, { Name = "Title", Text = text, Base = 36, X = cx, Y = top + h / 2, W = pw * 0.7, Z = z + 1 })
end

-- Build -----------------------------------------------------------------------------------------------------

function View:_drawFeatured(L, z: number)
	local Pw, Ph, f = L.fw, L.featureH, L.f
	local panel = Chrome.panel(self._canvas, {
		Name = "Featured",
		Size = UDim2.fromOffset(Pw, Ph),
		ZIndex = z,
	})
	local plateH = round(42 * f)
	local plateTop = round(12 * f)
	heading(panel, L, if self._rolling then ROLLING else self._featuredTitle, Pw / 2, plateTop, plateH, z + 1)
	local list = self._featuredIds
	local last, hole = 0, false
	for i = 1, 3 do
		if list[i] then
			last = i
			hole = hole or i > 1 and list[i - 1] == nil
		end
	end
	local n = if hole then 3 else math.max(last, 1)
	local pitch = math.min(0.31 * Pw, Pw / n)
	local pillH = math.max(round(32 * f), L.tmin + 6)
	local pillCy = Ph - math.max(round(12 * f), 8) - pillH / 2
	local nameH = math.max(round(24 * f), L.tmin + 4)
	local nameCy = pillCy - pillH / 2 - nameH / 2 - 4
	local dieTop = plateTop + plateH + round(4 * f)
	local dieBot = nameCy - nameH / 2 - 4
	local dieS = math.max(10, math.min(pitch * 0.92, dieBot - dieTop))
	local dieCy = (dieTop + dieBot) / 2
	local function cx(i: number): number
		return Pw / 2 + (i - (n + 1) / 2) * pitch
	end
	if self._rolling then -- placeholder: three NEUTRAL dice (never a rarity or die id) tumble until the result arrives
		for i = 1, 3 do
			local x = Pw / 2 + (i - 2) * 0.31 * Pw
			local h = dieS * 0.7
			local d = whole(panel, RollSprites.Die1, "RollingDie", x, dieCy, h, z + 2)
			if not self._rolling.Still then
				local spin = TweenService:Create(
					d,
					TweenInfo.new(0.7, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
					{ Rotation = 360 }
				)
				local hop = TweenService:Create(
					d,
					TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, (i - 1) * 0.08),
					{ Position = d.Position - UDim2.fromOffset(0, round(h * 0.15)) }
				)
				table.insert(self._tweens, spin)
				table.insert(self._tweens, hop)
				spin:Play()
				hop:Play()
			end
		end
		return
	end
	local pop = self._pop
	self._pop = false
	for i = 1, 3 do
		local item = list[i]
		if item == nil then
			continue -- an empty slot (a single roll result sits in the middle)
		end
		local x = cx(i)
		-- the die's own art (Sprites.DieArt, else the roll glyph tinted with its colour, as the Bag DICE tab)
		local die = Draw.img(panel, { Name = "Die" .. i, ZIndex = z + 2 })
		local art, tint = QuestLogic.dieArt(item.Id)
		Draw.icon(die, art, x, dieCy, dieS, dieS)
		die.ImageColor3 = tint or Color3.new(1, 1, 1)
		if pop then -- placeholder reveal: the die fades in (SetPop is never set under Reduced Motion)
			die.ImageTransparency = 1
			local t = TweenService:Create(
				die,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ ImageTransparency = 0 }
			)
			table.insert(self._tweens, t)
			t:Play()
		end
		local word = string.upper(item.Rarity)
		label(panel, L, {
			Name = "DieName" .. i,
			Text = item.Name,
			Base = 25,
			X = x,
			Y = nameCy,
			W = pitch - 8,
			H = nameH,
			Z = z + 3,
		})
		local pillW =
			math.min(round(pitch - 10), math.max(round(132 * L.w), math.ceil(Parts.measure(word, L.tmin)) + 14))
		local pill = Parts.Pill(panel, item.Rarity, word, {
			Name = "RarityPill" .. i,
			W = pillW,
			H = pillH,
			TextSize = textSize(L, 22, word, pillW - 12),
		})
		pill.AnchorPoint = Vector2.new(0.5, 0.5)
		pill.Position = UDim2.fromOffset(round(x), round(pillCy))
		pill.ZIndex = z + 3
		for _, d in pill:GetDescendants() do -- Global ZIndex: the pill's own parts must stay above it
			if d:IsA("GuiObject") then
				d.ZIndex = z + 4
			end
		end
	end
end

function View:_drawRarity(L, z: number)
	local Pw, Ph, f = L.rw, L.panelH, L.f
	local panel = Chrome.panel(self._canvas, {
		Name = "Rarity",
		Position = UDim2.fromOffset(L.rx, L.ry),
		Size = UDim2.fromOffset(Pw, Ph),
		ZIndex = z,
	})
	local plateH = 38.5 * f -- the mockup plate is 288 wide: 288 / native aspect 7.49
	local plateTop = round(12 * f)
	heading(panel, L, "RARITY CHANCES", Pw / 2, plateTop, plateH, z + 1)
	local top = plateTop + plateH + round(11 * f)
	local avail = Ph - top - round(12 * f)
	-- each 2 design px rim spills outside its row (and scales with K): rim + rim + 1 real px of clear gap
	local gap = math.max(round(5 * f), 4 + math.ceil(1 / K))
	local rowH = math.min(round(38 * f), (avail - 5 * gap) / 6)
	local pitch = (avail - rowH) / 5
	local rowW = Pw - round(34 * L.w)
	local rowX = (Pw - rowW) / 2
	local nameW, pctW = rowW * 0.43, rowW * 0.29
	local rowSize = math.max(math.floor(math.min(27 * f, rowH * 0.67) + 0.5), L.tmin)
	for _, r in self._rows do
		rowSize = math.min(
			rowSize,
			Parts.fitSize(r.Rarity, nameW, rowSize, L.tmin),
			Parts.fitSize(r.Text, pctW, rowSize, L.tmin)
		)
	end
	for i, row in self._rows do
		local c = ROW[row.Rarity] or ROW.Common
		local y = top + (i - 1) * pitch
		local bar = Chrome.panel(panel, {
			Name = "Row_" .. row.Rarity,
			Position = UDim2.fromOffset(round(rowX), round(y)),
			Size = UDim2.fromOffset(round(rowW), round(rowH)),
			BackgroundColor3 = c[1],
			Radius = 999,
			Rim = 2,
			ZIndex = z + 1,
		})
		bar.UIGradient.Color = ColorSequence.new(c[1], c[2])
		bar.UIStroke.Color = c[3]
		local icon = ROW_ICON[row.Rarity]
		local ic = Draw.img(bar, { Name = "Icon", ZIndex = z + 2 })
		Draw.icon(ic, icon[1], round(rowW * 0.135), rowH / 2, icon[2] * rowH / 38, icon[3] * rowH / 38)
		label(bar, L, {
			Name = "Name",
			Text = row.Rarity,
			Size = rowSize,
			AX = 0,
			X = rowW * 0.255,
			Y = rowH / 2,
			W = nameW,
			Z = z + 2,
		})
		label(bar, L, {
			Name = "Pct",
			Text = row.Text,
			Size = rowSize,
			AX = 1,
			X = rowW - round(17 * L.w),
			Y = rowH / 2,
			W = pctW,
			Z = z + 2,
		})
	end
end

function View:_drawPity(L, z: number, y: number)
	local W, H, f, w = L.W, L.pityH, L.f, L.w
	local panel = Chrome.panel(self._canvas, {
		Name = "Pity",
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(W, H),
		ZIndex = z,
	})
	-- info button: >= 44 real px hit area, art 36 design px
	local hs = math.max(math.ceil(44 / K), round(36 * f))
	local infoCx = hs / 2 + 6
	local hit = make("ImageButton", {
		Name = "InfoHit",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(infoCx), round(H / 2)),
		Size = UDim2.fromOffset(hs, hs),
		ZIndex = z + 1,
	}, panel)
	local art = Draw.img(hit, { Name = "Info", ZIndex = z + 2 })
	Draw.icon(art, RollSprites.Info, hs / 2, hs / 2, round(36 * f), round(36 * f))
	Parts.interact(hit)
	table.insert(
		self._connsBuild,
		hit.Activated:Connect(function()
			if self._onInfo then
				self._onInfo()
			end
		end)
	)
	local barL = hs + 12
	local barR = W - math.max(10, round(20 * w))
	local barW = barR - barL
	local barH = math.max(round(17 * f), 8)
	local barY = H * 0.72
	local pity = self._pity
	local _, fill = Chrome.track(panel, {
		Name = "PityBar",
		Position = UDim2.fromOffset(round(barL), round(barY - barH / 2)),
		Size = UDim2.fromOffset(round(barW), round(barH)),
		ZIndex = z + 1,
	}, GEM_YELLOW)
	local frac = if pity then RollLogic.pityFraction(pity.Count, pity.Max) else 0
	fill.Size = UDim2.fromScale(frac, 1)
	fill.Visible = frac > 0
	make("Frame", { -- the mockup's gloss line along the top of the fill
		Name = "Gloss",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.03, 0.18),
		Size = UDim2.fromScale(0.94, 0.22),
		ZIndex = z + 3,
	}, fill)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill.Gloss)
	if pity then
		local color = Parts.RarityColor[pity.Rarity] or Color3.new(1, 1, 1)
		local plain = `{pity.Rarity} guarantee`
		local textY = H * 0.33
		local count = RollLogic.pityText(pity.Count, pity.Max)
		local countW = math.ceil(Parts.measure(count, math.max(round(28 * f), L.tmin))) + 6
		label(panel, L, {
			Name = "PityText",
			Text = plain,
			Rich = `<font color="#{color:ToHex()}">{pity.Rarity}</font> guarantee`,
			Plain = plain,
			Base = 28,
			AX = 0,
			X = barL,
			Y = textY,
			W = barW - countW - 8,
			Z = z + 2,
		})
		label(panel, L, {
			Name = "Count",
			Text = count,
			Rich = `<font color="{YELLOW}">{pity.Count} /</font> {pity.Max}`, -- the count and the slash are yellow
			Plain = count,
			Base = 28,
			AX = 1,
			X = barR,
			Y = textY,
			W = countW,
			Z = z + 2,
		})
	end
end

function View:_drawButtons(L, z: number, y: number)
	local bh, f = L.btnH, L.f
	local defs = { RollSprites.Die1, RollSprites.Dice3, RollSprites.Dice3 }
	local rolling = self._rolling
	local s = bh / 87 -- sizes below are at the 87 design px button height
	for i, d in defs do
		local st = self._buttonState[i]
			or { Count = if i == 1 then 1 elseif i == 2 then 10 else 0, Price = 0, Enabled = false, Max = i == 3 }
		local isMax = st.Max == true
		local on = st.Enabled and not rolling -- rolling: every button reads disabled
		local colors = if on then BUTTON[i] else DISABLED
		local bwi = L.btnW
		local gap = math.max(L.gap, 8)
		local startX = (L.W - 3 * bwi - 2 * gap) / 2
		local btn = make("TextButton", {
			Name = if isMax then "RollMax" else "Roll" .. st.Count,
			Position = UDim2.fromOffset(round(startX + (i - 1) * (bwi + gap)), y),
			Size = UDim2.fromOffset(round(bwi), bh),
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			ZIndex = z + 1,
		}, self._canvas)
		local body =
			Chrome.panel(btn, { Name = "Body", Size = UDim2.fromScale(1, 1), Radius = 13, Rim = 2, ZIndex = z })
		body.UIGradient.Color = ColorSequence.new(colors[1], colors[2])
		body.UIStroke.Color = colors[3]
		Parts.interact(btn) -- hover / press scale and the gamepad focus rim
		local dw, dh = math.min(72 * s, bwi * 0.25), bh * 0.68
		local die = Draw.img(btn, { Name = "Dice", ZIndex = z + 2 })
		Draw.icon(die, d, bwi * 0.18, bh / 2, dw, dh)
		die.ImageColor3 = if on then Color3.new(1, 1, 1) else rgb(190, 190, 203)
		local cx = bwi * 0.64
		local busy = rolling and (if isMax then rolling.Max == true else rolling.Max ~= true and rolling.Count == st.Count)
		local text = if busy
			then ROLLING
			elseif isMax then (if st.Count > 1 then `ROLL MAX x{st.Count}` else "ROLL MAX")
			else `ROLL {st.Count}`
		label(btn, L, {
			Name = "Label",
			Text = text,
			Size = textSize(L, 33 * s / f, text, bwi * 0.62),
			X = cx,
			Y = bh * 0.28,
			W = bwi * 0.62,
			Z = z + 2,
		})
		local chipW, chipH = bwi * 0.62, bh * 0.38
		local chip = Chrome.panel(btn, {
			Name = "Chip",
			Position = UDim2.fromOffset(round(cx - chipW / 2), round(bh * 0.69 - chipH / 2)),
			Size = UDim2.fromOffset(round(chipW), round(chipH)),
			BackgroundColor3 = colors[4],
			NoGradient = true,
			Radius = 999,
			Rim = 1,
			ZIndex = z + 1,
		})
		chip.UIStroke.Color = Color3.new(0, 0, 0)
		chip.UIStroke.Transparency = 0.6
		local reason
		for _, t in if not st.Enabled and not rolling then NOTICE[self._notice] or {} else {} do
			reason = t
			if Parts.measure(t, L.tmin) <= chipW - 8 then
				break
			end
		end
		if reason then -- disabled: the chip says why instead of the price
			label(chip, L, {
				Name = "Reason",
				Text = reason,
				Base = 26,
				X = chipW / 2,
				Y = chipH / 2,
				W = chipW - 8,
				Z = z + 2,
			})
		else
			local priceText = `x{st.Price}`
			local gemS = math.min(chipH * 0.73, chipW * 0.22)
			local size = textSize(L, 27 * s / f, priceText, chipW - gemS - 12)
			local tw = Parts.measure(priceText, size)
			local gx = (chipW - (gemS + 6 + tw)) / 2
			local gem = Draw.img(chip, { Name = "Gem", Image = Sprites.Gem, ZIndex = z + 2 })
			gem.AnchorPoint = Vector2.new(0, 0.5)
			gem.Position = UDim2.fromOffset(round(gx), round(chipH / 2))
			gem.Size = UDim2.fromOffset(round(gemS), round(gemS))
			gem.ScaleType = Enum.ScaleType.Fit
			label(chip, L, {
				Name = "Price",
				Text = priceText,
				Size = size,
				AX = 0,
				X = gx + gemS + 6,
				Y = chipH / 2,
				W = tw + 6,
				Z = z + 2,
			})
		end
		btn:SetAttribute("Enabled", on)
		table.insert(
			self._connsBuild,
			btn.Activated:Connect(function()
				if self._onRoll then
					self._onRoll(st.Count, isMax)
				end
			end)
		)
	end
end

-- The VIP offer: a gold bar under the roll buttons, "VIP: 10% off every roll - R$ 299"; pressing it prompts the pass.
function View:_drawVip(L, z: number, y: number)
	local vip = self._vip
	local h = L.vipH - L.btnGap
	local w = math.min(L.W, math.max(L.btnW * 3 + 2 * math.max(L.gap, 8), 300))
	local btn = make("TextButton", {
		Name = "VipOffer",
		Position = UDim2.fromOffset(round((L.W - w) / 2), y),
		Size = UDim2.fromOffset(round(w), h),
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		ZIndex = z + 1,
	}, self._canvas)
	local body = Chrome.panel(btn, { Name = "Body", Size = UDim2.fromScale(1, 1), Radius = 13, Rim = 2, ZIndex = z })
	body.UIGradient.Color = ColorSequence.new(rgb(255, 196, 38), rgb(200, 120, 8))
	body.UIStroke.Color = rgb(255, 235, 150)
	Parts.interact(btn)
	local text = `VIP: {vip.Pct}% off every roll  -  R$ {vip.Robux}`
	label(btn, L, {
		Name = "Label",
		Text = text,
		Size = textSize(L, 30, text, w - 24),
		X = w / 2,
		Y = h / 2,
		W = w - 24,
		Z = z + 2,
	})
	table.insert(
		self._connsBuild,
		btn.Activated:Connect(function()
			if self._onVip then
				self._onVip()
			end
		end)
	)
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
	self:_stopTweens()
	clear(self._canvas)
	local z = self._canvas.ZIndex + 1
	if self._pool == "Event" then
		local ph = L.total
		local panel = Chrome.panel(self._canvas, { Name = "Empty", Size = UDim2.fromOffset(L.W, ph), ZIndex = z })
		label(panel, L, {
			Name = "Message",
			Text = "No event right now",
			Base = 40,
			X = L.W / 2,
			Y = ph / 2,
			W = L.W - 80,
			Z = z + 1,
			Stroke = 3,
		})
		self._scroll.CanvasSize = UDim2.fromOffset(0, 0)
		return
	end
	self:_drawFeatured(L, z)
	self:_drawRarity(L, z)
	local y = L.ry + L.panelH + L.btnGap
	self:_drawPity(L, z, y)
	self:_drawButtons(L, z, y + L.pityH + L.btnGap)
	if self._vip then
		self:_drawVip(L, z, y + L.pityH + L.btnGap + L.btnH + L.btnGap)
	end
	self._scroll.CanvasSize = UDim2.fromOffset(0, math.max(L.H, L.total))
end

-- Public ----------------------------------------------------------------------------------------------------

function View.new(slot)
	local self = setmetatable({}, View)
	self._conns, self._connsBuild = {}, {}
	self._pool = "Standard"
	self._featuredIds, self._featuredTitle, self._rows, self._pity = {}, "FEATURED DICE", {}, nil
	self._buttonState = {}
	self._tweens, self._pop = {}, false
	local scroll = make("ScrollingFrame", {
		Name = "RollView",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageTransparency = 0.25,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		Size = UDim2.fromScale(1, 1),
		ZIndex = slot.ZIndex + 1,
	}, slot)
	local canvas = make("Frame", {
		Name = "Canvas",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromScale(1, 1),
		ZIndex = scroll.ZIndex,
	}, scroll)
	self._scroll, self._canvas = scroll, canvas
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
				for _, c in a:GetChildren() do
					if c:IsA("UIScale") and c.Name ~= "Pop" then
						k *= c.Scale
						if not scaleSeen[c] then -- a later scale change (window resize) must rebuild: K sizes the hit boxes
							scaleSeen[c] = true
							table.insert(self._conns, c:GetPropertyChangedSignal("Scale"):Connect(rebuild))
						end
					end
				end
				a = a.Parent
			end
			K = k
			local L = compute(w, h, self._vip ~= nil and self._pool == "Standard")
			canvas.Size = UDim2.fromOffset(w, math.max(h, L.total))
			self._L = L
			self:_build()
		end)
	end
	self._rebuild = rebuild
	table.insert(self._conns, slot:GetPropertyChangedSignal("Size"):Connect(rebuild))
	rebuild()
	return self
end

function View:SetPool(pool: string)
	self._pool = pool
	self._rebuild()
end

function View:SetFeatured(list, title: string?)
	self._featuredIds = list
	self._featuredTitle = title or "FEATURED DICE"
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

-- Why a disabled button is disabled ("gems" | "region" | nil), shown in its price chip.
-- The VIP pass offer { Pct, Robux } shown under the buttons, or nil (owned / no pass).
function View:SetVip(offer)
	self._vip = offer
	self._rebuild()
end

function View:OnVip(cb)
	self._onVip = cb
end

function View:SetNotice(kind: string?)
	self._notice = kind
	self._rebuild()
end

function View:_stopTweens()
	for _, t in self._tweens do
		t:Cancel()
		t:Destroy()
	end
	table.clear(self._tweens)
end

function View:SetRolling(state)
	self._rolling = state
	self._rebuild()
end

function View:SetPop(on: boolean)
	self._pop = on
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
	self:_stopTweens()
	self._scroll:Destroy()
end

return View
