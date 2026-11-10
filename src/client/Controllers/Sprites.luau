-- Lobby HUD sprite asset ids: the one place to swap HUD art.
-- Source PNGs: Assets/UI/lobby HUD/export/<Name>.png, cut from the sheets by tools/slice_lobby_hud.py.
-- Images must be owned by the experience's group (33284082): a user-owned image fails in-game with
-- "Requester does not have permission". An empty id renders blank; never guess an id.

return {
	Frame = {
		Normal = "rbxassetid://78885083802615",
		Pressed = "rbxassetid://89832874276515",
		Highlighted = "rbxassetid://118454597257259",
		Disabled = "rbxassetid://109709376227869",
	},
	Icon = {
		Shop = "rbxassetid://101678974765725",
		Roll = "rbxassetid://82971869068918",
		Bag = "rbxassetid://126517434673889",
		Play = "rbxassetid://83117816055709",
		Codes = "rbxassetid://113696904708255",
		Daily = "rbxassetid://105300166351844",
		Quests = "rbxassetid://82993039644230",
		Settings = "rbxassetid://127440037246685",
	},
	Coin = "rbxassetid://119769142299811",
	Gem = "rbxassetid://115185738155305",
	XpTrack = "rbxassetid://137520320004464",
	XpFill = "rbxassetid://93923674845532",
	-- Elemental die art. Only dice listed in DieArt use it; other dice show Icon.Roll tinted
	-- with their Display colour.
	Dice = {
		Sun = "rbxassetid://83115626898237",
		Ice = "rbxassetid://112437489106031",
		Fire = "rbxassetid://71945614012149",
		Leaf = "rbxassetid://134654090367466",
		Lightning = "rbxassetid://87540072697942",
	},
	DieArt = {
		R01 = "Ice", -- Frost
		R02 = "Lightning", -- Arc
		E01 = "Fire", -- Emberstorm
	},
}
