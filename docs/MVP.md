# MVP — Verdant Trial (first playable slice)

**Status:** build contract for v0.04. Numbers marked *tune* are placeholders for Studio playtests. Everything outside this file's scope is deferred (see end).

## Scope
- **Solo**, one match per server. Owner = first player whose profile loaded; if the owner leaves, the next loaded player becomes owner and the server returns to Lobby. Non-owners get `Phase = "NotOwner"` and every intent is rejected. Set place max players to 1 for production.
- **Deck:** the profile's equipped deck, exactly 5 distinct owned die types. The starter deck (and the only dice obtainable so far) is C01 Pebble, C02 Needle, C03 Hammer, C04 Twinshot, C05 Longshot (stats/perks from DICE_CATALOG.md; Hammer turn speed omitted; Longshot's +25% range perk is moot under global targeting and awaits a replacement). `Start` plays the server-stored deck; the client never sends one.
- **Lobby (placeholder UI):** shown in Lobby and Ended. Menu Play / Deck / Collection / Quests / Profile; Shop, Chests, Craft, Leaderboards, Settings are greyed "Coming soon". Play: World 1 Trial + Start (the only way to start); Infinite shown locked. Deck: tap a slot, tap an owned die, Save. Collection: owned dice (rarity, level, copies) then the other 14 catalog dice as "Not available yet". Ended shows a dismissable results card (result, wave, Gold). Single place, solo: no queue, party or teleport.
- **Quests** (server-only `Config/Quests.luau`, Gold *tune*): S1 finish a Trial run (RunsPlayed ≥ 1) 50; S2 clear wave 5 (BestWave ≥ 5) 100; S3 clear the Trial (TrialCleared) 250; D1 daily: defeat 150 enemies today 100. One-time progress is derived from the stats only the run reward writes; the daily counts server kills (deaths by damage, never breaches) of Won/Lost runs, added in the same run-id-gated settle as the reward. UTC day = `floor(os.time()/86400)` on the server; effective day = `max(today, Daily.Day)`, so a skewed clock never reopens a claimed day; the daily rolls only at settle. Each quest pays once (per day for D1).
- **Board** 5×3 (cells 1..15, row-major). **Summon:** costs `min(250, max(10, floor(10*1.085^s)))` Energy (`s` = successful summons this match); places a pip-1 die of a random deck type in a random empty cell. **Merge** `from → to`: both occupied, same type, same pip, pip ≤ 6, `from ≠ to`; `from` is cleared, `to` becomes pip+1 with a type re-rolled from the deck. Pip 7 shows as **7★**.
- **Energy:** start 43 (exactly the first 4 summons: 10+10+11+12; playtest feedback); kill Grunt 3 / Runner 3 / Brute 5 / Boss 30; stipend `6 + floor(w/10)` after each cleared wave.
- **Waves 1–10.** Count `min(45, 8 + floor(.35*(w-1)))`; spawn interval `clamp(1.6 - .007*w, .35, 1.6)` s; speed multiplier `min(1.6, 1 + .006*(w-1))`; HP `round(80 * (1 + .018*(w-1)) * typeMul * bossMul)` with Grunt 1, Runner .70, Brute 3.0 (armored), Boss 12. Composition for spawn index `i` (1-based): Brute if `w ≥ 5 and i % 5 == 0`, else Runner if `w ≥ 3 and i % 3 == 0`, else Grunt. Wave 10 spawns the **Thorn Warden** boss first, then the normal budget. Max 90 alive (spawns wait, never dropped).
- **Cadence:** first wave starts 4 s after Start; each next wave 4 s after the previous one is cleared. When the next wave is 10, `BossAt` is set at the start of that prep (4 s warning).
- **Lives** 20; breach −1, boss −5. **Lost** at lives ≤ 0. **Won** when wave 10 is cleared.
- **Combat:** dice auto-attack, and every die targets the alive enemy **closest to the exit** (greatest path distance) anywhere on the path; there is no range limit (playtest feedback). `hitDamage = max(1, floor(base * pip^0.85 * perk))`. Perks: Pebble ×1.05 vs Grunt; Hammer ×1.12 vs armored; Longshot ×0.9 vs Boss; Needle every 6th hit of that die instance +8 flat; Twinshot two shots at ×0.7 each (second goes to the next-closest-to-exit alive enemy, else the same target). Cooldown does not bank while idle; max 2 attacks per die per tick.
- **Reward** at match end (Won or Lost; not on abort): Gold `50 + 3*wavesCompleted`, exactly once per run id. Also BestWave, RunsPlayed, TrialCleared.
- **Speeds (*tune*):** Grunt 6, Runner 9, Brute 4, Boss 3 studs/s.
- **Dice visuals:** white cube with dark type-tinted pips on the top face in standard 1–6 layouts; 7 is one large gold star; type colour also on a band around the lower sides. Selected die lifts with a yellow outline; valid merge partners get a white outline.
- **Framing:** the path hugs the board and the camera is fitted so path, board and boss clear the HUD at 1235×739, 844×390 and 667×375 (dice ≈ 65 px desktop, ≈ 34 px phone).

## Layout (Rojo, same tree as the owner's other projects)
`default.project.json`: `src/shared` → ReplicatedStorage.Shared, `src/server` → ServerScriptService.Server, `src/client` → StarterPlayerScripts.Client, `Players.CharacterAutoLoads = false`.

| Path | Responsibility |
|---|---|
| `src/server/init.server.luau` | Boot Services via Loader (from Build-a-Dungeon) |
| `src/server/Config/{Dice,Enemies,Balance,Quests}.luau` | All balance numbers, starter deck, rate limits, kick threshold, quest catalog. Server-only. |
| `src/server/Rules/Deck.luau` | Pure `Shape(ids)` (remote validator), `Check(owned, ids)`, `Equip(profile, ids)` |
| `src/server/Rules/Quests.luau` | Pure `Day(now)`, `View(profile, now)`, `Claim(profile, id, now)`, `SettleRun(profile, runId, waves, won, kills, now)` (wraps `Economy.GrantRunReward`) |
| `src/server/Rules/Formulas.luau` | Pure formulas above |
| `src/server/Rules/Board.luau` | Pure summon/merge; validate fully before mutating |
| `src/server/Rules/Match.luau` | Pure `New(runId, rng, now, deck)`, `Step(state, now)`, `TrySummon`, `TryMerge`; outbox `state.out` |
| `src/server/Rules/Economy.luau` | **Only** code that changes Energy or Gold: `TryChange(record, key, delta)`, `GrantRunReward(profile, runId, waves, won)` |
| `src/server/Rules/Validate.luau` | `IsInt(v, lo, hi)`: rejects non-number, NaN, ±inf, non-integer, out of range |
| `src/server/Rules/{ProfileSchema,SessionLease}.luau` | Profile v2 + MIGRATIONS (v1→v2); lease (from Build-a-Dungeon) |
| `src/server/Infrastructure/{DataStoreGateway,InMemoryDataStore,ProfileStore}.luau` | Session-locked saves (from Build-a-Dungeon, require paths only) |
| `src/server/Infrastructure/{RemoteGuard,Net}.luau` | Guarded remotes (adapted from Build-a-Dungeon) |
| `src/server/Services/ProfileService.luau` | Load/lease/autosave/release/BindToClose (trimmed from Build-a-Dungeon) |
| `src/server/Services/MatchService.luau` | Owner, remote handlers, 10 Hz tick, State/Enemies/Meta pushes, reward + quest settle + save |
| `src/shared/Core/{Loader,Signal}.luau`, `src/shared/Net/Remotes.luau` | Boot, signal, remote names |
| `src/shared/Layout.luau` | Geometry only: `CellPosition(i)`, path waypoints, `PathLength`, `PositionAt(dist)`, camera |
| `src/shared/Display.luau` | Dice names/colours/rarity, locked catalog dice (name + rarity only), enemy colours, pip label |
| `src/client/Controllers/{NetClient,BoardView,EnemyView,Hud,CameraController}.luau` | Intent sender, rendering, input, HUD |
| `src/client/Controllers/{Lobby,UiKit}.luau` | Placeholder lobby panels (render State/Meta, call NetClient only); shared UI helpers |

Pure modules (`Rules/*`, `Config/*`, `Layout`, `Display`) must run under `tests/luau/prelude.luau`: use `type()` not `typeof`, no `task`/services, take `now` and a `Random` as arguments.

## Server data model
- **MatchState** `{runId, rng, deck (own copy), kills, phase="Playing"|"Ended", result, energy, summons, lives, wave, wavesCompleted, waveState="Prep"|"Active", nextWaveAt, bossAt, queue, qi, nextSpawnAt, enemies, nextEnemyId, board[1..15] = Die|false, nextDieId, lastNow, rewardGranted, out}`. Lobby = no MatchState.
- **Die** `{id, type, pip, cd, hits}`. **Enemy** `{id, kind, hp, maxHp, speed, spawnAt, dist}`; `dist = speed * (now - spawnAt)`.
- **Profile v2** `{Version=2, Gold, BestWave, RunsPlayed, TrialCleared, LastRewardRunId, Dice={[id]={Level 1..10, Copies}}, Deck={5 ids}, Claimed={[questId]=true}, Daily={Day, Kills, Claimed={[questId]=true}}, profileRevision, sessionLease}`; counts are integers in [0, 1e9]; nil → default; bad shape → Corrupt; newer version → NewerVersion (never repaired or overwritten). Sanitising keeps only known dice (the 5 starters are always present), resets an illegal Deck to the starter deck, and keeps only `true` flags for known quests of the right kind. `MIGRATIONS[1]` (v1→v2) keeps every v1 field and adds the defaults; the store writes the result back on load. Level and Copies are stored and shown but have no source or effect yet.

## Tick
`RunService.Heartbeat` in MatchService calls `Match.Step(state, workspace:GetServerTimeNow())` at 10 Hz, `dt` clamped to 0.25 s, inside `pcall` (error → result "Error", no reward). Order: wave advance → spawn → move + breach (lose check) → dice attacks → deaths + kill Energy → wave clear / win.

**Enemy rendering:** server creates no enemy parts. Clients draw each enemy at `Layout.PositionAt(speed * (GetServerTimeNow() - spawnAt))` (exact because the MVP has no slows). HP, hits and deaths are server truth.

## Remotes (client sends intent only)
Every intent is a RemoteFunction (`InvokeServer`; no `InvokeClient` anywhere) returning `(ok: boolean, code: string?)`. Guard order: token bucket per player+remote → validator with **exact** arg count (pcall) → ready (profile loaded, sender is owner) → `seq` integer in [1, 2^31−1] and greater than the last accepted (consumed even if the rules reject) → handler (validates, then mutates, never yields, pcall).
Hard violations (RateLimited, BadArgs, BadSeq, and a client firing a server→client event) are logged (throttled) and kick at 20. Soft rejections (NotOwner, NotLoaded, WrongPhase, NoEnergy, BoardFull, IllegalMerge, BadDeck, UnknownDie, NotOwned, UnknownQuest, NotComplete, AlreadyClaimed, Overflow) are not counted.

| Remote | Kind | Args | Rules | Rate |
|---|---|---|---|---|
| `Start` | RF | `(seq)` | owner, loaded, phase Lobby or Ended, stored deck legal (else BadDeck) | 1/s, burst 2 |
| `Summon` | RF | `(seq)` | Playing, energy ≥ cost, empty cell | 5/s, burst 8 |
| `Merge` | RF | `(seq, from 1..15, to 1..15)` | Playing, merge rules above | 5/s, burst 8 |
| `EquipDeck` | RF | `(seq, ids)`: plain array, keys exactly 1..5, distinct strings of 1–8 bytes (else BadArgs) | not Playing; every id known (UnknownDie) and owned (NotOwned) | 1/s, burst 3 |
| `ClaimQuest` | RF | `(seq, id)`: string of 1–16 bytes | any phase; UnknownQuest, AlreadyClaimed, NotComplete, Overflow | 2/s, burst 4 |
| `State` | RE S→C | snapshot below | on change, ≤ 1 per tick + 1 per intent | — |
| `Enemies` | RE S→C, owner only | batch below | ≤ 10 Hz, only when non-empty | — |
| `Meta` | RE S→C, that player only | lobby payload below | on load, on any profile change, on UTC day change | — |

- **State:** `{Phase="Loading"|"Failed"|"NotOwner"|"Lobby"|"Playing"|"Ended", Energy, SummonCost, Wave, Lives, NextWaveAt?, BossAt?, Result?="Won"|"Lost"|"Aborted"|"Error", RewardGold?, Board={[1..15] = {T="C01", P=1} or false}, Gold, BestWave, RunsPlayed, TrialCleared}`.
- **Enemies:** `{S={{Id, Kind, SpawnAt, Speed, MaxHp, Hp}}, H={{Id, Hp}}, R={{Id, Why="Kill"|"Breach"}}, F={{Cell, Id}}}` — arrays of records only (sparse numeric keys do not survive remotes).
- **Meta:** `{Dice={{Id, Level, Copies}} sorted by Id, Deck={5 ids}, Quests={{Id, Name, Desc, Goal, Progress, Gold, Claimed, Daily}}, DailyResetAt}`; read-only display data.
- Client throttles each intent to ≤ 4/s and keeps a monotonically increasing `seq` shared by all intents.

## Persistence
Live store `DD_Profiles_v1`; Studio uses `DD_Profiles_v1_Studio`, or the in-memory store when Studio has no API access (in-memory is only reachable when `RunService:IsStudio()`). Key `Profile_<userId>`. 120 s lease renewed by each save; LeaseHeld waits up to 130 s; LeaseLost/StaleRevision → profile forgotten, Phase "Failed", no further writes. Saves: match end (after reward), 60 s autosave, leave (release), BindToClose (3 attempts, 25 s). Owner leaving or shutdown mid-match aborts with no reward. Load failure → no board, no rewards, nothing written.

## Specs (`python tests/luau/run.py`)
`net_guard` (malformed-arg matrix per remote, rate limit, replay/out-of-order seq shared across remotes, kick at 20 once, soft rejects not counted, throwing handler safe), `economy` (never negative, rejects NaN/inf/fractions/overflow, reward once per run id), `board` (cost sequence, summon/merge legality, full board, no mutation on reject), `match` (formulas, breach/loss, stipend, boss warning ≥ 3 s, kill Energy, perk damage, First targeting, scripted win, plays only the passed deck, kills exclude breaches), `deck` (shape matrix, unknown/unowned, no mutation on reject), `quests` (derived progress, settle once per run id, claim once, overflow, fake-clock day roll, clock going backwards, yesterday's daily), `profile_schema` (v2 defaults, v1→v2 migration, NewerVersion, field sanitising), `profile_store`.

## Deferred
Co-op, queues/parties/teleports, waves 11–100, elites, boss mechanics, Infinite (Start gets a mode argument when it ships), leaderboards, Rare+ dice and any way to acquire dice (so EquipDeck can only reorder the starters), in-match upgrades, dice level effects, shop/chests/crafting/Gems, materials (Verdant Fragments, Universal Dust), the BALANCING starter grant, account XP/level, tutorial, real lobby art, SFX, VFX beyond a hit tracer, generated art and Blender models. A save edited to a far-future `Daily.Day` keeps the daily locked (never pays extra). Known economy gap: losing early earns more Gold per minute than winning; fix before Gold gets a sink.
