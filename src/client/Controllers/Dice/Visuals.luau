local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")

local Data = require(script.Parent.ModelData)
local Rare = require(script.Parent.RareModelData)
local Epic = require(script.Parent.EpicModelData)

local Visuals = {}

local AUTHORED_SIZE = 2.5
local PIP = Color3.fromHex("#16171B")
local GOLD = Color3.fromHex("#FFD65C")
local STAR_RIM = Color3.fromHex("#32201A")
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new()
local BODIES = {}
local MARKS = {}
local RARE_BODIES = {}
local RARE_MARKS = {}
local EPIC_BODIES = {}
local EPIC_MARKS = {}
local EPIC_ORNAMENTS = {}
local TOP_TEXTURES = {}
local iceChips
local ready = Instance.new("BindableEvent")
local loading = true

function Visuals.Size(typeId: string): number
	return if Data.Styles[typeId] or Rare.Styles[typeId] or Epic.Styles[typeId] then AUTHORED_SIZE * 2 else 4.4
end

local function meshTemplate(
	packet: string,
	palette: { Color3 },
	paintTop: boolean?,
	firstMesh: EditableMesh?,
	swatches: boolean?
)
	local editable
	local ok, template, offset = pcall(function()
		editable = firstMesh or AssetService:CreateEditableMesh()
		if not editable then
			return nil
		end

		local data = EncodingService:Base64Decode(buffer.fromstring(packet))
		local vertexCount = buffer.readu16(data, 0)
		local triangleCount = buffer.readu16(data, 2)
		local positions = table.create(vertexCount)
		local ids = table.create(vertexCount)
		local min, max = Vector3.one * math.huge, Vector3.one * -math.huge
		local cursor = 4
		for i = 1, vertexCount do
			local p = Vector3.new(
				buffer.readi16(data, cursor),
				buffer.readi16(data, cursor + 2),
				buffer.readi16(data, cursor + 4)
			) / 1000
			positions[i] = p
			min, max = min:Min(p), max:Max(p)
			cursor += 6
		end
		local center = (min + max) / 2
		local topUVs = {}
		local blankUVs = {}
		if paintTop then
			local blank = editable:AddUV(Vector2.zero)
			for i = 1, 3 do
				local uv = if swatches then editable:AddUV(Vector2.new((14 + (i - 1) * 20) / 128, 2 / 128)) else blank
				blankUVs[i] = { uv, uv, uv }
			end
		end
		for i, p in positions do
			ids[i] = editable:AddVertex(p - center)
			if paintTop and p.Y == max.Y then
				topUVs[i] = editable:AddUV(Vector2.new(0.5 + p.X / 2.5, 0.5 + p.Z / 2.5))
			end
		end

		local colors, normals = {}, {}
		for i, color in palette do
			local id = editable:AddColor(color, 1)
			colors[i] = { id, id, id }
		end
		for _ = 1, triangleCount do
			local a = buffer.readu16(data, cursor) + 1
			local b = buffer.readu16(data, cursor + 2) + 1
			local c = buffer.readu16(data, cursor + 4) + 1
			local shade = buffer.readu8(data, cursor + 6) + 1
			local triangle = editable:AddTriangle(ids[a], ids[b], ids[c])
			local normal = (positions[b] - positions[a]):Cross(positions[c] - positions[a]).Unit
			local key =
				Vector3.new(math.round(normal.X * 1000), math.round(normal.Y * 1000), math.round(normal.Z * 1000))
			local faceNormals = normals[key]
			if faceNormals == nil then
				local id = editable:AddNormal(normal)
				faceNormals = { id, id, id }
				normals[key] = faceNormals
			end
			editable:SetFaceNormals(triangle, faceNormals)
			editable:SetFaceColors(triangle, colors[shade])
			if paintTop then
				editable:SetFaceUVs(
					triangle,
					if shade == 4 then { topUVs[a], topUVs[b], topUVs[c] } else blankUVs[shade]
				)
			end
			cursor += 7
		end

		-- Keep only the fixed-size copy after filling the editable scratch mesh.
		local fixed = AssetService:CreateEditableMeshAsync(Content.fromObject(editable), { FixedSize = true })
		if fixed then
			editable:Destroy()
			editable = fixed
		end
		local part = AssetService:CreateMeshPartAsync(Content.fromObject(editable))
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		return part, center
	end)
	if ok and template then
		return { Part = template, Offset = offset }
	end
	if editable then
		editable:Destroy()
	end
	return nil
end

local function pixelColor(color: Color3): number
	return 0xFF000000
		+ math.round(color.R * 255)
		+ math.round(color.G * 255) * 0x100
		+ math.round(color.B * 255) * 0x10000
end

local function topTexture(packet: string, color: Color3, style, rgb: boolean?)
	local editable
	local ok, texture = pcall(function()
		local size = Vector2.one * Data.TextureSize
		editable = AssetService:CreateEditableImage({ Size = size })
		if not editable then
			return nil
		end
		local runs = EncodingService:Base64Decode(buffer.fromstring(packet))
		local pixels = buffer.create(size.X * size.Y * 4)
		local ink = if style and style.Ink then Color3.fromHex(style.Ink) else BLACK
		local pixel = 0
		for i = 0, buffer.len(runs) - 1, if rgb then 4 else 2 do
			local first = buffer.readu8(runs, i + 1)
			local rgba = if rgb
				then 0xFF000000 + first + buffer.readu8(runs, i + 2) * 0x100 + buffer.readu8(runs, i + 3) * 0x10000
				else pixelColor(color:Lerp(ink, 1 - first / 255))
			for _ = 0, buffer.readu8(runs, i) do
				buffer.writeu32(pixels, pixel, rgba)
				pixel += 4
			end
		end
		assert(pixel == buffer.len(pixels), "Top texture has the wrong pixel count")
		if style then
			-- Flat color swatches sit above the top panel's UV island.
			local swatches = {
				pixelColor(color),
				pixelColor(if rgb then Color3.fromHex(style.Rim) else color:Lerp(BLACK, 0.27)),
				pixelColor(Color3.fromHex(style.Bevel)),
			}
			for i, rgba in swatches do
				for y = 0, 4 do
					for x = 8 + (i - 1) * 20, 20 + (i - 1) * 20 do
						buffer.writeu32(pixels, (y * size.X + x) * 4, rgba)
					end
				end
			end
		end
		editable:WritePixelsBuffer(Vector2.zero, size, pixels)
		return Content.fromObject(editable)
	end)
	if ok then
		return texture
	end
	if editable then
		editable:Destroy()
	end
	return nil
end

task.spawn(function()
	for typeId, style in Data.Styles do
		TOP_TEXTURES[typeId] = topTexture(style.Texture, Color3.fromHex(style.Body))
	end
	for typeId, style in Rare.Styles do
		TOP_TEXTURES[typeId] = topTexture(style.Texture, Color3.fromHex(style.Body), style)
	end
	for typeId, style in Epic.Styles do
		TOP_TEXTURES[typeId] = topTexture(style.Texture, Color3.fromHex(style.Body), style, true)
	end
	local allowed, firstMesh = pcall(AssetService.CreateEditableMesh, AssetService)
	if allowed and firstMesh then
		local bodyPalette = { Color3.fromHex("#E1E1E1"), Color3.fromHex("#B2B2B2"), WHITE, WHITE }
		for tier, packet in Data.Bodies do
			BODIES[tier] = meshTemplate(packet, bodyPalette, true, if tier == 1 then firstMesh else nil)
			MARKS[tier] = meshTemplate(Data.Marks[tier], if tier == 7 then { STAR_RIM, GOLD } else { PIP })
		end
		for tier, packet in Rare.Bodies do
			RARE_BODIES[tier] = meshTemplate(packet, { WHITE, WHITE, WHITE, WHITE }, true, nil, true)
			RARE_MARKS[tier] = meshTemplate(Rare.Marks[tier], { WHITE })
		end
		for tier, packet in Epic.Bodies do
			EPIC_BODIES[tier] = meshTemplate(packet, { WHITE, WHITE, WHITE, WHITE }, true, nil, true)
		end
		for tier, packet in Epic.Marks do
			EPIC_MARKS[tier] = meshTemplate(packet, { WHITE })
		end
		for typeId, ornament in Epic.Ornaments do
			local palette = {}
			for i, hex in ornament.Palette do
				palette[i] = Color3.fromHex(hex)
			end
			EPIC_ORNAMENTS[typeId] = meshTemplate(ornament.Mesh, palette)
		end
		iceChips = meshTemplate(Data.Ice, { Color3.fromHex("#245C8C"), Color3.fromHex("#58C9F1") })
	end
	loading = false
	ready:Fire()
end)

local function cloneMesh(template, parent: Instance, anchor: BasePart, name: string, color: Color3)
	local mesh = template.Part:Clone()
	local scale = anchor.Size.X / AUTHORED_SIZE
	mesh.Name = name
	mesh.Color = color
	mesh.Size *= scale
	mesh.CFrame = anchor.CFrame * CFrame.new(template.Offset * scale)
	mesh.Parent = parent
	return mesh
end

local function applyMeshes(anchor: BasePart, visuals: Instance, typeId: string, layout: number): boolean
	local epic = Epic.Styles[typeId]
	local style = Rare.Styles[typeId]
	local body = if epic then EPIC_BODIES[layout] elseif style then RARE_BODIES[layout] else BODIES[layout]
	local marks = if epic then EPIC_MARKS[layout] elseif style then RARE_MARKS[layout] else MARKS[layout]
	local texture = TOP_TEXTURES[typeId]
	if not (body and marks and texture) then
		return false
	end
	-- The templates use their full-size offsets even if they arrive mid-animation.
	local model = anchor:FindFirstAncestorOfClass("Model")
	local scale = if model then model:GetScale() else 1
	if model and scale ~= 1 then
		model:ScaleTo(1)
	end
	cloneMesh(body, visuals, anchor, "ChamferedBody", WHITE).TextureContent = texture
	-- Limit bloom so each star point and each pip in the six-pip grid stays distinct.
	local mark = cloneMesh(
		marks,
		visuals,
		anchor,
		if layout == 7 then "Stars" else "Pips",
		if epic or style then Color3.fromHex((epic or style).Pip):Lerp(BLACK, 0.24) else WHITE
	)
	if style or epic then
		mark.Material = Enum.Material.Neon
	end
	if epic then
		local ornament = EPIC_ORNAMENTS[typeId]
		if ornament then
			cloneMesh(ornament, visuals, anchor, Epic.Ornaments[typeId].Name, WHITE)
		end
	end
	if typeId == "C06" and iceChips then
		cloneMesh(iceChips, visuals, anchor, "IceChips", WHITE)
	end
	if model and scale ~= 1 then
		model:ScaleTo(scale)
	end
	anchor.Transparency = 1
	return true
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
			local star = symbol(surface, "Star", "★", if rare then pipColor else GOLD, 0.5, 0.46)
			star.ZIndex = 2
			star.TextStrokeColor3 = if epic then Color3.fromHex(style.Rim) else STAR_RIM
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
				pip.Position = UDim2.fromScale(0.5 + slot[1] / 2.5, 0.5 - slot[2] / 2.5)
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
	local epic = Epic.Styles[typeId]
	local style = epic or Rare.Styles[typeId] or Data.Styles[typeId]
	local target: Instance = visuals
	if style and style.Name then
		local variant = Instance.new("Model")
		variant.Name = string.format("%s_%02d", style.Name, tier)
		variant.WorldPivot = anchor.CFrame
		variant.Parent = visuals
		target = variant
	end
	if style and applyMeshes(anchor, target, typeId, tier) then
		return
	end

	local fallback = Instance.new("Folder")
	fallback.Name = "SurfaceMarks"
	fallback.Parent = target
	applySurfaces(anchor, fallback, tier, color, style, TOP_TEXTURES[typeId], epic ~= nil)
	if style and loading then
		ready.Event:Once(function()
			if visuals.Parent == anchor then
				if applyMeshes(anchor, target, typeId, tier) then
					fallback:Destroy()
				elseif TOP_TEXTURES[typeId] then
					fallback:ClearAllChildren()
					applySurfaces(anchor, fallback, tier, color, style, TOP_TEXTURES[typeId], epic ~= nil)
				end
			end
		end)
	end
end

return Visuals
