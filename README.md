# Dice Defenders

Dice Defenders is a Roblox dice-merging lane defense written in Luau. Enemies walk a lane toward your exit. You summon dice onto a 5 x 3 board, merge them to raise their pips (attack rate), and survive endless waves before your three lives run out.

## Game modes

- **Solo:** one player, one lane. Clearing wave 10 counts as a Trial clear; the run goes on.
- **Co-op:** two players share wave progress and lives. Each has their own board, deck, MP and Power Up tiers. Two mirrored lanes join before the exit.
- **Duel (1v1, ranked):** each player has their own lane and lives. Each wave ends with a boss per lane, and the match ends at 0 lives or a surrender. Players are matched by rank, or get a bot after 12 s, and earn Dice Rating (DR).

## How a match works

1. Your deck is five dice from your collection. Starter dice are Pebble, Needle, Hammer, Twinshot and Longshot.
2. You start with 100 MP, enough for four summons. Each summon costs 10 more than the last: 10, 20, 30, 40 ...
3. A summon puts a pip-1 die of a random deck type in a random empty cell. A die's attack rate is its base rate times its pips, so a 7-pip die fires seven times as often as a 1-pip die.
4. Merge two dice of the same type and pip to make one die with pip + 1. The new type is re-rolled from your deck. Pips cap at 7.
5. Kills pay MP. Spend it on summons, or on Power Up tiers (tier 1 to 5) that raise a die type's damage for the rest of the match.
6. Grunts and Runners that reach the exit cost 1 life, Brutes and Bosses cost 2.
7. Waves are endless. A boss comes every 5th wave up to 35 and then on odd waves, with Brute mini-bosses in between. HP follows the Random Dice model ([WAVE_SCALING.md](docs/WAVE_SCALING.md)).

## Progression and economy

- **Gold and Gems:** earned from waves, quests, the login calendar, milestones and codes. Gold pays for die levels and Shop offers; Gems pay for rolls and Shop offers.
- **Dice:** rolled for Gems (pity at 80 rolls) and found as rewards. Rarities are Common, Rare, Epic, Legendary, Mythic and Secret. Dice level 1 to 12 with spare copies and Gold.
- **MP:** match-only currency, never saved.
- **Also:** Bag (materials, items, cosmetics, five saved teams), Quests, Achievements, Mastery and redeem codes.

## Project layout

- `src/server/` (maps to `ServerScriptService.Server`): `Config/` holds the balance numbers, `Rules/` the pure game logic, `Services/` the Roblox services that connect them, `Infrastructure/` the data store, MemoryStore and teleport gateways and the guarded remotes.
- `src/shared/` (`ReplicatedStorage.Shared`): code used by client and server: `Bosses`, `Display`, `Layout`, `SettingsDefs`, `Core/` (loader, signal) and `Net/Remotes`.
- `src/client/` (`StarterPlayerScripts.Client`): `Controllers/` for the HUD, lobby menus, board and enemy views, effects and dice visuals, plus the client entry point.
- `tests/luau/`: headless specs for the game logic. Run `python tests/luau/run.py`; it needs the `luau` CLI on your PATH.
- `tools/`: the balance simulator (`python tools/balance_sim.py [seeds]`, needs the `luau` CLI) and Python scripts that slice UI sheets, build asset data and generate boss animation data.
- `docs/`: design documents (below). `docs/_archive/` holds superseded ones.
- `default.project.json`: the Rojo project that maps `src` into Roblox Studio.
- `Assets/`: art, models, audio and references. It is gitignored and exists only on the owner's machine, so a fresh clone does not have it.
- `build/`: local place files and check logs, also gitignored.
- `reports/` (currently empty) and `research_notes/` (modelling research notes) are working folders, not part of the game.
- `aftman.toml` and `selene.toml`: tool pins and lint config.

## Documentation

- [GDD.md](docs/GDD.md): what the game is and how it works today, with a short list of proposals.
- [WAVE_SCALING.md](docs/WAVE_SCALING.md): enemy HP, wave schedule and Challenge Tiers.
- [DICE_RATING.md](docs/DICE_RATING.md): the Duel mode, DR, matchmaking and bots.
- [DICE_CATALOG.md](docs/DICE_CATALOG.md): dice roster, stats and perks.
- [BALANCING.md](docs/BALANCING.md): MP, rewards, levels, roll odds and prices.
- [FUTURE_UPDATES.md](docs/FUTURE_UPDATES.md): proposed content only.
- [ART_PIPELINE.md](docs/ART_PIPELINE.md): art and model requirements for new dice and UI.
- [_archive/](docs/_archive/): the old MVP contract and the old Duel scaling note.
