# Duel (1v1) wave scaling

Source: NamuWiki "Random Dice: PvP Defense/Monster" (read 2026-11-23) plus the Random Dice HP model in `docs/WAVE_SCALING.md`.
Only the boss rule and the death/berserk phases are documented for PvP; the per-wave mob HP table is not published, so mobs use the same HP model as Co-op.

What the source says, and what the Duel does (all numbers in `Balance.Duel`, all *tune*):

| Source (PvP) | Duel |
|---|---|
| Boss HP = 25000 x round + 0.5 x remaining mob HP; the boss absorbs the remaining mobs | Each wave ends in one boss per lane: `BossPerRound` (300) x wave + `AbsorbShare` (0.5) x the lane's remaining mob HP. The source's 25000 is on a larger HP scale than ours, so the per-round base is calibrated down |
| Boss arrives after the mobs have been dealt with for a while | Once the wave's 10 mobs have spawned and the round timer (`Match.RoundTime`: 90 s, -10 s a wave, floor 60 s) has run out, or both lanes are clear |
| Boss counts as a boss: 2 hearts | `Boss` kind, 2 lives |
| "Death wave" from wave 7: mob HP and speed rise noticeably | From `DeathWave` (7): +8% HP and +3% speed per wave |
| SP per kill starts at 10 and rises 10 per boss killed (randomdice.gg PvP page); fixed at 110 from berserk wave 11; a boss drops 10x (wiki.gg) | Kill MP = `KillMpPerWave` (10) x wave, capped at `BerserkMp` (110); boss x10. Bosses move x1.25 from `BerserkWave` (11) |
| Boss HP/10 and Runner (fast) half HP | Mobs: 10 per wave, Runners (half HP, 1.5x speed) up to 5, from the shared HP carry/step model |

Not implemented (not documented or too large): random boss type with abilities, sending mobs to the opponent, a berserk boss-ability set.

Bot-vs-bot check: Bronze/Silver/Gold mirror matches end at wave 11-13, about 6-7 minutes.
Co-op uses the same HP model (see `docs/WAVE_SCALING.md`); its step values are placeholders to tune.

MP (SP) gain: Co-op/Solo `Balance.KillMp` already matches the documented shape (10 per kill, +10 per boss band, capped at 50 per NamuWiki; boss x10). Summon cost 10 + 10 per summon matches the source.
