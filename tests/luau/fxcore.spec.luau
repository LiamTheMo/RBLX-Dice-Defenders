-- FxCore: pool borrow/release/cap, scheduler (cap, limiter, swap-remove, lazy connect), curves, tiers.

local FxCore = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Effects.FxCore)

local function counterPool(max)
	local made, resets = 0, 0
	local pool = FxCore.newPool(function()
		made += 1
		return { id = made }
	end, function()
		resets += 1
	end, max)
	return pool, function()
		return made, resets
	end
end

local function fakeLoop()
	local loop = { step = nil, connects = 0, disconnects = 0 }
	loop.connect = function(step)
		loop.step = step
		loop.connects += 1
		return function()
			loop.disconnects += 1
			loop.step = nil
		end
	end
	return loop
end

test("pool borrows, reuses released items and resets on release", function()
	local pool, stats = counterPool(3)
	local a = pool.borrow()
	local b = pool.borrow()
	expect(a ~= nil and b ~= nil and a ~= b, "two distinct items")
	expectEq(pool.live(), 2, "live")
	expect(pool.release(a), "release ok")
	expectEq(pool.live(), 1, "live after release")
	local _, resets = stats()
	expectEq(resets, 1, "reset ran once")
	expect(pool.borrow() == a, "released item is reused, not recreated")
	expectEq(pool.total(), 2, "no new item created")
end)

test("pool caps at max and ignores double or foreign release", function()
	local pool = counterPool(2)
	local a, b = pool.borrow(), pool.borrow()
	expect(pool.borrow() == nil, "third borrow at cap is nil")
	expect(pool.release(a), "first release")
	expect(not pool.release(a), "double release rejected")
	expect(not pool.release({}), "foreign item rejected")
	expectEq(pool.live(), 1, "live count intact")
	expect(b ~= nil, "b kept")
end)

test("pool warm pre-creates up to the cap and a nil create is not counted", function()
	local pool, stats = counterPool(5)
	pool.warm(8)
	local made = stats()
	expectEq(made, 5, "warm stops at max")
	expectEq(pool.free(), 5, "all free")
	local ready = false
	local lazy = FxCore.newPool(function()
		return if ready then { 1 } else nil
	end, function() end, 4)
	expect(lazy.borrow() == nil, "not ready -> nil")
	expectEq(lazy.total(), 0, "nothing counted")
	ready = true
	expect(lazy.borrow() ~= nil, "ready -> item")
end)

test("curve sampling interpolates, clamps and eases per segment", function()
	local keys = { { t = 0, v = 1 }, { t = 0.1, v = 0.5 }, { t = 0.3, v = 0, ease = FxCore.Easing.quadOut } }
	expectNear(FxCore.sample(keys, -1), 1, 1e-9, "before start")
	expectNear(FxCore.sample(keys, 0.05), 0.75, 1e-9, "linear segment")
	expectNear(FxCore.sample(keys, 0.1), 0.5, 1e-9, "key")
	-- halfway through the eased segment: quadOut(0.5) = 0.75 of the way from 0.5 to 0
	expectNear(FxCore.sample(keys, 0.2), 0.5 - 0.5 * 0.75, 1e-9, "eased segment")
	expectNear(FxCore.sample(keys, 5), 0, 1e-9, "after end")
	expectEq(FxCore.sample({}, 1), 0, "empty")
end)

test("easing endpoints and scale", function()
	for name, f in FxCore.Easing do
		expectNear(f(0), 0, 1e-9, name .. "(0)")
		expectNear(f(1), 1, 1e-9, name .. "(1)")
	end
	expectNear(FxCore.scale(5), 1, 1e-9, "5-stud die")
	expectNear(FxCore.scale(4.4), 0.88, 1e-9, "fallback die")
end)

test("scheduler connects lazily, swap-removes and disconnects when empty", function()
	local loop = fakeLoop()
	local sched = FxCore.newScheduler(loop.connect, 60)
	expect(not sched.isConnected(), "idle")
	local ticks, ended = { a = 0, b = 0, c = 0 }, {}
	local function effect(name, life)
		return sched.run(function()
			ticks[name] += 1
			return ticks[name] >= life
		end, function()
			table.insert(ended, name)
		end)
	end
	effect("a", 1)
	effect("b", 3)
	effect("c", 2)
	expectEq(loop.connects, 1, "one connection for three effects")
	expectEq(sched.live(), 3, "live")
	loop.step(0.016)
	expectEq(sched.live(), 2, "a finished")
	loop.step(0.016)
	loop.step(0.016)
	expectEq(sched.live(), 0, "all finished")
	expectEq(#ended, 3, "onEnd once each")
	expectEq(ticks.b, 3, "b stepped exactly its life")
	expectEq(ticks.c, 2, "c stepped exactly its life")
	expect(not sched.isConnected() and loop.disconnects == 1, "disconnected when empty")
end)

test("scheduler global cap and per-style limiter drop new effects, not old ones", function()
	local loop = fakeLoop()
	local sched = FxCore.newScheduler(loop.connect, 3)
	local limiter = FxCore.newLimiter(2)
	local forever = function()
		return false
	end
	expect(sched.run(forever, nil, limiter) ~= nil, "1")
	expect(sched.run(forever, nil, limiter) ~= nil, "2")
	expect(sched.run(forever, nil, limiter) == nil, "limiter full")
	expectEq(limiter.count, 2, "rejected run not counted")
	expect(sched.run(forever) ~= nil, "3 (no limiter)")
	expect(sched.run(forever) == nil, "global cap")
	expectEq(sched.live(), 3, "live")
end)

test("cancel and clear run onEnd, free the limiter and stop the loop", function()
	local loop = fakeLoop()
	local sched = FxCore.newScheduler(loop.connect, 60)
	local limiter = FxCore.newLimiter(5)
	local ended = 0
	local forever = function()
		return false
	end
	local h = sched.run(forever, function()
		ended += 1
	end, limiter)
	sched.run(forever, function()
		ended += 1
	end, limiter)
	expectEq(limiter.count, 2, "two taken")
	h.cancel()
	h.cancel()
	expectEq(ended, 1, "cancel is idempotent")
	expectEq(limiter.count, 1, "slot returned")
	expect(h.isDone(), "handle done")
	sched.clear()
	expectEq(ended, 2, "clear finished the rest")
	expectEq(limiter.count, 0, "limiter empty")
	expectEq(sched.live(), 0, "nothing live")
	expect(not sched.isConnected(), "disconnected")
end)

test("an erroring update is dropped without stopping the others", function()
	local loop = fakeLoop()
	local sched = FxCore.newScheduler(loop.connect, 60)
	local good = 0
	local ended = 0
	sched.run(function()
		error("boom")
	end, function()
		ended += 1
	end)
	sched.run(function()
		good += 1
		return good >= 2
	end)
	local realWarn = warn
	-- selene: allow(incorrect_standard_library_use)
	warn = function() end
	loop.step(0.016)
	loop.step(0.016)
	-- selene: allow(incorrect_standard_library_use)
	warn = realWarn
	expectEq(ended, 1, "failed effect cleaned up")
	expectEq(good, 2, "healthy effect kept running")
	expectEq(sched.live(), 0, "all gone")
end)

test("effects started inside a step are stepped from the next frame", function()
	local loop = fakeLoop()
	local sched = FxCore.newScheduler(loop.connect, 60)
	local childTicks = 0
	sched.run(function()
		sched.run(function()
			childTicks += 1
			return childTicks >= 1
		end)
		return true
	end)
	loop.step(0.016)
	expectEq(sched.live(), 1, "child alive after parent finished")
	loop.step(0.016)
	expectEq(childTicks, 1, "child stepped once")
	expectEq(sched.live(), 0, "child done")
end)

test("quality tier: phone or reduced motion is Low (projectile + flash only)", function()
	expectEq(FxCore.tier(false, false), "High", "desktop")
	expectEq(FxCore.tier(true, false), "Low", "reduced motion")
	expectEq(FxCore.tier(false, true), "Low", "phone")
	for _, layer in { "projectile", "flash" } do
		expect(FxCore.layerAllowed("Low", layer), layer .. " kept on Low")
	end
	for _, layer in { "trail", "ring", "shard", "support", "status" } do
		expect(not FxCore.layerAllowed("Low", layer), layer .. " dropped on Low")
		expect(FxCore.layerAllowed("High", layer), layer .. " allowed on High")
	end
	expectNear(FxCore.flashOpacity(true, 1), 0.6, 1e-9, "reduced flash capped")
	expectNear(FxCore.flashOpacity(false, 1), 1, 1e-9, "normal flash")
end)
