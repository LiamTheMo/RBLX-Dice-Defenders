"""Cut the shared UI pieces (close X, badges, tabs, pill buttons, currency) into upload-ready PNGs.

Usage: python tools/slice_shared.py          -> Assets/UI/new/shared/export/Shared_<Name>.png + manifest.json
                                                (a PNG is rewritten only when its bytes change, so a rerun never touches an uploaded file)
       python tools/slice_shared.py --seam   also runs the seam test on the sliced sprites (prints; crops go to the temp dir)

Sheets: Assets/UI/new/shared/sheets/buttons-and-tabs.png (RGBA) and shared/currency/{Coin,Gem}.png.
Every cut: the crop is the sprite's grid cell (never touches a neighbour); only the solid blobs (alpha >= 128) are kept plus a 1 px
antialias ring (the sheet's soft coloured glow outside the dark outline is dropped); every partly transparent pixel takes the nearest
solid pixel's colour (the edge is the sprite's own dark outline, never the glow); tight bbox; native size, never scaled.
Sliced sprites (tabs, pills; approved exceptions X1/X2) are rebuilt as: left cap | ONE column (median of the centre, tiled 4 wide) | right cap.
The caps end where every column is within TOL of that column, so stretching the 4 px centre shows no step at either slice line.
Manifest: w, h, sheet, rect (source px), slice, sliceCenter = [x0, y0, x1, y1] (y = the middle row: with box height = h x SliceScale nothing stretches vertically).
"""

import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_common as sc  # noqa: E402
from slice_common import OPEN, clean  # noqa: E402

SRC = sc.UI / "shared"
OUT = SRC / "export"
SHEET = SRC / "sheets" / "buttons-and-tabs.png"
MID = 4  # width of the repeated centre column
CAP_MARGIN = 4  # extra cap px past the last column that differs
RAMP = 40  # cap columns that fade into the centre column

# name: (rect in the sheet (x0, y0, x1, y1), slice tolerance or None for a whole asset)
SHEET_COMP = {
    "Tab": ((60, 38, 466, 152), 72),
    "TabHover": ((474, 38, 878, 152), 72),
    "TabPressed": ((886, 38, 1290, 152), 72),
    "TabSelected": ((1298, 38, 1702, 152), {"hard": (62, 62), "mid": 85}),  # the underline gloss glints across the centre: centre column taken from a plain stretch
    "TabDisabled": ((1710, 38, 2112, 152), {"hard": (60, 60)}),  # dust specks in the sheet defeat the automatic cap
    "Close": ((720, 180, 893, 342), None),
    "CloseHover": ((999, 180, 1172, 342), None),
    "ClosePressed": ((1278, 180, 1452, 342), None),
    "PillGrey": ((56, 364, 562, 502), 72),
    "PillGreen": ((580, 364, 1078, 502), 72),
    "PillRed": ((1096, 364, 1594, 502), 72),
    "PillPurple": ((1611, 364, 2118, 502), 72),
    "Lock": ((541, 534, 718, 700), None),
    "Check": ((772, 534, 948, 700), None),
    "ArrowLeft": ((1002, 534, 1177, 700), None),
    "ArrowRight": ((1231, 534, 1407, 700), None),
    "Search": ((1458, 534, 1634, 700), None),
}
# Bare badges: connected component seeded at a point (sheet path under Assets/UI/new, seed x, y). One padlock / one tick for every menu.
BADGES = {
    "Padlock": ("bag menu/sheets/inventory-states-clean.png", (1293, 845)),  # gold padlock, catalog #11
    "Tick": ("quests menu/sheets/quest-and-mastery-icons.png", (1880, 370)),  # green round tick, catalog #11
}
CURRENCY = {"Coin": SRC / "currency" / "Coin.png", "Gem": SRC / "currency" / "Gem.png"}


def slice3(px: np.ndarray, spec):
    """Left cap | MID identical columns | right cap. The hard caps end past the last column that differs from the centre column by more
    than spec (rows 2..h-3: the ragged outer rows would otherwise stretch the caps); then each cap's inner RAMP columns fade smoothly into
    that centre column (smoothstep), so the cap meets the repeated column exactly: no step at either slice line."""
    h, w = px.shape[:2]
    c0 = spec["mid"] if isinstance(spec, dict) and "mid" in spec else w // 2
    col = np.median(px[:, c0 - 8 : c0 + 8].astype(np.float32), axis=1)  # (h, 4)

    def d(x):
        return int(np.abs(px[2 : h - 2, x].astype(int) - col[2 : h - 2].astype(int)).max())

    if isinstance(spec, dict):
        lc, rc = (n + RAMP for n in spec["hard"])
    else:
        lc = next((x + 1 for x in range(c0, -1, -1) if d(x) > spec), 0) + CAP_MARGIN + RAMP
        rc = next((w - x for x in range(c0, w) if d(x) > spec), 0) + CAP_MARGIN + RAMP
    work = px.astype(np.float32)
    for i in range(RAMP):  # i = 0 .. RAMP-1 from the hard cap inwards; the last cap column equals the centre column
        t = (i + 1) / RAMP
        t = t * t * (3 - 2 * t)
        for x in (lc - RAMP + i, w - rc + RAMP - 1 - i):
            work[:, x] = work[:, x] * (1 - t) + col * t
    mid = np.repeat(col[:, None, :], MID, axis=1)
    out = np.concatenate([work[:, :lc], mid, work[:, w - rc :]], axis=1)
    return np.clip(out.round(), 0, 255).astype(np.uint8), [lc, h // 2 - 1, lc + MID, h // 2]  # 1 px of vertical centre: edge-hugging vertical caps draw wrongly in engine


def seam_test(name: str, px: np.ndarray, sl: list):
    """Render the sprite at 7 widths (box height 54 design px, SliceScale = 54 / h) at 1672 and 2560 scale; max column diff across each slice line."""
    h, w = px.shape[:2]
    lc, rc = sl[0], w - sl[2]
    res = []
    tmp = Path(tempfile.gettempdir())
    for label, ds in (("1672", 1.0), ("2560", 2560 / 1672)):
        for width in (140, 180, 250, 300, 420, 600, 1000):
            s = 54 * ds / h  # real px per sprite px
            full_w = max(round(width * ds / s), lc + rc + 8)  # a box narrower than both caps shrinks them: never used
            mid = np.repeat(px[:, lc : lc + 1], full_w - lc - rc, axis=1)
            hi = np.concatenate([px[:, :lc], mid, px[:, w - rc :]], axis=1)
            img = Image.fromarray(hi).resize((round(hi.shape[1] * s), round(h * s)), Image.BILINEAR)
            r = np.array(img).astype(int)
            x1, x2 = round(lc * s), round((hi.shape[1] - rc) * s)
            line = max(int(np.abs(r[:, x - 1] - r[:, x]).max()) for x in (x1 - 1, x1, x1 + 1, x2 - 1, x2, x2 + 1))
            res.append((label, width, r.shape[1], line))
            if width in (180, 600):
                img.save(tmp / f"seam_{name}_{label}_{width}.png")
    return res


def main() -> None:
    OUT.mkdir(exist_ok=True)
    sheet = sc.load_rgba(SHEET)
    manifest = {}
    jobs = [(n, "buttons-and-tabs", r, t, sheet[r[1] : r[3], r[0] : r[2]]) for n, (r, t) in SHEET_COMP.items()]
    for n, p in CURRENCY.items():
        im = sc.load_rgba(p)
        jobs.append((n, p.name, (0, 0, im.shape[1], im.shape[0]), None, im))
    for n, (rel, (sx, sy)) in BADGES.items():
        im = sc.load_rgba(SRC.parent / rel)
        lab = sc.label8(im[..., 3] >= 128)
        comp = lab == lab[sy, sx]
        assert lab[sy, sx] > 0, n
        ys, xs = np.where(comp)
        x0, y0, x1, y1 = max(xs.min() - 20, 0), max(ys.min() - 20, 0), xs.max() + 21, ys.max() + 21
        crop = im[y0:y1, x0:x1].copy()
        crop[..., 3] = np.where(sc.dilate(comp, 8)[y0:y1, x0:x1], crop[..., 3], 0)
        jobs.append((n, rel, (int(x0), int(y0), int(x1), int(y1)), None, crop))
    seam = "--seam" in sys.argv
    for name, sh, rect, tol, crop in jobs:
        px = clean(crop, OPEN if sh == "buttons-and-tabs" else 0)  # the currency PNGs are already clean cuts: no opening (it would shave the gem's tips)
        entry = {"sheet": sh, "rect": list(rect), "slice": bool(tol)}
        if tol:
            px, sl = slice3(px, tol)
            entry["sliceCenter"] = sl
            if seam:
                for r in seam_test(name, px, sl):
                    print(f"seam {name} {r[0]} box{r[1]}: width {r[2]} line {r[3]}")
        entry["w"], entry["h"] = int(px.shape[1]), int(px.shape[0])
        sc.save_png(OUT / f"Shared_{name}.png", px)
        manifest[name] = entry
        print(name, entry["w"], entry["h"], entry.get("sliceCenter", ""))
    sc.write_manifest(OUT, manifest)


if __name__ == "__main__":
    main()
