# Future Updates — Dice Defenders Roadmap
**Status:** planning proposal. Update numbers are **content milestones**, not assigned release dates. Version branches are permanent `vX.XX`; `main` is integrated/deployed. Current preproduction baseline is [GDD.md](GDD.md). All new UI and dice visuals follow [ART_PIPELINE.md](ART_PIPELINE.md).

## Guiding commitments
- Each major content update should provide **at least one new gameplay strategy**, not merely higher numbers.
- All new dice receive an **original ChatGPT-generated game UI icon and one large clean multi-view/exploded 3D modeling breakdown**, with distinct ability FX; all UI art generated via ChatGPT unless owned existing assets can be modified cleanly.
- Do not launch Mythic or Secret additions as purchase-only exclusives; unlock routes are earnable. No stat advantage based solely on Robux.
- Every update includes balance/telemetry review, solo/duo fairness, validated leaderboards where applicable, mobile performance audits and updated documentation.
- Proposed milestone identifiers below are **future candidate version names**, not proof that these branches exist or that a corresponding release has shipped.

## Proposed cadence and order

| Update | Candidate version | Headline | New game content | Competitive impact |
|---|---|---|---|---|
| **1** | v1.10 | **The Shattered Isles** | World 2, new Wave-100 stage, special dice and world materials | New path modifiers and deck meta |
| **2** | v1.20 | **Anomaly Trials** | Stationary-board PvE challenge gauntlet | New PvE seasonal leaderboards |
| **3** | v1.30 | **Dice Duel Arena** | 1v1 / 2v2 PvP, rank, cosmetic rewards | Ranked PvP ladder |
| **4** | v1.40 | **Guilds & Raids** | 4-player raid bosses and guild projects | Guild raid rankings |
| **5** | v1.50 | **Starfall Ascension** | Mastery, Mythic pathways, new special dice | More viable endgame builds |
| **6** | v1.60 | **Corrupted Depths** | World 3, difficulty mutators, optional challenge runs | Mutator boards |
| **7** | v1.70 | **Season of Secrets** | First obtainable Secret dice, secrets and quests | Seasonal collection events |
| **8** | v2.00 | **The Grand Dice Update** | New progression arc, multi-world finale, endgame systems polish | Rebalanced seasonal landscape |

Updates 4–8 are flexible. Evaluate retention, monetization fairness and balancing before locking any content or version.

---

## Update 1: The Shattered Isles (first post-launch update)
**Objective:** establish the world-to-world progression system and introduce *special dice* that encourage novel strategies.

### New World 2 — Shattered Isles
- Unlock by completing **World 1 Wave 100**; visually distinct floating island / storm-bridge board.
- **100 new staged waves**, with new enemy families, World 2 material **Storm Shards**, and new boss encounters every 10 waves, culminating in **Tempest Leviathan** at Wave 100.
- Stage mutators: **Gust** (periodic movement boost to enemies), **Static** (unshielded enemies occasionally arc a debuff to adjacent enemies), and **Fractured Lanes** (two short branch segments converge near exit). Branch layout must not hide targeting behavior.
- Stronger enemies by world modifier `WorldHP=1.6` at equivalent wave and distinct boss tags; skill and deck diversity, not just HP, should drive difficulty.
- Clear rewards: new guaranteed Rare choice at Wave 20, special-dice schematic at Wave 60, unique Legendary blueprint at Wave 100, account badge, cosmetic board theme; normal World 1 reward loops remain viable.

### Special dice: proposed initial roster (new dice, not new rarity)
"Special" is a **mechanic tag**, not a rarity above Secret. Tentative five dice, final availability subject to art/ability production:
1. **Gale Dice (Rare)** — on-hit applies Tailwind to another enemy as a tradeoff: briefly speeds one target but causes multi-target splash vulnerability. Enables calculated risk/reward decks.
2. **Stormcall Dice (Epic)** — at 3+ copies in the same column, generate lightning every 7s across that column; strong against Fractured Lane groups, weak when board is dispersed.
3. **Swap Dice (Epic)** — on merge consumed, exchange positions of two random low-pip allies; position-dependent attack buffs make merge strategy more fluid. Limit to once per merge and prevent recursive swaps.
4. **Anchor Dice (Legendary)** — adjacent dice cannot be displaced by specified boss effects and gain +12% slow resistance; provides counterplay to World 2 Gust/knockback bosses at opportunity cost of DPS.
5. **Tempest Dice (Legendary)** — 7★ periodically creates a storm zone with diminishing area DPS against bosses; can be built around without outclassing baseline Legendary deck options.

**Deliverables:** World 2 map/environment, new mobs + boss references, five special dice card images and **five separate exploded 3D modeling reference sheets**, new map HUD effects, material/crafting tables, shop and chest tables with displayed odds, tutorials for map mutators.
**Acceptance:** Wave 100 clear is achievable without the new Legendary; Wave 2 enemy pathing and all new dice procs work solo and duo; World 1 remains relevant and no special dice is a paywall.

## Update 2: Anomaly Trials — stationary-board PvE challenge mode
**Core premise:** a repeatable solo/duo challenge gauntlet where every dice stays on its normal 5×3 board, enemies travel the established defense path, and the strategic puzzle changes through **announced board rules, enemy mutators, and between-round boons**. This must not become a moving-character, escort or room-navigation mode. The player never physically moves around a dungeon and dice never walk between areas.

### Reference and differentiation
Random Dice: Defense (111%) demonstrates stationary dice summoning, merging, leveling and defending waves, with solo, co-op raids and special challenges such as Mirror Mode. This update draws from the **stationary-board challenge format**, but Anomaly Trials' rules, modifiers, names, enemy behavior, UX and art are original. Sources (reviewed 2026-11-06):
- https://play.google.com/store/apps/details?id=com.percent.royaldice
- https://apps.apple.com/ca/app/random-dice-defense/id1462877149

### Session structure
- Queue **solo or duo**, preserving the existing 15-cell board per player, deck of five dice, merge rules, Energy and shared lives. No separate movement controls.
- **Three trials × 10 waves** (30 total), target **12–18 minutes** subject to playtesting. Each 10-wave trial has one mutator pair (board rule + enemy modifier); a boss or elite capstone ends waves 10, 20 and 30.
- At matchmaking, players see the full three-trial sequence, allowing informed deck building. The **weekly seed** determines the same modifiers and boss families for everyone in that mode/party-size category, so rankings are fair. Optionally offer a casual random-seed queue with non-ranked rewards.
- **Board state carries forward intact** after waves 10 and 20: existing dice, pips and placements remain. There is no "carry a selected die" rule and no room transition. Energy persists with a soft cap of 150 (tuning value); players choose a temporary boon and have 10 seconds to prepare.
- Mutators never forcibly merge or delete valuable dice. When a cell is disabled for a trial, it becomes **dormant** (its die is retained but cannot attack/merge until restored); UI previews this before the trial starts. At least nine functional cells remain and mutators cannot hard-lock all copies of a required die.
- At each intermission, choose **one of three temporary boons**; in duo, each player selects independently while both share the next trial's mutators. Boons expire at the end of the run, cannot be purchased for Gems or Robux, and must have stacking caps and readable icons.
- Failure occurs when shared lives reach zero. Reward partial clearing based on completed trials, not exploit-prone raw kills.

### Trial modifier pool (proposals)
| Modifier | Rule | Strategic impact / safeguards |
|---|---|---|
| **Star Alignment** | 7★ dice gain +20% ability output but -15% basic damage | Encourages high-pip specialization without unconditional DPS |
| **Twin Pips** | Attacks get +12% damage for each adjacent ally with same pip, capped +24% | Rewards placement/alignment |
| **Dormant Tiles** | Two previewed board cells stop attacking for this trial | Planning and merge timing; restore afterward |
| **Merge Surge** | Each completed merge grants 5 Energy, max 40 per wave | Encourages tempo merging without infinite loops |
| **Heavy Current** | Enemies have +25% HP but -12% movement speed | Encourages high-impact/boss builds |
| **Quickstep** | Runners move +20% faster, but take +10% status damage | Tests control and damage-over-time |
| **Resonant Rows** | Dice sharing a row with different types gain +5% attack speed per distinct type, capped +20% | Rewards mixed formations |
| **Shield Cycle** | Every eighth enemy carries a shield that must be hit three times; shield hits are capped per attack volley | Elevates rapid/multi-hit decks |

**Modifier exclusions:** no blind disabling of all stars, hard uncounterable immunity, permanent theft of dice, invisible enemy paths, randomized monetized buffs, or ambiguous scoring. Choose modifier combinations from a vetted compatibility matrix.

### Boon pool (eight initial choices)
**Overcharge:** +15% damage for next trial; **Quick Hands:** +12% attack speed; **Bounty:** +12% Energy from kills (capped); **Stabilizer:** dormant dice gain 50% of normal passive aura effect; **Echo Merge:** first three merges per wave refund 8 Energy; **Momentum:** damage +1% per cleared wave in trial, max +10%; **Bulwark:** prevent first two normal breaches of next trial (boss breach not prevented); **Foresight:** preview next two summon types, without allowing client selection. No lasting ownership, leaderboard advantage from purchase, or unbounded stacking.

### Boss, score and rewards
- Wave 10: **Anomaly Sentinel** teaches the current modifier; wave 20: **Fracture Knight** tests board recovery; wave 30: **Paradox Core** shifts vulnerability between short telegraphed phases. Bosses follow ordinary path/breach rules, and their mechanics must not relocate dice.
- Completion score = cleared waves (primary), remaining lives (secondary), then finish time (tertiary). Weekly **Solo** and **Duo** leaderboards are separate; casual queue excluded. All scores are server-validated against seed, modifier list, player count and run ID.
- Rewards: **Anomaly Fragments** for deterministic crafting of cosmetic board effects or utility materials, Gold, capped Gems from weekly milestones, profile challenge badges. Provide partial rewards per completed 10-wave trial, first-clear weekly milestone and daily diminishing returns so repeated farming does not overwhelm campaign economy.
- Mutators are **rules**, not new rarities. Future updates can add challenge combinations, world skins and new enemy types without requiring a different map or moving dice.

### UX and art contract
- Pre-run three-rule preview with 5-dice deck and enemy-counter guidance; in-match mini timeline for trials 1–3; fixed board and path view; clear dormant-cell treatment, active mutator icons with tap tooltips, 10-second boon selection between trials.
- Generate **all new UI assets through ChatGPT image generation**, except owned existing assets that can be modified cleanly. Every new dice added later still requires its own original icon and one large, clean, blown-up 3D modeling breakdown under ART_PIPELINE.md.
- A low-end phone may hide detailed projectile VFX, **never** damage/speed/score truth.

**Production scope:** one fixed trial map using established lane/board systems; 8 mutators, vetted compatibility table, 8 boons, 3 boss variants, one weekly seeded schedule, separate solo/duo rankings, rewards and tutorials. Avoid procedural room generation, escort pathfinding, spatial player movement, and additional full maps.

**Acceptance:** all 30 waves playable with stationary dice; deterministic weekly seeds produce equivalent challenges; no mutator creates unavoidable full-board disablement; valid solo and duo non-premium decks can clear; 12–18 minute target playtested; leaderboard score is verifiable; same-day retries do not duplicate weekly milestone prizes; mobile board and modifier warnings stay legible.

## Update 3: Dice Duel Arena — PvP with rewards and leaderboard
**Goal:** competitive gameplay that doesn't invalidate the cooperative foundation.

### Rules (proposed)
- Separate PvP queue with **1v1 ranked** launch, **2v2** after balance tests. Each player keeps their own **5×3, 15-cell board** and five-dice deck.
- **Asynchronous mirrored-lane pressure, synchronous live match:** defeating server-spawned enemies fills a **Pressure Meter**. At thresholds, choose a visible attack packet (e.g., Fast / Armored / Shielded) to send into the opponent's lane; baseline defense continues on both sides.
- **No direct dice destruction** and no arbitrary paid sabotages. All offense packets have a cap per interval, telegraphed tags, and an equally available counter route.
- **Fairness policy:** in ranked, **normalize persistent dice levels and permanent combat upgrades**. Unlocked dice and deck-building still matter; no additional combat advantage from Robux, chest tier or account age. Provide at least one fully free competitive starter deck.
- 15 team lives, 10–15 minute time limit. On timeout: higher lives wins, then total defended threat budget, then server-deterministic draw. Matchmaking by skill rating + region/latency; never use public lobby server as match authority.
- 2v2 optional: one team score with two separate boards and shared lives; opponent packets target a predictable team lane, not random player punishment.

### Ranks, seasons and rewards
- Provisional ladder: **Bronze → Silver → Gold → Platinum → Diamond → Master → Champion**, with visible rating and match history. Conservative initial placement and smurf/quit protection.
- **Seasonal Solo & Duo PvP leaderboards** separately; global ranking shows verified rating and win/loss stats. Freeze and archive at season end.
- Rewards: Gold, Gems in capped daily/seasonal allotments, exclusive **cosmetic** dice skins, board frames, titles and victory FX; never exclusive stat-bearing dice.
- Daily win rewards subject to participation and anti-bot checks. No rewards for deliberate forfeits. Safeguard disconnect reconnects, AFK farming, matchmaking abuse, repeated opponent collusion and score forgery.
- Ranked balancing should use separate PvP coefficients for stun/slow, summoning and boss pressure, preserving PvE mechanics while preventing unavoidable lockouts.

**Acceptance:** rank writes idempotent, verified fair levels, 1v1 resolves deterministically, declining participation doesn't create unbeatable queue disparities, phone UI supports PvP pressure telegraphs, no monetized combat advantage.

## Update 4: Guilds & Raids
- 4-player **cooperative boss raid**, intentionally scoped separately from campaign so scaling can be handcrafted. Each player's own 15-slot board contributes to shared phases.
- Guild projects contribute surplus world materials for non-combat hall decorations and rotating raid entry options.
- Phase mechanics reward specific utility roles (control, damage, shields, debuff cleansing), not four Mythics.
- Weekly raid leaderboard by fastest clean clear per guild, partitioned by raid difficulty and with anti-carry/fraud rules.
- Unlock new boss families and cosmetics. Do not make full quad campaign matchmaking compulsory.

## Update 5: Starfall Ascension
- **Dice Mastery**: complete meaningful role challenges to unlock alternate **sidegrades** (not unconditional DPS buffs). Example: Frost can choose stronger short slow vs broader weaker slow.
- Add 3–5 dice across Rare/Epic/Legendary/Mythic with counterplay and deterministic crafting recipes.
- Mythic acquisition stays earnable and strategic; meta diversity benchmark: at least four competitive archetypes survive balance passes.
- New star-7 VFX and dice-specific special animations; robust effect pooling.

## Update 6: Corrupted Depths
- World 3 with a Wave-100 clear, cavern branches, darkness/sight rules and bosses that alter target priority; do not conceal enemies unfairly on mobile.
- **Challenge mutators** rotating weekly (No Slows, Limited Merges, Shield Flood, Unstable Board). Pre-disclose all constraints and produce separate challenge leaderboards.
- World-specific drops and cosmetics; previous worlds retain crafting purpose.

## Update 7: Season of Secrets
- Activate the previously schema-defined **Secret** rarity only after ability and economy testing.
- Introduce a **single Secret dice**, with a multi-stage puzzle/quest acquisition path and transparent alternative progression. Avoid monetization-only obtainability.
- Add rotating community events, hidden board challenges and discoverable lore; secrets should not require external websites or exploits.
- Seasonal collection milestones and cosmetics; no Secret required for baseline PvE or ranked parity.

## Update 8: The Grand Dice Update (v2.00 candidate)
- Multi-world finale with boss gauntlet spanning earlier systems, accessibility overhaul, performance passes and a centralized cross-mode season hub.
- Targeted expansions to crafting, clear rewards, new enemies and multi-path strategies driven by telemetry.
- Full economy and ranking health audit, rerun simulator and balance test suite for all dice.

---

## Release operations checklist for *each* future update
1. Update GDD, dice definitions, balance configurations and any new mode specification before implementation.
2. Generate every required **original ChatGPT UI asset** and every new dice's **single large modeling breakdown**; verify completeness.
3. Audit server-authoritative events, economic ledgers, data migrations, loot odds, ranked integrity and performance before opening a test server.
4. Validate solo + duo; validate quad only for an expressly supported mode. Regression test all earlier worlds and modes.
5. Run security, client UX/device, localization/overflow, performance and low-end phone checks.
6. Verify current Roblox paid random item and user eligibility rules before any monetized chest changes.
7. Build and test on the intended permanent `vX.XX` checkpoint branch; complete changes merge into `main`, which is the only production publishing branch. Keep all `vX.XX` branches permanently.
8. Compare live telemetry to declared retention, clear rates, pick rates, and leaderboard integrity targets. Document balance patches by release.

## Items to decide after MVP playtesting
- Whether new World 2 should add 5 dice at once or launch with 3 and deliver 2 through events.
- Whether Anomaly Trials unlock after World 1 or World 2, and whether weekly difficulty tiers need separate matchmaking/leaderboards.
- Whether PvP is best with player-sent mobs or mirrored survival-only tiebreaks; prototype both before locking ranked.
- How competitive seasons reset rank without excessively punishing inactive skilled players.
- Whether four-player raids can maintain low-end phone frame rate, or should use simplified VFX.
