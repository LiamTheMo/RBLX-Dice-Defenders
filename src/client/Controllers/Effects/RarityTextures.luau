local AssetService = game:GetService("AssetService")

local Textures = {}
local sources = {}
local RESOLUTION = 48
local SIZE = Vector2.one * RESOLUTION

local function distance(point: Vector2, start: Vector2, finish: Vector2): number
	local edge = finish - start
	local t = math.clamp((point - start):Dot(edge) / edge:Dot(edge), 0, 1)
	return (point - start - edge * t).Magnitude
end

local function snowflake()
	local branches = {}
	for i = 0, 5 do
		local angle = i * math.pi / 3
		local direction = Vector2.new(math.cos(angle), math.sin(angle))
		table.insert(branches, { Vector2.zero, direction * 0.79 })
		for _, side in { -1, 1 } do
			local branchAngle = angle + side * math.pi / 3
			local start = direction * 0.42
			table.insert(branches, {
				start,
				start + Vector2.new(math.cos(branchAngle), math.sin(branchAngle)) * 0.27,
			})
		end
	end
	return function(point)
		local nearest = math.huge
		for _, branch in branches do
			nearest = math.min(nearest, distance(point, branch[1], branch[2]))
		end
		return math.clamp((0.061 - nearest) * 30, 0, 1)
	end
end

local function texture(kind: string)
	if sources[kind] ~= nil then
		return sources[kind]
	end
	local editable
	local ok, result = pcall(function()
		editable = AssetService:CreateEditableImage({ Size = SIZE })
		if not editable then
			return nil
		end
		local alpha = if kind == "Snowflake"
			then snowflake()
			else function(point)
				local radius = point.Magnitude
				return 0.82 * math.exp(-9 * radius * radius) * math.clamp((1 - radius) * 4, 0, 1)
			end
		local data = buffer.create(RESOLUTION * RESOLUTION * 4)
		for y = 0, RESOLUTION - 1 do
			for x = 0, RESOLUTION - 1 do
				local point = (Vector2.new(x, y) + Vector2.one * 0.5) / RESOLUTION * 2 - Vector2.one
				local opacity = math.clamp(alpha(point), 0, 1)
				buffer.writeu32(data, (y * RESOLUTION + x) * 4, math.round(255 * opacity) * 0x1000000 + 0xFFFFFF)
			end
		end
		editable:WritePixelsBuffer(Vector2.zero, SIZE, data)
		return { content = Content.fromObject(editable), image = editable }
	end)
	if not ok and editable then
		editable:Destroy()
	end
	sources[kind] = if ok and result then result else false
	return sources[kind]
end

function Textures.Create(parent: BasePart, kind: string, color: Color3)
	local source = texture(kind)
	if not source then
		return nil
	end
	local anchor = Instance.new("Attachment")
	anchor.Name = kind
	anchor.Parent = parent
	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = anchor
	billboard.LightInfluence = 0
	billboard.Enabled = false
	billboard.Parent = anchor
	local image = Instance.new("ImageLabel")
	image.ImageContent = source.content
	image.ImageColor3 = color
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Parent = billboard
	return { anchor = anchor, billboard = billboard, image = image }
end

function Textures.Show(sprite, position: Vector3, scale: number, opacity: number)
	sprite.anchor.WorldPosition = position
	sprite.billboard.Size = UDim2.fromScale(scale, scale)
	sprite.image.ImageTransparency = 1 - math.clamp(opacity, 0, 1)
	sprite.billboard.Enabled = opacity > 0
end

return Textures
