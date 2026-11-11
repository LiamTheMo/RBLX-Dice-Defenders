"""Cut the Bag menu sprites out of the source sheets into clean, upload-ready PNGs.

Usage: python tools/slice_bag.py
Reads Assets/UI/bag menu/<Folder>/<sheet>.png, writes Assets/UI/bag menu/export/Bag_<Name>.png
plus export/manifest.json (name, w, h, slice) -> copy into src/client/Controllers/Bag/BagSprites.luau.
Rects are alpha>=160 bounding boxes measured from the sheets (x, y, w, h). Needs Pillow + numpy.
Sprites in SLICED get a SliceCenter measured on the export, then moved inward until the art is flat across each line,
and their stretch regions are rebuilt as plain interpolations (Roblox's 9-slice does not sample its pieces continuously,
so any variation across a slice line renders as a hard step).
"""

import json
import math
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
    "Banner": ("Dice/frames-regenerated.png", (917, 536, 605, 208), 605, SHEET_MARGIN),  # laurels + ribbon + crowned die, one piece
    "Ribbon": ("Cosmetics/icons-regenerated.png", (26, 820, 690, 182), 690, SHEET_MARGIN),
    "BagDie": ("New/new menu dice.png", (166, 34, 840, 1169), 512, SHEET_MARGIN),
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
    "IconDice": ("Dice/icons-regenerated.png", (59, 100, 234, 259), 256, SHEET_MARGIN),
    "IconCrystals": ("Dice/icons-regenerated.png", (338, 100, 252, 242), 256, SHEET_MARGIN),
    "IconPotion": ("Dice/icons-regenerated.png", (628, 88, 200, 266), 256, SHEET_MARGIN),
    "IconCrown": ("Dice/icons-regenerated.png", (874, 104, 294, 224), 256, SHEET_MARGIN),
    "Lock": ("Dice/icons-regenerated.png", (1228, 96, 204, 242), 128, SHEET_MARGIN),
    "Coins": ("Dice/icons-regenerated.png", (40, 430, 210, 174), 128, SHEET_MARGIN),
    "Check": ("Dice/icons-regenerated.png", (280, 452, 174, 142), 128, SHEET_MARGIN),
    "Magnifier": ("Dice/icons-badges-and-effects.png", (622, 305, 95, 93), 128, SHEET_MARGIN),
    "SortArrows": ("Dice/icons-regenerated.png", (696, 442, 202, 150), 128, SHEET_MARGIN),  # up + down
    "CheckCircle": ("Materials/icons-regenerated.png", (1220, 290, 168, 170), 128, SHEET_MARGIN),
    "Flask": ("Items/icons-regenerated.png", (810, 420, 190, 214), 256, SHEET_MARGIN),
    "EquippedPill": ("Dice/icons-badges-and-effects.png", (36, 472, 204, 64), 204, 14),
}
# Sliced, height-fitted controls: export height (px, margin included) ~2x the largest full-tier draw height.
HEIGHTS = {
    "TabPurple": 120, "TabGold": 120, "BtnGreen": 112, "BtnRed": 112, "BtnGold": 112, "BtnPurple": 112, "Search": 112,
    "Sort": 112, "PillGold": 60, "PillPurple": 60, "PillBlue": 60, "PillGreen": 60, "PillGrey": 60, "PillPink": 60,
    "QtyMinus": 112, "QtyField": 112, "QtyPlus": 112, "LevelTrack": 52,
}
FEATHER = {"EquippedPill"}  # baked halo runs into the next element on the sheet: fade it to nothing over the margin
ERASE_GLYPH = {"QtyMinus": (11, 3), "QtyPlus": (7, 0)}  # the baked -/+ is drawn live; fill its area (pad, extra pad below) from the art around it
# Keep the baked chevron / check mark: the right-hand band is neither rebuilt nor checked. Value = (t_max, b_min) rows that bracket the
# glyph and its outline so no slice line crosses it (None where the pill's own corner arc forbids that: the line crosses the glyph).
KEEP_RIGHT = {"EquippedPill": None}
SHARED_SCALE = {"LevelFill": "LevelTrack"}  # same resize factor and margin as the track so the fill fits its interior
PILL_PINK_REF = ("materials-reference.png", (306, 310, 320, 322))  # MYTHIC pill body in the Materials reference screen
GLOW_SRC = SRC / "New" / "new glow.png"  # neutral grey ray burst; GlowCommon is it as-is, the rest are tinted
GLOW_BBOX = (122, 50, 1094, 1081)  # alpha>=8 extent (x, y, w, h)
GLOW_SIDE = 512
DEEP, LIGHT = 0.8, 0.3  # tinted glow: base = tint * DEEP, rays = tint lerped toward white by LIGHT
# rarity: tint hex, taken from the matching Bag_Pill* sprite (Legendary warmer orange-gold, Secret crimson)
GLOWS = {
    "GlowCommon": None, "GlowUncommon": "42BC02", "GlowRare": "0185FA", "GlowEpic": "8D15F1",
    "GlowLegendary": "FF9A1F", "GlowMythic": "FF4FCB", "GlowSecret": "DC143C",
}
# 9-slice sprites. Value = minimum (l, t, r, b) in export px that the slice must keep clear (e.g. a baked check mark).
# Sort is not here: its baked chevron can't sit on a slice line, so Parts draws it whole (Stretch) at its art aspect.
SLICED = {
    "Window": None, "LeftPanel": None, "Detail": None, "Strip": None, "TabPurple": None, "TabGold": None,
    "BtnGreen": None, "BtnRed": None, "BtnGold": None, "BtnPurple": None, "Search": None,
    "CardIdle": None, "CardSelected": None, "LevelTrack": None, "LevelFill": None,
    "PillGold": None, "PillPurple": None, "PillBlue": None, "PillGreen": None, "PillGrey": None, "PillPink": None,
    "QtyMinus": None, "QtyField": None, "QtyPlus": None, "EquippedPill": (0, 0, 76, 0),
}


def tint_glow(rgba: np.ndarray, hexcol: str | None) -> np.ndarray:
    """Clean alpha, fade the rim, recolour: a deep base to a light version of the same hue by grey level."""
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
        lum = rgba[..., :3].astype(np.float32).mean(-1)
        lo, hi = np.percentile(lum[rgba[..., 3] > 0], (2, 99.5))
        t = np.clip((lum - lo) / (hi - lo), 0, 1)[..., None]
        deep, light = tint * DEEP, tint + (1 - tint) * LIGHT  # same hue throughout, never pure white
        rgba[..., :3] = np.clip((deep + (light - deep) * t) * 255, 0, 255).astype(np.uint8)
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


def fit(w: int, h: int, base: int, side: int | None = None, height: int | None = None, inc_margin: bool = False):
    """Resize factor k and source margin m. m = max(base, ceil(3/k) + 2): the Lanczos kernel (3/k source px) must never reach the crop edge.
    side = longest output side (of the bbox, or of the margin-padded crop with inc_margin); height = output height incl. margin."""
    m = base
    for _ in range(20):
        cw, ch = w + 2 * m, h + 2 * m
        k = height / ch if height else side / (max(cw, ch) if inc_margin else max(w, h))
        k = min(1.0, k, 1024 / max(cw, ch))  # never upscale, never past 1024
        m2 = max(m, math.ceil(3 / k) + 2)
        if m2 == m:
            return k, m
        m = m2
    raise RuntimeError("margin did not converge")


def own_art(a: np.ndarray, core: tuple, base: int) -> int:
    """Blank art outside the old margin box that is not connected (alpha >= 8) to the sprite's own bbox: a neighbour's body.
    Works on a 4x coarse grid. Returns how many opaque (alpha >= 160) pixels were removed."""
    h, w = a.shape
    x0, y0, x1, y1 = core
    f = 4
    H, W = -(-h // f), -(-w // f)
    solid = np.zeros((H * f, W * f), bool)
    solid[:h, :w] = a >= 8
    solid = solid.reshape(H, f, W, f).any((1, 3))
    cur = np.zeros_like(solid)
    cur[max(y0, 0) // f : -(-y1 // f), max(x0, 0) // f : -(-x1 // f)] = True
    cur &= solid
    while True:
        p = np.pad(cur, 1)
        nxt = (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:] | p[:-2, :-2] | p[:-2, 2:] | p[2:, :-2] | p[2:, 2:] | cur) & solid
        if (nxt == cur).all():
            break
        cur = nxt
    keep = np.repeat(np.repeat(cur, f, 0), f, 1)[:h, :w]
    ring = np.ones((h, w), bool)
    ring[max(y0 - base, 0) : y1 + base, max(x0 - base, 0) : x1 + base] = False
    gone = ring & ~keep & (a > 0)
    opaque = int((gone & (a >= 160)).sum())
    a[gone] = 0
    return opaque


def dematte(px: np.ndarray) -> np.ndarray:
    """Pixels with 0 < alpha < 160 within 3 px of an alpha >= 200 pixel take that nearest pixel's colour (alpha kept): no baked-in dark matte."""
    h, w, _ = px.shape
    a = np.pad(px[..., 3], 3)
    rgb = np.pad(px[..., :3], ((3, 3), (3, 3), (0, 0)))
    todo = (px[..., 3] > 0) & (px[..., 3] < 160)
    src = a >= 200
    out = px[..., :3].copy()
    offs = sorted(((dy, dx) for dy in range(-3, 4) for dx in range(-3, 4) if dy or dx), key=lambda o: o[0] ** 2 + o[1] ** 2)
    for dy, dx in offs:
        ok = todo & src[3 + dy : 3 + dy + h, 3 + dx : 3 + dx + w]
        out[ok] = rgb[3 + dy : 3 + dy + h, 3 + dx : 3 + dx + w][ok]
        todo &= ~ok
    px[..., :3] = out
    return px


def _hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = np.where(mx == mn, 1, mx - mn)
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6
    return np.where(mx == mn, 0, h), np.where(mx == 0, 0, (mx - mn) / np.where(mx == 0, 1, mx)), mx


def _rgb(h, s, v):
    f = lambda n: v - v * s * np.clip(np.minimum((n + h * 6) % 6, 4 - (n + h * 6) % 6), 0, 1)
    return np.stack([f(5), f(3), f(1)], -1)


def recolor_pink(arr: np.ndarray, ref_rgb: np.ndarray) -> np.ndarray:
    """Hue/saturation/value-shift the pill so its body median matches the MYTHIC pill body in the reference screen."""
    h, w, _ = arr.shape
    body = np.median(arr[h // 2 - 6 : h // 2 + 6, w // 2 - 40 : w // 2 + 40, :3].reshape(-1, 3) / 255.0, 0)[None]
    (h0, s0, v0), (h1, s1, v1) = ([float(c[0]) for c in _hsv(m)] for m in (body, ref_rgb[None] / 255.0))
    hh, ss, vv = _hsv(arr[..., :3] / 255.0)
    out = _rgb((hh + h1 - h0) % 1, np.clip(ss * s1 / s0, 0, 1), np.clip(vv * v1 / v0, 0, 1))
    arr[..., :3] = np.round(out * 255).astype(np.uint8)
    return arr


def cut(img: Image.Image, rect, base: int, k: float, m: int, recolor=None, feather: bool = False):
    """Crop rect + margin m (clamped to the sheet), keep only the sprite's own art, resize by k, clean alpha, de-matte, bleed.
    Returns (px, opaque neighbour pixels removed). Asserts the export's 1 px outer ring is transparent (a real clip fails loudly)."""
    x, y, w, h = rect
    cx0, cy0, cx1, cy1 = max(x - m, 0), max(y - m, 0), min(x + w + m, img.width), min(y + h + m, img.height)
    arr = np.array(img.crop((cx0, cy0, cx1, cy1)))
    masked = own_art(arr[..., 3], (x - cx0, y - cy0, x + w - cx0, y + h - cy0), base)
    if recolor is not None:
        arr = recolor(arr)
    a = arr[..., 3]
    if feather:  # smoothstep alpha fade from the bbox out to the crop edge
        yy, xx = np.mgrid[0 : arr.shape[0], 0 : arr.shape[1]]
        dx = np.maximum(np.maximum(x - cx0 - xx, xx - (x + w - cx0 - 1)), 0)
        dy = np.maximum(np.maximum(y - cy0 - yy, yy - (y + h - cy0 - 1)), 0)
        t = np.clip(1 - np.hypot(dx, dy) / (m - 1), 0, 1)
        a[:] = np.round(a * t * t * (3 - 2 * t)).astype(np.uint8)
    a[a < 8] = 0
    a[a >= 248] = 255
    size = (round(arr.shape[1] * k), round(arr.shape[0] * k))
    px = np.array(Image.fromarray(arr).resize(size, Image.LANCZOS)) if k < 1 else arr  # Pillow premultiplies RGBA on resize
    px[..., 3][px[..., 3] < 8] = 0
    ring = np.concatenate([px[0, :, 3], px[-1, :, 3], px[:, 0, 3], px[:, -1, 3]])
    assert ring.max() < 24, f"sprite is clipped by its crop: outer ring alpha {ring.max()}"
    px[0], px[-1], px[:, 0], px[:, -1] = 0, 0, 0, 0
    return bleed(dematte(px)), masked


def _prem(px: np.ndarray) -> np.ndarray:
    return px[..., :3].astype(np.float32) * (px[..., 3:] / 255.0)


def _side(P: np.ndarray, side: int) -> np.ndarray:
    """View P so that side (0 left, 1 top, 2 right, 3 bottom) becomes the left edge."""
    return [P, P.transpose(1, 0, 2), P[:, ::-1], P.transpose(1, 0, 2)[:, ::-1]][side]


def _flat(Pv: np.ndarray, d: int) -> float:
    """Worst alpha-weighted RGB step between column d and the 8 columns after it, over every row."""
    return float(np.abs(Pv[:, d + 1 : d + 9] - Pv[:, d : d + 1]).max())


def _step(Pv: np.ndarray, d: int) -> float:
    """Worst adjacent-column delta within +-3 px of the line at d."""
    lo, hi = max(d - 4, 0), min(d + 3, Pv.shape[1] - 1)
    return float(np.abs(np.diff(Pv[:, lo : hi + 1], axis=1)).max())


def _bilinear(P: np.ndarray, O: np.ndarray, l: int, t: int, r: int, b: int) -> None:
    """O[t:b, l:r] = bilinear blend of P's four centre-corner pixels. Matches the lerped bands at every line; blending the raw
    border lines instead (Coons) carries the sheet's grain across the panel as visible streaks."""
    u = ((np.arange(l, r) - l) / (r - 1 - l))[None, :, None]
    v = ((np.arange(t, b) - t) / (b - 1 - t))[:, None, None]
    O[t:b, l:r] = (1 - u) * (1 - v) * P[t, l] + u * (1 - v) * P[t, r - 1] + (1 - u) * v * P[b - 1, l] + u * v * P[b - 1, r - 1]


def _to_px(O: np.ndarray) -> np.ndarray:
    a = np.clip(O[..., 3], 0, 255)
    a[a < 8] = 0
    rgb = np.clip(O[..., :3] / np.maximum(a[..., None], 1) * 255, 0, 255)
    return bleed(np.dstack([np.round(rgb), np.round(a)]).astype(np.uint8))


def _pa(px: np.ndarray) -> np.ndarray:
    return np.concatenate([_prem(px), px[..., 3:].astype(np.float32)], -1)


def erase_glyph(px: np.ndarray, pad: int, below: int) -> np.ndarray:
    """Fill the baked white glyph (and its dark outline) with a bilinear blend of the art around it."""
    h, w, _ = px.shape
    white = (px[..., :3].min(-1) >= 150) & (np.ptp(px[..., :3].astype(int), -1) <= 60) & (px[..., 3] == 255)
    white[:, : w // 4] = white[:, 3 * w // 4 :] = False
    white[: h // 4] = white[3 * h // 4 :] = False
    ys, xs = np.where(white)
    P = _pa(px)
    O = P.copy()
    _bilinear(P, O, xs.min() - pad, ys.min() - pad, xs.max() + pad + 1, ys.max() + pad + 1 + below)
    return _to_px(O)


def rebuild(px: np.ndarray, l: int, t: int, r: int, b: int, keep_right: bool = False) -> np.ndarray:
    """Stretch regions become plain interpolations of their border lines (premultiplied): top/bottom bands lerp along x between
    columns l and r-1, left/right bands along y between rows t and b-1, the centre is a bilinear blend of its four corner pixels."""
    h, w, _ = px.shape
    P = _pa(px)
    O = P.copy()
    u = ((np.arange(l, r) - l) / (r - 1 - l))[None, :, None]
    v = ((np.arange(t, b) - t) / (b - 1 - t))[:, None, None]
    for y0, y1 in ((0, t), (b, h)):
        O[y0:y1, l:r] = P[y0:y1, l : l + 1] * (1 - u) + P[y0:y1, r - 1 : r] * u
    for x0, x1 in ((0, l),) + (() if keep_right else ((r, w),)):
        O[t:b, x0:x1] = P[t : t + 1, x0:x1] * (1 - v) + P[b - 1 : b, x0:x1] * v
    _bilinear(P, O, l, t, r, b)
    return _to_px(O)


def seamproof(px: np.ndarray, lines: list[int], keep_right: bool = False, bracket: tuple | None = None):
    """Move each SliceCenter line inward until the art is flat across it (step <= 6 over 8 px, cap 45%), rebuild the stretch
    regions, then check adjacent-pixel deltas within 3 px of every line are <= 8 (moving a failing line further in).
    Returns (px, [l, t, r, b], notes); notes lists any line that still fails at the cap."""
    h, w, _ = px.shape
    d = [lines[0], lines[1], w - lines[2], h - lines[3]]
    cap = [int(0.45 * w), int(0.45 * h), int(0.45 * w), int(0.45 * h)]
    if bracket:
        cap[1], cap[3] = min(cap[1], bracket[0]), min(cap[3], h - bracket[1])
        d[1], d[3] = min(d[1], cap[1]), min(d[3], cap[3])
    P = _prem(px)

    def view(A, s):  # keep_right: the chevron columns (x >= r) are exempt from the top/bottom line checks
        Av = _side(A, s)
        return Av[: w - d[2]] if keep_right and s in (1, 3) else Av

    for s in range(4):
        Pv = view(P, s)
        d[s] = min(range(d[s], max(cap[s], d[s]) + 1), key=lambda c: (_flat(Pv, c) > 6, c if _flat(Pv, c) <= 6 else _flat(Pv, c)))
    for _ in range(600):
        out = rebuild(px, d[0], d[1], w - d[2], h - d[3], keep_right)
        Q = _prem(out)
        bad = [s for s in range(4) if _step(view(Q, s), d[s]) > 8]
        moved = [s for s in bad if d[s] < cap[s]]
        if not moved:
            notes = [f"side{s} step {_step(view(Q, s), d[s]):.1f}" for s in bad]
            return out, [d[0], d[1], w - d[2], h - d[3]], notes
        for s in moved:
            d[s] += 1
    raise RuntimeError("seamproof did not converge")


def main() -> None:
    OUT.mkdir(exist_ok=True)
    sheets: dict[str, Image.Image] = {}
    manifest = {}
    ref = np.array(Image.open(SRC / PILL_PINK_REF[0]).convert("RGB"))
    x0, y0, x1, y1 = PILL_PINK_REF[1]
    pink_ref = np.median(ref[y0:y1, x0:x1].reshape(-1, 3), 0)
    shared: dict[str, tuple[float, int]] = {}
    for name, (sheet, rect, side, margin) in SPRITES.items():
        img = sheets.setdefault(sheet, Image.open(SRC / sheet).convert("RGBA"))
        k, m = shared[SHARED_SCALE[name]] if name in SHARED_SCALE else fit(rect[2], rect[3], margin, side=side, height=HEIGHTS.get(name))
        shared[name] = (k, m)
        recolor = (lambda a: recolor_pink(a, pink_ref)) if name == "PillPink" else None
        px, masked = cut(img, rect, margin, k, m, recolor, name in FEATHER)
        assert px.shape[0] <= 1024 and px.shape[1] <= 1024, name
        info = {"w": px.shape[1], "h": px.shape[0]}
        note = f"k={k:.3f} m={m}" + (f" MASKED {masked} opaque neighbour px" if masked else "")
        if name in ERASE_GLYPH:
            px = erase_glyph(px, *ERASE_GLYPH[name])
        if name in SLICED:
            px, line, notes = seamproof(px, measure(px, SLICED[name] or (0, 0, 0, 0)), name in KEEP_RIGHT, KEEP_RIGHT.get(name))
            info["slice"] = line
            note += f" {line}" + "".join(f" WARN {n}" for n in notes)
        Image.fromarray(px).save(OUT / f"Bag_{name}.png", optimize=True)
        manifest[name] = info
        print(f"{name}: {px.shape[1]}x{px.shape[0]} {note}")
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
