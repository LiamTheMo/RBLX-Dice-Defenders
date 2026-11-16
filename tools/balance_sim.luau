-- Balance sim: which wave does a deck reach? Run: python tools/balance_sim.py [seeds]  (bot summons and merges; real Match/Formulas/Balance)
local Server = game:GetService("ServerScriptService").Server
local Match = require(Server.Rules.Match)
local Dice = require(Server.Config.Dice)

local P = { seeds = __SEEDS or 40, dt = 0.25, maxWave = 200 } -- dt = Balance.MaxStep; the live tick is 0.1

local function bot(state)
	while Match.TrySummon(state) do
	end
	local merged = true
	while merged do
		merged = false
		local best -- {pip, from, to}
		for i = 1, 15 do
			local a = state.board[i]
			if a and a.pip < 7 then
				for j = i + 1, 15 do
					local b = state.board[j]
					if b and b.type == a.type and b.pip == a.pip and (not best or a.pip < best[1]) then
						best = { a.pip, i, j }
						break
					end
				end
			end
		end
		if best and Match.TryMerge(state, best[2], best[3]) then
			merged = true
			while Match.TrySummon(state) do
			end
		end
	end
end

local function run(deck, seed)
	local state = Match.New(1, Random.new(seed), 0, deck)
	local now = 0
	for _ = 1, 3000000 do
		now += P.dt
		Match.Step(state, now)
		Match.TakeOut(state)
		if state.phase ~= "Playing" or state.wave > P.maxWave then
			break
		end
		bot(state)
	end
	return state.wave
end

local function batch(name, deck)
	local waves = {}
	for s = 1, P.seeds do
		table.insert(waves, run(deck, s * 7919))
	end
	table.sort(waves)
	print("  all: " .. table.concat(waves, " "))
	local median = waves[(#waves + 1) // 2]
	print(`{name}: deck={table.concat(deck, ",")} lost wave min/median/max = {waves[1]}/{median}/{waves[#waves]}`)
end

test("sim", function()
	batch("starter", Dice.Deck)
	local ids = {}
	for id, cfg in Dice.Types do
		if cfg.rarity == "Rare" or cfg.rarity == "Epic" or cfg.rarity == "Legendary" then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		local x, y = Dice.Types[a].base * Dice.Types[a].rate, Dice.Types[b].base * Dice.Types[b].rate
		if x ~= y then
			return x > y
		end
		return a < b
	end)
	batch("strong", { ids[1], ids[2], ids[3], ids[4], ids[5] })
end)
