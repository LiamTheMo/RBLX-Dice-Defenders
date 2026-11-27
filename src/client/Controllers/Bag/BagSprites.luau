-- Bag menu sprite asset ids: the one place to swap Bag art.
-- Source PNGs: Assets/UI/old/bag menu/export/Bag_<Name>.png (old cutter tools/slice_bag.py; new-art ids come from Assets/UI/new/bag menu/export via tools/slice_bag_new.py) (sizes and
-- Slice values below are copied from its export/manifest.json; Size and Slice are export pixels).
-- Images must be owned by the experience's group (33284082): a user-owned image fails in-game with
-- "Requester does not have permission". An empty id renders blank; never guess an id.
-- Slice = SliceCenter for 9-slice sprites only (corner arc measured on the export); no Slice = draw unsliced.
-- Ink = the opaque (alpha >= 160) box inside the export: the art is drawn smaller than its Size by this transparent margin.

return {
	BannerEmblem = {
		Image = "rbxassetid://70930091468478",
		Size = Vector2.new(116, 165),
		Ink = Rect.new(10, 10, 106, 155),
	},
	IconDice = { Image = "rbxassetid://70520619812748", Size = Vector2.new(243, 268), Ink = Rect.new(5, 6, 237, 262) },
	IconCrystals = {
		Image = "rbxassetid://100436479051738",
		Size = Vector2.new(262, 252),
		Ink = Rect.new(4, 4, 257, 247),
	},
	IconPotion = { Image = "rbxassetid://87955663373193", Size = Vector2.new(204, 268), Ink = Rect.new(5, 6, 197, 261) },
	IconCrown = { Image = "rbxassetid://115530210137734", Size = Vector2.new(266, 205), Ink = Rect.new(6, 5, 260, 199) },
	Lock = { Image = "rbxassetid://97572278907033", Size = Vector2.new(116, 136), Ink = Rect.new(4, 4, 111, 132) },
	Coins = { Image = "rbxassetid://107094953753317", Size = Vector2.new(137, 115), Ink = Rect.new(5, 4, 133, 111) },
	Check = { Image = "rbxassetid://84308256154435", Size = Vector2.new(138, 115), Ink = Rect.new(5, 5, 132, 109) },
	Magnifier = { Image = "rbxassetid://100509891805364", Size = Vector2.new(105, 103), Ink = Rect.new(5, 5, 100, 98) },
	SortArrows = {
		Image = "rbxassetid://123586293497993",
		Size = Vector2.new(137, 104),
		Ink = Rect.new(4, 4, 132, 100),
	},
	-- Loop 1: rarity cards (CardIdle recoloured; each has its own measured Slice), copper cards, scrollbar (vertical 9-slice:
	-- Slice spans the full width, so draw with SliceScale = draw width / Size.X), ribbon, divider, stat row, stat icons.
	NameRibbon = {
		Image = "rbxassetid://106849464375213",
		Size = Vector2.new(547, 125),
		Ink = Rect.new(5, 5, 542, 120),
	},
	DividerGold = { Image = "rbxassetid://109715124095809", Size = Vector2.new(709, 54), Ink = Rect.new(5, 5, 704, 49) },
	IconSword = {
		Image = "rbxassetid://123699420907091",
		Size = Vector2.new(127, 128),
		Ink = Rect.new(12, 12, 115, 116),
	},
	IconHourglass = {
		Image = "rbxassetid://97862745424254",
		Size = Vector2.new(108, 134),
		Ink = Rect.new(12, 12, 96, 122),
	},
	IconFlame = {
		Image = "rbxassetid://127274386417168",
		Size = Vector2.new(126, 137),
		Ink = Rect.new(12, 12, 114, 125),
	},
	-- Loop 2: StatsLineL has its diamond at the right end, StatsLineR is its mirror (ImageLabel cannot flip); selected copper cards keep a
	-- 14 source px glow inside Size, so Ink is the glowing card; PillWide is height-fitted (draw height = 38 -> Size.Y 76 = 2 texels per px).
	ItemsNameRibbon = {
		Image = "rbxassetid://122565481793195",
		Size = Vector2.new(731, 149),
		Ink = Rect.new(6, 6, 725, 143),
	},
	StatsLineL = {
		Image = "rbxassetid://98916366501119",
		Size = Vector2.new(187, 29),
		Ink = Rect.new(7, 5, 182, 24),
	},
	StatsLineR = {
		Image = "rbxassetid://135643487274866",
		Size = Vector2.new(187, 29),
		Ink = Rect.new(5, 5, 180, 24),
	},
	CosFlagLeft = {
		Image = "rbxassetid://85714742648147",
		Size = Vector2.new(165, 260),
		Ink = Rect.new(5, 5, 160, 255),
	},
	CosFlagRight = {
		Image = "rbxassetid://119365777858590",
		Size = Vector2.new(164, 260),
		Ink = Rect.new(5, 5, 159, 255),
	},
	GlowRing = {
		Image = "rbxassetid://91104103839060",
		Size = Vector2.new(607, 256),
		Ink = Rect.new(42, 50, 568, 225),
	},
	GlowCommon = {
		Image = "rbxassetid://93110762135131",
		Size = Vector2.new(512, 506),
		Ink = Rect.new(144, 136, 366, 354),
	},
	GlowUncommon = {
		Image = "rbxassetid://75255030105583",
		Size = Vector2.new(512, 506),
		Ink = Rect.new(144, 136, 366, 354),
	},
	GlowRare = {
		Image = "rbxassetid://97291881573481",
		Size = Vector2.new(512, 506),
		Ink = Rect.new(144, 136, 366, 354),
	},
	GlowEpic = {
		Image = "rbxassetid://140666842260980",
		Size = Vector2.new(512, 506),
		Ink = Rect.new(144, 136, 366, 354),
	},
	GlowLegendary = {
		Image = "rbxassetid://70940671313378",
		Size = Vector2.new(512, 506),
		Ink = Rect.new(144, 136, 366, 354),
	},
	GlowMythic = {
		Image = "rbxassetid://104121367214593",
		Size = Vector2.new(512, 506),
		Ink = Rect.new(144, 136, 366, 354),
	},
	GlowSecret = {
		Image = "rbxassetid://117081717361680",
		Size = Vector2.new(512, 506),
		Ink = Rect.new(144, 136, 366, 354),
	},
	-- Loop 3
	CheckWhite = { Image = "rbxassetid://101071703487201", Size = Vector2.new(40, 31), Ink = Rect.new(1, 1, 39, 30) },
	StepMinus = { Image = "rbxassetid://117801302967018", Size = Vector2.new(94, 93), Ink = Rect.new(5, 5, 89, 88) },
	StepPlus = { Image = "rbxassetid://112776734134955", Size = Vector2.new(95, 93), Ink = Rect.new(5, 5, 90, 88) },
	IconFlaskWhite = {
		Image = "rbxassetid://76935573916483",
		Size = Vector2.new(104, 128),
		Ink = Rect.new(5, 5, 99, 123),
	},
	-- New-art icons (Assets/UI/new/bag menu/export, tools/slice_bag_new.py), one per real Config/Inventory entry.
	-- Ids stay "" until uploaded: BagLogic.iconFor then keeps the older icon, so nothing renders blank meanwhile.
	MatSprout = { Image = "rbxassetid://134661070927650", Size = Vector2.new(306, 210) }, -- Bag_MatSprout.png
	ItemXpTicket = { Image = "rbxassetid://102844076473765", Size = Vector2.new(279, 202) }, -- Bag_ItemXpTicket.png
	ItemCoinTicket = { Image = "rbxassetid://93734368708841", Size = Vector2.new(291, 201) }, -- Bag_ItemCoinTicket.png
	CosLeafyDie = { Image = "rbxassetid://126522423569084", Size = Vector2.new(346, 273) }, -- Bag_CosLeafyDie.png
	CosCrown = { Image = "rbxassetid://135319981707362", Size = Vector2.new(294, 229) }, -- Bag_CosCrown.png
	CosOrbitRing = { Image = "rbxassetid://84809217998528", Size = Vector2.new(371, 220) }, -- Bag_CosOrbitRing.png
}
