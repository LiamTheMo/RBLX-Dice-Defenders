"""Cut the Bag menu sprites out of the source sheets into clean, upload-ready PNGs.

Usage: python tools/slice_bag.py
Reads Assets/UI/bag menu/<Folder>/<sheet>.png, writes Assets/UI/bag menu/export/Bag_<Name>.png
plus export/manifest.json (name, w, h, slice) -> copy into src/client/Controllers/Bag/BagSprites.luau.
Rects are alpha>=160 bounding boxes measured from the sheets (x, y, w, h). Needs Pillow + numpy.
Sprites in SLICED get a SliceCenter measured on the export (corner arc + rim), never estimated.
"""

import json
from pathlib import Path

import numpy as np
from PIL import Image

SRC = Path(__file__).resolve().parent.parent / "Assets" / "UI" / "bag menu"
OUT = SRC / "export"
SHEET_MARGIN = 4  # source px kept around each bbox for the soft edge
GLOW_MARGIN = 20  # bursts fade far past their alpha>=160 bbox

# name: (sheet, (x, y, w, h), longest output side of the bbox, margin). Never upscaled (side is capped at native).
SPRITES = {
    # Frames
    "Window": ("Dice/frames-regenerated.png", (195, 12, 1140, 499), 1016, SHEET_MARGIN),
    "LeftPanel": ("Dice/frames-regenerated.png", (17, 540, 578, 451), 1024, SHEET_MARGIN),
    "Detail": ("Dice/frames-regenerated.png", (607, 540, 297, 451), 1024, SHEET_MARGIN),
    "Strip": ("Dice/frames-regenerated.png", (921, 801, 601, 131), 1024, SHEET_MARGIN),
    # Controls
    "TabPurple": ("Dice/controls-regenerated.png", (48, 17, 706, 158), 600, SHEET_MARGIN),
    "TabGold": ("Dice/controls-regenerated.png", (781, 17, 705, 158), 600, SHEET_MARGIN),
    "BtnGreen": ("Dice/controls-regenerated.png", (57, 213, 344, 143), 256, SHEET_MARGIN),
    "BtnRed": ("Dice/controls-regenerated.png", (421, 213, 341, 144), 256, SHEET_MARGIN),
    "BtnGold": ("Dice/controls-regenerated.png", (781, 213, 343, 143), 256, SHEET_MARGIN),
    "BtnPurple": ("Dice/controls-regenerated.png", (1144, 213, 338, 143), 256, SHEET_MARGIN),
    "Search": ("Dice/controls-regenerated.png", (49, 403, 882, 110), 800, SHEET_MARGIN),
    "Sort": ("Dice/controls-regenerated.png", (968, 403, 506, 114), 506, SHEET_MARGIN),
    "CardIdle": ("Dice/controls-regenerated.png", (270, 544, 317, 318), 256, SHEET_MARGIN),
    "CardSelected": ("Dice/controls-regenerated.png", (624, 544, 321, 318), 258, SHEET_MARGIN),  # same scale as idle
    "Close": ("Dice/controls-regenerated.png", (1054, 619, 184, 173), 144, SHEET_MARGIN),
    "LevelTrack": ("Dice/controls-regenerated.png", (127, 904, 687, 87), 687, SHEET_MARGIN),
    "LevelFill": ("Dice/controls-regenerated.png", (864, 922, 519, 51), 519, SHEET_MARGIN),  # native, like the track
    # Title
    "Ribbon": ("Cosmetics/icons-regenerated.png", (26, 820, 690, 182), 690, SHEET_MARGIN),
    "BagDie": ("new menu dice.png", (166, 34, 840, 1169), 512, SHEET_MARGIN),
    # Pills (Materials controls 15-20)
    "PillGold": ("Materials/controls-regenerated.png", (52, 781, 254, 81), 254, SHEET_MARGIN),
    "PillPurple": ("Materials/controls-regenerated.png", (341, 781, 245, 81), 245, SHEET_MARGIN),
    "PillBlue": ("Materials/controls-regenerated.png", (621, 781, 250, 81), 250, SHEET_MARGIN),
    "PillGreen": ("Materials/controls-regenerated.png", (904, 781, 252, 81), 252, SHEET_MARGIN),
    "PillGrey": ("Materials/controls-regenerated.png", (1189, 781, 250, 81), 250, SHEET_MARGIN),
    "PillPink": ("Materials/controls-regenerated.png", (1473, 781, 250, 81), 250, SHEET_MARGIN),
    # Stepper (Materials controls 6/7/8)
    "QtyMinus": ("Materials/controls-regenerated.png", (473, 367, 153, 131), 153, SHEET_MARGIN),
    "QtyField": ("Materials/controls-regenerated.png", (657, 372, 460, 118), 460, SHEET_MARGIN),
    "QtyPlus": ("Materials/controls-regenerated.png", (1148, 367, 153, 132), 153, SHEET_MARGIN),
    # Icons
    "IconDice": ("Shared/dice-tab-icon.png", (210, 89, 884, 980), 256, SHEET_MARGIN),
    "IconCrystals": ("Dice/icons-regenerated.png", (338, 100, 252, 242), 256, SHEET_MARGIN),
    "IconPotion": ("Dice/icons-regenerated.png", (628, 88, 200, 266), 256, SHEET_MARGIN),
    "IconCrown": ("Dice/icons-regenerated.png", (874, 104, 294, 224), 256, SHEET_MARGIN),
    "Lock": ("Dice/icons-regenerated.png", (1228, 96, 204, 242), 128, SHEET_MARGIN),
    "Coins": ("Dice/icons-regenerated.png", (40, 430, 210, 174), 128, SHEET_MARGIN),
    "Check": ("Dice/icons-regenerated.png", (280, 452, 174, 142), 128, SHEET_MARGIN),
    "Magnifier": ("Dice/icons-regenerated.png", (482, 416, 178, 196), 128, SHEET_MARGIN),
    "SortArrows": ("Dice/icons-regenerated.png", (696, 442, 202, 150), 128, SHEET_MARGIN),  # up + down
    "CheckCircle": ("Materials/icons-regenerated.png", (1220, 290, 168, 170), 128, SHEET_MARGIN),
    "Flask": ("Items/icons-regenerated.png", (810, 420, 190, 214), 256, SHEET_MARGIN),
    "EquippedPill": ("Dice/icons-badges-and-effects.png", (36, 472, 204, 64), 204, SHEET_MARGIN),
}
GLOW_SRC = SRC / "new glow.png"  # neutral grey ray burst; GlowCommon is it as-is, the rest are tinted
GLOW_BBOX = (122, 50, 1094, 1081)  # alpha>=8 extent (x, y, w, h)
GLOW_SIDE = 512
# rarity: tint hex, taken from the matching Bag_Pill* sprite (Legendary warmer orange-gold, Secret crimson)
GLOWS = {
    "GlowCommon": None, "GlowUncommon": "42BC02", "GlowRare": "0185FA", "GlowEpic": "8D15F1",
    "GlowLegendary": "FF9A1F", "GlowMythic": "FF4FCB", "GlowSecret": "DC143C",
}
# 9-slice sprites. Value = minimum (l, t, r, b) in export px that the slice must keep clear (e.g. Sort's baked chevron).
SLICED = {
    "Window": None, "LeftPanel": None, "Detail": None, "Strip": None, "TabPurple": None, "TabGold": None,
    "BtnGreen": None, "BtnRed": None, "BtnGold": None, "BtnPurple": None, "Search": None,
    "Sort": (0, 0, 122, 0), "CardIdle": None, "CardSelected": None, "LevelTrack": None, "LevelFill": None,
    "PillGold": None, "PillPurple": None, "PillBlue": None, "PillGreen": None, "PillGrey": None, "PillPink": None,
    "QtyMinus": None, "QtyField": None, "QtyPlus": None, "EquippedPill": (0, 0, 0, 0),
}


def tint_glow(rgba: np.ndarray, hexcol: str | None) -> np.ndarray:
    """Clean alpha, fade the rim, recolour: mids/edges take the hue, the hot core and ray highlights stay near-white."""
    rgba = rgba.copy()
    a = rgba[..., 3].astype(np.float32)
    a[a < 12] = 0
    h, w = a.shape
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2))
    a *= 1 - np.clip((r - 0.86) / 0.14, 0, 1) ** 2 * (3 - 2 * np.clip((r - 0.86) / 0.14, 0, 1))  # smooth rim falloff
    rgba[..., 3] = np.round(a).astype(np.uint8)
    if hexcol:
        tint = np.array([int(hexcol[i : i + 2], 16) for i in (0, 2, 4)], np.float32) / 255
        lum = rgba[..., :3].astype(np.float32).mean(-1) / 255
        hot = np.clip((lum - 0.6) / 0.35, 0, 1)[..., None] ** 1.5
        base = tint * np.clip(lum / 0.75, 0, 1.2)[..., None]
        rgba[..., :3] = np.clip((base * (1 - hot) + hot) * 255, 0, 255).astype(np.uint8)
    return rgba


def threshold(rgba: np.ndarray, soft: bool) -> np.ndarray:
    """Drop the faint alpha fringe and make near-opaque truly opaque (soft glows only lose alpha < 8)."""
    a = rgba[..., 3]
    a[a < (8 if soft else 32)] = 0
    a[a >= 248] = 255
    return rgba


def bleed(rgba: np.ndarray) -> np.ndarray:
    """Spread edge colour into transparent pixels so Roblox's bilinear sampling has no dark halo."""
    a = rgba[..., 3]
    rgb = rgba[..., :3].astype(np.float32)
    known = a > 0
    for _ in range(8):
        acc = np.zeros_like(rgb)
        cnt = np.zeros(a.shape, np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            k = np.roll(known, (dy, dx), (0, 1))
            acc += np.roll(rgb, (dy, dx), (0, 1)) * k[..., None]
            cnt += k
        grow = ~known & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow, None]
        known |= grow
    rgba[..., :3] = rgb.astype(np.uint8)
    return rgba


def arc_extent(mask: np.ndarray) -> int:
    """Columns from the left before the silhouette's top and bottom edges run straight (the corner arc)."""
    best = 0
    for m in (mask, mask[::-1]):
        top = np.where(m.any(0), m.argmax(0), m.shape[0])  # first opaque row per column, from this edge
        x = next((i for i in range(m.shape[1] // 2) if top[i] <= top[m.shape[1] // 2] + 1), m.shape[1] // 2)
        best = max(best, x)
    return best


def measure(img: np.ndarray, minimum: tuple[int, int, int, int]) -> list[int]:
    """SliceCenter (l, t, r, b) in export px: the silhouette's corner arc (concentric rims end with it) plus 2 px."""
    h, w, _ = img.shape
    mask = img[..., 3] >= 160
    l, r = arc_extent(mask), arc_extent(mask[:, ::-1])
    t, b = arc_extent(mask.T), arc_extent(mask.T[:, ::-1])
    l, t, r, b = (min(v + 2, lim) for v, lim in ((l, w // 2 - 1), (t, h // 2 - 1), (r, w // 2 - 1), (b, h // 2 - 1)))
    l, t, r, b = max(l, minimum[0]), max(t, minimum[1]), max(r, minimum[2]), max(b, minimum[3])
    return [l, t, w - r, h - b]


def main() -> None:
    OUT.mkdir(exist_ok=True)
    sheets: dict[str, Image.Image] = {}
    manifest = {}
    for name, (sheet, (x, y, w, h), side, margin) in SPRITES.items():
        img = sheets.setdefault(sheet, Image.open(SRC / sheet).convert("RGBA"))
        box = (x - margin, y - margin, x + w + margin, y + h + margin)
        crop = Image.fromarray(threshold(np.array(img.crop(box)), False))
        k = min(1.0, side / max(w, h))  # never upscale
        size = (round(crop.width * k), round(crop.height * k))
        # Pillow premultiplies RGBA when resizing, so bleed afterwards.
        px = bleed(np.array(crop.resize(size, Image.LANCZOS) if k < 1 else crop))
        Image.fromarray(px).save(OUT / f"Bag_{name}.png", optimize=True)
        assert size[0] <= 1024 and size[1] <= 1024, name
        manifest[name] = {"w": size[0], "h": size[1]}
        if name in SLICED:
            manifest[name]["slice"] = measure(px, SLICED[name] or (0, 0, 0, 0))
        print(f"{name}: {size[0]}x{size[1]} {manifest[name].get('slice', '')}")
    gx, gy, gw, gh = GLOW_BBOX
    glow = Image.open(GLOW_SRC).convert("RGBA").crop((gx, gy, gx + gw, gy + gh))
    size = (round(gw * GLOW_SIDE / max(gw, gh)), round(gh * GLOW_SIDE / max(gw, gh)))
    for name, col in GLOWS.items():
        px = bleed(np.array(Image.fromarray(tint_glow(np.array(glow), col)).resize(size, Image.LANCZOS)))
        Image.fromarray(px).save(OUT / f"Bag_{name}.png", optimize=True)
        manifest[name] = {"w": size[0], "h": size[1]}
        print(f"{name}: {size[0]}x{size[1]} {col}")
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
