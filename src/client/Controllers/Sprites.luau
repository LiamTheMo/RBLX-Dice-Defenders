-- Lobby HUD sprite asset ids: the one place to swap HUD art.
-- Source PNGs: Assets/UI/lobby HUD/export/<Name>.png, cut from the sheets by tools/slice_lobby_hud.py.
-- Images must be owned by the experience's group (33284082): a user-owned image fails in-game with
-- "Requester does not have permission". An empty id renders blank; never guess an id.

return {
	Frame = {
		Normal = "rbxassetid://92989738398676",
		Pressed = "rbxassetid://83972505597052",
		Highlighted = "rbxassetid://114715455425249",
		Disabled = "rbxassetid://126677670648470",
	},
	Icon = {
		Shop = "rbxassetid://136091975378695",
		Roll = "rbxassetid://88652498791402",
		Bag = "rbxassetid://109669445687992",
		Play = "rbxassetid://128965276160933",
		Codes = "rbxassetid://74109008812258",
		Daily = "rbxassetid://109962548987845",
		Quests = "rbxassetid://98989594468537",
		Settings = "rbxassetid://85507248580399",
	},
	Coin = "rbxassetid://130085489748233",
	Gem = "rbxassetid://108015364836270",
	XpTrack = "rbxassetid://81408180099705", -- export 143x24
	XpFill = "rbxassetid://71158637905066", -- export 112x16
	-- Elemental die art. Only dice listed in DieArt use it; other dice show Icon.Roll tinted
	-- with their Display colour.
	Dice = {
		Sun = "rbxassetid://122873795000099",
		Ice = "rbxassetid://124076903041822",
		Fire = "rbxassetid://81256788562241",
		Leaf = "rbxassetid://75319378635825",
		Lightning = "rbxassetid://71178139321035",
	},
	DieArt = {
		R01 = "Ice", -- Frost
		R02 = "Lightning", -- Arc
		E01 = "Fire", -- Emberstorm
	},
}
