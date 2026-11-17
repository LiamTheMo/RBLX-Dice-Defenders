-- Codes view: gift with sparkles and HUD-gem decoration, heading, code field, REDEEM and the info strip with the live status text,
-- drawn in the shared shell's Content slot (the same window as every menu). Visual only: the controller owns focus, sanitising, the
-- button state machine and the keyboard lift. Design px of the Full content box (1068 x 582, window origin + (22, 64)) under one
-- UIScale, so phones shrink it uniformly with the window; the numbers are measured on codes-revised.png (slot = mockup - (302, 150)).
-- View.new(slot) -> .Box (TextBox) .Button (ImageButton) .Hit (its >= 44 real px TextButton) :SetButton(mode) :SetMessage(text?, tone?)
-- :SetField(tone) :Destroy()
-- mode "Disabled" | "Ready" | "Waiting" | "Cooldown"; tone "Info" | "Error" | "Success"; field tone "Default" | "Error" | "Success".

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Bag.Parts)
local Chrome = require(script.Parent.Parent.Bag.Chrome)
local CodesSprites = require(script.Parent.CodesSprites)
local Shared = require(script.Parent.Parent.SharedSprites)

local TextService = game:GetService("TextService")

local make = UiKit.make

local W, H = 1068, 582 -- Full content box
local CX = W / 2
local Z = 22 -- the shell's Content slot
local MIN_HIT = 44 -- real px
local CAPTION = "Enter a code for rewards!"
local DEFAULT_STATUS = "Enter a valid code to receive free rewards!"
local TONE = {
	Info = UiKit.WHITE,
	Error = Color3.fromRGB(255, 99, 99),
	Success = UiKit.GREEN,
}
local FIELD_RIM = Color3.fromRGB(205, 199, 214) -- mockup rim (215,209,225) outside, (128,119,138) at the inner edge
local FIELD_TONE = { Default = FIELD_RIM, Error = TONE.Error, Success = TONE.Success }
local FREDOKA = "rbxasset://fonts/families/FredokaOne.json"
local PLACEHOLDER_FONT = Font.new(FREDOKA, Enum.FontWeight.Regular, Enum.FontStyle.Italic)
local TEXT_FONT = Font.new(FREDOKA, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local TEXT_SIZE, TEXT_MIN = 47, 24 -- typed codes shrink to fit, then clip
local FIELD_W, FIELD_H = 721, 67 -- frame; the 4 px rim draws outside it: ink 729 x 75
local TEXT_PAD = 60 -- field edge to the placeholder / text start (mockup x 535)
local STRIP_W, STRIP_H = 785, 78
local STATUS_W = STRIP_W - 167 - 24
local BTN_W, BTN_H = 515, 100 -- the pill ink is 90 of the box height (81 measured at 90)
local LABEL_W = 218 -- the mockup's REDEEM label width

-- Whole sheet assets at native aspect (ids in CodesSprites; Size = export px, from manifest.json).
local SIZE = {
	Gift = Vector2.new(248, 234),
	Sparkle = Vector2.new(136, 150),
	InfoBadge = Vector2.new(106, 108),
	ShardBlue = Vector2.new(119, 202),
	ShardPurple = Vector2.new(106, 185),
}
local ART = {}
for name, size in SIZE do
	ART[name] = { Image = CodesSprites[name].Image, Size = size }
end
-- Crystals around the gift (decoration, not currency): left side { name, art, centre x, centre y, height, rotation }; mirrored right.
local SHARDS = {
	{ "Blue", "ShardBlue", 388, 122, 98, -12 },
	{ "Purple", "ShardPurple", 433, 138, 80, 8 },
	{ "Small", "ShardPurple", 358, 153, 58, -60 },
}
local CAPTION_SIZE = Parts.fitSize(CAPTION, 631, 100, 20)
local STATUS_FONT = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.SemiBold)
local STATUS_REF_W = 567 -- the mockup line is 545 wide; built ink measured 4% small
local BADGE = { Info = ART.InfoBadge, Success = Shared.Check, Error = Shared.Close }

local View = {}
View.__index = View

-- Image centred at (cx, cy), `w` wide at the sprite's native aspect.
local function art(parent, sprite, name: string, cx: number, cy: number, w: number, z: number)
	return make("ImageLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Image = sprite.Image,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(w, w * sprite.Size.Y / sprite.Size.X),
		ZIndex = z,
	}, parent)
end

-- TextSize at which `text` is `width` design px wide in the status font (never above 32 x the default's ratio when asked for a cap).
local function statusFit(text: string, width: number, probe: number): number
	local params = Instance.new("GetTextBoundsParams")
	params.Font, params.Size, params.Text = STATUS_FONT, probe, text
	return math.max(14, math.floor(probe * width / math.max(TextService:GetTextBoundsAsync(params).X, 1)))
end

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

	-- Decoration: sparkles and crystal shards either side, tucked behind the gift.
	local crystals = make("Frame", {
		Name = "Crystals",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(W, H),
		ZIndex = Z + 1,
	}, root)
	for sgn = -1, 1, 2 do
		art(root, ART.Sparkle, "Sparkle", CX + sgn * 117, 53, 54, Z + 1)
		for _, g in SHARDS do
			local sprite = ART[g[2]]
			local shard = art(
				crystals,
				sprite,
				(if sgn < 0 then "Left" else "Right") .. g[1],
				if sgn < 0 then g[3] else W - g[3],
				g[4],
				g[5] * sprite.Size.X / sprite.Size.Y,
				Z + 1
			)
			shard.Rotation = -sgn * g[6]
		end
	end
	art(root, ART.Gift, "Gift", CX, 112, 170, Z + 3)

	Parts.text(root, {
		Name = "Caption",
		Text = CAPTION,
		TextSize = CAPTION_SIZE, -- width matches the mockup (TextSize is line height)
		TextTruncate = Enum.TextTruncate.None,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(CX, 218),
		Size = UDim2.fromOffset(760, math.ceil(CAPTION_SIZE * 1.25)), -- the box holds the line height
		ZIndex = Z + 3,
	}, 4)

	-- Field: code-drawn (Chrome), fill (47,47,50), 4 px lilac rim. The TextBox spans the field (a tap anywhere focuses), padded to the
	-- text area, and grows to >= 44 real px tall on phones.
	local field = Chrome.panel(root, {
		Name = "Field",
		Position = UDim2.fromOffset((W - FIELD_W) / 2, 275),
		Size = UDim2.fromOffset(FIELD_W, FIELD_H),
		BackgroundColor3 = Color3.fromRGB(47, 47, 50),
		NoGradient = true,
		Radius = 22,
		Rim = 4,
		ZIndex = Z + 1,
	})
	local fieldRim = field:FindFirstChildOfClass("UIStroke")
	fieldRim.Color = FIELD_RIM
	local box = make("TextBox", {
		Name = "Box",
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		FontFace = PLACEHOLDER_FONT,
		TextSize = TEXT_SIZE,
		TextColor3 = UiKit.WHITE,
		PlaceholderText = "Enter code here...",
		PlaceholderColor3 = Color3.fromRGB(198, 195, 198), -- mockup placeholder
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd, -- unfocused overflow (None while focused, below)
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(FIELD_W, FIELD_H),
		ZIndex = Z + 2,
	}, field)
	make("UIPadding", { PaddingLeft = UDim.new(0, TEXT_PAD), PaddingRight = UDim.new(0, TEXT_PAD) }, box)
	local textW = FIELD_W - 2 * TEXT_PAD
	-- The mockup's resting caret: shown while the box is empty (the engine draws its own once there is text).
	local caret = make("Frame", {
		Name = "Caret",
		BackgroundColor3 = UiKit.WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(30, FIELD_H / 2),
		Size = UDim2.fromOffset(3, 44),
		ZIndex = Z + 2,
	}, field)
	local function caretOn()
		caret.Visible = box.Text == ""
	end
	caretOn()
	-- Unfocused overflow ends in "..."; while typing the box clips and follows the cursor instead (AtEnd would hide the caret's end).
	table.insert(
		conns,
		box.Focused:Connect(function()
			box.TextTruncate = Enum.TextTruncate.None
			caretOn()
		end)
	)
	table.insert(
		conns,
		box.FocusLost:Connect(function()
			box.TextTruncate = Enum.TextTruncate.AtEnd
			caretOn()
		end)
	)
	table.insert(
		conns,
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local t = box.Text
			box.FontFace = if t == "" then PLACEHOLDER_FONT else TEXT_FONT
			box.TextSize = if t == "" then TEXT_SIZE else Parts.fitSize(t, textW * 0.95, TEXT_SIZE, TEXT_MIN)
			caretOn()
		end)
	)

	-- REDEEM: the shared green pill (Parts.button), live label, a Hit box >= 44 real px.
	local button = Parts.button(root, {
		Name = "Redeem",
		Style = "Green",
		Label = "REDEEM",
		TextSize = Parts.fitSize("REDEEM", LABEL_W, 90, 20),
		Size = UDim2.fromOffset(BTN_W, BTN_H),
	})
	button.AnchorPoint, button.Position, button.ZIndex = Vector2.new(0.5, 0), UDim2.fromOffset(CX, 378), Z + 1
	local label = button.Label
	label.TextTruncate = Enum.TextTruncate.None
	label.ZIndex = Z + 2
	label:FindFirstChildOfClass("UIStroke").Thickness = 5
	local hit = make("TextButton", {
		Name = "Hit",
		BackgroundTransparency = 1,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(BTN_W, BTN_H),
		ZIndex = Z + 3,
		Selectable = false, -- the button stays the one gamepad stop
	}, button)
	UiKit.wire(hit, function(state)
		button:SetAttribute("DebugState", if state == "Normal" then nil else state)
	end)

	-- Info strip: Chrome strip, badge, divider, live status text.
	local strip = Chrome.strip(root, {
		Name = "Strip",
		Position = UDim2.fromOffset((W - STRIP_W) / 2, 490),
		Size = UDim2.fromOffset(STRIP_W, STRIP_H),
		BackgroundColor3 = Color3.fromRGB(50, 50, 53),
		NoGradient = true,
		Radius = 16,
		Rim = 3,
		ZIndex = Z + 1,
	})
	strip:FindFirstChildOfClass("UIStroke").Color = Color3.fromRGB(200, 198, 201)
	local badge = art(strip, ART.InfoBadge, "Badge", 92, STRIP_H / 2, 44, Z + 2)
	Chrome.divider(strip, {
		Name = "Divider",
		BackgroundColor3 = Color3.fromRGB(245, 245, 246),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(140, STRIP_H / 2),
		Size = UDim2.fromOffset(2, 42),
		ZIndex = Z + 2,
	})
	local status = make("TextLabel", {
		Name = "Status",
		BackgroundTransparency = 1,
		Text = DEFAULT_STATUS,
		FontFace = STATUS_FONT,
		TextColor3 = TONE.Info,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.None,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(167, STRIP_H / 2),
		Size = UDim2.fromOffset(STATUS_W, 30),
		ZIndex = Z + 2,
	}, strip)
	-- Status size: the default line is STATUS_REF_W wide (TextSize is line height, so measure instead of guessing).
	local statusSize = statusFit(DEFAULT_STATUS, STATUS_REF_W, 32)
	status.TextSize = statusSize
	status.Size = UDim2.fromOffset(STATUS_W, math.ceil(statusSize * 1.25))

	-- Uniform fit to the slot (design px); the field and REDEEM hit boxes grow to >= 44 real px (real px per design px = root / W).
	local function fit()
		local s = slot.Size
		scale.Scale = math.min(s.X.Offset / W, s.Y.Offset / H)
		local minD = math.ceil(MIN_HIT / math.max(root.AbsoluteSize.X / W, 0.05))
		box.Size = UDim2.fromOffset(FIELD_W, math.max(FIELD_H, minD))
		hit.Size = UDim2.fromOffset(BTN_W, math.max(BTN_H, minD))
	end
	fit()
	table.insert(conns, slot:GetPropertyChangedSignal("Size"):Connect(fit))
	table.insert(conns, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit))

	self._root, self._conns = root, conns
	self._status, self._badge, self._fieldRim, self._statusSize = status, badge, fieldRim, statusSize
	self.Box, self.Button, self.Hit = box, button, hit
	return self
end

-- Ready / Waiting keep the green look (Waiting shows a live label); Disabled / Cooldown use the shared disabled look.
function View:SetButton(mode: string)
	local text = if mode == "Waiting" then "REDEEMING..." else "REDEEM"
	Parts.setButton(self.Button, { Label = text, Enabled = mode == "Ready" or mode == "Waiting" })
	self.Button.Interactable = mode ~= "Waiting"
	self.Hit.Interactable = mode ~= "Waiting"
end

-- nil text = the default status. Long messages shrink to fit the strip; the badge follows the tone.
function View:SetMessage(text: string?, tone: string?)
	local s = self._status
	s.Text = text or DEFAULT_STATUS
	s.TextColor3 = TONE[tone or "Info"] or TONE.Info
	s.TextSize = math.min(self._statusSize, statusFit(s.Text, STATUS_W, 32))
	local b = BADGE[tone or "Info"] or BADGE.Info
	self._badge.Image = b.Image
	self._badge.Size = UDim2.fromOffset(44, 44 * b.Size.Y / b.Size.X)
end

-- Field rim tone: Default / Error / Success.
function View:SetField(tone: string)
	self._fieldRim.Color = FIELD_TONE[tone] or FIELD_RIM
end

function View:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	self._root:Destroy()
end

return View
