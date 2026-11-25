# Dice Defenders

Dice Defenders is a Roblox dice-merging lane defense. Enemies walk a path toward your exit. You summon dice onto a 5 × 3 board, merge them to raise their pips (attack rate), and survive endless waves before your lives run out.

## Game modes

- **Solo:** one player, one lane. Clearing wave 10 counts as a Trial clear.
- **Co-op:** two players share one wave progress and one set of lives. Each player has their own board, deck, summon budget and Power Up tiers. Enemies arrive on two mirrored lanes that join before the exit.
- **Duel (1v1):** two players race on their own lanes. Each wave ends with a boss per lane, and the match ends at zero lives. Duel has a dice rating (DR) that ranks players.

## How a match works

1. Your deck is five dice from your collection. Starter dice are Pebble, Needle, Hammer, Twinshot and Longshot.
2. You start with 100 MP, which is enough for four summons. Each summon costs more than the last: 10, 20, 30, 40 ...
3. Summon a die onto an empty board cell. Each die fires at enemies in range. Its attack rate is its base rate × its pip count, so a 7-pip die fires seven times as often as a 1-pip die.
4. Merge two dice of the same type and pip count to make one die with pip + 1. The merged die's type is re-rolled from your deck. Pips cap at 7.
5. Kills pay MP. Spend it on summons, or on Power Up tiers for a die type. Power Ups raise that type's damage for the rest of the match.
6. Enemies that reach the exit cost lives. Grunts and Runners cost 1 life, Brutes and Bosses cost 2. You start with 3.
7. Waves are endless. Each wave starts 4 seconds after the last one clears. Every 5th wave has a boss, and some waves have a Brute mini-boss.

Enemy HP and wave scaling follow the Random Dice model. See [WAVE_SCALING.md](docs/WAVE_SCALING.md) for the formulas and schedule.

## Progression and economy

- **Gold:** earned from waves and run rewards. Spent in the shop and on dice upgrades.
- **Gems:** earned from waves, quests and daily logins. Spent on rolls and shop items.
- **MP:** match-only currency for summons and Power Ups. It never carries over between matches.
- **Dice:** rolled from the shop or earned through quests. Each die has levels (1 to 7) that you raise with spare copies and Gold. Rarities are Common, Rare, Epic, Legendary and Mythic.
- **Quests, daily logins and redeem codes:** extra rewards, claimed from the lobby.

## Project layout

- `src/server/`: game rules and config, run on the server. `Config/` holds the balance numbers, `Rules/` the pure game logic, and `Services/` the Roblox services that connect them.
- `src/shared/`: modules used by both client and server, such as layout and bosses.
- `src/client/`: UI controllers and the client entry point.
- `tests/luau/`: headless specs for the game logic. Run them with `python tests/luau/run.py`, which needs the `luau` CLI on your PATH.
- `tools/`: the balance simulator (`python tools/balance_sim.py [seeds]`) and asset build scripts.
- `default.project.json`: the Rojo project mapping the `src` tree into Roblox Studio.

## Documentation

- [WAVE_SCALING.md](docs/WAVE_SCALING.md): enemy HP, wave schedule and lane rules.
- [MVP.md](docs/MVP.md): the first playable build, its rules and its remotes.
- [DUEL_SCALING.md](docs/DUEL_SCALING.md): 1v1 boss and phase rules.
- [DICE_RATING.md](docs/DICE_RATING.md): Duel matchmaking and rating.
- [DICE_CATALOG.md](docs/DICE_CATALOG.md): dice roster, stats and abilities.
- [BALANCING.md](docs/BALANCING.md): balance and economy notes. Parts of it are still proposals.
- [GDD.md](docs/GDD.md): the design document.
- [FUTURE_UPDATES.md](docs/FUTURE_UPDATES.md): planned content.
- [ART_PIPELINE.md](docs/ART_PIPELINE.md): art and model requirements for new dice.
