# Dice Defenders: design document

The code under `src/` is the source of truth. This file describes what is built; anything not built is marked **Proposed** and listed again in [FUTURE_UPDATES.md](FUTURE_UPDATES.md). The older MVP build contract is kept in [_archive/MVP.md](_archive/MVP.md) for history only (profile v10 era, partly wrong now).

All dice, art, names and UI must be original, not copied from Random Dice or other games. The enemy HP model and the Duel rules follow Random Dice data as the owner supplied it.

## 1. Concept

Players equip a deck of five dice, summon them onto a 5 x 3 board (15 cells), merge them to raise their pips and survive endless waves. Pips run 1 to 7; 7 is drawn as a gold star. A die's attack rate is its base rate times its pip count, so pips raise the rate and not the damage per hit.

World 1 is the Verdant Trial (a toy-diorama meadow). Its enemies are Grunts, Runners, Brutes (mini-boss) and three bosses (see section 6). Other worlds are shown locked in the Play menu.

## 2. Modes

| Mode | Players | Rules |
|---|---|---|
| Solo | 1 | One board, one lane. Endless. Clearing wave 10 sets Trial cleared; the run continues. |
| Co-op | 2 | Each player has a board, deck, MP, summon budget and Power Up tiers. Two mirrored lanes join before the exit. Wave progress and lives are shared; every kill pays MP to both players. Both opt in from the Play menu (`CoopReady`). |
| Duel (1v1, ranked) | 2 | Each player has their own lane, lives and MP. Both lanes get the same mobs, and each wave ends with a boss per lane. Ends at 0 lives or a surrender; there are no draws. Players are matched by rank (`QueueDuel`), or get a bot after 12 s. See [DICE_RATING.md](DICE_RATING.md). |

Solo and Co-op run in the lobby place. A Duel runs in a reserved server (a same-server bot Duel in Studio or when teleporting is unavailable).

A new profile first plays the tutorial: five free starter rolls (500 tutorial Gems, `Rules/Tutorial`), then a Solo run to wave 10, then a choice to end or keep playing, then the wave 10 play milestone, which the player claims in the Play menu: a Frost die, 500 Gems and 5 Dice Shards. Solo and Co-op need five equipped dice (`Deck.IsReady`).

## 3. A match

- **Start:** 100 MP, 3 lives. The first wave starts 4 s after Start and each later wave 4 s after the previous one is cleared (`Balance`).
- **Summon:** costs 10 + 10 x (summons so far) MP, so 10, 20, 30, 40 ... A pip-1 die of a random deck type lands in a random empty cell.
- **Merge:** two dice of the same type and the same pip (1 to 6) become one die of pip + 1 at the target cell. The new type is re-rolled from the deck. Two 7-pip dice do not merge.
- **Attacks:** automatic. The first shot goes to the living enemy furthest along the path, anywhere on it (no range limit). In a Duel a die only sees its own lane; in Co-op both lanes share the stretch past the junction.
- **Kill MP:** by wave band 10 (waves 1-5), 20 (6-10), 30 (11-15), 40 (16-20), 50 (21+). A Brute pays x5 and a Boss x10 (`Balance.KillMp`). There is no wave stipend. Duel kills pay differently (DICE_RATING.md).
- **Power Up:** MP buys tiers for a die type, tier 1 to 5, costing 100 / 200 / 400 / 700 MP. Each tier adds 10% of base damage to every die of that type. Tiers last for the match only.
- **Aura:** Beacon gives its four orthogonal neighbours attack speed (`base 6% + 1% per extra pip + 1% per Power Up tier above 1`), capped at +30% per die.
- **Lives:** Grunt and Runner breaches cost 1, Brute and Boss cost 2. At 0 the run ends.
- **Enemy HP and waves:** see [WAVE_SCALING.md](WAVE_SCALING.md).

## 4. Dice, levels and rarities

Rarities, in order: Common, Rare, Epic, Legendary, Mythic, Secret. The roster is 7 Common, 5 Rare, 3 Epic, 2 Legendary, 1 Mythic (Astral) and 1 Secret (Wyvern); see [DICE_CATALOG.md](DICE_CATALOG.md). Starter deck: Pebble, Needle, Hammer, Twinshot, Longshot.

Die levels cost spare copies and Gold (`Config/Progression.DieLevel`). Hit damage grows evenly to x6 at a die's top level. Each level step also adds crit damage percent to the whole account (every die's crit uses it, Astral's Singularity too). In Duels the crit bonus is 0 for both seats.

Mastery: after a run every owned die in the match deck gains Mastery XP equal to the waves completed (curve in `Progression.Mastery`, max level 20; levels 5 / 10 / 15 / 20 pay Gems and an XP Tome once per die).

## 5. Economy

| Resource | Source | Use |
|---|---|---|
| Gold | Run reward (5 per wave), daily login, quests, milestones, Duel win streaks, sales | Die level-ups, Shop |
| Gems | Run reward (Random Dice card schedule x10, see BALANCING.md), quests, achievements, milestones, daily login, codes | Rolls, Shop |
| Verdant Fragments | 1 per wave cleared, Shop | Materials; sell price 2 each |
| Dice Shard | Wave 10 milestone (tutorial) | One shard becomes one spare copy of an owned die |
| XP / account level | 10 per wave, XP Tomes (100 XP) | Levels 1 to 50 (`Progression.Account`) |
| MP | Kills | Match only, never saved |

Claimed through the lobby: Quests (S1-S3, D1, W1, W2), the 7-day login calendar, play milestones (P10 to P100), achievements (A1-A5), mastery rewards and redeem codes. Rewards are `Rules/Rewards` bundles; every write is all-or-nothing and runs once per run id.

Roll (Standard pool): 100 Gems per roll, 1000 for ten; Legendary pity at 80 rolls. Shop: Gold and Gem offers, Robux Starter Pack and Gem packs (Robux offers stay unavailable until real developer product ids are set), and the VIP game pass (every roll 10% cheaper). Numbers are in BALANCING.md.

## 6. Enemies and bosses

| Kind | Speed (studs/s) | HP | Breach |
|---|---:|---|---:|
| Grunt | 6 | Base HP | 1 |
| Runner | 9 | Base HP x 0.5 | 1 |
| Brute (mini-boss) | 5.33 | Base HP x (5 + 1.5 per earlier Brute) | 2 |
| Boss | 3 | Base HP x (10 + 1.5 per earlier Boss) | 2 |

Three boss variants are rolled per run, never the same one twice in a row. Each has one ability:

| Boss | Ability | First cast / interval |
|---|---|---|
| Goblin King | Portal Summon: 3 Grunts and 1 Runner | 8 s / 14 s |
| Cursed King | Hammer Lock: locks 3 dice (up to 6 at once) | 9 s / 16 s |
| Court Jester | Dice Shuffle: re-rolls the pips of 5 dice | 7 s / 12 s |

The boss stands still while it casts. A boss wave is announced 4 s ahead.

## 7. Lobby and menus

Sprite HUD: Shop, Roll, Bag, Play, Codes, Daily, Quests and Settings, plus Gold, Gems, level and XP, and a five-slot deck bar. Bag has Dice, Materials, Items and Cosmetics tabs (sell, use, lock, equip, five saved teams, die upgrade). Settings are a registry in `src/shared/SettingsDefs.luau`, saved in the profile; settings the game does not use yet are labelled "coming soon". `Controllers/Preload` loads every `*Sprites` asset behind a loading message before the lobby opens.

## 8. Server structure and remotes

Boot goes through `src/shared/Core/Loader`. Pure rules in `src/server/Rules/` are spec-tested headless; `Services/` hold the Roblox glue (`MatchService`, `QueueService`, `ProfileService`, `ShopService`, `RedeemService`, `TutorialService`, `PlayerPolicy`, `VipService`, `AdminService`); `Infrastructure/` has the profile store, teleport and MemoryStore gateways with in-memory fakes, and the rate-limited guarded remotes. Profile schema is version 15 (`Rules/ProfileSchema`, with migrations). Balance numbers live in `src/server/Config/` and never reach the client.

Remotes (`src/shared/Net/Remotes.luau`), client to server, all with a sequence number and a `(ok, code)` reply: `Start`, `Summon`, `Merge`, `EquipDeck`, `TeamAction`, `ClaimQuest`, `RedeemCode`, `SaveSettings`, `BagAction`, `Roll`, `Buy`, `UpgradeDie`, `PowerUp`, `AdminAction`, `CoopReady`, `QueueDuel`, `Surrender`, `LeaveDuel`, `TutorialAction`. Server to client: `State`, `Enemies`, `Meta`, `Catalog`, `RollResult`.

Server-authoritative rules: deck ownership, cell state, merge type and pip, MP and prices, receipts (granted exactly once per PurchaseId), rewards (once per run id), rate limits per remote (`Balance.Remotes`) with a kick threshold, and paid random items are blocked where Roblox policy restricts them (`PlayerPolicy`, fail closed).

## 9. Proposed, not built

- World 2 and beyond, the Wave-100 staged clear and an Infinite mode with leaderboards.
- Chests, crafting, Universal Dust, profile upgrade tracks (Global Damage, Starting MP and so on) and a rotating shop. Of the crafting resources only Verdant Fragments exist.
- A rotating Event tab in Roll (it shows "No event right now").
- Ability implementations for Rare, Epic and Legendary dice (they are stat-only today).
- Trio and quad co-op, extra enemy classes (Swarm, Shield, Regenerator, Elite), kill-responsive scaling.
- Challenge Tier HP, speed and boss cooldown factors (owner has not supplied numbers).

See [FUTURE_UPDATES.md](FUTURE_UPDATES.md).
