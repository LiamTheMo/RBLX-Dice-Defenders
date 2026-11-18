-- Roll menu sprite asset ids. Chrome (window, panels, rows, chip, bar) is code-drawn (Bag/Chrome); tabs, close X, rarity pills and
-- gems are shared (Shell, Parts, Sprites.Gem). Only this menu's own fixed-shape art is listed; every asset draws whole at its native aspect.
-- NEW (cut by tools/slice_roll.py from Assets/UI/new/roll menu/sheets/roll-elements.png, Assets/UI/new/roll menu/export/Roll_<Name>.png):
-- HeaderPlate, PityPill, BtnGold, BtnPurple, BtnGrey, Info, Die1, Dice3. Their ids are "" until the uploader fills them (never guess one); Size = Ink = export px.
-- The crowns and stars keep their earlier uploaded ids (the new sheet draws them only inside its rarity tags; the art differs: 3-point crown, 2 stars); Ink = the opaque box inside Size.
-- Images must be owned by the experience's group (33284082). An empty id renders blank.

return {
	HeaderPlate = { Image = "rbxassetid://98529766207822", Size = Vector2.new(584, 78), Ink = Rect.new(0, 0, 584, 78) }, -- Roll_HeaderPlate.png
	PityPill = { Image = "rbxassetid://74146270684071", Size = Vector2.new(257, 66), Ink = Rect.new(0, 0, 257, 66) }, -- Roll_PityPill.png
	BtnGold = { Image = "rbxassetid://109261846230479", Size = Vector2.new(318, 89), Ink = Rect.new(0, 0, 318, 89) }, -- Roll_BtnGold.png
	BtnPurple = { Image = "rbxassetid://87066018029602", Size = Vector2.new(321, 90), Ink = Rect.new(0, 0, 321, 90) }, -- Roll_BtnPurple.png
	Info = { Image = "rbxassetid://110902888957458", Size = Vector2.new(81, 80), Ink = Rect.new(0, 0, 81, 80) }, -- Roll_Info.png
	Die1 = { Image = "rbxassetid://138236550582668", Size = Vector2.new(95, 102), Ink = Rect.new(0, 0, 95, 102) }, -- Roll_Die1.png
	Dice3 = { Image = "rbxassetid://90274755357017", Size = Vector2.new(147, 133), Ink = Rect.new(0, 0, 147, 133) }, -- Roll_Dice3.png
	BtnGrey = { Image = "rbxassetid://103134708935976", Size = Vector2.new(304, 91), Ink = Rect.new(0, 0, 304, 91) }, -- Roll_BtnGrey.png
	CrownEpic = {
		Image = "rbxassetid://129116839663225",
		Size = Vector2.new(232, 151),
		Ink = Rect.new(11, 11, 221, 140),
	},
	StarsRare = {
		Image = "rbxassetid://76528779990987",
		Size = Vector2.new(293, 131),
		Ink = Rect.new(11, 11, 282, 120),
	},
	StarCommon = {
		Image = "rbxassetid://140147945031577",
		Size = Vector2.new(157, 152),
		Ink = Rect.new(11, 10, 146, 141),
	},
	CrownGold = {
		Image = "rbxassetid://139649180427601",
		Size = Vector2.new(230, 151),
		Ink = Rect.new(10, 11, 219, 140),
	},
	CrownSecret = {
		Image = "rbxassetid://107214964431114",
		Size = Vector2.new(228, 149),
		Ink = Rect.new(11, 10, 217, 138),
	},
	CrownMythic = {
		Image = "rbxassetid://129063378678628",
		Size = Vector2.new(230, 151),
		Ink = Rect.new(11, 11, 220, 140),
	},
}
