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
| **2** | v1.20 | **Treasure Defense** | Protect a shared vault across 30 waves, choose Secure or Greed every five waves, and earn capped rewards | Weekly solo/duo vault-defense leaderboards |
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

## Update 2: Treasure Defense — protect the vault, choose your risk
**Objective:** introduce a distinct, replayable PvE mode where players retain their stationary 5×3 dice boards but defend **recoverable treasure** instead of traditional lives. This mode centers on **vault theft, risk-versus-reward choices, and efficient defense**, rather than simply completing 100 waves or surviving indefinitely. All values below are **initial tuning proposals**, not tested final numbers.

### Mode rules and match structure
- Queue **solo or duo** (two-player primary). Every player brings their normal five-dice deck and keeps their own fixed **5-column × 3-row, 15-slot board**. Dice never walk, escort objects, leave the board or move around the map except through existing merge/ability mechanics.
- A shared **vault at the end of a single readable enemy path** starts with **1,000 Vault Treasure**. This is a **match-only score resource**, not persistent Gold: it must never be deposited directly into a player's wallet.
- **30 escalating waves** over an initial target of **8–12 minutes**, with boss encounters at waves 10, 20 and 30. Wave clears advance automatically after a brief break; shared match MP from kills funds dice summons and match upgrades as in campaign. Existing wave difficulty formula applies with a Treasure Defense mode multiplier and validated player-count scaling.
- Monsters that escape steal a defined amount of **Vault Treasure** instead of removing lives. The vault cannot drop below zero. **Vault at zero = defeat**, while defeating the final boss and clearing wave 30 with treasure remaining = full clear. Partial-run payout scales with completed waves and protected treasure but is capped against deliberate early-fail farming.
- Both players defend the same route and treasure; server credits each enemy kill once and grants individual match MP via the usual cooperation rules. Do not make total vault treasure or reward proportional to number of participants.

### Theft and enemy roster
| Enemy | Initial theft on breach | Mechanic / intended counter |
|---|---:|---|
| **Thief** | 15 | Fast, fragile; rewards fast targeting and slows |
| **Treasure Goblin** | 25 | Carries a visible bonus-token icon; killing it grants a small **match-only vault-restoration token**, never unlimited persistent currency |
| **Armored Bandit** | 60 | Slow armored target; encourages pierce / armor-break / sustained DPS |
| **Mimic** | 40 total if all pieces breach | Splits into two smaller enemies upon defeat; each piece steals 20; avoids double-counting theft when split |
| **Vaultbreaker Boss** | 150 | Three telegraphed vulnerability phases, substantial pressure near exit; boss defeat contributes score and a one-time recovery bonus |

Additional bosses can be reskins/mechanic variants at waves 10/20/30. Enemies killed before breach cause no vault theft. Any restoration token is awarded **only once per server-spawned enemy ID**, and tokens from split summons do not recursively generate more tokens. Telegraph thief, bandit and boss theft values on tap/hover.

### Core special feature: Vault Greed
At the end of **waves 5, 10, 15, 20 and 25**, after enemy cleanup, prompt players to choose a mode for the **next five-wave block**:
- **Secure:** no extra enemy threat or added reward multiplier; bank current risk level for this choice. Existing acquired bonus score is preserved; no new Greed modifier.
- **Greed:** increases upcoming enemy threat by **20% for that five-wave block** and adds a **15% bonus to the potential final score/reward factor** for choosing that block. A selected Greed block does **not** apply its enemy buff to the rest of the match, preventing a late irreversible difficulty spike; choosing Greed repeatedly compounds its *end-of-run reward bonus*, with a hard cap.
- Solo chooses directly; Duo votes independently with a visible **10-second** timer and **Secure wins ties or missing votes**. The safe default prevents one teammate from forcing risk onto another.
- Threat modifier applies to the **server-generated enemy threat budget** for the block (health/count/special mix), not both HP and count independently at +20% (which would inadvertently exceed the target). Difficulty remains bounded by enemy concurrency/performance limits.
- **Proposed cap:** at most five Greed decisions; reward factor `G(n)=min(1+0.15n,1.75)`. Secure decisions do not remove prior bonus; final rewards require surviving full blocks so leaving immediately after selection earns no extra payout.
- UI announces next Greed block's modifiers, expected theft risk, existing bonus and capped potential reward before choice. It must never display the risk bonus as guaranteed Gold.

### Scoring and reward economy
Keep three strictly separate ledgers:
1. **Vault Treasure** (1,000 starting, stolen/restored during this match): gameplay health/score resource, never persistent wallet balance.
2. **Match MP** (from killed monsters and wave stipends): buys summons and in-match upgrades, resets at run end.
3. **Persistent Gold / Gems / materials**: granted only through a server-validated end-of-run reward transaction, with no direct conversion from Vault Treasure.

**Example formula (provisional, independently tuneable):**
- `V = clamp(vaultRemaining / 1000,0,1)`
- `C = clamp(wavesCleared / 30,0,1)`
- `G = min(1 + 0.15 * completedGreedBlocks,1.75)`
- `CompletionFactor = 0.25 + 0.75*C`
- `GoldReward = floor(BaseGold * CompletionFactor * (0.20 + 0.80*V) * G)`
- Only count **fully survived Greed blocks**. On defeat, cap `GoldReward` to a non-clear partial-reward ceiling. `BaseGold`, difficulty bands and daily diminishing returns need economy simulation; this is **not** a promise of 1:1 conversion from protected treasure.

Materials earned at boss milestones are escrowed, with run-end award and once-only claim IDs. Gems come from **capped first-clear/weekly challenges**, not unlimited repeat runs. Additional chest rolls for 3+ completed Greed blocks must disclose odds, pity and eligibility, and use an earnable route. Keep paid and free rewards mechanically fair.

**Example:** finishing with 750 of 1,000 treasure protected, all 30 waves, and two successfully completed Greed blocks produces `GoldReward ≈ BaseGold × 1 × 0.80 × 1.30 = 1.04 × BaseGold` before daily caps. This is a reward factor, *not* 750 persistent Gold.

### Leaderboards and replayability
- Distinct **weekly Solo** and **weekly Duo** rankings; weekly season rotation resets a leaderboard, not profiles or owned dice.
- Score uses **successful wave 30 clear** as a prerequisite for ranked placement (proposed anti-farming gate), then **protected vault remaining**, **number of completed Greed blocks**, and **completion time** in that order. **Alternative for testing:** rank by a normalized composite score that rewards Greed enough to discourage only ever selecting Secure. Choose one transparent formula after simulations. Never place a failed run ahead of a complete one.
- A single server-signed run ID and stored profile/party/weekly seed protects against duplicated score submissions; kills count once and players cannot claim chest rewards twice. Paid purchases grant no competitive score advantage.
- Replay hooks: weekly enemy variants, special thief events, rotating vault cosmetics, Greed challenges and weekly missions. New maps may introduce different theft mechanics without changing stationary board controls.

### UI and art
- Lobby mode card: duration estimate, solo/duo, expected reward types, weekly leaderboard and stage unlock requirement (proposed: World 1 Wave 30).
- Match HUD: clearly labeled **Vault Treasure** bar, waves 1–30, theft warning icons, upcoming bosses, Greed/Secure vote panel, earned reward *projection* (not wallet balance), match MP, summon/merge controls, and normal stationary 5×3 player board. Keep battle path visible.
- Enemy theft value should be visible via one tap. Large boss warning must not cover the board. On phones, 44px minimum interactive targets, no clipped text, clean frames and accessible color-independent status icons.
- All new UI visuals must be **generated using ChatGPT image generation**, unless owned existing assets can be modified cleanly. If new dice are added later, generate each dice's original UI portrait and a large clean exploded **3D modeling breakdown sheet** following [ART_PIPELINE.md](ART_PIPELINE.md). Never splice unrelated existing graphics.

### Technical implementation and balancing safeguards
- Server alone mutates vault value, theft, enemy ID/kill credit, wave counters, Greed votes, rewards and leaderboard records. Make a breach and split-enemy resolution atomic so each enemy steals at most once.
- Monster-kill rewards must not enable infinite restoration or Gold gain; spawned minions and duplicate deaths may be excluded from restoration. Set maximum enemies and pooled VFX limits for mobile.
- Tune solo and duo separately with **same target completion rate at equivalent attainable deck investment**, rather than doubling enemy HP mechanically.
- Verify risk increase is multiplicative only once on the enemy threat budget and is applied to the next five waves only. Greed reward cap and anti-AFK protections must pass economy tests.

**Production scope:** one existing-path-derived treasure map with vault endpoint; 30 wave definitions; five theft-aware enemy types and 3 boss appearances/variants; Secure/Greed voting and threat-budget modifiers; reward ledger and theft resolution; solo/duo weekly leaderboards; loot/crafting integrations; generated UI assets and tutorial.

**Acceptance criteria:** stationary boards and existing merge rules unchanged; vault theft/restoration is deterministic and server-authoritative; zero vault ends run; fully clearing wave 30 with vault > 0 wins; no Gold/MP/Vault ledger conflation; solo/duo Greed voting cannot be forced by one player; partial rewards never outperform full clears through deliberate losses; every offered reward is achievable without Robux; leaderboard anti-cheat and once-only receipt/reward tests pass; low-end mobile text and controls readable; duration and win rates verified through playtesting.

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
- Whether Treasure Defense unlocks at World 1 Wave 30 or after a first world clear; tune the vault's starting treasure, thief theft values, Greed score incentives and weekly ranking tie-breakers through simulations.
- Whether PvP is best with player-sent mobs or mirrored survival-only tiebreaks; prototype both before locking ranked.
- How competitive seasons reset rank without excessively punishing inactive skilled players.
- Whether four-player raids can maintain low-end phone frame rate, or should use simplified VFX.
