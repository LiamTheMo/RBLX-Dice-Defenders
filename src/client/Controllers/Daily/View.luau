-- Daily menu view (daily-revised.png): claim strip, six day cards + the Day 7 chest card, and the PROGRESS | CLAIM | timer bar, in the shell's slot.
-- Visual only: no NetClient. Design px under the shell's UIScale; the slot's Size offset and "Compact" attribute pick the numbers
-- (one code path: Full = the mockup's 1068 x 582 content box, Compact = fixed-height strip and bar, the cards take the rest of the height).
-- View.new(slot) -> :SetDays(DailyLogic.days(Catalog.Daily.Days)) :SetLogin(Meta.Login) :SetTimer(prefix?, value?)
--   :SetClaimState("Ready" | "Claimed" | "Soon") :SetSoon(on) (the loading card) :OnAction(cb()) (a CLAIM press while "Ready") :Destroy()
-- Setters only store state; one deferred rebuild draws it (also on every slot size / Compact / scale change).
-- GUI paths under the slot: DailyRoot.Main.{Strip, Cards.Day1..Day7, Bar}, DailyRoot.Soon. Layers: cards 24, content 25-27.

local Bag = require(script.Parent.Parent.Bag.BagSprites)
local Chrome = require(script.Parent.Parent.Bag.Chrome)
local DailyLogic = require(script.Parent.DailyLogic)
local DailySprites = require(script.Parent.DailySprites)
local Parts = require(script.Parent.Parent.Bag.Parts)
local Shared = require(script.Parent.Parent.SharedSprites)
local Sprites = require(script.Parent.Parent.Sprites)
local UiKit = require(script.Parent.Parent.UiKit)

local Display = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Display"))

local make = UiKit.make

local WHITE = Color3.fromRGB(250, 248, 245)
local GOLD = Color3.fromRGB(252, 213, 26)
local LINE = Color3.fromRGB(18, 18, 22) -- text outline
local ORANGE = Color3.fromRGB(255, 152, 32) -- today's glow, plate and rim
local MAX_SCALE = 1.5 -- the Shell's largest UIScale: art is never drawn past native / MAX_SCALE design px (no upscale at 2560x1440)
local MIN_PX = 12 -- smallest text, real px

-- Per state: card fill, rim, plate fill, plate rim, pill fill and rim (CLAIM uses the shared green pill art), sampled from the mockup.
local STATE = {
	Upcoming = {
		fill = Color3.fromRGB(37, 36, 38),
		rim = Color3.fromRGB(143, 141, 146),
		plate = Color3.fromRGB(58, 57, 59),
		plateRim = Color3.fromRGB(126, 123, 124),
		pill = Color3.fromRGB(70, 69, 72),
		pillRim = Color3.fromRGB(150, 149, 152),
	},
	Claimed = {
		fill = Color3.fromRGB(38, 59, 33),
		rim = Color3.fromRGB(130, 143, 130),
		plate = Color3.fromRGB(44, 105, 16),
		plateRim = Color3.fromRGB(112, 191, 87),
		pill = Color3.fromRGB(42, 92, 31),
		pillRim = Color3.fromRGB(112, 191, 87),
	},
	Today = {
		fill = Color3.fromRGB(34, 34, 35),
		rim = Color3.fromRGB(255, 190, 90),
		plate = Color3.fromRGB(53, 51, 50),
		plateRim = ORANGE,
	},
}

local COIN, GEM = Shared.Coin, Shared.Gem -- the HUD currency icons (owner rule)
local ROLL = { Image = Sprites.Icon.Roll, Size = Vector2.new(256, 185) } -- dice without art, tinted
local DIE = Vector2.new(202, 213) -- the 10 elemental die icons are 200-205 x 211-215 (lobby hud/export/manifest.json); drawn with Fit

local round = UiKit.round

local K = 1 -- real px per design px under the shell's UIScales (set per build)

local function minText(): number
	return math.ceil(MIN_PX / K)
end

-- Live text centred at (cx, cy) in a w-wide box, shrunk (>= the 12 real px floor) to fit.
local function txt(parent, name: string, text: string, size: number, cx: number, cy: number, w: number, z: number, o)
	o = o or {}
	local floor = minText()
	size = Parts.fitSize(o.plain or text, w, math.max(size, floor), floor)
	local l = Parts.text(parent, {
		Name = name,
		Text = text,
		RichText = o.rich == true,
		TextSize = size,
		TextColor3 = o.fill or WHITE,
		TextTruncate = Enum.TextTruncate.None,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(cx), round(cy)),
		Size = UDim2.fromOffset(
			math.min(round(w), math.ceil(Parts.measure(o.plain or text, size)) + 6),
			math.ceil(size * 1.05)
		),
		ZIndex = z,
	}, o.px or 2)
	l.UIStroke.Color = LINE
	return l
end

-- A whole icon, aspect kept (Fit), at most maxW x maxH and never past native / MAX_SCALE, centred at (cx, cy).
local function icon(parent, rec, cx: number, cy: number, maxW: number, maxH: number, z: number, name: string)
	local size = rec.Size
	local s = math.min(maxW / size.X, maxH / size.Y, 1 / MAX_SCALE)
	return make("ImageLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Image = rec.Image,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(cx), round(cy)),
		Size = UDim2.fromOffset(round(size.X * s), round(size.Y * s)),
		ZIndex = z,
	}, parent)
end

-- Reward Kind -> its icon record and tint. Dice: elemental art, else the Roll glyph tinted by Display colour.
local function rewardRec(r): (any, Color3?)
	local kind = r.Kind
	if kind == "Coins" then
		return COIN
	elseif kind == "Gems" then
		return GEM
	elseif kind == "Potion" then
		return DailySprites.Potion
	elseif kind == "Crystals" then
		return Bag.IconCrystals
	end
	local art = Sprites.Dice[Sprites.DieArt[r.Id]]
	if art then
		return { Image = art, Size = DIE }
	end
	local info = Display.Dice[r.Id]
	return ROLL, info and info.Color
end

local function rewardIcon(parent, r, cx: number, cy: number, maxW: number, maxH: number, z: number)
	local rec, tint = rewardRec(r)
	icon(parent, rec, cx, cy, maxW, maxH, z, "Icon").ImageColor3 = tint or Color3.new(1, 1, 1)
end

-- Bare tick / padlock badges: SharedSprites.Tick / Padlock (ids filled later; blank until uploaded), s design px square, centred at (cx, cy).
local function glyph(parent, kind: string, cx: number, cy: number, s: number, z: number)
	local rec = if kind == "Tick" then Shared.Tick else Shared.Padlock
	icon(parent, rec or { Image = "", Size = Vector2.new(100, 100) }, cx, cy, s, s, z, kind)
end

local View = {}
View.__index = View

-- Layout ----------------------------------------------------------------------------------------------------

local function compute(W: number, H: number, compact: boolean)
	local L = { W = W, H = H, compact = compact }
	L.touch = math.ceil(44 / K) -- smallest button height that is >= 44 real px
	if compact then
		L.top, L.stripH, L.g1, L.barH, L.g2, L.bottom = 0, 38, 8, 72, 8, 0
		L.gap, L.inset = 4, 4
	else
		local k = math.min(1, H / 582)
		L.top, L.stripH, L.g1, L.barH, L.g2, L.bottom = 25 * k, 54 * k, 35 * k, 101 * k, 48 * k, 15 * k
		L.gap, L.inset = 9, 3
	end
	L.top, L.stripH, L.barH = round(L.top), round(L.stripH), round(L.barH)
	L.cardsY = round(L.top + L.stripH + L.g1)
	L.cardH = round(H - L.cardsY - L.g2 - L.barH - L.bottom)
	L.barY = L.cardsY + L.cardH + round(L.g2)
	L.cw = (W - 2 * L.inset - 6 * L.gap) / (6 + 160 / 140) -- six cards and Day 7 (160 / 140 as wide)
	L.f = math.min(1, L.cardH / 304, L.cw / 140) -- text and icon scale of the card contents
	return L
end

-- Build -----------------------------------------------------------------------------------------------------

function View:_card(L, parent, day, state: string, x: number, w: number)
	local c = STATE[state]
	local h, f = L.cardH, L.f
	local today = state == "Today"
	local card = make(if today then "TextButton" else "Frame", {
		Name = "Day" .. day.Day,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(x + w / 2), L.cardsY + round(h / 2)),
		Size = UDim2.fromOffset(round(w), h),
		ZIndex = 24,
	}, parent)
	if today then
		card.Text = ""
		card.AutoButtonColor = false
		Parts.interact(card) -- hover / press scale, gold focus rim for gamepad
		table.insert(
			self._connsBuild,
			card.Activated:Connect(function()
				if self._claim == "Ready" and self._onAction then
					self._onAction()
				end
			end)
		)
		local glow = make("Frame", {
			Name = "Glow",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(-4, -4),
			Size = UDim2.new(1, 8, 1, 8),
			ZIndex = 23,
		}, card)
		make("UICorner", { CornerRadius = UDim.new(0, 24) }, glow)
		Chrome.stroke(glow, ORANGE, 5).Transparency = 0.55
	end
	local panel = Chrome.panel(card, {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		Radius = 20,
		BackgroundColor3 = c.fill,
		ZIndex = 24,
	})
	panel.UIStroke.Color = c.rim

	-- DAY n plate
	local inset = round(w * 0.11)
	local plateTop = math.max(5, round(h * 0.026))
	local ph = math.clamp(round(h * 0.122), 26, 37)
	local plate = Chrome.strip(card, {
		Name = "Plate",
		Position = UDim2.fromOffset(inset, plateTop),
		Size = UDim2.fromOffset(w - 2 * inset, ph),
		Radius = 999,
		BackgroundColor3 = c.plate,
		ZIndex = 25,
	})
	plate.UIStroke.Color = c.plateRim
	txt(plate, "DayLabel", "DAY " .. day.Day, round(32 * f), (w - 2 * inset) / 2, ph / 2 + 1, w - 2 * inset - 12, 27)

	-- status pill: CLAIMED / CLAIM / UPCOMING
	local pillInset = round(w * (if L.compact then 0.03 else 0.06))
	local pillH = math.clamp(round(h * 0.14), 28, 43)
	local pillBottom = math.max(6, round(h * 0.043))
	local pillW = round(w - 2 * pillInset)
	if today then
		local pill = make("ImageLabel", {
			Name = "Pill",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(pillInset, h - pillBottom - pillH),
			Size = UDim2.fromOffset(pillW, pillH),
			ZIndex = 25,
		}, card)
		Parts.skinH(pill, Shared.PillGreen, pillH)
		txt(pill, "Label", "CLAIM", round(34 * f), pillW / 2, pillH / 2 - 1, pillW - 10, 27, { px = 3 })
	else
		local pill = Chrome.strip(card, {
			Name = "Pill",
			Position = UDim2.fromOffset(pillInset, h - pillBottom - pillH),
			Size = UDim2.fromOffset(pillW, pillH),
			Radius = 999,
			BackgroundColor3 = c.pill,
			ZIndex = 25,
		})
		pill.UIStroke.Color = c.pillRim
		local text = if state == "Claimed" then "CLAIMED" else "UPCOMING"
		local gs = round(pillH * 0.5)
		local size = Parts.fitSize(
			text,
			pillW - gs - (if L.compact then 9 else 22),
			math.max(round(26 * f), minText()),
			minText()
		)
		local tw = Parts.measure(text, size)
		local badge = tw + gs + 10 <= pillW -- Compact: no room for the lock / tick beside the word: the word alone
		local x0 = (pillW - (if badge then gs + 6 + tw else tw)) / 2
		if badge then
			glyph(pill, if state == "Claimed" then "Tick" else "Lock", x0 + gs / 2, pillH / 2, gs, 27)
		end
		txt(pill, "Label", text, size, x0 + (if badge then gs + 6 else 0) + tw / 2, pillH / 2 + 1, tw + 8, 27)
	end

	-- rewards between the plate and the pill
	local areaTop = plateTop + ph + 6
	local areaBot = h - pillBottom - pillH - 6
	local rewards = day.Rewards
	local n = #rewards
	if day.Chest then
		local zoneH = round(h * 0.22)
		local chestBot = areaBot - zoneH
		icon(
			card,
			DailySprites.Chest,
			w / 2,
			(areaTop - 2 + chestBot) / 2,
			w * 0.8,
			chestBot - areaTop + 2,
			26,
			"Chest"
		)
		local colW = (w - 8) / math.max(n, 1)
		for i, r in rewards do
			local cx = 4 + (i - 0.5) * colW
			rewardIcon(card, r, cx, areaBot - zoneH * 0.68, colW * 0.7, zoneH * 0.58, 26)
			local text = DailyLogic.amountText(r)
			local size = math.max(round(24 * f), minText())
			if Parts.measure(text, size) > colW and r.Amount >= 1000 then
				text = "+" .. math.floor(r.Amount / 100) / 10 .. "K" -- phones: 1,000 -> +1K when the column is too narrow
			end
			txt(card, "Amount", text, size, cx, areaBot - zoneH * 0.18, colW + 6, 27)
		end
	else -- stacked, centred: icon over amount, one row per reward (3 rows get smaller text)
		local rh = (areaBot - areaTop) / math.max(n, 2)
		local top0 = areaTop + (math.max(n, 2) - n) * rh / 2
		local size = if n <= 2 then round(34 * f) else round(math.min(34 * f, rh * 0.4))
		for i, r in rewards do
			local rowTop = top0 + (i - 1) * rh
			rewardIcon(card, r, w / 2, rowTop + rh * 0.4, w * 0.62, rh * (if n <= 2 then 0.58 else 0.55), 26)
			txt(card, "Amount", DailyLogic.amountText(r), size, w / 2, rowTop + rh * 0.81, w - 8, 27, { px = 3 })
		end
	end
end

-- The strip: calendar icon + the sentence ("7 days!" in gold) on a Chrome strip centred on the window axis.
function View:_strip(L, parent)
	local c = L.compact
	local w = math.min(700, L.W - 24)
	local h = L.stripH
	local strip = Chrome.strip(parent, {
		Name = "Strip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(round(L.W / 2), L.top),
		Size = UDim2.fromOffset(w, h),
		Radius = 20,
		BackgroundColor3 = Color3.fromRGB(56, 56, 58),
		ZIndex = 24,
	})
	local ih = if c then h - 6 else 56 -- mockup calendar 55 x 56, left edge 37 px in
	icon(strip, DailySprites.Calendar, if c then ih * 0.5 + 14 else 64, h / 2, ih, ih, 26, "Calendar")
	local left = ih + 22
	local avail = w - left - 20
	local mid = if c then left + avail / 2 else 390 -- mockup text centre
	txt(
		strip,
		"Text",
		`Claim rewards every day for <font color="#FCD51A">7 days!</font>`,
		if c then 24 else 38,
		mid,
		h / 2 + 1,
		avail,
		27,
		{ rich = true, px = 3, plain = "Claim rewards every day for 7 days!" }
	)
end

-- The bottom bar: calendar + PROGRESS + track | CLAIM | stopwatch + timer. Full segments sit at the mockup's offsets scaled with the bar width.
function View:_bar(L, parent)
	local c = L.compact
	local bw, bh = L.W - 2 * L.inset, L.barH
	local bar = Chrome.strip(parent, {
		Name = "Bar",
		Position = UDim2.fromOffset(L.inset, L.barY),
		Size = UDim2.fromOffset(bw, bh),
		Radius = 20,
		BackgroundColor3 = Color3.fromRGB(43, 43, 47),
		ZIndex = 24,
	})
	local u = if c then 1 else bw / 1062 -- Full positions are measured on the mockup's 1062 wide bar
	local v = math.min(1, bh / 101)
	local mid = bh / 2
	-- left segment: calendar, PROGRESS title, track with "n / 7 DAYS"
	icon(bar, DailySprites.Calendar, (if c then 40 else 66) * u, mid, 60 * v, 66 * v, 26, "Calendar")
	local streak = if self._login then self._login.Streak else 0
	local px = (if c then 70 else 113) * u
	local pw = if c then math.clamp(bw * 0.2, 110, 150) else 202 * u
	local pcx = px + pw / 2
	txt(bar, "ProgressTitle", "PROGRESS", round(31 * v), pcx - 8, bh * 0.25 - 3, pw, 27)
	local th = math.max(round(35 * v), 22)
	local track, fill = Chrome.track(bar, {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(pcx), round(bh * 0.63)),
		Size = UDim2.fromOffset(round(pw), th),
		ZIndex = 25,
	}, Color3.fromRGB(254, 172, 28))
	fill.Size = UDim2.fromScale(math.clamp(streak / DailyLogic.DAYS, 0, 1), 1)
	txt(track, "ProgressText", DailyLogic.progressText(streak), round(28 * v), pw / 2, th / 2, pw - 8, 28)
	local div1 = px + pw + (if c then 10 else 33 * u)
	local div2 = bw - (if c then math.clamp(bw * 0.27, 170, 270) else 340 * u)
	for i, x in { div1, div2 } do
		Chrome.divider(bar, {
			Name = "Divider" .. i,
			BackgroundColor3 = GOLD,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(round(x), round(mid)),
			Size = UDim2.fromOffset(3, round(bh * 0.64)),
			ZIndex = 25,
		})
	end
	-- the CLAIM button fills the middle segment (>= 44 real px tall)
	if self._claim ~= "Soon" then
		local ready = self._claim == "Ready"
		local cw = math.min(div2 - div1 - 2 * (if c then 14 else 40 * u), if c then 220 else 258)
		local btn = Parts.button(bar, {
			Name = "Claim",
			Style = if ready then "Green" else "Grey",
			Label = if ready then "CLAIM" else "CLAIMED",
			TextSize = round(52 * v),
			Enabled = ready,
			Size = UDim2.fromOffset(round(cw), math.min(math.max(round(63 * v), L.touch), bh - 8)),
		})
		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Position = UDim2.fromOffset(round((div1 + div2) / 2), round(mid))
		btn.ZIndex = 26
		btn.Label.ZIndex = 27
		table.insert(
			self._connsBuild,
			btn.Activated:Connect(function()
				if self._claim == "Ready" and self._onAction then
					self._onAction()
				end
			end)
		)
	end
	-- timer: stopwatch + two lines, hidden while a day can be claimed
	self._timerLive = nil
	if self._timer then
		local prefix, value = self._timer[1], self._timer[2]
		local tl, tr = div2 + (if c then 8 else 60 * u), bw - 14
		local sw = (if c then 36 else 50) * v
		icon(bar, DailySprites.Stopwatch, tl + sw / 2, mid, sw, sw * 1.05, 26, "Stopwatch")
		local textW = tr - (tl + sw + 8)
		local tx = tl + sw + 8 + textW / 2
		txt(bar, "TimerPrefix", prefix, round(28 * v), tx, mid - bh * 0.17, textW, 27)
		local vsize = round(40 * v)
		self._timerLive = {
			Label = txt(bar, "TimerValue", value, vsize, tx, mid + bh * 0.17, textW, 27, { fill = GOLD }),
			Fit = function(s: string): number
				return Parts.fitSize(s, textW, math.max(vsize, minText()), minText())
			end,
		}
	end
end

function View:_drawSoon(L)
	local W, H = L.W, L.H
	local w, h = math.min(if L.compact then 340 else 520, W - 20), math.min(if L.compact then 150 else 240, H - 10)
	local panel = Chrome.panel(self._soon, {
		Name = "SoonCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(round(W / 2), round(H / 2)),
		Size = UDim2.fromOffset(w, h),
		ZIndex = 30,
	})
	local ih = round(h * 0.4)
	icon(panel, DailySprites.Calendar, w / 2, h * 0.28, ih, ih, 31, "Icon")
	txt(panel, "Title", "DAILY REWARDS", if L.compact then 24 else 36, w / 2, h * 0.64, w - 30, 32)
	txt(
		panel,
		"Sub",
		"Loading...",
		if L.compact then 18 else 26,
		w / 2,
		h * 0.84,
		w - 30,
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
	for _, parent in { self._main, self._soon } do
		for _, ch in parent:GetChildren() do
			ch:Destroy()
		end
	end
	self._main.Visible, self._soon.Visible = not self._soonOn, self._soonOn
	if self._soonOn then
		self:_drawSoon(L)
	else
		self:_strip(L, self._main)
		local cards = make(
			"Frame",
			{ Name = "Cards", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 24 },
			self._main
		)
		local x = L.inset
		for i = 1, 7 do
			local day = self._days[i]
			local w = if i == 7 then L.cw * 160 / 140 else L.cw
			if day then
				self:_card(L, cards, day, DailyLogic.cardState(day.Day, self._login), x, w)
			end
			x += w + L.gap
		end
		self:_bar(L, self._main)
	end
	Chrome.restroke(self._root, K)
end

-- Public ----------------------------------------------------------------------------------------------------

function View.new(slot)
	local self = setmetatable({}, View)
	self._conns, self._connsBuild, self._days = {}, {}, {}
	self._login, self._claim, self._soonOn = nil, "Soon", true
	local z = slot.ZIndex + 1
	local root = make(
		"Frame",
		{ Name = "DailyRoot", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z },
		slot
	)
	self._main =
		make("Frame", { Name = "Main", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z }, root)
	self._soon = make(
		"Frame",
		{ Name = "Soon", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = z },
		root
	)
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

-- Meta.Login {Streak, NextDay?, ...}: card states and the progress bar.
function View:SetLogin(login)
	self._login = login
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
		l.Size = UDim2.fromOffset(
			math.min(l.Size.X.Offset, math.ceil(Parts.measure(value :: string, size)) + 6),
			math.ceil(size * 1.05)
		)
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
	self._root:Destroy()
end

return View
