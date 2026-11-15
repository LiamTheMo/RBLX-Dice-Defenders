--!strict
-- Codes popup logic: pure, no Instances. Shape rules and messages only (UX); the client
-- holds no codes or rewards, and the server re-checks every request.

local CodesLogic = {}

CodesLogic.MAX_LEN = 32
CodesLogic.PRESS_COOLDOWN = 1 -- seconds the button rests after any answered press
CodesLogic.MESSAGE_SECONDS = 3 -- how long a result message replaces the caption (at least)
-- The server's guessing lock (Config/Balance.Redeem, server-only; codes.spec keeps them equal): mirrored so an honest
-- player waits it out instead of spending the server's rejection allowance on refused tries.
CodesLogic.FREE_FAILURES, CodesLogic.LOCK_SECONDS, CodesLogic.MAX_LOCK_SECONDS = 5, 15, 600

export type Mode = "Disabled" | "Ready" | "Waiting" | "Cooldown"
export type Tone = "Success" | "Error" | "Info"
-- seconds = how long the message shows: MESSAGE_SECONDS, or the whole cooldown when that is longer.
export type Result = { text: string, tone: Tone, cooldown: number, clear: boolean, seconds: number }

local PRESS = CodesLogic.PRESS_COOLDOWN
local function result(text: string, tone: Tone, cooldown: number, clear: boolean): Result
	local seconds = math.max(CodesLogic.MESSAGE_SECONDS, cooldown)
	return table.freeze({ text = text, tone = tone, cooldown = cooldown, clear = clear, seconds = seconds })
end

local FAILURES: { [string]: Result } = {
	Invalid = result("That code isn't valid.", "Error", PRESS, false),
	Expired = result("That code has expired.", "Error", PRESS, false),
	AlreadyRedeemed = result("You already used that code.", "Info", PRESS, false),
}
local RATE_TEXT = "Too many tries! Wait a moment."
local SUCCESS = result("Code redeemed!", "Success", PRESS, true)
local FALLBACK = result("Something went wrong. Try again.", "Error", PRESS, false)

-- Keeps only the server's accepted bytes (ASCII A-Z a-z 0-9 - _), then caps at MAX_LEN.
-- Every byte of a multi-byte UTF-8 character is >= 0x80, so such characters drop whole.
-- `changed` is true when a disallowed character was removed (truncation alone does not set it).
local function strip(text: string): (string, boolean)
	local kept, removed = string.gsub(text, "[^A-Za-z0-9_%-]", "")
	return kept, removed > 0
end

function CodesLogic.sanitize(text: string): (string, boolean)
	local kept, changed = strip(text)
	return string.sub(kept, 1, CodesLogic.MAX_LEN), changed
end

-- Cursor for the sanitised text: just after the kept characters that stood before it. Below 1 (not editing) is unchanged.
function CodesLogic.cursorAfter(text: string, cursor: number): number
	if cursor < 1 then
		return cursor
	end
	return #CodesLogic.sanitize(string.sub(text, 1, cursor - 1)) + 1
end

-- One edit of the field. prev = its last clean text; text / cursor = after the edit (cursor < 1 when not editing).
-- Typing or pasting at the cursor keeps only as much of the insert as fits, so a full field stays unchanged; any
-- other edit (a replace, a script write) is sanitised. Returns the text to keep, its cursor and sanitize's `changed`.
function CodesLogic.edit(prev: string, text: string, cursor: number): (string, number, boolean)
	local k = #text - #prev -- bytes inserted
	local at = cursor - k -- where the insert starts
	if k > 0 and at >= 1 and string.sub(text, 1, at - 1) .. string.sub(text, cursor) == prev then
		local insert, changed = strip(string.sub(text, at, cursor - 1))
		insert = string.sub(insert, 1, math.max(0, CodesLogic.MAX_LEN - #prev))
		return string.sub(prev, 1, at - 1) .. insert .. string.sub(prev, at), at + #insert, changed
	end
	local cleaned, changed = CodesLogic.sanitize(text)
	return cleaned, CodesLogic.cursorAfter(text, cursor), changed
end

-- Real px to raise the popup so the field's bottom clears the keyboard's top by 8, never lifting the field's top above y 4.
-- Field top / bottom are where they sit unlifted; all three share one screen space. Whole px (UDim offsets are integers).
function CodesLogic.lift(fieldTop: number, fieldBottom: number, keyboardTop: number): number
	return math.max(0, math.min(math.ceil(fieldBottom + 8 - keyboardTop), math.floor(fieldTop - 4)))
end

-- Precedence: Waiting > Cooldown > Disabled > Ready. Cooldown ends when now reaches cooldownUntil.
function CodesLogic.buttonMode(text: string, waiting: boolean, now: number, cooldownUntil: number): Mode
	if waiting then
		return "Waiting"
	elseif now < cooldownUntil then
		return "Cooldown"
	elseif CodesLogic.sanitize(text) == "" then
		return "Disabled"
	end
	return "Ready"
end

-- Seconds of the streak-th RateLimited reply in a row (1, 2, ...): LOCK_SECONDS doubling, capped at MAX_LOCK_SECONDS.
function CodesLogic.lockSeconds(streak: number): number
	return math.min(CodesLogic.MAX_LOCK_SECONDS, CodesLogic.LOCK_SECONDS * 2 ^ (math.max(1, streak) - 1))
end

-- The RateLimited streak after a reply: +1 on RateLimited, unchanged on Throttled (nothing was sent), else 0.
function CodesLogic.nextStreak(streak: number, ok: boolean, code: string?): number
	if not ok and code == "RateLimited" then
		return streak + 1
	elseif not ok and code == "Throttled" then
		return streak
	end
	return 0
end

-- A failure reply the server's limiter counted: any rejection that reached it (not Throttled / Network, which never
-- left the client, nor RateLimited, a refused try). Generic server errors count too: locking early is the safe side.
function CodesLogic.isFailure(ok: boolean, code: string?): boolean
	return not ok and code ~= "Throttled" and code ~= "Network" and code ~= "RateLimited"
end

-- The failure count after a reply (per session, like the server's; a success never resets it).
function CodesLogic.nextFailures(failures: number, ok: boolean, code: string?): number
	return if CodesLogic.isFailure(ok, code) then failures + 1 else failures
end

-- Seconds the server locks after its n-th failure: 0 up to FREE_FAILURES, then LOCK_SECONDS doubling, capped.
function CodesLogic.failureLock(n: number): number
	local over = n - CodesLogic.FREE_FAILURES
	return if over > 0 then math.min(CodesLogic.MAX_LOCK_SECONDS, CodesLogic.LOCK_SECONDS * 2 ^ (over - 1)) else 0
end

-- What to show for NetClient.Request's (ok, code). streak = the RateLimited streak and failures = the failure count, both
-- including this reply (see nextStreak / nextFailures). A failure that locks shows the wait message for the whole lock.
-- nil for "Throttled": a double-tap, show nothing. Results are frozen tables.
function CodesLogic.result(ok: boolean, code: string?, streak: number?, failures: number?): Result?
	if ok then
		return SUCCESS
	elseif code == "Throttled" then
		return nil
	elseif code == "RateLimited" then -- the mirror fell out of sync: back off on the streak
		return result(RATE_TEXT, "Error", CodesLogic.lockSeconds(streak or 1), false)
	end
	local lock = if CodesLogic.isFailure(ok, code) then CodesLogic.failureLock(failures or 0) else 0
	if lock > 0 then
		return result(RATE_TEXT, "Error", lock, false)
	end
	return FAILURES[code :: string] or FALLBACK
end

return CodesLogic
