"""Cut the Codes art (gift, sparkle, info badge) into upload-ready PNGs.

Usage: python tools/slice_codes.py -> Assets/UI/new/codes menu/export/Codes_<Name>.png + manifest.json
Sheet: Assets/UI/new/codes menu/sheets/codes-elements.png. Whole assets at native size (never scaled, never sliced), cleaned with
slice_common.clean (glow drips and fringe dropped, edge = the art's own outline). The crystals are cut as two whole shards (decoration, not
currency). Text is live.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_common as sc  # noqa: E402

BASE = sc.UI / "codes menu"
SHEET = BASE / "sheets" / "codes-elements.png"
OUT = BASE / "export"
# name: (grid cell in the sheet (x0, y0, x1, y1), opening radius). Thin sparkle tips would not survive an opening.
CELLS = {
    "Gift": ((665, 5, 945, 270), sc.OPEN),
    "Sparkle": ((1385, 50, 1545, 225), 0),
    "InfoBadge": ((150, 740, 280, 870), sc.OPEN),
    "ShardBlue": ((1000, 30, 1145, 255), sc.OPEN),
    "ShardPurple": ((1200, 45, 1335, 255), sc.OPEN),
}


def main() -> None:
    OUT.mkdir(exist_ok=True)
    sheet = sc.load_rgba(SHEET)
    manifest = {}
    for name, (r, opening) in CELLS.items():
        px = sc.clean(sheet[r[1] : r[3], r[0] : r[2]], opening)
        sc.save_png(OUT / f"Codes_{name}.png", px)
        manifest[name] = sc.entry(px, "codes-elements.png", r)
        print(name, px.shape[1], px.shape[0])
    sc.write_manifest(OUT, manifest)


if __name__ == "__main__":
    main()
