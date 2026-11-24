local Net = require(script.Parent.Parent.Infrastructure.Net)
local Tutorial = require(script.Parent.Parent.Rules.Tutorial)
local MatchService = require(script.Parent.MatchService)
local ProfileService = require(script.Parent.ProfileService)

local TutorialService = {}
local rng = Random.new()

local function handle(player: Player, action: string, dieId: string): (boolean, string?)
	local profile = ProfileService.Get(player)
	if not profile then
		return false, "NotLoaded"
	end
	local ok, code, result
	if action == "Roll" then
		ok, code, result = Tutorial.Roll(profile, rng)
	elseif action == "End" then
		if not Tutorial.CanFinish(profile) then
			return false, "WrongTutorialStep"
		end
		ok, code = MatchService.FinishTutorial(player)
		if ok then
			Tutorial.Finish(profile)
		end
	elseif action == "Continue" then
		ok, code = Tutorial.Finish(profile), "WrongTutorialStep"
		if ok then
			code = nil
		end
	elseif action == "Claim" then
		ok, code = Tutorial.Claim(profile, rng)
	else
		ok, code = Tutorial.Convert(profile, dieId)
	end
	if ok then
		ProfileService.MarkChanged(player)
		if result then
			Net.Fire("RollResult", player, result)
		end
		task.spawn(ProfileService.SaveNow, player)
	end
	return ok, code
end

function TutorialService.Init()
	Net.Handle("TutorialAction", handle)
end

return TutorialService
