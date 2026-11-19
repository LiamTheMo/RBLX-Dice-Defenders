local Players = game:GetService("Players")

local Net = require(script.Parent.Parent.Infrastructure.Net)
local Admin = require(script.Parent.Parent.Rules.Admin)
local MatchService = require(script.Parent.MatchService)
local ProfileService = require(script.Parent.ProfileService)

local AdminService = {}
local busy = false

local function edit(action, userId, kind, id, quantity)
	local player = Players:GetPlayerByUserId(userId)
	if kind == "MP" then
		return MatchService.AdminMP(player, if action == "Give" then quantity else -quantity)
	end
	if not player then
		return ProfileService.EditOffline(userId, function(profile)
			return Admin.Apply(profile, action, kind, id, quantity)
		end)
	end
	local profile = ProfileService.Get(player)
	if not profile then
		return false, "ProfileBusy"
	end
	local ok, code = Admin.Apply(profile, action, kind, id, quantity)
	if not ok then
		return false, code
	end
	local resetting = action == "Reset"
	if resetting then
		MatchService.AdminReset(player)
	end
	ProfileService.MarkChanged(player)
	if resetting then
		ProfileService.BlockForReset(player)
	end
	local saved, saveCode = ProfileService.SaveNow(player)
	if resetting then
		-- Rejoin to discard client-local settings. The release save retries pending writes.
		task.delay(0.75, function()
			if player.Parent == Players then
				player:Kick(
					if saved
						then "Your game profile was reset. Rejoin to start fresh."
						else "Your session closed after an admin profile edit. Please rejoin."
				)
			end
		end)
	end
	if saved then
		return true
	end
	if saveCode == "NotLoaded" or saveCode == "LeaseLost" or saveCode == "StaleRevision" then
		return false, "SaveUncertain"
	end
	return true, "SavePending"
end

local function handle(player, action, userId, kind, id, quantity)
	if not Admin.IsAllowed(player.UserId) then
		return false, "Forbidden"
	end
	if busy then
		return false, "AdminBusy"
	end
	busy = true
	local ran, ok, code = pcall(edit, action, userId, kind, id, quantity)
	busy = false
	if not ran then
		warn("[Admin] Edit error: " .. tostring(ok))
		return false, "SaveUncertain"
	end
	if ok then
		print(("[Admin] %d %s %s %s x%d for %d"):format(player.UserId, action, kind, id, quantity, userId))
	end
	return ok, code
end

local function showButton(player)
	if Admin.IsAllowed(player.UserId) then
		player:SetAttribute("AdminPanelAllowed", true)
	end
end

function AdminService.Init()
	Net.Handle("AdminAction", handle)
end

function AdminService.Start()
	Players.PlayerAdded:Connect(showButton)
	for _, player in Players:GetPlayers() do
		showButton(player)
	end
end

return AdminService
