"""Cut the Bag menu icons for the real Config/Inventory entries out of the new sheets (Assets/UI/new/bag menu/sheets).

Usage: python tools/slice_bag_new.py  -> Assets/UI/new/bag menu/export/Bag_<Name>.png + manifest.json
tools/slice_bag.py (the old art cutter) stays: slice_shared.py imports its helpers.
Every cut: the sheet component's own bbox (+ PAD), only its solid blobs + a 1 px antialias ring (glow drips and sparkle
specks outside the art are dropped, sparkles drawn on the art stay), tight bbox, native size, never scaled
(same clean() as tools/slice_shared.py). Rects are (x, y, w, h) from _overhaul/assets-raw.json.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_shared as ss  # noqa: E402

SRC = Path(__file__).resolve().parent.parent / "Assets" / "UI" / "new" / "bag menu"
OUT = SRC / "export"
PAD = 6

# name: (sheet, (x, y, w, h)); the Inventory id each one serves is in notes.md
SPRITES = {
    "MatSprout": ("material-cutouts", (1097, 655, 309, 211)),  # Fragment (Verdant Fragments)
    "ItemXpTicket": ("item-cosmetic-icons", (1039, 351, 281, 204)),  # XpTome
    "ItemCoinTicket": ("item-cosmetic-icons", (1397, 349, 292, 204)),  # GoldPouch
    "CosLeafyDie": ("cosmetic-icons-cutouts-2", (1081, 124, 352, 274)),  # ThornDice
    "CosCrown": ("cosmetic-icons-cutouts", (689, 147, 294, 228)),  # SproutCap
    "CosOrbitRing": ("cosmetic-icons-cutouts-2", (581, 652, 370, 220)),  # FireflyTrail
}


def main() -> None:
    OUT.mkdir(exist_ok=True)
    manifest = {}
    sheets = {}
    for name, (sheet, (x, y, w, h)) in SPRITES.items():
        im = sheets.get(sheet)
        if im is None:
            im = sheets[sheet] = np.array(Image.open(SRC / "sheets" / f"{sheet}.png").convert("RGBA"))
        r = (max(x - PAD, 0), max(y - PAD, 0), min(x + w + PAD, im.shape[1]), min(y + h + PAD, im.shape[0]))
        px = ss.clean(im[r[1] : r[3], r[0] : r[2]])
        png, data = OUT / f"Bag_{name}.png", ss.png_bytes(px)
        if not png.exists() or png.read_bytes() != data:
            png.write_bytes(data)
        manifest[name] = {"w": int(px.shape[1]), "h": int(px.shape[0]), "sheet": sheet, "rect": list(r), "slice": False}
        print(name, px.shape[1], px.shape[0])
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
