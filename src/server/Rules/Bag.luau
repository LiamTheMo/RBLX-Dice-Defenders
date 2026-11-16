-- The BagAction rule (docs/MVP.md "Remotes"): sell, use, lock and unlock Materials and Items; equip and
-- unequip Cosmetics. Pure, no yields. Each action validates fully, then makes ONE change (Sell and Use:
-- one Rewards.Apply bundle), so a rejection leaves the profile untouched. Prices and Use bundles come
-- from Config/Inventory: the client sends only an action, an id and a quantity.
local Inventory = require(script.Parent.Parent.Config.Inventory)
local Economy = require(script.Parent.Economy)
local Rewards = require(script.Parent.Rewards)
local Validate = require(script.Parent.Validate)

local Bag = {}

Bag.MAX_QTY = 1_000_000 -- per request; the client's stepper mirrors it (BagLogic.MAX_QTY)

local ACTIONS = { Sell = true, Use = true, Lock = true, Unlock = true, Equip = true, Unequip = true }

-- RemoteGuard validator for (action, id, qty): a known action; id a string of 0..16 bytes, "" only with
-- Unequip (= unequip all); qty an integer in 1..MAX_QTY, and 1 unless the action is Sell or Use.
function Bag.Shape(action: any, id: any, qty: any): boolean
	if type(action) ~= "string" or ACTIONS[action] == nil then
		return false
	elseif type(id) ~= "string" or #id > 16 or (id == "" and action ~= "Unequip") then
		return false
	end
	return Validate.IsInt(qty, 1, Bag.MAX_QTY) and (qty == 1 or action == "Sell" or action == "Use")
end

-- ("Materials" | "Items", config entry) for a stackable id, else nil.
local function stack(id: string): (string?, any)
	if Inventory.Materials[id] then
		return "Materials", Inventory.Materials[id]
	elseif Inventory.Items[id] then
		return "Items", Inventory.Items[id]
	end
	return nil, nil
end

-- NotOwned, Locked or Insufficient for spending `qty` of a stack, else nil.
local function spendable(profile, kind: string, id: string, qty: number): string?
	local owned = profile[kind][id]
	if owned == nil then
		return "NotOwned"
	elseif profile.Locked[id] then
		return "Locked"
	elseif type(owned) ~= "number" or owned < qty then
		return "Insufficient"
	end
	return nil
end

local function sell(profile, id: string, qty: number): (boolean, string?)
	local kind, entry = stack(id)
	if kind == nil then
		return false, "UnknownItem"
	elseif entry.Sell == nil then
		return false, "NotSellable"
	end
	local refused = spendable(profile, kind, id, qty)
	if refused then
		return false, refused
	end
	local gold = entry.Sell * qty -- <= 1e9 * 1e6, exact in a double
	if gold > Economy.MAX then
		return false, "Overflow"
	end
	return Rewards.Apply(profile, { Gold = gold, [kind] = { [id] = -qty } })
end

-- Use bundles are counters only (Rules/Catalog labels Gold, Gems and Xp), each scaled by qty.
local function use(profile, id: string, qty: number): (boolean, string?)
	local kind, entry = stack(id)
	if kind == nil then
		return false, "UnknownItem"
	elseif kind ~= "Items" or entry.Use == nil then
		return false, "NotUsable"
	end
	local refused = spendable(profile, kind, id, qty)
	if refused then
		return false, refused
	end
	local bundle = { Items = { [id] = -qty } }
	for key, amount in entry.Use do
		if amount * qty > Economy.MAX then
			return false, "Overflow"
		end
		bundle[key] = amount * qty
	end
	return Rewards.Apply(profile, bundle)
end

local function lock(profile, id: string, on: boolean): (boolean, string?)
	local kind = stack(id) -- cosmetics and dice have no lock
	if kind == nil then
		return false, "UnknownItem"
	elseif profile[kind][id] == nil then
		return false, "NotOwned"
	end
	profile.Locked[id] = if on then true else nil
	return true, nil
end

local function equip(profile, id: string): (boolean, string?)
	local cosmetic = Inventory.Cosmetics[id]
	if cosmetic == nil then
		return false, "UnknownItem"
	elseif profile.Cosmetics.Owned[id] ~= true then
		return false, "NotOwned"
	end
	profile.Cosmetics.Equipped[cosmetic.Slot] = id -- replaces whatever that slot held
	return true, nil
end

local function unequip(profile, id: string): (boolean, string?)
	local equipped = profile.Cosmetics.Equipped
	if id == "" then
		table.clear(equipped)
		return true, nil
	end
	local cosmetic = Inventory.Cosmetics[id]
	if cosmetic == nil then
		return false, "UnknownItem"
	end
	if equipped[cosmetic.Slot] == id then
		equipped[cosmetic.Slot] = nil
	end
	return true, nil
end

-- Runs one Shape-valid BagAction. Codes: UnknownItem, NotOwned, Insufficient, Locked, NotSellable,
-- NotUsable, Overflow (or another Rewards.Apply code for a corrupt stored value).
function Bag.Act(profile: any, action: string, id: string, qty: number): (boolean, string?)
	if action == "Sell" then
		return sell(profile, id, qty)
	elseif action == "Use" then
		return use(profile, id, qty)
	elseif action == "Lock" or action == "Unlock" then
		return lock(profile, id, action == "Lock")
	elseif action == "Equip" then
		return equip(profile, id)
	elseif action == "Unequip" then
		return unequip(profile, id)
	end
	return false, "UnknownItem"
end

return Bag
