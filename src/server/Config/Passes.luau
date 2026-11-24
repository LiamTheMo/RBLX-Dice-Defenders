-- Game passes (Robux). Server-only. An Id of 0 means "not created yet": nobody owns it and no prompt is shown.
-- VIP (299 Robux): every roll costs VipDiscountPct (Config/Roll) less.
local Passes = {}

Passes.Vip = table.freeze({
	Id = 2092313367, -- created via Open Cloud 2026-11-21 (299 Robux, icon Assets/UI/new/shop menu/gamepasses/VIP.png)
	Name = "VIP",
	Robux = 299,
})

return table.freeze(Passes)
