# Dice Catalog — launch roster and mechanics

**Current roster:** 7 Common (Pebble, Needle, Hammer, Twinshot, Longshot, Chill, Spark), 7 Rare (the five below plus Wind, Rock), 8 Epic (Emberstorm, Mirror, Gravity plus Ice, Leaf, Lightning, Water, Shadow), 5 Legendary (Chrono, Forge plus Sun, Fire, Light), and 1 Mythic (Astral). No Secret dice. Chill slows hit enemies by 15% for 1.5 seconds, refreshing without stacking; Spark adds 5 damage every fourth hit. The ten newest dice are stat-only for now (table below). Higher-rarity abilities in the tables below are proposals, not implemented. The starter deck remains the first five Commons. Mythic is not currently obtainable.

**Removed in v11:** Reactor (E02), Catalyst (E04) and Prism (L03) no longer exist; profile migration v11 converts owned copies, mastery and deck slots to Lightning (E08), Leaf (E07) and Light (L06).

**New dice (stat-only for now):**

| ID | Name | Rarity | Base | Attacks/s | Status |
|---|---|---|---:|---:|---|
| R06 | Wind | Rare | 15 | 1.30 | stat-only for now |
| R07 | Rock | Rare | 26 | 0.75 | stat-only for now |
| E06 | Ice | Epic | 22 | 0.95 | stat-only for now |
| E07 | Leaf | Epic | 24 | 0.88 | stat-only for now |
| E08 | Lightning | Epic | 20 | 1.05 | stat-only for now |
| E09 | Water | Epic | 26 | 0.80 | stat-only for now |
| E10 | Shadow | Epic | 30 | 0.70 | stat-only for now |
| L04 | Sun | Legendary | 32 | 0.80 | stat-only for now |
| L05 | Fire | Legendary | 34 | 0.75 | stat-only for now |
| L06 | Light | Legendary | 28 | 0.90 | Aura: orthogonal neighbours +8% attack speed (+1.5% per extra pip and per Power Up tier), implemented |

The tables below describe the earlier proposed roster and ability design; current combat values are in the server configuration.
**Status:** 19 proposed launch dice; 18 Common–Legendary available first, single Mythic gated by v1.0 readiness. Secret rarity declared, **zero Secret dice at launch**. All statistics are **level-1, 1-pip tuning seeds**, not confirmed balance. Base DPS = hit damage × attacks/s before armor. Every die hits the enemy closest to the exit (global targeting), so there is no range stat.

## Universal dice rules
- Each player equips **five unique dice**; summons sample the five with equal probability. A die's visual asset and game definition share a stable unique ID.
- Pips: attacks per second = rate x `Balance.PipRate[pip]` ({1,...,7}, *tune*); damage per hit has no pip term. Power Up (in match, per deck die type, tier 1-5): +10% of base hit damage per tier above 1, costs 100 / 200 / 400 / 700 MP (*tune*). Aura dice (`aura = {base, perPip, perTier}`) give orthogonal neighbours attack speed, total per die capped at 30% (*tune*): Beacon 6% base, Light 8% base. All of this is implemented; `docs/BALANCING.md` has the figures. Ability-specific proc rates are normalized to attack rate to avoid rapid fire exploiting chances.
- Dice merge only with identical type and pips 1–6; rerolls type from deck at target with pip+1. Merge-bonus abilities trigger exactly once per server merge transaction.
- Levels 1–7 are persistent (cap is one constant, *tune*); +3% base damage per level is a proposal, not implemented (level has no combat effect yet), with role-specific alternatives. In-run power tiers are separate.
- **Status policy:** slow cap 45%; vulnerability cap 25%; armor shred cap 30%; on-hit proc coefficients damp very high-frequency attacks; unique effect IDs avoid multiplicative duplicates.
- Support dice can deal minimal damage but contribute meaningful utility. No rarity provides unconditional superiority over a well-built deck.
- All procs have explicit internal cooldowns (ICDs) or event budgets; multi-projectile attacks use per-volley rather than per-hit rolls unless specified.

## Common — 5
| ID / name | Base damage | Attacks/s | Signature and trigger | Intended use |
|---|---:|---:|---|---|
| C01 **Pebble** | 16 | 1.00 | Always: stable first-target single shot; +5% damage vs Grunts | Consistent baseline |
| C02 **Needle** | 9 | 1.75 | On-hit: every 6th hit adds 8 true damage (one stack per dice instance) | Fast single-target |
| C03 **Hammer** | 30 | 0.55 | Always: +12% against armored targets; slower turn speed | Heavy / armor soft-counter |
| C04 **Twinshot** | 10 | 0.95 | Every attack: 2 projectiles to same/adjacent targets at 70% damage each; no extra proc rolls | Weak swarm coverage |
| C05 **Longshot** | 22 | 0.72 | Always: -10% vs bosses (the +25% range perk is moot under global targeting; replacement TBD) | Replacement perk TBD |

## Rare — 5
| ID / name | Damage | Attacks/s | Signature and trigger | Intended use |
|---|---:|---:|---|---|
| R01 **Frost** | 12 | 1.00 | On-hit 22% per attack: 18% slow for 2.5 s; repeated hits refresh, not stack | Tempo / runners |
| R02 **Arc** | 12 | 0.90 | Every 4th attack: lightning chains to 2 additional enemies at 65% then 45% damage; unique targets | Cluster clear |
| R03 **Volley** | 8 | 1.15 | Every attack: 3 distinct-target bolts at 65% damage; single-target bolts consolidate at 55% | Multi-target burst |
| R04 **Venom** | 11 | 0.85 | On-hit 30%: poison 5 dmg/s for 5 s; up to 3 stacks per target across sources | DoT sustain / bosses |
| R05 **Beacon** | 6 | 0.85 | Implemented: orthogonally adjacent dice +6% attack speed (+1% per extra pip and per Power Up tier), each die's total capped at 30%; no isolation penalty | Positional support |

## Epic — 3
| ID / name | Damage | Attacks/s | Signature and trigger | Intended use |
|---|---:|---:|---|---|
| E01 **Emberstorm** | 13 | 0.75 | On-hit: applies Burn (6 dmg/s × 4 s). Every 6 s detonates burning enemies in a small radius for 45% attack damage, max 8 targets | Area/DoT engine |
| E03 **Mirror** | 7 | 1.00 | On summon and after merging INTO a Mirror: copy 35% of damage of strongest orthogonal neighbor for 8 s, not proc effects; refresh only on qualifying event | Board puzzle / carry amplifier |
| E05 **Gravity** | 14 | 0.70 | Every 7 s pull up to 5 normal enemies back 0.6 path units, boss immune; if 3+ dice in its column, cooldown 5.5 s; no chain of pulls within 1.5 s | Spatial control |

## Legendary — 2
| ID / name | Damage | Attacks/s | Signature and trigger | Intended use |
|---|---:|---:|---|---|
| L01 **Chrono** | 9 | 0.85 | Always: nearby same-row dice have 10% shorter ability ICDs (max 15% effective from all Chronos), but Chrono itself has -30% projectile damage | Ability engine / alignment |
| L02 **Forge** | 14 | 0.75 | On 3rd merge consumed anywhere on own board: transform one random 1–3 pip die into a random deck type of same pip and +25% output for 8 s; ICD 15 s, cannot retrigger itself | Merge economy / reroll control |

## Mythic — 1
| ID / name | Damage | Attacks/s | Signature and trigger | Intended use |
|---|---:|---:|---|---|
| M01 **Astral** | 15 | 0.90 | Always: +4% damage per distinct pip value present on own board (max +24%); at 7★, every 12 s fire a celestial beam hitting 5 unique enemies for 90% attack damage, boss hit capped at 150% total | High-end board diversity payoff; constrained by build puzzle |

**Mythic parity guardrail:** M01 should not exceed best available Legendary-centered decks by >10–15% sustained boss DPS on comparable investment during target-wave tests. It should lose to specialized Epic setups on relevant maps, making it a desirable *option*, not a necessity.

## Planned synergies and counterplay
- Frost + Gravity + Emberstorm: cluster slow enemies for burn detonations; bosses resist displacement.
- Beacon + Needle/Volley: physical adjacency matters more than raw rarity; Beacon cap prevents stacking monopoly.
- Chrono + Gravity: longer stalls until enemy fast-resistances and ICD caps; Chrono has low standalone DPS.
- Astral + rare varied-pip board: diversify pip values, conflict with desire to make all dice 7★.
- New world modifiers (e.g. Burn resistance, high mobility, armored squads, lane splits) should change optimal decks; communicate modifiers *before* deck lock.

## Acquisition and leveling (proposed)
| Tier | First attainable | Repeatable route |
|---|---|---|
| Common | All five tutorial starters | Gold shop, common chest, copies |
| Rare | Guaranteed choice on Wave 20 first-clear | Gold shop, rare chest, world fragments |
| Epic | One guaranteed Epic choice on Wave 60 first-clear | World boss fragments, crafting, chest pity |
| Legendary | Wave 100 first-clear **choice of a Legendary blueprint** (not complete die) | Long-term crafting, rare premium/free chest pity |
| Mythic | Post-clear mastery quest ending in guaranteed Astral schematic | Repeated world mastery crafting; optional high-tier chest at disclosed low chance |
| Secret | Not available | Future expansion only |

**Persistent leveling proposal:** Levels 1–7, +3% baseline role-specific stat/level (not implemented); level-ups spend spare copies of the same die (1, 1, 1, 2, 2, 3 for 1→2 … 6→7, *tune*), no Gold cost yet; unlock any dice's defining ability immediately at acquisition, not paywalled behind upgrading. All players receive the exact same **ability rules** at any level; levels change output, not feature ownership. Crafting guarantees targeted unlocks given time investment. Details in BALANCING.md.

## Ability implementation contract
```lua
-- Data-only proposal; server validates events and performs effects
DiceDefinition = {
    Id = "R01", Rarity = "Rare", BaseDamage = 12, AttacksPerSecond = 1.0,
    TargetPolicy = "First",
    Ability = {
        Trigger = "OnHit", Chance = 0.22, InternalCooldown = 0,
        Effect = "Slow", Magnitude = 0.18, Duration = 2.5,
        StackGroup = "Slow", Cap = 0.45,
        ProcCoefficient = 1.0
    }
}
```
Trigger events: OnHit, OnKill, OnMergeConsumed, OnMergeProduced, OnSummon, OnTimer, OnWaveStart, OnBossSpawn, OnAdjacentChanged, OnPipChanged, OnBoardFull, OnMapTagActive, OnEnemyThreshold. **Immutable run seed** + server RNG produce outcomes; apply ordering: validate event → compute conditions → cap & cooldown → activate → enqueue effects → publish FX. Max **3 nested proc generations** and **24 effect events per dice per server tick** initially; throttled FX must not throttle damage truth.

## Dice asset deliverables (mandatory for each new die)
One original ChatGPT-generated icon/portrait and rarity treatment; orthographic top/front/side/back views and 3/4 isometric beauty view; **one large clean modeling-breakdown sheet** with separated/exploded base cube, bevels, pip/star inlays, face details, projectiles, glow meshes, moving parts, labeled material/colors, proportions and approximate Roblox studs; silhouette verification at tiny size. See ART_PIPELINE.md for export contract and no-splicing rule.
