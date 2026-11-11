-- CLIENT-ONLY SAMPLE DATA: display placeholders for features the server does not have yet (gem rewards, weekly quests, achievements, mastery). Delete when real data exists. Never sent to the server.

local function quest(id, section, name, desc, progress, goal, gold, gems, icon)
	return {
		Id = "sample_" .. id,
		Section = section,
		Name = name,
		Desc = desc,
		Progress = progress,
		Goal = goal,
		Gold = gold,
		Gems = gems,
		Icon = icon,
		Claimed = false,
		Sample = true,
	}
end

local function reward(name, amount)
	return { Name = name, Amount = amount }
end

local function ach(id, name, desc, progress, goal, badge, rewards, unit, locked)
	return {
		Id = "sample_" .. id,
		Name = name,
		Desc = desc,
		Progress = progress,
		Goal = goal,
		Unit = unit,
		Locked = locked,
		Badge = badge,
		BadgeBig = badge .. "Big",
		Rewards = rewards,
		Sample = true,
	}
end

local function mastery(name, level, xp, xpGoal, element)
	return {
		Id = "sample_" .. element,
		Name = name,
		Desc = "Increase the power of " .. name .. " to unlock exclusive rewards!",
		Level = level,
		Xp = xp,
		XpGoal = xpGoal,
		Die = "Die" .. element,
		Skin = "Skin" .. element,
		Milestones = {
			{ Lv = 5, Icon = "Crystals", Name = "Crystals" },
			{ Lv = 10, Icon = "Potion", Name = "Potion" },
			{ Lv = 15, Icon = "Skin" .. element, Name = "Dice Skin" },
			{ Lv = 20, Icon = "Crown", Name = "Mastery Crown" },
		},
		Sample = true,
	}
end

local SampleData = {}

SampleData.Quests = {
	quest("roll", "Daily", "Roll Dice", "Roll 50 times", 50, 50, 500, 25, "IconDie"),
	quest("collect", "Daily", "Collect Materials", "Collect 200 materials", 132, 200, 300, 15, "IconCrystals"),
	quest("chests", "Daily", "Open Chests", "Open 10 chests", 7, 10, 400, 20, "IconChest"),
	quest("dailies", "Weekly", "Complete Daily Quests", "Finish 15 daily quests", 6, 15, 2500, 150, "IconCrown"),
	quest("craft", "Weekly", "Craft Dice", "Craft 5 dice", 2, 5, 1500, 100, "IconGalaxyDie"),
	quest("towers", "Weekly", "Play Towers", "Clear 20 tower stages", 8, 20, 2000, 125, "IconWings"),
}

SampleData.Achievements = {
	ach(
		"king",
		"Dice King",
		"Reach Level 10 and prove yourself as a true Dice King of the Dice Kingdom.",
		10,
		10,
		"BadgeKing",
		{ reward("Crystals", 500), reward("Die", 1) },
		"LVL"
	),
	ach(
		"royal",
		"Royal Collector",
		"Collect every royal die in the kingdom.",
		5,
		5,
		"BadgeRoyal",
		{ reward("Crystals", 300) }
	),
	ach(
		"material",
		"Material Master",
		"Gather 1,000 crafting materials.",
		1000,
		1000,
		"BadgeMaterial",
		{ reward("Crystals", 250) }
	),
	ach(
		"hoarder",
		"Item Hoarder",
		"Hold 10 different items in your bag.",
		8,
		10,
		"BadgeHoarder",
		{ reward("Crystals", 200) }
	),
	ach("crafter", "Dice Crafter", "Craft 50 dice at the forge.", 42, 50, "BadgeCrafter", { reward("Crystals", 350) }),
	ach("tower", "Tower Builder", "Clear 20 tower stages.", 12, 20, "BadgeTower", { reward("Crystals", 400) }),
	ach("battle", "Battle Victor", "Win 50 battles.", 25, 50, "BadgeBattle", { reward("Crystals", 450) }),
	ach("xp", "XP Champion", "Reach Level 20.", 12, 20, "BadgeXp", { reward("Crystals", 500) }, "LVL"),
	ach(
		"treasure",
		"Treasure Hunter",
		"Open 25 treasure chests.",
		18,
		25,
		"BadgeTreasure",
		{ reward("Crystals", 300) }
	),
	ach("rift", "Rift Explorer", "Explore 10 rifts.", 3, 10, "BadgeRift", { reward("Crystals", 600) }),
	ach(
		"galaxy",
		"Galaxy Master",
		"Roll your first Galaxy die.",
		0,
		1,
		"BadgeGalaxyLocked",
		{ reward("Crystals", 800) },
		nil,
		true
	),
	ach(
		"divine",
		"Divine Collector",
		"Collect a Divine die.",
		0,
		1,
		"BadgeDivineLocked",
		{ reward("Crystals", 900) },
		nil,
		true
	),
	ach(
		"mythic",
		"Mythic Hunter",
		"Defeat a Mythic enemy.",
		0,
		1,
		"BadgeMythicLocked",
		{ reward("Crystals", 1000) },
		nil,
		true
	),
	ach(
		"kingdom",
		"Kingdom Legend",
		"Finish every kingdom quest.",
		0,
		1,
		"BadgeKingdomLocked",
		{ reward("Crystals", 1200) },
		nil,
		true
	),
	ach(
		"true",
		"True Master",
		"Complete every other achievement.",
		0,
		1,
		"BadgeTrueLocked",
		{ reward("Crystals", 2000) },
		nil,
		true
	),
}

SampleData.Mastery = {
	mastery("Fire Dice", 12, 6540, 8000, "Fire"),
	mastery("Ice Dice", 10, 4200, 6000, "Ice"),
	mastery("Leaf Dice", 9, 3540, 5000, "Leaf"),
	mastery("Lightning Dice", 8, 2640, 4000, "Lightning"),
	mastery("Sun Dice", 7, 1980, 4000, "Sun"),
}

return SampleData
