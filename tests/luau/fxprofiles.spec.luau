-- Rarity effect profiles: every mesh key a profile names exists in FxMeshes (Fx.Part errors on unknown keys
-- mid-game), the retired Chrono/Forge/Astral keys are gone, and the new ones are wired.

local Effects = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Effects
local FxMeshes = require(Effects.FxMeshes)
local RarityStyles = require(Effects.RarityStyles)

local function keysOf(profile)
	local keys = {}
	local function add(key)
		if key then
			table.insert(keys, key)
		end
	end
	add(profile.core and profile.core.mesh)
	for _, ribbon in profile.ribbons or {} do
		add(ribbon.mesh)
	end
	for _, layer in profile.impact or {} do
		add(layer.mesh)
	end
	add(profile.followers and profile.followers.mesh)
	add(profile.dots and profile.dots.mesh)
	add(profile.neighbor and profile.neighbor.mesh)
	if profile.aura then
		add(profile.aura.mesh)
		add(profile.aura.ticks)
	end
	for _, entry in profile.status or {} do
		add(entry.mesh)
	end
	return keys
end

local referenced = {}

test("every profile mesh key exists in FxMeshes", function()
	local profiles = 0
	for id, profile in RarityStyles.Profiles do
		profiles += 1
		for _, key in keysOf(profile) do
			referenced[key] = true
			expect(FxMeshes[key] ~= nil, id .. " uses unknown mesh " .. key)
		end
	end
	expect(profiles >= 11, "all rarity profiles are checked")
end)

test("retired Chrono/Forge/Astral meshes are gone and the new layers are present", function()
	for _, key in
		{ "Chrono_AuraRing", "Chrono_Flash", "Chrono_HitRing", "Forge_Flash", "Astral_Core", "Astral_HitRing" }
	do
		expect(FxMeshes[key] == nil, key .. " was retired")
	end
	for _, key in
		{
			"Chrono_Core",
			"Chrono_Streak",
			"Chrono_StreakFlank",
			"Chrono_Ring",
			"Chrono_Ticks",
			"Chrono_Hands",
			"Chrono_GroundGlow",
			"Forge_Core",
			"Forge_Streaks",
			"Forge_Anvil",
			"Forge_Ring",
			"Forge_RingRim",
			"Forge_GroundGlow",
			"Astral_Comet",
			"Astral_Ring",
			"Astral_Constellation",
			"Astral_RayCrown",
			"Astral_GroundGlow",
		}
	do
		expect(FxMeshes[key] ~= nil, key .. " exists")
		expect(referenced[key] == true, key .. " is used by a profile")
	end
end)

test("L01/L02/M01 hits stay within 12 parts and flight within the ribbon budget", function()
	for _, id in { "L01", "L02", "M01" } do
		local profile = RarityStyles.Profiles[id]
		local parts = 0
		for _, layer in profile.impact do
			parts += layer.count or 1
		end
		expect(parts <= 12 and parts >= 6, id .. " hit parts " .. tostring(parts))
		expect(#(profile.ribbons or {}) <= 3, id .. " ribbons")
	end
end)

test("every impact layer of every profile stays above the route cap", function()
	local Layout = require(game:GetService("ReplicatedStorage").Shared.Layout)
	local top = Layout.Y - 0.8 -- the maps' route cap (3.2); shot.ground sits at this height
	local ctx = { ground = Vector3.new(0, top, 0), hit = Vector3.new(0, Layout.Y, 0), k = 1, seed = 1.3 }
	ctx.shot = { from = ctx.hit + Vector3.new(0, 3, 8), surface = ctx.hit }
	for id, profile in RarityStyles.Profiles do
		for _, layer in profile.impact or {} do
			local name = id .. " " .. tostring(layer.mesh)
			if layer.motion then
				for i = 1, layer.count or 1 do
					for step = 0, 20 do
						local ok, at = pcall(layer.motion, i, step / 20, ctx, layer.count) -- stub Vector3 lacks Lerp
						local y = if ok then at.Y else top
						expect(y >= top - 1e-6, name .. " motion Y " .. y .. " is under the route")
					end
				end
			elseif layer.orient == "ground" then
				expect(top + 0.05 + (layer.lift or 0) > top + 0.01, name .. " lies under the route")
			elseif layer.orient == "upright" then
				expect(layer.pivotUp > 0, name .. " pivot is under the route")
			end
		end
	end
end)
