"""Cut the Bag menu icons for the real Config/Inventory entries out of the new sheets (Assets/UI/new/bag menu/sheets).

Usage: python tools/slice_bag_new.py  -> Assets/UI/new/bag menu/export/Bag_<Name>.png + manifest.json
tools/slice_bag.py is the old-art cutter (its Assets/UI/old inputs).
Every cut: the sheet component's own bbox (+ PAD), only its solid blobs + a 1 px antialias ring (glow drips and sparkle
specks outside the art are dropped, sparkles drawn on the art stay), tight bbox, native size, never scaled
(slice_common.clean). Rects are (x, y, w, h) from _overhaul/assets-raw.json.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_common as sc  # noqa: E402

SRC = sc.UI / "bag menu"
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
            im = sheets[sheet] = sc.load_rgba(SRC / "sheets" / f"{sheet}.png")
        r = (max(x - PAD, 0), max(y - PAD, 0), min(x + w + PAD, im.shape[1]), min(y + h + PAD, im.shape[0]))
        px = sc.clean(im[r[1] : r[3], r[0] : r[2]])
        sc.save_png(OUT / f"Bag_{name}.png", px)
        manifest[name] = sc.entry(px, sheet, r)
        print(name, px.shape[1], px.shape[0])
    sc.write_manifest(OUT, manifest)


if __name__ == "__main__":
    main()
