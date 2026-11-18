-- Shop menu sprite asset ids: whole product art, cut by tools/slice_shop.py from Assets/UI/new/shop menu/sheets/ into
-- Assets/UI/new/shop menu/export/Shop_<Name>.png (Size = export px, Ink = the whole image: every cut is a tight crop, never sliced).
-- Window, tabs, close X, pills, Coin and Gem are the shared ones (SharedSprites, Sprites). Images must be owned by group 33284082.
-- An empty id renders blank; never guess an id (the overseer's uploader fills them).

return {
	HeroArt = { Image = "rbxassetid://88622657607968", Size = Vector2.new(317, 182), Ink = Rect.new(0, 0, 317, 182) }, -- Shop_HeroArt.png
	GemBag = { Image = "rbxassetid://74905164109034", Size = Vector2.new(178, 189), Ink = Rect.new(0, 0, 178, 189) }, -- Shop_GemBag.png
	ChestOpenGems = {
		Image = "rbxassetid://135207190790007",
		Size = Vector2.new(201, 188),
		Ink = Rect.new(0, 0, 201, 188),
	}, -- Shop_ChestOpenGems.png
	Clover = { Image = "rbxassetid://111437107375643", Size = Vector2.new(179, 191), Ink = Rect.new(0, 0, 179, 191) }, -- Shop_Clover.png
	Crown = { Image = "rbxassetid://96910090967843", Size = Vector2.new(230, 188), Ink = Rect.new(0, 0, 230, 188) }, -- Shop_Crown.png
	Robux = { Image = "rbxassetid://74672180062997", Size = Vector2.new(94, 104), Ink = Rect.new(0, 0, 94, 104) }, -- Shop_Robux.png
}
