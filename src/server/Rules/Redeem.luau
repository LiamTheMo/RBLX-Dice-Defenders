-- Redeem codes: Normalize, Claim and a per-player guessing limiter. Pure: callers
-- pass `now` (os.time() seconds). Gold only moves through Economy.
local Balance = require(script.Parent.Parent.Config.Balance)
local Codes = require(script.Parent.Parent.Config.Codes)
local Economy = require(script.Parent.Economy)

local Redeem = {}

local LIMITS = Balance.Redeem

-- The only codes Attempt returns; anything else (Overflow) reads as Invalid, so a
-- reply never reveals more about a code than these do.
local PUBLIC = table.freeze({ Invalid = true, Expired = true, AlreadyRedeemed = true, RateLimited = true })

-- Trimmed and upper-cased, so codes compare case-insensitively; nil for a non-string.
function Redeem.Normalize(text: any): string?
	if type(text) ~= "string" then
		return nil
	end
	local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
	return string.upper(trimmed)
end

-- Redeems `text` once per player. Codes: Invalid (unknown or not started yet),
-- Expired, AlreadyRedeemed, or an Economy code (Overflow); a rejection changes
-- nothing. Gold, then the flag, with no yield between. `codes` overrides the
-- catalog (specs only).
function Redeem.Claim(profile: any, text: any, now: number, codes: any?): (boolean, string?)
	local key = Redeem.Normalize(text)
	local entry = if key then (codes or Codes).ByCode[key] else nil
	if entry == nil or (entry.StartsAt ~= nil and now < entry.StartsAt) then
		return false, "Invalid"
	end
	if entry.ExpiresAt ~= nil and now >= entry.ExpiresAt then
		return false, "Expired"
	end
	if profile.Redeemed[entry.Id] then
		return false, "AlreadyRedeemed"
	end
	local ok, code = Economy.TryChange(profile, "Gold", entry.Gold)
	if not ok then
		return false, code
	end
	profile.Redeemed[entry.Id] = true
	return true, nil
end

-- Guessing limiter for one player. failures = evaluated rejections (they drive the
-- lock); locked = replies refused while locked. Success never resets either.
function Redeem.NewLimiter()
	return { failures = 0, locked = 0, lockedUntil = -math.huge }
end

-- One attempt through `limiter`. While locked: (false, "RateLimited") without
-- evaluating the code or extending the lock (it reveals nothing, so an early retry is
-- not punished). Otherwise Claim, with the code mapped to PUBLIC. Each failure past
-- freeFailures locks for lockSeconds, doubling per failure, capped at maxLockSeconds.
-- The third value is true exactly once: on the kickFailures-th rejection of either kind.
function Redeem.Attempt(limiter, profile: any, text: any, now: number, codes: any?): (boolean, string?, boolean)
	if now < limiter.lockedUntil then
		limiter.locked += 1
		return false, "RateLimited", limiter.failures + limiter.locked == LIMITS.kickFailures
	end
	local ok, code = Redeem.Claim(profile, text, now, codes)
	if ok then
		return true, nil, false
	end
	limiter.failures += 1
	local over = limiter.failures - LIMITS.freeFailures
	if over > 0 then
		local lock = math.min(LIMITS.maxLockSeconds, LIMITS.lockSeconds * 2 ^ (over - 1))
		limiter.lockedUntil = math.max(limiter.lockedUntil, now + lock)
	end
	return false, if PUBLIC[code] then code else "Invalid", limiter.failures + limiter.locked == LIMITS.kickFailures
end

return Redeem
