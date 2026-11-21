-- Shared window art asset ids (close X, tabs, pill buttons, badges): the one place to swap them.
-- Source PNGs: Assets/UI/new/shared/export/Shared_<Name>.png, cut by tools/slice_shared.py (Size and Slice copied from its manifest.json).
-- Size = export px. Slice = SliceCenter of the horizontal 3-slice sprites (tabs, pills: left cap, ONE repeated column, right cap;
-- draw at box height = Size.Y x SliceScale, never stretched vertically). Shared_Coin / Shared_Gem are Sprites.Coin / Sprites.Gem.
-- Images must be owned by the experience's group (33284082). An empty id renders blank; never guess an id.

return {
	Close = { Image = "rbxassetid://121869598091640", Size = Vector2.new(157, 146) }, -- Shared_Close.png
	CloseHover = { Image = "rbxassetid://100721920652098", Size = Vector2.new(157, 146) }, -- Shared_CloseHover.png
	ClosePressed = { Image = "rbxassetid://107474764520695", Size = Vector2.new(157, 147) }, -- Shared_ClosePressed.png
	Tab = { Image = "rbxassetid://104518271391702", Size = Vector2.new(158, 101), Slice = Rect.new(78, 49, 82, 50) }, -- Shared_Tab.png
	TabHover = {
		Image = "rbxassetid://100605890953609",
		Size = Vector2.new(157, 101),
		Slice = Rect.new(77, 49, 81, 50),
	}, -- Shared_TabHover.png
	TabPressed = {
		Image = "rbxassetid://97467819955649",
		Size = Vector2.new(158, 101),
		Slice = Rect.new(78, 49, 82, 50),
	}, -- Shared_TabPressed.png
	TabSelected = {
		Image = "rbxassetid://118970279943135",
		Size = Vector2.new(208, 101),
		Slice = Rect.new(102, 49, 106, 50),
	}, -- Shared_TabSelected.png
	TabDisabled = {
		Image = "rbxassetid://135215129328953",
		Size = Vector2.new(204, 102),
		Slice = Rect.new(100, 50, 104, 51),
	}, -- Shared_TabDisabled.png
	PillGrey = {
		Image = "rbxassetid://74057287249205",
		Size = Vector2.new(200, 123),
		Slice = Rect.new(112, 60, 116, 61),
	}, -- Shared_PillGrey.png
	PillGreen = {
		Image = "rbxassetid://81882619476097",
		Size = Vector2.new(217, 123),
		Slice = Rect.new(128, 60, 132, 61),
	}, -- Shared_PillGreen.png
	PillRed = {
		Image = "rbxassetid://124237054808738",
		Size = Vector2.new(212, 123),
		Slice = Rect.new(124, 60, 128, 61),
	}, -- Shared_PillRed.png
	PillYellow = {
		Image = "rbxassetid://138194144949885",
		Size = Vector2.new(217, 123),
		Slice = Rect.new(128, 60, 132, 61),
	}, -- Shared_PillYellow.png (the green pill, hue-shifted)
	PillPurple = {
		Image = "rbxassetid://70994617713469",
		Size = Vector2.new(210, 123),
		Slice = Rect.new(123, 60, 127, 61),
	}, -- Shared_PillPurple.png
	Lock = { Image = "rbxassetid://130449756186328", Size = Vector2.new(161, 151) }, -- Shared_Lock.png
	Check = { Image = "rbxassetid://89820101846625", Size = Vector2.new(161, 151) }, -- Shared_Check.png
	ArrowLeft = { Image = "rbxassetid://134846227881255", Size = Vector2.new(160, 151) }, -- Shared_ArrowLeft.png
	ArrowRight = { Image = "rbxassetid://116295701515895", Size = Vector2.new(161, 151) }, -- Shared_ArrowRight.png
	Search = { Image = "rbxassetid://84776157604419", Size = Vector2.new(161, 151) }, -- Shared_Search.png
	Padlock = { Image = "rbxassetid://84826637684270", Size = Vector2.new(68, 79) }, -- Shared_Padlock.png (bare gold padlock), awaiting upload
	Tick = { Image = "rbxassetid://127182534205943", Size = Vector2.new(121, 121) }, -- Shared_Tick.png (bare green tick), awaiting upload
	Coin = { Image = "rbxassetid://132885018986924", Size = Vector2.new(119, 123) }, -- Shared_Coin.png
	Gem = { Image = "rbxassetid://116462057129692", Size = Vector2.new(122, 118) }, -- Shared_Gem.png
}
