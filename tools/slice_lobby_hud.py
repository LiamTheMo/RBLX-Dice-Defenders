"""Cut the lobby HUD sprites out of the source sheets into clean, upload-ready PNGs.

Usage: python tools/slice_lobby_hud.py
Reads Assets/UI/lobby HUD/*.png, writes Assets/UI/lobby HUD/export/<Name>.png
(names match the keys in src/client/Controllers/Sprites.luau). Needs Pillow + numpy.
Rects are alpha>16 bounding boxes measured from the sheets (x, y, w, h); Icon_Roll is its own file, alpha>=8 bbox.
Shares the crop / margin / de-matte / 9-slice rebuild code with tools/slice_bag.py. XpTrack and XpFill (drawn sliced by LobbyHud)
get their SliceCenter in export/manifest.json.
"""

import json
from pathlib import Path

from PIL import Image

from slice_bag import cut, fit, seamproof, measure

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
    "Coin": ("Coin.png", (56, 44, 1126, 1140), 128),
    "Gem": ("Gem.png", (2, 2, 124, 114), 128),
    "Dice_Sun": ("Dice_Sun.png", (5, 5, 229, 246), 256),
    "Dice_Ice": ("Dice_Ice.png", (5, 5, 238, 247), 256),
    "Dice_Fire": ("Dice_Fire.png", (5, 5, 229, 246), 256),
    "Dice_Leaf": ("Dice_Leaf.png", (5, 5, 239, 247), 256),
    "Dice_Lightning": ("Dice_Lightning.png", (3, 5, 248, 246), 256),
    # Same scale for both bars so the fill lines up with the track interior.
    "XpTrack": ("xp-bar.png", (44, 68, 2084, 84), 1024),
    "XpFill": ("xp-bar.png", (52, 426, 2068, 54), 1024),
}
HEIGHTS = {"XpTrack": 24}  # export height (margin included) ~2x the drawn 12 px
SLICED = {"XpTrack", "XpFill"}


def main() -> None:
    OUT.mkdir(exist_ok=True)
    sheets: dict[str, Image.Image] = {}
    manifest = {}
    shared = None
    for name, (sheet, rect, side) in SPRITES.items():
        img = sheets.setdefault(sheet, Image.open(SRC / sheet).convert("RGBA"))
        if name == "XpFill":  # keep the track's scale and margin, not its own
            k, m = shared
        else:
            k, m = fit(rect[2], rect[3], MARGIN, side=side, height=HEIGHTS.get(name), inc_margin=True)
        if name == "XpTrack":
            shared = (k, m)
        px, masked = cut(img, rect, MARGIN, k, m)
        info = {"w": px.shape[1], "h": px.shape[0]}
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
