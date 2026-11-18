"""Cut the Shop product art out of the new sheets into upload-ready PNGs (whole assets, never sliced).

Usage: python tools/slice_shop.py   -> Assets/UI/new/shop menu/export/Shop_<Name>.png + manifest.json
(a PNG is only rewritten when its bytes change, so a rerun never touches an uploaded file)

Sheets: Assets/UI/new/shop menu/sheets/tabs-and-products.png (RGBA, a grid of cells with a grey frame between them) and shop-elements.png.
Every cut is the sprite's own rect plus MARGIN px (clipped to the sheet), run through slice_shared.clean: only the solid blobs
(alpha >= 128) stay plus a 1 px antialias ring, partly transparent pixels take the nearest solid pixel's colour (no coloured fringe
or halo), tight bbox, native size, never scaled. The sheet-frame component of tabs-and-products (#0) is not an asset.
Window, tabs, close X, pills, coin and gem are the shared ones (Shared_*, Sprites.Coin / Sprites.Gem): not cut here.
"""

import io
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_shared as ss  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets" / "UI" / "new" / "shop menu"
OUT = SRC / "export"
MARGIN = 3
# name: (sheet, annotated component rect x, y, w, h in sheet px, opening radius for slice_shared.clean)
COMP = {
    "HeroArt": ("tabs-and-products", (1393, 687, 317, 182), 2),  # chest, dice, potion, gems group (#13)
    "GemBag": ("tabs-and-products", (132, 688, 178, 189), 2),  # #14
    "ChestOpenGems": ("tabs-and-products", (558, 691, 201, 188), 2),  # #15
    "Clover": ("tabs-and-products", (1022, 464, 179, 191), 2),  # #11
    "Crown": ("tabs-and-products", (550, 460, 230, 187), 2),  # #9
    "Robux": ("shop-elements", (1405, 873, 93, 104), 0),  # #24 white hex icon
}


def cut(name: str) -> tuple[np.ndarray, list]:
    sheet, (x, y, w, h), opening = COMP[name]
    img = np.array(Image.open(SRC / "sheets" / f"{sheet}.png").convert("RGBA"))
    x0, y0 = max(0, x - MARGIN), max(0, y - MARGIN)
    x1, y1 = min(img.shape[1], x + w + MARGIN), min(img.shape[0], y + h + MARGIN)
    return ss.clean(img[y0:y1, x0:x1].copy(), opening), [x, y, w, h]


def main() -> None:
    OUT.mkdir(exist_ok=True)
    manifest = {}
    for name in COMP:
        px, rect = cut(name)
        data = ss.png_bytes(px)
        png = OUT / f"Shop_{name}.png"
        if not png.exists() or png.read_bytes() != data:
            png.write_bytes(data)
        h, w = px.shape[:2]
        manifest[name] = {"w": w, "h": h, "sheet": f"{COMP[name][0]}.png", "rect": rect, "slice": False}
        print(name, w, h)
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
