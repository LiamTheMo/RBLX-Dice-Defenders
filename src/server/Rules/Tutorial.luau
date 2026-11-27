local Dice = require(script.Parent.Parent.Config.Dice)
local Economy = require(script.Parent.Economy)
local Rewards = require(script.Parent.Rewards)
local Milestones = require(script.Parent.Parent.Config.Milestones)

local Tutorial = {}

Tutorial.RollCost = 100
Tutorial.TargetWave = 10
-- The gift is the wave-10 play milestone, claimed in the Play menu like any other.
Tutorial.GiftMilestone = "P10"
local gift = Milestones.ById[Tutorial.GiftMilestone].Reward
Tutorial.GiftGems = gift.Gems
Tutorial.GiftShards = gift.Materials.DieShard

local STARTERS = Dice.Deck
local STAGES = { Play = true, Choose = true, Gift = true, Done = true }

assert(#STARTERS == 5, "Tutorial needs five starters")

function Tutorial.Restore(stored, owned)
	if type(stored) ~= "table" then
		return nil
	end
	if STAGES[stored.Stage] then
		return { Stage = stored.Stage }
	end
	if stored.Stage ~= "Roll" then
		return nil
	end
	local rolls, seen = {}, {}
	if type(stored.Rolls) == "table" then
		for _, id in stored.Rolls do
			if #rolls >= #STARTERS - 1 then
				break
			end
			if type(id) == "string" and table.find(STARTERS, id) and owned[id] and not seen[id] then
				seen[id] = true
				table.insert(rolls, id)
			end
		end
	end
	return { Stage = "Roll", Rolls = rolls }
end

function Tutorial.Shape(action: any, dieId: any): boolean
	if type(dieId) ~= "string" then
		return false
	end
	if action == "Convert" then
		return #dieId >= 1 and #dieId <= 8
	end
	return dieId == "" and (action == "Roll" or action == "End" or action == "Continue")
end

function Tutorial.View(profile)
	local tutorial = profile.Tutorial
	if not tutorial or tutorial.Stage == "Done" then
		return nil
	end
	local rolls = if tutorial.Rolls then #tutorial.Rolls else #STARTERS
	return {
		Stage = tutorial.Stage,
		Rolls = rolls,
		RollCount = #STARTERS,
		RollCost = Tutorial.RollCost,
		Gems = (#STARTERS - rolls) * Tutorial.RollCost,
		TargetWave = Tutorial.TargetWave,
		GiftGems = Tutorial.GiftGems,
		GiftShards = Tutorial.GiftShards,
	}
end

function Tutorial.CanStart(profile): boolean
	return not profile.Tutorial or profile.Tutorial.Stage ~= "Roll"
end

function Tutorial.CanFinish(profile): boolean
	return profile.Tutorial ~= nil and profile.Tutorial.Stage == "Choose"
end

function Tutorial.ReachWave(profile, wavesCompleted: number): boolean
	if not profile.Tutorial or profile.Tutorial.Stage ~= "Play" or wavesCompleted < Tutorial.TargetWave then
		return false
	end
	profile.Tutorial.Stage = "Choose"
	return true
end

function Tutorial.Finish(profile): boolean
	if not Tutorial.CanFinish(profile) then
		return false
	end
	profile.Tutorial.Stage = if profile.Milestones[Tutorial.GiftMilestone] then "Done" else "Gift"
	return true
end

-- Each draw spends one tutorial-only Gem credit; regular Gems and paid roll odds stay separate.
function Tutorial.Roll(profile, rng)
	local tutorial = profile.Tutorial
	if not tutorial or tutorial.Stage ~= "Roll" then
		return false, "WrongTutorialStep"
	end
	local available = {}
	for _, id in STARTERS do
		if not table.find(tutorial.Rolls, id) then
			table.insert(available, id)
		end
	end
	local id = available[rng:NextInteger(1, #available)]
	local isNew = profile.Dice[id] == nil
	local ok, code = Rewards.Apply(profile, { Dice = { [id] = 1 } })
	if not ok then
		return false, code
	end
	profile.Stats.Rolls = math.min(Economy.MAX, profile.Stats.Rolls + 1)
	table.insert(tutorial.Rolls, id)
	if #tutorial.Rolls == #STARTERS then
		profile.Deck = table.clone(tutorial.Rolls)
		profile.Tutorial = { Stage = "Play" }
	end
	return true, nil, { Pool = "Tutorial", Results = { { Id = id, Rarity = Dice.Types[id].rarity, New = isNew } } }
end

-- Called after any successful claim: taking the wave-10 milestone ends the tutorial.
function Tutorial.Claimed(profile, id: string): boolean
	if id ~= Tutorial.GiftMilestone or not profile.Tutorial or profile.Tutorial.Stage ~= "Gift" then
		return false
	end
	profile.Tutorial.Stage = "Done"
	return true
end

function Tutorial.Convert(profile, id: string): (boolean, string?)
	if not profile.Dice[id] or not Dice.Types[id] then
		return false, "NotOwned"
	elseif profile.Locked.DieShard then
		return false, "Locked"
	end
	return Rewards.Apply(profile, { Dice = { [id] = 1 }, Materials = { DieShard = -1 } })
end

return table.freeze(Tutorial)
