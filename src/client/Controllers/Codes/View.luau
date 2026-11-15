-- Codes popup view: sparkles, gems and gift, the caption / result line, the code field and REDEEM, drawn in the shared shell's
-- Content slot (Shell deps.size = (623, 532)). Visual only: the controller owns focus, sanitising, the button state machine and the
-- keyboard lift. Design px of the Full content box (578 x 441) under one UIScale, so phones shrink it uniformly with the window.
-- View.new(slot) -> .Box (TextBox) .Button (ImageButton) :SetButton(mode) :SetMessage(text?, tone?) :SetField(tone) :Destroy()
-- mode "Disabled" | "Ready" | "Waiting" | "Cooldown"; tone "Info" | "Error" | "Success"; field tone "Default" | "Error" | "Success".

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Bag.Parts)
local Draw = require(script.Parent.Parent.QuestLog.Draw)
local Sprites = require(script.Parent.Parent.Sprites)

local Q, Bag = Draw.Q, Draw.Bag
local make = UiKit.make

local W, H = 578, 441 -- Full content box: window ink (22.5, 59) .. (600.5, 500)
local CX = 289 -- the window's centre column
local Z = 22 -- the shell's Content slot
local CAPTION = "Enter a code for rewards!"
local TONE = {
	Info = UiKit.WHITE,
	Error = Color3.fromRGB(255, 99, 99),
	Success = UiKit.GREEN,
}
local FREDOKA = "rbxasset://fonts/families/FredokaOne.json"
local PLACEHOLDER_FONT = Font.new(FREDOKA, Enum.FontWeight.Regular, Enum.FontStyle.Italic)
local TEXT_FONT = Font.new(FREDOKA, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local TEXT_SIZE, TEXT_MIN = 45, 24 -- typed codes shrink to fit, then clip (24 design = 15 real px on the smallest phone)
-- Raw-id lobby HUD art drawn by its measured alpha ink (same ids as Sprites; no sprite table entry).
local GIFT = { Image = Sprites.Icon.Daily, Size = Vector2.new(237, 256), Ink = Rect.new(5, 4, 233, 251) }
local GEM = { Image = Sprites.Gem, Size = Vector2.new(128, 124), Ink = Rect.new(3, 3, 125, 121) }
-- Sparkle: a small orange glow, then Sparkle1 tinted orange (outer edge), yellow and white. Yellow and white are drawn as crosses
-- (one narrow and one flat copy, `ratio` of the sprite's aspect) so the arms stay bright and yellow to the tips like the
-- reference's fat stars, not Sparkle1's thin tapered ones. { ink height, cross ratio (nil = one plain copy), tint }, design px.
local SPARK_X, SPARK_Y = 113.5, 20
local SPARK_GLOW = { size = 56, color = Color3.fromRGB(255, 120, 0), transparency = 0.7 }
local SPARK_YELLOW = Color3.fromRGB(255, 230, 0)
local SPARK_LAYERS = {
	{ 44, nil, Color3.fromRGB(255, 130, 0) },
	{ 40, 0.8, SPARK_YELLOW },
	{ 40, 0.6, SPARK_YELLOW },
	{ 32, 0.5, Color3.new(1, 1, 1) },
	{ 28, nil, Color3.new(1, 1, 1) },
}
-- Gems: top 53, clear of the sparkle's visible lower tip (~42); centred 104 off the middle so the inner tip tucks ~2 reference px
-- behind the gift.
local GEM_H, GEM_X, GEM_Y = 86, 104, 96
local FIELD_PAD = 54 -- field ink edge to the text area, both sides (the reference's text start)

local View = {}
View.__index = View

function View.new(slot)
	local self = setmetatable({}, View)
	local conns = {}
	local root = make("Frame", {
		Name = "Codes",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H),
		ZIndex = Z,
	}, slot)
	local scale = make("UIScale", {}, root)
	local function fit()
		local s = slot.Size
		scale.Scale = math.min(s.X.Offset / W, s.Y.Offset / H)
	end
	fit()
	table.insert(conns, slot:GetPropertyChangedSignal("Size"):Connect(fit))

	-- Sparkles and one HUD currency gem either side, tucked behind the gift.
	local gemW, gemH = Draw.fitIn(GEM, 1e3, GEM_H)
	for sgn = -1, 1, 2 do
		local x = CX + sgn * SPARK_X
		local glow = Draw.apply(
			Draw.img(root, { Name = "SparkGlow", ZIndex = Z }), -- under the gems
			Q.GlowRadial,
			x,
			SPARK_Y,
			SPARK_GLOW.size,
			SPARK_GLOW.size
		)
		glow.ImageColor3, glow.ImageTransparency = SPARK_GLOW.color, SPARK_GLOW.transparency
		local z = Z + 1
		local function spark(w, h, tint)
			z += 1
			Draw.apply(Draw.img(root, { Name = "Spark", ZIndex = z }), Q.Sparkle1, x, SPARK_Y, w, h).ImageColor3 = tint
		end
		for _, layer in SPARK_LAYERS do
			local h, ratio, tint = layer[1], layer[2], layer[3]
			local w = h * Q.Sparkle1.Ink.Width / Q.Sparkle1.Ink.Height
			if ratio then
				spark(w * ratio, h, tint)
				spark(w, h * ratio, tint)
			else
				spark(w, h, tint)
			end
		end
		Draw.apply(Draw.img(root, { Name = "Gem", ZIndex = Z + 1 }), GEM, CX + sgn * GEM_X, GEM_Y, gemW, gemH)
	end
	local gw, gh = Draw.fitIn(GIFT, 170, 147)
	Draw.apply(Draw.img(root, { Name = "Gift", ZIndex = Z + 2 }), GIFT, CX, 77, gw, gh)

	local caption = Parts.text(root, {
		Name = "Caption",
		Text = CAPTION,
		TextSize = 48,
		TextTruncate = Enum.TextTruncate.None,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(CX, 169),
		Size = UDim2.fromOffset(540, 57),
		ZIndex = Z + 3,
	}, 4)

	-- Field: the Bag search art at slice 0.6 (ink 550 x 101: its pink rim = the reference's). The TextBox is the inner text area,
	-- FIELD_PAD from the ink on both sides, so typed text clips (focused: follows the cursor) well inside the rim.
	local field = Draw.apply(Draw.img(root, { Name = "Field", ZIndex = Z + 1 }), Bag.Search, CX, 260, 550, 101, 0.6)
	local textW = 550 - 2 * FIELD_PAD
	local box = make("TextBox", {
		Name = "Box",
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		FontFace = PLACEHOLDER_FONT,
		TextSize = TEXT_SIZE,
		TextColor3 = UiKit.WHITE,
		PlaceholderText = "Enter code here...",
		PlaceholderColor3 = Color3.fromRGB(218, 210, 214), -- reference #DAD2D6
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd, -- unfocused overflow (None while focused, below)
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -3), -- text centre 3 above the ink centre
		Size = UDim2.fromOffset(textW, 101), -- the field ink's height: a tap anywhere on it focuses
		ZIndex = Z + 2,
	}, field)
	-- Scrolled text puts the caret on the text area's right edge: keep it inside the clip.
	make("UIPadding", { PaddingRight = UDim.new(0, 8) }, box)
	-- The field's side insets (outside the text area) focus the box too.
	field.Active = true
	table.insert(
		conns,
		field.InputBegan:Connect(function(input)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				box:CaptureFocus()
			end
		end)
	)
	-- Unfocused overflow ends in "..."; while typing the box clips and follows the cursor instead (AtEnd would hide the caret's end).
	table.insert(
		conns,
		box.Focused:Connect(function()
			box.TextTruncate = Enum.TextTruncate.None
		end)
	)
	table.insert(
		conns,
		box.FocusLost:Connect(function()
			box.TextTruncate = Enum.TextTruncate.AtEnd
		end)
	)
	table.insert(
		conns,
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local t = box.Text
			box.FontFace = if t == "" then PLACEHOLDER_FONT else TEXT_FONT
			box.TextSize = if t == "" then TEXT_SIZE else Parts.fitSize(t, textW * 0.95, TEXT_SIZE, TEXT_MIN)
		end)
	)

	-- REDEEM: the Play START / Daily CLAIM button family, visible ink 536 x 114.
	local bw, bh = Parts.inkBox("BtnGreen", 536, 114)
	local button = Parts.button(root, {
		Name = "Redeem",
		Style = "Green",
		Label = "REDEEM",
		TextSize = 76, -- the reference label width (FredokaOne caps are shorter than the reference face)
		Size = UDim2.fromOffset(math.floor(bw + 0.5), math.floor(bh + 0.5)),
	})
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromOffset(CX, 379)
	local label = button.Label
	label.TextTruncate = Enum.TextTruncate.None
	label.Position, label.Size = UDim2.fromOffset(8, 0), UDim2.new(1, -16, 1, -7) -- label centre 3.5 above the ink centre
	label:FindFirstChildOfClass("UIStroke").Thickness = 5

	self._root, self._conns, self._caption = root, conns, caption
	self.Box, self.Button = box, button
	return self
end

-- Ready / Waiting keep the green look (Waiting shows a live label); Disabled / Cooldown use the shared disabled look.
function View:SetButton(mode: string)
	Parts.setButton(self.Button, {
		Label = if mode == "Waiting" then "REDEEMING..." else "REDEEM",
		Enabled = mode == "Ready" or mode == "Waiting",
	})
	self.Button.Interactable = mode ~= "Waiting"
end

-- nil text = the default caption. The line keeps its box; long messages shrink to fit.
function View:SetMessage(text: string?, tone: string?)
	local c = self._caption
	c.Text = text or CAPTION
	c.TextColor3 = TONE[tone or "Info"] or TONE.Info
	c.TextSize = Parts.fitSize(c.Text, 540, 48, 28)
end

-- Field tone: kept for the contract; the field art does not change (a tint muddies the shared sprite).
function View:SetField(_tone: string) end

function View:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	self._root:Destroy()
end

return View
