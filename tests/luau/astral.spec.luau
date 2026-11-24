local Server = game:GetService("ServerScriptService").Server
local Formulas = require(Server.Rules.Formulas)

test("Singularity applies only to the sole Astral on a board", function()
	local astral = { type = "M01", pip = 3 }
	expect(not Formulas.HasSingularity({ false, { type = "C01" } }), "zero Astral")
	expect(Formulas.HasSingularity({ false, astral, { type = "C01" } }), "one Astral at any pip count")
	expect(not Formulas.HasSingularity({ astral, false, { type = "M01" } }), "two Astrals disable it")
	expectEq(Formulas.HitDamage("M01", "Grunt"), 140, "unbuffed")
	expectEq(Formulas.HitDamage("M01", "Grunt", nil, 1, true, false), 700, "exactly five times base")
	expectEq(Formulas.HitDamage("M01", "Grunt", nil, 1, true, true), 1400, "crit doubles the buffed hit")
	expectEq(Formulas.HitDamage("M01", "Grunt", nil, 2, true, true), 1540, "crit stacks with Power Up")
	expectEq(Formulas.HitDamage("C01", "Grunt", nil, 1, true, true), 16, "other dice keep their own damage")
end)

test("Singularity crits on ten of one hundred tickets and skips the RNG when inactive", function()
	local ticket, draws = 10, 0
	local rng = {
		NextInteger = function(_, low, high)
			draws += 1
			expectEq(low, 1, "lower bound")
			expectEq(high, 100, "upper bound")
			return ticket
		end,
	}
	expect(Formulas.SingularityCrit("M01", true, rng), "ticket ten crits")
	ticket = 11
	expect(not Formulas.SingularityCrit("M01", true, rng), "ticket eleven misses")
	expect(not Formulas.SingularityCrit("M01", false, rng), "inactive")
	expect(not Formulas.SingularityCrit("C01", true, rng), "other dice never crit from this ability")
	expectEq(draws, 2, "unrelated combat keeps the existing RNG stream")
end)
