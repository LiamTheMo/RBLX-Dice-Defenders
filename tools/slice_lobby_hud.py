"""Cut the lobby HUD sprites out of the source sheets into clean, upload-ready PNGs.

Usage: python tools/slice_lobby_hud.py
Reads Assets/UI/lobby HUD/*.png, writes Assets/UI/lobby HUD/export/<Name>.png
(names match the keys in src/client/Controllers/Sprites.luau). Needs Pillow + numpy.
Rects are alpha>=128 bounding boxes measured from the sheets (x, y, w, h).
"""

from pathlib import Path

import numpy as np
from PIL import Image

SRC = Path(__file__).resolve().parent.parent / "Assets" / "UI" / "lobby HUD"
OUT = SRC / "export"
MARGIN = 6  # source px kept around each bbox for the soft edge

# name: (sheet, (x, y, w, h), longest output side)
SPRITES = {
    "Frame_Normal": ("shared-frames.png", (40, 136, 464, 453), 256),
    "Frame_Pressed": ("shared-frames.png", (583, 136, 464, 453), 256),
    "Frame_Highlighted": ("shared-frames.png", (1126, 136, 464, 453), 256),
    "Frame_Disabled": ("shared-frames.png", (1669, 136, 464, 453), 256),
    "Icon_Shop": ("icons.png", (55, 88, 361, 307), 256),
    "Icon_Roll": ("icons.png", (507, 75, 316, 339), 256),
    "Icon_Bag": ("icons.png", (918, 72, 358, 335), 256),
    "Icon_Play": ("icons.png", (1378, 89, 337, 310), 256),
    "Icon_Codes": ("icons.png", (49, 519, 369, 287), 256),
    "Icon_Daily": ("icons.png", (500, 488, 329, 336), 256),
    "Icon_Quests": ("icons.png", (922, 503, 349, 325), 256),
    "Icon_Settings": ("icons.png", (1373, 493, 348, 340), 256),
    "Coin": ("currencies-and-dice.png", (448, 168, 271, 276), 128),
    "Gem": ("currencies-and-dice.png", (811, 173, 283, 261), 128),
    "Dice_Sun": ("currencies-and-dice.png", (66, 568, 246, 266), 256),
    "Dice_Ice": ("currencies-and-dice.png", (355, 567, 255, 265), 256),
    "Dice_Fire": ("currencies-and-dice.png", (645, 567, 248, 266), 256),
    "Dice_Leaf": ("currencies-and-dice.png", (922, 568, 256, 264), 256),
    "Dice_Lightning": ("currencies-and-dice.png", (1207, 566, 266, 269), 256),
    # Same scale for both bars so the fill lines up with the track interior.
    "XpTrack": ("xp-bar.png", (111, 59, 1950, 121), 1024),
    "XpFill": ("xp-bar.png", (117, 421, 1939, 82), 1018),
}


def threshold(rgba: np.ndarray) -> np.ndarray:
    """Drop the alpha 1-7 speckle fringe and make 'opaque' (alpha 253) truly opaque."""
    a = rgba[..., 3]
    a[a < 8] = 0
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


def main() -> None:
    OUT.mkdir(exist_ok=True)
    sheets: dict[str, Image.Image] = {}
    for name, (sheet, (x, y, w, h), side) in SPRITES.items():
        img = sheets.setdefault(sheet, Image.open(SRC / sheet).convert("RGBA"))
        box = (x - MARGIN, y - MARGIN, x + w + MARGIN, y + h + MARGIN)
        crop = Image.fromarray(threshold(np.array(img.crop(box))))
        k = side / max(crop.size)
        if name == "XpFill":  # keep the track's scale, not its own
            k = 1024 / (1950 + 2 * MARGIN)
        size = (round(crop.width * k), round(crop.height * k))
        # Pillow premultiplies RGBA when resizing, so bleed afterwards.
        out = Image.fromarray(bleed(np.array(crop.resize(size, Image.LANCZOS))))
        out.save(OUT / f"{name}.png", optimize=True)
        assert out.width <= 1024 and out.height <= 1024, name
        print(f"{name}: {size[0]}x{size[1]}")


if __name__ == "__main__":
    main()
