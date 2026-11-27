-- Legendary/Mythic dice models: each wired id has 7 bodies and marks, a texture, and well-formed Parts.

local Dice = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Dice
local Display = require(game:GetService("ReplicatedStorage").Shared.Display)

test("wired L/M dice carry complete model data", function()
	local rarities = {
		LegendaryModelData = { "L01", "L02" },
		MythicModelData = { "M01" },
		SecretModelData = { "S01" },
	}
	for module, ids in rarities do
		local data = require(Dice[module])
		local count = 0
		for _ in data.Styles do
			count += 1
		end
		expect(count == #ids, module .. " holds exactly its style ids")
		for _, typeId in ids do
			local style = data.Styles[typeId]
			expect(style ~= nil and style.Name == Display.Dice[typeId].Name, typeId .. " style matches Display")
			local bodies, marks = style.Bodies or data.Bodies, style.Marks or data.Marks
			expect(#bodies == 7 and #marks == 7, typeId .. " has 7 bodies and marks")
			expect(type(style.Texture) == "string", typeId .. " texture")
			local parts = data.Parts[typeId]
			expect(parts ~= nil and parts.Gem ~= nil and parts.Trim ~= nil, typeId .. " has Gem and Trim")
			for name, part in parts do
				expect(
					string.match(part.Color, "^#%x%x%x%x%x%x$") ~= nil and #part.Mesh > 0,
					typeId .. " part " .. name
				)
				expect(name ~= "ChamferedBody" and name ~= "Pips" and name ~= "Stars", typeId .. " part name clash")
			end
		end
	end
end)
