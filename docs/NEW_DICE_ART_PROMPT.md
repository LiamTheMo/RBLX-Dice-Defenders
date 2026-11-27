# New dice: image-generation prompt pack

Paste **Part A** once as the style lock, then paste **Part B** once per die (fill the die's row from Part C). Generate each die as **4 images**: (1) top face + icon sheet, (2) colour scheme sheet, (3) VFX concept sheet, (4) animation timing sheet. ART_PIPELINE.md also requires the beauty render and the 3D breakdown sheet; ask for those afterwards with the same style lock.

Stats and rules for each die live in `src/server/Config/Dice.luau` (`Dice.Pending`). Timings below come from those numbers.

---

## Part A: style lock (paste first, every session)

```
You are producing original game art for "Dice Defenders", a Roblox tower-defence game where players merge toy-like collectible dice on a 5x3 board. Style lock for every image:
- Chunky, faceted, low-poly toy look. Rounded bevelled cube with a clean silhouette. Flat colours with one soft highlight and one soft shadow per face. No photorealism, no noise textures, no gradients busier than 2 stops.
- Thick dark outline (about 6% of die width) so the die reads at 48 px.
- Pips are big round inserts, always readable; the 7-pip face is a large STAR. Glow must never cover the pips.
- Rarity has a non-colour cue: Common plain etched corners; Rare patterned rim; Epic luminous rune strips on the edges; Legendary a floating accent above the die; Mythic celestial rings around the die; Secret a masked "?" motif.
- Effects are vibrant but uncluttered: max 3 colours per effect, each effect shape distinct from every other die's effect.
- Plain neutral mid-grey (#3A3F4B) background, no text, no watermark, no UI chrome unless asked. Landscape-phone readability: every important shape survives at 64 px.
Keep these rules for every image I ask for, and keep each die's colours and motif consistent across all four of its images.
```

---

## Part B: per-die template (paste once per die)

```
Die: {NAME} ({RARITY}). Rule in one line: {RULE}.
Motif: {MOTIF}.  Palette: body {C1}, accent {C2}, glow {C3}, outline #101018.

Make FOUR separate images, 16:9, each clean and labelled with small sans-serif captions only where I say so:

IMAGE 1, TOP FACE AND ICON SHEET.
Left 60%: the die's TOP FACE seen straight down, large, showing the motif etched or inlaid in the top face, with the pip arrangement for 1, 3, 5 and 7 pips shown as four small variants along the bottom (the 7-pip is a star). Right 40%: the inventory icon (isometric die, motif visible, 1:1 square, centred) at three sizes: 256, 96 and 48 px, to prove it stays readable. Add the rarity cue. No text.

IMAGE 2, COLOUR SCHEME SHEET.
The die in a 3/4 view, flanked by: five labelled colour chips with hex codes (body, accent, glow, pip, outline), a light-mode and a dark-background version of the icon, and a greyscale version showing the motif still reads without colour. Show the die's four team-tint variants only as a thin outline swatch, not recoloured art.

IMAGE 3, VFX CONCEPT SHEET.
A 3x2 grid of panels on the same grey background, one panel each for: (a) PROJECTILE in flight, (b) HIT impact on an enemy, (c) ABILITY TRIGGER, (d) STATUS indicator on an enemy or on the board, (e) MERGE cue when this die is created, (f) the ability's FULL-BOARD view at phone scale (15 cells). {VFX} Each effect must use only the palette above and must look different from the other panels.

IMAGE 4, ANIMATION TIMING SHEET.
A storyboard with a labelled time ruler in seconds. Rows: IDLE loop, ATTACK, SPECIAL ABILITY, MERGE-IN. Each row has 6 to 8 frames drawn as small thumbnails with a timestamp under each frame (for example 0.00 s, 0.08 s, 0.16 s), the ease type written under each segment (ease-out, ease-in-out, linear), and arrows showing motion direction and scale (for example "squash to 90% in 0.06 s, stretch to 112% in 0.10 s"). Mark particle spawn and despawn times with small flags, and mark the exact moment damage is dealt with a red tick. Use these timings: {TIMING}. Add a legend box at the bottom listing every duration in seconds. Only numbers and short captions, no paragraphs.
```

---

## Part C: per-die fill-in values

Timings use the game's real numbers: attack period = 1 / (rate x pip rate), so quote times for a 1-pip die and note that more pips shorten the loop. Every die also shares: merge-in 0.35 s (scale 0 to 112% in 0.2 s ease-out, settle to 100% in 0.15 s ease-in-out), idle bob 2.4 s loop (4 px up/down, linear sine).

### Common

| Die | Palette (body / accent / glow) | Motif on top face | VFX | Timing |
|---|---|---|---|---|
| **C08 Anvil** | #6B7380 / #2B2F38 / #FFB347 | Anvil silhouette in a square | Projectile: a short iron slab that spins once. Hit: flat horizontal shockwave plus orange sparks, bigger and heavier on Brutes and Bosses. Trigger: none (passive); status: a small "x1.6" anvil badge over Brutes. Merge: dust puff. | Attack period 1.82 s: wind-up lift 0.5 s ease-out, hold 0.1 s, slam 0.12 s ease-in with damage at 0.72 s, recover 1.1 s. |
| **C09 Wager** | #7A3FB5 / #F4D03F / #FF5CA8 | Two tumbling mini-dice | Projectile: a spinning coin-die that flashes a random pip value. Hit: number burst whose size matches the roll (small for 40%, huge with gold stars for 260%). Status: none. Merge: confetti pop. | Attack period 1.00 s: flick 0.15 s, projectile flight 0.35 s, damage at 0.50 s; the die's face re-rolls (0.12 s flicker) after each shot. |
| **C10 Shackle** | #3F6B4F / #B8B8B8 / #9BE564 | Chain link ring | Projectile: a thin steel bolt with a tiny chain tail. Hit: grey spark. Trigger (8% roll): green chain loops snap around the enemy's feet. Status: chain ring at the enemy's base for 1.5 s with a shrinking arc timer. Merge: chain rattle shimmer. | Attack period 1.00 s. Root: chain wraps 0.15 s ease-out, holds 1.5 s, snaps off in 0.2 s with a 4-link shatter; one-time per enemy (a small cracked-link icon remains). |
| **C11 Blast** | #D9622B / #FFD166 / #FF8C42 | Starburst with a ring | Projectile: orange orb with a short trail. Hit: round blast ring with an 8-stud-wide radius marker (mark the radius on the ground as a thin dashed circle). Status: none. Merge: small ring pulse. | Attack period 1.00 s: charge glow 0.2 s, flight 0.3 s, impact at 0.5 s, ring expands 0 to 8 studs in 0.18 s ease-out then fades 0.12 s. |

### Rare

| Die | Palette | Motif | VFX | Timing |
|---|---|---|---|---|
| **R06 Hex** | #5B2A86 / #C77DFF / #E0AAFF | Eye inside a hexagon | Projectile: violet hex-shaped bolt. Hit: purple rune circle stamps under the enemy. Status: 1, 2 or 3 stacked floating hexagon marks over the enemy (show all three stages), bosses show half-bright marks. Trigger: none. Merge: rune flash. | Attack period 1.00 s. Mark: rune stamps 0.12 s ease-out; each stack lasts until the enemy dies; stack icon pops in 0.1 s with +8% flash; show 3 stacks reaching +24%. |
| **R07 Tithe** | #B8860B / #F7E7A1 / #FFD700 | Coin in a bowl | Projectile: golden coin. Hit: gold flash. Trigger on kill: coins fly from the enemy to the MP meter, the extra 25% shown as a larger coin. Status: none. Merge: coin shower. | Attack period 1.00 s. Kill payout: coins arc 0.45 s ease-in-out to the MP meter, "+25%" label floats up 0.6 s. |

### Epic

| Die | Palette | Motif | VFX | Timing |
|---|---|---|---|---|
| **E11 Reaper** | #1F1B2E / #A0A8C0 / #7CF5D0 | Scythe crossing a crescent | Projectile: pale scythe slash arc. Hit: teal crescent cut. Trigger (every 4th hit): large scythe sweep and a "3%" health-bar chunk visibly torn off the enemy bar (boss: a quarter-size chunk). Status: 4-segment ring around the die filling per hit. Merge: soul-wisp swirl. | Attack period 1.00 s. Hits 1-3: 0.2 s slash. Hit 4: wind-up 0.25 s, sweep 0.15 s, health chunk drains over 0.4 s ease-out; the segment ring resets in 0.15 s. |
| **E12 Tether** | #1E6F8F / #BFE9FF / #4DD2FF | Three nodes joined by lines | Projectile: cyan bolt. Trigger: three glowing threads connect the 3 marked enemies in a triangle; damage pulses travel along the threads at 30%. Status: node mark over each tethered enemy. Merge: thread weave. | Attack period 1.00 s. Tether forms 0.2 s; pulse travels between enemies in 0.12 s; threads fade 0.2 s when an enemy dies and a new target is picked (0.2 s). |
| **E13 Mint** | #2E8B57 / #F4D35E / #A8F0B8 | Coin stamp press | Projectile: small green coin. Trigger on timer: a coin pops from the die and flies to the MP meter with a "+MP" tag. Status: a circular timer fill on the die. Cap marker: three coin slots shown for the board limit. Merge: mint stamp. | Timer 10 s (tune): fill 0 to 100% linear, pop 0.15 s ease-out, coin flight 0.5 s, label 0.6 s, reset instantly. |
| **E14 Surge** | #F2A900 / #FFF3B0 / #FFE066 | Lightning bolt through a ring | Projectile: yellow zigzag bolt. Trigger every 8 s: a lightning bolt strikes a random board die, which glows and gets a spinning speed ring for 6 s. Status: yellow ring and speed lines on the buffed die. Merge: spark burst. | Every 8 s: telegraph 0.3 s (target die outlined), strike 0.1 s, buff ring 6 s with a 0.5 s fade-out warning flicker at 5.5 s, then idle 2 s before the next telegraph. |

### Legendary

| Die | Palette | Motif | VFX | Timing |
|---|---|---|---|---|
| **L07 Sunder** | #8C1D18 / #F5E6C8 / #FF6B35 | Axe splitting a circle | Projectile: red-white axe-edge bolt. Trigger every 5th hit: a vertical crack line splits the enemy and a "2%" chunk leaves its health bar (boss: 0.5%). Status: 5-pip counter orbiting above the die. Floating accent: a small axe hovering over the die. Merge: crack-flash. | Attack period 1.00 s. Hits 1-4 0.2 s. Hit 5: wind-up 0.3 s, crack draws in 0.1 s, enemy health bar drains 0.4 s ease-out; counter resets 0.15 s. |
| **L08 Overgrowth** | #2D6A3E / #C5F0A4 / #6EDC6A | Sprouting vine around a cube | Projectile: leafy bolt. Status: vines climb the die as waves pass (show stage at wave 0, 50 and 100: +0%, +100%, +200%), plus a floating seedling accent. Hit: leaf burst. Merge: bloom. | Growth steps +2% per wave: each wave-clear triggers a 0.4 s vine-grow pulse (ease-out) and a "+2%" tag; show the three milestone looks as a row. |
| **L09 Nexus** | #1B4FA0 / #D9E6FF / #5CC8FF | Six-node web | Projectile: blue beam. Trigger: a hexagonal web links 6 enemies; shared damage ripples along the strands; bosses visibly excluded (strands bounce off them), Brutes drawn with a thinner strand. Floating accent: a small linked-nodes orb. Merge: web flash. | Link forms 0.3 s; ripple 0.15 s per strand; re-link when a target dies 0.25 s; attack period 1.00 s. |
| **L10 Prism** | #7C4DFF / #FFFFFF / #FF8AF4 | Triangular prism splitting light | Projectile: rainbow-edged bolt. Trigger every 12 s: a light beam fans out to adjacent dice, each flashing and re-firing its timer ability (show Eclipse getting a short "10 s cooldown" lock icon). Floating accent: rotating prism. Merge: spectrum flash. | Every 12 s: charge 0.4 s, beam fan 0.15 s, adjacent dice flash 0.3 s; show the 10 s Eclipse lock as a separate bar. |
| **L11 Vault** | #3A4A5C / #FFD34D / #FFE9A0 | Vault door with a coin | Projectile: gold bolt. Passive: golden interest sparkles drift from the die to the MP meter every few seconds (5% shown), and a "-15%" tag on the Power Up button. Floating accent: spinning vault wheel. Merge: coin ring. | Interest sparkle every 2 s (0.5 s flight); Power Up discount tag pulses 0.3 s when the player opens the menu; attack period 1.00 s. |

### Mythic and Secret

| Die | Palette | Motif | VFX | Timing |
|---|---|---|---|---|
| **M02 Eclipse** | #0B0B1E / #F5C542 / #FF9F1C | Sun behind a dark disc with corona | Projectile: dark disc with gold rim. Trigger every 15 s: the whole lane dims and a golden corona ring expands from the die; enemies show a "+50%" red glow (bosses "+25%", dimmer). Status: eclipse timer arc over the die. Celestial rings orbit the die. Merge: eclipse flash. | Every 15 s: telegraph 0.4 s (lane starts to dim), eclipse active 5.0 s (corona pulses at 1 s steps), fade-out 0.5 s, then 9.1 s cooldown with a filling arc. |
| **S02 Doomsday** | #3B0A12 / #FF2D2D / #FFB703 | Masked skull in a meteor ring | Projectile: dark meteor. Trigger every 30 s: red sky tint, a huge sigil appears over the lane, and a red shockwave sweeps every enemy; a "10%" chunk drains each health bar (bosses 2.5%). Status: 30 s countdown skull. Secret mask "?" overlay on the die's top face when not owned. Merge: sigil flash. | Every 30 s: countdown skull fills linear over 30 s, telegraph 1.0 s (sigil draws in), shockwave 0.25 s across the lane, health chunks drain 0.5 s, sky tint fades 0.6 s. |

---

## Part D: after the images

1. Save each approved image under `Assets/Models/Dice/<Rarity>/<ID>/` as `top_icon.png`, `colour.png`, `vfx.png`, `timing.png`, and record prompt, date and rights in the manifest (ART_PIPELINE.md).
2. Ask for the 3D breakdown sheet and the beauty render with the same style lock, then model in Blender.
3. Once art and the ability code exist, move the die from `Dice.Pending` into `Dice.Types` and add its Display and DiceAssets rows.
