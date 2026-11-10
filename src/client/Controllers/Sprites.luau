-- Lobby HUD sprite asset ids: the one place to swap HUD art.
-- Source PNGs: Assets/UI/lobby HUD/export/<Name>.png, cut from the sheets by tools/slice_lobby_hud.py.
-- Images must be owned by the experience's group (33284082): a user-owned image fails in-game with
-- "Requester does not have permission". An empty id renders blank; never guess an id.

return {
	Frame = {
		Normal = "rbxassetid://80393414939954",
		Pressed = "rbxassetid://118760999098769",
		Highlighted = "rbxassetid://100534808336717",
		Disabled = "rbxassetid://131266246742978",
	},
	Icon = {
		Shop = "rbxassetid://100560956902187",
		Roll = "rbxassetid://114472853367162",
		Bag = "rbxassetid://90244048949141",
		Play = "rbxassetid://113023981750011",
		Codes = "rbxassetid://79544216881940",
		Daily = "rbxassetid://118089544403082",
		Quests = "rbxassetid://85341582897204",
		Settings = "rbxassetid://77321474703307",
	},
	Coin = "rbxassetid://75834021973843",
	Gem = "rbxassetid://86675405032065",
	XpTrack = "rbxassetid://131522632371494",
	XpFill = "rbxassetid://86801745416878",
	-- Elemental die art. Only dice listed in DieArt use it; other dice show Icon.Roll tinted
	-- with their Display colour.
	Dice = {
		Sun = "rbxassetid://138145319780314",
		Ice = "rbxassetid://127027200377323",
		Fire = "rbxassetid://128462787030188",
		Leaf = "rbxassetid://84541409461636",
		Lightning = "rbxassetid://85075259461674",
	},
	DieArt = {
		R01 = "Ice", -- Frost
		R02 = "Lightning", -- Arc
		E01 = "Fire", -- Emberstorm
	},
}
