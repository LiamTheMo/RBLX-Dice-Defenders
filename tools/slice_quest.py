"""Cut the Quest Log sprites out of the source sheets into clean, upload-ready PNGs.

Usage: python tools/slice_quest.py [Name ...]   cut all (or only the named) sprites -> Assets/UI/quest menu/export/Quest_<Name>.png + manifest.json
       python tools/slice_quest.py --luau        write src/client/Controllers/QuestLog/QuestSprites.luau from manifest.json (needs "asset" ids in it)
Reuses slice_bag's cleaning/slicing helpers (bleed, dematte, measure, seamproof, ink_box). Needs Pillow + numpy.

Every export = the alpha>0 extent of the sprite's own art (neighbours masked out by connected component, or by a hand region where
glows overlap) + PAD transparent px, native scale (never upscaled). Sliced sprites (plain tileable shapes only) get a SliceCenter measured
on the export and their stretch regions rebuilt flat, exactly like slice_bag. Everything ornate is exported whole.

Rects are sheet px (x0, y0, x1, y1). Mode: comp = connected component seeded by the rect (+ extra rects), region = pixels inside the rect
only (fade = soft alpha ramp over N px on the seam edges), fill = gold bar body flood-filled from inside a track.
Sheet folders: SF quests/shared-frame-navigation, QC quests/quest-controls, QI quests/quest-icons, AC achievements/achievement-controls,
UB achievements/unlocked-badges, LB achievements/locked-badges, MD mastery/mastery-dice, MC mastery/mastery-controls, MR mastery/mastery-rewards.

name              sheet rect (id on analysis overlay)       sliced?  why
Banner            SF  (842,0,1472,189) id2                  no       ornate scroll banner (text drawn live)
DetailPanel       SF  (584,493,873,874) id16                yes      plain framed panel; radial glow flattened by the rebuild (stretch regions must be flat)
Dropdown          SF  (1303,588,1661,667) id19              yes      plain pill; right cap keeps the chevron whole
IconTabScroll/Trophy SF id14 / id13                         no       icons
SectionBanner     QC  id8 (465,205,871,307)                 no       ornate ribbon        DetailRibbon QC id9 no
Row / RowSelected QC  id15 / id18                           yes      plain bars (glow of RowSelected sits inside the margin); shared 0.97 scale so both fit 1024
Track             QC  id16                                  yes      plain dark bar
FillGold          QC  gold body inside id17                 yes      bar fill          FillGreen QC green body inside id19, yes
Stopwatch         QC  id20                                  no       icon
Icon*             QI  ids 4,2,1,3,5,6,9(+7 halo),8,13       no       icons (IconWings = wings + halo ring)
CellSelected/Copper/Locked AC ids 1,3,2                     no       glow / padlock cells
PillComplete      AC  id9                                   yes      plain green pill (label drawn live)
BarTrackAch       AC  id13                                  yes      plain track       BarFillAch gold body inside AC id12, yes
Badge*            UB  see BADGES                            no       laurel badges     *Locked LB see BADGES (icon->name mapping is a guess)
Die*/Skin*/Crown/Potion MD                                  no       icons
MasteryTrack      MC  id14 yes     MasteryFill gold body inside MC id15 yes
CheckCircle MC id9, RewardBox MC id12 (sparkles), RewardBoxPlain MC id13, PillMasteryBlank MC id10 (crown)      no
MasteryRow/MasteryRowSelected: MC id2/id3 not cut - same plain copper / gold-glow bars as quest Row/RowSelected, reuse those.
Crystals MR id7, NextRewards MR id15 (blank), BannerFlameL/R MR id2/id3                                          no
SlotCopper / SlotPurple  MR id8 split at x=609 (region)     no       square cells
Sparkle1..4       MR  id13 split at x=1489 (1,2), id14 (3), id16 (4)                                             no
GlowDie / Rays / Halo MR id1 split by region: die glow x<556, halo y<282, rays y>=282 (seams faded over 16-44 px)             no  (GlowDie unused)
"""

import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_bag as sb  # noqa: E402  (plain helpers, no import side effects)

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets" / "UI" / "quest menu"
OUT = SRC / "export"
LUAU = ROOT / "src" / "client" / "Controllers" / "QuestLog" / "QuestSprites.luau"
PAD = 10  # transparent px around the alpha>0 extent
E = 40  # extra sheet px read around each rect so soft glows are never clipped
SCALE = {"Row": 0.97, "RowSelected": 0.97}  # 1013/1025 px wide bars would pass 1024 with padding

SHEETS = {
    "SF": "quests/shared-frame-navigation.png", "QC": "quests/quest-controls.png", "QI": "quests/quest-icons.png",
    "AC": "achievements/achievement-controls.png", "UB": "achievements/unlocked-badges.png", "LB": "achievements/locked-badges.png",
    "MD": "mastery/mastery-dice.png", "MC": "mastery/mastery-controls.png", "MR": "mastery/mastery-rewards.png",
}
# name: (sheet, rect, mode, extra)   extra: dict(also=[rects], fade={edge: px}, slice=min caps or None/absent = whole, keep_right, track=rect)
S: dict[str, tuple] = {}


def add(name, sheet, rect, mode="comp", **kw):
    S[name] = (sheet, rect, mode, kw)


add("Banner", "SF", (842, 0, 1472, 189))
add("DetailPanel", "SF", (584, 493, 873, 874), sliced=(0, 0, 0, 0))
add("Dropdown", "SF", (1303, 588, 1661, 667), sliced=(0, 0, 0, 0), chevron=True)
add("IconTabScroll", "SF", (61, 384, 193, 494))
add("IconTabTrophy", "SF", (190, 382, 320, 488))
add("SectionBanner", "QC", (465, 205, 871, 307))
add("DetailRibbon", "QC", (485, 315, 890, 407))
add("Row", "QC", (21, 439, 1034, 549), sliced=(0, 0, 0, 0))
add("RowSelected", "QC", (11, 548, 1036, 667), sliced=(0, 0, 0, 0))
add("Track", "QC", (1077, 439, 1661, 515), sliced=(0, 0, 0, 0))
add("FillGold", "QC", (1073, 509, 1667, 596), "fill", sliced=(0, 0, 0, 0))
add("FillGreen", "QC", (1078, 588, 1664, 667), "fill", sliced=(0, 0, 0, 0), green=True)
add("Stopwatch", "QC", (1348, 666, 1438, 777))
for n, r in {"IconQuestScroll": (96, 15, 397, 280), "IconDie": (559, 12, 811, 278), "IconCrystals": (963, 0, 1212, 272),
             "IconChest": (1382, 13, 1683, 271), "IconCrown": (95, 291, 407, 552), "IconGalaxyDie": (549, 293, 820, 566),
             "IconCalendar": (1403, 299, 1663, 550), "IconCalendarWeek": (47, 595, 308, 857)}.items():
    add(n, "QI", r)
add("IconWings", "QI", (914, 312, 1274, 550), also=[(999, 299, 1191, 408)])
# slice=(l, t, r, b) is a fixed SliceCenter Rect (export px, pixels untouched, no seamproof): plain rounded frames, corner arc ~46 px
# after the 11-15 px margin; CellSelected adds the 14 px glow margin; CellLocked's padlock (x190-250, y26-96) sits wholly in the
# top-right corner patch (right edge 283-185 = 98 px wide, top 100 px tall), so the stretched edges never touch it.
add("CellSelected", "AC", (43, 33, 341, 328), slice=(66, 66, 237, 233))
add("CellCopper", "AC", (353, 46, 629, 326), slice=(60, 60, 225, 228))
add("CellLocked", "AC", (655, 45, 931, 327), slice=(60, 100, 185, 228))
add("PillComplete", "AC", (691, 351, 1065, 453), sliced=(0, 0, 0, 0))
add("BarTrackAch", "AC", (45, 482, 525, 579), sliced=(0, 0, 0, 0))
add("BarFillAch", "AC", (564, 480, 1047, 579), "fill", sliced=(0, 0, 0, 0))
BADGES = {  # unlocked: icon -> name by meaning; locked: guessed from icon (star/wings/dragon/crown/dice)
    "BadgeKingBig": ("UB", (578, 0, 1196, 367)), "BadgeKing": ("UB", (42, 356, 360, 585)), "BadgeRoyal": ("UB", (384, 368, 706, 611)),
    "BadgeMaterial": ("UB", (735, 355, 1040, 587)), "BadgeCrafter": ("UB", (1075, 364, 1374, 587)),
    "BadgeHoarder": ("UB", (1403, 370, 1727, 587)), "BadgeTower": ("UB", (33, 607, 358, 844)),
    "BadgeBattle": ("UB", (380, 602, 711, 849)), "BadgeXp": ("UB", (727, 624, 1051, 854)),
    "BadgeTreasure": ("UB", (1069, 629, 1393, 849)), "BadgeRift": ("UB", (1404, 619, 1748, 842)),
    "BadgeTrueLocked": ("LB", (1732, 23, 2141, 356)), "BadgeDivineLocked": ("LB", (463, 31, 876, 354)),
    "BadgeMythicLocked": ("LB", (886, 15, 1301, 360)), "BadgeKingdomLocked": ("LB", (1296, 42, 1708, 354)),
    "BadgeGalaxyLocked": ("LB", (40, 45, 445, 352)),
}
for n, (sh, r) in BADGES.items():
    add(n, sh, r)
for n, r in {"DieFire": (110, 17, 401, 313), "DieIce": (436, 20, 712, 309), "DieLeaf": (753, 16, 1032, 311),
             "DieLightning": (1067, 15, 1356, 310), "DieSun": (1387, 16, 1663, 311), "SkinFire": (176, 327, 355, 573),
             "SkinIce": (485, 325, 670, 571), "SkinLeaf": (795, 325, 982, 573), "SkinLightning": (1098, 321, 1290, 572),
             "SkinSun": (1408, 327, 1597, 578), "Crown": (512, 580, 869, 869), "Potion": (950, 592, 1179, 877)}.items():
    add(n, "MD", r)
add("MasteryTrack", "MC", (846, 660, 1592, 752), sliced=(0, 0, 0, 0))
add("MasteryFill", "MC", (843, 764, 1601, 863), "fill", sliced=(0, 0, 0, 0))
add("CheckCircle", "MC", (1275, 483, 1403, 606))
add("RewardBox", "MC", (467, 640, 711, 875))
add("RewardBoxPlain", "MC", (178, 642, 422, 875))
add("PillMasteryBlank", "MC", (577, 508, 1016, 615))
add("Crystals", "MR", (1497, 353, 1740, 565))
add("NextRewards", "MR", (854, 708, 1347, 833))
add("BannerFlameL", "MR", (999, 39, 1182, 316))
add("BannerFlameR", "MR", (1184, 46, 1376, 311))
add("SlotCopper", "MR", (362, 565, 609, 839), "region")
add("SlotPurple", "MR", (610, 565, 853, 839), "region")
add("Sparkle1", "MR", (1362, 680, 1489, 819), "region")
add("Sparkle2", "MR", (1490, 680, 1583, 819), "region")
add("Sparkle3", "MR", (1576, 686, 1661, 798))
add("Sparkle4", "MR", (1657, 711, 1734, 796))
add("GlowDie", "MR", (0, 0, 556, 598), "region", fade={"r": 44})
add("Halo", "MR", (556, 96, 984, 282), "region", fade={"l": 44, "b": 16, "r": 16})
add("Rays", "MR", (556, 282, 956, 598), "region", fade={"l": 44, "t": 16, "r": 16})


def label8(m: np.ndarray):
    """8-connected labelling by flood fill (same as the sheet analysis)."""
    H, W = m.shape
    pad = np.zeros((H + 2, W + 2), np.uint8)
    pad[1:-1, 1:-1] = m
    flat = pad.ravel().tolist()
    lab = [0] * len(flat)
    st = W + 2
    offs = (-st - 1, -st, -st + 1, -1, 1, st - 1, st, st + 1)
    cur = 0
    for s in np.flatnonzero(pad.ravel()).tolist():
        if lab[s]:
            continue
        cur += 1
        lab[s] = cur
        stack = [s]
        while stack:
            p = stack.pop()
            for o in offs:
                q = p + o
                if flat[q] and not lab[q]:
                    lab[q] = cur
                    stack.append(q)
    return np.array(lab, np.int32).reshape(H + 2, W + 2)[1:-1, 1:-1]


def dilate(m: np.ndarray, r: int) -> np.ndarray:
    H, W = m.shape
    p = np.pad(m, r)
    out = np.zeros_like(m)
    for dy in range(2 * r + 1):
        for dx in range(2 * r + 1):
            out |= p[dy : dy + H, dx : dx + W]
    return out


def component_mask(arr: np.ndarray, seeds: list[tuple]) -> np.ndarray:
    """Pixels (alpha>0) of the components that hold most of each seed rect's opaque pixels (3 px bridge, soft glow grown back in)."""
    A = arr[..., 3]
    H, W = A.shape
    d = dilate(A > 8, 3)
    Lh = label8(d[0::2, 0::2])
    L = np.where(A > 0, np.repeat(np.repeat(Lh, 2, 0), 2, 1)[:H, :W], 0)
    for _ in range(2000):  # grow labels into faint alpha>0 pixels outside the dilation
        todo = (A > 0) & (L == 0)
        P = np.pad(L, 1)
        nb = np.zeros_like(L)
        for dy in range(3):
            for dx in range(3):
                if dy != 1 or dx != 1:
                    nb = np.maximum(nb, P[dy : dy + H, dx : dx + W])
        fill = todo & (nb > 0)
        if not fill.any():
            break
        L[fill] = nb[fill]
    keep = set()
    for x0, y0, x1, y1 in seeds:
        sub = L[y0:y1, x0:x1][A[y0:y1, x0:x1] >= 160]
        sub = sub[sub > 0]
        keep.add(int(np.bincount(sub).argmax()))
    return np.isin(L, list(keep)) & (A > 0)


def flood(m: np.ndarray, seed: tuple) -> np.ndarray:
    out = np.zeros_like(m)
    out[seed] = True
    stack = [seed]
    while stack:
        y, x = stack.pop()
        for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= yy < m.shape[0] and 0 <= xx < m.shape[1] and m[yy, xx] and not out[yy, xx]:
                out[yy, xx] = True
                stack.append((yy, xx))
    return out


def fill_mask(arr: np.ndarray, region: tuple, green: bool = False) -> np.ndarray:
    """Bar body inside a track: colour match, opened by 4 px (cuts the thin rim bridges), flooded from the middle row, regrown, +3 px for
    the body's own dark outline."""
    x0, y0, x1, y1 = region
    sub = arr[y0:y1, x0:x1].astype(int)
    r, g, b, a = (sub[..., i] for i in range(4))
    hit = ((g > 140) & (r < 170) & (b < 130) & (g > r + 40) if green else (r > 200) & (g > 70) & (b < 170)) & (a > 200)
    core = ~dilate(~hit, 4)
    ym = (y1 - y0) // 2
    seed = (ym, (x1 - x0) // 4)
    assert core[seed], seed
    body = dilate(flood(core, seed), 2) & hit
    ys, xs = np.flatnonzero(body[:, seed[1]]), np.flatnonzero(body[ym])
    # silhouette = stadium over the body's measured box (+4 px: the body was opened 2 px in, so +2 px of its own outline): the colour match is too ragged along the gradient
    top, bot, left, right = ys.min() - 4, ys.max() + 5, xs.min() - 4, xs.max() + 5
    yy, xx = np.mgrid[0 : y1 - y0, 0 : x1 - x0]
    rad = (bot - top) / 2
    cx = np.clip(xx + 0.5, left + rad, right - rad)
    sdf = np.hypot(xx + 0.5 - cx, yy + 0.5 - (top + bot) / 2) - rad
    alpha = np.clip(0.5 - sdf, 0, 1)
    full = np.zeros(arr.shape[:2], np.float32)
    full[y0:y1, x0:x1] = alpha
    return full


def fade_edges(a: np.ndarray, box: tuple, fade: dict) -> None:
    x0, y0, x1, y1 = box
    yy, xx = np.mgrid[0 : a.shape[0], 0 : a.shape[1]]
    t = np.ones(a.shape, np.float32)
    for e, n in fade.items():
        d = {"l": xx - x0, "r": x1 - 1 - xx, "t": yy - y0, "b": y1 - 1 - yy}[e]
        u = np.clip(d / n, 0, 1)
        t *= u * u * (3 - 2 * u)
    a[:] = np.round(a * t).astype(np.uint8)


def cut(name: str, sheets: dict) -> tuple[np.ndarray, dict]:
    sh, (x0, y0, x1, y1), mode, kw = S[name]
    img = sheets.setdefault(sh, np.pad(np.array(Image.open(SRC / SHEETS[sh]).convert("RGBA")), ((E, E), (E, E), (0, 0))))
    rects = [(x0, y0, x1, y1)] + kw.get("also", [])
    cx0, cy0 = min(r[0] for r in rects) - E, min(r[1] for r in rects) - E
    cx1, cy1 = max(r[2] for r in rects) + E, max(r[3] for r in rects) + E
    arr = img[cy0 + E : cy1 + E, cx0 + E : cx1 + E].copy()  # sheet coords -> padded array (+E)
    loc = [(a - cx0, b - cy0, c - cx0, d - cy0) for a, b, c, d in rects]
    if mode == "comp":
        keep = component_mask(arr, loc)
    elif mode == "region":
        keep = np.zeros(arr.shape[:2], bool)
        a, b, c, d = loc[0]
        keep[b:d, a:c] = True
    else:
        keep = fill_mask(arr, loc[0], bool(kw.get("green")))
    a = arr[..., 3]
    if mode == "fill":
        a[:] = np.round(keep * 255).astype(np.uint8)
    else:
        a[~keep] = 0
        if kw.get("fade"):
            fade_edges(a, loc[0], kw["fade"])
    a[a < 8] = 0
    a[a >= 248] = 255
    ys, xs = np.where(a > 0)
    H, W = img.shape[0] - 2 * E, img.shape[1] - 2 * E
    edge = cx0 + xs.min() <= 0 or cy0 + ys.min() <= 0 or cx0 + xs.max() >= W - 1 or cy0 + ys.max() >= H - 1  # the sheet's own edge clips the art
    arr = arr[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
    k = SCALE.get(name, 1.0)
    px = np.pad(arr, ((PAD, PAD), (PAD, PAD), (0, 0)))
    if k < 1:
        px = np.array(Image.fromarray(px).resize((round(px.shape[1] * k), round(px.shape[0] * k)), Image.LANCZOS))
        px[..., 3][px[..., 3] < 8] = 0
    px[0], px[-1], px[:, 0], px[:, -1] = 0, 0, 0, 0
    px[1], px[-2], px[:, 1], px[:, -2] = 0, 0, 0, 0
    px = sb.bleed(sb.dematte(px))
    assert max(px.shape[:2]) <= 1024, f"{name} {px.shape}"
    return px, {"edgeClipped": bool(edge), "scale": k}


def chevron_cap(px: np.ndarray) -> int:
    """Right cap width (px) that keeps the white chevron whole (+4 px)."""
    w = px.shape[1]
    white = (px[..., :3].min(-1) >= 200) & (px[..., 3] == 255)
    white[:, : w // 2] = False
    return w - int(np.where(white.any(0))[0].min()) + 4


def main() -> None:
    args = sys.argv[1:]
    if args == ["--luau"]:
        return write_luau()
    OUT.mkdir(exist_ok=True)
    mf = OUT / "manifest.json"
    manifest = json.loads(mf.read_text()) if mf.exists() else {}
    sheets: dict = {}
    for name in S:
        if args and name not in args:
            continue
        px, info = cut(name, sheets)
        kw = S[name][3]
        out = {"w": px.shape[1], "h": px.shape[0]}
        note = ""
        if "sliced" in kw:
            minimum = list(kw["sliced"])
            if kw.get("chevron"):
                minimum[2] = chevron_cap(px)
            lines = sb.measure(px, tuple(minimum))
            px, line, notes = sb.seamproof(px, lines, bool(kw.get("chevron")), None, False)
            out["slice"] = line
            note = f" slice {line}" + "".join(f" WARN {n}" for n in notes)
        if "slice" in kw:
            out["slice"] = list(kw["slice"])
        out["ink"] = sb.ink_box(px)
        if info["edgeClipped"]:
            note += " WARN touches the sheet edge"
        Image.fromarray(px).save(OUT / f"Quest_{name}.png", optimize=True)
        out["asset"] = manifest.get(name, {}).get("asset", "")
        manifest[name] = out
        print(f"{name}: {px.shape[1]}x{px.shape[0]}{note}")
    mf.write_text(json.dumps(manifest, indent=1))


def write_luau() -> None:
    manifest = json.loads((OUT / "manifest.json").read_text())
    lines = [
        "-- Quest Log sprite asset ids: the one place to swap Quest Log art.",
        "-- Source PNGs: Assets/UI/quest menu/export/Quest_<Name>.png, cut from the sheets by tools/slice_quest.py (Size, Ink and Slice below",
        "-- are copied from its export/manifest.json; all are export pixels). Same entry format as BagSprites.",
        "-- Images must be owned by the experience's group (33284082). An empty id renders blank; never guess an id.",
        "-- Slice = SliceCenter for 9-slice sprites only; no Slice = ornate art, draw unsliced by its aspect.",
        "-- Ink = the opaque (alpha >= 160) box inside the export: the art is drawn smaller than its Size by this transparent margin.",
        "",
        "return {",
    ]
    for name, m in manifest.items():
        if not m.get("asset"):
            continue
        i, w, h = m["ink"], m["w"], m["h"]
        head = f'Image = "rbxassetid://{m["asset"]}", Size = Vector2.new({w}, {h}), Ink = Rect.new({i[0]}, {i[1]}, {i[2]}, {i[3]})'
        if "slice" in m:
            s = m["slice"]
            lines += [f"\t{name} = {{", f'\t\tImage = "rbxassetid://{m["asset"]}",', f"\t\tSize = Vector2.new({w}, {h}),",
                      f"\t\tInk = Rect.new({i[0]}, {i[1]}, {i[2]}, {i[3]}),", f"\t\tSlice = Rect.new({s[0]}, {s[1]}, {s[2]}, {s[3]}),", "\t},"]
        else:
            lines.append(f"\t{name} = {{ {head} }},")
    lines.append("}")
    LUAU.parent.mkdir(parents=True, exist_ok=True)
    LUAU.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")  # LF like the repo (stylua)
    subprocess.run(["stylua", str(LUAU)], check=False)  # wrap long entries the way the repo's formatter wants
    print("wrote", LUAU)


if __name__ == "__main__":
    main()
