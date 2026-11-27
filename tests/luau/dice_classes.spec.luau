-- Class scaling (Config/DiceClasses): each die's numbers at its start class are the plain config, and at class 15 they
-- match the owner's class table; a match plays each die at its player's level (Match.New levels).

local Server = game:GetService("ServerScriptService").Server
local Dice = require(Server.Config.Dice)
local DiceClasses = require(Server.Config.DiceClasses)
local Progression = require(Server.Config.Progression)
local Match = require(Server.Rules.Match)
local Board = require(Server.Rules.Board)
local Enemies = require(Server.Config.Enemies)

local function near(a: number, b: number, label: string)
	expect(math.abs(a - b) < 1e-9, ("%s: expected %s, got %s"):format(label, tostring(b), tostring(a)))
end

local function startClass(id: string): number
	return Progression.Class(Dice.Types[id].rarity, 1)
end

test("at its start class a die plays exactly as its plain Config/Dice entry", function()
	for id, cfg in Dice.Types do
		local view = DiceClasses.View(id, startClass(id))
		expectEq(view.base, cfg.base, id .. " base")
		expectEq(view.rate, cfg.rate, id .. " rate")
		expectEq(view.shots or 1, cfg.shots or 1, id .. " shots")
		expectEq(view.procEvery, cfg.procEvery, id .. " procEvery")
		expectEq(view.chainEvery, cfg.chainEvery, id .. " chainEvery")
		expectEq(view.freezeEvery, cfg.freezeEvery, id .. " freezeEvery")
		expectEq(view.pierce, cfg.pierce, id .. " pierce")
		expectEq(#(view.cascade or {}), #(cfg.cascade or {}), id .. " cascade length")
		if cfg.vsKind then
			near(view.vsKind.Grunt, cfg.vsKind.Grunt, id .. " vsKind")
		end
		if cfg.poison then
			expectEq(view.poison.maxStacks, cfg.poison.maxStacks, id .. " stacks")
			near(view.poison.duration, cfg.poison.duration, id .. " poison duration")
		end
		if cfg.aura then
			near(view.aura.base, cfg.aura.base, id .. " aura")
		end
		if cfg.rift then
			expectEq(view.rift.every, cfg.rift.every, id .. " rift every")
			expectEq(view.rift.radius, cfg.rift.radius, id .. " rift radius")
		end
	end
end)

test("class 15 matches the owner's table", function()
	local function at15(id: string)
		return DiceClasses.View(id, 15)
	end
	near(at15("C01").vsKind.Grunt, 1.19, "Pebble +19% vs Grunts")
	expectEq(at15("C02").procEvery, 3, "Needle every 3rd")
	near(at15("C03").vsArmored, 1.40, "Hammer +40% vs armored")
	near(at15("C04").diffChance, 1.0, "Twinshot always a different enemy")
	near(at15("C05").slow, 0.14, "Longshot slow")
	near(at15("C06").slow, 0.29, "Chill slow")
	near(at15("C06").slowDuration, 2.2, "Chill duration")
	expectEq(at15("C07").chainEvery, 2, "Spark every 2nd")
	near(at15("R01").slowChance, 0.38, "Frost slow chance")
	expectEq(at15("R01").freezeEvery, 5, "Frost freeze every 5th")
	expectEq(#at15("R02").cascade, 5, "Arc front plus four chained")
	expectEq(at15("R03").shots, 5, "Volley five bolts")
	expectEq(at15("R04").poison.maxStacks, 7, "Venom seven stacks")
	near(at15("R05").aura.base, 0.12, "Beacon aura")
	expectEq(at15("E01").detonate.every, 4, "Emberstorm detonates every 4 s")
	near(at15("E03").pull.back, 0.16, "Gravity pull-back")
	expectEq(at15("E03").pull.count, 8, "Gravity pulls 8")
	near(at15("E03").pull.every, 5.5, "Gravity interval")
	near(at15("L01").rift.every, 7, "Chrono interval")
	expectEq(at15("L01").rift.radius, 26, "Chrono radius")
	expectEq(at15("L01").rift.rewindEvery, 2, "Chrono rewinds every 2nd")
	expectEq(at15("L01").rift.maxRewinds, 4, "Chrono max rewinds")
	expectEq(at15("L02").forge.every, 2, "Forge every 2nd")
	expectEq(at15("L02").forge.gap, 3, "Forge gap")
	expectEq(at15("S01").pierce, 5, "Wyvern pierces 5")
	expectEq(at15("S01").wyrmfire.every, 9, "Wyrmfire every 9 s")
end)

test("thresholds step at their class", function()
	expectEq(DiceClasses.View("C02", 4).procEvery, 6, "Needle class 4")
	expectEq(DiceClasses.View("C02", 5).procEvery, 5, "Needle class 5")
	expectEq(DiceClasses.View("C02", 10).procEvery, 4, "Needle class 10")
	expectEq(DiceClasses.View("R03", 9).shots, 3, "Volley class 9")
	expectEq(DiceClasses.View("R03", 10).shots, 4, "Volley class 10")
	expectEq(#DiceClasses.View("R02", 8).cascade, 3, "Arc class 8")
	expectEq(#DiceClasses.View("R02", 9).cascade, 4, "Arc class 9")
	expectEq(DiceClasses.View("S01", 12).pierce, 3, "Wyvern class 12")
	expectEq(DiceClasses.View("S01", 13).pierce, 4, "Wyvern class 13")
end)

test("a match plays each die at its player's level", function()
	local function firstHit(levels)
		local state = Match.New(1, Random.new(5), 0, Dice.Deck, nil, 0, nil, levels)
		state.critChance = 0
		state.waveState = "Active"
		state.wave = 1
		state.queue = { { kind = "Grunt", hp = 20 } }
		state.qi = 1
		state.nextSpawnAt = math.huge
		Board.Summon(state.board, 5, "C01", state.nextDieId)
		state.nextDieId += 1
		state.board[5].pip = 1
		state.board[5].cd = state.lastNow
		local speed = Enemies.Kinds.Grunt.speed
		local enemy = {
			id = 1,
			kind = "Grunt",
			hp = 1e9,
			maxHp = 1e9,
			speed = speed,
			spawnAt = state.lastNow - 56 / speed,
			dist = 56,
		}
		state.nextEnemyId = 2
		table.insert(state.enemies, enemy)
		Match.Step(state, state.lastNow + 0.1)
		return enemy.maxHp - enemy.hp
	end
	expectEq(firstHit({}), math.floor(150 * 1.05 + 1e-9), "level 1: base with +5% vs Grunts")
	expectEq(firstHit({ C01 = 15 }), math.floor(150 * 1.19 * 6 + 1e-9), "level 15: +19% vs Grunts and x6 damage")
end)
