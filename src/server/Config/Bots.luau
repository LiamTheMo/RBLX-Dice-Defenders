-- Duel bot tuning (docs/DICE_RATING.md section 9 item 2). Everything here is *tuned*; Rules/Bot reads it.
-- Rank index matches Config/Rating.Ranks: 1 Bronze, 2 Silver, 3 Gold.
--
-- Deck recipes (all dice distinct, ids drawn from Config/Dice by rarity):
--   Bronze: five Commons. Silver: Rare count in RareMin..RareMax, the rest Common.
--   Gold: five Rares where EpicMin..EpicMax of them are replaced by Epics.
-- Skill knobs:
--   ReactionMin/Max   seconds between two actions (the bot acts at most once per delay)
--   MaxPerSecond      hard cap on performed intents per rolling second (a human cannot tap faster)
--   MergeEagerness    chance a legal merge is taken when the bot is free to choose (always taken on a crowded board)
--   HighPipBias       chance the merge picks the highest-pip pair instead of the lowest
--   PowerUpEagerness  chance per opportunity to buy a Power Up when MP is spare (0 = never)
--   PowerUpMinDice    dice that must be on the board before the bot saves MP for Power Ups
--   MistakeChance     chance an action turn is wasted (the bot hesitates for a double delay)
local function rank(settings)
	return table.freeze(settings)
end

return table.freeze({
	-- Display names (Roblox-style).
	Names = table.freeze({
		"xX_Dicer_Xx",
		"RollMaster2009",
		"NoobSlayer_77",
		"CoolKid_Bloxy",
		"LuckyRoll_YT",
		"PixelPanda88",
		"SpeedyGonzalo",
		"ItsMeMarcus_",
		"DragonTamer_X",
		"Crit_Queen",
		"TheRealBlox42",
		"AlphaWolf_Rblx",
		"Snipe_God_99",
		"MegaMerger",
		"SilentNinja_01",
		"BananaBandit",
		"OofMaster_3000",
		"JadenPlaysRBX",
		"StarForge_Ava",
		"GoldenGamer_22",
		"TurboTurtle",
		"EpicEmma_x",
		"QuickMergeKing",
		"DiceLord_Kai",
	}),

	Ranks = table.freeze({
		rank({
			Name = "Bronze",
			DR = table.freeze({ Min = 0, Max = 299 }),
			Commons = 5,
			ReactionMin = 1.8,
			ReactionMax = 3.6,
			MaxPerSecond = 1,
			MergeEagerness = 0.35,
			HighPipBias = 0.1,
			PowerUpEagerness = 0,
			PowerUpMinDice = 15,
			MistakeChance = 0.25,
		}),
		rank({
			Name = "Silver",
			DR = table.freeze({ Min = 300, Max = 699 }),
			RareMin = 3,
			RareMax = 4,
			ReactionMin = 1.0,
			ReactionMax = 2.0,
			MaxPerSecond = 2,
			MergeEagerness = 0.7,
			HighPipBias = 0.25,
			PowerUpEagerness = 0.35,
			PowerUpMinDice = 11,
			MistakeChance = 0.1,
		}),
		rank({
			Name = "Gold",
			DR = table.freeze({ Min = 700, Max = 1100 }),
			EpicMin = 1,
			EpicMax = 2,
			ReactionMin = 0.5,
			ReactionMax = 1.1,
			MaxPerSecond = 3,
			MergeEagerness = 0.95,
			HighPipBias = 0.4,
			PowerUpEagerness = 0.7,
			PowerUpMinDice = 8,
			MistakeChance = 0.03,
		}),
	}),
})
