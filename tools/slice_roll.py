"""Cut the Roll menu's own art out of Assets/UI/new/roll menu/sheets/roll-elements.png into upload-ready WHOLE PNGs (no slicing).

Usage: python tools/slice_roll.py  -> Assets/UI/new/roll menu/export/Roll_<Name>.png + manifest.json
       (a PNG is rewritten only when its bytes change, so a rerun never touches an uploaded file)
Reuses slice_shared.clean: solid blobs + 1 px antialias ring, glow dropped, partly transparent pixels take the nearest solid colour, tight bbox, native size.
Rects are the sheet components of sheets-catalog.md (x, y, w, h), padded 4 px (no neighbour closer than 30 px).
Window, title, tabs, close X, rarity pills and gem are NOT cut here: shared (Shell / Parts / Sprites.Gem). Crowns / stars only exist inside the sheet's rarity tags (no clean cut): old ids kept.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_quest as sq  # noqa: E402
import slice_shared as ss  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets" / "UI" / "new" / "roll menu"
OUT = SRC / "export"
SHEET = SRC / "sheets" / "roll-elements.png"
PAD = 4
# name: (x, y, w, h) of the sheet component
COMP = {
    "HeaderPlate": (1178, 363, 585, 80),  # 27 ornate dark bar, two gold diamonds
    "PityPill": (778, 507, 257, 69),  # 28 purple pill with gold crown (the word PITY is live text)
    "BtnGold": (976, 612, 320, 92),  # 34 orange pill, blank
    "BtnPurple": (1328, 612, 322, 92),  # 35 purple pill, blank
    "Info": (1857, 361, 82, 83),  # 25 info icon, gold ring (the old export's red centre differs)
    "Die1": (795, 355, 96, 105),  # 24 single white die
    "Dice3": (948, 332, 147, 135),  # 23 three white dice
    "BtnGrey": (1683, 612, 305, 93),  # 36 dark grey pill, blank (disabled / rolling)
}


def trim_dust(px: np.ndarray) -> np.ndarray:
    """Keep only the main body: alpha > 0 pixels farther than 1 px from the body's solid (alpha >= 200) pixels are cleared, then re-trim."""
    a = px[..., 3]
    body = sq.label8(a >= 200)
    sizes = np.bincount(body.ravel())
    sizes[0] = 0
    solid = body == sizes.argmax()
    keep = sq.dilate(solid, 1) & (a > 0)
    out = px.copy()
    out[..., 3] = np.where(keep, a, 0)
    ys, xs = np.where(out[..., 3] > 0)
    return out[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]


def fix_rim(px: np.ndarray, cap: int = 45, rows: int = 5, tol: int = 90) -> np.ndarray:
    """The sheet's dust sits on the straight top / bottom rim rows (between the rounded caps): repaint every pixel there whose
    brightness is off its row's median by more than tol with that median colour (alpha kept)."""
    h, w = px.shape[:2]
    out = px.copy()
    for y in list(range(rows)) + list(range(h - rows, h)):
        band = out[y, cap : w - cap]
        lum = band[:, :3].astype(int).sum(1)
        ok = band[:, 3] > 0
        med = np.median(band[ok][:, :3], axis=0)
        bad = ok & (abs(lum - med.sum()) > tol)
        band[bad, :3] = med.astype(np.uint8)
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    sheet = np.array(Image.open(SHEET).convert("RGBA"))
    manifest = {}
    for name, (x, y, w, h) in COMP.items():
        rect = (max(x - PAD, 0), max(y - PAD, 0), min(x + w + PAD, sheet.shape[1]), min(y + h + PAD, sheet.shape[0]))
        px = trim_dust(ss.clean(sheet[rect[1] : rect[3], rect[0] : rect[2]]))
        if name in ("HeaderPlate", "PityPill"):
            px = fix_rim(px)
        lab = sq.label8(px[..., 3] > 0)
        comps = np.bincount(lab.ravel())[1:]
        assert (comps >= 20).all() and len(comps) == 1, (name, comps)  # no opaque component outside the body
        data = ss.png_bytes(px)
        png = OUT / f"Roll_{name}.png"
        if not png.exists() or png.read_bytes() != data:
            png.write_bytes(data)
        manifest[name] = {"name": name, "w": int(px.shape[1]), "h": int(px.shape[0]), "sheet": "roll-elements", "rect": list(rect), "slice": False}
        print(name, px.shape[1], px.shape[0])
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
