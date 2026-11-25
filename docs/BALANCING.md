# Balance, Difficulty, Economy and Progression — v0.01 Design Specification

> **Status:** Provisional tuning values, not playtested. These are initial formulas and targets, to be modified after instrumentation. Server-side definitions are the source of truth. All calculations must be checked for numeric overflow and long-session performance.

## 1. Unified difficulty model
All modes use the same virtual wave index `w` (starting at 1), party size `n`, enemy type coefficients, and combat formulas. World/Mode modifiers change the configuration, not the underlying algorithm.

### Enemy HP
Implemented as the Random Dice model (b, d × n, Fast ×0.5, Mini-Boss and Boss multipliers that grow per kind); see [WAVE_SCALING.md](WAVE_SCALING.md). The enemy-type and boss multipliers below are older proposals and are not in the code. Per-world multipliers are 1.0 in World 1. Proposed standard enemy multipliers: Grunt 1; Runner .70; Swarm .42; Brute 3.0; Shield 2.3; Regenerator 1.7; Elite 5.0.

### Spawn budgets and speed
```text
EnemiesPerWave = min(45,8 + floor(.35*(w-1)))
SpawnIntervalSeconds = clamp(1.6 - .007*w, .35, 1.6)
SpeedMultiplier = min(1.60, 1+.006*(w-1))
```
At most 90 live enemies for solo/duo initially; temporarily throttle spawns rather than deleting unspawned enemy budget. For quad prototype, at most 120 live enemies subject to device testing. Multiplayer count multipliers proposed {1:1.0, 2:1.15, 3:1.3, 4:1.45}; HP scaling and spawn scaling must be evaluated together to avoid compounding difficulty beyond party throughput.

### Infinite kill-responsive pressure (proposal, not implemented)
Only verified, non-summoned hostile kills count as `K`, once per match (not once per player). Let `ExpectedKills(w)` be the sum of configured enemy budgets completed through wave w. Compute:
```text
surplus = clamp((K-ExpectedKills(w))/max(50,ExpectedKills(w)),0,.20)
killPressure = 1 + .30 * surplus          # 1.00–1.06
```
Evaluate at **wave boundaries**, not for each hit; enemies spawned within a wave keep fixed HP. This responds to unusual extra kills without punishing efficient teams with uncontrolled runaway HP. Infinite pressure is predominantly wave-based. For a future kills-first variant, use a virtual wave derived from kills **instead** of stacking independent exponentials. Never count boss-generated farmable minions toward `K`.

### Boss events
- Implemented (MVP Trial, endless, no win): a boss every 5th wave (5, 10, 15, ...) with the Boss HP multiplier (10 + 1.5 per boss so far), plus a Brute mini-boss on waves 3, 8, 13, ... 33 then every even wave from 36 (5 + 1.5 per mini-boss so far); see [WAVE_SCALING.md](WAVE_SCALING.md) and MVP.md. Later staged-World targets: wave 10,20,30,...100; final boss must die for stage completion.
- Infinite: wave 110,120,130... OR +400 eligible kills since the previous boss, whichever occurs first. **Exactly one** boss event if thresholds coincide, then reset the kill target. Transition after World 1 wave 100 does not double-spawn.
- Every 5th non-boss wave can carry an Elite modifier. Telegraph bosses ≥3 seconds ahead.
- Implemented: 3 lives; Grunt/Runner breach -1, Brute/Boss -2; zero lives ends the run. Proposed for the full game: 20 team lives; ordinary breach -1, Elite -2, Boss -5.

### Party scaling and fairness
Two players default. Solo campaign clear with a Rare/Epic-accessible deck must remain viable. Team kill MP is credited to each teammate at `0.75+0.25/n` of normal kill value (rounded with fractional accumulators); kill MP is paid by wave band (MVP.md), no wave stipend. Separate Solo/Duo/Trio/Squad leaderboards; launch only Solo/Duo ranked until 3–4-player tests pass. Evaluate threats against modeled actual total player DPS, not assumed identical players.

## 2. Dice damage, pips and merge
```text
attacksPerSecond = rate * PipRate[pip]        # PipRate = {1,2,3,4,5,6,7} (*tune*); each pip is its own shooter; 7 is ★
tierMult(t) = 1 + DamagePerTier*(t-1)         # t=1...5 (in-match Power Up); DamagePerTier = 0.10 (*tune*)
hitDamage = max(1, floor(baseDamage*perk*tierMult)) + flat proc   # no pip term; the per-die-level bonus is NOT implemented
```
Merge **two dice of the same identity AND same pip (1–6)** to produce a single pip+1 dice at target, with its type re-rolled from five equipped deck dice; pips cap at 7★. Build-around effects can override explicitly but must obey transaction caps. Pips raise the attack rate only (7★ fires 7x as often as 1 pip); damage per hit does not depend on the pip. `Balance.MaxAttacksPerTick` (8) bounds attacks per die per simulation step and stays above the fastest possible die (rate x 7 x (1 + AuraCap) x 0.25 s, spec-checked). Projectile count, DoT and slow utility count toward balance, not merely hitDamage. All status stacking is capped (slow 45%; vulnerability 25%; armor shred 30%) and dangerous feedback loops have an internal cooldown and max proc depth.

**In-match Power Up (implemented, *tune*):** per die type of the match deck, tier 1-5; the server pays MP through `Rules/Economy` (`Match.TryPowerUp`, remote `PowerUp`). Buying tier t+1 costs `Balance.PowerUp.Costs[t]` = 100 / 200 / 400 / 700 MP (the one sourced Random Dice table; 225 / 450 / 900 / 1800 also met every target in the simulator at DamagePerTier 0.15). Each tier adds 10% of base hit damage to every die of that type, on the board now and summoned or merged in later. It lives only in the match state, resets each match, is never saved and never costs Gems or Robux.

**Aura dice (implemented, *tune*):** one effect, `aura = {base, perPip, perTier}` in the die config: an attack-speed bonus to the four orthogonal neighbours (5x3 board, no row wrap) of `base + perPip*(pip-1) + perTier*(tier-1)`. Beacon uses 0.06 / 0.01 / 0.01. A die's total received bonus is capped at `Balance.AuraCap` = 30%; the bonus is recomputed from the board every step (no accumulation, no procs).


## 3. In-match MP (separate from persistent Gold and Gems)
Starting MP: 100 (exactly four summons). Summon cost after `s` successful summons:
```text
cost(s) = 10 + 10*s                            # 10, 20, 30, 40, ...
```
Base kill MP: Grunt 15, Runner 15, Brute 25, Swarm 5, Elite 40, Boss 150, adjusted for player count. In-match upgrades for one dice type cost 225 / 450 / 900 / 1800 MP, cap 4 tiers. Match MP and temporary upgrade tiers **never persist** and **cannot be bought with Robux or Gems**. If summons become unaffordable too soon, lower the cost step or add wave stipend, not paid MP.

## 4. Persistent economy
| Currency/resource | Earned from | Used for |
|---|---|---|
| Gold | Match completion, dailies, first-clears, achievements | Standard shop, Common/Rare dice, common chests, levels, crafting fees |
| Gems | Achievements, first-clear, events, quests; optional Robux packages | Premium chest, cosmetics, limited premium dice choices, reroll |
| Verdant Fragments | World 1 encounters, bosses and quests | Targeted World 1 dice crafting |
| Universal Dust | Duplicates, chest rewards, challenges | Rare/Epic/Legendary/Mythic crafting |
| Dice copies | Chest, shop, stage, crafting | Persistent dice levels |
| MP | Kills during a match only | Summons and temporary match upgrades |

**Proposed starter grant:** 500 Gold, 50 Gems, five Common dice, one tutorial chest.  
**Stage reward seed (proposal; the MVP run pays 5 Gold, 10 XP, 1 Fragment and 1-3 Gems (Random Dice co-op's card schedule) per wave cleared, no win bonus):** 50+3×waves completed Gold; 40+4×waves completed XP, reduced on repeated clears. First-clear wave 20 guarantees a Rare selection; wave 60 an Epic selection; wave 100 a Legendary blueprint selection + 200 Gems + 800 Gold. Future worlds may unlock via first-clear achievements. Rewards must be idempotent: clear flags prevent reclaims.

**Craft seed:** Rare 80 Verdant Fragments + 300 Gold; Epic 250 fragments + 100 Dust + 1,200 Gold; Legendary 900 fragments + 500 Dust + 5,000 Gold + blueprint; Mythic 2,000 fragments + 1,500 Dust + mastery schematic + 12,000 Gold. Every rarity up to Mythic has an achievable non-Robux unlock route. Secret remains unobtainable at launch.

**Persistent leveling:** levels 1–7 (`Progression.DieLevel.Max`, *tune*). Implemented: copies needed 1, 1, 1, 2, 2, 3 for 1→2 … 6→7 (total 10, every rarity, spare copies of the same die), no Gold. Proposal, not implemented: for advancing from level `l` to `l+1`, copies needed `max(1,floor(l/2))`, Gold `100*l^1.55*rarityCostFactor` (round to whole coin), where factor Common=1, Rare=1.6, Epic=2.8, Legendary=5, Mythic=8. Level bonuses must remain small to avoid account-power dominance in Ranked.

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
| Starting MP | 5 | +10 | +50 |
| Gold Gains | 5 | +2% | +10% |
| Profile XP Gains | 5 | +3% | +15% |
| Boss Materials | 3 | +2% | +6% |
| MP/Kill | 5 | +1% | +5% |

Costs: each rank `200*2^(rank-1)` Gold for economy tracks, `500*2^(rank-1)` for combat tracks (proposal). Combat effects are capped in Infinite ranked; consider normalized ranked presets. Never sell combat-only upgrade ranks exclusively for Robux.

## 7. Leaderboard score and abuse prevention
Rank **highest fully completed wave**, then total eligible enemies defeated, then shorter verified run duration, then earliest completion. Separate Solo / Duo and seasonal / All-time; season reset archives past best. For duo runs both players may receive record credit, flagged with same server run ID; never count duplicates as independent team records in team standings. Verify all score math on server; stamp build version, deck IDs, profile loadout, party size, start/end times, wave/kill audit and server session ID. Batch OrderedDataStore writes and handle budgets/backoff.

## 8. Telemetry & tuning checkpoints
Track clear rates by solo/duo, wave time, damage contribution by dice, percent damage from proc effects, merges/wave, 7★ conversion rate, Gold & Gem income/expense, chest conversion, wave failure causes, over-cap enemies and phone FPS. Initial playtest targets **proposed**: solo 100-wave clear 25–40% of sufficiently progressed non-paying players, duo clear 35–55%, no single dice appearing in >75% of successful decks, no Mythic required, and no paid-reward effect on skill-normalized leaderboard advantage. Re-run automated simulations after each content patch; document tuning changes and avoid silently changing displayed odds.
