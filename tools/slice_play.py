"""Cut the NEW Play menu sprites out of the source sheets into upload-ready PNGs.

Usage: python tools/slice_play.py [Name ...]   cut all (or only the named) sprites -> Assets/UI/play menu/export/Play_<Name>.png + manifest.json
       python tools/slice_play.py --luau       write src/client/Controllers/Play/PlaySprites.luau from manifest.json (needs "asset" ids in it)
Reuses slice_quest's cutter (connected-component pick of the sprite, speck removal, PAD margin, dematte, bleed, native scale) and slice_bag's ink_box.

Sheets (Assets/UI/play menu/): H play-headings, I play-icons-transparent (both clean alpha), W play-world-cards (semi-transparent haze outside the
cards: alpha <= 254 everywhere, so only the pixels inside the card rims are used, forced to alpha 255).
NOT used: play-blank-controls, play-reward-icons (haze background, duplicate art). Everything else in the Play menu reuses uploaded sprites.

name          sheet rect (sheet px)       mode      why
LockCircle    I (262,532,468,742)         comp      grey ring + white padlock (locked status circle)
RewardBanner  I (752,195,995,390)         comp      purple banner, gold crown and gold knobs
PlayArrow     I (738,540,900,730)         comp      white play triangle (START button)
ScrollBase    H (62,215,835,378)          comp      blank parchment scroll: shared banner base for Bag / Quest Log / Play
GemPin        H (1458,250,1700,355)       comp      purple gem + gold wings hanging under the scroll centre
LaurelL/R     H (1140,230,1250,375) / (1283,230,1398,375)   comp   gold laurels beside the emblem
World*        W inner box of one card     crop      landscape interior only: inner edge of the gold rim + INSET px (clears the rounded rim at the corners),
                                                    alpha forced to 255, native scale. WorldDice = the big top preview card (highest res); the others =
                                                    the blank small cards. Card / CardSel / Preview = ImageRect crops (x0,y0,x1,y1 export px): the largest rect of the
                                                    target aspect (363x148, 363x168, 372x205), centred horizontally, top-aligned (the focal art is in the top half).
PurpleBox     REUSED id, not cut: Quest Log's old SlotPurple, Assets/UI/quest menu/export/Quest_SlotPurple.png (251x247, ink 14,12,238,236),
              group-owned asset 105278600388247. Slice = sb.measure on that export (corner arcs 48/45/47/44). Tiles + wide odds box.
Card and preview rims are a plain 2-3 px line (+ gold glow when selected) in the reference: live UIStroke, no rim sprite is cut.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_bag as sb  # noqa: E402
import slice_quest as sq  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets" / "UI" / "play menu"
OUT = SRC / "export"
LUAU = ROOT / "src" / "client" / "Controllers" / "Play" / "PlaySprites.luau"
sq.SRC = SRC
sq.SHEETS.update({"H": "play-headings.png", "I": "play-icons-transparent.png"})

COMP = {
    "LockCircle": ("I", (262, 532, 468, 742)),
    "RewardBanner": ("I", (752, 195, 995, 390)),
    "PlayArrow": ("I", (738, 540, 900, 730)),
    "ScrollBase": ("H", (62, 215, 835, 378)),
    "GemPin": ("H", (1458, 250, 1700, 355)),
    "LaurelL": ("H", (1140, 230, 1250, 375)),
    "LaurelR": ("H", (1283, 230, 1398, 375)),
}
INSET = {"WorldDice": 18, "WorldShadow": 11}  # px inside the rim's inner edge; default 10 (corner arc radius ~30 on the small cards, ~60 on the big one)
WORLDS = {  # inner edge of the gold rim (x0,y0,x1,y1) measured on play-world-cards.png
    "WorldDice": (318, 44, 1221, 393),
    "WorldFrost": (1174, 488, 1512, 688),
    "WorldMagma": (408, 767, 745, 967),
    "WorldShadow": (1173, 766, 1514, 969),
}
REUSED = {"PurpleBox": {"w": 251, "h": 247, "ink": [14, 12, 238, 236], "slice": [48, 45, 204, 203], "asset": "105278600388247"}}
TARGETS = {"Card": (363, 148), "CardSel": (363, 168), "Preview": (372, 205)}


def crop_rect(w: int, h: int, tw: int, th: int) -> list[int]:
    cw, ch = (w, round(w * th / tw)) if w / h <= tw / th else (round(h * tw / th), h)
    x0 = (w - cw) // 2
    return [x0, 0, x0 + cw, ch]


def world(name: str) -> tuple[np.ndarray, dict]:
    x0, y0, x1, y1 = WORLDS[name]
    d = INSET.get(name, 10)
    px = np.array(Image.open(SRC / "play-world-cards.png").convert("RGBA"))[y0 + d : y1 - d, x0 + d : x1 - d].copy()
    px[..., 3] = 255
    h, w = px.shape[:2]
    return px, {"rects": {k: crop_rect(w, h, *t) for k, t in TARGETS.items()}}


def main() -> None:
    args = sys.argv[1:]
    if args == ["--luau"]:
        return write_luau()
    OUT.mkdir(exist_ok=True)
    mf = OUT / "manifest.json"
    manifest = json.loads(mf.read_text()) if mf.exists() else {}
    sheets: dict = {}
    for name in [*COMP, *WORLDS]:
        if args and name not in args:
            continue
        if name in WORLDS:
            px, extra = world(name)
            note = ""
        else:
            sq.S[name] = (COMP[name][0], COMP[name][1], "comp", {})
            px, info = sq.cut(name, sheets)
            extra, note = {}, " WARN touches the sheet edge" if info["edgeClipped"] else ""
        Image.fromarray(px).save(OUT / f"Play_{name}.png", optimize=True)
        manifest[name] = {"w": px.shape[1], "h": px.shape[0], "ink": sb.ink_box(px), **extra,
                          "asset": manifest.get(name, {}).get("asset", "")}
        print(f"{name}: {px.shape[1]}x{px.shape[0]} ink {manifest[name]['ink']}{note}", extra.get("rects", ""))
    manifest.update(REUSED)
    mf.write_text(json.dumps(manifest, indent=1))


def write_luau() -> None:
    manifest = json.loads((OUT / "manifest.json").read_text())
    lines = [
        "-- Play menu sprite asset ids (only the sprites the Play menu adds; everything else reuses Bag / Quest Log / lobby sprites).",
        "-- Source PNGs: Assets/UI/play menu/export/Play_<Name>.png, cut from the sheets by tools/slice_play.py (Size, Ink and the Rects below",
        "-- are copied from its export/manifest.json; all are export pixels). Same entry format as QuestSprites.",
        "-- Images must be owned by the experience's group (33284082). An empty id renders blank; never guess an id.",
        "-- Slice = SliceCenter for 9-slice sprites only; no Slice = ornate art, draw unsliced by its aspect (none here: all unsliced).",
        "-- Ink = the opaque (alpha >= 160) box inside the export: the art is drawn smaller than its Size by this transparent margin.",
        "-- World* = opaque landscape interiors (no rim; the rim is a live UIStroke). Card / CardSel / Preview = ImageRectOffset/Size crops",
        "-- (x0, y0, x1, y1) for the left-column card (363x148), the selected card (363x168) and the right preview (372x205).",
        "",
        "return {",
    ]
    for name, m in manifest.items():
        if not m.get("asset"):
            continue
        i = m["ink"]
        lines += [f"\t{name} = {{", f'\t\tImage = "rbxassetid://{m["asset"]}",', f"\t\tSize = Vector2.new({m['w']}, {m['h']}),",
                  f"\t\tInk = Rect.new({i[0]}, {i[1]}, {i[2]}, {i[3]}),"]
        if "slice" in m:
            lines.append("		Slice = Rect.new({}, {}, {}, {}),".format(*m["slice"]))
        for k, r in m.get("rects", {}).items():
            lines.append(f"\t\t{k} = Rect.new({r[0]}, {r[1]}, {r[2]}, {r[3]}),")
        lines.append("\t},")
    lines.append("}")
    LUAU.parent.mkdir(parents=True, exist_ok=True)
    LUAU.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print("wrote", LUAU, "- now run: stylua", LUAU)


if __name__ == "__main__":
    main()
