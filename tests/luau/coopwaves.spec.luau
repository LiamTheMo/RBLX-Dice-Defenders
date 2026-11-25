-- Random Dice HP model (Config/CoopWaves): step table, the b chain, Fast / Mini-Boss / Boss multipliers, and the schedule.
local Server = game:GetService("ServerScriptService").Server
local CoopWaves = require(Server.Config.CoopWaves)

test("step d: +30 early, +450 by wave 25, then +150 every 5 waves", function()
	expectEq(CoopWaves.Step(1), 30, "d 1")
	expectEq(CoopWaves.Step(4), 30, "d 4")
	expectEq(CoopWaves.Step(5), 60, "d 5")
	expectEq(CoopWaves.Step(10), 90, "d 10")
	expectEq(CoopWaves.Step(20), 300, "d 20")
	expectEq(CoopWaves.Step(25), 450, "d 25")
	expectEq(CoopWaves.Step(34), 450 + 150, "d 34")
	expectEq(CoopWaves.Step(35), 450 + 300, "d 35")
end)

test("wave 1 starts at 100; slot n = b + d x n; the next wave starts at the last regular base", function()
	local queue, nextBase = CoopWaves.Next(1, CoopWaves.InitialHp)
	expectEq(#queue, 10, "ten regular slots")
	expectEq(queue[1].hp, 130, "slot 1")
	expectEq(queue[10].hp, 400, "slot 10")
	expectEq(queue[10].kind, "Grunt", "no runner on wave 1")
	expectEq(nextBase, 400, "wave 2 starts at 400")
end)

test("the base chain carries across waves: b10 = 4300", function()
	local base = CoopWaves.InitialHp
	for wave = 1, 9 do
		local _, nextBase = CoopWaves.Next(wave, base)
		base = nextBase
	end
	expectEq(base, 4300, "b10")
end)

test("Mini-Boss (brute) x5 on the first brute, and the last slot of a brute wave is a Runner at half HP", function()
	local queue = CoopWaves.Next(3, 700)
	expectEq(queue[1].kind, "Brute", "wave 3 brute")
	expectEq(queue[1].hp, 3650, "730 x 5")
	expectEq(queue[10].kind, "Runner", "fast slot")
	expectEq(queue[10].hp, 500, "(700 + 300) / 2")
end)

test("Boss x10 on wave 5, x11.5 on the second boss (wave 10)", function()
	local queue = CoopWaves.Next(5, 1300)
	expectEq(#queue, 1, "boss waves queue one boss")
	expectEq(queue[1].kind, "Boss", "wave 5 boss")
	expectEq(queue[1].hp, 13600, "(1300 + 60) x 10")
	local _, nextBase = CoopWaves.Next(5, 1300)
	expectEq(nextBase, 1900, "wave 6 starts at 1900")
	local second = CoopWaves.Next(10, 4300)
	expectEq(second[1].hp, 50485, "(4300 + 90) x 11.5")
end)

test("Duel plain waves: ten mobs and Runners grow with the wave, no boss or brute", function()
	local queue = CoopWaves.Next(3, 700, true)
	expectEq(queue[1].kind, "Grunt", "no brute in Duel")
	expectEq(queue[10].kind, "Runner", "one runner from wave 3")
	expectEq(queue[10].hp, 500, "runner half HP")
end)

test("schedule: boss every 5th wave to 35 then odd waves; brute 3, 8 ... 33 then even from 36", function()
	local bosses, brutes = {}, {}
	for w = 1, 40 do
		if CoopWaves.IsBoss(w) then
			table.insert(bosses, w)
		end
		if CoopWaves.HasBrute(w) then
			table.insert(brutes, w)
		end
	end
	expectEq(table.concat(bosses, ","), "5,10,15,20,25,30,35,37,39", "boss waves")
	expectEq(table.concat(brutes, ","), "3,8,13,18,23,28,33,36,38,40", "brute waves")
end)
