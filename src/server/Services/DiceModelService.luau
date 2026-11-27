-- Loads every uploaded die model (Shared.DiceAssets) into ReplicatedStorage.DiceModels so clients clone real MeshParts
-- instead of building editable meshes (their memory budget cannot hold all dice). Models are named "<typeId>_<tier>".
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.DiceAssets)

local DiceModelService = {}

local NEON_SUFFIX = {
	Gem = true,
	Eye = true,
	EyeL = true,
	EyeR = true,
	Drip = true,
	DripHi = true,
	Marks = true,
	Pips = true,
	Stars = true,
	Core = true,
	Glow = true,
}
local RETRIES = 4
local BATCH = 12

-- Roblox imports glb colour-only materials as grey and tints textured parts with it: restore Common/Rare colours from
-- the generated table and make every textured part white.
local function paint(model: Model, typeId: string, tier: number)
	local colours = Assets.Colors[typeId] and Assets.Colors[typeId][tier]
	for _, part in model:GetDescendants() do
		if part:IsA("MeshPart") then
			local hex
			if colours and part.TextureID == "" then
				local slot = part.Name:match("Body%.%d%d%d(%d?)$")
				if slot then
					hex = colours[if slot == "" then 1 else tonumber(slot) :: number]
				elseif part.Name:find("Marks") or part.Name:find("Pips") or part.Name:find("Stars") then
					hex = colours[#colours]
				end
			end
			part.Color = if hex and hex ~= "" then Color3.fromHex(hex) else Color3.new(1, 1, 1)
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
			local suffix = part.Name:gsub("%.%d+$", ""):match("(%a+)%d*$")
			part.Material = if typeId:sub(1, 1) ~= "C" and NEON_SUFFIX[suffix]
				then Enum.Material.Neon
				else Enum.Material.SmoothPlastic
		end
	end
end

local function loadOne(folder: Folder, typeId: string, tier: number, assetId: number)
	for attempt = 1, RETRIES do
		local ok, container = pcall(InsertService.LoadAsset, InsertService, assetId)
		if ok then
			local model = container:FindFirstChildOfClass("Model")
			if model then
				model.Name = typeId .. "_" .. tier
				paint(model, typeId, tier)
				model.Parent = folder
				container:Destroy()
				return
			end
			container:Destroy()
		end
		task.wait(attempt * 2)
	end
	warn(("[DiceModelService] could not load %s tier %d (asset %d)"):format(typeId, tier, assetId))
end

function DiceModelService.Init()
	local folder = Instance.new("Folder")
	folder.Name = "DiceModels"
	folder.Parent = ReplicatedStorage

	local jobs = {}
	for typeId, ids in Assets.Models do
		for tier, assetId in ids do
			table.insert(jobs, { typeId, tier, assetId })
		end
	end
	table.sort(jobs, function(a, b)
		return if a[2] ~= b[2] then a[2] < b[2] else a[1] < b[1] -- low tiers first: they are what a fresh match shows
	end)
	task.spawn(function()
		for first = 1, #jobs, BATCH do
			local pending = 0
			for i = first, math.min(first + BATCH - 1, #jobs) do
				pending += 1
				task.spawn(function()
					loadOne(folder, jobs[i][1], jobs[i][2], jobs[i][3])
					pending -= 1
				end)
			end
			while pending > 0 do
				task.wait()
			end
		end
		folder:SetAttribute("Ready", true)
	end)
end

return DiceModelService
