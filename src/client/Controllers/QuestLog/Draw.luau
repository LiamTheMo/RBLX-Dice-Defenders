-- Quest Log drawing helpers shared by Toolbar, Quests and Detail: Parts.inkBox only knows BagSprites keys, these take records.
-- Design px under the shell's UIScale. Everything is sized by the sprite's visible ink (Ink rect), centred by its ink.

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Bag.Parts)
local Bag = require(script.Parent.Parent.Bag.BagSprites)
local Q = require(script.Parent.QuestSprites)

local make = UiKit.make

local Draw = { Q = Q, Bag = Bag }

local function round(n: number): number
	return math.floor(n + 0.5)
end

function Draw.img(parent, props, class)
	props.BackgroundTransparency = 1
	props.ZIndex = props.ZIndex or parent.ZIndex + 1
	return make(class or "ImageLabel", props, parent)
end

-- Ink size that fits inside maxW x maxH at the sprite's own aspect.
function Draw.fitIn(rec, maxW: number, maxH: number): (number, number)
	local s = math.min(maxW / rec.Ink.Width, maxH / rec.Ink.Height)
	return rec.Ink.Width * s, rec.Ink.Height * s
end

-- Draws `rec` so its visible ink is inkW x inkH centred at (cx, cy) in the parent. Sliced sprites keep their margins at
-- slice scale k (default inkH / ink height), reduced when the box is too small for the caps; plain ones stretch to the ink.
function Draw.apply(inst, rec, cx: number, cy: number, inkW: number, inkH: number, k: number?)
	local ink, size = rec.Ink, rec.Size
	local sx, sy, w, h
	if rec.Slice then
		local sl = rec.Slice
		k = k or inkH / ink.Height
		local capX = sl.Min.X + size.X - sl.Max.X - (size.X - ink.Width)
		local capY = sl.Min.Y + size.Y - sl.Max.Y - (size.Y - ink.Height)
		if capX > 0 then
			k = math.min(k, inkW / capX)
		end
		if capY > 0 then
			k = math.min(k, inkH / capY)
		end
		sx, sy = k, k
		w, h = inkW + (size.X - ink.Width) * k, inkH + (size.Y - ink.Height) * k
		Parts.skin(inst, rec, k)
	else
		sx, sy = inkW / ink.Width, inkH / ink.Height
		w, h = size.X * sx, size.Y * sy
		Parts.skin(inst, rec, nil)
		inst.ScaleType = Enum.ScaleType.Stretch
	end
	inst.AnchorPoint = Vector2.new(0.5, 0.5)
	inst.Size = UDim2.fromOffset(round(w), round(h))
	inst.Position = UDim2.fromOffset(
		round(cx + (size.X / 2 - (ink.Min.X + ink.Max.X) / 2) * sx),
		round(cy + (size.Y / 2 - (ink.Min.Y + ink.Max.Y) / 2) * sy)
	)
	return inst
end

-- Title centre y for a DetailRibbon of ink height inkH drawn at cy: the middle of its front band (sprite row 41, above the ink
-- centre because the folded tails hang lower), less the ~0.05 x TextSize that caps sit below their text box's centre.
local RIBBON_BAND_Y = 41
function Draw.ribbonTextY(cy: number, inkH: number, textSize: number): number
	local ink = Q.DetailRibbon.Ink
	return cy + (RIBBON_BAND_Y - (ink.Min.Y + ink.Max.Y) / 2) / ink.Height * inkH - 0.05 * textSize
end

-- Scrollbar thumb (purple pill, vertical caps sliced, centre column only) of ink width trackW - 5, height h, top y in the track.
function Draw.thumb(inst, trackW: number, h: number, y: number)
	local w = trackW - 5
	Draw.apply(inst, Q.ScrollThumbPurple, trackW / 2, y + h / 2, w, h, w / Q.ScrollThumbPurple.Ink.Width)
end

-- Progress bar: Track + FillGold (also when complete) with "x / y" centred over the whole bar.
-- bar = Draw.bar(parent, W, H, z); bar.Frame is W x H (the ink); bar:Set(pct 0..1, text, complete).
function Draw.bar(parent, name: string, W: number, H: number, z: number, textSize: number?)
	local frame = Draw.img(parent, { Name = name, Size = UDim2.fromOffset(W, H), ZIndex = z }, "Frame")
	local track = Draw.img(frame, { Name = "Track", ZIndex = z + 1 })
	Draw.apply(track, Q.Track, W / 2, H / 2, W, H)
	local fill = Draw.img(frame, { Name = "Fill", ZIndex = z + 2 })
	local label = Parts.text(frame, {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -12, 1, 0),
		TextSize = textSize or math.max(12, math.floor(H * 0.55)),
		ZIndex = z + 3,
	}, 2)
	local base = label.TextSize
	local bar = { Frame = frame }
	function bar:Set(pct: number, text: string, _complete: boolean)
		local inset = 3
		local fw = round((W - 2 * inset) * math.clamp(pct, 0, 1))
		fill.Visible = fw > 0
		if fw > 0 then
			Draw.apply(fill, Q.FillGold, inset + fw / 2, H / 2, fw, H - 2 * inset) -- complete bars keep the same yellow fill
		end
		label.Text = text
		Parts.fit(label, W - 12, base, 11)
	end
	return bar
end

-- "Resets in" style timer pill (Search pill + glowing stopwatch + rich label), `w` ink wide and 40 tall, left edge x, centre y.
-- t = Draw.timerPill(parent, x, y, w, z); t.Group is the pill's frame (z = its ZIndex); t:Set("Resets in:", "13d 4h") shows the
-- value in gold, shrunk to fit; t.Avail is the label width.
local GOLD_HEX = "#FCD51A"
function Draw.timerPill(parent, x: number, y: number, w: number, z: number)
	local group = Draw.img(
		parent,
		{ Name = "Reset", Position = UDim2.fromOffset(x, y - 20), Size = UDim2.fromOffset(w, 40), ZIndex = z },
		"Frame"
	)
	local pill = Draw.img(group, { Name = "Pill" })
	Draw.apply(pill, Bag.Search, w / 2, 20, w, 40)
	local halo = Draw.img(group, { -- ref: the clock glows bright gold
		Name = "StopwatchGlow",
		Image = Q.GlowRadial.Image,
		ImageColor3 = Color3.fromRGB(255, 190, 40),
		ImageTransparency = 0.35,
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(22, 20),
		ZIndex = pill.ZIndex + 1,
	})
	local sw =
		Draw.img(group, { Name = "Stopwatch", ImageColor3 = Color3.fromRGB(255, 225, 120), ZIndex = halo.ZIndex + 1 })
	local sww, swh = Draw.fitIn(Q.Stopwatch, 28, 28)
	Draw.apply(sw, Q.Stopwatch, 22, 20, sww, swh)
	local avail = w - 56
	local label = Parts.text(group, {
		Name = "Resets",
		RichText = true,
		TextSize = 20,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(math.floor(40 + avail / 2), 20),
		Size = UDim2.fromOffset(avail, 40),
		ZIndex = pill.ZIndex + 1,
	}, 2)
	local timer = { Group = group, Label = label, Avail = avail }
	function timer:Set(prefix: string, value: string)
		label.Text = `{prefix} <font color="{GOLD_HEX}">{value}</font>`
		label.TextSize = Parts.fitSize(`{prefix} {value}`, avail, 20, 12)
	end
	return timer
end

return Draw
