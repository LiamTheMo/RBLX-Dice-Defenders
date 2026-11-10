-- Names and colours the client draws with. Keyed by the same ids the server sends.

local Display = {}

Display.Dice = table.freeze({
	C01 = table.freeze({ Name = "Pebble", Color = Color3.fromHex("#EC407A") }),
	C02 = table.freeze({ Name = "Needle", Color = Color3.fromHex("#1E88E5") }),
	C03 = table.freeze({ Name = "Hammer", Color = Color3.fromHex("#FB8C00") }),
	C04 = table.freeze({ Name = "Twinshot", Color = Color3.fromHex("#8E24AA") }),
	C05 = table.freeze({ Name = "Longshot", Color = Color3.fromHex("#00A86B") }),
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
