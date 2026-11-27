# 1v1 Duel and Dice Rating (DR)

How the ranked 1v1 mode works as built. Numbers are in `src/server/Config/Balance.luau` (`Duel`, `DuelReward`), `Config/Rating.luau`, `Config/Matchmaking.luau` and `Config/Bots.luau`; all are tuned values unless marked as the owner's Random Dice spec. This file replaces the old DUEL_SCALING.md (kept in [_archive/](_archive/DUEL_SCALING.md)).

Source for the Random Dice shape: NamuWiki "Random Dice: PvP Defense". It publishes the boss rule, the round timer, the death and berserk phases and the win-streak shape. It does not publish base trophies, class thresholds, the class-gap formula, season reset or matchmaking; those values here are our own.

## 1. Match rules (`Rules/Match.luau`, mode "Duel")

- Two seats, each with its own lane, lives (3), MP, board and deck. Both lanes get the same waves. A die only targets its own lane. The opponent's board stays visible.
- Mobs: 10 per wave from the Co-op HP model ([WAVE_SCALING.md](WAVE_SCALING.md)), no boss or mini-boss in the queue. Runners (half HP, speed 9) grow with the wave, `min(5, wave // 3)`.
- Boss: each wave ends with one boss per lane once the 10 mobs have spawned and the round timer has run out, or earlier when both lanes are clear. Boss HP = 40000 x wave + 0.5 x the lane's remaining mob HP (the boss absorbs those mobs). Boss counts as a Boss (2 lives).
- Round timer: 90 s, 10 s shorter each wave, floor 40 s.
- Death wave (from wave 7): mobs get +8% HP and +3% speed per wave from then on. This is the game's own tuning, not the spec's.
- Berserk (from wave 11): kills pay a fixed 110 SP and the boss moves x1.25.
- SP (MP) per kill: `min(110, 10 x wave)`; a boss pays 2 x that (up to 220). Summon cost is the same as Solo (10, 20, 30 ...).
- Normalised combat: die-level crit bonus is 0 for both seats. Deck, dice and pips are real.
- Ending: a seat at 0 lives loses. If both hit 0 in the same step the seat with more kills wins, then a seeded coin flip decides. There is no wave cap and no draw. `Surrender` or leaving the server is a forfeit.
- Result: `state.result = "Duel"` with `state.duel = { Winner, Why = "Lives" | "Tiebreak" | "Forfeit" | "Surrender", Lives, Kills }`.
- Return home: the server sends players back `DUEL_RETURN_SECONDS` (3 s) after the end, with the result in TeleportData (`Rules/ResultCarry`); the lobby validates it and shows it once.

Not built from the Random Dice PvP spec (**Proposed**): Random Missions on even waves from 4, a random boss type with abilities, sending mobs to the opponent, boss skill cooldown reduction in the death wave, the berserk boss-ability set, and the researched mob HP table (the spec's mob HP is not published).

Bot-vs-bot simulation: Bronze, Silver and Gold mirror matches end at about wave 11 to 13, 6 to 7 minutes (older measurement, not re-run since the current balance changes).

## 2. Dice Rating (`Rules/Rating.luau`)

| Rank | DR range |
|---|---|
| Bronze | 0-299 |
| Silver | 300-699 |
| Gold | 700+ (DR keeps counting; no rank 4) |

DR starts at 0 and never goes below 0. There is no rank-down protection.

Per finished Duel, with `gap = opponent rank index - my rank index`:
- Win: 30 + 3 x gap (base part clamped to 15..45), plus a streak bonus.
- Loss: -20 + 3 x gap, clamped to -35..-5.
- Streak: after a win the streak is `n`; the bonus is 2 x (n - 1) DR with n capped at 10 (1 x (n - 1) in Gold). Any loss, including a forfeit or disconnect, resets it to 0.
- Gold on a win: 100 x min(n, 10).
- Early forfeit: if a player forfeits before 3 cleared waves (`MinWavesForRewards`) they take a normal loss; the opponent gets no DR, streak, wins or Gold (result is a Win with delta 0, Why "EarlyForfeit"; `Rules/DuelSettle`).
- An aborted or errored match changes nothing. Rewards and DR apply once per match (`Rating.LastDuelRunId`).
- XP and Gems (`Balance.DuelReward`): per cleared wave, counting at most 20, the winner gets the Solo XP and Gems; the loser gets 40% of the XP and no Gems; a bot match halves both. Gold stays the streak Gold; bot matches multiply it by 0.5 (`Matchmaking.BotGoldFactor`).

Profile data: `profile.Rating = { DR, Streak, BestStreak, Wins, Losses, Draws (legacy, never incremented), LastDuelRunId, Recent }`.

## 3. Matchmaking (`Rules/Matchmaker`, `DuelQueue`, `DuelRoom`, `Services/QueueService`)

- "Find match" calls `QueueDuel(seq, on)`. A player may face an opponent at most 1 rank away. The same two humans are not paired again within 600 s (`Recent`, last 10); admins ignore this.
- Cross-server: waiting tickets sit in a MemoryStore sorted map (60 s lifetime); the server that finds a pair reserves a private server and teleports both players. The Duel server waits up to 45 s for the second player, then aborts with no DR change.
- Bots: with no human after 12 s the player gets a bot in the same server. Bronze bots use five Commons, Silver 3-4 Rares plus Commons, Gold five Rares with 1-2 replaced by Epics. Bot skill (reaction delay, merge eagerness, Power Up use, mistakes) scales by rank (`Config/Bots`). The UI shows a BOT tag; DR applies normally.
- Teleport and MemoryStore sit behind gateways with in-memory fakes, so the matchmaker is tested headless. Studio cannot test teleports.
- Remotes: `QueueDuel(seq, on)`, `Surrender(seq)`, `LeaveDuel(seq)`. Snapshot fields: `CanQueue`, `QueueState` (nil, "Searching", "Matched"), `QueueSince`, `QueueBotAfter`, `CanSurrender`, `InDuelServer`, `DuelWaiting`, `Opponent = { Name, DR, Rank, IsBot }`, and `DuelResult` at the end.

## 4. Arena

The Duel map has two boards, seat 1 north and seat 2 south, each with a U-shaped route. Route length is mapped to the 124-stud balance length like Solo and Co-op (`Layout.PathLength`). Each seat's camera puts its own board at the bottom of the screen. Geometry authority is the model in Studio.
