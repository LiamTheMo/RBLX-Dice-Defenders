-- RedeemCode remote: thin glue between the guard, the profile and Rules/Redeem.
-- Replies are ok, or one of Invalid, Expired, AlreadyRedeemed, RateLimited (plus the
-- guard's own codes). Never trusts anything from the client but the typed text.

local Players = game:GetService("Players")

local Balance = require(script.Parent.Parent.Config.Balance)
local Net = require(script.Parent.Parent.Infrastructure.Net)
local Redeem = require(script.Parent.Parent.Rules.Redeem)
local ProfileService = require(script.Parent.ProfileService)

local RedeemService = {}

-- shortcut: the guessing limiter lives only for this server session; rejoining resets it (5 free guesses, then one per
-- 15/30/60.. s lock). Fine while every code is public; store failures per UserId before shipping private codes.
local sessions = {} -- player -> { limiter, lastLog }

local function handleRedeem(player: Player, text: string): (boolean, string?)
	local profile = ProfileService.Get(player)
	if profile == nil or player.Parent == nil then
		return false, "NotLoaded"
	end
	local session = sessions[player]
	if session == nil then
		session = { limiter = Redeem.NewLimiter(), lastLog = -math.huge }
		sessions[player] = session
	end
	local now = os.time()
	local ok, code, abuse = Redeem.Attempt(session.limiter, profile, text, now)
	if ok then
		ProfileService.MarkChanged(player)
		return true, nil
	end
	local failures = session.limiter.failures
	if abuse then
		warn(("[Redeem] kicking %s: %d failed codes"):format(tostring(player), failures))
		player:Kick("Disconnected.")
	elseif failures > Balance.Redeem.freeFailures and now - session.lastLog >= Balance.LogInterval then
		session.lastLog = now
		warn(("[Redeem] %s locked: %d failed codes"):format(tostring(player), failures))
	end
	return false, code
end

function RedeemService.Init()
	Net.Handle("RedeemCode", handleRedeem)
end

function RedeemService.Start()
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

return RedeemService
