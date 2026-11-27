# Duel (1v1) wave scaling

Source: NamuWiki "Random Dice: PvP Defense/Monster" (read 2026-11-23) plus the Random Dice HP model in `docs/WAVE_SCALING.md`.
Only the boss rule and the death/berserk phases are documented for PvP; the per-wave mob HP table is not published, so mobs use the same HP model as Co-op.

What the source says, and what the Duel does (all numbers in `Balance.Duel`, all *tune*):

| Source (PvP) | Duel |
|---|---|
| Boss HP = 25000 x round + 0.5 x remaining mob HP; the boss absorbs the remaining mobs | Each wave ends in one boss per lane: `BossPerRound` (25000) x wave + `AbsorbShare` (0.5) x the lane's remaining mob HP (matches the owner's Random Dice spec) |
| Boss arrives after the mobs have been dealt with for a while | Once the wave's 10 mobs have spawned and the round timer (`Match.RoundTime`: 90 s, -10 s a wave, floor 40 s, matches the owner's Random Dice spec) has run out, or both lanes are clear |
| Boss counts as a boss: 2 hearts | `Boss` kind, 2 lives |
| "Death wave" from wave 7: mob HP and speed rise noticeably | From `DeathWave` (7): +8% HP and +3% speed per wave |
| Owner spec: regular kill SP = min(110, 10 x wave); a boss grants 2x the wave's regular SP (max 220) | `KillMpPerWave` (10) x wave capped at `BerserkMp` (110); boss x `BossKillMul` (2). Bosses move x1.25 from `BerserkWave` (the game's own). Before: boss x10 (up to 1100) |
| Boss HP/10 and Runner (fast) half HP | Mobs: 10 per wave, Runners (half HP, 1.5x speed) up to 5, from the shared HP carry/step model |

Owner PvP spec status:
- Round end: every lane's remaining mobs are absorbed into one boss, HP = 25000 x wave + 0.5 x that lane's own remaining HP (`absorbed[seat]`), per player and independent. The game also spawns the boss early when BOTH lanes are clear (its own extra, not in the spec).
- Fast monsters: Runner = 0.5x HP, speed 9 vs 6 (+50%), same as the spec.
- Regular mob HP: the spec wants 100 growing steadily over elapsed match time with no formula. The game uses 10 mobs a wave from the Co-op b/d recurrence, plus Death Wave +8% HP and +3% speed per wave from wave 7. Unchanged; awaiting the researched numbers.
- Random Missions (even waves from 4): not built, owner must define the objectives and debuffs. Death Wave (from 7): only the game's +8% HP and +3% speed exist; boss skill cooldown reduction is not built and needs numbers. Berserk (from 11): the SP lock at 110 and a x1.25 boss speed exist; the Berserk boss ability upgrades are not built and need a design.

Not implemented (not documented or too large): random boss type with abilities, sending mobs to the opponent, a berserk boss-ability set.

Bot-vs-bot check: Bronze/Silver/Gold mirror matches end at wave 11-13, about 6-7 minutes.
Co-op uses the same HP model (see `docs/WAVE_SCALING.md`); its step values follow the owner's Random Dice spec. The extra +8% HP per wave from wave 7 (`DeathHpPerWave`) is the game's own and is not in the spec.

MP (SP) gain: Co-op/Solo `Balance.KillMp` already matches the documented shape (10 per kill, +10 per boss band, capped at 50 per NamuWiki; boss x10). Summon cost 10 + 10 per summon matches the source.

Rewards and return: a Duel also pays XP and Gems (`Balance.DuelReward`, see BALANCING.md). The Duel server sends players home `DUEL_RETURN_SECONDS` (3 s) after the end with the result in TeleportData (`Rules/ResultCarry`); the lobby validates it and shows it once as snapshot `PendingResult`.
