-- Roll menu sprite asset ids (new sprites only; everything else reuses Bag / Quest Log / Play sprites).
-- Source PNGs: Assets/UI/roll menu/export/Roll_<Name>.png, cut from roll-featured / roll-rarities / roll-icons-text sheets by
-- tools/slice_roll.py (Size and Ink are copied from its export/manifest.json; export pixels). Same entry format as PlaySprites.
-- Images must be owned by the experience's group (33284082). An empty id renders blank; never guess an id.
-- Slice = SliceCenter for the horizontal 9-slice sprites (caps hold the diamonds / rounded ends); the rest draw unsliced.
-- Ink = the opaque (alpha >= 160) box inside the export: the art is drawn smaller than its Size by this transparent margin.

return {
	DieLegendary = {
		Image = "rbxassetid://81061694857996",
		Size = Vector2.new(375, 369),
		Ink = Rect.new(12, 13, 362, 357),
	},
	DieMythic = {
		Image = "rbxassetid://105265568874920",
		Size = Vector2.new(405, 391),
		Ink = Rect.new(11, 12, 392, 379),
	},
	HeaderPlate = {
		Image = "rbxassetid://102195834070987",
		Size = Vector2.new(683, 116),
		Ink = Rect.new(11, 12, 671, 105),
		Slice = Rect.new(100, 57, 583, 58),
	},
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
	Info = {
		Image = "rbxassetid://98408352181306",
		Size = Vector2.new(206, 208),
		Ink = Rect.new(11, 12, 196, 197),
	},
	PityPill = {
		Image = "rbxassetid://140611114727062",
		Size = Vector2.new(341, 142),
		Ink = Rect.new(14, 11, 329, 129),
		Slice = Rect.new(94, 70, 248, 71),
	},
	BarTrack = {
		Image = "rbxassetid://97359146610142",
		Size = Vector2.new(870, 84),
		Ink = Rect.new(11, 11, 857, 73),
		Slice = Rect.new(71, 41, 813, 42),
	},
	BarFill = {
		Image = "rbxassetid://93700754066161",
		Size = Vector2.new(491, 85),
		Ink = Rect.new(11, 11, 481, 72),
		Slice = Rect.new(66, 41, 418, 42),
	},
	CrownGold = {
		Image = "rbxassetid://139649180427601",
		Size = Vector2.new(230, 151),
		Ink = Rect.new(10, 11, 219, 140),
	},
	RowSecret = {
		Image = "rbxassetid://89199438575661",
		Size = Vector2.new(674, 109),
		Ink = Rect.new(13, 13, 662, 96),
		Slice = Rect.new(93, 53, 595, 54),
	},
	RowMythic = {
		Image = "rbxassetid://106395253559914",
		Size = Vector2.new(673, 106),
		Ink = Rect.new(13, 15, 662, 94),
		Slice = Rect.new(89, 52, 593, 53),
	},
	RowLegendary = {
		Image = "rbxassetid://87472221789482",
		Size = Vector2.new(672, 104),
		Ink = Rect.new(12, 13, 661, 92),
		Slice = Rect.new(76, 51, 599, 52),
	},
	RowEpic = {
		Image = "rbxassetid://71015933900219",
		Size = Vector2.new(673, 104),
		Ink = Rect.new(12, 15, 662, 91),
		Slice = Rect.new(86, 51, 587, 52),
	},
	RowRare = {
		Image = "rbxassetid://90274408333969",
		Size = Vector2.new(673, 100),
		Ink = Rect.new(12, 14, 662, 85),
		Slice = Rect.new(60, 49, 618, 50),
	},
	RowCommon = {
		Image = "rbxassetid://101791949844990",
		Size = Vector2.new(673, 93),
		Ink = Rect.new(13, 12, 662, 82),
		Slice = Rect.new(86, 45, 593, 46),
	},
	PillLegendary = {
		Image = "rbxassetid://73777508946773",
		Size = Vector2.new(370, 113),
		Ink = Rect.new(11, 13, 358, 102),
		Slice = Rect.new(91, 55, 280, 56),
	},
	PillMythic = {
		Image = "rbxassetid://70998849416231",
		Size = Vector2.new(381, 113),
		Ink = Rect.new(12, 13, 370, 102),
		Slice = Rect.new(85, 55, 314, 56),
	},
	BtnGold = {
		Image = "rbxassetid://121637472656143",
		Size = Vector2.new(427, 168),
		Ink = Rect.new(13, 13, 415, 155),
		Slice = Rect.new(118, 83, 322, 84),
	},
	BtnPurple = {
		Image = "rbxassetid://88033810662274",
		Size = Vector2.new(439, 167),
		Ink = Rect.new(13, 13, 426, 155),
		Slice = Rect.new(89, 82, 334, 83),
	},
	BtnGrey = {
		Image = "rbxassetid://84943437721372",
		Size = Vector2.new(424, 165),
		Ink = Rect.new(13, 12, 412, 154),
		Slice = Rect.new(118, 81, 331, 82),
	},
	PriceChip = {
		Image = "rbxassetid://115048367006330",
		Size = Vector2.new(288, 105),
		Ink = Rect.new(12, 11, 276, 94),
		Slice = Rect.new(66, 51, 228, 52),
	},
	BannerDieSolo = {
		Image = "rbxassetid://92798359066670",
		Size = Vector2.new(225, 242),
		Ink = Rect.new(11, 11, 214, 231),
	},
	BannerRing = {
		Image = "rbxassetid://114250841752433",
		Size = Vector2.new(523, 227),
		Ink = Rect.new(23, 22, 499, 204),
	},
	Die1 = {
		Image = "rbxassetid://139886553638643",
		Size = Vector2.new(189, 198),
		Ink = Rect.new(12, 11, 178, 187),
	},
	Dice3 = {
		Image = "rbxassetid://99922194024829",
		Size = Vector2.new(232, 212),
		Ink = Rect.new(12, 10, 221, 201),
	},
}
