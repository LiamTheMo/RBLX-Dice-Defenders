# Balance and economy

The source of truth is `src/server/Config/` (mainly `Balance.luau`, `Progression.luau`, `Roll.luau`, `Shop.luau`) and `src/server/Rules/Formulas.luau`. Values marked *tune* are placeholders, not playtested. Anything under **Proposed** is not built.

## 1. Enemies and waves

Enemy HP follows the Random Dice model (`Config/CoopWaves`); the full rules, schedule and checkpoints are in [WAVE_SCALING.md](WAVE_SCALING.md). Speeds are Grunt 6, Runner 9, Brute 16/3, Boss 3 studs/s, multiplied by `min(1.6, 1 + 0.006 x (wave - 1))`. At most 90 enemies are alive (`Balance.MaxAlive`). Lives: 3; a Grunt or Runner breach costs 1, a Brute or Boss 2.

Owner targets used by the simulator (`python tools/balance_sim.py [seeds]`, three bot skill levels): a full Common deck ends around wave 20, Rares 30, Epics 40, Legendaries 80 (the tutorial run clears wave 10); gems per wave equal the Random Dice co-op card schedule. Re-run the simulator after changing any balance number.

## 2. Dice damage

- Attacks per second = `rate x pip`; no pip term in damage. Hit damage = `max(1, floor(base x perk x tier multiplier))` plus a flat proc.
- Power Up (in match, per die type): tier 1 to 5, tier multiplier `1 + 0.10 x (tier - 1)`, buying the next tier costs 100 / 200 / 400 / 700 MP. Never saved, never bought with Gems or Robux.
- Aura: per-die total attack-speed bonus capped at 30% (`Balance.AuraCap`).
- Per-pip DPS is about 300 Common / 800 Rare / 3300 Epic / 23000 Legendary, with the abilities in [DICE_CATALOG.md](DICE_CATALOG.md); derivation and targets in [DICE_REBALANCE_PROPOSAL.md](DICE_REBALANCE_PROPOSAL.md).
- Die levels give no damage today. Each step adds account crit damage only (used by Astral). **Proposed, owner decision pending:** a small damage bonus per level. Stronger decks otherwise stall around wave 25 because boss HP grows linearly with the wave.

## 3. Match MP

- Start 100 MP; summon `10 + 10 x summons` (10, 20, 30, 40 ...).
- Kill MP by wave band: 10 (1-5), 20 (6-10), 30 (11-15), 40 (16-20), 50 (21+). Brute x5, Boss x10. No wave stipend.
- Duel uses its own SP rule (see [DICE_RATING.md](DICE_RATING.md)).

## 4. Run rewards (paid once per run id, `Rules/Quests.SettleRun`)

Per wave cleared: 5 Gold, 10 account XP, 1 Verdant Fragment and Gems. Gems per wave are the Random Dice co-op card schedule x10 (`Balance.WaveGems`, `Formulas.WaveGems`):

| Waves | Plain wave | Brute wave | Boss wave |
|---|---:|---:|---:|
| 1-35 | 10 | 20 (wave % 5 == 3) | 30 (wave % 5 == 0) |
| 36 on | 0 | 20 (even waves) | 60 (odd waves) |

Gems are then multiplied by the Challenge Tier: x1 up to wave 111, x2 from 112, x3 from 500, x4 from 1001, x5 from 1501. Tier HP, speed and boss cooldown factors are 1.0 and unused until the owner gives numbers. A run may report at most 5000 waves.

A Duel pays XP and Gems per cleared wave (max 20 waves): the winner the Solo amounts, the loser 40% of the XP and no Gems, a bot match half. See DICE_RATING.md.

## 5. Currencies and resources

| Resource | Earned from | Used for |
|---|---|---|
| Gold | Run rewards, login calendar, quests, milestones, codes, Duel streaks, selling materials | Die level-ups, Shop |
| Gems | Run rewards, quests, achievements, milestones, mastery, login calendar, codes, Robux packs | Rolls, Shop |
| Verdant Fragments | Runs, Shop | Sold for 2 Gold each; no crafting yet |
| XP Tome | Login, milestones, mastery, Shop | Use for 100 account XP (no sell price, so Gems cannot become Gold) |
| Gold Pouch | Login | Use for 200 Gold |
| Dice Shard | Tutorial gift | One shard becomes one spare copy of an owned die |
| Dice copies | Rolls, milestones, login, Starter Pack | Level-ups |
| MP | Kills | Match only |

Account level: 1 to 50, `100 x level` XP per step. Rewards never change a profile unless the whole bundle fits (counters cap at 1,000,000,000) and never come from the client.

## 6. Die levels

Levels 1 to 12 (`Progression.DieLevel`). Each step costs spare copies of that die and Gold; a rarer die starts further up the same Gold and crit curves (offset Common 0, Rare 2, Epic 4, Legendary, Mythic and Secret 6).

- Copies per step (1 to 12): 1, 2, 4, 8, 15, 25, 40, 60, 90, 130, 200.
- Gold per class step: 5, 10, 25, 50, 100, 200, 400, 800, 1500, 3000, 6000, 10000, then 15000 to 80000 for the highest classes.
- Account crit damage per class step: 1, 2, 2, 3, 3, 3, 4, 4, 4, 4, 5, then 5 for the rest.

Mastery: Mastery XP per owned deck die = waves completed; need `5 x level` per step, max level 20; levels 5 / 10 / 15 / 20 pay 20 Gems / 30 Gems + XP Tome / 50 Gems / 100 Gems once per die.

## 7. Roll and Shop

Roll, Standard pool: 1 roll 100 Gems, 10 rolls 1000 Gems, at most 50 rolls at once. Odds per roll: Common 58.89%, Rare 30%, Epic 10%, Legendary 1%, Mythic 0.1%, Secret 0.01%. A rarity's dice are drawn uniformly. Pity: the 80th roll in a row without a Legendary is one. VIP game pass (299 Robux): every roll 10% cheaper. Rolls are blocked for players whose Roblox policy restricts paid random items. The client sends only (pool, count); odds, prices, pity and the RNG stay on the server.

Shop: XP Tome 300 Gold; 20 Fragments 100 Gold; 3 XP Tomes 40 Gems; Robux Starter Pack (399 Robux: 1200 Gems, 2000 Gold, 1 Frost, once per account) and Gem packs 400 / 1200 / 3500 Gems for 99 / 249 / 699 Robux. Robux offers have no developer product id yet, so they show "Not available yet". Spec rule: nothing sells for more Gold than it cost, and nothing turns Gems or Robux into Gold.

Quests (S1-S3 one-time, D1 daily, W1 and W2 weekly), the login calendar (Day 7 pays 1000 Gold, 100 Gems and 2 XP Tomes), play milestones (P10 to P100) and achievements (A1-A5) are listed in `Config/Quests`, `Daily`, `Milestones` and `Achievements`. Daily resets at 00:00 UTC; weeks start Monday 00:00 UTC; a skewed clock never reopens a claimed period.

## 8. Rate limits

Every remote has a token bucket per player (`Balance.Remotes`) and a kick threshold of 20 hard violations. Redeem codes lock a player for 15 s after 5 failed guesses, doubling up to 600 s, with a kick at 50.

## Proposed (not built)

- Enemy classes Swarm, Shield, Regenerator and Elite with their own HP multipliers; kill-responsive "Infinite" pressure; 20 team lives with Boss breach -5.
- Multiplayer scaling beyond two players; per-player kill MP shares for 3 to 4 players.
- Chests with disclosed odds and pity, a Universal Dust and crafting economy, a rotating shop, permanent profile upgrade tracks (Global Damage, Starting MP, Gold, XP, MP per kill), and a leaderboard score (highest completed wave, then kills, then time).
- Rewards for staged first clears (a Rare at wave 20, an Epic at wave 60, a Legendary at wave 100) in place of the current play milestones.
- Telemetry targets: clear rates by party size, damage share per die, merges per wave, 7-pip conversion, phone FPS.
