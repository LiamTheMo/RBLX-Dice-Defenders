--!strict
-- CLIENT-ONLY SAMPLE DATA: display only. The server grants none of this; nothing here touches state or remotes.
-- Live players get `live` (no reward amounts or odds); Studio gets the full reference sample.

local function world(id: string, name: string, art: string)
	return { Id = id, Name = name, Art = art, Waves = 100, Locked = true }
end

local function ms(wave: number, icon: string, lines: { string })
	return { Wave = wave, Icon = icon, Lines = lines }
end

local Worlds = {
	world("FrostPeaks", "FROST PEAKS", "WorldFrost"),
	world("MagmaCitadel", "MAGMA CITADEL", "WorldMagma"),
	world("ShadowRealm", "SHADOW REALM", "WorldShadow"),
}

local Tiles = {
	{ Label = "MATERIALS", Icon = "IconCrystals" },
	{ Label = "ITEMS", Icon = "Potion" },
	{ Label = "COSMETICS", Icon = "Crown" },
	{ Label = "RARE DICE", Icon = "IconGalaxyDie" },
}

local full = {
	Worlds = Worlds,
	Tiles = Tiles,
	Milestones = {
		ms(10, "IconCrystals", { "+250", "CRYSTALS" }),
		ms(20, "Potion", { "+3", "LUCK POTIONS" }),
		ms(30, "IconChest", { "+1", "TREASURE CHEST" }),
		ms(40, "RewardBanner", { "+1", "EXCLUSIVE", "BANNER" }),
		ms(50, "IconGalaxyDie", { "+1", "RARE DIE" }),
		ms(100, "CrownGems", { "+1", "CROWN COSMETIC", "+5,000 GEMS" }),
	},
	Odds = {
		{ "WAVE 10:", "0.1%" },
		{ "WAVE 20:", "0.2%" },
		{ "WAVE 30:", "0.3%" },
		{ "+0.1%", "EVERY 10 WAVES" },
		{ "PER MILESTONE" },
	},
}

local liveMilestones = {}
for i, m in full.Milestones do
	liveMilestones[i] = ms(m.Wave, m.Icon, { "COMING", "SOON" })
end

local live = { Worlds = Worlds, Tiles = Tiles, Milestones = liveMilestones, Odds = { { "COMING SOON" } } }

return {
	full = full,
	live = live,
	get = function(isStudio: boolean)
		return if isStudio then full else live
	end,
}
