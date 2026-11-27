--!strict
-- Projectile speeds and the one flight-time formula. The server stamps every shot with its flight time and the client
-- flies, lands and applies the hit on exactly that clock, so the projectile and the HP bar cannot drift apart.

local Layout = require(script.Parent.Layout)

local ProjectileFlight = {}

-- Studs per second. Common dice differ; every Rare-and-up die flies at DefaultSpeed.
ProjectileFlight.Speed = table.freeze({
	C01 = 140,
	C02 = 170,
	C03 = 145,
	C04 = 155,
	C05 = 165,
	C06 = 150,
	C07 = 160,
})
ProjectileFlight.DefaultSpeed = 150

-- Seconds from the die to an enemy `dist` balance studs along its path (the enemy's position when the die fires;
-- the client aims ahead of it for this long). `arena` is the Layout arena key (mode name or player count).
function ProjectileFlight.Seconds(
	typeId: string,
	cell: number,
	dieSeat: number,
	enemySeat: number,
	dist: number,
	arena: (number | string)?
): number
	local from = Layout.CellPosition(cell, dieSeat, arena)
	local to = Layout.PositionAt(dist, enemySeat, arena)
	return (to - from).Magnitude / (ProjectileFlight.Speed[typeId] or ProjectileFlight.DefaultSpeed)
end

return ProjectileFlight
