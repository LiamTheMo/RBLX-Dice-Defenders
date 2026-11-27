# Dice catalog

The source of truth is `src/server/Config/Dice.luau`. Display names, colours and rarities for the client are in `src/shared/Display.luau`. Dice ids are stable and shared by art, config and saved profiles.

**Roster:** 7 Common, 5 Rare, 3 Epic, 2 Legendary, 1 Mythic (Astral) and 1 Secret (Dragon), 19 dice. The starter deck is C01 to C05.

## Rules in code

- A loadout holds up to five distinct dice; a match needs five equipped dice per player and summons from them with equal probability.
- Attacks per second = `rate x pip` (pips 1 to 7, `Balance.PipRate`). Damage per hit has no pip term. Each pip is its own shooter; `Balance.MaxAttacksPerTick` (8) bounds attacks per die per simulation step.
- Hit damage = `max(1, floor(base x perks x Power Up multiplier))` plus any flat proc. Power Up: tier 1 to 5, +10% of base per tier, costs 100 / 200 / 400 / 700 MP, match only.
- Perks in code: `vsKind` (damage multiplier against one enemy kind), `vsArmored` (against armored enemies; only Brutes are armored), `shots`, `procEvery` and `procFlat` (every Nth hit of a die instance adds flat damage), `slow` and `slowDuration`, `aura` and `singularity`.
- Merge: same type, same pip 1 to 6, new type re-rolled from the deck.
- Die levels (1 to 12) cost copies and Gold and add account crit damage only; see GDD.md. They do not raise damage.
- Rare, Epic and Legendary dice are stat-only: base x rate is set to about 19 / 21 / 25 damage per second per rarity tier, so rarity is a modest power step. Their named effects in the old design notes are not built and are listed under Proposed below.

## Common

| ID | Name | Base damage | Attacks/s | Perk |
|---|---|---:|---:|---|
| C01 | Pebble | 16 | 1.00 | +5% damage against Grunts |
| C02 | Needle | 9 | 1.75 | Every 6th hit of that die adds 8 flat damage |
| C03 | Hammer | 30 | 0.55 | +12% against armored enemies |
| C04 | Twinshot | 6 per shot | 0.95 | Two shots: one at the front enemy, one at a random living enemy (may be the same) |
| C05 | Longshot | 22 | 0.72 | -10% against bosses. Its old +25% range perk is moot because every die can hit anywhere; replacement perk undecided |
| C06 | Chill | 14 | 1.00 | Hits slow the enemy by 15% for 1.5 s; repeats refresh |
| C07 | Spark | 12 | 1.15 | Every 4th hit adds 5 flat damage |

## Rare, Epic, Legendary, Mythic, Secret

| ID | Name | Rarity | Base damage | Attacks/s | Effect |
|---|---|---|---:|---:|---|
| R01 | Frost | Rare | 19 | 1.00 | none yet |
| R02 | Arc | Rare | 21 | 0.90 | none yet |
| R03 | Volley | Rare | 17 | 1.15 | none yet |
| R04 | Venom | Rare | 23 | 0.85 | none yet |
| R05 | Beacon | Rare | 23 | 0.85 | Aura: +6% attack speed to the four orthogonal neighbours, +1% per extra pip and +1% per Power Up tier above 1; each die's total capped at +30% (`Balance.AuraCap`) |
| E01 | Emberstorm | Epic | 28 | 0.75 | none yet |
| E02 | Mirror | Epic | 21 | 1.00 | none yet |
| E03 | Gravity | Epic | 30 | 0.70 | none yet |
| L01 | Chrono | Legendary | 30 | 0.85 | none yet |
| L02 | Forge | Legendary | 34 | 0.75 | none yet |
| M01 | Astral | Mythic | 140 | 0.80 | Singularity: with exactly one Astral on your board it deals 5x damage, and 10% of its hits crit for 10x (plus the account crit bonus from die levels) |
| S01 | Dragon | Secret | 36 | 0.80 | none yet |

The Roll menu features Chrono, Astral and Forge. Standard roll odds are in BALANCING.md (Astral 0.1%, Dragon 0.01%, before pity).

Retired ids: profile v12 retired ten earlier dice and moved saved copies, levels and mastery to same-rarity replacements; v13 moved Mirror to E02 and Gravity to E03. Saves follow the die, not the number.

## Proposed: planned abilities (not built)

These were the original design notes for the stat-only dice. Treat them as ideas.

| Die | Idea |
|---|---|
| Frost | 22% chance per attack to slow 18% for 2.5 s |
| Arc | Every 4th attack chains lightning to 2 more enemies |
| Volley | Three bolts at three distinct enemies at reduced damage |
| Venom | 30% chance to poison (5 damage/s for 5 s, up to 3 stacks) |
| Emberstorm | Applies Burn; every 6 s detonates burning enemies nearby |
| Mirror | On summon or merge into it, copies part of the strongest neighbour's damage for 8 s |
| Gravity | Every 7 s pulls up to 5 normal enemies back; bosses immune |
| Chrono | Shortens nearby same-row dice ability cooldowns; low own damage |
| Forge | On the 3rd merge consumed, transforms a low-pip die for a short boost |

Design guardrails for any of these: status caps (slow 45%, vulnerability 25%, armor shred 30%), internal cooldowns on every proc, a cap on nested procs, and no rarity being unconditionally better than a well-built deck. The Mythic should not beat the best Legendary-centred decks by more than 10 to 15% on comparable investment.

Synergy ideas: slow plus pull plus burn detonation; Beacon next to fast shooters (the aura cap prevents stacking); keep one Astral and fill the rest of the board with other dice.

## Asset deliverables

Each die needs UI art, a 3D breakdown sheet and a model; see [ART_PIPELINE.md](ART_PIPELINE.md). In code, per-rarity model data is in `src/client/Controllers/Dice/*ModelData.luau`.
