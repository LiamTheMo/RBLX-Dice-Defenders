-- Settings menu sprite asset ids, cut by tools/slice_settings.py from Assets/UI/settings menu/export/Settings_<Name>.png (Size and Ink are export pixels; group 33284082).
-- Slice = 9-slice SliceCenter on the export (RowFrame/ValuePill/Rule are compacted: ends + short uniform middle; never use them unsliced).
-- TabGraphics reuses ScreenShake's image: ImageRect is the monitor only (export px), Size/Ink are relative to that rect.

return {
	ToggleOn = {
		Image = "rbxassetid://132514514456227",
		Size = Vector2.new(350, 140),
		Ink = Rect.new(13, 13, 339, 129),
	},
	ToggleOff = {
		Image = "rbxassetid://122930339502656",
		Size = Vector2.new(358, 140),
		Ink = Rect.new(11, 13, 346, 129),
	},
	RefreshWhite = {
		Image = "rbxassetid://83654154845582",
		Size = Vector2.new(156, 157),
		Ink = Rect.new(11, 11, 144, 144),
	},
	Diamond = {
		Image = "rbxassetid://127939935478195",
		Size = Vector2.new(178, 99),
		Ink = Rect.new(10, 11, 168, 88),
	},
	GearPair = {
		Image = "rbxassetid://90531697561953",
		Size = Vector2.new(412, 286),
		Ink = Rect.new(11, 11, 401, 275),
	},
	Die = {
		Image = "rbxassetid://130936588373010",
		Size = Vector2.new(194, 194),
		Ink = Rect.new(11, 11, 183, 183),
	},
	Knob = {
		Image = "rbxassetid://119455212058071",
		Size = Vector2.new(195, 196),
		Ink = Rect.new(11, 11, 183, 185),
	},
	ArrowLeft = {
		Image = "rbxassetid://129490788412748",
		Size = Vector2.new(277, 194),
		Ink = Rect.new(11, 13, 265, 182),
	},
	ArrowRight = {
		Image = "rbxassetid://70707193902468",
		Size = Vector2.new(266, 194),
		Ink = Rect.new(11, 13, 255, 183),
	},
	MasterVolume = {
		Image = "rbxassetid://92552353795217",
		Size = Vector2.new(276, 230),
		Ink = Rect.new(12, 11, 263, 218),
	},
	Music = {
		Image = "rbxassetid://99219700433598",
		Size = Vector2.new(253, 247),
		Ink = Rect.new(13, 12, 241, 236),
	},
	SoundEffects = {
		Image = "rbxassetid://70940096105289",
		Size = Vector2.new(300, 246),
		Ink = Rect.new(12, 11, 286, 234),
	},
	InterfaceSounds = {
		Image = "rbxassetid://115040468836941",
		Size = Vector2.new(238, 244),
		Ink = Rect.new(11, 12, 226, 233),
	},
	Ambience = {
		Image = "rbxassetid://72237656758973",
		Size = Vector2.new(306, 247),
		Ink = Rect.new(11, 11, 295, 237),
	},
	EffectsQuality = {
		Image = "rbxassetid://137557493909927",
		Size = Vector2.new(313, 240),
		Ink = Rect.new(11, 11, 302, 229),
	},
	Projectile = {
		Image = "rbxassetid://113656533970622",
		Size = Vector2.new(309, 265),
		Ink = Rect.new(12, 12, 298, 253),
	},
	Shadows = {
		Image = "rbxassetid://122655471081271",
		Size = Vector2.new(282, 273),
		Ink = Rect.new(11, 11, 271, 262),
	},
	ScreenShake = {
		Image = "rbxassetid://139910373503070",
		Size = Vector2.new(379, 230),
		Ink = Rect.new(11, 11, 366, 218),
	},
	UiScale = {
		Image = "rbxassetid://111594884270702",
		Size = Vector2.new(256, 255),
		Ink = Rect.new(11, 12, 244, 244),
	},
	EffectScale = {
		Image = "rbxassetid://93081524143354",
		Size = Vector2.new(259, 243),
		Ink = Rect.new(11, 11, 248, 232),
	},
	AutoSkip = {
		Image = "rbxassetid://84629297802202",
		Size = Vector2.new(306, 231),
		Ink = Rect.new(12, 11, 296, 220),
	},
	DamageNumbers = {
		Image = "rbxassetid://88838188740398",
		Size = Vector2.new(363, 317),
		Ink = Rect.new(11, 11, 352, 305),
	},
	RangeRings = {
		Image = "rbxassetid://84296726125548",
		Size = Vector2.new(361, 357),
		Ink = Rect.new(12, 11, 350, 345),
	},
	Announce = {
		Image = "rbxassetid://84063156144190",
		Size = Vector2.new(363, 297),
		Ink = Rect.new(11, 11, 352, 286),
	},
	PlacementGrid = {
		Image = "rbxassetid://122852845847650",
		Size = Vector2.new(315, 315),
		Ink = Rect.new(11, 11, 302, 304),
	},
	AutoClose = {
		Image = "rbxassetid://127910368849284",
		Size = Vector2.new(384, 321),
		Ink = Rect.new(13, 11, 373, 310),
	},
	TabGameplay = {
		Image = "rbxassetid://138961112938327",
		Size = Vector2.new(416, 287),
		Ink = Rect.new(13, 11, 403, 276),
	},
	ReducedMotion = {
		Image = "rbxassetid://70755898547390",
		Size = Vector2.new(376, 199),
		Ink = Rect.new(51, 11, 365, 188),
	},
	HighContrast = {
		Image = "rbxassetid://105830412271343",
		Size = Vector2.new(270, 276),
		Ink = Rect.new(11, 11, 259, 265),
	},
	ShowFps = {
		Image = "rbxassetid://102123543057035",
		Size = Vector2.new(303, 266),
		Ink = Rect.new(11, 13, 292, 255),
	},
	HideOthers = {
		Image = "rbxassetid://88532745399008",
		Size = Vector2.new(350, 291),
		Ink = Rect.new(11, 11, 338, 280),
	},
	Notifications = {
		Image = "rbxassetid://104101163763290",
		Size = Vector2.new(330, 262),
		Ink = Rect.new(11, 11, 319, 252),
	},
	Language = {
		Image = "rbxassetid://106449611304124",
		Size = Vector2.new(277, 276),
		Ink = Rect.new(11, 11, 266, 263),
	},
	TabMisc = {
		Image = "rbxassetid://94006882425595",
		Size = Vector2.new(319, 243),
		Ink = Rect.new(11, 11, 308, 230),
	},
	RowFrame = {
		Image = "rbxassetid://121966566357132",
		Size = Vector2.new(500, 133),
		Ink = Rect.new(11, 12, 487, 119),
		Slice = Rect.new(230, 65, 270, 67),
	},
	ValuePill = {
		Image = "rbxassetid://133832486825849",
		Size = Vector2.new(447, 193),
		Ink = Rect.new(13, 11, 434, 182),
		Slice = Rect.new(213, 95, 234, 97),
	},
	TabGraphics = {
		Image = "rbxassetid://139910373503070",
		Size = Vector2.new(225, 209),
		Ink = Rect.new(0, 1, 225, 208),
		ImageRect = Rect.new(75, 10, 300, 219),
	},
}
