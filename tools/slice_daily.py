"""Cut the 7 Daily Rewards sprites out of the source sheets into upload-ready PNGs.

Usage: python tools/slice_daily.py   cut all -> Assets/UI/daily menu/export/Daily_<Name>.png + manifest.json
(a PNG is only rewritten when its bytes change). Reuses slice_quest's helpers (connected components, PAD margin, E read margin) and
slice_bag's dematte / bleed / ink_box. All sprites are whole (never 9-sliced).

COMP: name -> (sheet, tight alpha>8 rect in sheet px, mode "comp"). The rect is the alpha>8 bounding box of the sprite's own connected
component (glow included, never an alpha>=160 box); neighbouring frames are separated from it by gaps of alpha <= 8, so no clear rects
are needed. comp = connected component seeded by the rect. Margins: sq.E = 40 sheet px are read around each rect, then the cut is
trimmed to alpha>0 and padded by sq.PAD = 10 transparent px. Alpha: < 8 -> 0, >= 248 -> 255, dematte + bleed as the other slicers.
    CardUpcoming  C (35, 18, 352, 298)    1st small frame
    CardToday     C (723, 17, 1051, 306)  3rd small frame, outer glow kept whole
    CardClaimed   C (1424, 17, 1743, 298) 5th small frame, green fill + tick baked
    Day7          C (30, 323, 416, 838)   row 2 plain tall frame incl. crown, HEALED
    Day7Glow      C (436, 323, 839, 849)  row 2 glowing tall frame, HEALED
    Chest         I (59, 288, 610, 845)   Royal Dice Chest
    Calendar      I (1427, 315, 1668, 562)
Sheets: C = daily-card-states-sheet.png, I = daily-reward-icons-sheet.png.

HEAL (Day7, Day7Glow): the purple ribbon with gold tails baked into the bottom of the card is removed from the sheet pixels before the cut,
using only the frame's own pixels. For each row y in [Y0, Y1) (the ribbon, its tails and their drop shadow) the fill between the two side rims
is replaced by the fill row mirrored about Y0 (row 2*Y0-1-y: clean straight-section rows directly above the ribbon, reflected so the texture
and the top join stay continuous; the span [Y0-120, Y0) is reflected back and forth as needed). The fill darkens toward the bottom rim, so
each column is gain-scaled by (target/source)^t, t = (y-Y0+1)/(Y1-Y0+1): source = mean of the 3 rows above Y0, target = mean of the 3 rows at
Y1 (both smoothed over 15 columns, measured away from the corner arcs and held constant out to the rims). The gain only rescales the frame's own fill pixels; no new art is painted and no reference image is used.
Per row the replaced span stops at the side rims: from each outer edge the contiguous run of bright rim pixels (R >= 170, G >= 60,
alpha >= 200) is the rim and one more pixel is kept; rows below the tail tips curve with the corner, so that edge is detected per row and
the span follows the corner. Rows outside [Y0, Y1), both rims and the bottom rim are never written, so the Day7Glow outer halo is untouched.
    Day7      Y0 696, Y1 804, scan from x 30..416
    Day7Glow  Y0 684, Y1 802, scan from x 436..839
Run `python tools/slice_daily.py --check` to print the join steps and write the 3x before/after band crops to the folder given by $DAILY_CHECK.
"""

import io
import json
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_bag as sb  # noqa: E402
import slice_quest as sq  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets" / "UI" / "daily menu"
OUT = SRC / "export"
SHEETS = {"C": "daily-card-states-sheet.png", "I": "daily-reward-icons-sheet.png"}
COMP = {
    "CardUpcoming": ("C", (35, 18, 352, 298)),
    "CardToday": ("C", (723, 17, 1051, 306)),
    "CardClaimed": ("C", (1424, 17, 1743, 298)),
    "Day7": ("C", (30, 323, 416, 838)),
    "Day7Glow": ("C", (436, 323, 839, 849)),
    "Chest": ("I", (59, 288, 610, 845)),
    "Calendar": ("I", (1427, 315, 1668, 562)),
}
HEAL = {"Day7": (696, 804, 30, 416), "Day7Glow": (684, 802, 436, 839)}  # Y0, Y1, scan x0, x1
RAMP = {"Day7": 2, "Day7Glow": 30}  # px of dark edge / inner glow inside the rim
CORNER_Y = 766  # below this row the bottom corner arcs start: fill is rebuilt from the distance to the rim
SPAN = 120  # clean rows above Y0 that are mirrored into the band


def rimish(p: np.ndarray) -> bool:
    return p[0] >= 170 and p[1] >= 60 and p[3] >= 200


def smooth_cols(v: np.ndarray, k: int = 15) -> np.ndarray:
    c = np.cumsum(np.pad(np.pad(v, (k // 2, k // 2), mode="edge"), (1, 0)))
    return (c[k:] - c[:-k]) / k


def edges(row: np.ndarray, x0: int, x1: int) -> tuple[int, int]:
    """(first fill x, last fill x) of a row: just past the bright rim runs entered from x0 and x1."""

    def walk(x: int, d: int) -> int:
        while not rimish(row[x]):
            x += d
        while rimish(row[x]):
            x += d
        return x

    return walk(x0, 1), walk(x1 - 1, -1)


def heal(sheet: np.ndarray, name: str) -> np.ndarray:
    y0, y1, sx0, sx1 = HEAL[name]
    ramp = RAMP[name]
    out = sheet.copy()
    f = sheet.astype(np.float32)
    ed = {y: edges(sheet[y], sx0, sx1) for y in range(y0 - 60, y1)}
    eL = max(ed[y][0] for y in range(y0 - 60, 786))  # straight-section edges (the rim edge wobbles by 1 px)
    eR = min(ed[y][1] for y in range(y0 - 60, 786))
    cols = slice(eL + ramp + 40, eR - ramp - 39)  # away from the rims and corner arcs: gain target row stays pure fill
    src = np.stack([smooth_cols(f[y0 - 3 : y0, cols, ch].mean(0)) for ch in range(3)], 1)
    tgt = np.stack([smooth_cols(f[y1 : y1 + 3, cols, ch].mean(0)) for ch in range(3)], 1)
    ratio = np.clip((tgt + 2) / (src + 2), 0.3, 3.0)  # per channel: the fill under the ribbon is redder and less blue than the fill above it

    def mirror(y: int, c: np.ndarray) -> np.ndarray:
        k = (y - y0) % (2 * SPAN)
        sy = y0 - 1 - (k if k < SPAN else 2 * SPAN - 1 - k)
        g = ratio[np.clip(c - (eL + ramp + 40), 0, len(ratio) - 1)] ** ((y - y0 + 1) / (y1 - y0 + 1))
        return f[sy, c, :3] * g

    # inner glow / edge shading of the rim: colour offset from the deep fill by distance d to the rim, read off the clean rows above the ribbon
    prof = f[y0 - 60 : y0, :, :3].mean(0)
    gl = prof[eL : eL + ramp + 1] - prof[eL + ramp]
    gr = prof[eR - ramp : eR + 1][::-1] - prof[eR - ramp]
    mid = (eL + eR) / 2  # left ramp left of the middle, right ramp right of it, blended over the middle 200 px (the bottom haze)
    yc = CORNER_Y
    ry0, ry1 = yc - 6, y1 + 30
    rim = np.zeros(sheet.shape[:2], bool)
    for y in range(ry0, ry1 + 1):
        row = sheet[y]
        for x in range(sx0, sx1):
            if rimish(row[x]) and (x <= eL + 6 or x >= eR - 6 or y >= 798):
                rim[y, x] = True
    ry, rx = np.where(rim)
    for y in range(y0, y1):
        xl, xr = ed[y][0], ed[y][1]
        c = np.arange(xl, xr + 1)
        if y < yc:
            out[y, xl : xr + 1, :3] = np.clip(mirror(y, c), 0, 255).astype(np.uint8)
        else:
            base = mirror(y, np.clip(c, eL + ramp, eR - ramp))
            d = np.array([np.sqrt(((rx - x) ** 2 + (ry - y) ** 2)[(abs(rx - x) <= ramp + 2) & (abs(ry - y) <= ramp + 2)].min(initial=1e9)) for x in c])
            di = np.clip(np.round(d).astype(int) - 1, 0, ramp)
            w = np.clip((c - mid) / 200 + 0.5, 0, 1)[:, None]
            out[y, xl : xr + 1, :3] = np.clip(base + gl[di] * (1 - w) + gr[di] * w, 0, 255).astype(np.uint8)
        out[y, xl : xr + 1, 3] = 255
    return out


def sheet_px(name: str, healed: bool = True) -> np.ndarray:
    a = np.array(Image.open(SRC / SHEETS[COMP[name][0]]).convert("RGBA"))
    return heal(a, name) if healed and name in HEAL else a


def cut(name: str, sheet: np.ndarray | None = None) -> np.ndarray:
    x0, y0, x1, y1 = COMP[name][1]
    img = np.pad(sheet_px(name) if sheet is None else sheet, ((sq.E, sq.E), (sq.E, sq.E), (0, 0)))
    cx0, cy0, cx1, cy1 = x0 - sq.E, y0 - sq.E, x1 + sq.E, y1 + sq.E
    arr = img[cy0 + sq.E : cy1 + sq.E, cx0 + sq.E : cx1 + sq.E].copy()
    loc = (x0 - cx0, y0 - cy0, x1 - cx0, y1 - cy0)
    a = arr[..., 3]
    a[~sq.component_mask(arr, [loc])] = 0
    a[a < 8] = 0
    a[a >= 248] = 255
    ys, xs = np.where(a > 0)
    px = np.pad(arr[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1], ((sq.PAD, sq.PAD), (sq.PAD, sq.PAD), (0, 0)))
    px[0], px[-1], px[:, 0], px[:, -1] = 0, 0, 0, 0
    px = sb.bleed(sb.dematte(px))
    assert max(px.shape[:2]) <= 1024, f"{name} {px.shape}"
    return px


def check(folder: Path) -> None:
    """Join steps (mean luma of 3 rows either side, per 16-column block, worst block) and 3x before/after crops of each healed band."""
    lum = lambda p: 0.299 * p[..., 0] + 0.587 * p[..., 1] + 0.114 * p[..., 2]
    folder.mkdir(parents=True, exist_ok=True)
    for name, (y0, y1, sx0, sx1) in HEAL.items():
        before, after = sheet_px(name, False), sheet_px(name)
        xs0 = max(edges(before[y], sx0, sx1)[0] for y in range(y0, 786))
        xs1 = min(edges(before[y], sx0, sx1)[1] for y in range(y0, 786))
        steps = {}
        for label, a, b in (("top", slice(y0 - 3, y0), slice(y0, y0 + 3)), ("bottom", slice(y1 - 3, y1), slice(y1, y1 + 3))):
            worst = 0.0
            for bx in range(xs0 + RAMP[name] + 40, xs1 - RAMP[name] - 54, 16):
                d = abs(lum(after[a, bx : bx + 16]).mean() - lum(after[b, bx : bx + 16]).mean())
                worst = max(worst, d)
            steps[label] = round(worst, 2)
        rowm = lum(after[y0 - 6 : y1 + 6, xs0 : xs1 + 1]).mean(1)
        steps["max row-to-row (band +-6 rows)"] = round(float(np.abs(np.diff(rowm)).max()), 2)
        bad = 0
        for y in range(y0, y1):
            xl, xr = edges(after[y], sx0, sx1)
            r = after[y, xl + RAMP[name] + 2 : xr - RAMP[name] - 1].astype(int)  # the inner glow ramp itself is legitimate gold-orange
            bad += int((((r[:, 0] >= 150) & (r[:, 1] >= 60)) | ((r[:, 2] > r[:, 0]) & (r[:, 2] > 60))).sum())
        steps["ribbon/gold/purple px left in fill"] = bad
        print(name, f"fill cols {xs0}..{xs1}", steps)
        box = (sx0, y0 - 40, sx1, y1 + 40)
        for tag, arr in (("before", before), ("after", after)):
            bg = Image.new("RGBA", arr.shape[1::-1], (40, 40, 40, 255))
            bg.alpha_composite(Image.fromarray(arr))
            c = bg.crop(box)
            c.resize((c.width * 3, c.height * 3), Image.NEAREST).save(folder / f"{name}_{tag}.png")


def main() -> None:
    if "--check" in sys.argv:
        check(Path(os.environ["DAILY_CHECK"]))
        return
    OUT.mkdir(exist_ok=True)
    mf = OUT / "manifest.json"
    old = json.loads(mf.read_text()) if mf.exists() else {}
    manifest = {}
    for name in COMP:
        px = cut(name)
        buf = io.BytesIO()
        Image.fromarray(px).save(buf, format="PNG", optimize=True)
        png = OUT / f"Daily_{name}.png"
        if not png.exists() or png.read_bytes() != buf.getvalue():
            png.write_bytes(buf.getvalue())
        h, w = px.shape[:2]
        manifest[name] = {"w": w, "h": h, "ink": sb.ink_box(px), "asset": old.get(name, {}).get("asset", "")}
        print(name, w, h, manifest[name]["ink"])
    mf.write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
