-- Geometry only (docs/MVP.md "Layout"): a flat map with a 5x3 board and a winding enemy path that
-- wraps its top, right and bottom sides, centred on ORIGIN: the match arena, far from the lobby map
-- (workspace.Lobby, built around the world origin, where players walk between runs). Server and
-- client share this, so an enemy's position is a pure function of its path distance.
-- Y is constant everywhere.

local Layout = {}

Layout.COLS = 5
Layout.ROWS = 3
Layout.CELL_SIZE = 6 -- studs between cell centres
Layout.Y = 1
Layout.ORIGIN = Vector3.new(1000, 0, 0) -- X/Z only: BoardView's ground and pad heights assume Y 0

local Y = Layout.Y
local O = Layout.ORIGIN

-- Cell i in 1..15, row-major (row 1 is the top/back row, z negative).
function Layout.CellPosition(i: number, seat: number?, playerCount: number?): Vector3
	local col = (i - 1) % Layout.COLS
	local row = (i - 1) // Layout.COLS
	return O
		+ Vector3.new(
			(col - (Layout.COLS - 1) / 2) * Layout.CELL_SIZE,
			Y,
			(row - (Layout.ROWS - 1) / 2) * Layout.CELL_SIZE
				+ (if playerCount == 2 then (if seat == 2 then 13 else -13) else 0)
		)
end

Layout.Waypoints = table.freeze({
	-- Hugs the board (1.8-stud gap to the 7-stud strip) so phones can frame it larger.
	O + Vector3.new(-28, Y, -14),
	O + Vector3.new(20, Y, -14),
	O + Vector3.new(20, Y, 14),
	O + Vector3.new(-28, Y, 14),
})

-- cumulative[i] = path distance of waypoint i.
local function distances(points)
	local cumulative = { 0 }
	for i = 2, #points do
		cumulative[i] = cumulative[i - 1] + (points[i] - points[i - 1]).Magnitude
	end
	return cumulative
end
local cumulative = distances(Layout.Waypoints)
Layout.PathLength = cumulative[#cumulative]
local function coopPath(z: number)
	return table.freeze({
		O + Vector3.new(-38, Y, z),
		O + Vector3.new(14, Y, z),
		O + Vector3.new(14, Y, 0),
		O + Vector3.new(59, Y, 0),
	})
end
local coop = { coopPath(-27), coopPath(27) }
local coopDistances = distances(coop[1])
Layout.CoopJunction = coopDistances[3]
Layout.CoopPathLength = coopDistances[#coopDistances]

function Layout.Path(seat: number?, playerCount: number?)
	return if playerCount == 2 then coop[seat or 1] else Layout.Waypoints
end

-- World position at `dist` studs along the path, clamped to [0, PathLength].
function Layout.PositionAt(dist: number, seat: number?, playerCount: number?): Vector3
	local waypoints = Layout.Path(seat, playerCount)
	local walked = if playerCount == 2 then coopDistances else cumulative
	if dist ~= dist or dist <= 0 then
		return waypoints[1]
	end
	if dist >= walked[#walked] then
		return waypoints[#waypoints]
	end
	for i = 2, #waypoints do
		if dist <= walked[i] then
			local t = (dist - walked[i - 1]) / (walked[i] - walked[i - 1])
			return waypoints[i - 1] + (waypoints[i] - waypoints[i - 1]) * t
		end
	end
	return waypoints[#waypoints]
end

-- Fixed top-down-ish view framing the path and the board.
Layout.Camera = table.freeze({
	-- Fitted so path, board and boss clear the HUD at 1235x739, 844x390 and 667x375.
	Position = O + Vector3.new(2, 50.5, 11.6),
	LookAt = O + Vector3.new(2, 0, -1),
	FieldOfView = 55,
})

Layout.CoopCamera = table.freeze({
	Position = O + Vector3.new(10, 76, 18),
	LookAt = O + Vector3.new(10, 0, 0),
	FieldOfView = 56,
})

return table.freeze(Layout)
