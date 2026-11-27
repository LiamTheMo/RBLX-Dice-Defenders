-- Class scaling: what each die's ability numbers are at a given class (class = level + the rarity's offset, see
-- Config/Progression). Every die starts at its rarity's start class, where these equal the plain Config/Dice values,
-- and a function here returns only the top-level keys that change with class; View merges them over the base entry.
-- Ramps are linear from the die's start class (so "per class" below = per class above the start); step thresholds are
-- "from class N". All numbers are the owner's class table (2026-11-27). Damage growth is separate (Progression.DamageMul).
local Dice = require(script.Parent.Dice)

local DiceClasses = {}

-- n at `from` rising by `per` each class above `start`.
local function ramp(class: number, start: number, from: number, per: number): number
	return from + per * (class - start)
end

-- value of the highest threshold class <= `class`: pick(c, 6, { { 5, 5 }, { 10, 4 }, { 15, 3 } }).
local function pick(class: number, base: number, steps: { { number } }): number
	local value = base
	for _, step in steps do
		if class >= step[1] then
			value = step[2]
		end
	end
	return value
end

local scale = {
	C01 = function(c)
		return { vsKind = { Grunt = ramp(c, 1, 1.05, 0.01) } }
	end,
	C02 = function(c)
		return { procEvery = pick(c, 6, { { 5, 5 }, { 10, 4 }, { 15, 3 } }) }
	end,
	C03 = function(c)
		return { vsArmored = ramp(c, 1, 1.12, 0.02) }
	end,
	C04 = function(c)
		return { diffChance = ramp(c, 1, 0.5, 0.5 / 14) } -- 50% at class 1 to 100% at class 15
	end,
	C05 = function(c)
		return { slow = 0.01 * (c - 1), slowDuration = 1.5, slowKinds = { Brute = true, Boss = true } }
	end,
	C06 = function(c)
		return { slow = ramp(c, 1, 0.15, 0.01), slowDuration = ramp(c, 1, 1.5, 0.05) }
	end,
	C07 = function(c)
		return { chainEvery = pick(c, 4, { { 8, 3 }, { 15, 2 } }) }
	end,
	R01 = function(c)
		return {
			slowChance = ramp(c, 3, 0.20, 0.015),
			freezeEvery = pick(c, 8, { { 7, 7 }, { 11, 6 }, { 15, 5 } }),
		}
	end,
	R02 = function(c)
		local cascade = { 0.9, 0.4, 0.2 } -- front, then the enemies behind it: 2 chained, 3 from class 9, 4 from class 15
		if c >= 9 then
			table.insert(cascade, 0.1)
		end
		if c >= 15 then
			table.insert(cascade, 0.05)
		end
		return { cascade = cascade }
	end,
	R03 = function(c)
		return { shots = pick(c, 3, { { 10, 4 }, { 15, 5 } }) }
	end,
	R04 = function(c)
		return {
			poison = {
				dps = 75,
				duration = ramp(c, 3, 4, 0.1),
				maxStacks = pick(c, 4, { { 7, 5 }, { 11, 6 }, { 15, 7 } }),
			},
		}
	end,
	R05 = function(c)
		local aura = Dice.Types.R05.aura
		return { aura = { base = ramp(c, 3, aura.base, 0.005), perPip = aura.perPip, perTier = aura.perTier } }
	end,
	E01 = function(c)
		return {
			burn = { dps = 375, duration = ramp(c, 5, 3, 0.1) },
			detonate = { every = pick(c, 6, { { 11, 5 }, { 15, 4 } }), radius = ramp(c, 5, 10, 0.5) },
		}
	end,
	E03 = function(c)
		local pull = Dice.Types.E03.pull
		return {
			pull = {
				every = pick(c, 7, { { 15, 5.5 } }),
				count = pick(c, 5, { { 15, 8 } }),
				back = ramp(c, 5, 0.12, 0.004),
				bossSlow = pull.bossSlow,
				bossSlowFor = pull.bossSlowFor,
			},
		}
	end,
	L01 = function(c)
		local rift = table.clone(Dice.Types.L01.rift)
		rift.every = pick(c, 10, { { 15, 7 } })
		rift.radius = ramp(c, 7, 18, 1)
		rift.rewindEvery = pick(c, 3, { { 12, 2 } })
		rift.maxRewinds = pick(c, 3, { { 15, 4 } })
		return { rift = rift }
	end,
	L02 = function(c)
		return { forge = { every = pick(c, 4, { { 11, 3 }, { 15, 2 } }), gap = pick(c, 5, { { 15, 3 } }) } }
	end,
	S01 = function(c)
		local fire = table.clone(Dice.Types.S01.wyrmfire)
		fire.every = pick(c, 12, { { 15, 9 } })
		fire.pct = ramp(c, 11, 0.004, 0.0005)
		return { pierce = pick(c, 3, { { 13, 4 }, { 15, 5 } }), wyrmfire = fire }
	end,
}

local cache = {}

-- The die's config at `class` (the plain entry for a die without class scaling). Cached; treat as read-only.
function DiceClasses.View(typeId: string, class: number)
	local base = Dice.Types[typeId]
	local make = scale[typeId]
	if make == nil then
		return base
	end
	local perDie = cache[typeId]
	if perDie == nil then
		perDie = {}
		cache[typeId] = perDie
	end
	local view = perDie[class]
	if view == nil then
		view = table.clone(base)
		for key, value in make(class) do
			view[key] = value
		end
		perDie[class] = view
	end
	return view
end

-- The ability numbers the Bag shows for a die at `class` (and the green "+N" an UPGRADE adds): { { Label, Value, Suffix? } }
-- in display order. `damageMul` is the level's hit-damage multiplier (Needle's flat bonus grows with it).
local function pct(fraction: number): number
	return math.floor(fraction * 1000 + 0.5) / 10
end

local function hundredth(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

local function tenth(n: number): number
	return math.floor(n * 10 + 0.5) / 10
end

local shown = {
	C01 = function(v)
		return { { "Grunt Bonus", pct(v.vsKind.Grunt - 1), "%" } }
	end,
	C02 = function(v, mul)
		return {
			{ "Boost Every", v.procEvery, " hits" },
			{ "Boost Damage", math.floor(v.procFlat * mul + 1e-9) },
		}
	end,
	C03 = function(v)
		return { { "Armor Bonus", pct(v.vsArmored - 1), "%" } }
	end,
	C04 = function(v)
		return { { "Split Chance", pct(v.diffChance), "%" } }
	end,
	C05 = function(v)
		return { { "Slow", pct(v.slow), "%" } }
	end,
	C06 = function(v)
		return { { "Chill Chance", pct(v.slow), "%" }, { "Chill Time", hundredth(v.slowDuration), "s" } }
	end,
	C07 = function(v)
		return { { "Chain Every", v.chainEvery, " hits" } }
	end,
	R01 = function(v)
		return { { "Slow Chance", pct(v.slowChance), "%" }, { "Freeze Every", v.freezeEvery, " hits" } }
	end,
	R02 = function(v)
		return { { "Chained Enemies", #v.cascade - 1 } }
	end,
	R03 = function(v)
		return { { "Bolts", v.shots } }
	end,
	R04 = function(v)
		return { { "Max Stacks", v.poison.maxStacks }, { "Poison Time", tenth(v.poison.duration), "s" } }
	end,
	R05 = function(v)
		return { { "Aura", pct(v.aura.base), "%" } }
	end,
	E01 = function(v)
		return {
			{ "Burn Time", tenth(v.burn.duration), "s" },
			{ "Blast Every", v.detonate.every, "s" },
			{ "Blast Radius", tenth(v.detonate.radius) },
		}
	end,
	E03 = function(v)
		return {
			{ "Pull Every", v.pull.every, "s" },
			{ "Pulled", v.pull.count },
			{ "Pull Back", pct(v.pull.back), "%" },
		}
	end,
	L01 = function(v)
		return {
			{ "Rift Every", v.rift.every, "s" },
			{ "Rift Radius", v.rift.radius },
			{ "Rewind Every", v.rift.rewindEvery, " rifts" },
			{ "Max Rewinds", v.rift.maxRewinds },
		}
	end,
	L02 = function(v)
		return { { "Free Die Every", v.forge.every, " merges" }, { "Free Die Gap", v.forge.gap, "s" } }
	end,
	S01 = function(v)
		return {
			{ "Pierce", v.pierce },
			{ "Wyrmfire Every", v.wyrmfire.every, "s" },
			{ "Wyrmfire Burn", math.floor(v.wyrmfire.pct * 10000 + 0.5) / 100, "%/s" },
		}
	end,
}

function DiceClasses.Stats(typeId: string, class: number, damageMul: number?)
	local show = shown[typeId]
	if show == nil then
		return {}
	end
	return show(DiceClasses.View(typeId, class), damageMul or 1)
end

return table.freeze(DiceClasses)
