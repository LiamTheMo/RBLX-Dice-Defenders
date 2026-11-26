-- Results menu sprite asset ids: the one place to swap Results art.
-- Source PNGs: Assets/UI/new/result menus/export/Results_<Name>.png (sizes from manifest.json).
-- Images are owned by the experience's group (33284082); user-owned images fail in-game.

local Hud = require(script.Parent.Parent.Sprites)
local Shared = require(script.Parent.Parent.SharedSprites)
local PlaySprites = require(script.Parent.Parent.Play.PlaySprites)
local QuestSprites = require(script.Parent.Parent.QuestLog.QuestSprites)

local Results = {
	CrestShieldDie = { Image = "rbxassetid://136895909006505", Size = Vector2.new(229, 253) }, -- Results_CrestShieldDie.png
	ShieldCube = { Image = "rbxassetid://125884155005926", Size = Vector2.new(174, 244) }, -- Results_ShieldCube.png
	Skull = { Image = "rbxassetid://91740360066715", Size = Vector2.new(199, 215) }, -- Results_Skull.png
	XpStar = { Image = "rbxassetid://85066897644026", Size = Vector2.new(200, 197) }, -- Results_XpStar.png
	RibbonNeutral = { Image = "rbxassetid://99600631073954", Size = Vector2.new(534, 146) }, -- Results_RibbonNeutral.png
	ContinueGreen = { Image = "rbxassetid://93122467837894", Size = Vector2.new(992, 188) }, -- Results_ContinueGreen.png
	TrophyGold = { Image = "rbxassetid://112542137478480", Size = Vector2.new(266, 199) }, -- Results_TrophyGold.png
	TrophyRed = { Image = "rbxassetid://100076601543291", Size = Vector2.new(260, 199) }, -- Results_TrophyRed.png
	DieBlue = { Image = "rbxassetid://96333195146578", Size = Vector2.new(135, 146) }, -- Results_DieBlue.png
	DiePurple = { Image = "rbxassetid://112611156371762", Size = Vector2.new(131, 143) }, -- Results_DiePurple.png
	DieRed = { Image = "rbxassetid://102664424976560", Size = Vector2.new(137, 144) }, -- Results_DieRed.png
	DieWhite = { Image = "rbxassetid://85890713036331", Size = Vector2.new(134, 145) }, -- Results_DieWhite.png
}

-- Reused art (ids stay in their own modules; owner rule: gems and coins are the HUD's Sprites.Coin / Sprites.Gem).
Results.Coin = { Image = Hud.Coin, Size = Shared.Coin.Size }
Results.Gem = { Image = Hud.Gem, Size = Shared.Gem.Size }
Results.LaurelL = PlaySprites.LaurelL
Results.LaurelR = PlaySprites.LaurelR
Results.Crown = PlaySprites.Crown
Results.Trophy = PlaySprites.Trophy
Results.Stopwatch = QuestSprites.Stopwatch
Results.RaysBurst = QuestSprites.RaysBurst

return Results
