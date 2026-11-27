"""Cut the NEW result-menu assets (plan.md N1-N6, N8-N13) out of the source sheets.

Usage: python tools/slice_results.py
Reads Assets/UI/new/result menus/<folder>/<sheet>.png, writes <root>/export/Results_<Name>.png + export/manifest.json.
Per asset: crop sheet rect + margin, keep only connected pieces lying inside the rect (drops neighbours, merges sparkles that
sit in it), kill the faint alpha haze (alpha <= HAZE -> 0, rescale), rebuild edge RGB from the nearest opaque pixel (no matte
fringe), trim to alpha > 0, never upscale. The ribbon is desaturated to a near-white neutral so ImageColor3 multiply-tints it.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_common as sc  # noqa: E402

ROOT = sc.UI / "result menus"
OUT = ROOT / "export"
MARGIN, HAZE = 8, 24

# name: (sheet, (x, y, w, h) solid-alpha bbox from _work/sheets_catalog.md, neutral)
SPRITES = {
    "CrestShieldDie": ("coop/summary-elements.png", (61, 22, 229, 252), False),
    "ShieldCube": ("coop/summary-elements.png", (1047, 31, 173, 243), False),
    "Skull": ("coop/summary-elements.png", (1513, 42, 198, 213), False),
    "XpStar": ("coop/summary-elements.png", (81, 291, 198, 195), False),
    "RibbonNeutral": ("coop/summary-elements.png", (36, 500, 533, 145), True),
    "ContinueGreen": ("shared/continue-blank-states.png", (47, 55, 991, 186), False),
    "TrophyGold": ("1v1-shared/headers.png", (110, 19, 264, 197), False),
    "TrophyRed": ("1v1-shared/headers.png", (411, 19, 259, 197), False),
    "DieBlue": ("1v1-shared/headers.png", (48, 428, 134, 144), False),
    "DiePurple": ("1v1-shared/headers.png", (220, 430, 129, 142), False),
    "DieRed": ("1v1-shared/headers.png", (383, 430, 136, 143), False),
    "DieWhite": ("1v1-shared/headers.png", (550, 429, 132, 143), False),
}


def neutral(rgb, a):
    # luminance only; body median -> 236 so multiply tint keeps the colour, outline stays dark
    l = rgb @ np.array([0.299, 0.587, 0.114])
    ref = np.median(l[a >= 128])
    l = np.clip(l * 236.0 / ref, 0, 255)
    return np.repeat(l[..., None], 3, axis=2)


def cut(sheet, rect, neu, sheets):
    x, y, w, h = rect
    im = sheets[sheet]
    x0, y0 = max(x - MARGIN, 0), max(y - MARGIN, 0)
    c = np.array(im.crop((x0, y0, min(x + w + MARGIN, im.width), min(y + h + MARGIN, im.height)))).astype(np.float32)
    rgb, a = c[..., :3], c[..., 3]
    a = np.where(a <= HAZE, 0, (a - HAZE) * 255.0 / (255 - HAZE))
    lab, n = ndi.label(ndi.binary_dilation(a >= 128, iterations=3))
    keep = np.zeros(a.shape, bool)
    inx0, iny0, inx1, iny1 = x - x0 - 6, y - y0 - 6, x - x0 + w + 6, y - y0 + h + 6
    for i, sl in enumerate(ndi.find_objects(lab), 1):  # keep pieces whose bbox lies inside the rect (+6, covers the 3 px dilation)
        if sl[1].start >= inx0 and sl[0].start >= iny0 and sl[1].stop <= inx1 and sl[0].stop <= iny1:
            keep |= lab == i
    keep = ndi.binary_dilation(keep, iterations=4)
    a = np.where(keep, a, 0)
    solid = a >= 128
    idx = ndi.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    rgb = rgb[idx[0], idx[1]]  # soft edge pixels (alpha < 128) take the colour of the nearest solid pixel
    if neu:
        rgb = neutral(rgb, a)
    out = np.dstack([rgb, a]).round().clip(0, 255).astype(np.uint8)
    ys, xs = np.where(out[..., 3] > 0)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    return Image.fromarray(out).crop(box), (x0 + box[0], y0 + box[1], box[2] - box[0], box[3] - box[1])


def main():
    OUT.mkdir(exist_ok=True)
    sheets, manifest = {}, []
    for name, (sheet, rect, neu) in SPRITES.items():
        if sheet not in sheets:
            sheets[sheet] = Image.open(ROOT / sheet).convert("RGBA")
        img, src = cut(sheet, rect, neu, sheets)
        assert img.width <= rect[2] + 2 * MARGIN and img.height <= rect[3] + 2 * MARGIN
        img.save(OUT / f"Results_{name}.png", optimize=True)
        manifest.append({"name": name, "w": img.width, "h": img.height, "sheet": sheet, "source": [int(v) for v in src],
                         "trimmed": True, "tintBase": neu, "slice": False})
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))
    for m in manifest:
        print(m["name"], m["w"], m["h"])


if __name__ == "__main__":
    main()
