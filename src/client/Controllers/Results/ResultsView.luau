-- Results window view: ONE shell (740x620 window, ribbon + emblem overhang, CONTINUE) under one UIScale, three content
-- builders on top (Summary solo/co-op, Victory, Defeat). Draws a ResultsLogic view-model; owns no rule, number or remote.
-- Names: PlayerGui.Lobby.Root.Results.Scaled.Window.{header, stats, rewards, players, trophies, level, continue}.
-- Design px 1672x941; the window box is [466,181,740,620]. All art is whole assets at native aspect (no slicing); panels,
-- glows, bars and pills are code-drawn; all text is live (Parts.text, fitted to measured widths).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UiKit = require(script.Parent.Parent.UiKit)
local Chrome = require(script.Parent.Parent.Bag.Chrome)
local Parts = require(script.Parent.Parent.Bag.Parts)
local SettingsLogic = require(script.Parent.Parent.Settings.SettingsLogic)
local HudSprites = require(script.Parent.Parent.Sprites)
local Sprites = require(script.Parent.ResultsSprites)
local ResultsLogic = require(script.Parent.ResultsLogic)

local make = UiKit.make

local WIN_W, WIN_H = 740, 620
local GUT = 28 -- content gutter
local CW = WIN_W - 2 * GUT -- 684
local OVERHANG = 97 -- emblem top above the window
local GROUP_H = OVERHANG + WIN_H -- 717
local TOP_BAR = 58 -- phone HUD top bar
local BASELINE = 76 -- ribbon bottom, window-local (y257 in design space)
local EMBLEM_H = 100
local CONT = { x = 70, y = 522, w = 600, h = 76 }
local PLATE_H = 96 -- CONTINUE art height: 507 wide at native aspect, under native (661x125 design px at 2560x1440)
local Z_ROOT = 300 -- above the lobby HUD (its top item is Z 200 + children) and menus; Lobby raises the toast to Z 400+
local DUR = 0.9 -- count / fill timeline (s), one for every animated value
local boost = 1 -- phone label boost (set per Render)
local floorSize = 11

local WHITE = Color3.new(1, 1, 1)
local SOFT = Color3.fromRGB(205, 210, 235)
local DARK = Color3.fromRGB(28, 28, 30)
local RIM = Color3.fromRGB(190, 190, 196)
local ORANGE = Color3.fromRGB(253, 161, 11)

local THEME = {
	Summary = {
		Ribbon = Color3.fromRGB(176, 64, 240),
		Rays = Color3.fromRGB(190, 60, 255),
		Laurel = WHITE,
		Alpha = 0.62,
	},
	Victory = { Ribbon = Color3.fromRGB(40, 205, 40), Rays = Color3.fromRGB(255, 196, 0), Laurel = WHITE, Alpha = 0.75 },
	Draw = { Ribbon = Color3.fromRGB(110, 134, 190), Rays = Color3.fromRGB(160, 180, 220), Laurel = WHITE, Alpha = 0.7 },
	Defeat = {
		Ribbon = Color3.fromRGB(215, 36, 40),
		Rays = Color3.fromRGB(255, 90, 80),
		Laurel = Color3.fromRGB(255, 120, 120),
		Alpha = 0.45,
	},
}
-- Header dice per variant: sprite key, x, y (window-local), height, rotation.
local DICE = {
	Victory = {
		{ "DieBlue", 92, -33, 80, -8 },
		{ "DiePurple", 138, 14, 56, 12 },
		{ "DieRed", 571, -31, 75, 10 },
		{ "DieWhite", 549, 19, 56, -10 },
	},
	Draw = {
		{ "DieBlue", 92, -33, 80, -8 },
		{ "DieWhite", 138, 14, 56, 12 },
		{ "DieWhite", 571, -31, 75, 10 },
		{ "DieBlue", 549, 19, 56, -10 },
	},
	Defeat = {
		{ "DieRed", 74, -31, 80, -8 },
		{ "DieWhite", 122, 21, 58, 12 },
		{ "DieRed", 590, -31, 75, 8 },
		{ "DieRed", 562, 25, 54, -10 },
	},
}
local GROUPS = { "stats", "rewards", "players", "trophies", "level" }

local ResultsView = {}
ResultsView.__index = ResultsView

-- Builders -------------------------------------------------------------------------------------------------

local function corner(inst, r: number)
	make("UICorner", { CornerRadius = UDim.new(0, r) }, inst)
end

local function box(parent, name: string, x: number, y: number, w: number, h: number, props: { [string]: any }?)
	local p = props or {}
	p.Name, p.Position, p.Size = name, UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
	p.BackgroundTransparency = if p.BackgroundColor3 then p.BackgroundTransparency or 0 else 1
	p.BorderSizePixel = 0
	return make("Frame", p, parent)
end

-- Whole sprite at native aspect, height h.
local function art(parent, name: string, key: string, h: number, x: number, y: number, props: { [string]: any }?)
	local s = Sprites[key]
	local p = props or {}
	p.Name, p.Image, p.BackgroundTransparency = name, s.Image, 1
	p.ScaleType = Enum.ScaleType.Fit
	p.Position, p.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(h * s.Size.X / s.Size.Y, h)
	p.ZIndex = p.ZIndex or 2
	return make("ImageLabel", p, parent), h * s.Size.X / s.Size.Y
end

local function artW(key: string, h: number): number
	local s = Sprites[key]
	return h * s.Size.X / s.Size.Y
end

-- Live text fitted to its box width (never "..." : the size shrinks instead).
local function text(
	parent,
	name: string,
	str: string,
	size: number,
	x: number,
	y: number,
	w: number,
	h: number,
	props: { [string]: any }?,
	stroke: number?
)
	local p = props or {}
	p.Name, p.Text = name, str
	p.Position, p.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
	if size <= 22 then
		size = math.floor(size * boost + 0.5)
	end
	local floor = p.Floor or floorSize
	p.Floor = nil
	if stroke and stroke > 0 and size >= 24 then
		stroke = math.max(stroke, math.ceil(size / 13)) -- heavier outline on big numbers (mockup weight)
	end
	p.TextSize = Parts.fitSize(str, w * 0.96, size, math.min(size, floor))
	p.TextTruncate = p.TextTruncate or Enum.TextTruncate.None
	p.ZIndex = p.ZIndex or 3
	return Parts.text(parent, p, stroke)
end

local function gold(label)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(253, 252, 42), Color3.fromRGB(203, 155, 3)),
		Rotation = 90,
	}, label)
end

-- Every ScreenGui here is ZIndex Global: an element draws by absolute ZIndex only. Builders give LOCAL values; restack turns
-- them absolute (child = parent + local) top-down, which is also correct under Sibling mode.
local function restack(inst: Instance)
	for _, c in inst:GetChildren() do
		if c:IsA("GuiObject") then
			c.ZIndex += (inst :: GuiObject).ZIndex
			restack(c)
		end
	end
end

local function pillColors(parent, c0: Color3, c1: Color3)
	make("UIGradient", { Color = ColorSequence.new(c0, c1), Rotation = 90 }, parent)
end

local function panel(parent, name, x, y, w, h, radius, rim, z, fill: Color3?)
	return Chrome.panel(parent, {
		Name = name,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		Radius = radius,
		Rim = rim,
		BackgroundColor3 = fill or Color3.fromRGB(34, 34, 36),
		ZIndex = z or 1,
	})
end

local function setRim(panelFrame, color: Color3)
	panelFrame:FindFirstChildOfClass("UIStroke").Color = color
end

local function glow(parent, x, y, w, h, radius, color, z)
	local frames = {}
	for i, a in { { 3, 0.55 }, { 8, 0.72 }, { 14, 0.85 }, { 22, 0.93 } } do
		local f = box(parent, `Glow{i}`, x - a[1], y - a[1], w + 2 * a[1], h + 2 * a[1], {
			BackgroundColor3 = color,
			BackgroundTransparency = a[2],
			ZIndex = z,
		})
		corner(f, radius + a[1])
		table.insert(frames, f)
	end
	return frames
end

-- Neutral grey silhouette (no avatar yet / bot / unknown opponent).
local function silhouette(parent)
	local c = Color3.fromRGB(110, 116, 132)
	local head = box(parent, "SilHead", 27, 14, 36, 36, { BackgroundColor3 = c, ZIndex = 2 })
	corner(head, 18)
	local body = box(parent, "SilBody", 11, 56, 68, 60, { BackgroundColor3 = c, ZIndex = 2 })
	corner(body, 30)
end

local function loadAvatar(image, userId: number)
	task.spawn(function()
		local ok, content, ready = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			userId,
			Enum.ThumbnailType.AvatarBust,
			Enum.ThumbnailSize.Size150x150
		)
		if not image.Parent then
			return
		end
		image.Image = if ok
				and ready
				and content ~= ""
			then content
			else `rbxthumb://type=AvatarBust&id={userId}&w=150&h=150`
		image.Visible = true
	end)
end

-- Shell ----------------------------------------------------------------------------------------------------

function ResultsView.new(parent: GuiObject, handlers: { onContinue: () -> (), onSkip: () -> () })
	local self = setmetatable(
		{ _parent = parent, _handlers = handlers, _token = 0, _rise = {}, _counts = {}, _tweens = {} },
		ResultsView
	)
	local root = make("Frame", {
		Name = "Results",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = Z_ROOT,
	}, parent)
	self.Root = root
	local dim = make("TextButton", {
		Name = "Dim",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		-- The Lobby gui uses CoreUISafeInsets (origin below the top bar): oversize the dim so it also covers that strip.
		Position = UDim2.fromOffset(-3000, -3000),
		Size = UDim2.fromOffset(9000, 9000),
		Selectable = false,
		ZIndex = 1,
	}, root)
	dim.Activated:Connect(handlers.onSkip) -- swallows input behind the window; a tap only skips the entrance motion
	local scaled =
		make("Frame", { Name = "Scaled", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, root)
	local uiScale = make("UIScale", { Scale = 1 }, scaled)
	local window = make(
		"Frame",
		{ Name = "Window", BackgroundTransparency = 1, Size = UDim2.fromOffset(WIN_W, WIN_H), ClipsDescendants = false },
		scaled
	)
	self.Scaled, self.Window, self._uiScale = scaled, window, uiScale

	-- Layers (sibling order): rays 1, outline 2, body 3, content groups 4, continue 5, header 6.
	self._rays = make("ImageLabel", {
		Name = "Rays",
		Image = Sprites.RaysBurst.Image,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(WIN_W / 2, -47),
		Size = UDim2.fromOffset(440, 440),
		ImageTransparency = 0.62,
		ZIndex = 1,
	}, window)
	-- The 5 px rim stroke draws outside the body, so the body sits 5 px in and the rim's outer edge is the window box.
	local outline = box(
		window,
		"Outline",
		-1,
		-1,
		WIN_W + 2,
		WIN_H + 2,
		{ BackgroundColor3 = Color3.fromRGB(11, 10, 12), ZIndex = 2 }
	)
	corner(outline, 33)
	local body = box(window, "Body", 5, 5, WIN_W - 10, WIN_H - 10, { BackgroundColor3 = WHITE, ZIndex = 3 })
	corner(body, 27)
	make(
		"UIGradient",
		{ Color = ColorSequence.new(Color3.fromRGB(44, 44, 46), Color3.fromRGB(28, 28, 30)), Rotation = 90 },
		body
	)
	local rim = Chrome.stroke(body, RIM, 5)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(215, 216, 222), Color3.fromRGB(120, 118, 124)),
		Rotation = 90,
	}, rim)

	local skipHit = make("TextButton", {
		Name = "SkipHit",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Size = UDim2.fromOffset(WIN_W, WIN_H),
		ZIndex = 3,
	}, window)
	skipHit.Activated:Connect(handlers.onSkip)

	-- CONTINUE (persistent): art plate + live label + invisible hit box (>= 44 real px, sized in fit).
	local cont = box(window, "continue", CONT.x, CONT.y, CONT.w, CONT.h, { ZIndex = 5 })
	local feel = make("UIScale", { Name = "Feel", Scale = 1 }, cont)
	local plate = make("ImageLabel", {
		Name = "Plate",
		Image = Sprites.ContinueGreen.Image,
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(artW("ContinueGreen", PLATE_H), PLATE_H),
		ZIndex = 1,
	}, cont)
	local sheen = box(cont, "Sheen", 0, 0, artW("ContinueGreen", PLATE_H) - 16, PLATE_H - 14, {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	sheen.AnchorPoint, sheen.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	corner(sheen, 999)
	self._plate, self._sheen, self._feel, self._cont = plate, sheen, feel, cont
	self._label = Parts.text(cont, {
		Name = "Label",
		Text = "CONTINUE",
		TextSize = 46,
		Size = UDim2.fromOffset(CONT.w, CONT.h),
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = 3,
	}, 4)
	local hit = make("TextButton", {
		Name = "Hit",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CONT.w, CONT.h),
		ZIndex = 4,
	}, cont)
	self._hit = hit
	self._refresh = UiKit.wire(hit, function(state: string)
		local c = WHITE
		local sc, shine = 1, 1
		if state == "Pressed" then
			c, sc = Color3.fromRGB(180, 180, 180), 0.97
		elseif state == "Hover" then
			sc, shine = 1.04, 0.86
		end
		plate.ImageColor3, plate.ImageTransparency = c, 0
		self._label.TextColor3 = WHITE
		feel.Scale, sheen.BackgroundTransparency = sc, shine
	end)
	hit.Activated:Connect(handlers.onContinue)
	self._header = box(window, "header", 0, 0, WIN_W, WIN_H, { ZIndex = 6 })
	window.ZIndex = 1
	root.ZIndex = Z_ROOT
	restack(root) -- local values -> absolute (root 34, dim 35, scaled 36, window 37, children 38+)

	-- Fit: one scale for every tier; phones keep the group clear of the 58 px top bar.
	local function fit()
		local size = UiKit.screenSize(parent)
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local phone = size.Y < UiKit.PHONE_H
		local es
		if phone then
			es = math.min(size.X / 1672, (size.Y - TOP_BAR - 16) / GROUP_H) -- 8 px clear above and below
		else
			es = math.min(size.X / 1672, size.Y / 941, 1.5) * SettingsLogic.get("uiScale") / 100
			es = math.min(es, size.X / (WIN_W + 40), size.Y / GROUP_H)
		end
		es = math.max(es, 0.2)
		uiScale.Scale = es
		scaled.Size = UDim2.fromScale(1 / es, 1 / es)
		local dh = size.Y / es
		local top = if phone
			then TOP_BAR / es + ((size.Y - TOP_BAR) / es - GROUP_H) / 2 + OVERHANG
			else math.max(OVERHANG + 4, dh / 2 - 289.5)
		window.Position = UDim2.fromOffset(math.floor(size.X / es / 2 - WIN_W / 2), math.floor(top))
		hit.Size = UDim2.fromOffset(CONT.w, math.max(CONT.h, math.ceil(44 / es)))
		Chrome.restroke(window, es)
		local changed = self._es ~= nil and math.abs(self._es - es) > 0.001
		self._es = es
		if changed and self._v and self.Root.Visible then
			self:Render(self._v, false) -- text sizes depend on the scale (phone boost / floor)
		end
	end
	self._fit = fit
	self._conns = {
		parent:GetAttributeChangedSignal("EmulateSize"):Connect(fit),
		parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit),
		{
			Disconnect = SettingsLogic.onChanged(function(id)
				if id == "uiScale" then
					fit()
				end
			end),
		},
	}
	fit()
	return self
end

function ResultsView:Fit()
	self._fit()
end

-- CONTINUE ----------------------------------------------------------------------------------------------

-- Content builders -----------------------------------------------------------------------------------------

local function group(self, name: string, z: number)
	return box(self.Window, name, 0, 0, WIN_W, WIN_H, { ZIndex = z + self.Window.ZIndex })
end

local function rise(self, inst)
	table.insert(self._rise, { inst = inst, pos = inst.Position })
end

local function plain(n: number): string
	return ResultsLogic.commas(n)
end

-- Animated number: label shows fmt(round(from + (to - from) * ease)) during the timeline, `final` at the end / on skip.
local function countRange(self, label, final: string, from: number, to: number, fmt: (number) -> string)
	table.insert(self._counts, { label = label, final = final, from = from, to = to, fmt = fmt })
end

-- "+1,450" counts up from 0 (other strings stay static).
local function count(self, label, final: string)
	if string.match(final, "^%+?[%d,]+$") then
		local prefix = string.match(final, "^%+") or ""
		countRange(self, label, final, 0, tonumber((string.gsub(final, "[^%d]", ""))) or 0, function(n)
			return prefix .. plain(n)
		end)
	end
end

-- Reward tile (one component per layout): mode "card" = Summary 152x176 (icon, value, chip); "cell" = duel bar 158x62.
local TILE_CARD = { w = 152, h = 176, gap = 14 }
local TILE_CELL = { w = 158, h = 62, gap = 8 }
local CHIP = {
	Coins = { "COINS", Color3.fromRGB(253, 209, 1), Color3.fromRGB(254, 138, 1) },
	Gems = { "GEMS", Color3.fromRGB(237, 78, 253), Color3.fromRGB(139, 6, 252) },
	Xp = { "XP", Color3.fromRGB(4, 221, 254), Color3.fromRGB(1, 116, 251) },
}

local function tileIcon(parent, t, h: number, x: number, y: number, maxW: number)
	local key = if t.Kind == "Coins"
		then "Coin"
		elseif t.Kind == "Gems" then "Gem"
		elseif t.Kind == "Xp" then "XpStar"
		else nil
	if key then
		local w = artW(key, h)
		local sc = math.min(1, maxW / w)
		return art(parent, "Icon", key, h * sc, x + (maxW - w * sc) / 2, y, { ZIndex = 4 })
	end
	local img = t.ArtKey and HudSprites.DieArt[t.ArtKey]
	img = (img and HudSprites.Dice[img]) or (t.DieId and HudSprites.Dice[HudSprites.DieArt[t.DieId] or ""]) or nil
	if img then
		return make("ImageLabel", {
			Name = "Icon",
			Image = img,
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.fromOffset(x + (maxW - h) / 2, y),
			Size = UDim2.fromOffset(h, h),
			ZIndex = 4,
		}, parent)
	end
	return art(parent, "Icon", "DieWhite", h, x + (maxW - artW("DieWhite", h)) / 2, y, { ZIndex = 4 }) -- unknown die art
end

local function chip(parent, name: string, str: string, c0: Color3, c1: Color3, x, y, w, h, size)
	local pill = box(parent, name, x, y, w, h, { BackgroundColor3 = WHITE, ZIndex = 4 })
	corner(pill, 999)
	pillColors(pill, c0, c1)
	Chrome.stroke(pill, Color3.fromRGB(8, 6, 8), 2)
	text(pill, "Label", str, size, 0, 0, w, h, { ZIndex = 5 }, 3)
end

local function buildTile(self, parent, t, x: number, y: number, mode: string)
	local d = if mode == "card" then TILE_CARD else TILE_CELL
	local tile = panel(
		parent,
		`Tile_{t.Kind}`,
		x,
		y,
		d.w,
		d.h,
		if mode == "card" then 18 else 14,
		if mode == "card" then 3 else 2,
		3,
		Color3.fromRGB(40, 40, 40)
	)
	rise(self, tile)
	local drop = t.Kind == "Drop"
	local c0, c1
	local chipText
	if drop then
		local base = Parts.RarityColor[t.Rarity or ""] or Color3.fromRGB(150, 150, 165)
		c0, c1 = base, base:Lerp(Color3.new(0, 0, 0), 0.35)
		chipText = string.upper(t.Rarity or "DIE")
	else
		chipText, c0, c1 = CHIP[t.Kind][1], CHIP[t.Kind][2], CHIP[t.Kind][3]
	end
	if mode == "card" then
		tileIcon(tile, t, 80, 0, 12, d.w)
		local num = text(tile, "Value", t.Text, if drop then 26 else 42, 6, 90, d.w - 12, 42, nil, 3)
		if not drop then
			count(self, num, t.Text)
		end
		chip(tile, "Chip", chipText, c0, c1, 10, 136, d.w - 20, 32, 22)
	else
		tileIcon(tile, t, 46, 6, 8, 46)
		if drop then
			text(tile, "Value", t.Text, 19, 56, 6, d.w - 62, 24, nil, 2)
			chip(tile, "Chip", chipText, c0, c1, 58, 33, d.w - 66, 22, 15)
		else
			local num = text(tile, "Value", t.Text, 34, 56, 8, d.w - 62, 46, nil, 3)
			count(self, num, t.Text)
		end
	end
	return tile
end

-- Tiles in one row of constant tile size: up to 4 centred in `w`, more -> an X-only ScrollingFrame (thin bar, touch drag).
local function tilesRow(self, parent, tiles, x: number, y: number, w: number, mode: string)
	local d = if mode == "card" then TILE_CARD else TILE_CELL
	local n = #tiles
	local total = n * d.w + (n - 1) * d.gap
	if n <= 4 then
		local x0 = x + (w - total) / 2
		for i, t in tiles do
			buildTile(self, parent, t, x0 + (i - 1) * (d.w + d.gap), y, mode)
		end
		return
	end
	-- inner padding keeps the tile rims unclipped; the thin bar sits in its own gutter below the tiles, inside the panel
	local pad, lift = if mode == "card" then 4 else 3, if mode == "card" then 0 else 3
	local sf = make("ScrollingFrame", {
		Name = "TileScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, y - pad - lift),
		Size = UDim2.fromOffset(w, d.h + pad + 10),
		CanvasSize = UDim2.fromOffset(total + 2 * pad, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		VerticalScrollBarInset = Enum.ScrollBarInset.None,
		ScrollBarImageColor3 = Color3.fromRGB(190, 190, 200),
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		ZIndex = 3,
	}, parent)
	for i, t in tiles do
		buildTile(self, sf, t, pad + (i - 1) * (d.w + d.gap), pad, mode)
	end
end

local function trophy(parent, h: number, x: number, y: number)
	return art(parent, "Trophy", "Trophy", h, x, y)
end

-- Summary: stats strip (3 -> 2 -> 1 cells) + RUN REWARDS (4 -> 3 tiles).
function ResultsView:_summary(v)
	local cells = {}
	if v.Wave then
		table.insert(cells, { "wave", "WAVE REACHED", v.Wave, "ShieldCube", 64 })
	end
	if v.RunTime then
		table.insert(cells, { "time", "RUN TIME", v.RunTime, "Stopwatch", 60 })
	end
	if v.Kills then
		table.insert(cells, { "kills", "ENEMIES", v.Kills, "Skull", 56 })
	end
	if #cells > 0 then
		local g = group(self, "stats", 4)
		local bar = panel(g, "Bar", GUT, 114, CW, 100, 24, 3, 1)
		rise(self, bar)
		local cw = CW / #cells
		for i, c in cells do
			local cx = GUT + (i - 1) * cw
			if i > 1 then
				local d = box(
					g,
					`Divider{i - 1}`,
					cx - 1,
					125,
					3,
					78,
					{ BackgroundColor3 = Color3.fromRGB(205, 205, 210), ZIndex = 2 }
				)
				corner(d, 2)
			end
			local iconH = c[5]
			local iconW = artW(c[4], iconH)
			local textW = math.min(cw - iconW - 12 - 36, 170) -- 18 px clear of the dividers
			local startX = cx + (cw - (iconW + 12 + textW)) / 2
			art(g, `{c[1]}_icon`, c[4], iconH, startX, 114 + (100 - iconH) / 2, nil)
			local tx = startX + iconW + 12
			text(g, `{c[1]}_label`, c[2], 19, tx, 128, textW, 30, { TextColor3 = SOFT }, 3)
			local val = text(g, `{c[1]}_value`, c[3], 48, tx, 158, textW, 50, nil, 3)
			val.TextColor3 = WHITE
			gold(val)
			count(self, val, c[3])
		end
	end

	if #v.Tiles > 0 then
		local g = group(self, "rewards", 4)
		local fy, fh = 232, 262
		glow(g, GUT, fy, CW, fh, 28, ORANGE, 1)
		local frame = panel(g, "Frame", GUT, fy, CW, fh, 28, 5, 2, Color3.fromRGB(36, 36, 36))
		setRim(frame, ORANGE)
		for _, side in { -1, 1 } do
			local gl =
				box(g, "Glint", WIN_W / 2 + side * 160 - 55, fy + 28, 110, 3, { BackgroundColor3 = ORANGE, ZIndex = 3 })
			make("UIGradient", {
				Transparency = NumberSequence.new(
					if side < 0
						then { NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }
						else { NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }
				),
			}, gl)
		end
		text(g, "Title", "RUN REWARDS", 38, GUT, fy + 8, CW, 46, nil, 4)
		tilesRow(self, g, v.Tiles, GUT + 16, fy + 62, CW - 32, "card")
	end
end

local function playerCard(
	self,
	g,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	who,
	winner: boolean,
	badgeLeft: boolean
)
	local card = panel(g, name, x, y, w, h, 22, 3, 3, Color3.fromRGB(32, 32, 34))
	if winner then
		for _, gf in glow(g, x, y, w, h, 22, Color3.fromRGB(255, 160, 0), 2) do
			rise(self, gf)
		end
		setRim(card, Color3.fromRGB(248, 216, 40))
		card:FindFirstChildOfClass("UIStroke"):SetAttribute("Rim", 4)
		card:FindFirstChildOfClass("UIStroke").Thickness = 4
	end
	rise(self, card)
	local av = box(
		card,
		"Avatar",
		8,
		(h - 90) / 2,
		90,
		90,
		{ BackgroundColor3 = Color3.fromRGB(20, 20, 24), ClipsDescendants = true, ZIndex = 4 }
	)
	corner(av, 16)
	local img = make("ImageLabel", {
		Name = "Thumb",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		ZIndex = 5,
	}, av)
	if who.UserId and not who.Silhouette then
		loadAvatar(img, who.UserId)
	end
	if not (who.UserId and not who.Silhouette) then
		silhouette(av)
	end
	local colX, colW = 104, w - 104 - 8
	text(
		card,
		"Name",
		who.Name or "Player",
		32,
		colX,
		14,
		colW,
		40,
		{ TextTruncate = Enum.TextTruncate.AtEnd, Floor = math.max(14, floorSize) },
		3
	)
	if who.DRText then
		local size = Parts.fitSize(who.DRText, colW - 44, 30, 12)
		local tw = Parts.measure(who.DRText, size)
		local gx = colX + (colW - (38 + 6 + tw)) / 2
		trophy(card, 34, gx, 59)
		gold(
			text(card, "DR", who.DRText, 30, gx + 44, 54, tw + 6, 42, { TextXAlignment = Enum.TextXAlignment.Left }, 2)
		)
	end
	if winner then
		local tagW = Parts.measure("WINNER!", 19) + 28
		local gw = 46 + tagW - 8
		local gx = if badgeLeft then x + 14 else x + w - 14 - gw
		local badge = box(g, "WinnerBadge", gx, y - 30, gw, 34, { ZIndex = 6 })
		art(badge, "Crown", "Crown", 30, 0, 0, { ZIndex = 2 })
		local tag = box(badge, "Tag", 38, 3, tagW, 28, { BackgroundColor3 = Color3.fromRGB(252, 204, 4), ZIndex = 3 })
		corner(tag, 14)
		Chrome.stroke(tag, Color3.fromRGB(26, 20, 4), 2)
		local t =
			text(tag, "Label", "WINNER!", 19, 0, 0, tagW, 28, { TextColor3 = Color3.fromRGB(26, 22, 6), ZIndex = 4 }, 0)
		t.UIStroke.Enabled = false
		rise(self, badge)
	end
end

-- Duel (Victory / Defeat): cards, delta + total, MATCH REWARDS (coin cell), level bar.
function ResultsView:_duel(v)
	local d = v.Duel
	local hasLevel = v.Level ~= nil
	local s1, s2, s3 = 0, 0, 0
	if not hasLevel then -- no level bar: spread the freed 59 px
		s1, s2, s3 = 12, 30, 50
	end

	local pg = group(self, "players", 4)
	local cy = 115 + s1
	local win = v.Self.Winner
	playerCard(
		self,
		pg,
		"Card_Self",
		GUT,
		cy,
		308,
		105,
		{ Name = v.Self.Name or "You", UserId = v.Self.UserId, DRText = d.DRText },
		win,
		true
	)
	local opp = v.Opponent or { Name = "Opponent" }
	playerCard(self, pg, "Card_Opponent", WIN_W - GUT - 308, cy, 308, 105, opp, opp.Winner == true, false)
	text(pg, "VS", "VS", 46, WIN_W / 2 - 30, cy + 26, 60, 52, { Rotation = -6 }, 4)

	-- Delta + total.
	local tg = group(self, "trophies", 4)
	local ty = 238 + s2
	local bar = panel(tg, "Bar", GUT, ty, CW, 90, 24, 3, 1)
	rise(self, bar)
	local kind = d.DeltaKind
	local main = if kind == "Gain"
		then Color3.fromRGB(240, 216, 0)
		elseif kind == "Loss" then Color3.fromRGB(248, 56, 48)
		else Color3.fromRGB(200, 190, 150)
	local fill = if kind == "Gain"
		then Color3.fromRGB(48, 32, 16)
		elseif kind == "Loss" then Color3.fromRGB(48, 8, 8)
		else Color3.fromRGB(40, 38, 30)
	local half = CW / 2
	local info = d.InfoLine
	local py = if info then 3 else 16
	local pill = box(tg, "DeltaPill", GUT + half / 2 - 117, ty + py, 234, 58, { BackgroundColor3 = fill, ZIndex = 2 })
	corner(pill, 28)
	local pst = Chrome.stroke(pill, main, 3)
	pst.Name = "Rim"
	local str = if d.NoDR then "NO DR" else (string.gsub(d.DeltaText, " DR$", ""))
	local size = Parts.fitSize(str, 130, 50, 18)
	local tw = Parts.measure(str, size)
	local gx = (234 - (44 + 8 + tw)) / 2
	trophy(pill, 40, gx, 9)
	text(
		pill,
		"Delta",
		str,
		50,
		gx + 52,
		3,
		tw + 8,
		52,
		{ TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = main },
		3
	)
	if info then
		text(tg, "InfoLine", info, 16, GUT + 10, ty + 65, half - 20, 18, { TextColor3 = SOFT }, 2)
	end
	local div = box(
		tg,
		"Divider",
		GUT + half - 1,
		ty + 12,
		3,
		66,
		{ BackgroundColor3 = Color3.fromRGB(240, 220, 20), ZIndex = 2 }
	)
	corner(div, 2)
	text(tg, "TotalLabel", "TOTAL TROPHIES", 20, GUT + half, ty + 6, half, 24, nil, 3)
	local tsize = Parts.fitSize(d.DRText, half - 100, 46, 14)
	local ttw = Parts.measure(d.DRText, tsize)
	local tx = GUT + half + (half - (44 + 8 + ttw)) / 2
	trophy(tg, 40, tx, ty + 36)
	local total = text(
		tg,
		"TotalValue",
		d.DRText,
		46,
		tx + 52,
		ty + 32,
		ttw + 8,
		54,
		{ TextXAlignment = Enum.TextXAlignment.Left },
		3
	)
	gold(total)
	if d.TotalFrom and d.TotalTo then
		countRange(self, total, d.DRText, d.TotalFrom, d.TotalTo, function(n)
			return `{plain(n)} DR`
		end)
	end

	-- MATCH REWARDS: the same tiles as the Summary, in a compact cell.
	if #v.Tiles > 0 then
		local rg = group(self, "rewards", 4)
		local ry = 362 + s3
		local rbar = panel(rg, "Bar", GUT, ry, CW, 78, 22, 3, 1)
		rise(self, rbar)
		local label = "MATCH REWARDS"
		local lw = Parts.measure(label, 24) + 56
		local lp = box(rg, "TitlePill", WIN_W / 2 - lw / 2, ry - 26, lw, 36, { BackgroundColor3 = DARK, ZIndex = 3 })
		corner(lp, 18)
		Chrome.stroke(lp, RIM, 2)
		text(lp, "Label", label, 24, 0, 0, lw, 36, nil, 3)
		tilesRow(self, rg, v.Tiles, GUT + 8, ry + 10, CW - 16, "cell")
	end

	-- Level bar.
	if hasLevel then
		local lg = group(self, "level", 4)
		local ly = 456
		local lbar = panel(lg, "Bar", GUT, ly, CW, 43, 21, 3, 1)
		rise(self, lbar)
		self._lvLabel = text(
			lg,
			"LvLabel",
			v.Level.LevelText,
			27,
			GUT + 14,
			ly + 4,
			96,
			32,
			{ TextXAlignment = Enum.TextXAlignment.Left },
			3
		)
		local track, f = Chrome.track(lg, {
			Name = "Track",
			Position = UDim2.fromOffset(GUT + 116, ly + 3),
			Size = UDim2.fromOffset(CW - 116 - 10, 37),
			ZIndex = 2,
		}, Color3.fromRGB(190, 40, 248))
		f.Size = UDim2.fromScale(v.Level.Frac, 1)
		self._level = { fill = f, v = v.Level }
		self._xpText = text(track, "XpText", v.Level.Text, 26, 0, 0, CW - 126, 37, { ZIndex = 5 }, 3)
	end
end

-- Header: rays, ribbon, emblem, laurels, pill, dice.
function ResultsView:_buildHeader(v)
	local kind = if v.Draw then "Draw" else v.Kind
	local th = THEME[kind]
	local h = self._header
	for _, c in h:GetChildren() do
		c:Destroy()
	end
	self._rays.ImageColor3, self._rays.ImageTransparency = th.Rays, th.Alpha
	local rh = 96
	local rw = artW("RibbonNeutral", rh)
	local ribbon =
		art(h, "Ribbon", "RibbonNeutral", rh, (WIN_W - rw) / 2, BASELINE - rh, { ImageColor3 = th.Ribbon, ZIndex = 2 })
	self._ribbon = ribbon
	text(
		h,
		"Title",
		(if kind == "Draw" then "DRAW" else v.Title) .. (if kind == "Victory" then "!" else ""),
		58,
		(WIN_W - rw) / 2 + 40,
		BASELINE - rh + 10,
		rw - 80,
		70,
		nil,
		4
	)
	local key = if kind == "Summary"
		then "CrestShieldDie"
		elseif kind == "Victory" or kind == "Draw" then "TrophyGold"
		else "TrophyRed"
	local ew = artW(key, EMBLEM_H)
	local emblem = art(h, "Emblem", key, EMBLEM_H, (WIN_W - ew) / 2, -47 - EMBLEM_H / 2, { ZIndex = 5 })
	self._emblem, self._ribbonY, self._emblemPos = emblem, BASELINE - rh, emblem.Position
	local lh = 64
	local lw = artW("LaurelL", lh)
	art(h, "LaurelL", "LaurelL", lh, WIN_W / 2 - ew / 2 - 40, -52, { ImageColor3 = th.Laurel, ZIndex = 3 })
	art(h, "LaurelR", "LaurelR", lh, WIN_W / 2 + ew / 2 - lw + 40, -52, { ImageColor3 = th.Laurel, ZIndex = 3 })
	for _, die in DICE[kind] or {} do
		art(h, "Die", die[1], die[4], die[2], die[3], { Rotation = die[5], ZIndex = 3 })
	end
	local pillText = if kind == "Summary" then v.ModeText else "MATCH RESULT"
	local pw = math.max(150, Parts.measure(pillText, 22) + 56)
	local pill = box(h, "ModePill", (WIN_W - pw) / 2, 57, pw, 38, { BackgroundColor3 = DARK, ZIndex = 6 })
	corner(pill, 19)
	Chrome.stroke(pill, RIM, 2)
	text(pill, "Label", pillText, 22, 0, 0, pw, 38, nil, 2)
	if v.OutcomeLine then
		text(h, "OutcomeLine", v.OutcomeLine, 15, GUT, 97, CW, 16, { TextColor3 = SOFT }, 2)
	end
end

-- Render ---------------------------------------------------------------------------------------------------

function ResultsView:Render(v, animate: boolean)
	self:Skip()
	self._v = v
	local es = self._es or 1
	local phone = UiKit.screenSize(self._parent).Y < UiKit.PHONE_H
	boost = if phone then math.clamp(9 / (15 * es), 1, 1.35) else 1 -- small labels: ~9 real px on phones where the width allows
	floorSize = if phone then math.max(11, math.ceil(8 / es)) else 11
	for _, name in GROUPS do
		local g = self.Window:FindFirstChild(name)
		if g then
			g:Destroy()
		end
	end
	table.clear(self._rise)
	table.clear(self._counts)
	self._level, self._lvLabel, self._xpText = nil, nil, nil
	self:_buildHeader(v)
	restack(self._header)
	if v.Kind == "Summary" then
		self:_summary(v)
	else
		self:_duel(v)
	end
	for _, name in GROUPS do
		local g = self.Window:FindFirstChild(name)
		if g then
			restack(g)
		end
	end
	self._refresh()
	if animate and not SettingsLogic.get("reducedMotion") then
		self:_animate()
	end
end

function ResultsView:Skip()
	self._token += 1
	for _, tw in self._tweens do
		tw:Cancel()
	end
	table.clear(self._tweens)
	for _, r in self._rise do
		if r.inst.Parent then
			r.inst.Position = r.pos
		end
	end
	for _, c in self._counts do
		if c.label.Parent then
			c.label.Text = c.final
		end
	end
	local lv = self._level
	if lv and lv.fill.Parent then
		lv.fill.Size = UDim2.fromScale(lv.v.Frac, 1)
		self._xpText.Text, self._lvLabel.Text = lv.v.Text, lv.v.LevelText
	end
	if self._ribbon and self._ribbon.Parent then
		self._ribbon.Position = UDim2.fromOffset(self._ribbon.Position.X.Offset, self._ribbonY)
		self._emblem.Position = self._emblemPos
	end
end

function ResultsView:_animate()
	local token = self._token
	local info = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local function slide(inst, from: UDim2, to: UDim2, delay: number)
		inst.Position = from
		task.delay(delay, function()
			if self._token == token and inst.Parent then
				local tw = TweenService:Create(inst, info, { Position = to })
				table.insert(self._tweens, tw)
				tw:Play()
			end
		end)
	end
	local rp = self._ribbon.Position
	slide(self._ribbon, rp - UDim2.fromOffset(0, 28), rp, 0)
	local ep = self._emblem.Position
	slide(self._emblem, ep - UDim2.fromOffset(0, 24), ep, 0.08)
	for i, r in self._rise do
		slide(r.inst, r.pos + UDim2.fromOffset(0, 14), r.pos, 0.1 + 0.06 * i)
	end
	-- Level bar: fills From -> To through each level up (segments), cosmetic; the final text is always the server's.
	local lv = self._level
	local segs, total = nil, 0
	if lv and lv.v.From and lv.v.To then
		segs = {}
		local ups = math.max(0, lv.v.To.Level - lv.v.From.Level)
		for k = 0, ups do
			local a = if k == 0 then lv.v.From.Frac else 0
			local b = if k == ups then lv.v.To.Frac else 1
			table.insert(segs, { a = a, b = b, level = lv.v.From.Level + k })
			total += math.max(b - a, 0)
		end
	end
	local function setLevel(e: number)
		if not segs or not lv.fill.Parent then
			return
		end
		local pos = e * total
		local seg = segs[#segs]
		local frac = seg.b
		for _, sg in segs do
			local len = math.max(sg.b - sg.a, 0)
			if pos <= len or sg == segs[#segs] then
				seg, frac = sg, if len > 0 then sg.a + math.min(pos, len) / len * (sg.b - sg.a) else sg.b
				break
			end
			pos -= len
		end
		lv.fill.Size = UDim2.fromScale(frac, 1)
		self._lvLabel.Text = `Lv. {seg.level}`
		-- only the final level's cap is known: earlier levels show a percentage, never a wrong "x / y"
		self._xpText.Text = if seg.level == lv.v.Level
			then `{plain(math.floor(frac * lv.v.XpNeed + 0.5))} / {plain(lv.v.XpNeed)} XP`
			else `{math.floor(frac * 100)}%`
	end
	local function setCounts(e: number)
		for _, c in self._counts do
			if c.label.Parent then
				c.label.Text = c.fmt(math.floor(c.from + (c.to - c.from) * e + 0.5))
			end
		end
	end
	setCounts(0)
	setLevel(0)
	task.spawn(function()
		local t0 = os.clock()
		while self._token == token do
			local a = math.min((os.clock() - t0) / DUR, 1)
			local e = 1 - (1 - a) ^ 3
			setCounts(e)
			setLevel(e)
			if a >= 1 then
				break
			end
			task.wait()
		end
		if self._token == token then
			self:Skip() -- exact final values
		end
	end)
end

function ResultsView:Show()
	self._fit()
	self.Root.Visible = true
end

function ResultsView:Hide()
	self:Skip()
	self.Root.Visible = false
end

function ResultsView:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	self._token += 1
	self.Root:Destroy()
end

return ResultsView
