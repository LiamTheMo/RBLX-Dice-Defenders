-- Geometry only (docs/MVP.md "Layout"): a flat map with a 5x3 board at the origin and
-- a winding enemy path that wraps its top, right and bottom sides. Server and
-- client share this, so an enemy's position is a pure function of its path distance.
-- Y is constant everywhere.

local Layout = {}

Layout.COLS = 5
Layout.ROWS = 3
Layout.CELL_SIZE = 6 -- studs between cell centres
Layout.Y = 1

local Y = Layout.Y

-- Cell i in 1..15, row-major (row 1 is the top/back row, z negative).
function Layout.CellPosition(i: number): Vector3
	local col = (i - 1) % Layout.COLS
	local row = (i - 1) // Layout.COLS
	return Vector3.new(
		(col - (Layout.COLS - 1) / 2) * Layout.CELL_SIZE,
		Y,
		(row - (Layout.ROWS - 1) / 2) * Layout.CELL_SIZE
	)
end

Layout.Waypoints = table.freeze({
	Vector3.new(-40, Y, -19),
	Vector3.new(22, Y, -19),
	Vector3.new(22, Y, 19),
	Vector3.new(-10, Y, 19),
})

-- cumulative[i] = path distance of waypoint i.
local cumulative = { 0 }
for i = 2, #Layout.Waypoints do
	cumulative[i] = cumulative[i - 1] + (Layout.Waypoints[i] - Layout.Waypoints[i - 1]).Magnitude
end
Layout.PathLength = cumulative[#cumulative]

-- World position at `dist` studs along the path, clamped to [0, PathLength].
function Layout.PositionAt(dist: number): Vector3
	local waypoints = Layout.Waypoints
	if dist ~= dist or dist <= 0 then
		return waypoints[1]
	end
	if dist >= Layout.PathLength then
		return waypoints[#waypoints]
	end
	for i = 2, #waypoints do
		if dist <= cumulative[i] then
			local t = (dist - cumulative[i - 1]) / (cumulative[i] - cumulative[i - 1])
			return waypoints[i - 1] + (waypoints[i] - waypoints[i - 1]) * t
		end
	end
	return waypoints[#waypoints]
end

-- Fixed top-down-ish view framing the path and the board.
Layout.Camera = table.freeze({
	Position = Vector3.new(-9, 85, 38),
	LookAt = Vector3.new(-9, 0, 0),
	FieldOfView = 55,
})

return table.freeze(Layout)
