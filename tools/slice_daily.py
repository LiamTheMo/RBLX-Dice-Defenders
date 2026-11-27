"""Cut the Daily menu icons out of Assets/UI/new/daily menu/sheets/daily-elements.png into upload-ready whole PNGs.

Usage: python tools/slice_daily.py -> Assets/UI/new/daily menu/export/Daily_<Name>.png + manifest.json
(a PNG is rewritten only when its bytes change). Cards, day plates, pills, progress track and fill are code-drawn (Bag/Chrome.luau); gems and
coins are Sprites.Gem / Sprites.Coin (owner rule); dice use Sprites.DieArt. Only the four icons below are art. Cuts use slice_common.clean
(solid blobs + 1 px ring, glow dropped, edge colour from the sprite's own outline, tight bbox, never scaled).
Rects are grid cells of the sheet (sheet px, x0 y0 x1 y1), each holding one sprite and no neighbour.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_common as sc  # noqa: E402

SRC = sc.UI / "daily menu"
OUT = SRC / "export"
SHEET = SRC / "sheets" / "daily-elements.png"
CELLS = {
    "Calendar": (1425, 575, 1595, 730),
    "Stopwatch": (1605, 575, 1750, 735),
    "Chest": (670, 705, 860, 865),
    "Potion": (385, 735, 520, 870),
}


def main() -> None:
    OUT.mkdir(exist_ok=True)
    sheet = sc.load_rgba(SHEET)
    manifest = {}
    for name, r in CELLS.items():
        px = sc.clean(sheet[r[1] : r[3], r[0] : r[2]])
        sc.save_png(OUT / f"Daily_{name}.png", px)
        manifest[name] = sc.entry(px, "daily-elements", r)
        print(name, px.shape[1], px.shape[0])
    sc.write_manifest(OUT, manifest)


if __name__ == "__main__":
    main()
