"""Cut the lobby HUD art (menu tiles, deck slot frames, plus, gear, 10 die icons) into upload-ready PNGs.

Usage: python tools/slice_lobby_hud.py  -> Assets/UI/new/lobby hud/export/HUD_<Name>.png + manifest.json

Sheets: lobby hud/sheets/menu-buttons.png (top row = tiles with the label baked in), lobby hud/sheets/hud-elements.png,
bag menu/sheets/dice-icons-clean.png (the one source of all 10 die icons: the shared/dice PNGs cover only 5 and differ in style/scale).
Each sprite is a connected component of the sheet (alpha >= 128, seed rect inside it); neighbours are masked out (only the component
dilated by PAD survives), then slice_shared.clean() drops the sheet's coloured glow, recolours the soft edge from the sprite's own outline
and trims to the bbox. Native size, never scaled, no slicing.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_quest as sq  # noqa: E402
import slice_shared as ss  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
NEW = ROOT / "Assets" / "UI" / "new"
OUT = NEW / "lobby hud" / "export"
MENU = NEW / "lobby hud" / "sheets" / "menu-buttons.png"
ELEM = NEW / "lobby hud" / "sheets" / "hud-elements.png"
DICE = NEW / "bag menu" / "sheets" / "dice-icons-clean.png"
PAD = 8

# name: (sheet path, a point inside the component, glow kept? (slot highlight))
SPRITES = {
    "Shop": (MENU, (130, 340)),
    "Roll": (MENU, (350, 340)),
    "Bag": (MENU, (565, 340)),
    "Play": (MENU, (780, 340)),
    "Codes": (MENU, (990, 340)),
    "Daily": (MENU, (1205, 340)),
    "Quests": (MENU, (1420, 340)),
    "Slot": (ELEM, (330, 190)),  # dark fill, white rim
    "SlotGlow": (ELEM, (700, 190)),  # purple neon rim
    "SlotGrey": (ELEM, (1050, 190)),  # lighter grey fill
    "Plus": (ELEM, (1350, 183)),
    "Gear": (ELEM, (1612, 750)),
    "Die_Sun": (DICE, (260, 250)),
    "Die_Ice": (DICE, (575, 250)),
    "Die_Fire": (DICE, (890, 250)),
    "Die_Leaf": (DICE, (1205, 250)),
    "Die_Lightning": (DICE, (1520, 250)),
    "Die_Wind": (DICE, (260, 615)),
    "Die_Rock": (DICE, (575, 615)),
    "Die_Water": (DICE, (890, 615)),
    "Die_Light": (DICE, (1205, 615)),
    "Die_Shadow": (DICE, (1520, 615)),
}


def main() -> None:
    OUT.mkdir(exist_ok=True)
    manifest = {}
    cache = {}
    for name, (path, (px_, py_)) in SPRITES.items():
        if path not in cache:
            arr = np.array(Image.open(path).convert("RGBA"))
            cache[path] = (arr, sq.label8(arr[..., 3] >= 128))
        arr, lab = cache[path]
        comp = lab == lab[py_, px_]
        assert lab[py_, px_] > 0, name
        ys, xs = np.where(comp)
        x0, y0, x1, y1 = max(xs.min() - 20, 0), max(ys.min() - 20, 0), xs.max() + 21, ys.max() + 21
        crop = arr[y0:y1, x0:x1].copy()
        keep = sq.dilate(comp, PAD)[y0:y1, x0:x1]
        crop[..., 3] = np.where(keep, crop[..., 3], 0)
        out = ss.clean(crop, 0 if path == DICE or name.startswith("Slot") else ss.OPEN)
        png = OUT / f"HUD_{name}.png"
        data = ss.png_bytes(out)
        if not png.exists() or png.read_bytes() != data:
            png.write_bytes(data)
        manifest[name] = {"w": int(out.shape[1]), "h": int(out.shape[0]), "sheet": path.name,
                          "rect": [int(x0), int(y0), int(x1), int(y1)], "slice": False}
        print(name, out.shape[1], out.shape[0])
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
