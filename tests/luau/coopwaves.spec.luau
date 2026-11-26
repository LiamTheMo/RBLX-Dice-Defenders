-- Random Dice HP model (Config/CoopWaves): step table, the b chain, Fast / Mini-Boss / Boss multipliers, and the schedule.
local Server = game:GetService("ServerScriptService").Server
local CoopWaves = require(Server.Config.CoopWaves)

test(
	"step d (owner's Random Dice spec): 10 at wave 1, +10/wave to 10, then +10 x ceil(w/10) to 50, +50 x ceil(w/10) from 51",
	function()
		local want = {
			[1] = 10,
			[2] = 20,
			[10] = 100,
			[11] = 120,
			[20] = 300,
			[21] = 330,
			[30] = 600,
			[40] = 1000,
			[50] = 1500,
			[51] = 1800,
			[52] = 2100,
		}
		for w, d in want do
			expectEq(CoopWaves.Step(w), d, "d " .. w)
		end
	end
)

test("wave 1 is 110..200 (b 100, d 10); the next wave starts at the last regular base", function()
	local queue, nextBase = CoopWaves.Next(1, CoopWaves.InitialHp)
	expectEq(#queue, 10, "ten regular slots")
	expectEq(queue[1].hp, 110, "slot 1")
	expectEq(queue[10].hp, 200, "slot 10")
	expectEq(queue[10].kind, "Grunt", "no runner on wave 1")
	expectEq(nextBase, 200, "b2 = 200")
end)

test("the base chain carries across waves: b2 200, b10 4600, b11 5600, b12 6800", function()
	local base, want = CoopWaves.InitialHp, { 200, 400, 700, 1100, 1600, 2200, 2900, 3700, 4600, 5600, 6800 }
	for wave = 1, 11 do
		local _, nextBase = CoopWaves.Next(wave, base)
		base = nextBase
		expectEq(base, want[wave], "b" .. wave + 1)
	end
	local queue = CoopWaves.Next(11, 5600)
	expectEq(queue[1].hp, 5720, "wave 11 slot 1 = 5600 + 120")
	expectEq(queue[10].hp, 6800, "wave 11 slot 10")
end)

test(
	"Mini-Boss (brute) x5 on the first brute (wave 4), x6.5 on the second (wave 9); the last slot is a Runner at half HP",
	function()
		local queue = CoopWaves.Next(4, 700)
		expectEq(queue[1].kind, "Brute", "wave 4 brute")
		expectEq(queue[1].hp, 3700, "(700 + 40) x 5")
		expectEq(queue[10].kind, "Runner", "fast slot")
		expectEq(queue[10].hp, 550, "(700 + 400) / 2")
		expectEq(CoopWaves.Next(9, 3700)[1].hp, 24635, "(3700 + 90) x 6.5")
		expectEq(CoopWaves.Next(3, 400)[1].kind, "Grunt", "wave 3 is a plain wave now")
	end
)

test("Boss x10 on wave 5, x11.5 on the second boss (wave 10)", function()
	local queue, nextBase = CoopWaves.Next(5, 1100)
	expectEq(#queue, 1, "boss waves queue one boss")
	expectEq(queue[1].kind, "Boss", "wave 5 boss")
	expectEq(queue[1].hp, 11500, "(1100 + 50) x 10")
	expectEq(nextBase, 1600, "wave 6 starts at 1600")
	expectEq(CoopWaves.Next(10, 4600)[1].hp, 54050, "(4600 + 100) x 11.5")
end)

test("Duel plain waves: ten mobs and Runners grow with the wave, no boss or brute", function()
	local queue = CoopWaves.Next(3, 400, true)
	expectEq(queue[1].kind, "Grunt", "no brute in Duel")
	expectEq(queue[10].kind, "Runner", "one runner from wave 3")
	expectEq(queue[10].hp, 350, "runner half HP")
end)

test(
	"schedule: boss every 5th wave to 35 then odd waves; brute on x4/x9 to 35, then x3/x8 with a boss winning a clash",
	function()
		local bosses, brutes = {}, {}
		for w = 1, 60 do
			if CoopWaves.IsBoss(w) then
				table.insert(bosses, w)
			end
			if CoopWaves.HasBrute(w) then
				table.insert(brutes, w)
			end
			expect(not (CoopWaves.IsBoss(w) and CoopWaves.HasBrute(w)), "never both on wave " .. w)
		end
		expectEq(table.concat(bosses, ","), "5,10,15,20,25,30,35,37,39,41,43,45,47,49,51,53,55,57,59", "boss waves")
		expectEq(table.concat(brutes, ","), "4,9,14,19,24,29,34,38,48,58", "brute waves (43 and 53 are boss waves)")
	end
)

test(
	"deep chain: b20 23600, b50 267600 (tenth 282600), wave 51 300600 last, b112 8361100; stays exact at wave 1500",
	function()
		local base, b = CoopWaves.InitialHp, {}
		for wave = 1, 1500 do
			b[wave] = base
			local _, nextBase = CoopWaves.Next(wave, base, true)
			base = nextBase
		end
		expectEq(b[20], 23600, "b20")
		expectEq(b[50], 267600, "b50")
		expectEq(b[51], 282600, "b51")
		expectEq(CoopWaves.Next(51, 282600, true)[1].hp, 284400, "wave 51 first")
		expectEq(b[52], 300600, "wave 51 tenth / b52")
		expectEq(b[112], 8361100, "b112")
		expectEq(b[1000], 8388055100, "b1000")
		expectEq(b[1500], 28290492600, "b1500")
	end
)
