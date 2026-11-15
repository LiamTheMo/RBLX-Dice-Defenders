-- Codes popup logic: input shape, button modes, result messages.

local Codes = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Codes
local CodesLogic = require(Codes.CodesLogic)

local SERVER_PATTERN = "^[A-Za-z0-9_%-]+$" -- RemoteGuard's RedeemCode check

local function serverAccepts(s: string): boolean
	return #s <= 32 and string.find(s, SERVER_PATTERN) ~= nil
end

local function check(input: string, want: string, wantChanged: boolean, label: string)
	local got, changed = CodesLogic.sanitize(input)
	expectEq(got, want, label)
	expectEq(changed, wantChanged, label .. " changed")
end

test("constants", function()
	expectEq(CodesLogic.MAX_LEN, 32, "MAX_LEN")
	expectEq(CodesLogic.PRESS_COOLDOWN, 1, "PRESS_COOLDOWN")
	expectEq(CodesLogic.MESSAGE_SECONDS, 3, "MESSAGE_SECONDS")
end)

test("sanitize keeps valid input and case", function()
	check("Summer2026", "Summer2026", false, "mixed case")
	check("ABCXYZ", "ABCXYZ", false, "upper")
	check("abcxyz", "abcxyz", false, "lower")
	check("0123456789", "0123456789", false, "digits")
	check("DICE-DAY_1", "DICE-DAY_1", false, "dash and underscore")
	check("-_-", "-_-", false, "only dash and underscore")
	check("", "", false, "empty")
end)

test("sanitize removes spaces and symbols", function()
	check("  HELLO  ", "HELLO", true, "trim")
	check("DICE DAY", "DICEDAY", true, "inner space")
	check("A\0B\tC\rD\nE", "ABCDE", true, "control chars")
	check("\0\t\r\n", "", true, "only control chars")
	check("   ", "", true, "only spaces")
	check("!@#$%^&*()+=.,/", "", true, "only symbols")
	check("CODE!", "CODE", true, "trailing symbol")
end)

test("sanitize drops multi-byte characters whole", function()
	check("C\u{00D3}DE", "CDE", true, "accented letter")
	check("\u{1F3B2}DICE\u{1F3B2}", "DICE", true, "emoji")
	check("\u{FF21}\u{FF22}", "", true, "fullwidth letters")
	check("\u{200B}GO", "GO", true, "zero-width space")
end)

test("sanitize length cap", function()
	local exact = string.rep("A", 32)
	check(exact, exact, false, "exactly 32")
	check(exact .. "B", exact, false, "33 truncates")
	check(string.rep("Z", 100), string.rep("Z", 32), false, "100 truncates")
	-- Removal happens before the cap, so dropped characters do not use up length.
	check(string.rep(" ", 40) .. exact, exact, true, "spaces before 32")
	check(string.rep("A", 31) .. "\u{00E9}XY", string.rep("A", 31) .. "X", true, "multi-byte at the boundary")
end)

test("sanitize every single byte", function()
	for b = 0, 255 do
		local c = string.char(b)
		local allowed = string.find(c, SERVER_PATTERN) ~= nil
		check(c, if allowed then c else "", not allowed, "byte " .. b)
	end
	local allowedCount = 0
	for b = 0, 255 do
		if CodesLogic.sanitize(string.char(b)) ~= "" then
			allowedCount += 1
		end
	end
	expectEq(allowedCount, 26 + 26 + 10 + 2, "allowed byte count")
end)

test("sanitize output is always server-shaped", function()
	local rng = Random.new(20261115)
	for i = 1, 500 do
		local bytes = {}
		for j = 1, rng:NextInteger(0, 60) do
			bytes[j] = rng:NextInteger(0, 255)
		end
		local out = CodesLogic.sanitize(string.char(table.unpack(bytes)))
		expect(out == "" or serverAccepts(out), "random " .. i .. " -> " .. out)
	end
	for _, s in { "CÓDE", "\u{1F3B2}", "a b", string.rep("é", 40), "x\0y" } do
		local out = CodesLogic.sanitize(s)
		expect(out == "" or serverAccepts(out), "sample " .. s)
	end
end)

test("cursorAfter", function()
	local c = CodesLogic.cursorAfter
	expectEq(c("ABC", 4), 4, "clean text keeps the cursor")
	expectEq(c("AB C", 4), 3, "a space typed mid-code: cursor stays after it")
	expectEq(c("AB CD", 5), 4, "after the C")
	expectEq(c("A\u{00E9}B", 4), 2, "multi-byte before the cursor")
	expectEq(c(" ABC", 1), 1, "at the start")
	expectEq(c("ABC", -1), -1, "not editing")
	expectEq(c("ABC", 0), 0, "zero is unchanged")
	local long = string.rep("A", 33)
	expectEq(c(long, 34), 33, "past the cap: end of the 32 kept")
end)

test("edit: typing and pasting", function()
	local function e(prev, text, cursor, want, wantCursor, wantChanged, label)
		local got, c, changed = CodesLogic.edit(prev, text, cursor)
		expectEq(got, want, label)
		expectEq(c, wantCursor, label .. " cursor")
		expectEq(changed, wantChanged, label .. " changed")
	end
	local full = string.rep("A", 32)
	e("", "ABC", 4, "ABC", 4, false, "paste into empty")
	e("AB", "AXB", 3, "AXB", 3, false, "type mid-code")
	e("AB", "A B", 3, "AB", 2, true, "space mid-code")
	e("AB", "A\u{00E9}B", 4, "AB", 2, true, "multi-byte mid-code")
	e(full, "AAAAX" .. string.rep("A", 28), 6, full, 5, false, "type into the middle of a full field")
	e(full, full .. "B", 34, full, 33, false, "type at the end of a full field")
	e(full, "A" .. "XYZ" .. string.rep("A", 31), 5, full, 2, false, "paste into a full field")
	e(full, "A A" .. string.rep("A", 30), 3, full, 2, true, "space into a full field")
	e("", string.rep("Z", 40), 41, string.rep("Z", 32), 33, false, "overflowing paste into empty")
	e(string.rep("A", 30), "XYZ" .. string.rep("A", 30), 4, "XY" .. string.rep("A", 30), 3, false, "paste: what fits")
	e(full, string.rep("Q", 40), 41, string.rep("Q", 32), 33, false, "select-all replace with a long paste")
	e("ABC", "AC", 2, "AC", 2, false, "delete")
	e("AB", "A B C", -1, "ABC", -1, true, "script write, not editing")
	e("ABC", "", -1, "", -1, false, "cleared")
	for _, case in { { full, full .. "\u{1F3B2}", 37 }, { "", "\0\t", 3 }, { "AB", "A!!B", 4 } } do
		local got = CodesLogic.edit(case[1], case[2], case[3])
		expect(got == "" or serverAccepts(got), "server-shaped " .. got)
	end
end)

test("lock streak", function()
	for streak, want in
		{ [0] = 15, [1] = 15, [2] = 30, [3] = 60, [4] = 120, [5] = 240, [6] = 480, [7] = 600, [50] = 600 }
	do
		expectEq(CodesLogic.lockSeconds(streak), want, "lockSeconds " .. streak)
	end
	local n = CodesLogic.nextStreak
	expectEq(n(0, false, "RateLimited"), 1, "first lock")
	expectEq(n(3, false, "RateLimited"), 4, "consecutive")
	expectEq(n(3, false, "Throttled"), 3, "nothing sent")
	expectEq(n(3, false, "Invalid"), 0, "another reply resets")
	expectEq(n(3, false, "Network"), 0, "network resets")
	expectEq(n(3, true, nil), 0, "success resets")
	local r = CodesLogic.result(false, "RateLimited", 3) :: CodesLogic.Result
	expectEq(r.cooldown, 60, "streak 3 cooldown")
	expectEq(r.seconds, 60, "the message stays for the whole cooldown")
	expectEq(r.text, "Too many tries! Wait a moment.", "text")
	expect(table.isfrozen(r), "frozen")
	expectEq((CodesLogic.result(false, "RateLimited", 99) :: CodesLogic.Result).cooldown, 600, "capped")
	expectEq((CodesLogic.result(false, "Invalid") :: CodesLogic.Result).seconds, 3, "short replies show 3 s")
	expectEq((CodesLogic.result(true, nil) :: CodesLogic.Result).seconds, 3, "success shows 3 s")
end)

test("failure lock mirrors the server's guessing lock", function()
	local Balance = require(game:GetService("ServerScriptService").Server.Config.Balance)
	expectEq(CodesLogic.FREE_FAILURES, Balance.Redeem.freeFailures, "free failures = Balance.Redeem")
	expectEq(CodesLogic.LOCK_SECONDS, Balance.Redeem.lockSeconds, "base lock = Balance.Redeem")
	expectEq(CodesLogic.MAX_LOCK_SECONDS, Balance.Redeem.maxLockSeconds, "cap = Balance.Redeem")

	local nf = CodesLogic.nextFailures
	for _, code in
		{ "Invalid", "Expired", "AlreadyRedeemed", "Error", "NotLoaded", "BadArgs", "BadSeq", "NotOwner", "Bogus" }
	do
		expectEq(nf(2, false, code), 3, code .. " counts")
	end
	for _, code in { "Throttled", "Network", "RateLimited" } do
		expectEq(nf(2, false, code), 2, code .. " never reached the limiter")
	end
	expectEq(nf(7, true, nil), 7, "a success never resets it")

	-- Replay a guessing session: failures 1-5 are free, then 15 s doubling to the cap, as Rules/Redeem.
	local want = { 1, 1, 1, 1, 1, 15, 30, 60, 120, 240, 480, 600, 600 }
	local failures = 0
	for i, cooldown in want do
		failures = nf(failures, false, "Invalid")
		local r = CodesLogic.result(false, "Invalid", 0, failures) :: CodesLogic.Result
		expectEq(r.cooldown, cooldown, "failure " .. i .. " cooldown")
		expectEq(r.seconds, math.max(3, cooldown), "failure " .. i .. " message stays the whole cooldown")
		expectEq(
			r.text,
			if cooldown > 1 then "Too many tries! Wait a moment." else "That code isn't valid.",
			"text " .. i
		)
		expectEq(r.clear, false, "keeps the field " .. i)
	end
	expectEq(CodesLogic.failureLock(0), 0, "no failures")
	local net = CodesLogic.result(false, "Network", 0, 9) :: CodesLogic.Result
	expectEq(net.cooldown, 1, "a network error after the free failures locks nothing")
	expectEq(net.text, "Something went wrong. Try again.", "network text")
	expectEq(
		(CodesLogic.result(false, "RateLimited", 2, 9) :: CodesLogic.Result).cooldown,
		30,
		"out of sync: the streak"
	)
	expectEq((CodesLogic.result(true, nil, 0, 9) :: CodesLogic.Result).cooldown, 1, "success after a lock")
end)

test("keyboard lift", function()
	local lift = CodesLogic.lift
	-- Layout plan section 9 (unlifted field = lifted + lift).
	expectEq(lift(209, 272, 228), 52, "844x390, keyboard 162")
	expectEq(lift(209, 272, 181), 99, "844x390, keyboard 209")
	expectEq(lift(202, 262, 213), 57, "667x375, keyboard 162")
	expectEq(lift(202, 262, 166), 104, "667x375, keyboard 209")
	expectEq(lift(100, 160, 300), 0, "keyboard well below")
	expectEq(lift(100, 160, 168), 0, "exactly 8 clear")
	expectEq(lift(100, 160, 167), 1, "one short")
	expectEq(lift(50, 110, 20), 46, "never lifts the field top above y 4")
	expectEq(lift(2, 60, 20), 0, "field already at the top: no negative lift")
	-- Fractional rects (measured in Studio at 844x390): whole px, rounded towards a full 8 px gap and a field top >= 4.
	expectEq(lift(204, 275.3, 228), 56, "ceil keeps the gap >= 8")
	expectEq(lift(50.6, 110, 20), 46, "floor keeps the top >= 4")
end)

test("buttonMode", function()
	local m = CodesLogic.buttonMode
	expectEq(m("CODE", false, 10, 0), "Ready", "ready")
	expectEq(m("", false, 10, 0), "Disabled", "empty")
	expectEq(m("  !! ", false, 10, 0), "Disabled", "only invalid")
	expectEq(m("CODE", false, 10, 11), "Cooldown", "cooldown")
	expectEq(m("CODE", true, 10, 0), "Waiting", "waiting")
	-- Precedence: Waiting > Cooldown > Disabled > Ready.
	expectEq(m("", true, 10, 11), "Waiting", "waiting beats cooldown and disabled")
	expectEq(m("", false, 10, 11), "Cooldown", "cooldown beats disabled")
	-- Boundary: cooldown holds while now < cooldownUntil.
	expectEq(m("CODE", false, 10.999, 11), "Cooldown", "just before")
	expectEq(m("CODE", false, 11, 11), "Ready", "at the boundary")
	expectEq(m("", false, 11, 11), "Disabled", "empty at the boundary")
end)

test("result success", function()
	local r = CodesLogic.result(true, nil) :: CodesLogic.Result
	expectEq(r.text, "Code redeemed!", "text")
	expectEq(r.tone, "Success", "tone")
	expectEq(r.cooldown, 1, "cooldown")
	expectEq(r.clear, true, "clear")
end)

test("result failures", function()
	local want = {
		Invalid = { "That code isn't valid.", "Error", 1 },
		Expired = { "That code has expired.", "Error", 1 },
		AlreadyRedeemed = { "You already used that code.", "Info", 1 },
		RateLimited = { "Too many tries! Wait a moment.", "Error", 15 },
	}
	for _, code in { "Network", "Error", "NotLoaded", "BadArgs", "BadSeq", "NotOwner", "Bogus", "" } do
		want[code] = { "Something went wrong. Try again.", "Error", 1 }
	end
	for code, w in want do
		local r = CodesLogic.result(false, code) :: CodesLogic.Result
		expectEq(r.text, w[1], code .. " text")
		expectEq(r.tone, w[2], code .. " tone")
		expectEq(r.cooldown, w[3], code .. " cooldown")
		expectEq(r.clear, false, code .. " keeps the text")
	end
	expectEq((CodesLogic.result(false, nil) :: CodesLogic.Result).text, "Something went wrong. Try again.", "nil code")
	expectEq(CodesLogic.result(false, "Throttled"), nil, "throttled is ignored")
end)

test("result messages fit one line", function()
	local all = { CodesLogic.result(true, nil) }
	for _, code in { "Invalid", "Expired", "AlreadyRedeemed", "RateLimited", "Network" } do
		table.insert(all, CodesLogic.result(false, code))
	end
	for _, r in all do
		local res = r :: CodesLogic.Result
		expect(#res.text <= 32, "too long: " .. res.text)
		expect(table.isfrozen(res), "frozen: " .. res.text)
	end
end)
