# Dice catalog

The source of truth is `src/server/Config/Dice.luau`. Display names, colours and rarities for the client are in `src/shared/Display.luau`. Dice ids are stable and shared by art, config and saved profiles.

**Roster:** 7 Common, 5 Rare, 3 Epic, 2 Legendary, 1 Mythic (Astral) and 1 Secret (Wyvern), 19 dice. The starter deck is C01 to C05.

## Rules in code

- A loadout holds up to five distinct dice; a match needs five equipped dice per player and summons from them with equal probability.
- Attacks per second = `rate x pip` (pips 1 to 7, `Balance.PipRate`). Damage per hit has no pip term. Each pip is its own shooter; `Balance.MaxAttacksPerTick` (8) bounds attacks per die per simulation step.
- Hit damage = `max(1, floor(base x perks x Power Up multiplier))` plus any flat proc. Power Up: tier 1 to 5, +10% of base per tier, costs 100 / 200 / 400 / 700 MP, match only.
- Perks in code: `vsKind` (damage multiplier against one enemy kind), `vsArmored` (against armored enemies; only Brutes are armored), `shots`, `procEvery` and `procFlat` (every Nth hit of a die instance adds flat damage), `slow` and `slowDuration`, `aura` and `singularity`.
- Merge: same type, same pip 1 to 6, new type re-rolled from the deck.
- Die levels cost copies and Gold, add account crit damage and raise hit damage up to x6 at the top level; see GDD.md.
- Per-pip DPS (base x shots x rate) is about 300 Common, 800 Rare, 3300 Epic, 23000 Legendary (Mythic and Secret higher). With the abilities below, `python tools/balance_sim.py` puts full-rarity decks at about wave 19-24 (Common), 25-38 (Rare), 38-49 (Epic) and 77-79 (Legendary, careful play). Reasoning and the full derivation: [DICE_REBALANCE_PROPOSAL.md](DICE_REBALANCE_PROPOSAL.md).
- Abilities live in `src/server/Rules/Abilities.luau` and are data-driven from `Config/Dice` (field list at the top of that file). Guardrails: slow cap 60% (bosses 50%), bosses never freeze or rewind, one enemy rewinds at most 3 times, procs never trigger procs.

## Common

| ID | Name | Base | Attacks/s | DPS/pip | Perk |
|---|---|---:|---:|---:|---|
| C01 | Pebble | 300 | 1.00 | 300 | +5% damage against Grunts |
| C02 | Needle | 170 | 1.75 | 298 + 44 | Every 6th hit of that die adds 150 flat damage |
| C03 | Hammer | 570 | 0.55 | 314 | +12% against armored enemies |
| C04 | Twinshot | 130 per shot | 0.95 | 247 | Two shots: one at the front enemy, one at a random living enemy (may be the same) |
| C05 | Longshot | 420 | 0.72 | 302 | Sniper: always aims at the highest-HP enemy |
| C06 | Chill | 270 | 1.00 | 270 | Hits slow the enemy by 15% for 1.5 s; repeats refresh |
| C07 | Spark | 230 | 1.15 | 265 + 27 | Every 4th attack chains to 1 more enemy for 60% of the hit |

## Rare, Epic, Legendary, Mythic, Secret

| ID | Name | Rarity | Base | Attacks/s | DPS/pip | Ability |
|---|---|---|---:|---:|---:|---|
| R01 | Frost | Rare | 750 | 1.00 | 750 | 20% per hit: slow 25% for 2.5 s. Every 8th hit freezes a non-boss for 0.6 s |
| R02 | Arc | Rare | 750 | 0.90 | 675 | Every hit strikes the front enemy for 90% of its damage, the enemy behind it for 40% and a third for 20% |
| R03 | Volley | Rare | 225 x 3 | 1.15 | 776 | Three bolts per attack, each at a different enemy when possible |
| R04 | Venom | Rare | 675 | 0.85 | 574 | Hits stack poison (90/s for 4 s, up to 4 stacks per die); a poisoned enemy that dies passes it to the nearest enemy |
| R05 | Beacon | Rare | 855 | 0.85 | 727 | Aura: +6% attack speed to the four orthogonal neighbours, +1% per extra pip and per Power Up tier above 1; capped at +30% (`Balance.AuraCap`) |
| E01 | Emberstorm | Epic | 4200 | 0.75 | 3150 | Hits burn (400/s for 3 s). Every 6 s all burning enemies take their remaining burn at once and ignite enemies within 10 studs |
| E02 | Mirror | Epic | 3300 | 1.00 | 3300 | On summon or merge copies the highest pip count on the board (never fewer pips than it has) |
| E03 | Gravity | Epic | 4900 | 0.70 | 3430 | Every 7 s pulls up to 5 non-boss enemies back 12% of the lane; bosses are slowed 35% for 1.5 s |
| L01 | Chrono | Legendary | 27500 | 0.85 | 23375 | Every 10 s a Time Rift on the lead enemy slows enemies within 18 studs 60% for 4 s (bosses 30%); every 3rd rift also rewinds non-bosses 15% of the lane (max 3 per enemy) |
| L02 | Forge | Legendary | 31200 | 0.75 | 23400 | A merge next to Forge keeps the merged type (no re-roll); every 4th such merge adds a free pip-1 die (one per 5 s) |
| M01 | Astral | Mythic | 34900 | 0.80 | 27920 (x5.5 expected with Singularity) | Singularity: with exactly one Astral on the board it deals 5x damage, and 10% of its hits deal 10x (plus the account crit bonus from die levels) |
| S01 | Wyvern | Secret | 40500 | 0.80 | 32400 | Shots pierce the next 3 enemies behind the target at full damage. Every 12 s Wyrmfire burns the whole lane for 6 s at 0.4% max HP per second (bosses 0.1%) |

The Roll menu features Chrono, Astral and Forge. Standard roll odds are in BALANCING.md (Astral 0.1%, Wyvern 0.01%, before pity).

Retired ids: profile v12 retired ten earlier dice and moved saved copies, levels and mastery to same-rarity replacements; v13 moved Mirror to E02 and Gravity to E03. Saves follow the die, not the number.

## Proposed: new dice (not built; need art)

Tether (Epic: mark 3 enemies, damage shared 30%), Mint (Epic: timed MP income), Nexus (Legendary: link enemies, damage shared in full), Prism (Legendary: re-fires neighbours' abilities), Vault (Legendary: MP interest, cheaper Power Up). Full stats and rules are in DICE_REBALANCE_PROPOSAL.md. They need fresh ids (E04, E05, L03, L04, L05 are retired profile ids, so use E11+ and L07+) plus models, sprites and effects before they enter `Config/Dice`; a rolled die without art breaks the client.

## Asset deliverables

Each die needs UI art, a 3D breakdown sheet and a model; see [ART_PIPELINE.md](ART_PIPELINE.md). In code, per-rarity model data is in `src/client/Controllers/Dice/*ModelData.luau`.

## Classes (die upgrades)

Every die levels up to class 15: class = level + the rarity's offset (Common 0, Rare 2, Epic 4, Legendary 6, Mythic 8, Secret 10), so a rarer die starts at a higher class with fewer levels (Common 15, Rare 13, Epic 11, Legendary 9, Mythic 7, Secret 5). `Config/Progression` holds the copies per step per rarity (totals 456 / 145 / 53 / 19 / 6 / 4) and the gold per class (totals 62,090 / 62,075 / 62,000 / 61,700 / 60,500 / 56,000). Hit damage grows evenly to x6 (+500%) at the top level (`Progression.DamageMul`). Each die's ability numbers also grow with class (`Config/DiceClasses`, from the owner's class table). Mirror only gains the damage; Astral only the damage and the account crit damage. A match plays each die at its owner's level.

Account crit: every die crits on 3% of shots (`Balance.Crit`) for 2x plus the crit damage earned from die levels; a lone Astral keeps its own 10% chance and 10x.
