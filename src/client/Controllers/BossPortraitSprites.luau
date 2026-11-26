-- Boss portrait sprite asset ids: the one place to swap boss portrait art.
-- Source PNGs: Assets/Models/Enemies/Boss/portraits/small/<Name>.png (64x64, never upscaled).
-- Images are owned by the experience's group (33284082); user-owned images fail in-game.

local BossPortraits = {
	GoblinKing = { Image = "rbxassetid://98413462146998", Size = Vector2.new(64, 64) }, -- GoblinKing.png
	CursedKing = { Image = "rbxassetid://71164671005746", Size = Vector2.new(64, 64) }, -- CursedKing.png
	CourtJester = { Image = "rbxassetid://107425248234616", Size = Vector2.new(64, 64) }, -- CourtJester.png
}

return BossPortraits
