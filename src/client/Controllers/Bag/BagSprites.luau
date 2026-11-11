-- Bag menu sprite asset ids: the one place to swap Bag art.
-- Source PNGs: Assets/UI/bag menu/export/Bag_<Name>.png, cut from the sheets by tools/slice_bag.py (sizes and
-- Slice values below are copied from its export/manifest.json; Size and Slice are export pixels).
-- Images must be owned by the experience's group (33284082): a user-owned image fails in-game with
-- "Requester does not have permission". An empty id renders blank; never guess an id.
-- Slice = SliceCenter for 9-slice sprites only (corner arc measured on the export); no Slice = draw unsliced.

return {
	Window = {
		Image = "rbxassetid://127348078735613",
		Size = Vector2.new(1023, 452),
		Slice = Rect.new(44, 44, 977, 409),
	},
	LeftPanel = {
		Image = "rbxassetid://85445124955125",
		Size = Vector2.new(586, 459),
		Slice = Rect.new(41, 40, 547, 419),
	},
	Detail = {
		Image = "rbxassetid://119103475886794",
		Size = Vector2.new(305, 459),
		Slice = Rect.new(34, 35, 271, 422),
	},
	Strip = { Image = "rbxassetid://101790827789779", Size = Vector2.new(609, 139), Slice = Rect.new(40, 39, 569, 99) },
	TabPurple = {
		Image = "rbxassetid://86739775196437",
		Size = Vector2.new(607, 141),
		Slice = Rect.new(42, 41, 566, 105),
	},
	TabGold = {
		Image = "rbxassetid://139745849357913",
		Size = Vector2.new(607, 141),
		Slice = Rect.new(42, 41, 566, 105),
	},
	BtnGreen = {
		Image = "rbxassetid://106029084329385",
		Size = Vector2.new(262, 112),
		Slice = Rect.new(36, 35, 227, 81),
	},
	BtnRed = { Image = "rbxassetid://138971710058931", Size = Vector2.new(262, 114), Slice = Rect.new(37, 36, 226, 81) },
	BtnGold = {
		Image = "rbxassetid://137816866055300",
		Size = Vector2.new(262, 113),
		Slice = Rect.new(37, 34, 226, 82),
	},
	BtnPurple = {
		Image = "rbxassetid://133775390142257",
		Size = Vector2.new(262, 114),
		Slice = Rect.new(36, 35, 226, 81),
	},
	Search = { Image = "rbxassetid://128312059815872", Size = Vector2.new(807, 107), Slice = Rect.new(43, 42, 765, 67) },
	Sort = { Image = "rbxassetid://129617928284570", Size = Vector2.new(514, 122), Slice = Rect.new(41, 39, 392, 85) },
	CardIdle = {
		Image = "rbxassetid://78924107352264",
		Size = Vector2.new(262, 262),
		Slice = Rect.new(37, 37, 225, 228),
	},
	CardSelected = {
		Image = "rbxassetid://85888918505065",
		Size = Vector2.new(264, 262),
		Slice = Rect.new(40, 40, 224, 226),
	},
	Close = { Image = "rbxassetid://112008310949168", Size = Vector2.new(150, 142) },
	LevelTrack = {
		Image = "rbxassetid://72081878542807",
		Size = Vector2.new(695, 95),
		Slice = Rect.new(38, 39, 657, 57),
	},
	LevelFill = {
		Image = "rbxassetid://124108511162940",
		Size = Vector2.new(527, 59),
		Slice = Rect.new(22, 25, 504, 36),
	},
	Ribbon = { Image = "rbxassetid://71675040842911", Size = Vector2.new(698, 190) },
	BagDie = { Image = "rbxassetid://81557477067385", Size = Vector2.new(371, 516) },
	PillGold = {
		Image = "rbxassetid://122511019025810",
		Size = Vector2.new(262, 89),
		Slice = Rect.new(38, 35, 224, 53),
	},
	PillPurple = {
		Image = "rbxassetid://111293973532512",
		Size = Vector2.new(253, 89),
		Slice = Rect.new(37, 36, 215, 54),
	},
	PillBlue = { Image = "rbxassetid://92798793301779", Size = Vector2.new(258, 89), Slice = Rect.new(37, 36, 221, 54) },
	PillGreen = {
		Image = "rbxassetid://119582575597286",
		Size = Vector2.new(260, 89),
		Slice = Rect.new(38, 36, 224, 52),
	},
	PillGrey = {
		Image = "rbxassetid://71636900265653",
		Size = Vector2.new(258, 89),
		Slice = Rect.new(38, 35, 220, 55),
	},
	PillPink = { Image = "rbxassetid://83397183525264", Size = Vector2.new(258, 89), Slice = Rect.new(37, 35, 220, 53) },
	QtyMinus = {
		Image = "rbxassetid://84219220695849",
		Size = Vector2.new(161, 139),
		Slice = Rect.new(34, 33, 127, 105),
	},
	QtyField = {
		Image = "rbxassetid://80579013839188",
		Size = Vector2.new(468, 126),
		Slice = Rect.new(31, 31, 438, 96),
	},
	QtyPlus = {
		Image = "rbxassetid://114382493426663",
		Size = Vector2.new(161, 140),
		Slice = Rect.new(38, 34, 123, 103),
	},
	IconDice = { Image = "rbxassetid://81727233237331", Size = Vector2.new(233, 258) },
	IconCrystals = { Image = "rbxassetid://123282159756164", Size = Vector2.new(260, 250) },
	IconPotion = { Image = "rbxassetid://100621603986778", Size = Vector2.new(200, 264) },
	IconCrown = { Image = "rbxassetid://98620169484054", Size = Vector2.new(263, 202) },
	Lock = { Image = "rbxassetid://109118979321599", Size = Vector2.new(112, 132) },
	Coins = { Image = "rbxassetid://106285514552586", Size = Vector2.new(133, 111) },
	Check = { Image = "rbxassetid://113255952705328", Size = Vector2.new(134, 110) },
	Magnifier = { Image = "rbxassetid://103114099809379", Size = Vector2.new(121, 133) },
	SortArrows = { Image = "rbxassetid://132745033924739", Size = Vector2.new(133, 100) },
	Flask = { Image = "rbxassetid://129393083346064", Size = Vector2.new(198, 222) },
	GlowCommon = { Image = "rbxassetid://93110762135131", Size = Vector2.new(512, 506) },
	GlowUncommon = { Image = "rbxassetid://94527136234963", Size = Vector2.new(512, 506) },
	GlowRare = { Image = "rbxassetid://105781621758443", Size = Vector2.new(512, 506) },
	GlowEpic = { Image = "rbxassetid://108076679893522", Size = Vector2.new(512, 506) },
	GlowLegendary = { Image = "rbxassetid://131427367497685", Size = Vector2.new(512, 506) },
	GlowMythic = { Image = "rbxassetid://94893574634404", Size = Vector2.new(512, 506) },
	GlowSecret = { Image = "rbxassetid://113012067568804", Size = Vector2.new(512, 506) },
}
