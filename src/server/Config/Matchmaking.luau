-- Duel matchmaking tuning (docs/DICE_RATING.md section 9). All values are tuned.
return table.freeze({
	MaxRankGap = 1, -- max |rank index difference| between two humans
	BotAfterSeconds = 12, -- wait before the player gets a bot in the same server
	BotGoldFactor = 0.5, -- gold multiplier for a bot match
	CooldownSeconds = 600, -- the same two humans are not paired again within this
	RecentMax = 10, -- profile.Rating.Recent length
	TicketTtlSeconds = 60, -- queue entry lifetime in the sorted map
	MatchTtlSeconds = 90, -- match ticket lifetime
	PollSeconds = 2, -- how often a server polls the queue / its match ticket
	SecondPlayerTimeoutSeconds = 45, -- the reserved server waits this long for the second player
})
