-- Teams popup: five saved loadouts. Each row shows its dice with SAVE (store the equipped loadout there) and LOAD (equip it).
-- Pure view: the Bag sends TeamAction and the rows redraw from the next Meta.
-- TeamsPopup.new(parent, z) -> popup :Set(meta) :OnAction(cb(action: "Save"|"Load", slot)) :Show() :Hide() :IsOpen()
-- parent is the Bag window (design px); the popup dims everything under it and a click outside closes it.

local Sprites = require(script.Parent.Parent.Sprites)
local UiKit = require(script.Parent.Parent.UiKit)
local Chrome = require(script.Parent.Chrome)
local Parts = require(script.Parent.Parts)
local Display = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Display"))

local make = UiKit.make
local SIZE = 5
local PANEL_W, HEAD_H, ROW_H, ROW_GAP, PAD = 660, 64, 62, 8, 20
local ICON, ICON_GAP, ICONS_X = 50, 6, 124
local GOLD = Color3.fromRGB(252, 205, 10)
local SOFT = Color3.fromRGB(150, 150, 160)

local TeamsPopup = {}
TeamsPopup.__index = TeamsPopup

local function art(id: string): string?
	local name = Sprites.DieArt[id]
	local image = name and Sprites.Dice[name]
	return if image and image ~= "" then image else nil
end

local function sameDeck(a, b): boolean
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
		return false
	end
	for i, id in a do
		if b[i] ~= id then
			return false
		end
	end
	return true
end

function TeamsPopup.new(parent: GuiObject, z: number)
	local self = setmetatable({}, TeamsPopup)
	self._rows, self._onAction, self._open = {}, nil, false

	local backdrop = make("TextButton", {
		Name = "TeamsBackdrop",
		Text = "",
		AutoButtonColor = false,
		Active = true,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = z,
	}, parent)
	backdrop.Activated:Connect(function()
		self:Hide()
	end)
	self._backdrop = backdrop

	local panelH = HEAD_H + SIZE * ROW_H + (SIZE - 1) * ROW_GAP + PAD
	local panel = Chrome.panel(backdrop, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_W, panelH),
		ZIndex = z + 1,
		Radius = 18,
	})
	local sink = make("TextButton", { -- a click on the panel itself must not reach the backdrop
		Name = "Sink",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
	}, panel)
	sink.Active = true

	local title = Parts.text(panel, {
		Name = "Title",
		Text = "TEAMS",
		TextSize = 36,
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.fromOffset(0, 8),
		ZIndex = z + 3,
	}, 3)
	title.TextXAlignment = Enum.TextXAlignment.Center
	local close = Parts.button(panel, {
		Name = "Close",
		Style = "Red",
		Label = "X",
		TextSize = 26,
		Size = UDim2.fromOffset(52, 42),
	})
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 11)
	close.ZIndex = z + 4
	close.Label.ZIndex = z + 5
	close.Activated:Connect(function()
		self:Hide()
	end)

	for i = 1, SIZE do
		local strip = Chrome.strip(panel, {
			Name = "Team" .. i,
			Position = UDim2.fromOffset(PAD, HEAD_H + (i - 1) * (ROW_H + ROW_GAP)),
			Size = UDim2.fromOffset(PANEL_W - 2 * PAD, ROW_H),
			ZIndex = z + 3,
		})
		local label = Parts.text(strip, {
			Name = "Label",
			Text = "TEAM " .. i,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(16, 0),
			Size = UDim2.fromOffset(100, ROW_H),
			ZIndex = z + 4,
		}, 2)
		local icons = {}
		for k = 1, SIZE do
			icons[k] = make("ImageLabel", {
				Name = "Die" .. k,
				BackgroundTransparency = 1,
				ScaleType = Enum.ScaleType.Fit,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, ICONS_X + (k - 1) * (ICON + ICON_GAP), 0.5, 0),
				Size = UDim2.fromOffset(ICON, ICON),
				Visible = false,
				ZIndex = z + 4,
			}, strip)
		end
		local empty = Parts.text(strip, {
			Name = "Empty",
			Text = "Empty",
			TextSize = 22,
			TextColor3 = SOFT,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(ICONS_X, 0),
			Size = UDim2.fromOffset(200, ROW_H),
			ZIndex = z + 4,
		}, 2)
		local function actionButton(name: string, text: string, style: string, rightInset: number)
			local btn = Parts.button(strip, {
				Name = name,
				Style = style,
				Label = text,
				TextSize = 22,
				Size = UDim2.fromOffset(96, 42),
			})
			btn.AnchorPoint = Vector2.new(1, 0.5)
			btn.Position = UDim2.new(1, -rightInset, 0.5, 0)
			btn.ZIndex = z + 4
			btn.Label.ZIndex = z + 5
			btn.Activated:Connect(function()
				if self._onAction then
					self._onAction(string.upper(name) == "SAVE" and "Save" or "Load", i)
				end
			end)
			return btn
		end
		local load = actionButton("Load", "LOAD", "Green", 14)
		local save = actionButton("Save", "SAVE", "Grey", 14 + 96 + 8)
		self._rows[i] = {
			Strip = strip,
			Stroke = strip:FindFirstChildOfClass("UIStroke"),
			Label = label,
			Icons = icons,
			Empty = empty,
			Load = load,
			Save = save,
		}
	end
	return self
end

-- Redraw every row from Meta (Deck and Teams); the row equal to the equipped loadout gets a gold rim.
function TeamsPopup:Set(meta)
	local deck = meta and meta.Deck or {}
	local teams = meta and meta.Teams or {}
	for i, row in self._rows do
		local ids = teams[tostring(i)]
		local saved = type(ids) == "table" and #ids > 0
		row.Empty.Visible = not saved
		for k, icon in row.Icons do
			local id = saved and ids[k] or nil
			icon.Visible = id ~= nil
			if id then
				local image = art(id)
				local info = Display.Dice[id]
				icon.Image = image or Sprites.Icon.Roll
				icon.ImageColor3 = if image then Color3.new(1, 1, 1) else (info and info.Color or Color3.new(1, 1, 1))
			end
		end
		local current = saved and sameDeck(ids, deck)
		if row.Stroke then
			row.Stroke.Color = if current then GOLD else Chrome.PanelRim
		end
		Parts.setButton(row.Load, { Enabled = saved and not current })
		Parts.setButton(row.Save, { Enabled = #deck > 0 and not current })
	end
end

function TeamsPopup:OnAction(cb)
	self._onAction = cb
end

function TeamsPopup:Show()
	self._open = true
	self._backdrop.Visible = true
end

function TeamsPopup:Hide()
	self._open = false
	self._backdrop.Visible = false
end

function TeamsPopup:IsOpen(): boolean
	return self._open
end

function TeamsPopup:Destroy()
	self._backdrop:Destroy()
end

return TeamsPopup
