# Balance, Difficulty, Economy and Progression — v0.01 Design Specification

> **Status:** Provisional tuning values, not playtested. These are initial formulas and targets, to be modified after instrumentation. Server-side definitions are the source of truth. All calculations must be checked for numeric overflow and long-session performance.

## 1. Unified difficulty model
All modes use the same virtual wave index `w` (starting at 1), party size `n`, enemy type coefficients, and combat formulas. World/Mode modifiers change the configuration, not the underlying algorithm.

### Enemy HP
```text
W(w) = (1 + 0.018 * min(w-1,39)) * (1.038 ^ max(0,w-40))
P_HP(n) = {1:1.00, 2:1.68, 3:2.30, 4:2.88}[n]
H_enemy = round(80 * W(w) * P_HP(n) * enemyTypeHP * bossHP * killPressure)
```
The first 40 waves ramp gently; after that, health grows exponentially at 3.8% per wave, compounded. Per-world multipliers are 1.0 in World 1. Proposed standard enemy multipliers: Grunt 1; Runner .70; Swarm .42; Brute 3.0; Shield 2.3; Regenerator 1.7; Elite 5.0. Boss health multiplier: 12 at wave 10, linearly reaching 25 at wave 100, with individual adjustment by boss mechanics.

### Difficulty example, solo normal monster
| Wave | Approx. HP |
|---:|---:|
| 1 | 80 |
| 20 | 107 |
| 40 | 136 |
| 60 | 286 |
| 80 | 604 |
| 100 | 1,272 |
| 150 | 8,200 |
| 200 | 52,800 |

The figures are illustrative approximations, not test outcomes. HP scaling alone will not balance the full stage; target enemy damage throughput, deck growth and boss-specific mechanics in simulations.

### Spawn budgets and speed
```text
EnemiesPerWave = min(45,8 + floor(.35*(w-1)))
SpawnIntervalSeconds = clamp(1.6 - .007*w, .35, 1.6)
SpeedMultiplier = min(1.60, 1+.006*(w-1))
```
At most 90 live enemies for solo/duo initially; temporarily throttle spawns rather than deleting unspawned enemy budget. For quad prototype, at most 120 live enemies subject to device testing. Multiplayer count multipliers proposed {1:1.0, 2:1.15, 3:1.3, 4:1.45}; HP scaling and spawn scaling must be evaluated together to avoid compounding difficulty beyond party throughput.

### Infinite kill-responsive pressure
Only verified, non-summoned hostile kills count as `K`, once per match (not once per player). Let `ExpectedKills(w)` be the sum of configured enemy budgets completed through wave w. Compute:
```text
surplus = clamp((K-ExpectedKills(w))/max(50,ExpectedKills(w)),0,.20)
killPressure = 1 + .30 * surplus          # 1.00–1.06
```
Evaluate at **wave boundaries**, not for each hit; enemies spawned within a wave keep fixed HP. This responds to unusual extra kills without punishing efficient teams with uncontrolled runaway HP. Infinite pressure is predominantly wave-based. For a future kills-first variant, use a virtual wave derived from kills **instead** of stacking independent exponentials. Never count boss-generated farmable minions toward `K`.

### Boss events
- Staged World 1: wave 10,20,30,...100; final boss must die for stage completion.
- Infinite: wave 110,120,130... OR +400 eligible kills since the previous boss, whichever occurs first. **Exactly one** boss event if thresholds coincide, then reset the kill target. Transition after World 1 wave 100 does not double-spawn.
- Every 5th non-boss wave can carry an Elite modifier. Telegraph bosses ≥3 seconds ahead.
- 20 team lives proposed; ordinary breach -1, Elite -2, Boss -5; zero lives is failure.

### Party scaling and fairness
Two players default. Solo campaign clear with a Rare/Epic-accessible deck must remain viable. Team kill Energy is credited to each teammate at `0.75+0.25/n` of normal kill value (rounded with fractional accumulators); wave stipend 6+floor(w/10), max 20 per person. Separate Solo/Duo/Trio/Squad leaderboards; launch only Solo/Duo ranked until 3–4-player tests pass. Evaluate threats against modeled actual total player DPS, not assumed identical players.

## 2. Dice damage, pips and merge
```text
pipMultiplier(p) = p^.85                       # 1...7; 7 is ★
persistentLevel(l) = 1+.03*(l-1)              # l=1...10
matchUpgrade(t) = 1+.12*t                     # t=0...4
hitDamage = max(1, floor(baseDamage*pipMultiplier*persistentLevel*matchUpgrade*buffFactor*resistanceFactor))
```
Merge **two dice of the same identity AND same pip (1–6)** to produce a single pip+1 dice at target, with its type re-rolled from five equipped deck dice; pips cap at 7★. Build-around effects can override explicitly but must obey transaction caps. At 7★ multiplier ≈5.23, not 7. Projectile count, DoT and slow utility count toward balance, not merely hitDamage. All status stacking is capped (slow 45%; vulnerability 25%; armor shred 30%) and dangerous feedback loops have an internal cooldown and max proc depth.

## 3. In-match Energy (separate from persistent Gold and Gems)
Starting Energy: 20. Summon cost after `s` successful summons:
```text
cost(s) = min(250, max(10, floor(10*1.085^s)))
```
Base kill Energy: Grunt 3, Runner 3, Brute 5, Swarm 1, Elite 8, Boss 30, adjusted for player count. In-match upgrades for one dice type cost 45 / 90 / 180 / 360 Energy, cap 4 tiers. Match Energy and temporary upgrade tiers **never persist** and **cannot be bought with Robux or Gems**. If summons become unaffordable too soon, lower the exponential cost or add wave stipend, not paid Energy.

## 4. Persistent economy
| Currency/resource | Earned from | Used for |
|---|---|---|
| Gold | Match completion, dailies, first-clears, achievements | Standard shop, Common/Rare dice, common chests, levels, crafting fees |
| Gems | Achievements, first-clear, events, quests; optional Robux packages | Premium chest, cosmetics, limited premium dice choices, reroll |
| Verdant Fragments | World 1 encounters, bosses and quests | Targeted World 1 dice crafting |
| Universal Dust | Duplicates, chest rewards, challenges | Rare/Epic/Legendary/Mythic crafting |
| Dice copies | Chest, shop, stage, crafting | Persistent dice levels |
| Energy | Kills during a match only | Summons and temporary match upgrades |

**Proposed starter grant:** 500 Gold, 50 Gems, five Common dice, one tutorial chest.  
**Stage reward seed:** 50+3×waves completed Gold; 40+4×waves completed XP, reduced on repeated clears. First-clear wave 20 guarantees a Rare selection; wave 60 an Epic selection; wave 100 a Legendary blueprint selection + 200 Gems + 800 Gold. Future worlds may unlock via first-clear achievements. Rewards must be idempotent: clear flags prevent reclaims.

**Craft seed:** Rare 80 Verdant Fragments + 300 Gold; Epic 250 fragments + 100 Dust + 1,200 Gold; Legendary 900 fragments + 500 Dust + 5,000 Gold + blueprint; Mythic 2,000 fragments + 1,500 Dust + mastery schematic + 12,000 Gold. Every rarity up to Mythic has an achievable non-Robux unlock route. Secret remains unobtainable at launch.

**Persistent leveling:** levels 1–10. For advancing from level `l` to `l+1`, copies needed `max(1,floor(l/2))`, Gold `100*l^1.55*rarityCostFactor` (round to whole coin), where factor Common=1, Rare=1.6, Epic=2.8, Legendary=5, Mythic=8. Level bonuses must remain small to avoid account-power dominance in Ranked.

### Rotating store
- Daily: 4 Gold offers + 2 Gem offers; weekly: 3 featured offers + 1 material bundle (proposed).
- Every offer states dice type, count, cost, remaining quantity, refresh timestamp and exact upgrade/crafting impact.
- A rotating shop should **never** be the sole way to acquire progression-critical dice. Offer duplicate conversion.
- Wallet and purchase transactions are server authoritative; use purchase IDs for idempotent retries and Robux receipts.

## 5. Chests and transparency
Illustrative proposed rarity odds (subject to balancing, Roblox compliance, and disclosure):
| Chest | Common | Rare | Epic | Legendary | Mythic | Secret |
|---|---:|---:|---:|---:|---:|---:|
| Basic (Gold) | 75% | 23% | 2% | 0% | 0% | 0% |
| Advanced (Gold/Gems) | 40% | 45% | 14% | 1% | 0% | 0% |
| Premium (Gems/optional Robux) | 0% | 64% | 31% | 4.8% | 0.2% | 0% |

All probabilities shown **before purchase and opening**, including duplicates; no hidden Secret rewards. Design proposed **Epic+ pity** after 20 eligible Advanced/Premium chests, and **Legendary pity** after 80 Premium chests, per product-specific pity ledger. Pity must be plainly disclosed and all streaks persisted safely. To protect fairness, premium-only dice and exclusive combat benefits are prohibited. Comply with Roblox location/age-dependent paid-random-item restrictions and provide alternative purchase routes as required by current policies. Prices, odds and mechanics require legal/platform review before launch.

## 6. Permanent profile upgrade tree
| Upgrade | Ranks | Per-rank effect | Total cap |
|---|---:|---|---|
| Global Dice Damage | 5 | +1% | +5% |
| Starting Energy | 5 | +2 | +10 |
| Gold Gains | 5 | +2% | +10% |
| Profile XP Gains | 5 | +3% | +15% |
| Boss Materials | 3 | +2% | +6% |
| Energy/Kill | 5 | +1% | +5% |

Costs: each rank `200*2^(rank-1)` Gold for economy tracks, `500*2^(rank-1)` for combat tracks (proposal). Combat effects are capped in Infinite ranked; consider normalized ranked presets. Never sell combat-only upgrade ranks exclusively for Robux.

## 7. Leaderboard score and abuse prevention
Rank **highest fully completed wave**, then total eligible enemies defeated, then shorter verified run duration, then earliest completion. Separate Solo / Duo and seasonal / All-time; season reset archives past best. For duo runs both players may receive record credit, flagged with same server run ID; never count duplicates as independent team records in team standings. Verify all score math on server; stamp build version, deck IDs, profile loadout, party size, start/end times, wave/kill audit and server session ID. Batch OrderedDataStore writes and handle budgets/backoff.

## 8. Telemetry & tuning checkpoints
Track clear rates by solo/duo, wave time, damage contribution by dice, percent damage from proc effects, merges/wave, 7★ conversion rate, Gold & Gem income/expense, chest conversion, wave failure causes, over-cap enemies and phone FPS. Initial playtest targets **proposed**: solo 100-wave clear 25–40% of sufficiently progressed non-paying players, duo clear 35–55%, no single dice appearing in >75% of successful decks, no Mythic required, and no paid-reward effect on skill-normalized leaderboard advantage. Re-run automated simulations after each content patch; document tuning changes and avoid silently changing displayed odds.
