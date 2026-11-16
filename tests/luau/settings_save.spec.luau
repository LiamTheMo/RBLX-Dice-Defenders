-- Saved settings: the shared registry (one table for client and server), the SaveSettings shape
-- guard and Rules/Settings.Merge (known keys only, every value cleaned, bad ones dropped).

local SettingsDefs = require(game:GetService("ReplicatedStorage").Shared.SettingsDefs)
local SettingsLogic =
	require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Settings.SettingsLogic)
local Server = game:GetService("ServerScriptService").Server
local ProfileSchema = require(Server.Rules.ProfileSchema)
local Settings = require(Server.Rules.Settings)

local NAN, INF = 0 / 0, math.huge

local function snap(value)
	if type(value) ~= "table" then
		return tostring(value)
	end
	local keys = {}
	for k in value do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in keys do
		table.insert(parts, tostring(k) .. "=" .. snap(value[k]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function fresh()
	return ProfileSchema.Default()
end

test("one registry: the client store reads the shared defs; frozen", function()
	expectEq(SettingsLogic.DEFS, SettingsDefs.DEFS, "same DEFS table")
	expectEq(SettingsLogic.byId, SettingsDefs.ById, "same lookup")
	expectEq(SettingsLogic.clean, SettingsDefs.clean, "same cleaner")
	expectEq(#SettingsDefs.DEFS, 23, "23 settings")
	expect(table.isfrozen(SettingsDefs.DEFS) and table.isfrozen(SettingsDefs.ById), "registry frozen")
	for _, def in SettingsDefs.DEFS do
		expect(table.isfrozen(def), def.id .. " frozen")
		expect(#def.id >= 1 and #def.id <= 32, def.id .. " fits the 32-byte key limit")
		if def.options then
			for _, option in def.options do
				expect(#option <= 32, def.id .. " option fits the 32-byte value limit")
			end
		end
	end
end)

test("Shape: a full patch of every default is well formed", function()
	local patch = {}
	for _, def in SettingsDefs.DEFS do
		patch[def.id] = def.default
	end
	expect(SettingsDefs.Shape(patch), "every default")
	expect(SettingsDefs.Shape({}), "empty")
	expect(not SettingsDefs.Shape({ uiScale = NAN }), "NaN is a number but not finite")
end)

test("Merge writes cleaned values for known keys and returns true", function()
	local p = fresh()
	expectEq(
		Settings.Merge(p, { shadows = false, effectsQuality = "Low", autoSkipWaves = true, uiScale = 85 }),
		true,
		"ok"
	)
	expectEq(
		snap(p.Settings),
		snap({ shadows = false, effectsQuality = "Low", autoSkipWaves = true, uiScale = 85 }),
		"stored"
	)
	expectEq(Settings.Merge(p, { uiScale = 90 }), true, "second patch")
	expectEq(p.Settings.uiScale, 90, "overwritten")
	expectEq(p.Settings.shadows, false, "keys not in the patch kept")
end)

test("Merge drops unknown keys, wrong types, non-finite numbers and oversized strings", function()
	local p = fresh()
	Settings.Merge(p, { shadows = false })
	local before = snap(p.Settings)
	local bad = {
		{ nope = true },
		{ Shadows = true },
		{ shadows = 1 },
		{ shadows = "true" },
		{ uiScale = "80" },
		{ uiScale = true },
		{ uiScale = NAN },
		{ uiScale = INF },
		{ uiScale = -INF },
		{ effectsQuality = true },
		{ effectsQuality = ("H"):rep(33) },
		{ language = ("x"):rep(4096) },
		{ effectsQuality = "Ultra" },
		{ effectsQuality = "high" },
		{ language = "French" },
		{ language = "" },
	}
	for i, patch in bad do
		expectEq(Settings.Merge(p, patch), true, "soft: still ok " .. i)
		expectEq(snap(p.Settings), before, "nothing written " .. i)
	end
	for id in p.Settings do
		expect(SettingsDefs.ById[id] ~= nil, "only registry keys stored: " .. tostring(id))
	end
end)

test("Merge snaps and clamps sliders like the client store", function()
	local p = fresh()
	local cases = {
		{ "uiScale", 73, 75 },
		{ "uiScale", 72, 70 },
		{ "uiScale", 200, 100 },
		{ "uiScale", 10, 70 },
		{ "uiScale", 1e300, 100 },
		{ "uiScale", -1e300, 70 },
		{ "effectScale", 27.4, 25 },
		{ "masterVolume", -5, 0 },
		{ "masterVolume", 33.3, 35 },
		{ "sfxVolume", 101, 100 },
	}
	for _, c in cases do
		Settings.Merge(p, { [c[1]] = c[2] })
		expectEq(p.Settings[c[1]], c[3], c[1] .. " " .. tostring(c[2]))
		expect(SettingsLogic.set(c[1], c[2]) and SettingsLogic.get(c[1]) == c[3], c[1] .. " matches the client store")
	end
	SettingsLogic.resetAll()
end)

test("Merge reads only registry keys: a mixed patch keeps the good entries", function()
	local p = fresh()
	Settings.Merge(p, { shadows = false, nope = 5, uiScale = NAN, effectsQuality = "Medium", language = "Klingon" })
	expectEq(snap(p.Settings), snap({ shadows = false, effectsQuality = "Medium" }), "good entries only")
end)
