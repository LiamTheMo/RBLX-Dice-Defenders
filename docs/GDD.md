# Dice Defenders — Game Design Document
**Repository:** LiamTheMo/RBLX-Dice-Defenders  
**Design version:** 0.1 (preproduction) · **Status:** Proposed unless marked **Locked**  
**Platform:** Roblox · **Genre:** Co-operative dice-merging lane defense, collection, progression  
**Related specifications:** [Dice Catalog](DICE_CATALOG.md), [Balancing & Economy](BALANCING.md), [Art & Production](ART_PIPELINE.md)

> This document distinguishes the creator's locked product requirements from recommended starting values. All numerical tuning, names, drop probabilities and time targets are provisional until playtests. All dice, cosmetics, names, UI and 3D references must be original rather than copied from Random Dice or other games.

## 1. High concept and pillars

Players equip a five-dice deck, enter a themed world, summon randomly selected dice onto a **5-column × 3-row board (15 cells)**, earn **MP** from monster kills, strategically merge dice and survive waves with one to four players. Finish **Wave 100** on the first world to earn its clear rewards; compete on a separately tuned **Infinite** mode with ranked leaderboards. Collect, craft and upgrade dice using persistent Gold, Gems, materials and copies. New worlds, bosses and dice interactions should create genuinely different strategies.

**Locked:** first world with Wave-100 clear, Infinite mode and leaderboards; solo and two-player support; four-player considered with scaling; two persistent currencies (Gold and Gems) plus independent match-only MP; six rarity definitions (Common, Rare, Epic, Legendary, Mythic, Secret); 5 Common, 5 Rare, 5 Epic, 3 Legendary, 1 Mythic dice targeted for first release; 5×3 board; pips 1–7, with 7 displayed as a star; dice obtained from progression, shops, crafting, events and chests; abilities can trigger on hits, merges, timers, positioning, pips and conditions; ChatGPT-generated UI and dice art with 3D breakdowns.

**Scope interpretation:** the user's "Common through Legendary initially" and "1 Mythic for release" can both be honored by shipping Mythic as a **single late-game chase reward after initial MVP validation**. Secret is schema-defined but unobtainable at launch. Release target is 19 dice; MVP content gate is 18 if the Mythic's implementation is not ready, with the nineteenth delivered before public 1.0.

### Design pillars
1. **Readable randomness, decisive choices.** Summon outcomes are random, but deck building, board placement, merge timing and upgrades should matter more than luck.
2. **Synergy over raw rarity.** Rares and Epics enable strategies; Legendaries are transformative; Mythic is a desirable build-around, not mandatory.
3. **Short-term strategy and long-term collection.** Match MP is separate from persistent economies.
4. **Scalable co-op.** Two players is the baseline; solo always viable; four-player joins only after performance and balance gates.
5. **Replayability without runaway monetization.** No paid-only abilities, no required purchases, transparent chances and earning routes.
6. **World identity.** Future map geometry, modifiers and bosses make different dice shine.

## 2. Player journey
**First session:** tutorial explains lane path, summon, dice pips, attacks, merging (same type/same pip), deck, boss telegraphs and MP; free starter deck contains five Common dice. Intro stage plays a short practice encounter, then first-world campaign unlocked.  
**Early:** earn Gold/materials, unlock first Rare via predictable stage milestone, improve dice levels, experiment with 1–2 synergies.  
**Mid:** reach Wave 100, craft specific Rare/Epic, unlock repeatable World 1 runs, rotate daily shop, learn bosses.  
**Late:** maximize efficient decks, chase Legendaries/Mythic through deterministic pity/crafting, compete in Infinite, prepare for future worlds.

### Core session loop
Choose deck and mode → matchmake (solo, duo default, optional group) → place dice using MP → kill enemies for MP → adapt positioning, merges and match-level upgrades → survive boss → win at Wave 100 or end Infinite when lives reach zero → receive persistent rewards and progress → craft/upgrade/equip → play again.

## 3. World, stage and map
### World 1: **Verdant Circuit** (working name)
- **One map at launch**, toy-diorama fantasy meadow with five readable player columns, one unmistakable winding monster path, generous attack readability and two boss staging zones; no path hiding behind panels.
- **Staged objective:** defeat the Wave 100 boss and eliminate remaining enemies while team lives > 0. Complete only once per profile for first-clear bonus; repeat runs grant smaller farm rewards.
- **Wave progression:** waves 1–100; minor enemy pressure changes throughout; **boss every 10 waves** (10, 20, … 100), escalating boss families; lighter elite/mutator wave every 5 waves without doubling as a boss.
- **Recommended checkpoints:** waves 1–20 tutorial-friendly; 21–40 status-counter introduction; 41–60 shields/resistances; 61–80 elites and mixed squads; 81–99 high-pressure combinations; 100 world guardian.
- **Future worlds:** separate reward/material tables, visual themes, path lengths, situational modifiers, local boss roster and stage-specific unlocks. Same dice schema and normalized threat budgeting across worlds. World 2 is NOT required for launch.

### Enemy path & breach rule
Enemies travel toward exit; kill before escape. Team starts with **20 Lives** (proposed). Normal breach costs 1, elite 2, boss 5. At zero lives game over. Server controls all path positions, HP, deaths, MP and lives. Bosses may introduce summons, armor, slow immunity windows or ability-lock mechanics; every counter must be readable.

### Wave cadence
Staged: next wave after prior wave cleared and 4 s preparation (proposed); cap wait when a slow enemy stalls. Infinite: same virtual wave system, but **also count cumulative kills** for escalation and boss trigger thresholds. Fixed-wave and kill-threshold bosses must not duplicate: first qualifying event queues exactly one boss, then advances the boss threshold. See BALANCING.md.

## 4. Player counts, combat boards and co-op
- **Solo:** one 15-slot board, one path, 1× enemy threat baseline; 100 waves must be achievable with obtainable Rare/Epic decks.
- **Duo (primary):** two independent 15-slot boards defend the **same shared path/lives**; enemies scale to team DPS without a strict 2× HP wall. Both players see distinct board ownership, teammate pings, and shared boss warnings.
- **Trio/quad (experimental):** maximum four independent boards, one shared path, scaled enemies and spawn budget, stronger server-side projectile batching. Restrict to friends/private queue until performance, fairness and clarity gates pass. Never silently mix duo and quad into the same leaderboard.
- **Separate leaderboards:** Solo, Duo, Trio and Squad if enabled. The default public competitive leaderboard launches Solo and Duo only. Each record stores best completed wave, kills, run duration, loadout checksum, player count, season and verified run ID.
- **Co-op integrity:** no friendly fire; each player owns their MP, summons, merge actions and in-match upgrades; kills distribute MP to all participating players at a reduced per-player rate. Shared kills are counted once for Infinite threat scaling. Disconnect: allow short reconnection period then keep board attacking temporarily or normalize surviving-player threat between waves (not mid-boss); do not grant duplicate rewards.

## 5. Dice deck, board and merging
- Equip exactly **five distinct dice types** from owned collection; sampling is uniformly random among those five initially; odds-changing modifiers must be explicit.
- Board is a 5×3 grid; click/tap Summon → if an empty slot exists, server consumes MP and places a 1-pip random deck die into a server-selected empty slot. This preserves meaningful placement randomness; specialized dice can reposition or transform.
- **Pips:** 1,2,3,4,5,6 and **7★**. Pip count increases effective output through a defined nonlinear multiplier (see BALANCING.md). Use 7★ as the cap.
- **Merge:** two dice with the **same type and same pip**, at pips 1–6, can be dragged together. Remove both, create one die of pip+1 at the target cell, and roll its **new type from equipped deck**. This is deliberate risk: merging does not guarantee preservation of type. Execute on server atomically; never spend both pieces twice. Some dice alter result type through explicit abilities.
- Two 7★ dice cannot merge under baseline rules. Merge-triggered abilities read pre-merge, result and post-merge events deterministically. Distinguish "on merge consumed" from "on merge produced."
- Fill/lock states are clear. If board full, new summon prohibited until merge/move/clear creates space.
- Dice have attack target policy (First, Last, Strongest, Closest) where supported; baseline target First. Default auto-attacks; strategic input should emphasize merges and deck choice, not constant clicking.
- In-match upgrade terminal gives up to 4 tiers for an equipped type (proposed), purchased with MP and reset after run. Persistent level is a separate multiplicative progression system.
- Pip visuals read at phone scale; 7★ never renders seven tiny dots.

## 6. Dice design, rarity and abilities
Defined rarity enum, in order: **Common → Rare → Epic → Legendary → Mythic → Secret**; Secret reserved for future discoverable mechanics and events. **Exclusive** is not part of the canonical rarity ladder here.
- Common (5): straightforward attack stat variants, simple predictable minor perks; all five available in tutorial.
- Rare (5): status effects, chaining, multi-hit, conditional tempo and modest team utility.
- Epic (5): board layout, timing, DoT, summons or merge-driven strategies that change play.
- Legendary (3): powerful archetype-enabling dice with trade-offs/counters and diminishing returns.
- Mythic (1 target by v1.0): star-centric growth / strategic build-around but balanced against strong Epic/Legendary combinations.
- Secret (0 launch): system and UI enum only; do not make unobtainable Secret seem purchasable.
- Full **19 individual dice specifications** (stats, effects, triggers, constraints, synergies, unlock routes and balance roles) live in [DICE_CATALOG.md](DICE_CATALOG.md).

**Universal ability framework:** support always-on, on-hit (seeded probability), on-crit, on-kill, on-merge-source, on-merge-result, on-summon, timer/interval, start/end wave, boss spawn, ally adjacency, row/column alignment, pip threshold/parity, board-full, HP threshold, enemy tags, map tags, and conditional stance. Ability definitions use server-registered IDs, activation predicates, cooldowns, proc coefficients, stacking categories, caps and event budgets. Never trust remote-supplied damage or probability.

## 7. Enemy roster and bosses
Launch enemy tags/classes: Grunt (basic), Runner (fast), Brute (armored), Swarm (many low HP), Bulwark (shield), Wisp (evasion / target retarget), Regenerator, and Elite variants. Introduce tags gradually and telegraph all resistances.
**Boss progression (10 encounters, reuse 4–5 families with variants):** Thorn Warden at 10/50; Stoneback Colossus at 20/60; Clockwork Swarm Queen at 30/70; Mirror Magus at 40/80; overcharged variants at 90 and Verdant Sovereign at 100. Each boss gets 1–2 signature mechanics: e.g. Stoneback temporary armor, Swarm Queen adds, Mirror Magus decoys, Sovereign rotating vulnerability. Show warning at least 3 s before arrival. No permanent dice theft, no unavoidable random board wipe.
**Boss rewards:** staged milestone materials and end-run loot; first-clear Wave-100 reward guaranteed. Infinite bosses grant score and materials with daily caps, not exponentially increasing permanent currency.

## 8. Economy, rewards and monetization
### Currency boundaries
- **Gold (persistent, earnable):** regular rotating shop dice/copies, lower-tier chests, common materials, standard upgrades and crafting fees.
- **Gems (persistent, earnable; premium):** targeted premium chest choices, cosmetics, expedited shop reroll with limits; rare dice purchasing only under clearly priced caps. Avoid hard premium lockouts.
- **MP (match-only):** granted by enemy kills and small wave stipend; buys summons and in-match upgrade tiers; always resets at match end. Never convertible to Gold/Gems.
- **Materials (persistent):** world-specific fragments and universal dust from enemies/bosses/stage rewards; deterministic craft recipes.
- **Robux:** optional premium chest bundles and cosmetic offers; visibly disclose odds before opening, local currency price, duplicates and pity rules. No exclusive power tier or deceptive time pressure. Design for Roblox current commerce/policy requirements before release.

### Acquisition routes
World milestone first-clears → guaranteed dice/copies; repeat runs → Gold/materials; rotating shop → Gold items + limited Gem premium choices; crafting → deterministic dice; events → conditional dice/skins; chests → publicly documented rarity odds plus duplicate protection/pity. Disallow purchased chests granting unreleased Secret dice. Duplicate dice become copies for levels or dust, never disappear.
Proposed economy/prices, loot tables, pity protection and upgrade math: [BALANCING.md](BALANCING.md). Seasonal events must not introduce permanent competitive paywalls.

## 9. Permanent profile progression
Account level from XP earned at match end. Character profile owns unlocked worlds, dice inventory/copies, levels, materials, Gold, Gems, upgrade ranks, quest flags, cosmetics and season stats.
**Proposed permanent upgrade tracks:** Global Dice Damage (5 ranks × +1%, cap +5%); Starting MP (5 × +10, cap +50); Gold Earned (5 × +2%, cap +10%); Profile XP Earned (5 × +3%, cap +15%); Boss Material Yield (3 × +2%, cap +6%); Match MP on Kills (5 × +1%, cap +5%); optional reroll utility purchased only via play. Track price ramps and avoid unbounded compounded damage.
Permanent upgrades may make campaign faster but ranked Infinite either **normalizes profile power** or uses progression brackets; initial proposal: global damage benefits capped at +5%, leaderboard records display profile level, and seasons offer normalized challenge presets.

## 10. Infinite mode
Unlocked after World 1 Wave 100 clear (recommended); uses same core wave and enemy-HP functions as campaign extended beyond 100, but adds a **cumulative kill-pressure factor** and periodic boss triggers. Score prioritizes deepest fully completed wave; ties: enemies defeated, then shortest run duration, then timestamp. Record best score, not sum. Run ends on zero lives, voluntary surrender or validated disconnect.
To prevent kill-farming abuse: only server-spawned hostile enemies count once; summoned adds from bosses are explicitly tagged non-scoring unless intended; no player-created kill loops. Kill-pressure is monotonic, bounded per wave to avoid accidental spikes, and independent of extra players' duplicated kill credits.
Leaderboard categories are per player-count and per season, with separate All-Time displays. Store only validated best runs; use Roblox OrderedDataStore sparingly with batched updates and rate-limit/backoff. Anticheat verifies run trace summary, claimed wave/kill totals and session identity.

## 11. UX and information architecture
**Lobby:** Play (World 1 / Infinite), Deck, Collection, Dice Upgrade, Craft, Shop, Chests, Profile, Leaderboards, Settings. Show locked worlds/rarities without false promises.
**Match HUD:** path unobstructed; top wave + progress + boss countdown; team lives and teammate status; bottom center 5×3 player board with non-overlapping dice detail popup; Summon button, MP balance, next summon price, compact in-match dice upgrade row; boss warning and ability cues; merged 7★ star indicator.
**Dice detail:** name, rarity, level, pips, base stats, triggers/proc conditions, stacking limits and targets; compare at next level. **Shop:** clearly separate Gold/Gem/Robux offers and show odds. **Leaderboards:** season, player count, wave, kills, time, verified status.
**Accessibility:** readable on phone landscape, 44 px minimum interactive targets, contrast and non-color rarity cues, reduced FX, scalable text with overflow handling, haptics optional. No UI assets assembled from unrelated stock sprites; see art contract.

## 12. Technical system specification (proposed)
**Server-authoritative modules:** MatchService, QueueService, WaveDirector, EnemyService, DiceService, MergeService, AbilityRuntime, DamageResolver, EconomyService, RewardsService, ProfileService, ShopRotationService, CraftingService, LeaderboardService, AntiExploitService.  
**Shared data definitions:** DiceDefinition, AbilityDefinition, EnemyDefinition, BossDefinition, WorldDefinition, RewardTable, ShopOffer, ProfileSchema, VersionedBalanceConfig.  
**Client:** camera/board rendering, drag/tap placement requests, combat VFX pooling, readable hit feedback, menus, controller/touch support.  
**Persistence:** DataStore profile versioning and reconciliation; session-lock to prevent concurrent overwrites, idempotent reward grants, transactional purchase receipt handling, retry/backoff. Never persist a match as a source of arbitrary client currency.  
**Combat performance:** deterministic tick/batched update; cap attack proc recursion depth and chain jumps; projectiles may be visual client-side but hit truth stays server-side; pool enemies, effects and floating numbers. Favor <100 simultaneous enemies for initial phone target; load test 4-player mode before public enabling.  
**Anti-exploit:** validate deck ownership, occupied cell state, merge type/pip/coordinates, MP/price, rate limits, trusted RNG, kills, wave, shop purchases, developer product receipts, and reward claims.  
**Analytics:** wave reached per match, failure wave/boss, queue time, deck diversity, pick/win rates by rarity, acquisition funnels, Gold/Gem balance, conversion, crash/performance counters, reconnects.

## 13. Production milestones and acceptance
**P0 systems:** core map, enemy path, waves 1–100, solo+duo, 15 cells, star pips, merge, 18 Common–Legendary dice, economy, progression, bosses, UX, save safety.
**P1 launch content:** nineteenth Mythic if ready, Infinite (solo+duo) with verified leaderboards, Gold/Gem shop/chest loop, crafting, permanent upgrades, tutorial, first-clear rewards, accessible mobile UX, original art sheets.
**P2:** quad private test, new worlds, events, Secret content (only once implemented), seasonal progression and cosmetics.

### Release gates
- Wave 100 can be cleared solo and duo using achievable non-premium decks; no mandatory Legendary.
- Every dice type works with 1–7 pips, persistence levels, tooltip, correct merge outcomes, expected triggers and no infinite proc loops.
- Match MP cannot persist between sessions; persistent purchases, duplicate conversion and receipt replay tests pass.
- 100-wave campaign and high-wave Infinite complete without memory leak, runaway enemy count, unreadable FX or client-authoritative wins.
- Solo/Duo rankings exclude suspicious/unverified results; restart/reconnect never duplicates rewards.
- All UI and dice visuals meet [ART_PIPELINE.md](ART_PIPELINE.md); assets are original and legible on desktop/phone.
- CI/tests applicable to the repository pass; deployment/publishing only from main.

## 14. Decisions to test, not assume
1. A campaign of 100 waves may be too long: benchmark playtime, offer break/save checkpoints only if exploit-safe.
2. Deck sampling and random-pip merge results can be punishing: playtest rescue mechanisms, especially for 7★.
3. Quad scaling must be gated by device and teamwork clarity; do not promise balancing without empirical tests.
4. Define whether Infinite power is normalized or progression-weighted for fair leaderboards.
5. Public odds, monetization, eligibility and UI must be checked against current Roblox requirements before publishing.
6. Exact values in companion documents are hypotheses and should be A/B tuned from observed outcomes.
