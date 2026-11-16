-- The client-visible display projection of the server catalogues, sent once per
-- player as the Catalog event. Pure. Arrays only (no sparse keys); the id lists
-- below Cosmetics keep config order, the others are sorted by Id. Never reads the
-- redeem code list.
--   { StarterDeck = { ids }, Dice = {{Id, Name, Rarity, Damage, Rate}},
--     Materials = {{Id, Name, Rarity, Description, Sell?}},
--     Items = {{Id, Name, Rarity, Description, Icon?, Sell?, Use?}},
--     Cosmetics = {{Id, Name, Rarity, Type, Slot, Description}},
--     Daily = { Days = {{Day, Chest?, Rewards}} }, Milestones = {{Id, Wave, Reachable, Rewards}},
--     Achievements = {{Id, Name, Desc, Goal, Badge, Rewards}},
--     Mastery = { Max, Need = { per level 1..Max-1 }, Milestones = {{Lv, Rewards}} },
--     DieLevel = { Max, Copies = { per level 1..Max-1 } },
--     Repeat = { PerWave = Rewards },
--     Roll = { Pools = {{Id, Name, Prices = {{Count, Gems}}, Odds = {{Rarity, Bp}}, Dice = {{Id, Rarity}},
--              Pity = {Rarity, Max}, Featured = { ids }}} },
--     Shop = { Offers = {{Id, Tab = "Featured"|"Gems", Name, Currency = "Gold"|"Gems"|"Robux", Price, Rewards,
--              Limit?, ProductId?, Available}} } }
-- Damage is a die's base damage, Rate its attacks per second; Use is display text
-- ("+100 XP"); Rewards are Rewards.Lines: {{Kind, Id?, Amount}}. Roll odds are basis points (sum 10000): the menu
-- shows exactly these numbers.
local Achievements = require(script.Parent.Parent.Config.Achievements)
local Balance = require(script.Parent.Parent.Config.Balance)
local Daily = require(script.Parent.Parent.Config.Daily)
local Dice = require(script.Parent.Parent.Config.Dice)
local Inventory = require(script.Parent.Parent.Config.Inventory)
local Milestones = require(script.Parent.Parent.Config.Milestones)
local Progression = require(script.Parent.Parent.Config.Progression)
local RollConfig = require(script.Parent.Parent.Config.Roll)
local ShopConfig = require(script.Parent.Parent.Config.Shop)
local Rewards = require(script.Parent.Rewards)

local Catalog = {}

local USE_LABEL = { Gold = "Gold", Gems = "Gems", Xp = "XP" }

local function byId(a, b)
	return a.Id < b.Id
end

-- "+100 XP" for { Xp = 100 }; parts in key order, joined by ", ".
local function useText(use): string?
	if use == nil then
		return nil
	end
	local parts = {}
	for key, amount in use do
		assert(USE_LABEL[key], "Catalog: no label for Use key " .. key)
		table.insert(parts, "+" .. amount .. " " .. USE_LABEL[key])
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

-- One row per entry of `map`, sorted by Id; `row(id, entry)` picks the fields.
local function rows(map, row)
	local list = {}
	for id, entry in map do
		table.insert(list, row(id, entry))
	end
	table.sort(list, byId)
	return list
end

-- One row per entry of the array `list`, in order.
local function map(list, row)
	local out = {}
	for _, entry in list do
		table.insert(out, row(entry))
	end
	return out
end

function Catalog.Build()
	local mastery, reward, dieLevel = Progression.Mastery, Balance.Reward, Progression.DieLevel
	local need = {}
	for level = 1, mastery.Max - 1 do
		need[level] = mastery.Need(level)
	end
	return {
		StarterDeck = table.clone(Dice.Deck),
		Dice = rows(Dice.Types, function(id, t)
			return { Id = id, Name = t.name, Rarity = t.rarity, Damage = t.base, Rate = t.rate }
		end),
		Materials = rows(Inventory.Materials, function(id, m)
			return { Id = id, Name = m.Name, Rarity = m.Rarity, Description = m.Description, Sell = m.Sell }
		end),
		Items = rows(Inventory.Items, function(id, item)
			return {
				Id = id,
				Name = item.Name,
				Rarity = item.Rarity,
				Description = item.Description,
				Icon = item.Icon,
				Sell = item.Sell,
				Use = useText(item.Use),
			}
		end),
		Cosmetics = rows(Inventory.Cosmetics, function(id, c)
			return {
				Id = id,
				Name = c.Name,
				Rarity = c.Rarity,
				Type = c.Type,
				Slot = c.Slot,
				Description = c.Description,
			}
		end),
		Daily = {
			Days = map(Daily.Days, function(d)
				return { Day = d.Day, Chest = d.Chest, Rewards = Rewards.Lines(d.Reward) }
			end),
		},
		Milestones = map(Milestones.List, function(m)
			return { Id = m.Id, Wave = m.Wave, Reachable = m.Reachable, Rewards = Rewards.Lines(m.Reward) }
		end),
		Achievements = map(Achievements.List, function(a)
			return {
				Id = a.Id,
				Name = a.Name,
				Desc = a.Desc,
				Goal = a.Goal,
				Badge = a.Badge,
				Rewards = Rewards.Lines(a.Reward),
			}
		end),
		Mastery = {
			Max = mastery.Max,
			Need = need,
			Milestones = map(mastery.Milestones, function(level)
				return { Lv = level, Rewards = Rewards.Lines(mastery.Rewards[level]) }
			end),
		},
		DieLevel = { Max = dieLevel.Max, Copies = table.clone(dieLevel.Copies) },
		Repeat = {
			PerWave = Rewards.Lines({
				Gold = reward.goldPerWave,
				Xp = reward.xpPerWave,
				Materials = { Fragment = reward.fragmentsPerWave },
			}),
		},
		Roll = {
			Pools = map(RollConfig.Pools, function(pool)
				return {
					Id = pool.Id,
					Name = pool.Name,
					Prices = map(pool.Prices, table.clone),
					Odds = map(pool.Odds, table.clone),
					Dice = map(pool.Dice, table.clone),
					Pity = table.clone(pool.Pity),
					Featured = table.clone(pool.Featured),
				}
			end),
		},
		Shop = {
			Offers = map(ShopConfig.Offers, function(o)
				return {
					Id = o.Id,
					Tab = o.Tab,
					Name = o.Name,
					Currency = o.Currency,
					Price = o.Price,
					Rewards = Rewards.Lines(o.Grant),
					Limit = o.Limit,
					ProductId = o.ProductId,
					Available = o.Currency ~= "Robux" or o.ProductId ~= nil, -- a Robux offer needs its developer product
				}
			end),
		},
	}
end

return Catalog
