-- Planar impact silhouettes from the Common Blender scenes.
local Meshes = require(script.Parent.RarityMeshes)
local WEIGHT = require(script.Parent.ProjectileScale).ImpactWeight
local V = Vector3.new
local bake = Meshes.Bake

local needleVertices, needleFaces = {}, {}
for axis = 0, 3 do
	local turn = CFrame.Angles(0, 0, axis * math.pi / 2)
	for _, vertex in { V(0.37, 0, 0), V(0.245, 0.034 * WEIGHT, 0), V(0.12, 0, 0), V(0.245, -0.034 * WEIGHT, 0) } do
		table.insert(needleVertices, turn:VectorToWorldSpace(vertex))
	end
	local start = 4 * axis + 1
	table.insert(needleFaces, { start, start + 1, start + 2 })
	table.insert(needleFaces, { start, start + 2, start + 3 })
end

local function star(points, inner, alternating)
	local vertices, faces = { Vector3.zero }, {}
	for i = 0, 2 * points - 1 do
		local angle = i * math.pi / points
		local radius = if i % 2 == 1 then inner * WEIGHT elseif alternating and i % 4 == 2 then 0.224 else 0.36
		vertices[i + 2] = V(math.cos(angle) * radius, math.sin(angle) * radius, 0)
		faces[i + 1] = { 1, i + 2, (i + 1) % (2 * points) + 2 }
	end
	return bake(vertices, faces, 0.018)
end

local function fan(vertices, faces, thickness)
	for _, face in faces do
		local a, b, c = vertices[face[1]], vertices[face[2]], vertices[face[3]]
		local direction = (a + b + c).Unit
		local side = V(-direction.Y, direction.X, 0)
		local center = (a + b + c):Dot(side) / 3
		for _, index in face do
			local vertex = vertices[index]
			vertices[index] = vertex + side * ((vertex:Dot(side) - center) * (WEIGHT - 1))
		end
	end
	return bake(vertices, faces, thickness)
end

return table.freeze({
	Needle = bake(needleVertices, needleFaces, 0.028),
	Hammer = fan({
		V(-0.015, 0.214, 0),
		V(0.0302, 0.6803, 0),
		V(-0.1246, 0.6694, 0),
		V(-0.1463, 0.1569, 0),
		V(-0.4489, 0.6192, 0),
		V(-0.5864, 0.491, 0),
		V(-0.2133, 0.0224, 0),
		V(-0.6317, 0.146, 0),
		V(-0.6483, -0.0115, 0),
	}, { { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 } }, 0.035),
	Twinshot = fan({
		V(-0.055, 0.035, 0),
		V(-0.095, 0.118, 0),
		V(-0.43, 0.155, 0),
		V(-0.055, -0.038, 0),
		V(-0.12, -0.125, 0),
		V(-0.37, -0.15, 0),
	}, { { 3, 2, 1 }, { 6, 5, 4 } }, 0.03),
	Chill = star(4, 0.053, false),
	Spark = star(8, 0.053, true),
})
