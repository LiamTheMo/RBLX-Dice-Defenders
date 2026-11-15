-- Preload: the pure asset-id walk, and the "*Sprites" discovery rule against the real client tree (every
-- literal asset id in the client must live in a module the rule finds, or its menu opens blank).

local Controllers = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers
local Preload = require(Controllers.Preload)

-- The sprite tables build Vector2 / Rect values the prelude does not stub; the walk only needs them to be non-strings.
Vector2 = Vector2 or {
	new = function(...)
		return { ... }
	end,
}
Rect = Rect or {
	new = function(...)
		return { ... }
	end,
}

local CLIENT = "StarterPlayer/StarterPlayerScripts/Client/"
local CONTROLLERS = CLIENT .. "Controllers/"

local function asSet(list)
	local set, n = {}, 0
	for _, v in list do
		if not set[v] then
			n += 1
		end
		set[v] = true
	end
	return set, n
end

local function nodeAt(key: string)
	local parts = string.split(key, "/")
	local node = game:GetService(parts[1])
	for i = 2, #parts do
		node = node[parts[i]]
	end
	return node
end

test("collect walks nested tables", function()
	local ids = Preload.collect({
		{ Gem = { Image = "rbxassetid://1", Rect = { 0, 0, 10, 10 } } },
		{ { { { "rbxassetid://2" } } } },
		"rbxassetid://3",
	})
	local set, n = asSet(ids)
	expectEq(n, 3, "three ids")
	expectEq(#ids, 3, "no extras")
	for _, id in { "rbxassetid://1", "rbxassetid://2", "rbxassetid://3" } do
		expect(set[id], id)
	end
end)

test("collect dedupes ids across and within tables", function()
	local shared = { Image = "rbxassetid://42" }
	local ids = Preload.collect({
		{ A = shared, B = shared },
		{ C = "rbxassetid://42" },
		{ "rbxassetid://7", "rbxassetid://42" },
	})
	expectEq(#ids, 2, "42 once, 7 once")
end)

test("collect ignores non-asset strings, numbers, booleans and keys", function()
	local ids = Preload.collect({
		"rbxasset://textures/ui/x.png",
		"",
		"Gem",
		"rbxassetid://",
		"rbxassetid://12abc",
		" rbxassetid://5",
		"http://www.roblox.com/asset/?id=5",
		123,
		true,
		false,
		{ ["rbxassetid://9"] = true },
	})
	expectEq(#ids, 0, "nothing collected")
end)

test("collect of empty input is empty", function()
	expectEq(#Preload.collect({}), 0, "{}")
	expectEq(#Preload.collect({ {}, { {} } }), 0, "nested empties")
end)

test("isSpriteModule matches a trailing Sprites only", function()
	for name, want in
		{
			Sprites = true,
			BagSprites = true,
			QuestSprites = true,
			SpritesHelper = false,
			sprites = false,
			Sprite = false,
		}
	do
		expectEq(Preload.isSpriteModule(name), want, name)
	end
end)

test("discovery finds every sprite table, and every client asset id lives in one", function()
	local found = {}
	for key, source in __sources do
		if key:sub(1, #CLIENT) == CLIENT then
			local parts = string.split(key, "/")
			local name = parts[#parts]
			if Preload.isSpriteModule(name) then
				expect(
					key:sub(1, #CONTROLLERS) == CONTROLLERS,
					key .. " is under Controllers (Preload walks only there)"
				)
				found[name] = key
			elseif source:find("rbxassetid://%d") then
				expect(false, key .. " holds an asset id outside a *Sprites module, so Preload misses it")
			end
		end
	end
	local expected = {
		"Sprites",
		"BagSprites",
		"QuestSprites",
		"PlaySprites",
		"RollSprites",
		"ShopSprites",
		"DailySprites",
		"SettingsSprites",
	}
	local tables = {}
	for _, name in expected do
		expect(found[name] ~= nil, name .. " found")
		if found[name] then
			local ids = Preload.collect({ require(nodeAt(found[name])) })
			expect(#ids > 0, name .. " has ids")
		end
	end
	for _, key in found do
		table.insert(tables, require(nodeAt(key)))
	end
	print(("    %d unique asset ids across %d sprite modules"):format(#Preload.collect(tables), #tables))
end)
