-- Server dice config vs client Display: same ids, names and rarities; Locked dice stay out of
-- the config; stat-only Rare/Epic/Legendary DPS beats every Common, on paper and in combat.

local Server = game:GetService("ServerScriptService").Server
local Dice = require(Server.Config.Dice)
local Enemies = require(Server.Config.Enemies)
local Board = require(Server.Rules.Board)
local Formulas = require(Server.Rules.Formulas)
local Catalog = require(Server.Rules.Catalog)
local Progression = require(Server.Config.Progression)
local Display = require(game:GetService("ReplicatedStorage").Shared.Display)

local RARITIES = { Common = true, Rare = true, Epic = true, Legendary = true, Mythic = true, Secret = true }

local function dps(cfg): number
	return cfg.base * cfg.rate * (cfg.shots or 1) * (cfg.shotMul or 1)
end

-- Sustained output on one target with perks: every shot (as Match deals them) plus Needle's averaged proc.
local function combatDps(id: string, pip: number, kind: string): number
	local cfg = Dice.Types[id]
	local proc = if cfg.procEvery then cfg.procFlat / cfg.procEvery else 0
	return (Formulas.HitDamage(id, kind) * (cfg.shots or 1) + proc) / Formulas.Period(id, pip)
end

test("config and Display.Dice hold the same ids with the same Name, Rarity and a distinct Color", function()
	local colors = {}
	for _, enemy in Display.Enemies do
		colors[("%.4f,%.4f,%.4f"):format(enemy.Color.R, enemy.Color.G, enemy.Color.B)] = true
	end
	for id, cfg in Dice.Types do
		local info = Display.Dice[id]
		expect(info ~= nil, "display entry " .. id)
		if info then
			expectEq(info.Name, cfg.name, "name " .. id)
			expectEq(info.Rarity, cfg.rarity, "rarity " .. id)
			expect(info.Color ~= nil, "color " .. id)
			local key = info.Color and ("%.4f,%.4f,%.4f"):format(info.Color.R, info.Color.G, info.Color.B)
			expect(key ~= nil and not colors[key], "distinct color " .. id)
			colors[key or id] = true
		end
	end
	for id in Display.Dice do
		expect(Dice.Types[id] ~= nil, "Display.Dice only lists playable dice: " .. id)
	end
end)

test("Locked dice are not playable and no id appears twice", function()
	local seen = {}
	for id in Display.Dice do
		seen[id] = true
	end
	for _, die in Display.Locked do
		expectEq(Dice.Types[die.Id], nil, "locked " .. die.Id .. " not in config")
		expect(not seen[die.Id], "unique " .. die.Id)
		seen[die.Id] = true
	end
	expect(seen.M01 and Dice.Types.M01 ~= nil, "Mythic Astral has a definition")
end)

test("every config die has a launch rarity", function()
	for id, cfg in Dice.Types do
		expect(RARITIES[cfg.rarity] == true, "rarity " .. id .. ": " .. tostring(cfg.rarity))
	end
end)

test("every non-Common stat-only DPS beats every Common", function()
	local best = 0
	for _, cfg in Dice.Types do
		if cfg.rarity == "Common" then
			best = math.max(best, dps(cfg))
		end
	end
	expect(best > 0, "commons present")
	for id, cfg in Dice.Types do
		if cfg.rarity ~= "Common" then
			expect(dps(cfg) > best, ("%s dps %.2f > best Common %.2f"):format(id, dps(cfg), best))
		end
	end
end)

test("in combat no non-Common is weaker than any Common, at every pip and enemy kind", function()
	for pip = 1, Board.MAX_PIP do
		for kind in Enemies.Kinds do
			local best = 0
			for id, cfg in Dice.Types do
				if cfg.rarity == "Common" then
					best = math.max(best, combatDps(id, pip, kind))
				end
			end
			for id, cfg in Dice.Types do
				if cfg.rarity ~= "Common" then
					local d = combatDps(id, pip, kind)
					expect(d > best, ("%s pip %d vs %s: %.2f > %.2f"):format(id, pip, kind, d, best))
				end
			end
		end
	end
end)

test("the client holds no die level cap of its own; the Catalog carries the server cap", function()
	local source = __sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/Bag/Tabs/Dice"]
	expect(source ~= nil, "Tabs/Dice source readable")
	expect(not string.find(source, "MaxLevel%s*=%s*%d"), "no hard-coded MaxLevel = <number>")
	expectEq(Catalog.Build().DieLevel.Max, Progression.DieLevel.Max, "Catalog DieLevel.Max")
end)
