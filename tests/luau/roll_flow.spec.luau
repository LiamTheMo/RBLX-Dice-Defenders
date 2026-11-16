-- Roll press flow (pure state machine): failure replies, result before / after the reply, minimum spin, timeouts, busy
-- presses, a lost reply, close mid-roll, stale results, Reduced Motion, and no randomness in the module.

local Roll = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Roll
local RollFlow = require(Roll.RollFlow)

local RESULT = { Pool = "Standard", Results = { { Id = "C01", Rarity = "Common", New = false } } }

local function pressed(now, reduced)
	local f = RollFlow.new()
	local a = f:Press(now or 0, reduced)
	expect(a.send == true and a.show == "rolling" and a.gen == 1, "press sends and shows rolling")
	return f, a
end

test("failure reply: each code toasts a readable text and returns to Idle", function()
	local codes = {
		"Insufficient",
		"Restricted",
		"Throttled",
		"RateLimited",
		"NotLoaded",
		"NotOwner",
		"Network",
		"Error",
		"BadArgs",
		"BadSeq",
	}
	for _, code in codes do
		local f, a = pressed()
		local r = f:Reply(a.gen, false, code, 0.1)
		expect(r.show == "idle" and r.toast == RollFlow.REPLIES[code] and f:IsIdle(), code)
		expect(r.toast ~= code and #r.toast > 0, code .. ": never the raw code")
	end
	local f, a = pressed()
	expectEq(f:Reply(a.gen, false, "Weird", 0.1).toast, "Something went wrong", "unknown code")
	f, a = pressed()
	expectEq(f:Reply(a.gen, false, nil, 0.1).toast, "Something went wrong", "no code")
end)

test("result before the reply: reveal only after the minimum spin", function()
	local f, a = pressed(0)
	expectEq(f:Result(RESULT, 0.1), nil, "buffered while sending")
	expectEq(f:Reply(a.gen, true, nil, 0.2), nil, "reply ok, spin not over")
	expectEq(f:Next(), 0.6, "wakes at min spin")
	expectEq(f:Tick(0.5), nil, "still spinning")
	local r = f:Tick(0.6)
	expect(r.show == "reveal" and r.result == RESULT, "reveal at 0.6")
	expectNear(f:Next(), 0.9, 1e-9, "reveal lasts 0.3")
	expectEq(f:Tick(0.8), nil, "revealing")
	r = f:Tick(0.9)
	expect(r.show == "idle" and r.settle == RESULT and f:IsIdle(), "settled")
end)

test("result after the reply, and a slow reply past the minimum spin", function()
	local f, a = pressed(0)
	expectEq(f:Reply(a.gen, true, nil, 0.1), nil, "rolling")
	expectEq(f:Next(), 10, "only the timeout while no result")
	expectEq(f:Result(RESULT, 0.3), nil, "too early to reveal")
	expectEq(f:Tick(0.6).show, "reveal", "min spin respected")
	f, a = pressed(0)
	f:Result(RESULT, 0.1)
	expectEq(f:Reply(a.gen, true, nil, 2).show, "reveal", "reply after min spin reveals at once")
end)

test("timeout in Sending and in Rolling returns to Idle with a toast", function()
	local f = pressed(0)
	expectEq(f:Next(), 10, "deadline")
	expectEq(f:Tick(9.9), nil, "not yet")
	local r = f:Tick(10)
	expect(r.show == "idle" and r.toast == "Connection problem" and f:IsIdle(), "sending timeout")
	local g, a = pressed(0)
	g:Reply(a.gen, true, nil, 1)
	r = g:Tick(10)
	expect(r.show == "idle" and r.toast == "Connection problem" and g:IsIdle(), "rolling timeout")
end)

test("a press while busy is ignored", function()
	local f = pressed(0)
	local a = f:Press(0.1)
	expect(a.send == nil and a.toast == nil and a.show == nil, "sending: ignored")
	f:Reply(1, true, nil, 0.2)
	a = f:Press(0.3)
	expect(a.send == nil and a.toast == nil, "rolling: ignored")
	f:Result(RESULT, 0.6)
	a = f:Press(0.7)
	expect(a.send == nil and a.toast == nil, "revealing: ignored")
	expectEq(f.gen, 1, "no second request")
end)

test("press after a timeout while the invoke is still open: toast, no send", function()
	local f, a = pressed(0)
	f:Tick(10)
	local p = f:Press(11)
	expect(p.send == nil and p.toast == RollFlow.STILL_WAITING, "still waiting")
	expectEq(f:Reply(a.gen, true, nil, 12), nil, "the late reply is ignored")
	p = f:Press(13)
	expect(p.send == true, "after the invoke returned a press goes through")
end)

test("close mid-roll: Idle, the result that follows is stale (late)", function()
	local f, a = pressed(0)
	f:Close()
	expect(f:IsIdle() and f:Next() == nil, "idle, nothing scheduled")
	expectEq(f:Reply(a.gen, true, nil, 0.1), nil, "reply ignored")
	local r = f:Result(RESULT, 0.2)
	expect(r.late == RESULT and r.show == nil, "late result")
	local g, b = pressed(0)
	g:Reply(b.gen, true, nil, 0.1)
	g:Close()
	expect(g:Result(RESULT, 0.2).late == RESULT, "closed while rolling: late")
end)

test("stale result after a timeout is late", function()
	local f, a = pressed(0)
	f:Tick(10)
	f:Reply(a.gen, true, nil, 11)
	expect(f:Result(RESULT, 12).late == RESULT, "late")
end)

test(
	"Roll.luau skips Meta / Catalog re-renders while the flow is not Idle (pity / gems do not leak the outcome)",
	function()
		local f, a = pressed(0)
		expect(not f:IsIdle(), "sending: refresh gate closed")
		f:Reply(a.gen, true, nil, 0.1)
		expect(not f:IsIdle(), "rolling: refresh gate closed")
		f:Result(RESULT, 0.2)
		expect(f:Tick(0.6).show == "reveal" and not f:IsIdle(), "revealing: refresh gate closed")
		expect(f:Tick(0.9).settle == RESULT and f:IsIdle(), "settle opens it (and renders once)")
		local source = __sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/Roll/Roll"]
		expect(
			string.find(source or "", "flow:IsIdle() and select(5, inputs())", 1, true) ~= nil,
			"refresh is gated on Idle"
		)
	end
)

test("timeout, stale reply ok, press B, A's result arrives: late only; B's own result is revealed", function()
	local f, a = pressed(0)
	f:Tick(10)
	expectEq(f:Reply(a.gen, true, nil, 11), nil, "A's reply ignored")
	local b = f:Press(12)
	expect(b.send == true, "B sent")
	expect(f:Result(RESULT, 12.5).late == RESULT, "A's result is late, not B's")
	expect(not f:IsIdle(), "B still sending")
	f:Reply(b.gen, true, nil, 13)
	local r2 = { Pool = "Standard", Results = { { Id = "C02", Rarity = "Common", New = true } } }
	expect(f:Result(r2, 13.1).result == r2, "B's own result revealed (spin already over)")
	-- result before the reply while timed out: consumed as stale, B is unaffected
	f = RollFlow.new()
	a = f:Press(0)
	f:Tick(10)
	expect(f:Result(RESULT, 10.5).late == RESULT, "late")
	f:Reply(a.gen, true, nil, 11)
	b = f:Press(12)
	f:Reply(b.gen, true, nil, 12.1)
	f:Result(r2, 12.2)
	expect(f:Tick(12.6).result == r2, "B reveals")
	-- a failed or silent A does not poison B
	f = RollFlow.new()
	a = f:Press(0)
	f:Tick(10)
	f:Reply(a.gen, false, "Error", 11)
	b = f:Press(12)
	f:Reply(b.gen, true, nil, 12.1)
	f:Result(r2, 12.2)
	expect(f:Tick(12.6).result == r2, "failed A: B reveals")
	f = RollFlow.new()
	a = f:Press(0)
	f:Close(1)
	f:Reply(a.gen, true, nil, 2)
	b = f:Press(9)
	f:Reply(b.gen, true, nil, 9.1)
	f:Result(r2, 9.2)
	expect(f:Tick(9.8).result == r2, "A's window (5 s) over: B reveals")
end)

test(
	"close with a result buffered but not revealed hands it back to be toasted; after the reveal it does not",
	function()
		local f, a = pressed(0)
		expect(f:Result(RESULT, 0.05) == nil, "result before the reply is buffered")
		local c = f:Close(0.1)
		expect(
			c ~= nil and c.late == RESULT and f:IsIdle(),
			"closed while Sending: the buffered result comes back as late"
		)
		f, a = pressed(0)
		f:Reply(a.gen, true, nil, 0.1)
		f:Result(RESULT, 0.2) -- buffered, minimum spin not over
		c = f:Close(0.3)
		expect(c ~= nil and c.late == RESULT, "closed while Rolling inside the minimum spin: late")
		f, a = pressed(0)
		f:Reply(a.gen, true, nil, 0.1)
		local r = f:Result(RESULT, 0.7)
		expect(r ~= nil and r.show == "reveal", "revealing (already toasted by the reveal)")
		expect(f:Close(0.8) == nil, "closed while Revealing: nothing more to tell")
		f, a = pressed(0)
		expect(
			f:Close(0.1) == nil,
			"closed with nothing buffered: nothing to tell now (the result that follows is late)"
		)
	end
)

test("reduced motion: no spin and no reveal delay", function()
	local f, a = pressed(0, true)
	f:Reply(a.gen, true, nil, 0)
	local r = f:Result(RESULT, 0)
	expect(r.show == "reveal", "reveals at once")
	expectEq(f:Next(), 0, "no reveal delay")
	r = f:Tick(0)
	expect(r.settle == RESULT and f:IsIdle(), "settles at once")
end)

test("RollFlow never uses randomness", function()
	local source = __sources["StarterPlayer/StarterPlayerScripts/Client/Controllers/Roll/RollFlow"]
	expect(source ~= nil, "scanned")
	for _, word in { "math.random", "Random", "require(" } do
		expect(not string.find(source or "", word, 1, true), word)
	end
end)
