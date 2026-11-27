# Dice rebalance proposal (wave 20 / 30 / 40 and beyond)

Status: **applied** to the 19 existing dice (stats, abilities, `Rules/Abilities.luau`, specs, `BossPerRound` 40000). The final numbers are in `docs/DICE_CATALOG.md`; where they differ from the tables below, the catalog wins (Rare and Legendary-and-up were retuned after the abilities went in, for the wave 80 Legendary target). The five new dice (Tether, Mint, Nexus, Prism, Vault) are **not built**: they need art and fresh ids. Numbers marked **sim** were run through `tools/balance_sim.py` on a scratch copy with the proposed `Dice.luau`; numbers marked **est** are estimates because the simulator does not model status effects or abilities.

## 1. What the numbers say

**The current dice cannot survive the current HP curve.** Running `tools/balance_sim.py` on the unchanged repo, the starter Commons lose at wave 3 (target in the docs: about wave 15). `CoopWaves` follows the Random Dice HP model (wave 20 = 347k total HP, wave 40 = 1.5M, wave 80 = 22M), while dice sit at about 15 damage per pip-second. Dice damage must rise about 20x just to reach the old targets.

How the DPS requirement was derived (solo, same HP and path model as Co-op):

- A wave must die inside its window: spawn time (`9 x SpawnInterval`) plus the walk of the 124-stud lane at `6 x SpeedMul` (boss: `3 x SpeedMul`).
- Board DPS = pip-units x (base x rate). Merging 1+1 into 2 keeps DPS, higher merges lose `p-1` pips, so the board holds about 8 pip-units at wave 3, 30 at wave 20, 41 at wave 40 and 49 at wave 80 for the bot (the 15 cells cap it at 105).
- The binding waves are **mini-boss waves (4, 9, 14 ...) and boss waves**, not plain waves. Every sim loss lands on one (19, 24, 29, 34, 38, 48 ...).

| Wave | Total HP of binding wave | DPS needed (avg over window) | DPS needed per pip-unit |
|---:|---:|---:|---:|
| 10 | 54k | 1.9k | 104 |
| 20 | 347k | 12.6k | 421 |
| 30 | 1.18M | 44.9k | 1213 |
| 40 | 1.51M | 109k (boss 39) | 2664 |
| 50 | 2.76M | 234k | 5318 |
| 60 | 5.77M | 621k | 13.8k |
| 80 | 22M (boss 79 binds) | 3.76M | 76.7k |

Per-pip DPS rises about 3x per 10 waves. That is why one rarity step has to be a 3x to 3.5x jump in per-pip DPS, and why no stat-only deck can reach wave 80.

## 2. New dice stats (rarity targets, sim-verified)

Rule used for abilities: **no crit chance, no damage increase, no attack-speed buff** on any new ability. Two existing exceptions are kept as they are: Astral's Singularity (the owner likes it) and Beacon's attack-speed aura. Power Up (+10% per tier) is unchanged.

Per-pip DPS = `base x shots x rate`. "Old" is today's value.

| ID | Die | Rarity | Base | Rate | New DPS/pip | Old DPS/pip |
|---|---|---|---:|---:|---:|---:|
| C01 | Pebble | Common | 300 | 1.00 | 300 (315 vs Grunt) | 16 |
| C02 | Needle | Common | 170 (+150 flat every 6th) | 1.75 | 298 + 44 proc | 15.8 |
| C03 | Hammer | Common | 570 | 0.55 | 314 | 16.5 |
| C04 | Twinshot | Common | 130 x 2 shots | 0.95 | 247 | 11.4 |
| C05 | Longshot | Common | 420 | 0.72 | 302 | 15.8 |
| C06 | Chill | Common | 270 | 1.00 | 270 | 14 |
| C07 | Spark | Common | 230 (+95 flat every 4th) | 1.15 | 265 + 27 proc | 13.8 |
| R01 | Frost | Rare | 1000 | 1.00 | 1000 | 19 |
| R02 | Arc | Rare | 1000 | 0.90 | 900 | 18.9 |
| R03 | Volley | Rare | 310 x 3 bolts | 1.15 | 1070 | 19.6 |
| R04 | Venom | Rare | 900 | 0.85 | 765 + poison | 19.6 |
| R05 | Beacon | Rare | 1150 | 0.85 | 978 | 19.6 |
| E01 | Emberstorm | Epic | 4200 | 0.75 | 3150 + burn | 21 |
| E02 | Mirror | Epic | 3300 | 1.00 | 3300 | 21 |
| E03 | Gravity | Epic | 4900 | 0.70 | 3430 | 21 |
| E04 | Tether (new) | Epic | 3300 | 1.00 | 3300 | n/a |
| E05 | Mint (new) | Epic | 3500 | 1.00 | 3500 | n/a |
| L01 | Chrono | Legendary | 7650 | 0.85 | 6500 | 25.5 |
| L02 | Forge | Legendary | 8670 | 0.75 | 6500 | 25.5 |
| L03 | Nexus (new) | Legendary | 7060 | 0.85 | 6000 | n/a |
| L04 | Prism (new) | Legendary | 6470 | 0.85 | 5500 | n/a |
| L05 | Vault (new) | Legendary | 7330 | 0.75 | 5500 | n/a |
| M01 | Astral | Mythic | 10000 | 0.80 | 8000 (x5.5 expected with Singularity = 44000) | 112 (616) |
| S01 | Dragon | Secret | 11250 | 0.80 | 9000 | 28.8 |

Why two Epics and three Legendaries are added: a loadout needs five distinct dice, and there are only 3 Epics and 2 Legendaries today, so "full Epic" and "full Legendary" decks do not exist yet. Roll odds divide a rarity evenly, so more dice per rarity dilute each one; that is a decision for the owner.

Support dice (Beacon, Prism, Vault, Mint, Tether) are set 10% to 15% under their rarity line because their ability is worth more than a stat.

### Sim results (stat only, abilities not modelled; median lost wave, 5 to 8 seeds)

| Deck | "Eager" bot (new player) | "Full" bot (careful player) | Target |
|---|---:|---:|---|
| Starter Commons | 19 (19 to 24) | 24 | 20 |
| Five Rares | 29 (24 to 29) | 34 | 30 |
| Five Epics | 38 (34 to 38) | 48 | 40 |
| Five Legendaries | 48 (48 to 53) | 58 | 50 to 60 |
| Legendary + Mythic + Secret + Epic | 48 | 58 | 60 |

Losses cluster on mini-boss and boss waves, so the result moves in steps of about 5 waves. A deck that needs one more percent of DPS jumps a whole step; do not read the steps as noise.

Early waves become very easy: at wave 1 a Common board does about 1500 DPS against 44 needed. If that bothers you, raise early HP (`InitialHp`) instead of lowering dice.

## 3. Abilities

Trigger types are in brackets. Every proc has an internal cooldown, and a proc cannot trigger another proc.

### Common (keep the existing perks; scaled only)

| Die | Ability |
|---|---|
| Pebble | +5% vs Grunts (existing) |
| Needle | [every 6th hit] +150 flat (existing) |
| Hammer | +12% vs armored (existing) |
| Twinshot | Two shots: front enemy and a random one (existing) |
| Longshot | **New perk, Sniper:** always targets the highest-HP living enemy; the -10% boss penalty is removed (it replaces the moot range perk) |
| Chill | Hits slow 15% for 1.5 s (existing) |
| Spark | [every 4th hit] +95 flat (existing) |

### Rare (utility, no strategy engine)

| Die | Ability |
|---|---|
| Frost | [random] 20% per hit: slow 25% for 2.5 s. [counter] Every 8th hit freezes a non-boss enemy for 0.6 s |
| Arc | [counter] Every 4th attack chains to 2 more enemies for 60% each (only adds damage on groups) |
| Volley | Three bolts per attack, each on a different enemy when 3+ are alive (otherwise on the same enemy) |
| Venom | Each hit adds a poison stack (90/s for 4 s, 4 stacks per die). [on kill] a poisoned enemy that dies passes its stacks to the nearest enemy |
| Beacon | Existing aura (+6% attack speed to 4 neighbours, +1% per pip and per Power Up tier, cap 30%). This is the one new-tier exception to "no buffs" |

### Epic (control and build pieces)

| Die | Ability |
|---|---|
| Emberstorm | Hits apply Burn (400/s for 3 s). [timer] every 6 s all burning enemies take their remaining burn at once and ignite enemies within 10 studs |
| Mirror | [on spawn / on merge] for 10 s copies the ability of the highest-rarity adjacent die (not Mirror or Astral's Singularity), using Mirror's own stats. Next to a Legendary it borrows a Legendary ability |
| Gravity | [timer] every 7 s pulls up to 5 non-boss enemies back 12% of the path. A boss is slowed 35% for 1.5 s instead |
| Tether (new) | [timer] every 6 s marks 3 enemies (not bosses) for 5 s; damage on one marked enemy also hits the other marked ones for 30% |
| Mint (new) | [timer] every 20 s pays one kill's worth of MP at the current wave (`Formulas.KillMp`). Counts at most 3 Mints per board |

### Legendary and above (strategy dice)

| Die | Archetype | Ability |
|---|---|---|
| Chrono | Stall | [timer] every 10 s a Time Rift forms on the lead non-boss enemy: enemies within 18 studs are slowed 60% for 4 s (bosses 30%). Every 3rd Rift also rewinds enemies inside it 15% of the path (never bosses; one enemy can be rewound at most 3 times) |
| Forge | Merge engine | [on merge] a merge next to Forge keeps the type of the die you dragged (no re-roll). [every 4th such merge] spawns a free pip-1 die of that type on an empty cell (at most one per 5 s). Forge is never consumed by the merge it enables |
| Nexus (new) | Link / sweep | [timer] every 9 s links up to 6 enemies for 5 s: any damage to one linked enemy hits all linked at full value (Brutes take 50%; bosses are never linked) |
| Prism (new) | Relay | [timer] every 12 s re-triggers the ability of each adjacent die once (timers reset to ready; counters complete). Makes Gravity, Chrono, Emberstorm, Tether and Mint fire far more often |
| Vault (new) | Hoard | [wave start] +5% interest on unspent MP (capped at +250). While on the board, Power Up costs 15% less |
| Astral (Mythic) | Solo carry | Unchanged Singularity: with exactly one Astral on the board it deals 5x, and 10% of those hits deal 10x. The only die that keeps a built-in multiplier. Its base is a normal Mythic line (8000 per pip, between Legendary 6500 and Dragon 9000) because the one-per-board rule is the cost |
| Wyvern (Secret) | Lane sweep | Shots pierce: each also hits the next 3 enemies behind the target at full damage. [timer] every 12 s Wyrmfire burns the whole lane for 6 s at 0.4% of max HP per second (bosses 0.1%) |

## 4. Strategies and how far they reach

The stat-only wall for Legendary decks is wave 48 to 58 (sim). Past that, the binding waves are bosses, which take no AoE help, so every strategy must do one of three things: stretch time on the boss, raise pip-units on the board, or sustain damage that does not scale with attack speed (burn, poison, %HP).

| Strategy | Core dice | What it multiplies | Est. reach |
|---|---|---|---:|
| Stall and burn | Chrono, Gravity, Frost, Emberstorm, Venom | Boss window x2 to 2.5 (slow stack capped at 50% on bosses), burn and poison keep ticking | 65 to 70 |
| Merge engine | Forge, Mirror, Mint, Vault + one carry | Pip-units 45 to 70 (x1.5) and Power Ups earlier | 60 to 65 |
| Relay | Prism + Chrono, Gravity, Emberstorm, Mint | Timer dice act about twice as often | 65 to 72 |
| Link sweep | Nexus, Tether, Arc, Volley | Mini-boss waves (a major wall) and mob clear speed (earlier MP) | 55 to 60 |
| Astral solo | Astral + any four | One 7-pip Astral alone is about 308k DPS (8000 x 5.5 x 7), roughly a whole Legendary board | 70 to 75 |
| All-in | Forge-built mono board + Prism relaying Chrono and Gravity | everything above | 75 to 80 |

Reading the estimates: wave 70 needs about 3x the DPS of the stat-only wall (wave 58), wave 80 needs about 7x. Time stretch (x2 to 2.5) times more pips (x1.5) gets to about 3 to 4x, so wave 80 only appears when every layer stacks. Honest read: **wave 80 is a perfect-build ceiling, not a normal outcome.** If you want it routine, the HP growth after wave 50 (`50 x ceil(w/10)` per slot) is the knob to flatten, not the dice.

### Guardrails (so strategies cannot be infinite)

- Slow: at most 60% on normal enemies, 30% to 50% on bosses (Chrono and Gravity stack up to this cap).
- Freeze and rewind: bosses are immune to Rewind, take a third of freeze duration, then 10 s immunity; each enemy can be rewound at most 3 times.
- %HP damage hits bosses at a quarter of the stated rate.
- Every proc has an internal cooldown; no proc triggers another proc (Prism re-triggers once per cast only).
- The wave timer does not pause: a stalled wave still ends only when cleared, so stalling forever gains nothing (rewards are per cleared wave).

## 5. PvP (Duel) and Co-op

**Co-op.** Same HP model and curve, so the Solo table applies. Both lanes receive the wave, but dice DPS and MP income are shared in both directions (every kill pays both players), so two players should land close to the Solo result, a few waves higher from the doubled MP income. The simulator only runs one player, so this is **est**.

**Duel.** Mobs use the same HP model with the death-wave multiplier (+8% HP and +3% speed per wave from wave 7). The boss is `25000 x wave` HP, a linear term the mobs soon overtake. Analytic model (not simulated: the sim has no Duel mode):

| Duel boss `BossPerRound` | Commons | Rares | Epics |
|---:|---:|---:|---:|
| 25000 (today) | about wave 18 | about 27 | about 38 |
| 40000 | about wave 11 | about 27 | about 38 |

With 25000 a Common mirror match would run to about wave 18, roughly 12 minutes, against the 6 to 7 minutes (waves 11 to 13) the docs record. Raising `BossPerRound` to 40000 restores the short Common match without touching Rares and above. The jump from wave 11 to 27 between Common and Rare is intended: duels are matched by rating, so a Common player is rarely facing a Rare player. Anti-stall for Duel: bosses already resist slows by 50% in these guardrails; no Rewind targets bosses.

## 6. What was applied, and the final sim (6 seeds, abilities live)

| Deck | Eager (new player) | Full (careful) |
|---|---:|---:|
| Starter Commons | 19 | 24 |
| Five Rares | 31 (25 to 35) | 38 |
| Three Epics | 38 | 49 |
| Chrono + Forge | 57 | 79 |
| Chrono, Forge, Astral, Dragon, Gravity | 73 | 77 |

Final bases: Frost 750, Arc 750, Volley 225 x 3, Venom 675, Beacon 855; Chrono 27500, Forge 31200, Astral 34900, Dragon 40500 (Rarity lines are about 800 / 23000 / 28000 / 32400 per pip). Rare stat had to drop about 25% from the table above because Frost, Arc and Venom abilities are worth about a third of the deck in the sim.

## 7. Original apply checklist

1. Replace `Dice.Types` stats in `src/server/Config/Dice.luau` (the table in section 2). Add `E04`, `E05`, `L03`, `L04`, `L05` and the matching display, model and roll-pool entries.
2. Implement abilities (status system: slow, freeze, burn, poison, mark, link; timers; on-merge hooks). Only the existing perks are built today.
3. `Balance.Duel.BossPerRound` to 40000 (if you agree).
4. Update `docs/DICE_CATALOG.md`, `docs/BALANCING.md` (the "about 19 / 21 / 25 DPS" lines) and the `tests/luau` specs that pin base values.
5. Re-run `python tools/balance_sim.py` (extend it with the ability model or hand-check), then a Studio playtest.

Method and limits: the sim bots ("eager" merges at once, "full" fills the board first) stand in for a new and a careful player; real players vary. Ability values are untested: Venom, Burn, Wyrmfire and Mint numbers especially need a pass once built.
