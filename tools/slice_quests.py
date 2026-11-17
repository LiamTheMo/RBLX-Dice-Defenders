"""Cut the QUESTS menu icons (new sheet) into upload-ready PNGs.

Usage: python tools/slice_quests.py   -> Assets/UI/new/quests menu/export/Quests_<Name>.png + manifest.json
Sheet: Assets/UI/new/quests menu/sheets/quest-and-mastery-icons.png (RGBA). Only the icons the menu draws are cut; everything else in the
menu (tabs, close X, CLAIM pill, check, lock, coin, gem) is the shared art, and bars, panels, fields and the scrollbar are code-drawn.
Every cut is a whole asset at native size: the crop is the icon's own sheet rect (never touches a neighbour), only the solid blobs plus a
1 px antialias ring are kept (the sheet's soft glow drips are dropped), partly transparent pixels take the nearest solid colour, tight bbox.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_shared as ss  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets" / "UI" / "new" / "quests menu"
OUT = SRC / "export"
SHEET = SRC / "sheets" / "quest-and-mastery-icons.png"
PAD = 6  # sheet px read around the icon's bbox

# name: (x0, y0, x1, y1) icon bbox in the sheet (solid blob extents)
ICONS = {
    "Calendar": (64, 65, 235, 233),  # red calendar page with grid: DAILY header
    "CalendarWeek": (286, 63, 440, 233),  # empty calendar page: WEEKLY header (the 7 is live text)
    "Stopwatch": (59, 282, 203, 452),  # reset timer pill
}


def main() -> None:
    OUT.mkdir(exist_ok=True)
    sheet = np.array(Image.open(SHEET).convert("RGBA"))
    manifest = {}
    for name, (x0, y0, x1, y1) in ICONS.items():
        r = (x0 - PAD, y0 - PAD, x1 + PAD, y1 + PAD)
        px = ss.clean(sheet[r[1] : r[3], r[0] : r[2]], 0)
        (OUT / f"Quests_{name}.png").write_bytes(ss.png_bytes(px))
        manifest[name] = {"w": int(px.shape[1]), "h": int(px.shape[0]), "sheet": "quest-and-mastery-icons", "rect": list(r), "slice": False}
        print(name, px.shape[1], px.shape[0])
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
