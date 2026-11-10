-- Summon cost sequence, summon/merge legality, full board, no mutation on reject.

local Server = game:GetService("ServerScriptService").Server
local Board = require(Server.Rules.Board)
local Match = require(Server.Rules.Match)
local Formulas = require(Server.Rules.Formulas)
local Dice = require(Server.Config.Dice)

local NAN, INF = 0 / 0, math.huge

local function ser(v)
	if type(v) ~= "table" then
		return tostring(v)
	end
	local keys = {}
	for k in v do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in keys do
		table.insert(parts, tostring(k) .. ":" .. ser(v[k]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function place(board, cell, typeId, pip)
	Board.Summon(board, cell, typeId, cell)
	board[cell].pip = pip or 1
end

test("summon cost: min(250, max(10, floor(10 * 1.085^s)))", function()
	local expected = { [0] = 10, 10, 11, 12, 13, 15, 16, 17, 19, 20, 22, 24 }
	for s, cost in expected do
		expectEq(Formulas.SummonCost(s), cost, "cost after " .. s .. " summons")
	end
	expectEq(Formulas.SummonCost(20), 51, "s=20")
	expectEq(Formulas.SummonCost(39), 240, "s=39")
	expectEq(Formulas.SummonCost(40), 250, "capped at 250")
	local last = 0
	for s = 0, 300 do
		local cost = Formulas.SummonCost(s)
		expect(cost >= last and cost >= 10 and cost <= 250, "monotonic and bounded at " .. s)
		last = cost
	end
end)

test("summon places a pip-1 die in an empty cell only", function()
	local board = Board.New()
	expectEq(#Board.EmptyCells(board), 15, "15 empty cells")
	expect(Board.Summon(board, 8, "C03", 1), "summon")
	local die = board[8]
	expect(die.type == "C03" and die.pip == 1 and die.id == 1, "pip-1 die of that type")
	expectEq(#Board.EmptyCells(board), 14, "one filled")
	local before = ser(board)
	for _, args in
		{
			{ 8, "C01" },
			{ 0, "C01" },
			{ 16, "C01" },
			{ 1.5, "C01" },
			{ NAN, "C01" },
			{ INF, "C01" },
			{ "3", "C01" },
			{ 3, "C99" },
			{ 3, 5 },
		}
	do
		local ok = Board.Summon(board, args[1], args[2], 2)
		expect(not ok, "rejects " .. tostring(args[1]) .. "/" .. tostring(args[2]))
	end
	expectEq(ser(board), before, "board unchanged by rejects")
end)

test("merge: same type and pip, both occupied, from ~= to; result is pip+1 and re-rolled type", function()
	local board = Board.New()
	place(board, 1, "C01", 1)
	place(board, 2, "C01", 1)
	local ok = Board.Merge(board, 1, 2, "C04")
	expect(ok, "legal merge")
	expectEq(board[1], false, "from cleared")
	expect(board[2].pip == 2 and board[2].type == "C04", "to is pip 2 with the new type")
	expectEq(board[2].hits, 0, "hit counter reset")
end)

test("illegal merges are rejected and change nothing", function()
	local board = Board.New()
	place(board, 1, "C01", 1)
	place(board, 2, "C02", 1)
	place(board, 3, "C01", 2)
	place(board, 4, "C01", 1)
	place(board, 5, "C05", 7)
	place(board, 6, "C05", 7)
	local before = ser(board)
	local cases = {
		{ 1, 2 }, -- different type
		{ 1, 3 }, -- different pip
		{ 1, 1 }, -- same cell
		{ 1, 9 }, -- empty target
		{ 9, 1 }, -- empty source
		{ 5, 6 }, -- pip 7 cannot merge
		{ 0, 1 },
		{ 1, 16 },
		{ 1.5, 4 },
		{ NAN, 4 },
		{ 1, INF },
		{ "1", 4 },
		{ nil, 4 },
	}
	for index, args in cases do
		local ok, code = Board.Merge(board, args[1], args[2], "C01")
		expect(not ok and code == "IllegalMerge", "case " .. index .. " rejected")
	end
	local ok2, code2 = Board.Merge(board, 1, 4, "C99")
	expect(not ok2 and code2 == "BadType", "unknown type rejected")
	local ok3 = Board.Merge(board, 1, 4, nil)
	expect(not ok3, "missing type rejected")
	expectEq(ser(board), before, "board byte-for-byte unchanged")
end)

test("pip climbs to 7 through merges, then stops", function()
	local board = Board.New()
	place(board, 1, "C01", 6)
	place(board, 2, "C01", 6)
	expect(Board.Merge(board, 1, 2, "C01"), "6+6 -> 7")
	expectEq(board[2].pip, 7, "pip 7")
	place(board, 3, "C01", 7)
	local ok = Board.Merge(board, 3, 2, "C01")
	expect(not ok, "7 cannot merge")
end)

test("a full board rejects summon without spending Energy or consuming randomness", function()
	local rng = Random.new(5)
	local state = Match.New(1, rng, 0)
	state.energy = 100000
	for _ = 1, 15 do
		state.energy = 100000
		expect(Match.TrySummon(state), "summon until full")
	end
	expectEq(#Board.EmptyCells(state.board), 0, "board full")
	local before = ser(state.board) .. state.energy .. state.summons .. state.nextDieId
	local rngBefore = rng._state
	local ok, code = Match.TrySummon(state)
	expect(not ok and code == "BoardFull", "BoardFull")
	expectEq(ser(state.board) .. state.energy .. state.summons .. state.nextDieId, before, "state unchanged")
	expectEq(rng._state, rngBefore, "rng not consumed")
end)

test("summons spend the rising cost; NoEnergy leaves state unchanged; deck types only", function()
	local state = Match.New(1, Random.new(9), 0)
	expectEq(state.energy, 20, "start energy")
	expect(Match.TrySummon(state), "first summon")
	expectEq(state.energy, 10, "cost 10")
	expect(Match.TrySummon(state), "second summon (cost 10)")
	expectEq(state.energy, 0, "spent")
	expectEq(Match.SummonCost(state), 11, "third costs 11")
	local before = ser(state.board) .. state.energy .. state.summons
	local ok, code = Match.TrySummon(state)
	expect(not ok and code == "NoEnergy", "no energy")
	expectEq(ser(state.board) .. state.energy .. state.summons, before, "unchanged on reject")
	for _, die in state.board do
		if die then
			expect(table.find(Dice.Deck, die.type) ~= nil and die.pip == 1, "deck type pip 1")
		end
	end
end)

test("Match.TryMerge validates before rolling; reject leaves everything, including rng, unchanged", function()
	local state = Match.New(1, Random.new(3), 0)
	place(state.board, 1, "C01", 1)
	place(state.board, 2, "C02", 1)
	local before = ser(state.board)
	local reference = Random.new(3)
	local ok, code = Match.TryMerge(state, 1, 2)
	expect(not ok and code == "IllegalMerge", "illegal")
	expectEq(ser(state.board), before, "board unchanged")
	expectEq(state.rng:NextInteger(1, 1000000), reference:NextInteger(1, 1000000), "rng not consumed")
	state.board[2].type = "C01"
	expect(Match.TryMerge(state, 1, 2), "legal merge")
	expectEq(state.board[2].pip, 2, "merged")
	expectEq(state.board[1], false, "source cleared")
	state.phase = "Ended"
	local ok2, code2 = Match.TryMerge(state, 1, 2)
	expect(not ok2 and code2 == "WrongPhase", "not while ended")
end)
