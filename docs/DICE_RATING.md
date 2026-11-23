# 1v1 Duel and Dice Rating (DR)

Binding design for the 1v1 mode ("Duel") and the ranked rating ("DR"). Written by the overseer; implementers follow it and
report deviations. Tuning values live in config, never inline.

## 1. Research: how Random Dice: PvP Defense ranks its 1v1 (what is verified)

Source: NamuWiki "Random Dice: PvP Defense" (read in full on 2026-11-23). The Fandom wiki has no trophy pages.

Verified from the source:
- 1v1 "Match mode": a win gives trophies, gold and gems; a loss gives nothing but a support-box ad. "Class" (rank) is set by trophy count.
- "Each time the class difference increases by 1, the range of trophy increases": the trophy gain depends on the class gap between the players (no formula is published).
- Win streak: "2 additional trophies per winning streak"; gold reward +100, rising with each streak step, capped at 10 consecutive wins. At the top class ("Golden") the streak is worth 1 trophy per consecutive win.
- A boosting ticket doubles trophies (class 11+). Not copied.
- Format: 3 hearts each; a boss or large monster costs 2 hearts, a normal monster 1; all hearts lost, 3 connection failures, or surrender = defeat. A boss ends every wave. Round time starts at 90 s and drops 10 s per round to a 40 s floor.

NOT published anywhere readable (do not claim them as the original's numbers): base win/loss trophies, class thresholds, the gap formula, season reset, draw handling, matchmaking, bots.
The values below that are not in the list above are **our tuning**, flagged `tuned`.

## 2. DR rules (server-authoritative, pure module `Rules/Rating.luau`)

> Superseded in part: Draw outcomes and the wave cap no longer exist; see section 9 (Duels end only at 0 lives, surrender or forfeit).

Ranks (only the first three exist for now; DR above Gold keeps counting, there is no rank 4):

| Rank | Index | DR range |
|---|---|---|
| Bronze | 1 | 0-299 (tuned; the "class 1 = 0-299" figure is an unverified fan note) |
| Silver | 2 | 300-699 (tuned) |
| Gold | 3 | 700+ (tuned) |

DR starts at 0 and never goes below 0. Rank = highest rank whose lower bound <= DR. No rank-down protection yet.

Per finished Duel (result for each player: Win, Loss, Draw), with `gap = opponentRankIndex - myRankIndex` (-2..2):
- Win: `base 30` `+ 3*gap` (clamped so the base part stays within 15..45), plus the streak bonus.
- Loss: `-20` `+ 3*gap` (a loss to a higher rank costs less, to a lower rank more; clamped to -35..-5).
- Draw: 0 DR, streak unchanged.
- Streak bonus (verified shape, tuned size): after a win the streak is `n` (the new count). Bonus = `2 * (n - 1)` DR, with `n` capped at 10 (max +18). In Gold the bonus is `1 * (n - 1)` (the "Golden class" rule).
- A loss (including a forfeit or disconnect mid-match) sets the streak to 0. A win by the opponent's forfeit counts as a normal win.
- Win-trading guard: a forfeit before `Balance.Duel.MinWavesForRewards` (3, tuned) waves are cleared still costs the leaver a normal Loss, but the opponent gets no DR, streak, win count or gold (the result shows Outcome "Win", DRDelta 0, Gold 0, Why = "EarlyForfeit"). Rule lives in `Rules/DuelSettle`. A server shutdown or error ends a Duel as Aborted (no DR for anyone).
- Gold reward on a win: `100 * min(n, 10)` (verified shape: +100 gold per streak step, cap 10 wins). A loss or draw pays 0 gold.
- Aborted or errored matches (server error, profile failure, shutdown) change nothing.
- Rewards and DR apply once per match: guard with the profile's `Rating.LastDuelRunId`.

All numbers come from `Config/Rating.luau` (Ranks, WinBase, LossBase, GapStep, StreakStep, TopRankStreakStep, StreakCap, WinGold, bounds).

## 3. Profile data (`ProfileSchema`, bump the schema version with a migration)

`profile.Rating = { DR = 0, Streak = 0, BestStreak = 0, Wins = 0, Losses = 0, Draws = 0, LastDuelRunId = 0 }`.
Migration fills it for old profiles; `Validate`/`Clean` rejects negative or non-integer values.

## 4. Duel match rules (`Rules/Match.luau`, mode "Duel")

> Superseded in part: Draw outcomes and the wave cap no longer exist; see section 9 (Duels end only at 0 lives, surrender or forfeit).

- `Match.New` gets an options table (or a new constructor `Match.NewDuel`) for two seats. `state.mode = "Duel"`, `state.playerCount = 2`. Solo (`mode "Solo"`) and Coop (`mode "Coop"`) behave exactly as today.
- Both seats get the **same enemy waves** (existing wave generator, same spawn times, one lane each). Each enemy belongs to its lane seat.
- **Own lives:** each seat has `lives = Balance.StartLives`. A breach costs only the lane owner `Enemies.Kinds[kind].lives`.
- **Own lane only:** a die targets only enemies of its own seat (no shared stretch; there is no junction).
- **Own MP:** kill MP goes only to the seat whose lane the enemy died on.
- **Normalized combat:** crit bonus from die levels is 0 for both seats in a Duel (fair ranked). Deck, dice and pips are real.
- **Ending (deterministic):** checked each Step after breaches. A seat at 0 lives loses. Both at 0 in the same step = Draw. Time/wave cap: when `wavesCompleted >= Balance.Duel.MaxWaves` (tuned 30) the higher lives wins; equal lives then more kills wins; still equal = Draw.
- **Forfeit:** `Match.Forfeit(state, seatIndex)`: that seat loses (opponent wins). A player leaving mid-Duel = forfeit.
- Result fields: `state.result` stays `"Lost" | "Aborted" | "Error"` for Solo/Coop. A Duel ends with `state.result = "Duel"` and `state.duel = { Winner = 1 | 2 | nil (draw), Why = "Lives" | "Cap" | "Forfeit" | "Draw", Lives = {n1, n2}, Kills = {k1, k2} }`.
- Outbox records (`S` spawn, `F` hit, `R` removal) carry the existing `Seat` and `PlayerCount` and a new `Arena = "Solo"|"Coop"|"Duel"` (the layout key, see section 5).

## 5. Layout / map

- Layout functions that take `playerCount` also accept an arena key: `1`/`2` (legacy numbers = Solo/Coop) or `"Solo"|"Coop"|"Duel"`. Clients read `record.Arena or record.PlayerCount`.
- Duel arena = the OneVOne map (`ReplicatedStorage.Maps.Duel`, moved from `ServerStorage.OneVOne`, its portals deleted, the same way Solo/Coop were prepared). Two boards: seat 1 north (z negative), seat 2 south, divider between; each seat has its own U-shaped route that runs down its west side, across the bottom (next to the divider) and up its east side. Authoritative geometry = the model in Studio; first-cut numbers: seat 1 route A(-18.65,-20.55) -> B(-18.65,-2.9) -> C(18.65,-2.9) -> D(18.65,-20.55), seat 2 the mirror in z; pads as in Coop (rows -20.5/-14.5/-8.5 and 8.5/14.5/20.5). Verify against the model.
- Route length is mapped to the 124-stud balance length exactly like Solo and Coop (`PositionAt` scaling; `Layout.PathLength` stays 124). Arena X origin 1000 like the others (streaming radius).
- Cameras: per seat, so a player's own board is at the bottom of the screen. Seat 2 uses a camera on the +z side looking toward -z (like Coop); seat 1 uses a camera on the -z side looking toward +z. Both frame both boards (phones 844x390).

## 6. Pairing (this version)

Server-local, like Co-op: the first two loaded players can both tap "1v1 Ranked"; the Duel starts when both are ready. No cross-server queue, no bots, no DR-based matchmaking yet (future: MemoryStoreService queue). A one-player server shows the button disabled ("Needs an opponent"). Mixed readiness (one Coop, one Duel) just waits.
Both players must pass `Tutorial.CanStart` and `Deck.IsReady`.

## 7. Contracts between modules

Remote (add to `Shared/Net/Remotes.luau`, `NetClient` rate limit, `Lobby` toast names): `DuelReady = "Function", -- (seq, ready)` returning `(ok, code)` with codes `NeedPartner`, `FinishStarterRolls`, `BadDeck`, `PartnerDeck`, `WrongPhase`, `NotLoaded`.

Snapshot (`State` push) new fields:
- Lobby: `CanDuel: boolean` (two players present and this player is one of them), `DuelReady: boolean`, `Rating = { DR, Rank, RankIndex, NextRankAt (number or nil at Gold), Streak, BestStreak, Wins, Losses, Draws }`.
- Playing/Ended in a Duel: `Mode = "Duel"` (Solo and Coop send `"Solo"`/`"Coop"`), `Lives` = my lives, `OpponentLives`, `Opponent = { Name, DR, Rank }`.
- Ended Duel: `DuelResult = { Outcome = "Win"|"Loss"|"Draw", Why, DRBefore, DRAfter, DRDelta, StreakBonus, Streak, RankBefore, RankAfter, Gold }`.
Meta push: `Rating` as above.

## 8. File ownership (one agent per file, no overlaps)

| Agent | Files |
|---|---|
| Rating core | `Config/Rating.luau`, `Rules/Rating.luau`, `Rules/ProfileSchema.luau`, `tests/luau/rating.spec.luau`, schema tests |
| Duel rules | `Rules/Match.luau`, `Config/Balance.luau` (Duel table only), `tests/luau/duel.spec.luau`, `tools/balance_sim.luau` only if needed |
| Layout + arena | `Shared/Layout.luau`, `BoardView`, `CameraController`, `EnemyView`, `Effects/CommonProjectiles` + `RarityEffects` call sites (arena key), the Studio map move |
| Service | `Services/MatchService.luau`, `Shared/Net/Remotes.luau`, `NetClient.luau` (rate limit entry) |
| Client UI | `Controllers/Play/*`, `Hud.luau`, `HudLogic.luau`, `Lobby.luau`, new Duel result view |

Rules: Sonnet/Haiku subagents only. No commits, no pushes, no AI names in any git artifact. Do not touch the owner's other uncommitted files (`Dice/*ModelData.luau`, `Visuals.luau`, `UiSounds.luau`, `tools/build_common_variants.py`, `tools/make_ui_sounds.py`). StyLua binary: `C:\Users\asus\.aftman\tool-storage\JohnnyMorganz\StyLua\2.6.0\StyLua.exe`; selene per `selene.toml`; tests `python tests\luau\run.py` (known unrelated failures: baglogic, claims, profile_schema). Studio: the open place is the owner's main place: edits there are allowed only where the task says so, never save/publish. 3D captures render black on this machine: do not rely on screenshots.

---

## 9. Revision 2 (owner decisions, 2026-11-23). This section overrides sections 4 and 6 where they differ.

1. **Cross-server queue.** Players press "Find match" (replaces the local ready-up). Matching is by rank: a player can be matched with an opponent whose rank index differs by at most 1 (Bronze with Bronze/Silver, Silver with any, Gold with Silver/Gold). Cross-server via MemoryStoreService (sorted map of waiting tickets, entries expire); the server that finds a compatible pair reserves a private server (TeleportService:ReserveServer), writes a match ticket for both users, and each player's own server teleports its own player. The reserved server detects its role from TeleportData (`Mode = "Duel"`, match id, the two user ids with their pre-match DR and rank, optional bot) and auto-starts the Duel when both players are loaded (timeout 45 s waiting for the second player: abort, no DR change, return to the lobby server). After a Duel the players can return to the lobby (teleport to the public place).
2. **Bots.** If no human opponent is found within `Matchmaking.BotAfterSeconds` (tuned 12 s) the player is paired with a bot **in the same server** (no teleport). Bots exist for every rank with a randomized deck (all dice must be valid deck dice from `Config/Dice`):
   - Bronze bots: five random **Common** dice.
   - Silver bots: majority **Rare** with some Commons (3 or 4 Rare, rest Common).
   - Gold bots: all **Rare**, with 1 or 2 **Epic** replacing Rares.
   The bot's rank = the human's rank (or +-1 at random, like a human could be); the bot has a display name from a pool and a DR sampled inside that rank's range. The bot plays seat 2 through the normal Match intents (summon, merge, power up) with a human-like delay and rank-scaled skill. `Opponent.IsBot = true` is sent in the snapshot and the UI shows a small BOT tag. Bot matches apply DR normally; gold is multiplied by `Matchmaking.BotGoldFactor` (tuned 0.5); bot matches never create opponent cooldowns.
3. **Per-opponent cooldown.** The profile keeps the last matches (`Rating.Recent = { {UserId, At} ... }`, max 10). The matchmaker never pairs two players who fought each other within `Matchmaking.CooldownSeconds` (tuned 600). Admins (`Rules/Admin.IsAllowed(userId)`) ignore the cooldown.
4. **No draws; only surrenders.** A Duel has no wave cap and no draw. It ends when a seat reaches 0 lives or a player surrenders. If both reach 0 lives in the same Step the winner is the seat with more kills, then (still equal) a seeded coin flip from the match Random. `Outcome` is only Win or Loss; remove the Draw and wave-cap paths from Match and the result UI (keep profile `Draws` field for compatibility, never incremented). New `Surrender` remote (Duel only, confirm dialog in the UI) = `Match.Forfeit`; leaving the server is also a forfeit; the early-forfeit rule (before `MinWavesForRewards` waves) still applies.
5. **Visible boards.** The opponent's board (dice and pips) stays visible, bots included. Already implemented through `PartnerBoard`.
6. Studio cannot test teleports: build MemoryStore and Teleport behind gateways with in-memory fakes (like `DataStoreGateway`/`InMemoryDataStore`) and test the pure matchmaker headless.

### Section 9 addendum: final contracts (as built)
- Remotes: `QueueDuel(seq, on)`, `Surrender(seq)`, `LeaveDuel(seq)` replace `DuelReady`. Snapshot: `CanQueue`, `QueueState` (nil|"Searching"|"Matched"), `QueueSince`, `QueueBotAfter`, `CanSurrender`, `InDuelServer`, `DuelWaiting`, `Opponent.IsBot`; `CanDuel`/`DuelReady` no longer exist. Section 7's DuelReady/CanDuel text is superseded.
- Every Duel (human vs human, human vs bot) runs in a reserved server. In Studio, or when MemoryStore/teleport is unavailable, a bot Duel runs in the same server instead.
- `MemoryStoreGateway:Claim` swaps the entry for a `__claimed` marker then removes it (an UpdateAsync transform returning nil cancels the update, it does not delete).
