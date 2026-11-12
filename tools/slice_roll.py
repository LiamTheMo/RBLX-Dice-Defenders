"""Cut the 26 Roll menu sprites out of the source sheets into upload-ready PNGs.

Usage: python tools/slice_roll.py            cut all -> Assets/UI/roll menu/export/Roll_<Name>.png + manifest.json
                                             (a PNG is only rewritten when its bytes change, so a rerun never touches an uploaded file)
       python tools/slice_roll.py --luau     write src/client/Controllers/Roll/RollSprites.luau from manifest.json (needs "asset" ids in it)
Reuses slice_quest's cutter (connected-component pick, alpha<8 cleared, PAD margin, dematte, bleed, native scale) and slice_bag's ink_box.

Sheets (Assets/UI/roll menu/, all RGBA): F roll-featured-sprites, R roll-rarities-sprites, I roll-icons-text-sprites, B roll-buttons-sprites.
COMP below lists every sprite with its sheet and rect (sheet px): the dice, banner die, header plate, crowns / stars / info icon, pity pill,
bar track / fill, the six rarity rows, the two featured pills, the three ROLL buttons and the price chip.
Horizontal 9-slice sprites (SLICED + HeaderPlate): Slice = (left cap, mid-1, right cap, mid). A cap is the rounded end (silhouette arc + 2 px) or,
where highlights and inner rims still change past it, up to the last column that changes by more than TOL, + 2 (see settle_caps): the centre
band is the whole plain middle, so stretching it shows no step. HeaderPlate keeps SLICE_X px of cap (diamond + angled end + margin).
"""

import io
import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_bag as sb  # noqa: E402
import slice_quest as sq  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets" / "UI" / "roll menu"
OUT = SRC / "export"
LUAU = ROOT / "src" / "client" / "Controllers" / "Roll" / "RollSprites.luau"
sq.SRC = SRC
sq.SHEETS.update({"F": "roll-featured-sprites.png", "R": "roll-rarities-sprites.png", "I": "roll-icons-text-sprites.png", "B": "roll-buttons-sprites.png"})

COMP = {
    "DieLegendary": ("F", (1030, 25, 1405, 390)),
    "DieMythic": ("F", (1408, 0, 1800, 390)),
    "HeaderPlate": ("R", (185, 125, 845, 225)),
    "CrownEpic": ("I", (1380, 25, 1600, 170)),
    "StarsRare": ("I", (1640, 60, 1920, 150)),
    "StarCommon": ("I", (1970, 30, 2115, 150)),
    "Info": ("I", (1040, 225, 1235, 410)),
    "BannerDie": ("F", (30, 10, 580, 300)),
    "PityPill": ("F", (385, 545, 700, 665)),
    "BarTrack": ("F", (750, 540, 1600, 610)),
    "BarFill": ("F", (750, 635, 1225, 700)),
    "CrownGold": ("I", (1120, 25, 1340, 170)),
    "RowSecret": ("R", (900, 245, 1565, 335)),
    "RowMythic": ("R", (900, 335, 1565, 420)),
    "RowLegendary": ("R", (900, 425, 1565, 510)),
    "RowEpic": ("R", (900, 510, 1565, 595)),
    "RowRare": ("R", (900, 595, 1565, 675)),
    "RowCommon": ("R", (900, 675, 1565, 760)),
    "PillLegendary": ("R", (900, 770, 1255, 870)),
    "PillMythic": ("R", (1295, 770, 1665, 870)),
    "BtnGold": ("B", (900, 40, 1310, 190)),
    "BtnPurple": ("B", (1315, 40, 1745, 190)),
    "BtnGrey": ("B", (900, 560, 1310, 710)),
    "PriceChip": ("B", (555, 755, 830, 845)),
    "Die1": ("I", (60, 20, 240, 200)),
    "Dice3": ("I", (310, 10, 540, 200)),
}
# The rarity rows touch (their glows overlap): each row is cut inside the midline y-band between it and its neighbours (sheet px), the rest cleared.
BANDS = {"RowSecret": (240, 337), "RowMythic": (337, 427), "RowLegendary": (427, 512), "RowEpic": (512, 596), "RowRare": (596, 676), "RowCommon": (676, 766)}
SLICED = {"PityPill", "BarTrack", "BarFill", "RowSecret", "RowMythic", "RowLegendary", "RowEpic", "RowRare", "RowCommon", "PillLegendary", "PillMythic",
          "BtnGold", "BtnPurple", "BtnGrey", "PriceChip"}  # horizontal 9-slice: caps = silhouette corner arc (sb.measure) + 2 px, 1 px centre band
SLICE_X = 100  # px of cap kept each side: left diamond ends ~x 80, angled end ~x 48 (measured on the export)


TOL = 12  # per-column change (97th percentile over rows, premultiplied colour) below which the art counts as the plain middle
MAX_CAP = 0.3  # a sprite whose texture never settles (a gradient bar) keeps the silhouette-arc caps


def settle_caps(px, right_arc: int, left_arc: int) -> tuple[int, int]:
    """Left / right cap widths: the rounded end (silhouette arc + 2, as sb.measure) or, if the art is still changing past it (highlights
    and inner rims bend later than the silhouette), up to the last column that changes by more than TOL, + 2. The centre band is the whole
    plain middle between the caps, so stretching it never repeats or drops a changing column (no step where cap meets centre)."""
    h, w = px.shape[:2]
    a = px.astype(float)
    pm = a[..., :3] * a[..., 3:4] / 255
    d = sq.np.percentile(sq.np.abs(pm[:, 1:, :] - pm[:, :-1, :]).max(2), 97, axis=0)
    lc, rc = left_arc, right_arc
    left = [x + 1 for x in range(w // 2) if d[x] > TOL]
    right = [w - 1 - x for x in range(w - 2, w // 2, -1) if d[x] > TOL]
    if left and max(left) + 2 <= w * MAX_CAP:
        lc = max(lc, max(left) + 2)
    if right and max(right) + 2 <= w * MAX_CAP:
        rc = max(rc, max(right) + 2)
    return join_columns(px, lc, rc)


JOIN_SEARCH = 45  # px past the settled cap in which a boundary column may move


def join_columns(px, lc: int, rc: int) -> tuple[int, int]:
    """Move each slice boundary to the column where the luminance step between the two columns it separates is smallest.
    jump[x] = max over the face rows (alpha >= 200 in both columns) of |luma[x+1] - luma[x]|. The left boundary lc separates columns lc-1 | lc,
    the right boundary (w - rc) separates w-rc-1 | w-rc; each sits inside a uniform run, so the stretched centre meets the caps without a seam."""
    h, w = px.shape[:2]
    a = px.astype(float)
    luma = a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114
    solid = a[..., 3] >= 200
    both = solid[:, 1:] & solid[:, :-1]
    jump = sq.np.where(both, sq.np.abs(luma[:, 1:] - luma[:, :-1]), 0).max(axis=0)  # jump[x]: columns x | x+1
    lim = int(w * MAX_CAP)
    best_l = min(range(lc, min(lc + JOIN_SEARCH, lim) + 1), key=lambda c: (jump[c - 1], c))
    best_r = min(range(rc, min(rc + JOIN_SEARCH, lim) + 1), key=lambda c: (jump[w - c - 1], c))
    return best_l, best_r


def main() -> None:
    if sys.argv[1:] == ["--luau"]:
        return write_luau()
    OUT.mkdir(exist_ok=True)
    manifest, sheets = {}, {}
    mf = OUT / "manifest.json"
    old = json.loads(mf.read_text()) if mf.exists() else {}
    for name, (sh, rect) in COMP.items():
        if name in BANDS:  # private copy of the (padded) sheet with the other rows cleared
            sheets[name] = sq.np.pad(sq.np.array(Image.open(SRC / sq.SHEETS[sh]).convert("RGBA")), ((sq.E, sq.E), (sq.E, sq.E), (0, 0)))
            sheets[name][: BANDS[name][0] + sq.E, :, 3] = 0
            sheets[name][BANDS[name][1] + sq.E :, :, 3] = 0
            sq.SHEETS[name], sh = sq.SHEETS[sh], name
        sq.S[name] = (sh, rect, "comp", {})
        px, info = sq.cut(name, sheets)
        buf = io.BytesIO()
        Image.fromarray(px).save(buf, format="PNG", optimize=True)
        png = OUT / f"Roll_{name}.png"
        if not png.exists() or png.read_bytes() != buf.getvalue():
            png.write_bytes(buf.getvalue())
        h, w = px.shape[:2]
        manifest[name] = {"w": w, "h": h, "ink": sb.ink_box(px), "asset": old.get(name, {}).get("asset", "")}
        if name in SLICED:
            m = sb.measure(px, (0, 0, 0, 0))
            lc, rc = settle_caps(px, w - m[2], m[0])
            manifest[name]["slice"] = [lc, h // 2 - 1, w - rc, h // 2]
        if name == "HeaderPlate":
            manifest[name]["slice"] = [SLICE_X, h // 2 - 1, w - SLICE_X, h // 2]
        print(name, w, h, manifest[name]["ink"], "WARN sheet edge" if info["edgeClipped"] else "")
    mf.write_text(json.dumps(manifest, indent=1))


def write_luau() -> None:
    manifest = json.loads((OUT / "manifest.json").read_text())
    lines = [
        "-- Roll menu sprite asset ids (new sprites only; everything else reuses Bag / Quest Log / Play sprites).",
        "-- Source PNGs: Assets/UI/roll menu/export/Roll_<Name>.png, cut from roll-featured / roll-rarities / roll-icons-text sheets by",
        "-- tools/slice_roll.py (Size and Ink are copied from its export/manifest.json; export pixels). Same entry format as PlaySprites.",
        "-- Images must be owned by the experience's group (33284082). An empty id renders blank; never guess an id.",
        "-- Slice = SliceCenter for the horizontal 9-slice sprites (caps hold the diamonds / rounded ends); the rest draw unsliced.",
        "-- Ink = the opaque (alpha >= 160) box inside the export: the art is drawn smaller than its Size by this transparent margin.",
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
            lines.append("\t\tSlice = Rect.new({}, {}, {}, {}),".format(*m["slice"]))
        lines.append("\t},")
    lines.append("}")
    LUAU.parent.mkdir(parents=True, exist_ok=True)
    LUAU.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print("wrote", LUAU, "- now run: stylua", LUAU)


if __name__ == "__main__":
    main()
