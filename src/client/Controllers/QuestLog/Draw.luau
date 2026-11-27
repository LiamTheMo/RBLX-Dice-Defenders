-- Quest Log drawing helpers shared by Toolbar, Quests and Detail: Parts.inkBox only knows BagSprites keys, these take records.
-- Design px under the shell's UIScale. Everything is sized by the sprite's visible ink (Ink rect), centred by its ink.

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Bag.Parts)
local Q = require(script.Parent.QuestSprites)

local make = UiKit.make

local Draw = { Q = Q }

local round = UiKit.round

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
-- Size and Position snap to whole design px (offsets are integers) unless `exact` (the parent's design size): then they are
-- scales of it, so the box lands at the fractional design px asked for.
function Draw.apply(inst, rec, cx: number, cy: number, inkW: number, inkH: number, k: number?, exact: Vector2?)
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
	local px, py =
		cx + (size.X / 2 - (ink.Min.X + ink.Max.X) / 2) * sx, cy + (size.Y / 2 - (ink.Min.Y + ink.Max.Y) / 2) * sy
	if exact then
		inst.Size = UDim2.fromScale(w / exact.X, h / exact.Y)
		inst.Position = UDim2.fromScale(px / exact.X, py / exact.Y)
	else
		inst.Size = UDim2.fromOffset(round(w), round(h))
		inst.Position = UDim2.fromOffset(round(px), round(py))
	end
	return inst
end

-- Icon fitted in maxW x maxH centred at (cx, cy): a QuestSprites key (or record) by its ink, or a raw asset id (the HUD
-- coin / gem, die art) letterboxed with Fit.
function Draw.icon(inst, ref, cx: number, cy: number, maxW: number, maxH: number)
	local rec = if type(ref) == "table" then ref else Q[ref]
	if rec then
		local w, h = Draw.fitIn(rec, maxW, maxH)
		return Draw.apply(inst, rec, cx, cy, w, h)
	end
	inst.Image = ref or ""
	inst.ScaleType = Enum.ScaleType.Fit
	inst.AnchorPoint = Vector2.new(0.5, 0.5)
	inst.Size = UDim2.fromOffset(round(maxW), round(maxH))
	inst.Position = UDim2.fromOffset(round(cx), round(cy))
	return inst
end

return Draw
