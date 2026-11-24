local Dice = require(script.Parent.Parent.Config.Dice)
local Inventory = require(script.Parent.Parent.Config.Inventory)
local Economy = require(script.Parent.Economy)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Rewards = require(script.Parent.Rewards)
local Validate = require(script.Parent.Validate)

local Admin = {}
local ALLOWED_USERS = table.freeze({ [855002824] = true })
local CATALOGS =
	{ Dice = Dice.Types, Materials = Inventory.Materials, Items = Inventory.Items, Cosmetics = Inventory.Cosmetics }
local COUNTERS = { Gold = true, Gems = true, Xp = true, MP = true }

function Admin.IsAllowed(userId: number): boolean
	return ALLOWED_USERS[userId] == true
end

function Admin.Shape(action, userId, kind, id, quantity)
	if
		not Validate.IsInt(userId, 1, 2 ^ 53 - 1)
		or type(kind) ~= "string"
		or #kind > 9
		or type(id) ~= "string"
		or #id > 32
	then
		return false
	end
	if action == "Reset" then
		return kind == "" and id == "RESET" and quantity == 0
	end
	if action == "Revoke" then
		return kind == "Dice" and #id > 0 and quantity == 1
	end
	if action ~= "Give" and action ~= "Take" then
		return false
	end
	if not Validate.IsInt(quantity, 1, Economy.MAX) then
		return false
	end
	if COUNTERS[kind] then
		return id == ""
	end
	return CATALOGS[kind] ~= nil and #id > 0 and (kind ~= "Cosmetics" or quantity == 1)
end

function Admin.Apply(profile, action, kind, id, quantity)
	if action == "Reset" then
		local fresh = ProfileSchema.Migrate(nil)
		-- Store metadata and paid receipt IDs survive a gameplay reset.
		fresh.profileRevision, fresh.sessionLease = profile.profileRevision, profile.sessionLease
		fresh.adminEditId = profile.adminEditId
		fresh.Receipts = profile.Receipts
		table.clear(profile)
		for key, value in fresh do
			profile[key] = value
		end
		return true
	end
	if COUNTERS[kind] then
		local ok, value = Economy.Sum(profile[kind], if action == "Give" then quantity else -quantity)
		if not ok then
			return false, value
		end
		profile[kind] = value
		return true
	end
	local entry = CATALOGS[kind][id]
	if not entry then
		return false, "UnknownItem"
	end
	if action == "Give" then
		return Rewards.Apply(profile, { [kind] = { [id] = if kind == "Cosmetics" then true else quantity } })
	end
	if kind == "Cosmetics" then
		if not profile.Cosmetics.Owned[id] then
			return false, "NotOwned"
		end
		profile.Cosmetics.Owned[id] = nil
		if profile.Cosmetics.Equipped[entry.Slot] == id then
			profile.Cosmetics.Equipped[entry.Slot] = nil
		end
		return true
	end
	if kind == "Dice" then
		local die = profile.Dice[id]
		if not die then
			return false, "NotOwned"
		elseif action ~= "Revoke" and quantity <= die.Copies then
			die.Copies -= quantity
		elseif action ~= "Revoke" and quantity ~= die.Copies + 1 then
			return false, "Insufficient"
		elseif table.find(Dice.Deck, id) then
			return false, "StarterDie"
		else
			profile.Dice[id] = nil
			local slot = table.find(profile.Deck, id)
			if slot then
				for _, starter in Dice.Deck do
					if not table.find(profile.Deck, starter) then
						profile.Deck[slot] = starter
						break
					end
				end
			end
		end
		return true
	end
	local ok, code = Rewards.Apply(profile, { [kind] = { [id] = -quantity } })
	if ok and profile[kind][id] == nil then
		profile.Locked[id] = nil
	end
	return ok, code
end

return Admin
