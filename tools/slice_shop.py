"""Cut the 11 Shop sprites out of the source sheets into upload-ready PNGs.

Usage: python tools/slice_shop.py   cut all -> Assets/UI/shop menu/export/Shop_<Name>.png + manifest.json
(a PNG is only rewritten when its bytes change). Reuses slice_quest's helpers (connected components, alpha clean-up, PAD margin) and
slice_bag's dematte / bleed / ink_box. All sprites are whole (never 9-sliced).

COMP: name -> (sheet, tight alpha>8 rect in sheet px, clear rects, mode). comp = connected component seeded by the rect after the clear rects
(neighbours that touch the rect, e.g. the STARTER pin or the glow burst) are zeroed; region = every pixel inside the rect (glow included).
Heading plates are split from the plate below by KEEP_Y / the crown column.
"""

import io
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_bag as sb  # noqa: E402
import slice_quest as sq  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets" / "UI" / "shop menu"
OUT = SRC / "export"
SHEETS = {"H": "shop-headings.png", "T": "shop-tabs.png", "S": "shop-starter-details.png", "P": "shop-product-icons.png"}
CROWN = (1262, 380, 1293, 1000)  # the GAMEPASSES crown ball that touches the plate above
COMP = {
    "Emblem": ("H", (479, 5, 764, 254), [(440, 238, 506, 262)], "comp"),
    "StarterCap": ("H", (903, 240, 1649, 391), [(0, 392, 2000, 1000), CROWN], "comp"),
    "GPHeading": ("H", (897, 380, 1660, 526), [(0, 0, 2000, 380), (0, 380, 1262, 392), (1293, 380, 2000, 392)], "comp"),
    "GemsHeading": ("H", (900, 540, 1637, 638), [], "comp"),
    "IconStar": ("T", (205, 727, 352, 865), [], "comp"),
    "IconShards": ("T", (961, 725, 1142, 868), [], "comp"),
    "Robux": ("S", (707, 484, 853, 651), [], "comp"),
    "HeroArt": ("S", (43, 7, 741, 387), [], "region"),
    "Clover": ("P", (386, 578, 605, 814), [(386, 790, 445, 815)], "comp"),
    "GemBag": ("P", (907, 23, 1206, 319), [], "comp"),
    "ChestOpenGems": ("P", (507, 7, 853, 329), [], "comp"),
}


def cut(name: str) -> np.ndarray:
    sh, (x0, y0, x1, y1), clear, mode = COMP[name]
    img = np.pad(np.array(Image.open(SRC / SHEETS[sh]).convert("RGBA")), ((sq.E, sq.E), (sq.E, sq.E), (0, 0)))
    cx0, cy0, cx1, cy1 = x0 - sq.E, y0 - sq.E, x1 + sq.E, y1 + sq.E
    arr = img[cy0 + sq.E : cy1 + sq.E, cx0 + sq.E : cx1 + sq.E].copy()
    for a, b, c, d in clear:
        arr[max(b - cy0, 0) : max(d - cy0, 0), max(a - cx0, 0) : max(c - cx0, 0), 3] = 0
    loc = (x0 - cx0, y0 - cy0, x1 - cx0, y1 - cy0)
    a = arr[..., 3]
    if mode == "comp":
        keep = sq.component_mask(arr, [loc])
    else:
        keep = np.zeros(a.shape, bool)
        keep[loc[1] : loc[3], loc[0] : loc[2]] = True
    a[~keep] = 0
    a[a < 8] = 0
    a[a >= 248] = 255
    ys, xs = np.where(a > 0)
    px = np.pad(arr[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1], ((sq.PAD, sq.PAD), (sq.PAD, sq.PAD), (0, 0)))
    px[0], px[-1], px[:, 0], px[:, -1] = 0, 0, 0, 0
    px = sb.bleed(sb.dematte(px))
    assert max(px.shape[:2]) <= 1024, f"{name} {px.shape}"
    return px


def main() -> None:
    OUT.mkdir(exist_ok=True)
    mf = OUT / "manifest.json"
    old = json.loads(mf.read_text()) if mf.exists() else {}
    manifest = {}
    for name in COMP:
        px = cut(name)
        buf = io.BytesIO()
        Image.fromarray(px).save(buf, format="PNG", optimize=True)
        png = OUT / f"Shop_{name}.png"
        if not png.exists() or png.read_bytes() != buf.getvalue():
            png.write_bytes(buf.getvalue())
        h, w = px.shape[:2]
        manifest[name] = {"w": w, "h": h, "ink": sb.ink_box(px), "asset": old.get(name, {}).get("asset", "")}
        print(name, w, h, manifest[name]["ink"])
    mf.write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
