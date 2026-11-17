-- Code-drawn window chrome shared by every menu (plan D1): window, panels, strips, dividers, fields, bar tracks and fills.
-- Colours are sampled from the mockups (Assets/UI/new/_overhaul/shared-measure.md). Design px under the shell's UIScale.
-- UIStroke thickness follows the UIScale above it (the shell's title stroke relies on it), so a design rim of 1 px would be
-- 0.5 real px on a phone: strokes carry the Rim attribute and Chrome.restroke(root, realPerDesign) keeps them >= 1 real px.

local UiKit = require(script.Parent.Parent.UiKit)

local make = UiKit.make

local Chrome = {}

Chrome.Fill = { Top = Color3.fromRGB(44, 44, 52), Bottom = Color3.fromRGB(35, 35, 41) } -- window body gradient
Chrome.Dark = Color3.fromRGB(22, 21, 28) -- inner and outer line of the window rim
Chrome.Light = Color3.fromRGB(172, 172, 184) -- the window's light rim
Chrome.PanelFill = { Top = Color3.fromRGB(39, 38, 42), Bottom = Color3.fromRGB(35, 34, 38) }
Chrome.PanelRim = Color3.fromRGB(135, 133, 139)
Chrome.FieldFill = Color3.fromRGB(30, 30, 34)
Chrome.TrackFill = Color3.fromRGB(33, 32, 37)

local function corner(inst, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, inst)
end

local function gradient(inst, top: Color3, bottom: Color3)
	make("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 }, inst)
end

-- Rim stroke: remembers its design thickness for restroke.
function Chrome.stroke(inst, color: Color3, thickness: number)
	local s = make("UIStroke", {
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
	s:SetAttribute("Rim", thickness)
	return s
end

-- Keeps every Rim stroke under root at >= 1 real px (k = real px per design px).
function Chrome.restroke(root: Instance, k: number)
	for _, d in root:GetDescendants() do
		local t = d:IsA("UIStroke") and d:GetAttribute("Rim")
		if t then
			d.Thickness = math.max(t, 1 / math.max(k, 0.01))
		end
	end
end

-- The window body inside `window` (the container, 1112x666 at the Full tier): outer dark line, 3 px light rim, inner dark line, gradient fill.
-- Measured on the mockups: dark 1 / light 3 / dark 2 px, outer corner radius 28.
function Chrome.window(window: GuiObject, z: number)
	local function layer(name: string, inset: number, radius: number, color: Color3)
		local f = make("Frame", {
			Name = name,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(inset, inset),
			Size = UDim2.new(1, -2 * inset, 1, -2 * inset),
			ZIndex = z,
		}, window)
		corner(f, radius)
		return f
	end
	layer("Outline", 0, 28, Chrome.Dark)
	layer("Rim", 1, 27, Chrome.Light)
	layer("Inner", 4, 24, Chrome.Dark)
	local fill = layer("Fill", 6, 22, Color3.new(1, 1, 1)) -- a UIGradient multiplies BackgroundColor3: base white
	gradient(fill, Chrome.Fill.Top, Chrome.Fill.Bottom)
	return fill
end

-- Inner dark panel with a thin light rim (Roll Featured / Rarity / Pity, Bag detail ...).
function Chrome.panel(parent: Instance, props: { [string]: any }?)
	props = props or {}
	local radius, rim = props.Radius or 14, props.Rim or 3
	local flat = props.NoGradient
	props.Radius, props.Rim, props.NoGradient = nil, nil, nil
	local base = props.BackgroundColor3 or Chrome.PanelFill.Top
	props.BackgroundColor3 = if flat then base else Color3.new(1, 1, 1) -- gradient multiplies the base: white
	props.BorderSizePixel = 0
	local f = make("Frame", props, parent)
	corner(f, radius)
	if not flat then
		gradient(f, base, base:Lerp(Color3.new(0, 0, 0), 0.08))
	end
	Chrome.stroke(f, Chrome.PanelRim, rim)
	return f
end

-- Header / row strip: a panel with a 2 px rim and a darker body.
function Chrome.strip(parent: Instance, props: { [string]: any }?)
	props = props or {}
	props.Radius, props.Rim = props.Radius or 10, props.Rim or 2
	props.BackgroundColor3 = props.BackgroundColor3 or Chrome.FieldFill
	return Chrome.panel(parent, props)
end

-- Search / sort field body.
function Chrome.field(parent: Instance, props: { [string]: any }?)
	props = props or {}
	props.Radius, props.Rim = props.Radius or 14, props.Rim or 2
	props.BackgroundColor3 = Chrome.FieldFill
	props.NoGradient = true
	return Chrome.panel(parent, props)
end

-- Thin light divider line (horizontal when w > h).
function Chrome.divider(parent: Instance, props: { [string]: any }?)
	props = props or {}
	props.BackgroundColor3 = props.BackgroundColor3 or Chrome.PanelRim
	props.BorderSizePixel = 0
	local f = make("Frame", props, parent)
	corner(f, 2)
	return f
end

-- Progress-bar track; returns the track and its fill (Fill.Size = UDim2.fromScale(fraction, 1)).
function Chrome.track(parent: Instance, props: { [string]: any }?, fillColor: Color3?)
	props = props or {}
	props.BackgroundColor3 = Chrome.TrackFill
	props.BorderSizePixel = 0
	props.ClipsDescendants = true
	local track = make("Frame", props, parent)
	corner(track, 999)
	Chrome.stroke(track, Chrome.PanelRim, 2)
	local c = fillColor or Color3.fromRGB(254, 224, 20)
	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = (props.ZIndex or 1) + 1,
	}, track)
	corner(fill, 999)
	make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, c:Lerp(Color3.new(1, 1, 1), 0.35)),
			ColorSequenceKeypoint.new(0.5, c),
			ColorSequenceKeypoint.new(1, c:Lerp(Color3.new(0, 0, 0), 0.2)),
		}),
		Rotation = 90,
	}, fill)
	return track, fill
end

return Chrome
