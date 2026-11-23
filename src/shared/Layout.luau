-- Geometry only (docs/MVP.md "Layout"): where the World 1 maps put the 5x3 boards and the enemy routes.
-- Every function that takes an arena `key` accepts 1/2 (legacy player count: Solo/Coop) or "Solo"|"Coop"|"Duel".
-- The maps are models in ReplicatedStorage.Maps (Solo, Coop, Duel), built far from the lobby map (workspace.Lobby,
-- around the world origin, where players walk between runs); BoardView clones the one a run needs. Server and
-- client share this, so an enemy's position is a pure function of its path distance.
-- Y is constant everywhere: the height a die centre and an enemy walk at above the map's pads and route.

local Layout = {}

Layout.COLS = 5
Layout.ROWS = 3
Layout.CELL_SIZE = 6 -- studs between cell centres
Layout.Y = 4 -- route top 3.2 + 0.8
Layout.PadTop = 3.4 -- top face of a map pad: dice stand here
-- Where a run's arena is shown (X/Z only; the centre cell of the board). Streaming pauses the picture when the camera
-- is beyond the streaming radius of the lobby, so arenas stay within ~1000 studs of the world origin.
Layout.ORIGIN = Vector3.new(1000, 0, 0)
Layout.COOP_ORIGIN = Vector3.new(1000, 0, 0)
Layout.DUEL_ORIGIN = Vector3.new(1000, 0, 0)
-- Where the maps were authored in ReplicatedStorage.Maps (X of each model's centre); BoardView moves a clone to the origin.
Layout.SOLO_MAP_X = 5000
Layout.COOP_MAP_X = 5800
Layout.DUEL_MAP_X = 5400
Layout.COOP_SEAT_OFFSET = 14.5 -- each seat's board sits this far either side of the co-op map's centre line
Layout.DUEL_SEAT_OFFSET = 14.5 -- same for the duel map: seat 1 north (z negative), seat 2 south

local Y = Layout.Y
local O = Layout.ORIGIN
local CO = Layout.COOP_ORIGIN
local DO = Layout.DUEL_ORIGIN

-- "Solo" | "Coop" | "Duel" for an arena key (1/2 legacy numbers, or the names; anything else is Solo).
local function arenaOf(key: (number | string)?): string
	if key == 2 or key == "Coop" then
		return "Coop"
	elseif key == "Duel" then
		return "Duel"
	end
	return "Solo"
end
Layout.ArenaOf = arenaOf

-- Cell i in 1..15, row-major (row 1 is the top/back row, z negative).
function Layout.CellPosition(i: number, seat: number?, arenaKey: (number | string)?): Vector3
	local col = (i - 1) % Layout.COLS
	local row = (i - 1) // Layout.COLS
	local arena = arenaOf(arenaKey)
	local origin, offset = O, 0
	if arena == "Coop" then
		origin, offset = CO, Layout.COOP_SEAT_OFFSET
	elseif arena == "Duel" then
		origin, offset = DO, Layout.DUEL_SEAT_OFFSET
	end
	if offset ~= 0 and seat ~= 2 then
		offset = -offset
	end
	return origin
		+ Vector3.new(
			(col - (Layout.COLS - 1) / 2) * Layout.CELL_SIZE,
			Y,
			(row - (Layout.ROWS - 1) / 2) * Layout.CELL_SIZE + offset
		)
end

-- The walked route is the middle of each map's route strip. The server balances waves against a fixed
-- 124-stud route (VIRTUAL_LENGTH); the maps' routes are shorter, so path distance stays in those balance
-- studs and PositionAt scales it onto the real route. Enemies take the same time to cross either way.
local VIRTUAL_LENGTH = 124

Layout.Waypoints = table.freeze({
	-- Solo: in at the west end, up the west side, along the top, down the east side to the exit.
	O + Vector3.new(-20.3, Y, 7.65),
	O + Vector3.new(-20.3, Y, -13.1),
	O + Vector3.new(20.9, Y, -13.1),
	O + Vector3.new(20.9, Y, 7.65),
})

-- cumulative[i] = real distance (studs) of waypoint i along the route.
local function distances(points)
	local cumulative = { 0 }
	for i = 2, #points do
		cumulative[i] = cumulative[i - 1] + (points[i] - points[i - 1]).Magnitude
	end
	return cumulative
end
local cumulative = distances(Layout.Waypoints)
Layout.PathLength = VIRTUAL_LENGTH
local soloScale = VIRTUAL_LENGTH / cumulative[#cumulative] -- balance studs per real stud

local function coopPath(z: number)
	return table.freeze({
		CO + Vector3.new(-18.8, Y, z),
		CO + Vector3.new(-18.8, Y, 0), -- the lanes meet here
		CO + Vector3.new(16.95, Y, 0),
	})
end
local coop = { coopPath(-19.15), coopPath(19.15) }
local coopDistances = distances(coop[1])
local coopScale = VIRTUAL_LENGTH / coopDistances[#coopDistances]
Layout.CoopJunction = coopDistances[2] * coopScale
Layout.CoopPathLength = VIRTUAL_LENGTH

-- Duel: one U per seat (west side in, across the bottom next to the divider, up the east side), measured on the
-- map's route strips. Seat 1 is north (z negative), seat 2 the mirror in z.
local function duelPath(sign: number)
	return table.freeze({
		DO + Vector3.new(-18.65, Y, 20.55 * sign),
		DO + Vector3.new(-18.65, Y, 2.9 * sign),
		DO + Vector3.new(18.65, Y, 2.9 * sign),
		DO + Vector3.new(18.65, Y, 20.55 * sign),
	})
end
local duel = { duelPath(-1), duelPath(1) }
local duelDistances = distances(duel[1])
local duelScale = VIRTUAL_LENGTH / duelDistances[#duelDistances]

function Layout.Path(seat: number?, arenaKey: (number | string)?)
	local arena = arenaOf(arenaKey)
	if arena == "Coop" then
		return coop[seat or 1]
	elseif arena == "Duel" then
		return duel[if seat == 2 then 2 else 1]
	end
	return Layout.Waypoints
end

-- World position at `dist` balance studs along the path, clamped to [0, PathLength].
function Layout.PositionAt(dist: number, seat: number?, arenaKey: (number | string)?): Vector3
	local waypoints = Layout.Path(seat, arenaKey)
	local walked, scale
	local arena = arenaOf(arenaKey)
	if arena == "Coop" then
		walked, scale = coopDistances, coopScale
	elseif arena == "Duel" then
		walked, scale = duelDistances, duelScale
	else
		walked, scale = cumulative, soloScale
	end
	if dist ~= dist or dist <= 0 then
		return waypoints[1]
	end
	dist /= scale
	if dist >= walked[#walked] or dist * scale >= VIRTUAL_LENGTH then
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

-- Fixed top-down-ish views framing each map's route and board (tuned for phones: 844x390 and 667x375).
Layout.Camera = table.freeze({
	Position = O + Vector3.new(1, 43, 8.3),
	LookAt = O + Vector3.new(1, 3.2, -3),
	FieldOfView = 55,
})

local duelCameras = {
	table.freeze({
		Position = DO + Vector3.new(0, 68, -8),
		LookAt = DO + Vector3.new(0, 3.2, 2),
		FieldOfView = 60,
	}),
	table.freeze({
		Position = DO + Vector3.new(0, 68, 8),
		LookAt = DO + Vector3.new(0, 3.2, -2),
		FieldOfView = 60,
	}),
}

Layout.CoopCamera = table.freeze({
	Position = CO + Vector3.new(-1, 68, 14),
	LookAt = CO + Vector3.new(-1, 3.2, 0),
	FieldOfView = 56,
})

-- Duel cameras: a player's own board is at the bottom of the screen. Seat 2 sits on the +z side looking toward -z,
-- seat 1 is the same view turned 180 degrees about the map's centre. Both boards, both routes and both portals stay
-- inside the screen at 844x390 and 667x375 (checked with perspective projection, margins >= 0.15 of half-screen).
function Layout.DuelCamera(seat: number?)
	return if seat == 2 then duelCameras[2] else duelCameras[1]
end

return table.freeze(Layout)
