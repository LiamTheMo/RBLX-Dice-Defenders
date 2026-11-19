-- Vertex outlines and triangulation from the Blender VFX sources, in studs.
local V = Vector3.new
local WEIGHT = require(script.Parent.ProjectileScale).ImpactWeight

local function bake(vertices, faces, thickness)
	local wedges = {}
	for face, indices in faces do
		local a, b, c = vertices[indices[1]], vertices[indices[2]], vertices[indices[3]]
		local ab, ac, bc = b - a, c - a, c - b
		if ab.Magnitude > ac.Magnitude and ab.Magnitude > bc.Magnitude then
			a, c = c, a
		elseif ac.Magnitude > bc.Magnitude then
			a, b = b, a
		end
		ab, ac, bc = b - a, c - a, c - b
		local right = ac:Cross(ab).Unit
		local back = bc.Unit
		local up = back:Cross(right).Unit
		local height = math.abs(ab:Dot(up))
		local widthA, widthB = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
		if widthA > 0.002 then
			table.insert(
				wedges,
				{ CFrame.fromMatrix((a + b) / 2, right, up, back), V(thickness, height, widthA), face }
			)
		end
		if widthB > 0.002 then
			table.insert(
				wedges,
				{ CFrame.fromMatrix((a + c) / 2, -right, up, -back), V(thickness, height, widthB), face }
			)
		end
	end
	return wedges
end

local Meshes = {
	Bake = bake,
	Crystal = bake({
		V(0, 0, 0.63),
		V(0, 0, -0.79),
		V(0.25, 0, 0),
		V(0, 0.31, 0),
		V(-0.25, 0, 0),
		V(0, -0.31, 0),
	}, {
		{ 1, 3, 4 },
		{ 1, 4, 5 },
		{ 1, 5, 6 },
		{ 1, 6, 3 },
		{ 2, 3, 4 },
		{ 2, 4, 5 },
		{ 2, 5, 6 },
		{ 2, 6, 3 },
	}, 0.026),
	Shard = bake({ V(-0.50, -0.26 * WEIGHT, 0), V(0.64, 0, 0), V(-0.50, 0.26 * WEIGHT, 0) }, {
		{ 3, 2, 1 },
	}, 0.10),
	Bolt = bake({
		V(0.65, 0, 0),
		V(-0.11, 0.33, 0),
		V(0.02, 0.10, 0),
		V(-0.54, 0, 0),
		V(0.02, -0.10, 0),
		V(-0.11, -0.33, 0),
	}, {
		{ 1, 2, 3 },
		{ 1, 3, 4 },
		{ 1, 4, 5 },
		{ 1, 5, 6 },
	}, 0.070),
	Diamond = bake({
		V(0, 0, 0.46),
		V(0, 0, -0.56),
		V(0.25, 0, 0),
		V(0, 0.37, 0),
		V(-0.25, 0, 0),
		V(0, -0.37, 0),
	}, {
		{ 1, 3, 4 },
		{ 1, 4, 5 },
		{ 1, 5, 6 },
		{ 1, 6, 3 },
		{ 2, 3, 4 },
		{ 2, 4, 5 },
		{ 2, 5, 6 },
		{ 2, 6, 3 },
	}, 0.032),
	Ember = bake({
		V(0, 0, 0.38),
		V(0.02, 0.06, -0.56),
		V(0.3, 0.14, -0.09),
		V(0.10, 0.38, -0.04),
		V(-0.22, 0.25, 0.02),
		V(-0.34, -0.12, 0.04),
		V(-0.10, -0.30, 0.01),
		V(0.26, -0.18, -0.19),
	}, {
		{ 1, 3, 4 },
		{ 1, 4, 5 },
		{ 1, 5, 6 },
		{ 1, 6, 7 },
		{ 1, 7, 8 },
		{ 1, 8, 3 },
		{ 2, 3, 4 },
		{ 2, 4, 5 },
		{ 2, 5, 6 },
		{ 2, 6, 7 },
		{ 2, 7, 8 },
		{ 2, 8, 3 },
	}, 0.035),
	Star = bake({
		V(0, 0.59, 0),
		V(-0.083, 0.115, 0),
		V(-0.561, 0.182, 0),
		V(-0.135, -0.044, 0),
		V(-0.347, -0.477, 0),
		V(0, -0.142, 0),
		V(0.347, -0.477, 0),
		V(0.135, -0.044, 0),
		V(0.561, 0.182, 0),
		V(0.083, 0.115, 0),
	}, {
		{ 10, 9, 8 },
		{ 8, 7, 6 },
		{ 6, 5, 4 },
		{ 4, 3, 2 },
		{ 2, 1, 10 },
		{ 10, 8, 6 },
		{ 6, 4, 2 },
		{ 10, 6, 2 },
	}, 0.055),
	Anvil = bake({
		V(-1.04, 0.40, 0),
		V(0.54, 0.40, 0),
		V(1.15, 0.49, 0),
		V(0.83, 0.22, 0),
		V(0.52, 0.12, 0),
		V(0.21, 0.08, 0),
		V(0.12, -0.29, 0),
		V(0.55, -0.41, 0),
		V(0.55, -0.56, 0),
		V(-0.66, -0.56, 0),
		V(-0.66, -0.41, 0),
		V(-0.31, -0.28, 0),
		V(-0.42, 0.10, 0),
		V(-1.04, 0.17, 0),
	}, {
		{ 1, 14, 13 },
		{ 12, 11, 10 },
		{ 2, 1, 13 },
		{ 12, 10, 9 },
		{ 2, 13, 12 },
		{ 4, 3, 2 },
		{ 6, 5, 4 },
		{ 9, 8, 7 },
		{ 6, 4, 2 },
		{ 12, 9, 7 },
		{ 6, 2, 12 },
		{ 12, 7, 6 },
	}, 0.16),
}

local flashes = {}
function Meshes.Flash(points: number, fan: boolean?)
	local key = if fan then -points else points
	if not flashes[key] then
		local vertices, faces = { Vector3.zero }, {}
		local count = 2 * points
		for i = 0, count - 1 do
			local angle = if fan then 0.08 + i * (math.pi - 0.16) / (count - 1) else math.pi / 2 + i * math.pi / points
			local radius = if i % 2 ~= 0
				then 0.23 * WEIGHT
				elseif fan then 0.64 + 0.40 * math.sin(angle)
				elseif i % 4 == 0 then 1
				else 0.73
			vertices[i + 2] = V(math.cos(angle) * radius, math.sin(angle) * radius, 0)
			if not fan or i < count - 1 then
				faces[i + 1] = { 1, i + 2, (i + 1) % count + 2 }
			end
		end
		flashes[key] = bake(vertices, faces, 0.045)
		assert(#flashes[key] >= points, "Missing impact flash faces")
	end
	return flashes[key]
end

return Meshes
