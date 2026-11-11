-- Bag menu sprite asset ids: the one place to swap Bag art.
-- Source PNGs: Assets/UI/bag menu/export/Bag_<Name>.png, cut from the sheets by tools/slice_bag.py (sizes and
-- Slice values below are copied from its export/manifest.json; Size and Slice are export pixels).
-- Images must be owned by the experience's group (33284082): a user-owned image fails in-game with
-- "Requester does not have permission". An empty id renders blank; never guess an id.
-- Slice = SliceCenter for 9-slice sprites only (corner arc measured on the export); no Slice = draw unsliced.

return {
	Banner = { Image = "rbxassetid://76738978316837", Size = Vector2.new(615, 218) },
	Window = {
		Image = "rbxassetid://74635802178347",
		Size = Vector2.new(1024, 454),
		Slice = Rect.new(292, 154, 800, 330),
	},
	LeftPanel = {
		Image = "rbxassetid://112239196711193",
		Size = Vector2.new(588, 461),
		Slice = Rect.new(142, 96, 452, 391),
	},
	Detail = {
		Image = "rbxassetid://91432251836467",
		Size = Vector2.new(307, 461),
		Slice = Rect.new(78, 121, 229, 325),
	},
	Strip = { Image = "rbxassetid://116142876011318", Size = Vector2.new(611, 141), Slice = Rect.new(164, 51, 500, 87) },
	TabPurple = {
		Image = "rbxassetid://123157195681056",
		Size = Vector2.new(502, 120),
		Slice = Rect.new(79, 44, 439, 71),
	},
	TabGold = {
		Image = "rbxassetid://102821520842628",
		Size = Vector2.new(502, 120),
		Slice = Rect.new(107, 48, 391, 72),
	},
	BtnGreen = {
		Image = "rbxassetid://114519818957405",
		Size = Vector2.new(255, 112),
		Slice = Rect.new(47, 47, 203, 68),
	},
	BtnRed = { Image = "rbxassetid://71905905437194", Size = Vector2.new(252, 112), Slice = Rect.new(60, 44, 206, 68) },
	BtnGold = { Image = "rbxassetid://93484736171044", Size = Vector2.new(255, 112), Slice = Rect.new(48, 42, 190, 65) },
	BtnPurple = {
		Image = "rbxassetid://78674211223111",
		Size = Vector2.new(251, 112),
		Slice = Rect.new(46, 46, 205, 66),
	},
	Search = { Image = "rbxassetid://84614169062062", Size = Vector2.new(821, 112), Slice = Rect.new(65, 50, 754, 62) },
	Sort = { Image = "rbxassetid://123838910993791", Size = Vector2.new(460, 112) },
	CardIdle = {
		Image = "rbxassetid://133458673461541",
		Size = Vector2.new(265, 266),
		Slice = Rect.new(52, 51, 190, 205),
	},
	CardSelected = {
		Image = "rbxassetid://106442954748693",
		Size = Vector2.new(268, 265),
		Slice = Rect.new(89, 57, 187, 207),
	},
	Close = { Image = "rbxassetid://125887242292231", Size = Vector2.new(153, 145) },
	LevelTrack = {
		Image = "rbxassetid://86428448512666",
		Size = Vector2.new(355, 52),
		Slice = Rect.new(41, 23, 307, 29),
	},
	LevelFill = {
		Image = "rbxassetid://138425836297925",
		Size = Vector2.new(270, 34),
		Slice = Rect.new(24, 15, 201, 19),
	},
	Ribbon = { Image = "rbxassetid://71675040842911", Size = Vector2.new(698, 190) },
	BagDie = { Image = "rbxassetid://81557477067385", Size = Vector2.new(371, 516) },
	PillGold = { Image = "rbxassetid://80671828511855", Size = Vector2.new(169, 60), Slice = Rect.new(76, 27, 125, 33) },
	PillPurple = {
		Image = "rbxassetid://80863031745981",
		Size = Vector2.new(164, 60),
		Slice = Rect.new(45, 27, 117, 33),
	},
	PillBlue = {
		Image = "rbxassetid://126648578581928",
		Size = Vector2.new(167, 60),
		Slice = Rect.new(35, 27, 133, 33),
	},
	PillGreen = {
		Image = "rbxassetid://124574406442748",
		Size = Vector2.new(168, 60),
		Slice = Rect.new(38, 27, 112, 33),
	},
	PillGrey = { Image = "rbxassetid://85584125075479", Size = Vector2.new(167, 60), Slice = Rect.new(37, 27, 124, 33) },
	PillPink = {
		Image = "rbxassetid://121575386704300",
		Size = Vector2.new(167, 60),
		Slice = Rect.new(36, 27, 129, 33),
	},
	QtyMinus = { Image = "rbxassetid://84925190750074", Size = Vector2.new(129, 112), Slice = Rect.new(58, 50, 72, 62) },
	QtyField = {
		Image = "rbxassetid://78594440866082",
		Size = Vector2.new(407, 112),
		Slice = Rect.new(161, 47, 308, 62),
	},
	QtyPlus = { Image = "rbxassetid://101301827972870", Size = Vector2.new(128, 112), Slice = Rect.new(54, 50, 89, 71) },
	IconDice = { Image = "rbxassetid://70520619812748", Size = Vector2.new(243, 268) },
	IconCrystals = { Image = "rbxassetid://100436479051738", Size = Vector2.new(262, 252) },
	IconPotion = { Image = "rbxassetid://87955663373193", Size = Vector2.new(204, 268) },
	IconCrown = { Image = "rbxassetid://115530210137734", Size = Vector2.new(266, 205) },
	Lock = { Image = "rbxassetid://97572278907033", Size = Vector2.new(116, 136) },
	Coins = { Image = "rbxassetid://107094953753317", Size = Vector2.new(137, 115) },
	Check = { Image = "rbxassetid://84308256154435", Size = Vector2.new(138, 115) },
	Magnifier = { Image = "rbxassetid://100509891805364", Size = Vector2.new(105, 103) },
	SortArrows = { Image = "rbxassetid://123586293497993", Size = Vector2.new(137, 104) },
	Flask = { Image = "rbxassetid://82272186901928", Size = Vector2.new(200, 224) },
	GlowCommon = { Image = "rbxassetid://93110762135131", Size = Vector2.new(512, 506) },
	GlowUncommon = { Image = "rbxassetid://75255030105583", Size = Vector2.new(512, 506) },
	GlowRare = { Image = "rbxassetid://97291881573481", Size = Vector2.new(512, 506) },
	GlowEpic = { Image = "rbxassetid://140666842260980", Size = Vector2.new(512, 506) },
	GlowLegendary = { Image = "rbxassetid://70940671313378", Size = Vector2.new(512, 506) },
	GlowMythic = { Image = "rbxassetid://104121367214593", Size = Vector2.new(512, 506) },
	GlowSecret = { Image = "rbxassetid://117081717361680", Size = Vector2.new(512, 506) },
}
