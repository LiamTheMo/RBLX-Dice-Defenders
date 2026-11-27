"""Cut the game HUD art into upload-ready PNGs at the exact atlas rects (native size, no resize, no slicing).

Usage: python tools/slice_game_hud.py  -> Assets/UI/new/game hud/export/Game_<Name>.png + manifest.json

Source: game hud/game-hud-without-text.png (the text-free sheet); rects from game hud/game-hud-atlas.json ([x, y, w, h]).
Fails if any crop edge pixel is semi-opaque (alpha 1..254 on a transparent-gutter neighbour would mean a bleed) -- it only reports
the edge alpha, so the caller can judge. Asset ids are preserved from an existing manifest.json.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_common as sc  # noqa: E402

HUD = sc.UI / "game hud"
OUT = HUD / "export"
SHEET = HUD / "game-hud-without-text.png"

# output name: atlas sprite key
SPRITES = {
    "StatusBar": "status_background",
    "StatusDivider": "status_divider",
    "HeartFull": "icon_heart_full",
    "HeartEmpty": "icon_heart_empty",
    "UpgradeBlank": "upgrade_background",
}


def main() -> None:
    atlas = json.loads((HUD / "game-hud-atlas.json").read_text())["sprites"]
    sheet = Image.open(SHEET).convert("RGBA")
    OUT.mkdir(exist_ok=True)
    mf = OUT / "manifest.json"
    old = json.loads(mf.read_text()) if mf.exists() else {}
    manifest = {}
    for name, key in SPRITES.items():
        x, y, w, h = atlas[key]["rect"]
        crop = sheet.crop((x, y, x + w, y + h))
        a = np.array(crop)[..., 3]
        edge = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
        png = OUT / f"Game_{name}.png"
        crop.save(png, optimize=True)
        manifest[name] = {"file": png.name, "w": w, "h": h, "rect": [x, y, w, h], "atlas": key,
                          "sheet": SHEET.name, "slice": False, "maxEdgeAlpha": int(edge.max()),
                          "cornerAlpha": [int(a[0, 0]), int(a[0, -1]), int(a[-1, 0]), int(a[-1, -1])]}
        manifest[name].update({k: v for k, v in old.get(name, {}).items() if k in ("assetId", "moderation", "preload")})
        print(name, w, h, "maxEdgeAlpha", manifest[name]["maxEdgeAlpha"], "corners", manifest[name]["cornerAlpha"])
    mf.write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
