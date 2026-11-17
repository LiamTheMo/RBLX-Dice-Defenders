"""Cut the Codes art (gift, sparkle, info badge) into upload-ready PNGs.

Usage: python tools/slice_codes.py -> Assets/UI/new/codes menu/export/Codes_<Name>.png + manifest.json
Sheet: Assets/UI/new/codes menu/sheets/codes-elements.png. Whole assets at native size (never scaled, never sliced), cleaned with
slice_shared.clean (glow drips and fringe dropped, edge = the art's own outline). The crystals are cut as two whole shards (decoration, not
currency). Text is live.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_shared as ss  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
BASE = ROOT / "Assets" / "UI" / "new" / "codes menu"
SHEET = BASE / "sheets" / "codes-elements.png"
OUT = BASE / "export"
# name: (grid cell in the sheet (x0, y0, x1, y1), opening radius). Thin sparkle tips would not survive an opening.
CELLS = {
    "Gift": ((665, 5, 945, 270), ss.OPEN),
    "Sparkle": ((1385, 50, 1545, 225), 0),
    "InfoBadge": ((150, 740, 280, 870), ss.OPEN),
    "ShardBlue": ((1000, 30, 1145, 255), ss.OPEN),
    "ShardPurple": ((1200, 45, 1335, 255), ss.OPEN),
}


def main() -> None:
    OUT.mkdir(exist_ok=True)
    sheet = np.array(Image.open(SHEET).convert("RGBA"))
    manifest = {}
    for name, (r, opening) in CELLS.items():
        px = ss.clean(sheet[r[1] : r[3], r[0] : r[2]], opening)
        png = OUT / f"Codes_{name}.png"
        data = ss.png_bytes(px)
        if not png.exists() or png.read_bytes() != data:
            png.write_bytes(data)
        manifest[name] = {"w": int(px.shape[1]), "h": int(px.shape[0]), "sheet": "codes-elements.png", "rect": list(r), "slice": False}
        print(name, px.shape[1], px.shape[0])
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
