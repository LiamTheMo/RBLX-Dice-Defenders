"""Cut the Play menu art (world banners, rank shields, START button, crown, trophy, reward icons) into upload-ready PNGs.

Usage: python tools/slice_play.py -> Assets/UI/new/play menu/export/Play_<Name>.png + manifest.json
       (a PNG is rewritten only when its bytes change, so a rerun never touches an uploaded file)

Sheets: Assets/UI/new/play menu/sheets/worlds-and-controls.png (W) and rank-and-reward-icons.png (R), both RGBA 1774x887.
Every cut: the sheet's component bbox (Assets/UI/new/_overhaul/assets-raw.json) padded 3 px, then slice_shared.clean (solid blobs plus a 1 px antialias
ring, glow dropped, tight bbox, native size, never scaled). No slicing: every sprite is a whole asset. Window, tabs, close X, lock, check,
coin and gem are the shared ones (Shared_*), so the sheet's own copies are not cut.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_shared as ss  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets" / "UI" / "new" / "play menu"
OUT = SRC / "export"
PAD = 3

# name: (sheet, component bbox (x, y, w, h) from assets-raw.json, opening radius)
JOBS = {
    "BannerDice": ("worlds-and-controls", (29, 396, 413, 173), 0),
    "BannerFrost": ("worlds-and-controls", (464, 396, 412, 173), 0),
    "BannerMagma": ("worlds-and-controls", (899, 397, 411, 172), 0),
    "BannerShadow": ("worlds-and-controls", (1333, 397, 412, 173), 0),
    "Start": ("worlds-and-controls", (906, 248, 458, 120), ss.OPEN),  # green button with the play arrow, no text (live label)
    "Crown": ("worlds-and-controls", (519, 766, 125, 90), 0),
    "Trophy": ("worlds-and-controls", (64, 768, 109, 97), 0),
    "RankBronze": ("rank-and-reward-icons", (29, 13, 163, 181), 0),
    "RankSilver": ("rank-and-reward-icons", (236, 13, 164, 180), 0),
    "RankGold": ("rank-and-reward-icons", (442, 13, 162, 180), 0),
    "Crystals": ("rank-and-reward-icons", (426, 616, 129, 108), 0),
    "CrownGems": ("rank-and-reward-icons", (851, 616, 143, 105), 0),
}


def main() -> None:
    OUT.mkdir(exist_ok=True)
    sheets = {}
    manifest = {}
    for name, (sheet, (x, y, w, h), opening) in JOBS.items():
        if sheet not in sheets:
            sheets[sheet] = np.array(Image.open(SRC / "sheets" / f"{sheet}.png").convert("RGBA"))
        a = sheets[sheet]
        rect = (max(x - PAD, 0), max(y - PAD, 0), min(x + w + PAD, a.shape[1]), min(y + h + PAD, a.shape[0]))
        px = ss.clean(a[rect[1] : rect[3], rect[0] : rect[2]], opening)
        data = ss.png_bytes(px)
        png = OUT / f"Play_{name}.png"
        if not png.exists() or png.read_bytes() != data:
            png.write_bytes(data)
        manifest[name] = {"w": int(px.shape[1]), "h": int(px.shape[0]), "sheet": sheet, "rect": list(rect), "slice": False}
        print(name, manifest[name]["w"], manifest[name]["h"])
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
