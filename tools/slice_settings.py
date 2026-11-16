"""Cut the Settings menu sprites out of the source sheets into upload-ready PNGs.

Usage: python tools/slice_settings.py   cut all -> Assets/UI/settings menu/export/Settings_<Name>.png + manifest.json
(a PNG is only rewritten when its bytes change; the manifest keeps each upload's asset id). Reuses slice_quest's helpers
(component_mask, PAD / E margins) and slice_bag's dematte / bleed / ink_box.

COMP: name -> (sheet, ink bbox at alpha>60 in sheet px, extra seed rects). Mode comp: every connected component that holds >= MINPX
opaque (alpha>=160) pixels inside the rect is kept (multi-part icons: sparkles, ring dashes, cursor rays, wiggles; the extras are
additional seeds for tiny pieces); neighbours outside the rect are dropped, so touching-but-separate art is never rectangle-bled.
Alpha: < 8 -> 0, >= 248 -> 255, then dematte + bleed. Margins: PAD transparent px around the alpha>0 extent (E sheet px read around the
rect so glows are never clipped). All sprites fit by aspect (never sliced) except SLICED.

SLICED (9-slice, plain/tileable only): name -> (sheet, rect, left, mid, right, vertical).
  The cut is compacted: `left` export px of the left end, a `mid` px strip continuing it (no left seam; the bars carry a slight lengthwise shade), `right` px of the right end
  (>1024 wide sheets would not upload). Slice = Rect(left, top, left + mid, bottom) measured on the export:
  RowFrame 230 + 40 + 230, Rule 70 + 40 + 70 (centre strip = the uniform bar), ValuePill keeps its full width with a 20 px centre
  strip. Vertical: a 2 px band at the middle row, so rims/corners keep their native thickness and only the interior stretches.
TabGraphics has no PNG: it is a monitor-only ImageRect of ScreenShake (SHEET_RECTS), mapped into the export by the cut origin.
"""

import io
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_bag as sb  # noqa: E402
import slice_quest as sq  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets" / "UI" / "settings menu"
OUT = SRC / "export"
SHEETS = {
    "C": "shared/controls-and-states-sheet.png",
    "T": "shared/tabs-and-banner-icons-sheet.png",
    "A": "audio tab/audio-icons-and-sliders-sheet.png",
    "G": "graphics tab/graphics-icons-sheet.png",
    "P": "gameplay tab/gameplay-icons-sheet.png",
    "M": "misc tab/misc-icons-sheet.png",
}
MINPX = 40
COMP = {
    "ToggleOn": ("C", (930, 42, 1258, 159), []),
    "ToggleOff": ("C", (1341, 41, 1678, 158), []),
    "Refresh": ("C", (1548, 206, 1682, 340), []),
    "Diamond": ("C", (848, 784, 926, 863), []),
    "GearPair": ("T", (315, 32, 706, 296), []),
    "Die": ("T", (983, 73, 1156, 246), []),
    "Knob": ("A", (211, 630, 385, 806), []),
    "ArrowLeft": ("M", (96, 681, 350, 852), []),
    "ArrowRight": ("M", (497, 681, 741, 853), []),
    "MasterVolume": ("A", (89, 131, 342, 340), []),
    "Music": ("A", (432, 116, 662, 341), [(441, 186, 475, 222)]),
    "SoundEffects": ("A", (750, 124, 1026, 348), []),
    "InterfaceSounds": ("A", (1102, 117, 1318, 340), [(1102, 197, 1165, 236)]),
    "Ambience": ("A", (1405, 114, 1690, 340), []),
    "EffectsQuality": ("G", (88, 46, 380, 266), []),
    "Projectile": ("G", (538, 53, 825, 295), []),
    "Shadows": ("G", (986, 47, 1247, 300), []),
    "ScreenShake": ("G", (1363, 73, 1720, 282), []),
    "UiScale": ("G", (101, 363, 335, 595), []),
    "EffectScale": ("G", (543, 367, 781, 588), []),
    "AutoSkip": ("P", (90, 145, 375, 355), []),
    "DamageNumbers": ("P", (488, 100, 830, 395), []),
    "RangeRings": ("P", (921, 80, 1259, 415), []),
    "Announce": ("P", (1364, 112, 1706, 388), []),
    "PlacementGrid": ("P", (185, 509, 477, 802), []),
    "AutoClose": ("P", (687, 509, 1049, 809), []),
    "TabGameplay": ("P", (1200, 529, 1592, 795), []),
    "ReducedMotion": ("M", (77, 81, 408, 260), []),
    "HighContrast": ("M", (518, 45, 766, 301), []),
    "ShowFps": ("M", (914, 53, 1196, 296), []),
    "HideOthers": ("M", (1345, 45, 1674, 315), []),
    "Notifications": ("M", (59, 372, 368, 613), []),
    "Language": ("M", (486, 371, 741, 624), []),
    "TabMisc": ("M", (851, 372, 1149, 592), []),
}
SLICED = {
    "RowFrame": ("C", (58, 385, 1470, 493), 230, 40, 230),
    "ValuePill": ("A", (556, 630, 977, 803), None, 20, None),  # full width; ends = (w - 20) / 2
    "Rule": ("C", (65, 808, 840, 840), 70, 40, 70),
}
RECOLOUR = {"RefreshWhite": "Refresh"}  # the reference's Reset icon is white with a black outline: the gold cut with its fill mapped to white
SHEET_RECTS = {"TabGraphics": ("ScreenShake", (1428, 73, 1653, 282))}


def cut(name: str):
    """-> (RGBA export array, (ox, oy) = sheet coordinate of the export's top-left pixel)."""
    if name in RECOLOUR:
        px, origin = cut(RECOLOUR[name])
        px = px.copy()
        lum = 0.45 * px[..., 0] + 0.5 * px[..., 1] + 0.05 * px[..., 2]
        t = np.clip((lum - 40) / 130, 0, 1)
        px[..., :3] = (255 * (t * t * (3 - 2 * t)))[..., None].astype(np.uint8)
        return px, origin
    sh, (x0, y0, x1, y1), *extra = COMP.get(name) or SLICED[name]
    extra = extra[0] if name in COMP else []
    img = np.pad(np.array(Image.open(SRC / SHEETS[sh]).convert("RGBA")), ((sq.E, sq.E), (sq.E, sq.E), (0, 0)))
    cx0, cy0, cx1, cy1 = x0 - sq.E, y0 - sq.E, x1 + sq.E, y1 + sq.E
    arr = img[cy0 + sq.E : cy1 + sq.E, cx0 + sq.E : cx1 + sq.E].copy()
    loc = (x0 - cx0, y0 - cy0, x1 - cx0, y1 - cy0)
    a = arr[..., 3]
    keep = np.zeros(a.shape, bool)
    work = arr.copy()
    seeds = [loc] + [(a_ - cx0, b - cy0, c - cx0, d - cy0) for a_, b, c, d in extra]
    for sd in seeds:
        for _ in range(16):
            sub = work[sd[1] : sd[3], sd[0] : sd[2], 3]
            if (sub >= 160).sum() < (MINPX if sd is loc else 8):
                break
            m = sq.component_mask(work, [sd])
            keep |= m
            work[m, 3] = 0
    if name in SLICED:  # never take a neighbour's glow/tip that bridges in (Rule: the Diamond's left tip)
        keep[:, : loc[0] - 6] = keep[:, loc[2] + 6 :] = False
    a[~keep] = 0
    a[a < 8] = 0
    a[a >= 248] = 255
    ys, xs = np.where(a > 0)
    px = np.pad(arr[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1], ((sq.PAD, sq.PAD), (sq.PAD, sq.PAD), (0, 0)))
    px[0], px[-1], px[:, 0], px[:, -1] = 0, 0, 0, 0
    px = sb.bleed(sb.dematte(px))
    origin = (cx0 + int(xs.min()) - sq.PAD, cy0 + int(ys.min()) - sq.PAD)
    return px, origin


def compact(px: np.ndarray, left, mid, right):
    """Left end + centre strip + right end; -> (array, slice Rect as [l, t, r, b])."""
    h, w = px.shape[:2]
    if left is None:
        left = right = (w - mid) // 2
        mid = w - left - right
    out = np.concatenate([px[:, : left + mid], px[:, w - right :]], axis=1)  # centre strip continues the left end: no seam there
    return out, [left, h // 2 - 1, left + mid, h // 2 + 1]


def main() -> None:
    OUT.mkdir(exist_ok=True)
    mf = OUT / "manifest.json"
    old = json.loads(mf.read_text()) if mf.exists() else {}
    manifest = {}
    origins = {}
    for name in [*COMP, *SLICED, *RECOLOUR]:
        px, origins[name] = cut(name)
        slc = None
        if name in SLICED:
            _, _, left, mid, right = SLICED[name]
            px, slc = compact(px, left, mid, right)
        assert max(px.shape[:2]) <= 1024, f"{name} {px.shape}"
        buf = io.BytesIO()
        Image.fromarray(px).save(buf, format="PNG", optimize=True)
        png = OUT / f"Settings_{name}.png"
        if not png.exists() or png.read_bytes() != buf.getvalue():
            png.write_bytes(buf.getvalue())
        h, w = px.shape[:2]
        manifest[name] = {"w": w, "h": h, "ink": sb.ink_box(px), "asset": old.get(name, {}).get("asset", "")}
        if slc:
            manifest[name]["slice"] = slc
        print(name, w, h, manifest[name]["ink"], slc or "")
    for name, (base, (x0, y0, x1, y1)) in SHEET_RECTS.items():
        ox, oy = origins[base]
        r = [x0 - ox, y0 - oy, x1 - ox, y1 - oy]
        manifest[name] = {"base": base, "rect": r}
        print(name, "ImageRect of", base, r)
    mf.write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
