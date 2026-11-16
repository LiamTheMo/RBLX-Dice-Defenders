-- Fetch every menu sprite once at join, so no menu opens blank (Roblox only fetches a hidden image when it is first shown).
-- Gathers each "rbxassetid://<digits>" from every ModuleScript under Controllers whose name ends in "Sprites" (a new menu's
-- sprite table is picked up automatically) and preloads them in one call, then draws each once under Hud's loading
-- message so its texture is decoded before any menu shows it. Hud holds its loading overlay until Finished.
-- Preload.Done (boolean), Preload.Finished (Signal, fired once). Capped, so a broken asset can never lock a player out.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Core.Signal)

local CAP = 20 -- seconds (tune): download + warm-up; let the player in even if either has not finished

local Preload = { Done = false, Finished = Signal.new() }
local warmup = nil -- ScreenGui of warm-up labels; destroyed before the loading message hides

function Preload.isSpriteModule(name: string): boolean
	return name:sub(-7) == "Sprites"
end

-- Every distinct asset id string in the given tables, nested at any depth; anything else is ignored.
function Preload.collect(tables: { any }): { string }
	local ids, seen = {}, {}
	local function walk(t)
		for _, v in t do
			if type(v) == "table" then
				walk(v)
			elseif type(v) == "string" and v:match("^rbxassetid://%d+$") and not seen[v] then
				seen[v] = true
				table.insert(ids, v)
			end
		end
	end
	walk(tables)
	return ids
end

local function finish()
	if warmup then
		warmup:Destroy()
	end
	if not Preload.Done then
		Preload.Done = true
		Preload.Finished:Fire()
	end
end

function Preload.Init()
	task.delay(CAP, finish) -- in Init: the Loader runs every Init before any Start, so a stalled Start cannot hold the cap
end

function Preload.Start()
	task.spawn(function()
		local tables = {}
		for _, module in script.Parent:GetDescendants() do
			if module:IsA("ModuleScript") and Preload.isSpriteModule(module.Name) then
				table.insert(tables, require(module))
			end
		end
		-- Throwaway ImageLabels: plain id strings report Failure in Studio.
		local labels, failed = {}, {}
		for _, id in Preload.collect(tables) do
			local l = Instance.new("ImageLabel")
			l.Image = id
			table.insert(labels, l)
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, labels, function(id, status)
			if status ~= Enum.AssetFetchStatus.Success then
				failed[id] = true -- never loads: don't wait for it
			end
		end)
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		if Preload.Done then
			return -- capped mid-download: the message is already gone, so nothing may be drawn under it
		end
		-- Downloaded is not decoded: a texture is only decoded on its first draw. Draw every id once, opaque and on
		-- screen but under Hud's opaque loading message (DisplayOrder 7, same safe area), until all report IsLoaded.
		warmup = Instance.new("ScreenGui")
		warmup.Name = "PreloadWarmup"
		warmup.DisplayOrder = 5
		warmup.ResetOnSpawn = false
		warmup.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
		local box = Instance.new("Frame")
		box.BackgroundTransparency = 1
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.5)
		box.Size = UDim2.fromOffset(64, 64)
		box.Parent = warmup
		for _, l in labels do
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(1, 1)
			l.Parent = box
		end
		warmup.Parent = playerGui
		local function ready()
			for _, l in labels do
				if not (l.IsLoaded or failed[l.Image]) then
					return false
				end
			end
			return true
		end
		repeat
			task.wait(0.1)
		until Preload.Done or ready()
		finish()
	end)
end

return Preload
