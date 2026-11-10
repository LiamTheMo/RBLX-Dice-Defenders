-- Pure request guard behind Net (no Instances, so specs run it headless). Order:
-- token bucket -> exact argument check -> ready check -> seq check -> handler.
-- Every refusal is (false, "Code"); the client is never trusted to be well-formed.
--
-- Hard violations (RateLimited, BadArgs, BadSeq) are logged (throttled) and counted;
-- reaching the threshold calls `kick` exactly once. Soft rejections (anything the
-- ready check or a handler returns) are never counted.
local Balance = require(script.Parent.Parent.Config.Balance)
local Validate = require(script.Parent.Parent.Rules.Validate)

local RemoteGuard = {}
RemoteGuard.__index = RemoteGuard

RemoteGuard.MAX_SEQ = 2 ^ 31 - 1

-- argc counts every argument including the leading seq; check(...) gets the
-- arguments after seq and must return exactly true.
RemoteGuard.Specs = table.freeze({
	Start = table.freeze({ argc = 1 }),
	Summon = table.freeze({ argc = 1 }),
	Merge = table.freeze({
		argc = 3,
		check = function(from, to)
			return Validate.IsInt(from, 1, Balance.BoardCells) and Validate.IsInt(to, 1, Balance.BoardCells)
		end,
	}),
})

export type Options = {
	clock: () -> number,
	-- (owner) -> true, or (false, softCode). Throwing counts as "NotLoaded".
	ready: ((any) -> (boolean, string?))?,
	-- (owner, reason) -> (); called once per player at the threshold.
	kick: ((any, string) -> ())?,
	warn: ((string) -> ())?,
	kickThreshold: number?,
	logInterval: number?,
}

function RemoteGuard.new(options: Options)
	return setmetatable({
		_clock = options.clock,
		_ready = options.ready,
		_kick = options.kick,
		_warn = options.warn or warn,
		_threshold = options.kickThreshold or Balance.KickThreshold,
		_logInterval = options.logInterval or Balance.LogInterval,
		_players = {}, -- owner -> { buckets, lastSeq, violations, kicked, lastLog }
	}, RemoteGuard)
end

function RemoteGuard:_state(owner: any)
	local state = self._players[owner]
	if state == nil then
		state = { buckets = {}, lastSeq = 0, violations = 0, kicked = false, lastLog = -math.huge }
		self._players[owner] = state
	end
	return state
end

-- Drops all of a leaving player's state (PlayerRemoving).
function RemoteGuard:Forget(owner: any)
	self._players[owner] = nil
end

function RemoteGuard:Violations(owner: any): number
	local state = self._players[owner]
	return state and state.violations or 0
end

local function take(self, state, name: string, rate: number, burst: number): boolean
	local now = self._clock()
	local bucket = state.buckets[name]
	if bucket == nil then
		bucket = { tokens = burst, at = now }
		state.buckets[name] = bucket
	end
	bucket.tokens = math.min(burst, bucket.tokens + math.max(0, now - bucket.at) * rate)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

local function violation(self, owner: any, state, name: string, code: string)
	state.violations += 1
	local now = self._clock()
	if now - state.lastLog >= self._logInterval then
		state.lastLog = now
		pcall(self._warn, ("[Net] %s from %s: %s (%d)"):format(name, tostring(owner), code, state.violations))
	end
	if state.violations >= self._threshold and not state.kicked then
		state.kicked = true
		if self._kick then
			local ok, err = pcall(self._kick, owner, code)
			if not ok then
				pcall(self._warn, "[Net] kick failed: " .. tostring(err))
			end
		end
	end
	return false, code
end

-- Runs one request. `handler(owner, ...)` gets the arguments after seq and returns
-- (ok, code?). Returns (ok, code?). Never throws.
function RemoteGuard:Call(owner: any, name: string, handler: (any, ...any) -> (boolean, string?), ...)
	local spec = RemoteGuard.Specs[name]
	local limits = Balance.Remotes[name]
	if spec == nil or limits == nil then
		return false, "BadArgs"
	end
	local state = self:_state(owner)
	if not take(self, state, name, limits.rate, limits.burst) then
		return violation(self, owner, state, name, "RateLimited")
	end

	if select("#", ...) ~= spec.argc then
		return violation(self, owner, state, name, "BadArgs")
	end
	local seq = ...
	if spec.check then
		local checked, valid = pcall(spec.check, select(2, ...))
		if not checked or valid ~= true then
			return violation(self, owner, state, name, "BadArgs")
		end
	end

	if self._ready then
		local readyOk, ready, code = pcall(self._ready, owner)
		if not readyOk or ready ~= true then
			return false, if readyOk and type(code) == "string" then code else "NotLoaded"
		end
	end

	if not Validate.IsInt(seq, 1, RemoteGuard.MAX_SEQ) or seq <= state.lastSeq then
		return violation(self, owner, state, name, "BadSeq")
	end
	state.lastSeq = seq -- consumed even if the rules reject

	local ran, ok, code = pcall(handler, owner, select(2, ...))
	if not ran then
		pcall(self._warn, ("[Net] %s handler failed: %s"):format(name, tostring(ok)))
		return false, "Error"
	end
	return ok == true, if type(code) == "string" then code else nil
end

return RemoteGuard
