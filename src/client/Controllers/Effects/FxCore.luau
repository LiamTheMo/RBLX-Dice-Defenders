--!strict
-- Pure (Roblox-free) logic behind FxLib: easing, curve sampling, generic pool, limiter, the one-loop
-- scheduler and the quality-tier rules. Kept separate so tests/luau can run it headless.

local FxCore = {}

export type Easing = (number) -> number
export type Key = { t: number, v: number, ease: Easing? } -- ease shapes the segment that ENDS at this key

FxCore.GLOBAL_CAP = 60 -- live effects across every style; over it callers drop flourishes, never gameplay
FxCore.POOL_WARM = 8

-- Easing -----------------------------------------------------------------------------------------

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

FxCore.Easing = table.freeze({
	linear = function(t: number): number
		return clamp01(t)
	end,
	quadOut = function(t: number): number
		t = clamp01(t)
		return 1 - (1 - t) * (1 - t)
	end,
	quadIn = function(t: number): number
		t = clamp01(t)
		return t * t
	end,
	quadInOut = function(t: number): number
		t = clamp01(t)
		if t < 0.5 then
			return 2 * t * t
		end
		return 1 - 2 * (1 - t) * (1 - t)
	end,
	cubicOut = function(t: number): number
		t = clamp01(t)
		local u = 1 - t
		return 1 - u * u * u
	end,
	backOut = function(t: number): number
		t = clamp01(t)
		local c1, c3 = 1.70158, 2.70158
		local u = t - 1
		return 1 + c3 * u * u * u + c1 * u * u
	end,
})

function FxCore.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Piecewise curve through keys sorted by t (seconds or 0..1). Clamps outside the range.
function FxCore.sample(keys: { Key }, t: number): number
	local n = #keys
	if n == 0 then
		return 0
	end
	local first = keys[1]
	if t <= first.t then
		return first.v
	end
	for i = 2, n do
		local b = keys[i]
		if t <= b.t then
			local a = keys[i - 1]
			local span = b.t - a.t
			local alpha = if span > 0 then (t - a.t) / span else 1
			if b.ease then
				alpha = b.ease(alpha)
			end
			return a.v + (b.v - a.v) * alpha
		end
	end
	return keys[n].v
end

-- Die-size scale: effects are authored for a 5-stud die.
function FxCore.scale(dieSize: number): number
	return dieSize / 5
end

-- Pool -------------------------------------------------------------------------------------------

export type Pool<T> = {
	borrow: () -> T?,
	release: (T) -> boolean,
	warm: (n: number) -> (),
	live: () -> number,
	free: () -> number,
	total: () -> number,
}

-- create may return nil (asset not ready): the borrow then returns nil and nothing is counted.
-- Borrow grows the pool up to `max` items, then returns nil. reset must undo every changed property.
function FxCore.newPool<T>(create: () -> T?, reset: (T) -> (), max: number): Pool<T>
	local freeList: { T } = {}
	local out: { [T]: boolean } = {}
	local total, live = 0, 0

	local function make(): T?
		if total >= max then
			return nil
		end
		local item = create()
		if item ~= nil then
			total += 1
		end
		return item
	end

	local pool = {} :: Pool<T>
	function pool.borrow(): T?
		local n = #freeList
		local item: T? = nil
		if n > 0 then
			item = freeList[n]
			freeList[n] = nil
		else
			item = make()
		end
		if item == nil then
			return nil
		end
		out[item] = true
		live += 1
		return item
	end
	function pool.release(item: T): boolean
		if not out[item] then
			return false -- double release or foreign item
		end
		out[item] = nil
		live -= 1
		reset(item)
		table.insert(freeList, item)
		return true
	end
	function pool.warm(n: number)
		while total < math.min(n, max) do
			local item = make()
			if item == nil then
				return
			end
			reset(item)
			table.insert(freeList, item)
		end
	end
	function pool.live(): number
		return live
	end
	function pool.free(): number
		return #freeList
	end
	function pool.total(): number
		return total
	end
	return pool
end

-- Limiter (per-style MAX_SHOTS) --------------------------------------------------------------------

export type Limiter = { max: number, count: number }

function FxCore.newLimiter(max: number): Limiter
	return { max = max, count = 0 }
end

-- Scheduler (one shared loop) -----------------------------------------------------------------------

export type Handle = { cancel: () -> (), isDone: () -> boolean }
type Entry = {
	update: (number) -> boolean,
	onEnd: (() -> ())?,
	limiter: Limiter?,
	finished: boolean,
}

export type Scheduler = {
	run: (update: (number) -> boolean, onEnd: (() -> ())?, limiter: Limiter?) -> Handle?,
	step: (dt: number) -> (),
	live: () -> number,
	clear: () -> (),
	isConnected: () -> boolean,
}

-- connect(step) must hook the step to a per-frame signal and return a function that disconnects it.
function FxCore.newScheduler(connect: ((number) -> ()) -> () -> (), cap: number): Scheduler
	local entries: { Entry } = {}
	local n = 0
	local live = 0
	local disconnect: (() -> ())? = nil
	local stepping = false
	local sched = {} :: Scheduler

	local function finish(e: Entry)
		if e.finished then
			return
		end
		e.finished = true
		live -= 1
		if e.limiter then
			e.limiter.count -= 1
		end
		local onEnd = e.onEnd
		if onEnd then
			local ok, err = pcall(onEnd)
			if not ok then
				warn("FxCore onEnd failed: " .. tostring(err))
			end
		end
	end

	local function stop()
		if disconnect then
			disconnect()
			disconnect = nil
		end
	end

	function sched.step(dt: number)
		stepping = true
		for i = n, 1, -1 do
			local e = entries[i]
			if e ~= nil then
				if not e.finished then
					local ok, done = pcall(e.update, dt)
					if not ok then
						warn("FxCore update failed: " .. tostring(done))
						done = true
					end
					if done then
						finish(e)
					end
				end
				if e.finished then -- swap-remove; the entry moved into i was already visited (or is new)
					entries[i] = entries[n]
					entries[n] = nil
					n -= 1
				end
			end
		end
		stepping = false
		if n == 0 then
			stop()
		end
	end

	function sched.run(update, onEnd, limiter): Handle?
		if live >= cap then
			return nil
		end
		if limiter then
			if limiter.count >= limiter.max then
				return nil
			end
			limiter.count += 1
		end
		local e: Entry = { update = update, onEnd = onEnd, limiter = limiter, finished = false }
		n += 1
		entries[n] = e
		live += 1
		if disconnect == nil then
			disconnect = connect(sched.step)
		end
		return {
			cancel = function()
				finish(e)
			end,
			isDone = function()
				return e.finished
			end,
		}
	end

	function sched.live(): number
		return live
	end

	function sched.clear()
		for i = 1, n do
			local e = entries[i]
			if e then
				finish(e)
			end
		end
		if not stepping then -- inside a step the loop sweeps the finished entries itself
			table.clear(entries)
			n = 0
			stop()
		end
	end

	function sched.isConnected(): boolean
		return disconnect ~= nil
	end

	return sched
end

-- Quality tier -------------------------------------------------------------------------------------

export type Tier = "Low" | "High"
local LOW_LAYERS = { projectile = true, flash = true }

-- Phone or reduced motion -> Low (projectile + one flash only).
function FxCore.tier(reducedMotion: boolean, isPhone: boolean): Tier
	if reducedMotion or isPhone then
		return "Low"
	end
	return "High"
end

-- layer: "projectile" | "flash" | "trail" | "ring" | "shard" | "support" | "status"
function FxCore.layerAllowed(tier: Tier, layer: string): boolean
	if tier == "High" then
		return true
	end
	return LOW_LAYERS[layer] == true
end

-- Reduced flash: opacity <= 0.6 (callers also skip sparks and shake).
function FxCore.flashOpacity(reducedMotion: boolean, opacity: number): number
	if reducedMotion then
		return math.min(opacity, 0.6)
	end
	return opacity
end

return FxCore
