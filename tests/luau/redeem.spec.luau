-- Redeem rules: Normalize, Claim (valid, unknown, expired, not started, already
-- redeemed, overflow, double call), the guessing limiter on an injected clock, the
-- shipped catalog, and no code data in any module under src/shared or src/client.

local Server = game:GetService("ServerScriptService").Server
local Redeem = require(Server.Rules.Redeem)
local Codes = require(Server.Config.Codes)
local QuestConfig = require(Server.Config.Quests)
local Balance = require(Server.Config.Balance)
local Economy = require(Server.Rules.Economy)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local RemoteGuard = require(Server.Infrastructure.RemoteGuard)

local T = 1_800_000_000 -- a fixed os.time()
local L = Balance.Redeem

local function fresh()
	return ProfileSchema.Default()
end

-- A catalog with time windows (the shipped one has none).
local TIMED = {
	ByCode = {
		SOON = { Id = "soon", Code = "SOON", Gold = 10, StartsAt = T + 60 },
		OLD = { Id = "old", Code = "OLD", Gold = 10, ExpiresAt = T },
		WINDOW = { Id = "window", Code = "WINDOW", Gold = 10, StartsAt = T - 10, ExpiresAt = T + 10 },
	},
}

-- Fails `n` guesses at `now` (no lock is running yet).
local function failFree(limiter, n, now)
	for _ = 1, n do
		Redeem.Attempt(limiter, fresh(), "NOPE", now)
	end
end

test("Normalize trims whitespace and upper-cases; non-strings are nil", function()
	expectEq(Redeem.Normalize(" welcome "), "WELCOME", "spaces")
	expectEq(Redeem.Normalize("\t\r\nWeLcOmE\n "), "WELCOME", "mixed whitespace and case")
	expectEq(Redeem.Normalize("ab-c_9"), "AB-C_9", "symbols and digits kept")
	expectEq(Redeem.Normalize("a b"), "A B", "inner space kept")
	expectEq(Redeem.Normalize("   "), "", "blank")
	for _, bad in { 5, true, {} } do
		expectEq(Redeem.Normalize(bad), nil, "non-string " .. type(bad))
	end
	expectEq(Redeem.Normalize(nil), nil, "nil")
end)

test("Claim: a valid code in any case pays its Gold once and records the Id", function()
	local p = fresh()
	p.Gold = 7
	local ok, code = Redeem.Claim(p, " welcome ", T)
	expect(ok and code == nil, "redeemed")
	expectEq(p.Gold, 7 + Codes.ByCode.WELCOME.Gold, "gold paid")
	expectEq(p.Redeemed.welcome, true, "id recorded")
end)

test("Claim: unknown text is Invalid and changes nothing", function()
	for _, text in { "NOPE", "WELCOMEX", "", "WEL COME", "welcome!", 5, true, {} } do
		local p = fresh()
		local before = snap(p)
		local ok, code = Redeem.Claim(p, text, T)
		expect(not ok and code == "Invalid", "Invalid for " .. tostring(text))
		expectEq(snap(p), before, "unchanged for " .. tostring(text))
	end
end)

test("Claim: Expired from ExpiresAt on; not started yet reads as Invalid", function()
	local p = fresh()
	local _, expired = Redeem.Claim(p, "old", T, TIMED)
	expectEq(expired, "Expired", "at ExpiresAt")
	local _, early = Redeem.Claim(p, "soon", T + 59, TIMED)
	expectEq(early, "Invalid", "before StartsAt")
	expectEq(p.Gold, 0, "nothing paid")
	expectEq(next(p.Redeemed), nil, "nothing recorded")
	expect(Redeem.Claim(fresh(), "old", T - 1, TIMED), "a second before expiry")
	expect(Redeem.Claim(fresh(), "soon", T + 60, TIMED), "at StartsAt")
	expect(Redeem.Claim(fresh(), "window", T, TIMED), "inside the window")
end)

test("Claim: a double call grants once; the second is AlreadyRedeemed in any case", function()
	local p = fresh()
	expect(Redeem.Claim(p, "WELCOME", T), "first")
	local gold = p.Gold
	local ok, code = Redeem.Claim(p, "welcome", T)
	expect(not ok and code == "AlreadyRedeemed", "second")
	expectEq(p.Gold, gold, "paid once")
end)

test("Claim: Overflow leaves the profile unchanged and the code unredeemed", function()
	local p = fresh()
	p.Gold = Economy.MAX - 1
	local before = snap(p)
	local ok, code = Redeem.Claim(p, "WELCOME", T)
	expect(not ok and code == "Overflow", "overflow")
	expectEq(snap(p), before, "unchanged")
	p.Gold = 0
	expect(Redeem.Claim(p, "WELCOME", T), "still redeemable once there is room")
end)

test("Attempt replies only Invalid, Expired, AlreadyRedeemed or RateLimited; each is a failure", function()
	local limiter = Redeem.NewLimiter()
	local p = fresh()
	p.Gold = Economy.MAX
	local _, overflow = Redeem.Attempt(limiter, p, "WELCOME", T)
	expectEq(overflow, "Invalid", "Overflow is not revealed")
	expectEq(limiter.failures, 1, "overflow counted")
	local q = fresh()
	expect(Redeem.Attempt(limiter, q, "welcome", T), "valid code ok")
	expectEq(limiter.failures, 1, "success not counted")
	local _, again = Redeem.Attempt(limiter, q, "WELCOME", T)
	expectEq(again, "AlreadyRedeemed", "already")
	expectEq(limiter.failures, 2, "AlreadyRedeemed counted")
	local _, expired = Redeem.Attempt(limiter, fresh(), "OLD", T, TIMED)
	expectEq(expired, "Expired", "expired")
	expectEq(limiter.failures, 3, "Expired counted")
end)

test("limiter: free failures never lock; a success neither counts nor resets", function()
	expectEq(L.freeFailures, 5, "5 free failures")
	local limiter, p = Redeem.NewLimiter(), fresh()
	for i = 1, L.freeFailures do
		local ok, code, abuse = Redeem.Attempt(limiter, p, "NOPE", T)
		expect(not ok and code == "Invalid" and abuse == false, "free failure " .. i)
	end
	expectEq(limiter.lockedUntil, -math.huge, "not locked")
	expect(Redeem.Attempt(limiter, p, "WELCOME", T), "a valid code still works")
	expectEq(limiter.failures, L.freeFailures, "success not counted, not reset")
	local _, code = Redeem.Attempt(limiter, p, "NOPE", T)
	expectEq(code, "Invalid", "the next failure is still evaluated")
	expectEq(limiter.lockedUntil, T + 15, "then locks for 15 s")
end)

test("limiter: while locked, RateLimited without evaluating the code; evaluated again after", function()
	local limiter = Redeem.NewLimiter()
	failFree(limiter, L.freeFailures + 1, T) -- locked until T + 15
	local p = fresh()
	local before = snap(p)
	local ok, code = Redeem.Attempt(limiter, p, "WELCOME", T + 14)
	expect(not ok and code == "RateLimited", "locked")
	expectEq(snap(p), before, "a valid code was not evaluated")
	local _, code2 = Redeem.Attempt(limiter, nil, "WELCOME", T + 14) -- evaluating would throw on nil
	expectEq(code2, "RateLimited", "not evaluated (nil profile)")
	expect(Redeem.Attempt(limiter, p, "WELCOME", limiter.lockedUntil), "evaluated once the lock ends")
	expectEq(p.Redeemed.welcome, true, "and redeemed")
end)

test("limiter: each further failure doubles the lock up to 600 s; locked replies never extend it", function()
	local limiter = Redeem.NewLimiter()
	failFree(limiter, L.freeFailures, T)
	local t = T
	for i, seconds in { 15, 30, 60, 120, 240, 480, 600, 600, 600 } do
		t = math.max(t, limiter.lockedUntil) -- wait the lock out so the guess is evaluated
		local _, code = Redeem.Attempt(limiter, fresh(), "NOPE", t)
		expectEq(code, "Invalid", "evaluated " .. i)
		expectEq(limiter.lockedUntil - t, seconds, "lock " .. i)
	end
	local before = limiter.failures
	local _, code = Redeem.Attempt(limiter, fresh(), "NOPE", t + 1)
	expectEq(code, "RateLimited", "locked")
	expectEq(limiter.failures, before, "a locked reply is not an evaluated failure")
	expectEq(limiter.locked, 1, "but is tallied for the abuse threshold")
	expectEq(limiter.lockedUntil, t + 600, "and leaves the lock as it was")
	local _, back = Redeem.Attempt(limiter, fresh(), "NOPE", T) -- clock went backwards
	expectEq(back, "RateLimited", "an earlier clock never unlocks")
	expectEq(limiter.lockedUntil, t + 600, "nor shortens the lock")
end)

test("limiter: the 50th failure of a session flags abuse exactly once", function()
	expectEq(L.kickFailures, 50, "threshold")
	local limiter, flagged = Redeem.NewLimiter(), {}
	for i = 1, L.kickFailures + 20 do
		local _, _, abuse = Redeem.Attempt(limiter, fresh(), "NOPE", T + i) -- mostly locked replies
		if abuse then
			table.insert(flagged, i)
		end
	end
	expect(#flagged == 1 and flagged[1] == L.kickFailures, "flagged once, at 50 (" .. #flagged .. ")")
	expectEq(limiter.failures + limiter.locked, L.kickFailures + 20, "every reply counted")
	local separate = Redeem.NewLimiter()
	failFree(separate, 3, T)
	expectEq(separate.failures, 3, "limiters are independent")
end)

test("shipped catalog: one launch code paying the daily quest's Gold; every code is well formed", function()
	expectEq(#Codes.List, 1, "one code")
	local welcome = Codes.ByCode.WELCOME
	expect(welcome ~= nil and welcome.Id == "welcome", "WELCOME -> welcome")
	expectEq(welcome.Gold, QuestConfig.ById.D1.Reward.Gold, "= the D1 daily reward")
	expectEq(welcome.Gold, 100, "100 Gold")
	local ids = {}
	for _, entry in Codes.List do
		expect(type(entry.Id) == "string" and #entry.Id > 0 and ids[entry.Id] == nil, "unique id " .. entry.Id)
		ids[entry.Id] = true
		expectEq(Redeem.Normalize(entry.Code), entry.Code, "code stored normalised")
		expect(RemoteGuard.Specs.RedeemCode.check(entry.Code) == true, "code passes the remote check")
		expect(Economy.TryChange({ Gold = 0 }, "Gold", entry.Gold) and entry.Gold > 0, "positive integer Gold")
		expectEq(Codes.ById[entry.Id], entry, "ById")
		expect(table.isfrozen(entry), "entry frozen")
	end
	expect(table.isfrozen(Codes.List) and table.isfrozen(Codes.ByCode), "catalog frozen")
	-- Every Id ever shipped: append here, never remove. A deleted entry would drop its
	-- saved flags on load, and re-adding the Id would pay everyone again.
	for _, id in { "welcome" } do
		expect(Codes.ById[id] ~= nil, "shipped id still in the catalog: " .. id)
	end
end)

test("no module under src/shared or src/client holds a code or a code table", function()
	local scanned = 0
	for path, source in __sources do
		if string.sub(path, 1, 18) == "ReplicatedStorage/" or string.sub(path, 1, 14) == "StarterPlayer/" then
			scanned += 1
			expect(not string.find(source, "WELCOME", 1, true), path .. " contains WELCOME")
			expect(not string.find(source, "ByCode", 1, true), path .. " has a code lookup")
			for _, entry in Codes.List do
				expect(not string.find(source, entry.Code, 1, true), path .. " contains " .. entry.Code)
			end
		end
	end
	expect(scanned > 10, "scanned the shared and client modules (" .. scanned .. ")")
	expect(__sources["StarterPlayer/StarterPlayerScripts/Client/init.client"] ~= nil, "entry scripts scanned too")
	local server = __sources["ServerScriptService/Server/Config/Codes"]
	expect(server ~= nil and string.find(server, "WELCOME", 1, true) ~= nil, "the scan sees the server table")
end)

test("Claim pays through Rewards.Apply: Gold and optional Gems land whole or not at all, once per code", function()
	local Rewards = require(Server.Rules.Rewards)
	local GEMS = { ByCode = { GEM = { Id = "gem", Code = "GEM", Gold = 10, Gems = 5 } } }
	local p = fresh()
	expect(Redeem.Claim(p, " gem ", T, GEMS), "redeemed")
	expect(p.Gold == 10 and p.Gems == 55 and p.Redeemed.gem == true, "Gold and Gems paid, id recorded")
	local before = snap(p)
	local _, again = Redeem.Claim(p, "GEM", T, GEMS)
	expectEq(again, "AlreadyRedeemed", "once")
	expectEq(snap(p), before, "nothing paid twice")
	local q = fresh()
	q.Gems = Economy.MAX
	local qBefore = snap(q)
	local ok, code = Redeem.Claim(q, "GEM", T, GEMS)
	expect(not ok and code == "Overflow", "Gems at the cap: Overflow")
	expectEq(snap(q), qBefore, "Gold not paid either, code not redeemed")
	for _, entry in Codes.List do
		expect(Rewards.Valid({ Gold = entry.Gold, Gems = entry.Gems }), "shipped code is a valid bundle: " .. entry.Id)
	end
	local source = __sources["ServerScriptService/Server/Rules/Redeem"]
	expect(not string.find(source, "TryChange", 1, true), "Redeem pays only through Rewards.Apply")
end)
