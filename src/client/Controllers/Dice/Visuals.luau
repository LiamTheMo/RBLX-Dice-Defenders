local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")

local Data = require(script.Parent.ModelData)

local Visuals = {}

local PIP = Color3.fromHex("#16171B")
local GOLD = Color3.fromHex("#FFD65C")
local STAR_RIM = Color3.fromHex("#32201A")
local WHITE = Color3.new(1, 1, 1)
local BODIES = {}
local MARKS = {}
local ORNAMENTS = {}
local ready = Instance.new("BindableEvent")
local loading = true

function Visuals.Size(typeId: string): number
	return if Data.Styles[typeId] then 2.5 else 4.4
end

local function meshTemplate(packet: string, palette: { Color3 }, firstMesh: EditableMesh?)
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
		for i, p in positions do
			ids[i] = editable:AddVertex(p - center)
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

task.spawn(function()
	local allowed, firstMesh = pcall(AssetService.CreateEditableMesh, AssetService)
	if allowed and firstMesh then
		local bodyPalette = { Color3.fromHex("#E1E1E1"), Color3.fromHex("#B2B2B2"), WHITE }
		for tier, packet in Data.Bodies do
			BODIES[tier] = meshTemplate(packet, bodyPalette, if tier == 1 then firstMesh else nil)
			MARKS[tier] = meshTemplate(Data.Marks[tier], if tier == 7 then { STAR_RIM, GOLD } else { PIP })
		end
		for typeId, style in Data.Styles do
			ORNAMENTS[typeId] =
				meshTemplate(style.Mesh, { Color3.fromHex(style.Colors[1]), Color3.fromHex(style.Colors[2]) })
		end
	end
	loading = false
	ready:Fire()
end)

local function cloneMesh(template, parent: Folder, anchor: BasePart, name: string, color: Color3)
	local mesh = template.Part:Clone()
	mesh.Name = name
	mesh.Color = color
	mesh.CFrame = anchor.CFrame * CFrame.new(template.Offset)
	mesh.Parent = parent
end

local function applyMeshes(anchor: BasePart, visuals: Folder, typeId: string, layout: number, color: Color3): boolean
	local body, marks, ornaments = BODIES[layout], MARKS[layout], ORNAMENTS[typeId]
	if not (body and marks and ornaments) then
		return false
	end
	cloneMesh(body, visuals, anchor, "ChamferedBody", color)
	cloneMesh(marks, visuals, anchor, if layout == 7 then "Stars" else "Pips", WHITE)
	cloneMesh(ornaments, visuals, anchor, "Ornaments", WHITE)
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
local function applySurfaces(anchor: BasePart, fallback: Folder, tier: number, color: Color3, style)
	anchor.Color = if style then Color3.fromHex(style.Body) else WHITE
	anchor.Transparency = 0
	for _, face in Enum.NormalId:GetEnumItems() do
		local surface = Instance.new("SurfaceGui")
		surface.Name = face.Name
		surface.Face = face
		surface.Adornee = anchor
		surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		surface.CanvasSize = Vector2.new(128, 128)
		surface.LightInfluence = 0.25
		if style then
			if face.Name == style.Face or face == Enum.NormalId.Top then
				symbol(surface, "Ornament", style.Mark, Color3.fromHex(style.Colors[1]), 0.15, 0.15)
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
			local star = symbol(surface, "Star", "★", GOLD, 0.5, 0.46)
			star.TextStrokeColor3 = STAR_RIM
			star.TextStrokeTransparency = 0
		else
			for i, slot in Data.Layouts[tier] do
				local pip = Instance.new("Frame")
				pip.Name = "Pip" .. i
				pip.AnchorPoint = Vector2.new(0.5, 0.5)
				pip.Position = UDim2.fromScale(0.5 + slot[1] / 2.5, 0.5 - slot[2] / 2.5)
				pip.Size = UDim2.fromScale(0.176, 0.176)
				pip.BorderSizePixel = 0
				pip.BackgroundColor3 = PIP
				pip.Parent = surface
				local round = Instance.new("UICorner")
				round.CornerRadius = UDim.new(0.5, 0)
				round.Parent = pip
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
	local style = Data.Styles[typeId]
	local bodyColor = if style then Color3.fromHex(style.Body) else WHITE
	if style and applyMeshes(anchor, visuals, typeId, tier, bodyColor) then
		return
	end

	local fallback = Instance.new("Folder")
	fallback.Name = "SurfaceMarks"
	fallback.Parent = visuals
	applySurfaces(anchor, fallback, tier, color, style)
	if style and loading then
		ready.Event:Once(function()
			if visuals.Parent == anchor and applyMeshes(anchor, visuals, typeId, tier, bodyColor) then
				fallback:Destroy()
			end
		end)
	end
end

return Visuals
