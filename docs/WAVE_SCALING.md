# Waves and enemy HP

Waves are endless in Solo, Co-op and Duel. Solo spawns one copy of each wave on one lane. Two-player Co-op spawns the same wave on two mirrored lanes that join before the exit; both lanes are the same length, and the players share wave progress and lives. Each player has a separate board, deck, summon budget and Power Up tiers, and every kill pays MP to both players.

## Enemy HP model

This follows the Random Dice Defense scaling model as community data-mining describes it (the owner's summary). The rules are implemented in `src/server/Config/CoopWaves.luau`; all HP is in Roblox HP.

- **Start:** wave 1 has b = 100.
- **Regular monsters:** Base HP = b + d × n. n is the spawn slot, 1 to 10. Every wave has 10 regular slots.
- **Step d (the owner's exact Random Dice formula):** d(1) = 10 and d(w) = d(w-1) + Delta(w), Delta(w) = 10 x ceil(w/10) for waves 2-50 and 50 x ceil(w/10) from wave 51, unbounded. d(10) = 100, d(11) = 120, d(20) = 300, d(21) = 330, d(30) = 600, d(31) = 640, d(40) = 1000, d(41) = 1050, d(50) = 1500, d(51) = 1800, d(60) = 4500, d(61) = 4850, d(70) = 8000, d(80) = 12000, d(111) = 27600. Checkpoints: b(20) = 23600, b(50) = 267600 (10th monster 282600), wave 51 runs 284400 to 300600, b(112) = 8361100, b(1000) = 8.39e9, b(1500) = 2.83e10 (exact in a double). **Owner note:** the worked example "b(50) = 213500" does not follow from the formula; the code implements the formula.
- **Carry:** the next wave's b is this wave's last regular monster Base HP, b + d × 10.
- **Fast (Runner):** Base HP × 0.5. On mini-boss waves the last slots are Runners: ceil(wave / 10) of them up to wave 60 (1 at wave 3, 2 at wave 13 ...), then 6 (61–66), 7 (67–74), 8 (75–84) and 9 (85 on). Duel waves have up to 5 Runners instead (see below).
- **Mini-Boss (Brute):** Base HP × (5 + 1.5 × (k − 1)), where k counts the mini-bosses up to and including this wave. It takes slot 1 of its wave.
- **Boss:** Base HP × (10 + 1.5 × (k − 1)), where k counts the bosses up to and including this wave. A boss wave is a single boss in slot 1.

Wave 1 example: slots 1 to 10 have HP 110, 120 ... 200. Wave 2 starts at b = 200 (b: 100, 200, 400, 700, 1100, 1600, 2200, 2900, 3700, 4600, 5600, 6800 for waves 1-12).

Balance numbers are *tune*. Dice, pips, damage and summon costs are balanced separately ([BALANCING.md](BALANCING.md), [DICE_CATALOG.md](DICE_CATALOG.md)).

## Schedule

- **Bosses:** every 5th wave up to wave 35, then every odd wave from 37.
- **Mini-bosses (owner's spec):** waves ending in 4 or 9 up to wave 35 (4, 9 ... 34); waves ending in 3 or 8 from 36 (38, 48 ...). A boss wave wins a clash (43, 53 ... are boss waves), and the k of the mini-boss formula counts only waves that really spawn one. The spec gives no mini-boss cadence after wave 50: the 36-50 rule continues. A boss wave is always one boss (never doubled).
- **Spawn timing and speed:** the number of enemies per wave comes from the queue above (10, or 1 on a boss wave). `Formulas.SpawnInterval` (1.6 s - 0.007 s x wave, clamped to 0.35-1.6 s) and `Formulas.SpeedMul` (1 + 0.006 x (wave - 1), capped at 1.6) in `src/server/Rules/Formulas.luau` set the gap between spawns and the speed multiplier. Base speeds: Grunt 6, Runner 9, Brute 16/3, Boss 3 studs/s (`Config/Enemies`). Cadence: first wave 4 s after Start, each later wave 4 s after the previous one is cleared. At most 90 enemies are alive at once (`Balance.MaxAlive`).

## Challenge Tiers and gems

Waves 112-499 are Challenge Tier 1, 500-1000 Tier 2, 1001-1500 Tier 3 and 1501+ the Max tier (`Balance.ChallengeTiers`). The owner gave no numbers for the monster HP and speed jump or the shorter boss skill cooldowns, so those factors are 1.0 (**TODO-owner**) and nothing reads them yet. The Gem multiplier is the owner's: gems per cleared wave = the Random Dice card table x 10 (`Balance.GemsPerCard`, `Balance.WaveGems`) x 1 / 2 / 3 / 4 / 5 for waves 1-111 / Tier 1 / 2 / 3 / Max (`Formulas.WaveGems`). A run may report at most `Balance.MaxRunWaves` = 5000 waves (`Quests.SettleRun`).

## Duel (1v1)

Duel mobs use the same HP model with no boss or mini-boss in the wave queue; Runners grow with the wave instead (`min(5, wave // 3)`). Each wave also ends in a Duel boss. See [DICE_RATING.md](DICE_RATING.md).

## Tutorial and first gifts

New profiles receive 500 tutorial Gems reserved for five free, distinct starter rolls. The game equips the resulting dice. Clearing wave 10 in the Solo tutorial pauses progression for the player's choice to end or keep playing. The separate gift grants one random Epic die, 500 regular Gems and five Dice Shards. One shard converts into one spare copy of a die the player owns.

## Sources and limits

The model and its step table are from community data-mining of Random Dice Defense, as summarized by the owner. They have not been checked against the live game. The earlier measured curve (`docs/COOP_SCALING.md` in git history) is no longer used.
