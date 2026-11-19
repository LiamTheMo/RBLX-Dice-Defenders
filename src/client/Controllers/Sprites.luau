-- Lobby HUD sprite asset ids: the one place to swap HUD art.
-- Source PNGs: Assets/UI/new/lobby hud/export/HUD_<Name>.png, cut by tools/slice_lobby_hud.py (native sizes are in LobbyHud and in export/manifest.json).
-- Images must be owned by the experience's group (33284082): a user-owned image fails in-game with
-- "Requester does not have permission". An empty id renders blank; never guess an id.
-- Kept free of Vector2/Rect: the specs require this module headless.

return {
	-- Borderless glyphs still read by the menus (Roll, Bag, Play, Codes, Daily); the HUD's own tiles are Hud below.
	Icon = {
		Roll = "rbxassetid://88652498791402",
		Bag = "rbxassetid://109669445687992",
		Play = "rbxassetid://128965276160933",
		Codes = "rbxassetid://74109008812258",
		Daily = "rbxassetid://109962548987845",
	},
	Coin = "rbxassetid://132885018986924", -- Shared_Coin.png
	Gem = "rbxassetid://116462057129692", -- Shared_Gem.png
	-- HUD tiles (label baked in), deck slot frames, plus and gear: awaiting upload.
	Hud = {
		Shop = "rbxassetid://90341484257657", -- HUD_Shop.png
		Roll = "rbxassetid://139496074840525", -- HUD_Roll.png
		Bag = "rbxassetid://131991531775420", -- HUD_Bag.png
		Play = "rbxassetid://115238837794060", -- HUD_Play.png
		Codes = "rbxassetid://103679373841650", -- HUD_Codes.png
		Daily = "rbxassetid://96058128963367", -- HUD_Daily.png
		Quests = "rbxassetid://90259542489356", -- HUD_Quests.png
		Slot = "rbxassetid://96951884025689", -- HUD_Slot.png (dark fill, white rim)
		SlotGlow = "rbxassetid://133434805661862", -- HUD_SlotGlow.png (purple neon rim: hover)
		SlotGrey = "rbxassetid://86679428947492", -- HUD_SlotGrey.png (lighter grey: loading)
		Plus = "rbxassetid://107677699351348", -- HUD_Plus.png (empty slot)
		Gear = "rbxassetid://121271384774331", -- HUD_Gear.png
	},
	-- Dice without a thumbnail use the Roll icon tinted with their Display colour.
	Dice = {
		Astral = "rbxthumb://type=Asset&id=100392198939888&w=420&h=420",
		Dragon = "rbxthumb://type=Asset&id=140058325428836&w=420&h=420",
	},
	DieArt = {
		M01 = "Astral",
		S01 = "Dragon",
	},
}
