-- Settings store: registry shape, cleaning, set/reset, change signal, cycle, format.

local SettingsLogic =
	require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Settings.SettingsLogic)

test("registry", function()
	expectEq(#SettingsLogic.DEFS, 20, "count")
	local seen, perTab, real = {}, {}, {}
	for _, def in SettingsLogic.DEFS do
		expect(not seen[def.id], "duplicate " .. def.id)
		seen[def.id] = true
		perTab[def.tab] = (perTab[def.tab] or 0) + 1
		expectEq(SettingsLogic.clean(def, def.default), def.default, "default valid " .. def.id)
		expectEq(SettingsLogic.byId[def.id], def, "byId " .. def.id)
		if not def.noEffectYet then
			real[def.id] = true
		end
	end
	for tab, n in { GAMEPLAY = 4, GRAPHICS = 6, AUDIO = 5, MISC = 5 } do
		expectEq(perTab[tab], n, tab)
	end
	expectEq(table.concat(SettingsLogic.TABS, ","), "GAMEPLAY,GRAPHICS,AUDIO,MISC", "tab order")
	local want = {
		shadows = true,
		uiScale = true,
		reducedMotion = true,
		showFps = true,
		projectileEffects = true,
		masterVolume = true,
		sfxVolume = true,
		interfaceVolume = true,
	}
	for id in want do
		expect(real[id], "real " .. id)
	end
	for id in real do
		expect(want[id], "unexpectedly real " .. id)
	end
end)

test("clamp and step", function()
	SettingsLogic.resetAll()
	for _, c in { { "uiScale", 73, 75 }, { "uiScale", 200, 100 }, { "uiScale", 10, 70 }, { "effectScale", 27.4, 25 } } do
		expect(SettingsLogic.set(c[1], c[2]), "accepted " .. c[1])
		expectEq(SettingsLogic.get(c[1]), c[3], c[1] .. " " .. c[2])
	end
end)

test("bad input rejected, state unchanged, no signal", function()
	SettingsLogic.resetAll()
	local fired = 0
	local off = SettingsLogic.onChanged(function()
		fired += 1
	end)
	local bad = {
		{ "uiScale", 0 / 0 },
		{ "uiScale", math.huge },
		{ "uiScale", -math.huge },
		{ "uiScale", "80" },
		{ "uiScale", true },
		{ "shadows", 1 },
		{ "effectsQuality", "Ultra" },
		{ "nope", true },
	}
	for _, c in bad do
		expect(not SettingsLogic.set(c[1], c[2]), "rejected " .. c[1] .. " " .. tostring(c[2]))
	end
	expectEq(SettingsLogic.get("uiScale"), 100, "uiScale kept")
	expectEq(SettingsLogic.get("shadows"), true, "shadows kept")
	expectEq(SettingsLogic.get("effectsQuality"), "High", "quality kept")
	expectEq(SettingsLogic.get("nope"), nil, "unknown id")
	expectEq(fired, 0, "no signal")
	off()
end)

test("signal once per real change; disconnect; throwing listener", function()
	SettingsLogic.resetAll()
	local log = {}
	local off = SettingsLogic.onChanged(function(id, value)
		table.insert(log, id .. "=" .. tostring(value))
	end)
	local bomb = SettingsLogic.onChanged(function()
		error("boom")
	end)
	expect(SettingsLogic.set("shadows", false), "set")
	expect(SettingsLogic.set("shadows", false), "same value still accepted")
	expectEq(#log, 1, "once")
	expectEq(log[1], "shadows=false", "payload")
	expectEq(SettingsLogic.get("shadows"), false, "stored despite throwing listener")
	SettingsLogic.set("uiScale", 72) -- cleans to 70
	SettingsLogic.set("uiScale", 70)
	expectEq(#log, 2, "cleaned-equal value is not a change")
	off()
	bomb()
	SettingsLogic.set("shadows", true)
	expectEq(#log, 2, "disconnected")
end)

test("resetTab and resetAll", function()
	SettingsLogic.resetAll()
	SettingsLogic.set("shadows", false)
	SettingsLogic.set("masterVolume", 10)
	local log = {}
	local off = SettingsLogic.onChanged(function(id)
		table.insert(log, id)
	end)
	SettingsLogic.resetTab("GRAPHICS")
	expectEq(SettingsLogic.get("shadows"), true, "graphics reset")
	expectEq(SettingsLogic.get("masterVolume"), 10, "audio untouched")
	expectEq(#log, 1, "fired once per changed setting")
	SettingsLogic.resetAll()
	expectEq(SettingsLogic.get("masterVolume"), 100, "all reset")
	expectEq(#log, 2, "only the changed one fired")
	off()
end)

test("cycle", function()
	SettingsLogic.resetAll()
	expect(SettingsLogic.cycle("effectsQuality", 1), "wrap up")
	expectEq(SettingsLogic.get("effectsQuality"), "Low", "High -> Low")
	expect(SettingsLogic.cycle("effectsQuality", -1), "wrap down")
	expectEq(SettingsLogic.get("effectsQuality"), "High", "Low -> High")
	expect(not SettingsLogic.cycle("shadows", 1), "not a select")
end)

test("format", function()
	SettingsLogic.resetAll()
	expectEq(SettingsLogic.format("shadows"), "ON", "on")
	expectEq(SettingsLogic.format("shadows", false), "OFF", "off")
	expectEq(SettingsLogic.format("effectScale"), "75%", "percent")
	expectEq(SettingsLogic.format("effectsQuality"), "HIGH", "select")
end)

test("removed defs", function()
	for _, id in { "language", "rangeRings", "placementGrid" } do
		expect(SettingsLogic.byId[id] == nil, id .. " has no def")
		expectEq(SettingsLogic.get(id), nil, id .. " get")
	end
end)

test("fromFraction", function()
	expectEq(SettingsLogic.fromFraction("uiScale", 0), 70, "min")
	expectEq(SettingsLogic.fromFraction("uiScale", 1), 100, "max")
	expectEq(SettingsLogic.fromFraction("uiScale", 0.5), 85, "mid")
	expectEq(SettingsLogic.fromFraction("uiScale", 0.52), 85, "snaps down")
	expectEq(SettingsLogic.fromFraction("uiScale", 0.6), 90, "snaps up")
	expectEq(SettingsLogic.fromFraction("uiScale", -3), 70, "clamps low")
	expectEq(SettingsLogic.fromFraction("uiScale", 9), 100, "clamps high")
	expectEq(SettingsLogic.fromFraction("effectScale", 0.5), 65, "offset range")
	expectEq(SettingsLogic.fromFraction("masterVolume", 0.333), 35, "0..100")
	expectEq(SettingsLogic.fromFraction("uiScale", 0 / 0), nil, "NaN")
	expectEq(SettingsLogic.fromFraction("shadows", 0.5), nil, "not a slider")
	expectEq(SettingsLogic.fromFraction("nope", 0.5), nil, "unknown id")
end)
