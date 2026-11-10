-- Names and colours the client draws with. Keyed by the same ids the server sends.

local Display = {}

Display.Dice = table.freeze({
	C01 = table.freeze({ Name = "Pebble", Color = Color3.fromRGB(176, 176, 176) }),
	C02 = table.freeze({ Name = "Needle", Color = Color3.fromRGB(96, 200, 232) }),
	C03 = table.freeze({ Name = "Hammer", Color = Color3.fromRGB(214, 120, 64) }),
	C04 = table.freeze({ Name = "Twinshot", Color = Color3.fromRGB(150, 110, 220) }),
	C05 = table.freeze({ Name = "Longshot", Color = Color3.fromRGB(96, 190, 110) }),
})

Display.Enemies = table.freeze({
	Grunt = table.freeze({ Name = "Grunt", Color = Color3.fromRGB(120, 170, 80) }),
	Runner = table.freeze({ Name = "Runner", Color = Color3.fromRGB(230, 200, 70) }),
	Brute = table.freeze({ Name = "Brute", Color = Color3.fromRGB(150, 70, 60) }),
	Boss = table.freeze({ Name = "Thorn Warden", Color = Color3.fromRGB(70, 120, 50) }),
})

-- Pip count shown on a die; pip 7 is the star tier.
function Display.PipLabel(pip: number): string
	if pip >= 7 then
		return "7\u{2605}"
	end
	return tostring(pip)
end

return table.freeze(Display)
