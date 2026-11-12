-- Play menu sprite asset ids (only the sprites the Play menu adds; everything else reuses Bag / Quest Log / lobby sprites).
-- Source PNGs: Assets/UI/play menu/export/Play_<Name>.png, cut from the sheets by tools/slice_play.py (Size, Ink and the Rects below
-- are copied from its export/manifest.json; all are export pixels). Same entry format as QuestSprites.
-- Images must be owned by the experience's group (33284082). An empty id renders blank; never guess an id.
-- Slice = SliceCenter for 9-slice sprites only; no Slice = ornate art, draw unsliced by its aspect (none here: all unsliced).
-- Ink = the opaque (alpha >= 160) box inside the export: the art is drawn smaller than its Size by this transparent margin.
-- World* = opaque landscape interiors (no rim; the rim is a live UIStroke). Card / CardSel / Preview = ImageRectOffset/Size crops
-- (x0, y0, x1, y1) for the left-column card (363x148), the selected card (363x168) and the right preview (372x205).

return {
	LockCircle = {
		Image = "rbxassetid://130150348133376",
		Size = Vector2.new(229, 233),
		Ink = Rect.new(11, 11, 218, 222),
	},
	RewardBanner = {
		Image = "rbxassetid://96216607192940",
		Size = Vector2.new(268, 215),
		Ink = Rect.new(12, 11, 256, 204),
	},
	PlayArrow = {
		Image = "rbxassetid://111030592508089",
		Size = Vector2.new(183, 214),
		Ink = Rect.new(11, 11, 172, 203),
	},
	ScrollBase = {
		Image = "rbxassetid://115994531146571",
		Size = Vector2.new(796, 188),
		Ink = Rect.new(11, 14, 785, 176),
	},
	GemPin = {
		Image = "rbxassetid://101199843483354",
		Size = Vector2.new(267, 130),
		Ink = Rect.new(13, 11, 256, 118),
	},
	LaurelL = {
		Image = "rbxassetid://90850050471758",
		Size = Vector2.new(138, 168),
		Ink = Rect.new(11, 11, 126, 157),
	},
	LaurelR = {
		Image = "rbxassetid://86406800916185",
		Size = Vector2.new(140, 168),
		Ink = Rect.new(13, 11, 128, 157),
	},
	WorldDice = {
		Image = "rbxassetid://88260523003357",
		Size = Vector2.new(867, 313),
		Ink = Rect.new(0, 0, 867, 313),
		Card = Rect.new(0, 0, 768, 313),
		CardSel = Rect.new(0, 0, 676, 313),
		Preview = Rect.new(150, 0, 718, 313),
		CardC = Rect.new(0, 0, 768, 313),
	},
	WorldFrost = {
		Image = "rbxassetid://78301219301212",
		Size = Vector2.new(331, 180),
		Ink = Rect.new(0, 0, 331, 180),
		Card = Rect.new(0, 0, 331, 135),
		CardSel = Rect.new(0, 0, 331, 153),
		Preview = Rect.new(2, 0, 329, 180),
		CardC = Rect.new(0, 26, 298, 148),
	},
	WorldMagma = {
		Image = "rbxassetid://77757739631030",
		Size = Vector2.new(317, 180),
		Ink = Rect.new(0, 0, 317, 180),
		Card = Rect.new(0, 0, 317, 129),
		CardSel = Rect.new(0, 0, 317, 147),
		Preview = Rect.new(0, 0, 317, 175),
		CardC = Rect.new(0, 0, 317, 129),
	},
	WorldShadow = {
		Image = "rbxassetid://113653597909595",
		Size = Vector2.new(319, 181),
		Ink = Rect.new(0, 0, 319, 181),
		Card = Rect.new(0, 6, 300, 128),
		CardSel = Rect.new(0, 4, 300, 143),
		Preview = Rect.new(0, 0, 319, 176),
		CardC = Rect.new(0, 6, 300, 128),
	},
	PurpleBox = {
		Image = "rbxassetid://105278600388247",
		Size = Vector2.new(251, 247),
		Ink = Rect.new(14, 12, 238, 236),
		Slice = Rect.new(48, 45, 204, 203),
	},
}
