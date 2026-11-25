# Waves and enemy HP

Waves are endless in Solo, Co-op and Duel. Solo spawns one copy of each wave on one lane. Two-player Co-op spawns the same wave on two mirrored lanes that join before the exit; both lanes are the same length, and the players share wave progress and lives. Each player has a separate board, deck, summon budget and Power Up tiers, and every kill pays MP to both players.

## Enemy HP model

This follows the Random Dice Defense scaling model as community data-mining describes it (the owner's summary). The rules are implemented in `src/server/Config/CoopWaves.luau`; all HP is in Roblox HP.

- **Start:** wave 1 has b = 100.
- **Regular monsters:** Base HP = b + d × n. n is the spawn slot, 1 to 10. Every wave has 10 regular slots.
- **Step d:** a flat HP added per slot, set per wave. `CoopWaves.Step` uses +30 from wave 1, +60 from wave 5, +90 from wave 10, +150 from wave 15, +300 from wave 20 and +450 from wave 25. From wave 25 it grows by +150 every 5 waves. **These step values are placeholders to be tuned, not confirmed Random Dice numbers.**
- **Carry:** the next wave's b is this wave's last regular monster Base HP, b + d × 10.
- **Fast (Runner):** Base HP × 0.5. On mini-boss waves the last slots are Runners: ceil(wave / 10) of them up to wave 60 (1 at wave 3, 2 at wave 13 ...), then 6 (61–66), 7 (67–74), 8 (75–84) and 9 (85 on). Duel waves have up to 5 Runners instead (see below).
- **Mini-Boss (Brute):** Base HP × (5 + 1.5 × (k − 1)), where k counts the mini-bosses up to and including this wave. It takes slot 1 of its wave.
- **Boss:** Base HP × (10 + 1.5 × (k − 1)), where k counts the bosses up to and including this wave. A boss wave is a single boss in slot 1.

Wave 1 example: slots 1 to 10 have HP 130, 160 ... 400. Wave 2 starts at b = 400.

Balance numbers are *tune*. Dice, pips, damage and summon costs are balanced separately ([MVP.md](MVP.md), [DICE_CATALOG.md](DICE_CATALOG.md)).

## Schedule

- **Bosses:** every 5th wave up to wave 35, then every odd wave from 37.
- **Mini-bosses:** waves 3, 8 ... 33, then every even wave from 36.
- **Spawn count and speed:** `Formulas.WaveCount`, `SpawnInterval` and `SpeedMul` in `src/server/Rules/Formulas.luau`. Spawn timing uses these local formulas.

## Duel (1v1)

Duel mobs use the same HP model with no boss or mini-boss in the wave queue; Runners grow with the wave instead (up to 5). Each wave also ends in a Duel boss. See [DUEL_SCALING.md](DUEL_SCALING.md).

## Tutorial and first gifts

New profiles receive 500 tutorial Gems reserved for five free, distinct starter rolls. The game equips the resulting dice. Clearing wave 10 in the Solo tutorial pauses progression for the player's choice to end or keep playing. The separate gift grants one random Epic die, 500 regular Gems and five Dice Shards. One shard converts into one spare copy of a die the player owns.

## Sources and limits

The model and its step table are from community data-mining of Random Dice Defense, as summarized by the owner. They have not been checked against the live game. The earlier measured curve (`docs/COOP_SCALING.md` in git history) is no longer used.
