# Future updates

**Everything in this file is Proposed.** Nothing here is built unless a line says so. Update numbers are content milestones, not release dates, and the version names are candidates only. Version branches are permanent `vX.XX` (the current one is v0.06); `main` is the only production branch. What exists today is described in [GDD.md](GDD.md).

## Commitments for any update

- Each major update adds at least one new strategy, not only bigger numbers.
- New dice and UI follow [ART_PIPELINE.md](ART_PIPELINE.md).
- Every new Mythic or Secret die is earnable; nothing is purchase-only and Robux never buys a stat advantage.
- Each update ends with a balance review, a mobile performance check and updated docs.

## Already built (removed from this roadmap)

- 1v1 ranked Duel with Dice Rating, rank-based cross-server matchmaking, bots, surrender and rewards ([DICE_RATING.md](DICE_RATING.md)). Still open from the original PvP idea: 2v2, a pressure meter to send mobs to the opponent, and ranks above Gold.
- Two-player Co-op, the Roll and Shop menus, Quests, login calendar, milestones, achievements, mastery, redeem codes and the VIP pass.
- Three bosses with abilities (Goblin King, Cursed King, Court Jester) and the Random Dice enemy HP model.

## Candidate order

| # | Candidate | Headline | Content |
|---|---|---|---|
| 1 | v1.10 | Shattered Isles | World 2, special dice, new mutators |
| 2 | v1.20 | Treasure Defense | Vault-defence mode with Secure or Greed choices |
| 3 | v1.30 | Duel expansion | 2v2, mob sending, higher ranks, seasons |
| 4 | v1.40 | Guilds and Raids | Four-player raid bosses |
| 5 | v1.50 | Starfall Ascension | Dice mastery sidegrades, more dice |
| 6 | v1.60 | Corrupted Depths | World 3, weekly challenge mutators |
| 7 | v1.70 | Season of Secrets | A first obtainable Secret die beyond Dragon's roll odds |
| 8 | v2.00 | Grand Dice Update | Multi-world finale, accessibility and economy audit |

Updates 4 to 8 are flexible; check retention and fairness before locking any of them.

## Update 1: Shattered Isles

World 2 (floating islands, storm bridges), unlocked by clearing World 1. It needs a staged win condition first, because World 1 is endless today. Ideas: 100 staged waves with a boss every 10, a Storm Shards material, mutators (Gust speed bursts, Static arcs, Fractured Lanes with branch paths), a world HP modifier of about 1.6, and a Tempest Leviathan final boss.

Special dice (a mechanic tag, not a rarity): Gale (Rare), Stormcall (Epic, column lightning), Swap (Epic, swaps low-pip dice on merge), Anchor (Legendary, boss-displacement counter), Tempest (Legendary, a 7-pip storm zone). Deliverables: map, mobs and boss references, five dice with art and breakdown sheets, material tables, tutorials. Acceptance: World 2 clearable without the new Legendary, all procs work solo and duo, no paywall.

## Update 2: Treasure Defense

A 30-wave solo or duo mode with the normal 5 x 3 boards. A shared vault holds 1000 Vault Treasure (match-only, never wallet currency). Escaping enemies steal treasure instead of costing lives; zero treasure is defeat, clearing wave 30 with treasure left is a win. Bosses at waves 10, 20, 30.

- Enemies and theft per breach: Thief 15, Treasure Goblin 25 (killing it restores a little treasure once), Armored Bandit 60, Mimic 40 total (splits into two pieces that steal 20 each), Vaultbreaker boss 150.
- Vault Greed: after waves 5, 10, 15, 20 and 25 players pick Secure or Greed for the next five waves. Greed adds 20% enemy threat budget for that block and raises the reward factor by 0.15, with `G = min(1 + 0.15 x blocks, 1.75)`. In duo a 10 s vote decides and Secure wins ties.
- Rewards: `Gold = floor(BaseGold x (0.25 + 0.75 x waves/30) x (0.2 + 0.8 x vault/1000) x G)`, granted by one server-validated reward transaction, with partial-run caps against early-fail farming.
- Leaderboards: weekly solo and duo, ranked by wave 30 clear, then vault left, then Greed blocks, then time.

Production scope: one vault map, 30 wave definitions, five theft enemies, three boss variants, Secure/Greed voting, a reward ledger, weekly leaderboards and a tutorial.

## Update 3: Duel expansion

Open ideas beyond today's Duel: 2v2 with shared team lives; a pressure meter that lets a player send a visible, capped mob packet to the opponent; ranks above Gold (Platinum, Diamond, Master, Champion); seasons with an archived reset; cosmetic-only seasonal rewards. Rules for any of these: no paid sabotage, normalised levels in ranked, anti-collusion and anti-forfeit-farming checks.

## Updates 4 to 8 in brief

- **4 Guilds and Raids:** four-player raid boss with role-based phases, guild projects for non-combat rewards, a weekly clean-clear leaderboard.
- **5 Starfall Ascension:** Dice Mastery sidegrades (alternate versions of a die, not flat buffs), three to five more dice, new 7-pip visual effects.
- **6 Corrupted Depths:** World 3, cavern branches, weekly challenge mutators (No Slows, Limited Merges, Shield Flood, Unstable Board) with their own leaderboards.
- **7 Season of Secrets:** more Secret dice with a quest route and a free alternative, seasonal collection events.
- **8 Grand Dice Update:** a multi-world boss gauntlet, accessibility and performance passes, a full economy and ranking audit.

## Open decisions

- Whether World 2 launches with five special dice or three plus two from events.
- Whether Treasure Defense unlocks at wave 30 of World 1 or after a first clear.
- How seasons reset rank without punishing inactive players.
- Whether four-player raids hold frame rate on low-end phones.
- Whether die levels should add a damage bonus (today they give only account crit damage). Owner decision pending.
- How stronger decks get past about wave 25 (boss HP grows linearly with the wave); revisit when die levels or abilities add power.
- Rare, Epic and Legendary ability designs (see Proposed in [DICE_CATALOG.md](DICE_CATALOG.md)) and a replacement perk for Longshot.

## Release checklist for each update

1. Update the GDD, dice config, balance config and any mode spec before building.
2. Produce every required art asset and dice breakdown sheet; verify completeness.
3. Audit server authority, ledgers, data migrations, roll odds, ranked integrity and performance.
4. Run the headless specs (`python tests/luau/run.py`) and the balance simulator; playtest solo and two-player.
5. Check client UX on desktop and small landscape phones, and low-end performance.
6. Check current Roblox rules for paid random items before changing any paid roll.
7. Build on the next `vX.XX` branch; finished changes merge into `main`, the only production branch.
