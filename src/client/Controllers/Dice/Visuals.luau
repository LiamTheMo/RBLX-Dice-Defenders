local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(script.Parent.CommonModelData)
local Rare = require(script.Parent.RareModelData)
local Epic = require(script.Parent.EpicModelData)
local Legendary = require(script.Parent.LegendaryModelData)
local Mythic = require(script.Parent.MythicModelData)
local Secret = require(script.Parent.SecretModelData)
local Assets = require(ReplicatedStorage.Shared.DiceAssets)

local Visuals = {}

-- Dice are the uploaded models DiceModelService loads into ReplicatedStorage.DiceModels ("<typeId>_<tier>"); the
-- ModelData modules only supply styles and pip layouts for the flat fallback shown until a model arrives.
local NORMALIZED_EDGE = 2.5 -- pip layouts are in normalized die space (cube +-1.25)
local DICE_SIZE = 4 -- the die is a 4-stud cube (owner 2026-11-26): studs per side on the board
local PIP = Color3.fromHex("#0E0E0E")
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new()
local LM_STYLES = { Legendary, Mythic, Secret }
local MODEL_WAIT = 60 -- seconds a die waits for its model before keeping the flat fallback

-- A cloned model's mesh and top texture arrive asynchronously, so a die that swaps in the moment its model exists shows
-- a bare body first and the design a beat later. Every model is preloaded once and swaps in only when it is ready.
local ready = {} -- model -> true once its meshes and textures are in memory
local warmed = {} -- typeId -> true

function Visuals.Warm(typeId: string)
	if warmed[typeId] then
		return
	end
	warmed[typeId] = true
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("DiceModels", MODEL_WAIT)
		if not folder then
			return
		end
		for tier = 1, 7 do
			task.spawn(function()
				local model = folder:WaitForChild(typeId .. "_" .. tier, MODEL_WAIT)
				if model then
					-- shortcut: a failed fetch still marks the model ready, so a bad asset never hides its die
					pcall(ContentProvider.PreloadAsync, ContentProvider, { model })
					ready[model] = true
				end
			end)
		end
	end)
end

function Visuals.Size(_typeId: string): number
	return DICE_SIZE
end

-- Epic and the L/M/S dice share the "epic" fallback look and style table.
local function epicStyle(typeId: string)
	local style = Epic.Styles[typeId]
	if style then
		return style
	end
	for _, module in LM_STYLES do
		if module.Styles[typeId] then
			return module.Styles[typeId]
		end
	end
	return nil
end

local function findModel(typeId: string, tier: number): Model?
	local folder = ReplicatedStorage:FindFirstChild("DiceModels")
	return folder and folder:FindFirstChild(typeId .. "_" .. tier) :: Model?
end

-- Clones every MeshPart of the uploaded model onto the anchor, scaled from the model's authored edge to the anchor.
local function applyModel(anchor: BasePart, target: Instance, model: Model, typeId: string)
	local edge = Assets.Edge[typeId:sub(1, 1)]
	local scale = anchor.Size.X / edge
	-- The template offsets are full-size even if the die arrives mid-animation.
	local owner = anchor:FindFirstAncestorOfClass("Model")
	local ownerScale = if owner then owner:GetScale() else 1
	if owner and ownerScale ~= 1 then
		owner:ScaleTo(1)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("MeshPart") then
			local mesh = part:Clone()
			mesh.Size = part.Size * scale
			mesh.CFrame = anchor.CFrame * CFrame.new(part.Position * scale)
			mesh.Parent = target
		end
	end
	if owner and ownerScale ~= 1 then
		owner:ScaleTo(ownerScale)
	end
	anchor.Transparency = 1
end

local function symbol(surface: SurfaceGui, name: string, glyph: string, color: Color3, pos: number, size: number)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, pos)
	label.Size = UDim2.fromScale(0.7, size)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = glyph
	label.TextColor3 = color
	label.TextScaled = true
	label.Parent = surface
	return label
end

-- Surface marks also work in experiences or on devices without an editable mesh budget.
local function applySurfaces(
	anchor: BasePart,
	fallback: Folder,
	tier: number,
	color: Color3,
	style,
	texture: Content?,
	epic: boolean
)
	anchor.Color = if style then Color3.fromHex(style.Body) else color:Lerp(BLACK, 0.35)
	anchor.Transparency = 0
	local rare = style and style.Pip
	local pipColor = if rare then Color3.fromHex(rare) elseif style then PIP else color:Lerp(WHITE, 0.55)
	for _, face in Enum.NormalId:GetEnumItems() do
		local surface = Instance.new("SurfaceGui")
		surface.Name = face.Name
		surface.Face = face
		surface.Adornee = anchor
		surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		surface.CanvasSize = Vector2.new(128, 128)
		surface.LightInfluence = 0.25
		if style then
			if face == Enum.NormalId.Top then
				if texture then
					local paint = Instance.new("ImageLabel")
					paint.Name = "TopDesign"
					paint.BackgroundTransparency = 1
					paint.ImageContent = texture
					paint.Size = UDim2.fromScale(1, 1)
					if rare then
						paint.ImageRectOffset = Vector2.new(0, 5)
						paint.ImageRectSize = Vector2.new(128, 123)
						paint.Position = UDim2.fromScale(0, 5 / 128)
						paint.Size = UDim2.fromScale(1, 123 / 128)
					end
					paint.Parent = surface
				else
					local paint = symbol(
						surface,
						"TopDesign",
						style.Mark,
						if style.Ink then Color3.fromHex(style.Ink) elseif epic then Color3.fromHex(style.Bevel) else PIP,
						0.5,
						0.7
					)
					paint.TextTransparency = 0.65
				end
			end
		elseif face ~= Enum.NormalId.Top then
			local band = Instance.new("Frame")
			band.Name = "Band"
			band.Size = UDim2.fromScale(1, if face == Enum.NormalId.Bottom then 1 else 0.46)
			band.AnchorPoint = Vector2.new(0, 1)
			band.Position = UDim2.fromScale(0, 1)
			band.BackgroundColor3 = color
			band.BorderSizePixel = 0
			band.Parent = surface
		end

		if tier == 7 then
			local star = symbol(surface, "Star", "★", if rare then pipColor else PIP, 0.5, 0.46)
			star.ZIndex = 2
			star.TextStrokeColor3 = if epic then Color3.fromHex(style.Rim) else PIP
			star.TextStrokeTransparency = if rare and not epic then 1 else 0
		else
			local slots = if epic
				then Epic.Layouts[tier]
				elseif rare and tier == 6 then Rare.TierSix
				else Data.Layouts[tier]
			for i, slot in slots do
				local pip = Instance.new("Frame")
				pip.Name = "Pip" .. i
				pip.AnchorPoint = Vector2.new(0.5, 0.5)
				pip.Position = UDim2.fromScale(0.5 + slot[1] / NORMALIZED_EDGE, 0.5 - slot[2] / NORMALIZED_EDGE)
				pip.Size = UDim2.fromScale(0.176, 0.176)
				pip.BorderSizePixel = 0
				pip.BackgroundColor3 = pipColor
				pip.ZIndex = 2
				pip.Parent = surface
				local round = Instance.new("UICorner")
				round.CornerRadius = UDim.new(0.5, 0)
				round.Parent = pip
				if epic then
					local stroke = Instance.new("UIStroke")
					stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					stroke.Color = Color3.fromHex(style.Rim)
					stroke.Parent = pip
				end
			end
		end
		surface.Parent = fallback
	end
end

function Visuals.Apply(anchor: BasePart, typeId: string, tier: number, color: Color3)
	local old = anchor:FindFirstChild("Visuals")
	if old then
		old:Destroy()
	end
	local visuals = Instance.new("Folder")
	visuals.Name = "Visuals"
	visuals.Parent = anchor
	local epic = epicStyle(typeId)
	local style = epic or Rare.Styles[typeId] or Data.Styles[typeId]
	local target: Instance = visuals
	if style and style.Name then
		local variant = Instance.new("Model")
		variant.Name = string.format("%s_%02d", style.Name, tier)
		variant.WorldPivot = anchor.CFrame
		variant.Parent = visuals
		target = variant
	end
	Visuals.Warm(typeId)
	local model = findModel(typeId, tier)
	if model and ready[model] then
		applyModel(anchor, target, model, typeId)
		return
	end

	local fallback = Instance.new("Folder")
	fallback.Name = "SurfaceMarks"
	fallback.Parent = target
	applySurfaces(anchor, fallback, tier, color, style, nil, epic ~= nil)
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("DiceModels", MODEL_WAIT)
		local arrived = folder and folder:WaitForChild(typeId .. "_" .. tier, MODEL_WAIT)
		local deadline = os.clock() + MODEL_WAIT
		while arrived and not ready[arrived] and os.clock() < deadline do
			task.wait(0.05)
		end
		if arrived and visuals.Parent == anchor then
			applyModel(anchor, target, arrived :: Model, typeId)
			fallback:Destroy()
		end
	end)
end

return Visuals
