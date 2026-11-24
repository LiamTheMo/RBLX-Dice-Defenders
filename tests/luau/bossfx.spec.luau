-- BossFxData: palettes cover each boss, budgets stay within the per-boss live cap, particle counts shrink on phones and
-- vanish in reduced motion, the spiral / portal / confetti curves behave.

local Data = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Effects.BossFxData)
local Bosses = require(game:GetService("ReplicatedStorage").Shared.Bosses)

test("every boss has a palette and a budget within the live cap", function()
	for _, id in Bosses.List do
		expect(next(Data.Palette[id]) ~= nil, "palette " .. id)
		local overlap = 0
		for _, n in Data.Budget[id] do
			overlap += n
		end
		expect(overlap <= Data.MaxLive, "budget " .. id .. " " .. overlap)
	end
end)

test("windup seconds are clamped", function()
	expectEq(Data.WindupSeconds(11, 10), 1, "normal")
	expectEq(Data.WindupSeconds(10, 10.5), 0.2, "late")
	expectEq(Data.WindupSeconds(50, 10), 2, "far")
end)

test("counts: full, half on Low, none when reduced", function()
	expectEq(Data.Count(10, false, false), 10, "full")
	expectEq(Data.Count(9, true, false), 5, "low")
	expectEq(Data.Count(10, false, true), 0, "reduced")
	expectEq(Data.Count(10, true, true), 0, "reduced beats low")
end)

test("spiral stays in its cylinder and climbs", function()
	for k = 1, 10 do
		for _, u in { 0, 0.3, 1 } do
			local x, y, z = Data.Spiral(k, 10, u, 4.5, 8, 1.5)
			expect(math.sqrt(x * x + z * z) <= 4.5 + 1e-9, "radius")
			expect(y >= 0 and y <= 8, "height")
		end
	end
end)

test("the portal grows in like a spawning die, stays open, then shrinks closed", function()
	expect(Data.PortalScale(0, 1.5) < 0.01, "starts tiny")
	expect(math.abs(Data.PortalScale(0.125, 1.5) - (1 - 0.999 * 0.25)) < 1e-9, "same quad-out curve as the die")
	expectEq(Data.PortalScale(0.25, 1.5), 1, "full after 0.25 s")
	expectEq(Data.PortalScale(1.0, 1.5), 1, "open")
	expect(Data.PortalScale(1.5 + 0.125, 1.5) < 1, "closing")
	expect(Data.PortalScale(1.5 + 0.25, 1.5) < 0.01, "closed")
end)

test("confetti falls under gravity", function()
	local _, y0 = Data.Ballistic(1, 10, 1, 0, 22)
	local _, y1 = Data.Ballistic(1, 10, 1, 2, 22)
	expectEq(y0, 0, "start")
	expect(y1 < 0, "landed below launch")
end)
