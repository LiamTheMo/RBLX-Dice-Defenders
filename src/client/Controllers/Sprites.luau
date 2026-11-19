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
	-- Elemental die art, one icon per die cut from bag menu/sheets/dice-icons-clean.png (the only source covering all 10 in one style):
	-- awaiting upload. Only dice listed in DieArt use it; other dice show Icon.Roll tinted with their Display colour.
	Dice = {
		Astral = "rbxthumb://type=Asset&id=100392198939888&w=420&h=420",
		Dragon = "rbxthumb://type=Asset&id=140058325428836&w=420&h=420",
		Sun = "rbxassetid://92375704626493", -- HUD_Die_Sun.png
		Ice = "rbxassetid://137551370057628", -- HUD_Die_Ice.png
		Fire = "rbxassetid://92126709791096", -- HUD_Die_Fire.png
		Leaf = "rbxassetid://78696450481883", -- HUD_Die_Leaf.png
		Lightning = "rbxassetid://105735192413916", -- HUD_Die_Lightning.png
		Wind = "rbxassetid://125939635765640", -- HUD_Die_Wind.png
		Rock = "rbxassetid://140000197910693", -- HUD_Die_Rock.png
		Water = "rbxassetid://84790101174995", -- HUD_Die_Water.png
		Light = "rbxassetid://95604252012939", -- HUD_Die_Light.png
		Shadow = "rbxassetid://101027605408362", -- HUD_Die_Shadow.png
	},
	DieArt = {
		M01 = "Astral",
		S01 = "Dragon",
		L04 = "Sun",
		E06 = "Ice",
		L05 = "Fire",
		E07 = "Leaf",
		E08 = "Lightning",
		R06 = "Wind",
		R07 = "Rock",
		E09 = "Water",
		L06 = "Light",
		E10 = "Shadow",
	},
}
