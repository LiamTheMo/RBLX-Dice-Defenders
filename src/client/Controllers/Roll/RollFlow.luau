-- shortcut: placeholder roll animation, replace with real VFX later
-- Roll press flow (pure state machine, client display only). The clock is passed in; nothing here reads the outcome, picks
-- anything at random or draws: the server's RollResult is only buffered and handed back for display once the spin is over.
-- States: Idle -> Sending (press) -> Rolling (reply ok) -> Revealing (result buffered and MIN_SPIN over) -> Idle.
-- Every method returns nil or an action { send, show = "rolling"|"reveal"|"idle", toast, result, settle, late }.
-- Timeout: Sending / Rolling at t0 + TIMEOUT -> toast, Idle (the NetClient request stays open: `open` blocks a new press).
-- Stale: a roll abandoned (timeout / close) before its result came still has one RollResult on the way; the next Result
-- is that one (late, toast only, never revealed as the next press) until it arrives, its reply fails, or STALE passes.

local RollFlow = {}
RollFlow.__index = RollFlow

RollFlow.MIN_SPIN = 0.6
RollFlow.REVEAL = 0.3
RollFlow.TIMEOUT = 10
RollFlow.STALE = 5 -- how long after the reply a timed-out / closed roll's own RollResult is still expected
RollFlow.STILL_WAITING = "Still waiting for the last roll"
RollFlow.TIMED_OUT = "Connection problem"
RollFlow.GENERIC = "Something went wrong"
RollFlow.REPLIES = {
	Restricted = "Not available in your region",
	Insufficient = "Not enough Gems",
	UnknownPool = "Roll unavailable",
	UnknownPrice = "Roll unavailable",
	Overflow = "You can't hold that much",
	NotLoaded = "Still loading",
	NotOwner = "This server is in use",
	Throttled = "Slow down",
	RateLimited = "Slow down",
	Network = "Connection problem",
	Error = "Something went wrong",
	BadArgs = "Something went wrong",
	BadSeq = "Something went wrong",
}

function RollFlow.new()
	return setmetatable({ state = "Idle", gen = 0, open = false, spin = 0, reveal = 0 }, RollFlow)
end

function RollFlow:IsIdle(): boolean
	return self.state == "Idle"
end

-- nil = a press may go ahead; else the action to apply instead ({} = ignore silently)
function RollFlow:Blocked()
	if self.state ~= "Idle" then
		return {}
	elseif self.open then
		return { toast = RollFlow.STILL_WAITING }
	end
	return nil
end

function RollFlow:Press(now: number, reducedMotion: boolean?)
	local blocked = self:Blocked()
	if blocked then
		return blocked
	end
	self.gen += 1
	self.state, self.t0, self.buffered, self.open = "Sending", now, nil, true
	self.spin = if reducedMotion then 0 else RollFlow.MIN_SPIN
	self.reveal = if reducedMotion then 0 else RollFlow.REVEAL
	return { send = true, gen = self.gen, show = "rolling" }
end

-- Called when a Sending / Rolling roll is abandoned: its result may still be on the way.
local function abandon(self, now: number?)
	if (self.state == "Sending" or self.state == "Rolling") and not self.buffered then
		self.stale = true
		self.staleUntil = if self.open or now == nil then nil else now + RollFlow.STALE -- else the reply sets it
	end
end

local function idle(self, toast)
	self.state, self.buffered = "Idle", nil
	return { show = "idle", toast = toast }
end

-- The invoke returned (ok, code). Always closes the request, whatever generation it belongs to.
function RollFlow:Reply(gen: number, ok: boolean, code: any, now: number)
	self.open = false
	if gen ~= self.gen or self.state ~= "Sending" then
		if self.stale and self.staleUntil == nil then
			self.staleUntil = if ok then now + RollFlow.STALE else 0 -- a failed request has no result coming
		end
		return nil -- closed or timed out meanwhile: the timeout already told the player
	end
	if not ok then
		return idle(self, RollFlow.REPLIES[code] or RollFlow.GENERIC)
	end
	self.state = "Rolling"
	return self:Tick(now)
end

-- A RollResult event. Buffered while a roll is in flight (it may arrive before the reply); otherwise late.
function RollFlow:Result(r: any, now: number)
	if self.stale then
		local mine = self.staleUntil == nil or now < self.staleUntil
		self.stale, self.staleUntil = false, nil
		if mine then
			return { late = r }
		end
	end
	if self.state == "Sending" or self.state == "Rolling" then
		self.buffered = r
		return self:Tick(now)
	end
	return { late = r }
end

function RollFlow:Tick(now: number)
	local s = self.state
	if (s == "Sending" or s == "Rolling") and now >= self.t0 + RollFlow.TIMEOUT then
		abandon(self, now)
		self.gen += 1 -- whatever arrives later is stale
		return idle(self, RollFlow.TIMED_OUT)
	elseif s == "Rolling" and self.buffered and now >= self.t0 + self.spin then
		self.state, self.t1 = "Revealing", now
		return { show = "reveal", result = self.buffered }
	elseif s == "Revealing" and now >= self.t1 + self.reveal then
		local r = self.buffered
		self.state, self.buffered = "Idle", nil
		return { show = "idle", settle = r }
	end
	return nil
end

-- The next clock time Tick can change something, or nil.
function RollFlow:Next(): number?
	local s = self.state
	if s == "Sending" or s == "Rolling" then
		if s == "Rolling" and self.buffered then
			return math.min(self.t0 + self.spin, self.t0 + RollFlow.TIMEOUT)
		end
		return self.t0 + RollFlow.TIMEOUT
	elseif s == "Revealing" then
		return self.t1 + self.reveal
	end
	return nil
end

-- The menu closed: back to Idle, any result still to come is stale. `open` stays until the invoke returns.
-- A result already buffered but not yet revealed (and so not yet toasted) comes back as { late } so it is still told.
function RollFlow:Close(now: number?)
	local unrevealed = if self.state ~= "Revealing" then self.buffered else nil
	abandon(self, now)
	self.gen += 1
	self.state, self.buffered = "Idle", nil
	return if unrevealed then { late = unrevealed } else nil
end

return RollFlow
