-- Names and colours the client draws with. Keyed by the same ids the server sends.

local Display = {}

Display.Dice = table.freeze({
	C01 = table.freeze({ Name = "Pebble", Rarity = "Common", Color = Color3.fromHex("#EC407A") }),
	C02 = table.freeze({ Name = "Needle", Rarity = "Common", Color = Color3.fromHex("#1E88E5") }),
	C03 = table.freeze({ Name = "Hammer", Rarity = "Common", Color = Color3.fromHex("#FB8C00") }),
	C04 = table.freeze({ Name = "Twinshot", Rarity = "Common", Color = Color3.fromHex("#8E24AA") }),
	C05 = table.freeze({ Name = "Longshot", Rarity = "Common", Color = Color3.fromHex("#00A86B") }),
})

-- Catalogue dice with no server config yet: shown as "Not available yet".
Display.Locked = table.freeze({
	table.freeze({ Id = "R01", Name = "Frost", Rarity = "Rare" }),
	table.freeze({ Id = "R02", Name = "Arc", Rarity = "Rare" }),
	table.freeze({ Id = "R03", Name = "Volley", Rarity = "Rare" }),
	table.freeze({ Id = "R04", Name = "Venom", Rarity = "Rare" }),
	table.freeze({ Id = "R05", Name = "Beacon", Rarity = "Rare" }),
	table.freeze({ Id = "E01", Name = "Emberstorm", Rarity = "Epic" }),
	table.freeze({ Id = "E02", Name = "Reactor", Rarity = "Epic" }),
	table.freeze({ Id = "E03", Name = "Mirror", Rarity = "Epic" }),
	table.freeze({ Id = "E04", Name = "Catalyst", Rarity = "Epic" }),
	table.freeze({ Id = "E05", Name = "Gravity", Rarity = "Epic" }),
	table.freeze({ Id = "L01", Name = "Chrono", Rarity = "Legendary" }),
	table.freeze({ Id = "L02", Name = "Forge", Rarity = "Legendary" }),
	table.freeze({ Id = "L03", Name = "Prism", Rarity = "Legendary" }),
	table.freeze({ Id = "M01", Name = "Astral", Rarity = "Mythic" }),
})

Display.Enemies = table.freeze({
	Grunt = table.freeze({ Name = "Grunt", Color = Color3.fromHex("#F5F5F5") }),
	Runner = table.freeze({ Name = "Runner", Color = Color3.fromHex("#00E5FF") }),
	Brute = table.freeze({ Name = "Brute", Color = Color3.fromHex("#3949AB") }),
	Boss = table.freeze({ Name = "Thorn Warden", Color = Color3.fromHex("#101010") }),
})

-- Pip count shown on a die; pip 7 is the star tier.
function Display.PipLabel(pip: number): string
	if pip >= 7 then
		return "7\u{2605}"
	end
	return tostring(pip)
end

return table.freeze(Display)
