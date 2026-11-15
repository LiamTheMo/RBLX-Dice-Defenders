-- The client-visible display projection of the server catalogues, sent once per
-- player as the Catalog event. Pure. Arrays only (no sparse keys), each sorted by
-- Id. Never reads the redeem code list.
--   { StarterDeck = { ids }, Dice = {{Id, Name, Rarity, Damage, Rate}},
--     Materials = {{Id, Name, Rarity, Description, Sell?}},
--     Items = {{Id, Name, Rarity, Description, Icon?, Sell?, Use?}},
--     Cosmetics = {{Id, Name, Rarity, Type, Slot, Description}} }
-- Damage is a die's base damage, Rate its attacks per second; Use is display text
-- ("+100 XP").
local Dice = require(script.Parent.Parent.Config.Dice)
local Inventory = require(script.Parent.Parent.Config.Inventory)

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

function Catalog.Build()
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
	}
end

return Catalog
