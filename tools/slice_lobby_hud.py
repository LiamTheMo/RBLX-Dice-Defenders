"""Cut the lobby HUD sprites out of the source sheets into clean, upload-ready PNGs.

Usage: python tools/slice_lobby_hud.py [Name ...]  (names given: cut only those, merge into manifest.json)
Reads Assets/UI/lobby HUD/*.png, writes Assets/UI/lobby HUD/export/<Name>.png
(names match the keys in src/client/Controllers/Sprites.luau). Needs Pillow + numpy.
Rects are alpha>16 bounding boxes measured from the sheets (x, y, w, h); Icon_Roll is its own file, alpha>=8 bbox.
XpFill is scaled to sit inside the track's channel; its manifest "pad" is how far (track-export px) its box sits in from each end.
Shares the crop / margin / de-matte / 9-slice rebuild code with tools/slice_bag.py. XpTrack and XpFill (drawn sliced by LobbyHud)
get their SliceCenter in export/manifest.json.
"""

import json
import math
import sys
from pathlib import Path

from PIL import Image

from slice_bag import cut, fit, measure, recolor_tone, seamproof

SRC = Path(__file__).resolve().parent.parent / "Assets" / "UI" / "lobby HUD"
OUT = SRC / "export"
MARGIN = 6  # minimum source px kept around each bbox for the soft edge (slice_bag.fit raises it at heavy downscale)

# name: (sheet, (x, y, w, h), longest output side)
SPRITES = {
    "Frame_Normal": ("shared-frames.png", (42, 134, 464, 454), 256),
    "Frame_Pressed": ("shared-frames.png", (578, 134, 462, 452), 256),
    "Frame_Highlighted": ("shared-frames.png", (1120, 134, 464, 454), 256),
    "Frame_Disabled": ("shared-frames.png", (1658, 134, 466, 454), 256),
    "Icon_Shop": ("icons.png", (50, 70, 366, 330), 256),
    "Icon_Roll": ("Icon_Roll.png", (82, 136, 1159, 830), 256),
    "Icon_Bag": ("icons.png", (920, 58, 376, 350), 256),
    "Icon_Play": ("icons.png", (1362, 70, 350, 326), 256),
    "Icon_Codes": ("icons.png", (54, 514, 366, 308), 256),
    "Icon_Daily": ("icons.png", (500, 482, 330, 358), 256),
    "Icon_Quests": ("icons.png", (918, 494, 358, 346), 256),
    "Icon_Settings": ("icons.png", (1370, 494, 344, 342), 256),
    "Coin": ("Coin.png", (47, 29, 1139, 1168), 128),
    "Gem": ("Gem.png", (212, 153, 881, 854), 128),
    "Dice_Sun": ("Dice_Sun.png", (5, 5, 229, 246), 256),
    "Dice_Ice": ("Dice_Ice.png", (5, 5, 238, 247), 256),
    "Dice_Fire": ("Dice_Fire.png", (5, 5, 229, 246), 256),
    "Dice_Leaf": ("Dice_Leaf.png", (5, 5, 239, 247), 256),
    "Dice_Lightning": ("Dice_Lightning.png", (3, 5, 248, 246), 256),
    "XpTrack": ("xptrack.png", (13, 217, 2146, 278), 1024),
    "XpFill": ("xpfill.png", (79, 268, 2004, 187), 1024),  # scaled to fit XP_CHANNEL, see main()
}
HEIGHTS = {"XpTrack": 24}  # export height (margin included) ~2x the drawn 12 px
SLICED = {"XpTrack", "XpFill"}
RECOLOR = {"Icon_Settings": lambda a: recolor_tone(a, [("F99E09", "FCBB13", 45)])}  # gear body -> the HUD reference gold
PAD = {"xptrack.png": 64}  # transparent border added to the sheet: its art runs to 13 px from the edge, less than the margin
XP_CHANNEL = (70, 273, 2032, 163)  # xptrack.png: the purple channel inside the copper rim (x, y, w, h)
XP_FILL_INSET = 4  # source px of dark channel kept around the fill, as in the xpbar.png mock-up


def main() -> None:
    OUT.mkdir(exist_ok=True)
    sheets: dict[str, Image.Image] = {}
    only = set(sys.argv[1:])
    old = OUT / "manifest.json"
    manifest = json.loads(old.read_text()) if only and old.exists() else {}
    shared = None
    for name, (sheet, rect, side) in SPRITES.items():
        if only and name not in only:
            continue
        if sheet not in sheets:
            img = Image.open(SRC / sheet).convert("RGBA")
            p = PAD.get(sheet, 0)
            sheets[sheet] = Image.new("RGBA", (img.width + 2 * p, img.height + 2 * p))
            sheets[sheet].paste(img, (p, p))
        img = sheets[sheet]
        p = PAD.get(sheet, 0)
        rect = (rect[0] + p, rect[1] + p, rect[2], rect[3])
        if name == "XpFill":  # track's scale times pill-to-channel height, so the pill sits inside the copper rim
            k = shared[0] * (XP_CHANNEL[3] - 2 * XP_FILL_INSET) / rect[3]
            m = max(MARGIN, math.ceil(3 / k) + 2)
        else:
            k, m = fit(rect[2], rect[3], MARGIN, side=side, height=HEIGHTS.get(name), inc_margin=True)
        px, masked = cut(img, rect, MARGIN, k, m, RECOLOR.get(name))
        if name == "XpTrack":
            shared = (px.shape[1] / (rect[2] + 2 * m), m)  # effective x scale after rounding, margin
        info = {"w": px.shape[1], "h": px.shape[0]}
        if name == "XpFill":
            # Track-export px from each end of the track to the fill's box (its own margin included); the art is symmetric.
            kt, mt = shared
            track_rect = SPRITES["XpTrack"][1]
            left = (mt + XP_CHANNEL[0] + XP_FILL_INSET - track_rect[0]) * kt - m * px.shape[1] / (rect[2] + 2 * m)
            right = (mt + track_rect[0] + track_rect[2] - (XP_CHANNEL[0] + XP_CHANNEL[2] - XP_FILL_INSET)) * kt - m * px.shape[1] / (rect[2] + 2 * m)
            info["pad"] = [round(left, 2), round(right, 2)]
        note = f"k={k:.3f} m={m}" + (f" MASKED {masked} opaque neighbour px" if masked else "")
        if name in SLICED:
            px, line, notes = seamproof(px, measure(px, (0, 0, 0, 0)))
            info["slice"] = line
            note += f" {line}" + "".join(f" WARN {n}" for n in notes)
        Image.fromarray(px).save(OUT / f"{name}.png", optimize=True)
        manifest[name] = info
        print(f"{name}: {px.shape[1]}x{px.shape[0]} {note}")
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
