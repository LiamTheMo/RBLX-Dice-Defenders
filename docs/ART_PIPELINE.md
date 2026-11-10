# UI, Dice Art, 3D Modeling and Asset Production Contract
**Status:** mandatory visual-pipeline requirement. This is an asset-production specification, not a claim that images are already created.

## Non-negotiable generation rule
- **All new UI art** must be generated through ChatGPT image generation: full panels, buttons, frames, rarity borders, symbols, icons, bars, backgrounds, prompts, overlays, currency art, shop/chest imagery, HUD elements and gameplay cards.
- Do **not** stitch unrelated stock/old sprites together or construct a "new" design by splicing existing sprites. **Exception:** existing internally owned assets may be cleanly edited or extended if doing so introduces no distortion, clipped detail, seams, copyright uncertainty or inconsistent appearance.
- **Every new dice** needs **ChatGPT-generated UI art AND ChatGPT-generated large single-sheet 3D modeling breakdown** (exploded/blown-up components + orthographic reference views). Never substitute procedural thumbnails, borrowed art or text-only descriptions for these deliverables.
- Generated image ≠ final Roblox model. Artists model in Blender/Meshy/etc. from original references; final exported mesh/texture assets validated independently.

## Art direction (proposed)
Playful readable collectible dice (toy-like bevels, chunky pips, distinctive silhouette). Vibrant magical effects with restrained screen clutter; readable at 48–64px and in a 15-cell phone landscape board. Each rarity adds a recognizable non-color visual language: Common plain etched corners, Rare patterned rim, Epic luminous runes, Legendary floating accent, Mythic celestial rings, Secret masked unknown motif (no launch Secret assets required). Glow should not obscure pip count; 7-pip is a large **star**, visually unmistakable.

## Required dice asset package — 19 release dice
Per each stable ID C01–C05, R01–R05, E01–E05, L01–L03, M01:
1. **UI beauty art**: front/isometric view with pip/star, clean silhouette, 1:1 large render and a cropped inventory card variant, both generated with ChatGPT image generation; no label embedded unless requested.
2. **One large clean 3D breakdown image** generated with ChatGPT: front, rear, left, right, top, bottom, three-quarter views, **exploded component layout** with parts separated and identified (cube base, bevel/chamfer, pip inserts, motifs, rune strips, floaters, VFX mount points), dimensions/proportions and consistent orientation, material & color callouts and how moving parts animate.
3. **Gameplay VFX conceptual art** generated through ChatGPT: projectile, hit, ability trigger, status ring and merge cue. All visual effect concepts must be distinct.
4. **Model brief:** dimensions in Roblox studs, pivot/origin and forward/up conventions, collision and bounds, low-poly mesh budget, material/texture channels, idle+attack+special animation plan, LOD and accessibility alternative to color.
5. **Export:** separate versioned source art, 3D source file, meshes/materials and thumbnails; maintain a manifest mapping stable IDs to assets and approval state.
6. **QA:** compare modeled object to generated reference; rotate through all orientations; verify star and pip visibility at match scale and team 2-player scale; no clipping/holes/overlap, no unintended seams; ensure fx pooling and phone performance.

## UI generated asset checklist
- Lobby home, world selection, stage card (Wave 100 goal), matchmaking solo/duo/experimental squad, Infinite access/season leaderboard.
- HUD wave/boss/progress, 15-cell board, spawn button and MP meter, dice detail tooltip, in-match upgrade strip, shared lives/team portraits, pause/reconnect.
- Collection rarity filters, dice cards, locked state, detail/compare, level/copies, crafting.
- Gold/Gem wallets, rotating store cards, purchase confirmation, chests, exact pre-open odds, duplicate conversion, pity tracker, Robux offer disclosures and receipt failure state.
- Daily/weekly quest, profile upgrades, achievements, world clear, rewards, loss, tutorial and settings.
- Full unstitched base panel and button images; if 9-slice is used, **use genuine stretch-safe regions** with visually seamless trim. Otherwise scale complete images with preserved aspect ratio. Do not stretch ornamental borders.

## UI responsive implementation
- Desktop and **landscape phone**: safe-area-aware frames and constraints; board and combat path remain visible; minimum 44×44 pixel/equivalent touch targets, ≥8px internal padding, readable text hierarchy.
- Use asset-true aspect ratios and explicit scale modes. Test wide desktop, narrow laptop, small landscape phone. Ensure longer translations/numbers do not clip.
- Avoid panel nesting that causes border seams; use one full asset for each decorative full frame if 9-slicing would create a visible split. Never interpolate differently sized icons into mismatched cells.
- All art approved against a single palette and layout reference before production of new sheets. Keep a style guide with color hex values, edge widths and outline widths **after a reference direction is selected**; don't invent brand colors as a locked requirement.

## Production workflow
Design brief → original ChatGPT image generation → visual approval → detailed ChatGPT modeling breakdown → 3D model → reference QA → in-engine previews at realistic device resolutions → final integration and manifest update. If a dice is modified, update **both** its UI art and modeling breakdown rather than allowing visual mismatch. Record prompt, version, dimensions and source/rights for every approved asset. Never claim an image was generated until an actual artifact exists.

## Asset acceptance gates
- 19/19 required original dice portrait + breakdown packages for the target 19-dice release.
- 100% of gameplay-critical HUD frames/icons can be traced to approved original ChatGPT generation (or a cleanly modified owned preexisting asset).
- All frames, text and sprites readable/undistorted at smallest supported landscape phone; star pips and rarity have non-color cues.
- All costs, probabilities and currency labels are readable without obstructing the path.
