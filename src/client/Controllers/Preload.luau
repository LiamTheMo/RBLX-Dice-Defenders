-- Fetch every menu sprite once at join, so no menu opens blank (Roblox only fetches a hidden image when it is first shown).
-- Gathers each "rbxassetid://<digits>" from every ModuleScript under Controllers whose name ends in "Sprites" (a new menu's
-- sprite table is picked up automatically) and preloads them in one call. Hud holds its loading overlay until Finished.
-- Preload.Done (boolean), Preload.Finished (Signal, fired once). Capped, so a broken asset can never lock a player out.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Core.Signal)

local CAP = 20 -- seconds (tune): let the player in even if PreloadAsync has not returned

local Preload = { Done = false, Finished = Signal.new() }

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
		local labels = {}
		for _, id in Preload.collect(tables) do
			local l = Instance.new("ImageLabel")
			l.Image = id
			table.insert(labels, l)
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, labels)
		for _, l in labels do
			l:Destroy()
		end
		finish()
	end)
end

return Preload
