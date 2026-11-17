-- Quest Log widgets, all code-drawn (plan D1) with colours sampled from Assets/UI/new/quests menu/*.png. Design px under the shell's UIScale.
-- Kit.minHit = design px that make 44 real px (QuestLog sets it on every layout); controls pad their hit boxes with it.
-- Kit.card(parent, props, o) -> button, setSelected(on)   clickable strip: hover / pressed fill, gold selected rim, gamepad focus rim
-- Kit.bar(parent, props, color, textSize) -> { Frame, Set(pct, text, color?) }   progress bar (track + gradient fill + centred text)
-- Kit.scrollbar(root, scroll, z) -> { Track, Layout(h, w, rightInset, top?) }   dark track + purple thumb, driven by the scroll
-- Kit.chip(parent, text, w, h, props) -> label chip; Kit.timer(parent, props) -> { Frame, Set(prefix, value) }; Kit.chevron(parent, props)
-- Kit.setIcon(inst, ref)  ref = QuestSprites key, sprite record or raw asset id; always ScaleType.Fit (native aspect, never stretched)
-- Kit.dieName(name) -> "<name> Dice"

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Bag.Parts)
local Chrome = require(script.Parent.Parent.Bag.Chrome)
local Q = require(script.Parent.QuestSprites)

local make = UiKit.make
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)

local Kit = {
	minHit = 44,
	Gold = Color3.fromRGB(255, 191, 51), -- selected rim / ready slot
	Green = Color3.fromRGB(62, 232, 30), -- complete bar
	Yellow = Color3.fromRGB(254, 224, 20), -- progress bar
	Purple = Color3.fromRGB(158, 37, 254), -- scrollbar thumb
	CoinText = Color3.fromRGB(251, 243, 137),
	Soft = Color3.fromRGB(203, 203, 202), -- descriptions
	RowFill = Color3.fromRGB(50, 50, 52),
	PanelFill = Color3.fromRGB(46, 45, 48),
	DetailFill = Color3.fromRGB(31, 32, 34),
	ChipFill = Color3.fromRGB(46, 46, 50),
}

-- Our font renders ~25% smaller than the mockups' at the same TextSize: every size below is authored in mockup terms and scaled once here.
Kit.S = 1.3
local function sc(n: number): number
	return math.floor(n * Kit.S + 0.5)
end
function Kit.text(parent, props, stroke: number?)
	props.TextSize = sc(props.TextSize)
	return Parts.text(parent, props, stroke)
end
function Kit.fitSize(str: string, availW: number, maxSize: number, minSize: number): number
	return Parts.fitSize(str, availW, sc(maxSize), sc(minSize))
end
function Kit.fit(label, availW: number, maxSize: number, minSize: number)
	label.TextSize = Kit.fitSize(label.Text, availW, maxSize, minSize)
end
function Kit.measure(str: string, size: number): number
	return Parts.measure(str, sc(size))
end

local function corner(inst, r: number)
	make("UICorner", { CornerRadius = UDim.new(0, r) }, inst)
end

local focusRim
local function focus()
	if not focusRim then
		focusRim = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
		make("UIStroke", { Color = Kit.Gold, Thickness = 3 }, focusRim)
	end
	return focusRim
end

function Kit.dieName(name: string): string
	return if string.match(name, "Dice$") then name else name .. " Dice"
end

function Kit.setIcon(inst, ref)
	local rec = if type(ref) == "table" then ref else Q[ref]
	inst.Image = if rec then rec.Image else (ref or "")
	inst.ScaleType = Enum.ScaleType.Fit
end

function Kit.card(parent, props, o)
	o = o or {}
	local base = o.Fill or Kit.RowFill
	local rim, rimT = o.RimColor or Chrome.PanelRim, o.Rim or 2
	props.BackgroundColor3 = base
	props.BorderSizePixel = 0
	props.Text = ""
	props.AutoButtonColor = false
	props.ZIndex = props.ZIndex or parent.ZIndex + 1
	local btn = make("TextButton", props, parent)
	corner(btn, o.Radius or 10)
	local stroke = Chrome.stroke(btn, rim, rimT)
	btn.SelectionImageObject = focus()
	local selected, state = false, "Normal"
	local function paint()
		btn.BackgroundColor3 = if state == "Pressed"
			then base:Lerp(BLACK, 0.18)
			elseif state == "Hover" then base:Lerp(WHITE, 0.08)
			else base
		local t = if selected then rimT + 1 else rimT
		stroke.Color = if selected then Kit.Gold else rim
		stroke.Thickness = t
		stroke:SetAttribute("Rim", t)
	end
	UiKit.wire(btn, function(s)
		state = s
		paint()
	end)
	return btn, function(on: boolean)
		selected = on
		paint()
	end
end

local function tint(fill, c: Color3)
	fill.UIGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c:Lerp(WHITE, 0.2)),
		ColorSequenceKeypoint.new(0.5, c),
		ColorSequenceKeypoint.new(1, c:Lerp(BLACK, 0.08)),
	})
end

function Kit.bar(parent, props, color: Color3?, textSize: number)
	local z = props.ZIndex or parent.ZIndex + 1
	props.ZIndex = z
	local track, fill = Chrome.track(parent, props, color or Kit.Yellow)
	local label = Kit.text(track, {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -8, 1, 0),
		TextSize = textSize,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = z + 3,
	}, 2)
	local bar = { Frame = track }
	function bar:Set(pct: number, text: string, c: Color3?)
		fill.Size = UDim2.fromScale(math.clamp(pct, 0, 1), 1)
		fill.Visible = pct > 0
		tint(fill, c or color or Kit.Yellow)
		label.Text = text
		label.TextSize = math.min(
			Kit.fitSize(text, math.max(10, track.Size.X.Offset - 8), textSize, 9),
			math.max(9, track.Size.Y.Offset - 2) -- the line must fit the bar's height too
		)
	end
	return bar
end

function Kit.scrollbar(root, scroll, z: number)
	local track = make("Frame", {
		Name = "ScrollTrack",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Chrome.TrackFill,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = z,
	}, root)
	corner(track, 999)
	Chrome.stroke(track, Chrome.PanelRim, 1)
	local thumb = make("Frame", {
		Name = "Thumb",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = z + 1,
	}, track)
	corner(thumb, 999)
	make("UIGradient", {
		Color = ColorSequence.new(Kit.Purple:Lerp(WHITE, 0.3), Kit.Purple:Lerp(BLACK, 0.15)),
		Rotation = 0,
	}, thumb)
	local visibleH, barW = 0, 12
	local api = { Track = track }
	local function update()
		local win, canvas = scroll.AbsoluteWindowSize.Y, math.max(1, scroll.AbsoluteCanvasSize.Y)
		local maxY = math.max(0, canvas - win)
		track.Visible = maxY > 1 and visibleH > 0
		local h = math.clamp(math.floor(visibleH * win / canvas), 40, math.max(40, visibleH))
		thumb.Size = UDim2.fromOffset(math.max(4, barW - 3), h)
		thumb.Position =
			UDim2.new(0.5, 0, 0, math.floor((visibleH - h) * (if maxY > 0 then scroll.CanvasPosition.Y / maxY else 0)))
	end
	function api.Layout(h: number, w: number, rightInset: number, top: number?)
		visibleH, barW = h, w
		track.Size = UDim2.fromOffset(w, h)
		track.Position = UDim2.new(1, -rightInset, 0, top or 0)
		update()
	end
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(update)
	scroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(update)
	scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(update)
	return api
end

-- Dark label chip (OBJECTIVE, PROGRESS, REWARDS, NEXT REWARDS ...) of w x h, centred text.
function Kit.chip(parent, text: string, w: number, h: number, props)
	props = props or {}
	props.Size = UDim2.fromOffset(w, h)
	props.Radius, props.Rim = 999, 2
	props.BackgroundColor3 = Kit.ChipFill
	props.NoGradient = true
	local chip = Chrome.panel(parent, props)
	local label = Parts.text(chip, {
		Name = "Label",
		Text = text,
		TextSize = Kit.fitSize(text, w - 16, math.floor(h * 0.74), 10),
		Size = UDim2.fromScale(1, 1),
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = chip.ZIndex + 1,
	}, 2)
	return chip, label
end

-- "Resets in: 12h 34m" pill: field body, stopwatch icon, the value in gold. timer:Set(prefix, value).
function Kit.timer(parent, props)
	local w, h = props.Size.X.Offset, props.Size.Y.Offset
	props.BackgroundTransparency = 1 -- plain text + clock (mockup: no bordered pill)
	local pill = make("Frame", props, parent)
	local z = pill.ZIndex
	local sw = make("ImageLabel", {
		Name = "Stopwatch",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(6, h / 2),
		Size = UDim2.fromOffset(h - 8, h - 8),
		ZIndex = z + 1,
	}, pill)
	Kit.setIcon(sw, "QuestStopwatch")
	local avail = w - h - 8
	local label = Parts.text(pill, {
		Name = "Resets",
		RichText = true,
		TextSize = math.floor(h * 0.6 * Kit.S),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(h, h / 2),
		Size = UDim2.fromOffset(avail, h),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = z + 1,
	}, 2)
	local timer = { Frame = pill, Label = label }
	function timer:Set(prefix: string, value: string)
		label.Text = `{prefix} <font color="#FCD51A">{value}</font>`
		label.TextSize = Kit.fitSize(`{prefix} {value}`, avail, math.floor(h * 0.6), 10)
	end
	return timer
end

-- Down chevron (two rounded bars at +-45 degrees) centred in a box of `size` at props.Position.
function Kit.chevron(parent, props)
	local size = props.Size.X.Offset
	local box = make("Frame", {
		Name = "Chevron",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.Position,
		Size = props.Size,
		ZIndex = props.ZIndex,
	}, parent)
	local len, thick = size * 0.62, math.max(3, size * 0.17)
	for i, dir in { -1, 1 } do
		local arm = make("Frame", {
			Name = "Arm" .. i,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + dir * 0.17, 0.42),
			Size = UDim2.fromOffset(len, thick),
			Rotation = -dir * 45,
			ZIndex = props.ZIndex,
		}, box)
		corner(arm, 999)
	end
	return box
end

-- White magnifier (ring + handle) in a box of props.Size at props.Position (left-centre anchored).
function Kit.magnifier(parent, props)
	local s = props.Size.X.Offset
	local box = make("Frame", {
		Name = "Magnifier",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = props.Position,
		Size = props.Size,
		ZIndex = props.ZIndex,
	}, parent)
	local ring = make("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(s * 0.66, s * 0.66),
		ZIndex = props.ZIndex,
	}, box)
	corner(ring, 999)
	make(
		"UIStroke",
		{ Color = WHITE, Thickness = math.max(2, s * 0.11), ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
		ring
	)
	local handle = make("Frame", {
		Name = "Handle",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(s * 0.8, s * 0.8),
		Size = UDim2.fromOffset(s * 0.38, math.max(3, s * 0.12)),
		Rotation = 45,
		ZIndex = props.ZIndex,
	}, box)
	corner(handle, 999)
	return box
end

-- Thin gold rule with a diamond in the middle (detail panel separators), w wide, centred at props.Position.
function Kit.rule(parent, props)
	local w = props.Size.X.Offset
	local rule = make("Frame", {
		Name = props.Name or "Rule",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.Position,
		Size = UDim2.fromOffset(w, 8),
		ZIndex = props.ZIndex,
	}, parent)
	local gold = Color3.fromRGB(176, 140, 52)
	make("Frame", {
		Name = "Line",
		BackgroundColor3 = gold,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 2),
		ZIndex = props.ZIndex,
	}, rule)
	make("Frame", {
		Name = "Diamond",
		BackgroundColor3 = Color3.fromRGB(235, 190, 60),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(7, 7),
		Rotation = 45,
		ZIndex = props.ZIndex + 1,
	}, rule)
	return rule
end

return Kit
