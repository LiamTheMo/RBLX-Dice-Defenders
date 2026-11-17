-- Names and colours the client draws with. Keyed by the same ids the server sends.

local Display = {}

Display.Dice = table.freeze({
	C01 = table.freeze({ Name = "Pebble", Rarity = "Common", Color = Color3.fromHex("#EC407A") }),
	C02 = table.freeze({ Name = "Needle", Rarity = "Common", Color = Color3.fromHex("#1E88E5") }),
	C03 = table.freeze({ Name = "Hammer", Rarity = "Common", Color = Color3.fromHex("#FB8C00") }),
	C04 = table.freeze({ Name = "Twinshot", Rarity = "Common", Color = Color3.fromHex("#8E24AA") }),
	C05 = table.freeze({ Name = "Longshot", Rarity = "Common", Color = Color3.fromHex("#00A86B") }),
	C06 = table.freeze({ Name = "Chill", Rarity = "Common", Color = Color3.fromHex("#A4D5E9") }),
	C07 = table.freeze({ Name = "Spark", Rarity = "Common", Color = Color3.fromHex("#E8BB27") }),
	R01 = table.freeze({ Name = "Frost", Rarity = "Rare", Color = Color3.fromHex("#42AFD7") }),
	R02 = table.freeze({ Name = "Arc", Rarity = "Rare", Color = Color3.fromHex("#8866CC") }),
	R03 = table.freeze({ Name = "Volley", Rarity = "Rare", Color = Color3.fromHex("#DB7157") }),
	R04 = table.freeze({ Name = "Venom", Rarity = "Rare", Color = Color3.fromHex("#8EA112") }),
	R05 = table.freeze({ Name = "Beacon", Rarity = "Rare", Color = Color3.fromHex("#AE8104") }),
	E01 = table.freeze({ Name = "Emberstorm", Rarity = "Epic", Color = Color3.fromHex("#AE3204") }),
	E02 = table.freeze({ Name = "Reactor", Rarity = "Epic", Color = Color3.fromHex("#307326") }),
	E03 = table.freeze({ Name = "Mirror", Rarity = "Epic", Color = Color3.fromHex("#12A1A1") }),
	E04 = table.freeze({ Name = "Catalyst", Rarity = "Epic", Color = Color3.fromHex("#A82462") }),
	E05 = table.freeze({ Name = "Gravity", Rarity = "Epic", Color = Color3.fromHex("#736326") }),
	L01 = table.freeze({ Name = "Chrono", Rarity = "Legendary", Color = Color3.fromHex("#266E73") }),
	L02 = table.freeze({ Name = "Forge", Rarity = "Legendary", Color = Color3.fromHex("#AE5F04") }),
	L03 = table.freeze({ Name = "Prism", Rarity = "Legendary", Color = Color3.fromHex("#ED38FA") }),
	M01 = table.freeze({ Name = "Astral", Rarity = "Mythic", Color = Color3.fromHex("#46459B") }),
})

-- Catalogue dice with no server config yet: shown as "Not available yet".
Display.Locked = table.freeze({
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
