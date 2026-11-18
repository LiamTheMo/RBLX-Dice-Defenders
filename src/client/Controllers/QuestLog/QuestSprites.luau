-- Quest Log sprite asset ids: the one place to swap Quest Log art.
-- Source PNGs: Assets/UI/quest menu/export/Quest_<Name>.png, cut from the sheets by tools/slice_quest.py (Size, Ink and Slice below
-- are copied from its export/manifest.json; all are export pixels). Same entry format as BagSprites.
-- Images must be owned by the experience's group (33284082). An empty id renders blank; never guess an id.
-- Slice = SliceCenter for 9-slice sprites only; no Slice = ornate art, draw unsliced by its aspect.
-- Ink = the opaque (alpha >= 160) box inside the export: the art is drawn smaller than its Size by this transparent margin.

return {
	IconTabScroll = {
		Image = "rbxassetid://112573496917543",
		Size = Vector2.new(125, 111),
		Ink = Rect.new(13, 11, 112, 99),
	},
	IconTabTrophy = {
		Image = "rbxassetid://72862868524356",
		Size = Vector2.new(122, 115),
		Ink = Rect.new(13, 15, 110, 102),
	},
	DetailRibbon = {
		Image = "rbxassetid://88855241981971",
		Size = Vector2.new(414, 103),
		Ink = Rect.new(12, 12, 403, 91),
	},
	Stopwatch = { Image = "rbxassetid://125124093222791", Size = Vector2.new(101, 106), Ink = Rect.new(11, 11, 89, 94) },
	IconQuestScroll = {
		Image = "rbxassetid://137802432389859",
		Size = Vector2.new(310, 268),
		Ink = Rect.new(11, 12, 299, 257),
	},
	IconDie = { Image = "rbxassetid://105826914685259", Size = Vector2.new(251, 262), Ink = Rect.new(13, 13, 237, 251) },
	IconCrystals = {
		Image = "rbxassetid://137746637738631",
		Size = Vector2.new(256, 264),
		Ink = Rect.new(13, 11, 245, 253),
	},
	IconChest = {
		Image = "rbxassetid://84360693457613",
		Size = Vector2.new(311, 261),
		Ink = Rect.new(11, 13, 300, 250),
	},
	IconCrown = {
		Image = "rbxassetid://125357506164126",
		Size = Vector2.new(326, 265),
		Ink = Rect.new(11, 11, 315, 254),
	},
	IconGalaxyDie = {
		Image = "rbxassetid://71055335238510",
		Size = Vector2.new(259, 268),
		Ink = Rect.new(11, 11, 247, 257),
	},
	IconCalendar = {
		Image = "rbxassetid://102236404325266",
		Size = Vector2.new(265, 263),
		Ink = Rect.new(12, 11, 254, 251),
	},
	IconCalendarWeek = {
		Image = "rbxassetid://120842489827991",
		Size = Vector2.new(265, 265),
		Ink = Rect.new(11, 12, 254, 252),
	},
	IconWings = {
		Image = "rbxassetid://72694908360907",
		Size = Vector2.new(362, 239),
		Ink = Rect.new(12, 14, 350, 227),
	},
	BadgeKingBig = {
		Image = "rbxassetid://89750291695389",
		Size = Vector2.new(630, 364),
		Ink = Rect.new(12, 22, 618, 352),
	},
	BadgeKing = {
		Image = "rbxassetid://125598022381163",
		Size = Vector2.new(320, 232),
		Ink = Rect.new(11, 12, 309, 221),
	},
	BadgeRoyal = {
		Image = "rbxassetid://109761864655274",
		Size = Vector2.new(322, 228),
		Ink = Rect.new(12, 13, 311, 217),
	},
	BadgeMaterial = {
		Image = "rbxassetid://123452899426576",
		Size = Vector2.new(313, 233),
		Ink = Rect.new(11, 11, 302, 222),
	},
	BadgeCrafter = {
		Image = "rbxassetid://135730822072955",
		Size = Vector2.new(307, 232),
		Ink = Rect.new(11, 11, 296, 221),
	},
	BadgeHoarder = {
		Image = "rbxassetid://136345229670860",
		Size = Vector2.new(329, 228),
		Ink = Rect.new(12, 13, 318, 217),
	},
	BadgeTower = {
		Image = "rbxassetid://128820999703281",
		Size = Vector2.new(333, 246),
		Ink = Rect.new(13, 12, 322, 235),
	},
	BadgeBattle = {
		Image = "rbxassetid://89866337168269",
		Size = Vector2.new(328, 226),
		Ink = Rect.new(13, 12, 317, 215),
	},
	BadgeXp = { Image = "rbxassetid://98302680014688", Size = Vector2.new(322, 233), Ink = Rect.new(12, 12, 310, 222) },
	BadgeTreasure = {
		Image = "rbxassetid://128663407322037",
		Size = Vector2.new(329, 213),
		Ink = Rect.new(11, 12, 318, 201),
	},
	BadgeRift = {
		Image = "rbxassetid://106907172707114",
		Size = Vector2.new(349, 229),
		Ink = Rect.new(12, 20, 338, 218),
	},
	BadgeGalaxyLocked = {
		Image = "rbxassetid://111205642927992",
		Size = Vector2.new(407, 311),
		Ink = Rect.new(13, 13, 396, 300),
	},
	BadgeDivineLocked = {
		Image = "rbxassetid://89045047950703",
		Size = Vector2.new(422, 301),
		Ink = Rect.new(12, 11, 411, 290),
	},
	BadgeMythicLocked = {
		Image = "rbxassetid://113142572525192",
		Size = Vector2.new(409, 344),
		Ink = Rect.new(11, 12, 398, 333),
	},
	BadgeKingdomLocked = {
		Image = "rbxassetid://131798865979778",
		Size = Vector2.new(406, 311),
		Ink = Rect.new(12, 11, 395, 300),
	},
	BadgeTrueLocked = {
		Image = "rbxassetid://122834017971945",
		Size = Vector2.new(410, 337),
		Ink = Rect.new(11, 12, 399, 326),
	},
	DieFire = { Image = "rbxassetid://93532995776333", Size = Vector2.new(292, 309), Ink = Rect.new(12, 11, 281, 297) },
	DieIce = { Image = "rbxassetid://113373610042543", Size = Vector2.new(286, 305), Ink = Rect.new(11, 11, 275, 293) },
	DieLeaf = { Image = "rbxassetid://123689222857445", Size = Vector2.new(287, 308), Ink = Rect.new(11, 12, 276, 297) },
	DieLightning = {
		Image = "rbxassetid://113124787534973",
		Size = Vector2.new(290, 309),
		Ink = Rect.new(11, 13, 277, 298),
	},
	DieSun = { Image = "rbxassetid://135528766837983", Size = Vector2.new(286, 308), Ink = Rect.new(11, 12, 274, 297) },
	SkinFire = {
		Image = "rbxassetid://107455813792198",
		Size = Vector2.new(191, 258),
		Ink = Rect.new(11, 11, 180, 247),
	},
	SkinIce = { Image = "rbxassetid://118553063360056", Size = Vector2.new(191, 257), Ink = Rect.new(11, 12, 180, 246) },
	SkinLeaf = {
		Image = "rbxassetid://139625171157235",
		Size = Vector2.new(191, 259),
		Ink = Rect.new(11, 11, 180, 248),
	},
	SkinLightning = {
		Image = "rbxassetid://135282982209810",
		Size = Vector2.new(193, 260),
		Ink = Rect.new(11, 11, 182, 249),
	},
	SkinSun = { Image = "rbxassetid://79163363436536", Size = Vector2.new(196, 264), Ink = Rect.new(11, 11, 183, 253) },
	Crown = { Image = "rbxassetid://133130676205241", Size = Vector2.new(373, 298), Ink = Rect.new(10, 11, 361, 287) },
	Potion = { Image = "rbxassetid://96180639806384", Size = Vector2.new(243, 299), Ink = Rect.new(11, 11, 232, 288) },
	CheckCircle = {
		Image = "rbxassetid://114783065862052",
		Size = Vector2.new(134, 135),
		Ink = Rect.new(12, 11, 123, 124),
	},
	RewardBox = {
		Image = "rbxassetid://116836535434277",
		Size = Vector2.new(250, 239),
		Ink = Rect.new(11, 11, 238, 226),
	},
	RewardBoxPlain = {
		Image = "rbxassetid://139567597144015",
		Size = Vector2.new(252, 239),
		Ink = Rect.new(13, 11, 240, 226),
	},
	PillMasteryBlank = {
		Image = "rbxassetid://85272232594317",
		Size = Vector2.new(444, 107),
		Ink = Rect.new(11, 13, 433, 94),
	},
	Crystals = { Image = "rbxassetid://84688389950238", Size = Vector2.new(250, 215), Ink = Rect.new(11, 11, 237, 204) },
	NextRewards = {
		Image = "rbxassetid://133724846469712",
		Size = Vector2.new(500, 110),
		Ink = Rect.new(11, 11, 487, 99),
	},
	BannerFlameL = {
		Image = "rbxassetid://104997722576053",
		Size = Vector2.new(182, 272),
		Ink = Rect.new(11, 12, 170, 261),
	},
	BannerFlameR = {
		Image = "rbxassetid://112624872590130",
		Size = Vector2.new(185, 274),
		Ink = Rect.new(12, 14, 172, 263),
	},
	SlotCopper = {
		Image = "rbxassetid://84150105926644",
		Size = Vector2.new(264, 280),
		Ink = Rect.new(27, 45, 251, 269),
	},
	Sparkle1 = { Image = "rbxassetid://125951352923741", Size = Vector2.new(125, 128), Ink = Rect.new(27, 27, 94, 100) },
	Sparkle2 = { Image = "rbxassetid://72088321289923", Size = Vector2.new(112, 131), Ink = Rect.new(29, 10, 77, 103) },
	Sparkle3 = { Image = "rbxassetid://116022411205812", Size = Vector2.new(87, 85), Ink = Rect.new(28, 25, 60, 57) },
	Sparkle4 = { Image = "rbxassetid://74537580277951", Size = Vector2.new(75, 72), Ink = Rect.new(26, 26, 49, 45) },
	Halo = { Image = "rbxassetid://114426866213056", Size = Vector2.new(429, 197), Ink = Rect.new(30, 37, 399, 171) },
	Rays = { Image = "rbxassetid://85552709706701", Size = Vector2.new(403, 278), Ink = Rect.new(38, 51, 348, 250) },
	GlowRadial = {
		Image = "rbxassetid://128110272700921",
		Size = Vector2.new(256, 256),
		Ink = Rect.new(0, 0, 256, 256),
	},
	CrownPlain = {
		Image = "rbxassetid://130291183544148",
		Size = Vector2.new(163, 105),
		Ink = Rect.new(11, 11, 152, 93),
	},
	RaysBurst = { Image = "rbxassetid://125622434000742", Size = Vector2.new(256, 256), Ink = Rect.new(0, 0, 256, 256) },
	BannerSeal = {
		Image = "rbxassetid://88217102630797",
		Size = Vector2.new(157, 168),
		Ink = Rect.new(18, 19, 124, 151), -- visible edge: the last alpha column (124) is parchment-coloured
	},
	BannerQuill = {
		Image = "rbxassetid://91693766916316",
		Size = Vector2.new(510, 127),
		Ink = Rect.new(8, 10, 465, 90),
	},
	-- New QUESTS sheet icons (Assets/UI/new/quests menu/export/Quests_<Name>.png, cut by tools/slice_quests.py). Ids "" until uploaded.
	QuestCalendar = {
		Image = "rbxassetid://95383506552165",
		Size = Vector2.new(173, 170),
		Ink = Rect.new(0, 0, 173, 170),
	}, -- Quests_Calendar.png
	QuestCalendarWeek = {
		Image = "rbxassetid://88618454954916",
		Size = Vector2.new(156, 172),
		Ink = Rect.new(0, 0, 156, 172),
	}, -- Quests_CalendarWeek.png
	QuestStopwatch = {
		Image = "rbxassetid://112981991478099",
		Size = Vector2.new(146, 172),
		Ink = Rect.new(0, 0, 146, 172),
	}, -- Quests_Stopwatch.png
}
