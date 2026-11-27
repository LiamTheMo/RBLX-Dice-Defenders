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
		-- In-match HUD (text-free sheet, native px, whole art, no slicing; keep aspect when scaling).
		GameBar = "rbxassetid://72468083657559", -- Game_StatusBar.png 660x74
		GameDivider = "rbxassetid://105844333790925", -- Game_StatusDivider.png 8x40
		HeartFull = "rbxassetid://81382167662841", -- Game_HeartFull.png 76x76
		HeartEmpty = "rbxassetid://133273395255758", -- Game_HeartEmpty.png 76x76
		UpgradeBlank = "rbxassetid://118016473787372", -- Game_UpgradeBlank.png 128x140
	},
	-- Dice without a thumbnail use the Roll icon tinted with their Display colour.
	Dice = {
		-- Die icons (Assets/UI/new/real items/dice), group-owned Image assets uploaded 2026-11-27 after an imagery review.
		Pebble = "rbxassetid://90518040385188",
		Needle = "rbxassetid://87118450720685",
		Hammer = "rbxassetid://125349373715696",
		Twinshot = "rbxassetid://84721712694180",
		Longshot = "rbxassetid://123336683810037",
		Chill = "rbxassetid://91277319618931",
		Spark = "rbxassetid://118248534001026",
		Emberstorm = "rbxassetid://135782678850108",
		Frost = "rbxassetid://122585480704123",
		Arc = "rbxassetid://123853498712490",
		Volley = "rbxassetid://95243873359428",
		Venom = "rbxassetid://128949119046586",
		Beacon = "rbxassetid://88179916654860",
		Mirror = "rbxassetid://100167778190059",
		Gravity = "rbxassetid://98032181746359",
		Chrono = "rbxassetid://81784102637280",
		Forge = "rbxassetid://102693867803034",
		Astral = "rbxassetid://135295471014042",
		Dragon = "rbxassetid://111461360208634", -- Wyvern (S01)
	},
	-- Boss portraits by variant (HUD "approaches" strip), group-owned Image assets uploaded 2026-11-24.
	Boss = {
		GoblinKing = "rbxthumb://type=Asset&id=96056308738131&w=256&h=256",
		CursedKing = "rbxthumb://type=Asset&id=135490538869758&w=256&h=256",
		CourtJester = "rbxthumb://type=Asset&id=140208999198089&w=256&h=256",
	},
	DieArt = {
		C01 = "Pebble",
		C02 = "Needle",
		C03 = "Hammer",
		C04 = "Twinshot",
		C05 = "Longshot",
		C06 = "Chill",
		C07 = "Spark",
		R01 = "Frost",
		R02 = "Arc",
		R03 = "Volley",
		R04 = "Venom",
		R05 = "Beacon",
		E01 = "Emberstorm",
		E02 = "Mirror",
		E03 = "Gravity",
		L01 = "Chrono",
		L02 = "Forge",
		M01 = "Astral",
		S01 = "Dragon",
	},
}
