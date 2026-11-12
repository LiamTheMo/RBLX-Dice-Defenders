"""Cut the Bag menu sprites out of the source sheets into clean, upload-ready PNGs.

Usage: python tools/slice_bag.py
Reads Assets/UI/bag menu/<Folder>/<sheet>.png, writes Assets/UI/bag menu/export/Bag_<Name>.png
plus export/manifest.json (name, w, h, slice) -> copy into src/client/Controllers/Bag/BagSprites.luau.
Rects are alpha>=160 bounding boxes measured from the sheets (x, y, w, h). Needs Pillow + numpy.
Usage: python tools/slice_bag.py [Name ...] cuts only the named sprites (and merges into manifest.json). Every entry gets "ink" = [l, t, r, b], the alpha>=160 box.
Sprites in SLICED get a SliceCenter measured on the export, then moved inward until the art is flat across each line,
and their stretch regions are rebuilt as plain interpolations (Roblox's 9-slice does not sample its pieces continuously,
so any variation across a slice line renders as a hard step).
"""

import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

SRC = Path(__file__).resolve().parent.parent / "Assets" / "UI" / "bag menu"
OUT = SRC / "export"
SHEET_MARGIN = 4  # source px kept around each bbox for the soft edge
GLOW_MARGIN = 20  # bursts fade far past their alpha>=160 bbox

# rarity -> (rim hex, fill hex). Rims are the Bag_Glow tints (= the matching pill body); fills are the Materials/Dice reference card fills
# (Secret has no reference card: crimson).
CARD_FILL = {
    "Common": ("B4B4B4", "4A4B4A"), "Uncommon": ("42BC02", "1F4C01"), "Rare": ("0185FA", "0A457A"), "Epic": ("8D15F1", "4F1276"),
    "Legendary": ("FF9A1F", "7A3A00"), "Mythic": ("FF4FCB", "60148D"), "Secret": ("DC143C", "5A0F1E"),
}

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
    "Close": ("Dice/controls-regenerated.png", (1054, 619, 184, 173), 144, SHEET_MARGIN),
    "LevelTrack": ("Dice/controls-regenerated.png", (127, 904, 687, 87), 687, SHEET_MARGIN),
    "LevelFill": ("Dice/controls-regenerated.png", (864, 922, 519, 51), 519, SHEET_MARGIN),  # native, like the track
    # Title
    "Ribbon": ("Cosmetics/icons-regenerated.png", (26, 820, 690, 182), 690, SHEET_MARGIN),
    # Pills (Materials controls 15-20)
    "PillGold": ("Materials/controls-regenerated.png", (52, 781, 254, 81), 254, SHEET_MARGIN),
    "PillPurple": ("Materials/controls-regenerated.png", (341, 781, 245, 81), 245, SHEET_MARGIN),
    "PillBlue": ("Materials/controls-regenerated.png", (621, 781, 250, 81), 250, SHEET_MARGIN),
    "PillGreen": ("Materials/controls-regenerated.png", (904, 781, 252, 81), 252, SHEET_MARGIN),
    "PillGrey": ("Materials/controls-regenerated.png", (1189, 781, 250, 81), 250, SHEET_MARGIN),
    "PillPink": ("Materials/controls-regenerated.png", (1473, 781, 250, 81), 250, SHEET_MARGIN),
    # Stepper (Materials controls 6/7/8)
    "QtyField": ("Materials/controls-regenerated.png", (657, 372, 460, 118), 460, SHEET_MARGIN),
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
    # Loop 1: rarity cards = CardIdle recoloured (RECOLOR); CardCopper = the Cosmetics sheet's copper-rimmed card at CardIdle's scale
    **{f"Card{r}": ("Dice/controls-regenerated.png", (270, 544, 317, 318), 256, SHEET_MARGIN) for r in CARD_FILL},
    "CardCopperMaroon": ("Cosmetics/controls-regenerated.png", (73, 44, 339, 331), 274, SHEET_MARGIN),  # items tab: maroon fill
    "ScrollTrack": ("Materials/controls-regenerated.png", (1576, 25, 54, 447), 270, SHEET_MARGIN),  # ~2 texels per design px at 16 px wide
    "ScrollThumb": ("Materials/controls-regenerated.png", (1676, 70, 55, 274), 270, SHEET_MARGIN),
    "NameRibbon": ("Materials/icons-badges-and-effects.png", (46, 747, 537, 115), 537, SHEET_MARGIN),
    "DividerGold": ("Cosmetics/controls-regenerated.png", (68, 920, 891, 57), 700, SHEET_MARGIN),
    "StatRow": ("Cosmetics/controls-regenerated.png", (843, 807, 357, 48), 357, SHEET_MARGIN),  # native: the reference row is 33 px tall
    "IconSword": ("Dice/icons-badges-and-effects.png", (999, 300, 103, 104), 128, 12),
    "IconTarget": ("Dice/icons-badges-and-effects.png", (1130, 293, 117, 119), 128, 12),
    "IconHourglass": ("Dice/icons-badges-and-effects.png", (1277, 296, 84, 110), 128, 12),
    "IconFlame": ("Dice/icons-badges-and-effects.png", (1401, 291, 102, 113), 128, 12),
    # Loop 2: items name ribbon, selected copper cards (glow incl.), badge, stats side lines (L: diamond at its right end; R = mirror),
    # cosmetics flags, wide pill, portal ring. Rects are alpha>=160 boxes (the ring's soft halo is feathered out over the margin).
    "ItemsNameRibbon": ("Items/icons-effects-regenerated-v2.png", (371, 536, 761, 146), 720, SHEET_MARGIN),
    "CardCopperSelectedMaroon": ("Cosmetics/controls-regenerated.png", (436, 42, 353, 353), 285, 14),
    "StatsLineL": ("Dice/icons-badges-and-effects.png", (1172, 831, 267, 27), 190, SHEET_MARGIN),
    "StatsLineR": ("Dice/icons-badges-and-effects.png", (1172, 831, 267, 27), 190, SHEET_MARGIN),
    "CosFlagLeft": ("Cosmetics/icons-badges-and-effects.png", (41, 439, 184, 297), 250, SHEET_MARGIN),
    "CosFlagRight": ("Cosmetics/icons-badges-and-effects.png", (259, 439, 183, 297), 250, SHEET_MARGIN),
    "PillWide": ("Cosmetics/controls-regenerated.png", (1020, 900, 453, 92), 453, SHEET_MARGIN),
    "GlowRing": ("Cosmetics/icons-badges-and-effects.png", (473, 788, 568, 212), 560, 24),
    # Loop 3: white EQUIPPED check lifted off the Dice sheet's baked pill (glyph + its dark outline only), stepper -/+ buttons with their own
    # baked glyphs (Items sheet), a white USE flask (recoloured from the Items sheet's green one).
    "CheckWhite": ("Dice/icons-badges-and-effects.png", (178, 488, 41, 35), 41, 6),
    "StepMinus": ("Items/icons-badges-and-effects.png", (975, 392, 84, 83), 84, SHEET_MARGIN),
    "StepPlus": ("Items/icons-badges-and-effects.png", (867, 392, 85, 83), 85, SHEET_MARGIN),
    "IconFlaskWhite": ("Items/icons-badges-and-effects.png", (39, 372, 94, 118), 118, SHEET_MARGIN),
}
# Sliced, height-fitted controls: export height (px, margin included) ~2x the largest full-tier draw height.
HEIGHTS = {
    "TabPurple": 120, "TabGold": 120, "BtnGreen": 112, "BtnRed": 112, "BtnGold": 112, "BtnPurple": 112, "Search": 112,
    "Sort": 112, "PillGold": 60, "PillPurple": 60, "PillBlue": 60, "PillGreen": 60, "PillGrey": 60, "PillPink": 60,
    "QtyField": 112, "LevelTrack": 52, "PillWide": 76,
}
VERTICAL = {"ScrollTrack", "ScrollThumb"}  # sliced top/bottom only: Slice = Rect(0, t, w, h - b); draw with SliceScale = draw width / Size.X
FEATHER = {"EquippedPill", "GlowRing", "CardCopperSelectedMaroon"}  # baked halo runs into the next element on the sheet: fade it to nothing over the margin
ERASE_GLYPH = {}  # the baked -/+ is drawn live; fill its area (pad, extra pad below) from the art around it
# Keep the baked chevron / check mark: the right-hand band is neither rebuilt nor checked. Value = (t_max, b_min) rows that bracket the
# glyph and its outline so no slice line crosses it (None where the pill's own corner arc forbids that: the line crosses the glyph).
KEEP_RIGHT = {"EquippedPill": None}
SHARED_SCALE = {"LevelFill": "LevelTrack", "ScrollThumb": "ScrollTrack"}  # same resize factor and margin as the track so the fill fits its interior
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
    "Window": (292, 154, 224, 124), "LeftPanel": None, "Detail": None, "Strip": None, "TabPurple": (79, 44, 63, 49), "TabGold": None,
    "BtnGreen": None, "BtnRed": None, "BtnGold": None, "BtnPurple": None, "Search": None,
    "LevelTrack": None, "LevelFill": None,
    "PillGold": None, "PillPurple": None, "PillBlue": None, "PillGreen": None, "PillGrey": None, "PillPink": None,
    "QtyField": None, "EquippedPill": (0, 0, 76, 0),
    **{f"Card{r}": None for r in CARD_FILL}, "CardCopperMaroon": None, "StatRow": None,
    "CardCopperSelectedMaroon": None, "PillWide": None,
    "ScrollTrack": None, "ScrollThumb": None,
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


def recolor_pink(arr: np.ndarray, ref_rgb: np.ndarray, band: tuple[float, float] | None = None) -> np.ndarray:
    """Hue/saturation/value-shift the sprite so its body median matches the reference body colour (the MYTHIC pill; the idle tab).
    The body is the middle rows by default, or the rows between band (fractions of the height)."""
    h, w, _ = arr.shape
    r0, r1 = (int(band[0] * h), int(band[1] * h)) if band else (h // 2 - 6, h // 2 + 6)
    body = np.median(arr[r0:r1, w // 2 - 40 : w // 2 + 40, :3].reshape(-1, 3) / 255.0, 0)[None]
    (h0, s0, v0), (h1, s1, v1) = ([float(c[0]) for c in _hsv(m)] for m in (body, ref_rgb[None] / 255.0))
    hh, ss, vv = _hsv(arr[..., :3] / 255.0)
    out = _rgb((hh + h1 - h0) % 1, np.clip(ss * s1 / s0, 0, 1), np.clip(vv * v1 / v0, 0, 1))
    arr[..., :3] = np.round(out * 255).astype(np.uint8)
    return arr


def _hexrgb(h: str) -> np.ndarray:
    return np.array([int(h[i : i + 2], 16) for i in (0, 2, 4)], np.float32)


def _edge_dist(alive: np.ndarray, n: int) -> np.ndarray:
    """How many of n alternating cross / square erosions each pixel of `alive` survives (~ distance to the silhouette edge, capped at n)."""
    dist = np.zeros(alive.shape, np.float32)
    cur = alive.copy()
    for i in range(n):
        dist += cur
        p = np.pad(cur, 1)
        nxt = p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
        if i % 2:
            nxt = nxt & p[:-2, :-2] & p[:-2, 2:] & p[2:, :-2] & p[2:, 2:]
        cur = nxt
    return dist


def recolor_window(arr: np.ndarray) -> np.ndarray:
    """Dice reference rim is orange (#FB9124 / highlight #FBB14B) where the sheet's is gold (#FDBC34): rotate the bright rim hue about
    8 degrees toward red."""
    rgb = arr[..., :3].astype(np.float32) / 255
    h, s_, v = _hsv(rgb)
    deg = h * 360
    wt = np.clip((deg - 26) / 10, 0, 1) * np.clip((v - 0.85) / 0.1, 0, 1) * np.clip((s_ - 0.4) / 0.2, 0, 1)
    arr[..., :3] = np.round(np.clip(_rgb((deg - 8 * wt) / 360 % 1, s_, v), 0, 1) * 255).astype(np.uint8)
    return arr


def trim_outline(px: np.ndarray) -> np.ndarray:
    """Soften the 1-2 px near-black outer outline of the finished export (the reference window has only a soft shadow): alpha x 0.4.
    Done after the slice is built so it is identical along every stretched band and cannot move a slice line."""
    dark = (px[..., :3].mean(-1) < 100) & (_edge_dist(px[..., 3] >= 160, 3) <= 2) & (px[..., 3] > 0)
    px[..., 3][dark] = np.round(px[..., 3][dark] * 0.4).astype(np.uint8)
    return px


def recolor_close(arr: np.ndarray) -> np.ndarray:
    """Close X red face #F31C17 -> reference #F72827: add (4, 12, 16) to pure-red pixels only (white X and the outlines are untouched)."""
    rgb = arr[..., :3].astype(np.float32)
    wt = np.clip((rgb[..., 0] - 150) / 60, 0, 1) * np.clip((120 - rgb[..., 1]) / 40, 0, 1) * np.clip((120 - rgb[..., 2]) / 40, 0, 1)
    arr[..., :3] = np.clip(rgb + wt[..., None] * np.array([4, 12, 16], np.float32), 0, 255).astype(np.uint8)
    return arr


def recolor_tone(arr: np.ndarray, pairs: list[tuple[str, str, float]]) -> np.ndarray:
    """Shift colours near each src hex by (dst - src), full strength within tol / 2, fading out by `tol` RGB distance, so the art's own shading survives.
    Overlapping pairs blend their shifts (weights normalised, total strength capped at 1). Alpha is untouched."""
    rgb = arr[..., :3].astype(np.float32)
    num = np.zeros_like(rgb)
    tot = np.zeros(rgb.shape[:2], np.float32)
    for src, dst, tol in pairs:
        w = np.clip(2 - 2 * np.linalg.norm(rgb - _hexrgb(src), axis=-1) / tol, 0, 1)  # full shift inside tol / 2
        w = w * w * (3 - 2 * w)
        num += w[..., None] * (_hexrgb(dst) - _hexrgb(src))
        tot += w
    arr[..., :3] = np.clip(rgb + num / np.maximum(tot, 1)[..., None], 0, 255).astype(np.uint8)
    return arr


def strip_left_diamond(px: np.ndarray, margin: int) -> np.ndarray:
    """StatsLine: drop the left diamond (columns where > 12 rows are opaque) and crop to the line plus margin; the right diamond stays."""
    cols = (px[..., 3] >= 160).sum(0)
    wide = np.where(cols > 12)[0]
    x = int(wide[wide < px.shape[1] // 3].max()) + 1
    px = px[:, x - margin :].copy()
    px[:, :margin, 3] = 0
    return px


def recolor_card(arr: np.ndarray, rim: str | None, fill: str | None, d: int, white: float = 0.5) -> np.ndarray:
    """Recolour a frame by region: the rim (every pixel within d px of the silhouette edge, outlines included) takes the rim colour
    scaled by its grey level (highlights go toward white by `white`), the interior takes the fill colour scaled the same way, so the
    art's own shading and gradient survive. None keeps that region as drawn."""
    rgb = arr[..., :3].astype(np.float32)
    lum = rgb.mean(-1)
    alive = arr[..., 3] >= 160
    dist = _edge_dist(alive, d + 2)
    w = np.clip((d + 1 - dist) / 2, 0, 1)[..., None]  # 1 on the rim, soft hand-over to the fill
    if rim:
        ring = (w[..., 0] > 0.9) & alive
        t = (lum / np.percentile(lum[ring], 80))[..., None]
        base = _hexrgb(rim) * np.minimum(t, 1)
        rim_px = base + (255 - base) * np.clip(t - 1, 0, 1) * white
    else:
        rim_px = rgb
    if fill:
        inner = (w[..., 0] < 0.1) & alive
        t = np.clip(lum / np.median(lum[inner]), 0, 2.5)[..., None]
        fill_px = _hexrgb(fill) * t
    else:
        fill_px = rgb
    arr[..., :3] = np.clip(rim_px * w + fill_px * (1 - w), 0, 255).astype(np.uint8)
    return arr


def isolate_check(arr: np.ndarray) -> np.ndarray:
    """Keep only the white check mark baked into a green pill (flood from its brightest pixel through white pixels), grown 2 px so its dark
    outline comes along. Everything else (the pill) goes transparent."""
    c = arr[..., :3].astype(int)
    white = (c.min(-1) >= 170) & (np.ptp(c, -1) <= 50)
    h, w = white.shape
    cur = np.zeros_like(white)
    sy, sx = np.unravel_index(np.argmax(np.where(white, c.sum(-1), 0)), white.shape)
    cur[sy, sx] = True
    while True:
        p = np.pad(cur, 1)
        nxt = (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:] | p[:-2, :-2] | p[:-2, 2:] | p[2:, :-2] | p[2:, 2:] | cur) & white
        if (nxt == cur).all():
            break
        cur = nxt
    keep = cur
    for _ in range(2):
        p = np.pad(keep, 1)
        keep = p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:] | p[:-2, :-2] | p[:-2, 2:] | p[2:, :-2] | p[2:, 2:] | keep
    p = np.pad(cur, 1)  # one px bolder: the tick's strokes are thin for a 12 px mark; the dark outline (2 px) keeps 1 px
    bold = (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:] | p[:-2, :-2] | p[:-2, 2:] | p[2:, :-2] | p[2:, 2:] | cur) & keep
    arr[bold, :3] = 255
    arr[..., 3] = np.where(keep, 255, 0).astype(np.uint8)
    return arr


def recolor_flask_white(arr: np.ndarray) -> np.ndarray:
    """Green flask -> white (the reference USE glyph): every bright, saturated pixel goes toward white by its saturation; the dark outline stays."""
    rgb = arr[..., :3].astype(np.float32) / 255
    _, s, v = _hsv(rgb)
    wt = np.clip(s * 1.1, 0, 1) * np.clip((v - 0.3) / 0.3, 0, 1)
    arr[..., :3] = np.round((rgb + (1 - rgb) * (wt[..., None] * 0.92)) * 255).astype(np.uint8)
    return arr


# name -> recolour applied to the source crop (before resize). TabPurple: idle tab body = reference tab body (Dice reference, x 1075-1095, y 147-195)
TAB_REF = ("dice-reference.png", (1075, 147, 20, 48))
RECOLOR = {f"Card{r}": (lambda a, c=c: recolor_card(a, c[0], c[1], 17)) for r, c in CARD_FILL.items()}
RECOLOR["CardCopperMaroon"] = lambda a: recolor_card(a, None, "421717", 18)
RECOLOR["CardCopperSelectedMaroon"] = lambda a: recolor_card(a, None, "421717", 24)
RECOLOR["Window"] = lambda a: recolor_tone(
    recolor_window(a),  # loop 2: rim top #FE8805 -> #FDA828, bottom #E16002 -> #FC8C23; fill #361422 / #411415 -> ref red-brown #3E130E / #44150D
    [("FE8805", "FDA828", 32), ("E16002", "FC8C23", 32), ("361422", "3E130E", 28), ("411415", "44150D", 20)],
)
RECOLOR["Close"] = lambda a: recolor_tone(recolor_close(a), [("F8B695", "FDE9C3", 30)])  # outer highlight -> ref cream
RECOLOR["LeftPanel"] = lambda a: recolor_tone(a, [("FFB465", "FAFAEC", 30)])  # rim highlight -> ref cream
RECOLOR["Detail"] = lambda a: recolor_tone(a, [("E76E28", "F2855D", 28)])
RECOLOR["Strip"] = lambda a: recolor_tone(a, [("CE1FA1", "A82B8B", 30)])
RECOLOR["DividerGold"] = lambda a: recolor_tone(a, [("F2A903", "F5C21C", 80)])  # warm body median #F2A903 -> ref #F5C21C; the pale core (B > 90) is out of range
RECOLOR["CheckWhite"] = isolate_check
TRIM = {"CheckWhite": 1}  # name -> transparent px kept around the alpha bbox
RECOLOR["IconFlaskWhite"] = recolor_flask_white
RECOLOR["StatRow"] = lambda a: recolor_card(a, "663064", "320E2B", 12, 0)  # reference row: #320E2B fill, subtle #5A2A58 rim


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


def rebuild(px: np.ndarray, l: int, t: int, r: int, b: int, keep_right: bool = False, vertical: bool = False) -> np.ndarray:
    """Stretch regions become plain interpolations of their border lines (premultiplied): top/bottom bands lerp along x between
    columns l and r-1, left/right bands along y between rows t and b-1, the centre is a bilinear blend of its four corner pixels."""
    h, w, _ = px.shape
    P = _pa(px)
    O = P.copy()
    v = ((np.arange(t, b) - t) / (b - 1 - t))[:, None, None]
    if vertical:  # full-width bands: every column is a lerp between its rows t and b-1 (the caps are left untouched)
        O[t:b] = P[t : t + 1] * (1 - v) + P[b - 1 : b] * v
        return _to_px(O)
    u = ((np.arange(l, r) - l) / (r - 1 - l))[None, :, None]
    for y0, y1 in ((0, t), (b, h)):
        O[y0:y1, l:r] = P[y0:y1, l : l + 1] * (1 - u) + P[y0:y1, r - 1 : r] * u
    for x0, x1 in ((0, l),) + (() if keep_right else ((r, w),)):
        O[t:b, x0:x1] = P[t : t + 1, x0:x1] * (1 - v) + P[b - 1 : b, x0:x1] * v
    _bilinear(P, O, l, t, r, b)
    return _to_px(O)


def seamproof(px: np.ndarray, lines: list[int], keep_right: bool = False, bracket: tuple | None = None, vertical: bool = False):
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

    sides = (1, 3) if vertical else range(4)
    for s in sides:
        Pv = view(P, s)
        d[s] = min(range(d[s], max(cap[s], d[s]) + 1), key=lambda c: (_flat(Pv, c) > 6, c if _flat(Pv, c) <= 6 else _flat(Pv, c)))
    for _ in range(600):
        out = rebuild(px, d[0], d[1], w - d[2], h - d[3], keep_right, vertical)
        Q = _prem(out)
        bad = [s for s in sides if _step(view(Q, s), d[s]) > 8]
        moved = [s for s in bad if d[s] < cap[s]]
        if not moved:
            notes = [f"side{s} step {_step(view(Q, s), d[s]):.1f}" for s in bad]
            return out, [d[0], d[1], w - d[2], h - d[3]], notes
        for s in moved:
            d[s] += 1
    raise RuntimeError("seamproof did not converge")


def ink_box(px: np.ndarray) -> list[int]:
    ys, xs = np.where(px[..., 3] >= 160)
    return [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]


# Banner emblem for the shared Play_ScrollBase scroll: the crowned die + purple ribbon tails of BannerScroll, rebuilt from New/banner-sprites.png.
# Parts are placed where BannerScroll shows them (centre cx, cy in BannerScroll px; scale = BannerScroll px per sheet px), then mapped into
# ScrollBase export px (the scroll ink 1013 wide there = 774 wide, centred on the ink) so the emblem PNG is 1:1 with ScrollBase's pixels.
# The small sparkles / dice / swooshes at the scroll ends are not cut: ~12 screen px at full size.
EMBLEM_PARTS = [  # back to front
    ("rib", (821, 472, 1155, 663), 0.360, (178, 168)),
    ("die", (480, 417, 738, 691), 0.400, (182, 112)),
    ("crown", (54, 446, 407, 685), 0.285, (181, 52)),  # centred on the die's top face (its pip at x 181), rim resting on it
]
BANNER_INK = (5, 5, 1018, 212)  # BannerScroll ink
SCROLLBASE_INK = (11, 14, 785, 176)  # export/Play ScrollBase ink (play menu/export/manifest.json)
EMBLEM_PAD = 12
EMBLEM_OUTLINE = (70, 36, 22)  # the thin dark-brown outline BannerScroll draws round the die / crown / ribbons


def premult_resize(img: Image.Image, size: tuple[int, int]) -> np.ndarray:
    """Lanczos resize on premultiplied colour: no dark/light halo at soft edges."""
    a = np.array(img.convert("RGBA")).astype(np.float32)
    a[..., :3] *= a[..., 3:] / 255
    out = np.dstack([np.array(Image.fromarray(a[..., i], "F").resize(size, Image.LANCZOS)) for i in range(4)])
    out[..., :3] = np.where(out[..., 3:] > 0.5, out[..., :3] / np.maximum(out[..., 3:], 0.5) * 255, 0)
    return np.clip(np.round(out), 0, 255).astype(np.uint8)


def banner_emblem() -> tuple[np.ndarray, list[float]]:
    """-> (RGBA px, [x, y, w, h] placement as fractions of the ScrollBase ink box)."""
    sheet = Image.open(SRC / "New" / "banner-sprites.png").convert("RGBA")
    f = (SCROLLBASE_INK[2] - SCROLLBASE_INK[0]) / (BANNER_INK[2] - BANNER_INK[0])  # ScrollBase px per BannerScroll px
    ox = SCROLLBASE_INK[0] + 0.0 - BANNER_INK[0] * f
    oy = (SCROLLBASE_INK[1] + SCROLLBASE_INK[3]) / 2 - (BANNER_INK[1] + BANNER_INK[3]) / 2 * f
    placed = []
    for _, rect, s, (cx, cy) in EMBLEM_PARTS:
        w, h = round((rect[2] - rect[0]) * s * f), round((rect[3] - rect[1]) * s * f)
        placed.append((premult_resize(sheet.crop(rect), (w, h)), round(ox + cx * f - w / 2), round(oy + cy * f - h / 2)))
    x0, y0 = min(p[1] for p in placed) - EMBLEM_PAD, min(p[2] for p in placed) - EMBLEM_PAD
    x1, y1 = max(p[1] + p[0].shape[1] for p in placed) + EMBLEM_PAD, max(p[2] + p[0].shape[0] for p in placed) + EMBLEM_PAD
    canvas = Image.new("RGBA", (x1 - x0, y1 - y0))
    for px, x, y in placed:  # each part gets its own outline so the die's outline shows over the ribbons
        part = Image.new("RGBA", canvas.size)
        part.paste(Image.fromarray(px), (x - x0, y - y0))
        a = part.getchannel("A").filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(0.8))
        outline = Image.new("RGBA", canvas.size, EMBLEM_OUTLINE + (0,))
        outline.putalpha(a)
        canvas.alpha_composite(outline)
        canvas.alpha_composite(part)
    px = bleed(np.array(canvas))
    px[..., 3][px[..., 3] < 8] = 0
    sw, sh = SCROLLBASE_INK[2] - SCROLLBASE_INK[0], SCROLLBASE_INK[3] - SCROLLBASE_INK[1]
    ink = ink_box(px)
    return px, [round((x0 + ink[0] - SCROLLBASE_INK[0]) / sw, 4), round((y0 + ink[1] - SCROLLBASE_INK[1]) / sh, 4),
                round((ink[2] - ink[0]) / sw, 4), round((ink[3] - ink[1]) / sh, 4)]


def main() -> None:
    OUT.mkdir(exist_ok=True)
    only = set(sys.argv[1:])
    if "BannerEmblem" in only:  # composed from several parts: its own path, merged into the manifest
        only.discard("BannerEmblem")
        px, box = banner_emblem()
        Image.fromarray(px).save(OUT / "Bag_BannerEmblem.png", optimize=True)
        mf = json.loads((OUT / "manifest.json").read_text())
        mf["BannerEmblem"] = {"w": px.shape[1], "h": px.shape[0], "ink": ink_box(px), "box": box, "asset": mf.get("BannerEmblem", {}).get("asset", "")}
        (OUT / "manifest.json").write_text(json.dumps(mf, indent=1))
        print(f"BannerEmblem: {px.shape[1]}x{px.shape[0]} ink {ink_box(px)} box {box}")
        if not only:
            return
    sheets: dict[str, Image.Image] = {}
    old = OUT / "manifest.json"
    manifest = json.loads(old.read_text()) if only and old.exists() else {}
    ref = np.array(Image.open(SRC / PILL_PINK_REF[0]).convert("RGB"))
    x0, y0, x1, y1 = PILL_PINK_REF[1]
    pink_ref = np.median(ref[y0:y1, x0:x1].reshape(-1, 3), 0)
    tx, ty, tw, th = TAB_REF[1]
    tab_ref = np.median(np.array(Image.open(SRC / TAB_REF[0]).convert("RGB"))[ty : ty + th, tx : tx + tw].reshape(-1, 3), 0)
    RECOLOR["TabPurple"] = lambda a: recolor_pink(a, tab_ref, (0.15, 0.8))
    shared: dict[str, tuple[float, int]] = {}
    for name, (sheet, rect, side, margin) in SPRITES.items():
        if only and name not in only:
            continue
        img = sheets.setdefault(sheet, Image.open(SRC / sheet).convert("RGBA"))
        k, m = shared[SHARED_SCALE[name]] if name in SHARED_SCALE else fit(rect[2], rect[3], margin, side=side, height=HEIGHTS.get(name))
        shared[name] = (k, m)
        recolor = (lambda a: recolor_pink(a, pink_ref)) if name == "PillPink" else RECOLOR.get(name)
        px, masked = cut(img, rect, margin, k, m, recolor, name in FEATHER)
        if name == "GlowRing":  # a faint streak of the neighbouring art survives at alpha <= 25: the halo below that is invisible anyway
            px[..., 3][px[..., 3] < 28] = 0
        if name.startswith("StatsLine"):
            px = strip_left_diamond(px, m)
            if name == "StatsLineR":
                px = px[:, ::-1].copy()
        assert px.shape[0] <= 1024 and px.shape[1] <= 1024, name
        info = {"w": px.shape[1], "h": px.shape[0]}
        note = f"k={k:.3f} m={m}" + (f" MASKED {masked} opaque neighbour px" if masked else "")
        if name in ERASE_GLYPH:
            px = erase_glyph(px, *ERASE_GLYPH[name])
        if name in SLICED:
            lines = measure(px, SLICED[name] or (0, 0, 0, 0))
            if name in VERTICAL:
                lines[0], lines[2] = 0, px.shape[1]
            px, line, notes = seamproof(px, lines, name in KEEP_RIGHT, KEEP_RIGHT.get(name), name in VERTICAL)
            info["slice"] = line
            note += f" {line}" + "".join(f" WARN {n}" for n in notes)
        if name == "Window":
            px = trim_outline(px)
        if name in TRIM:  # tight crop to the art (the ring assert already ran on the padded crop): the sprite box is the ink, sized by its Ink
            ys, xs = np.nonzero(px[..., 3])
            pad = TRIM[name]
            px = np.pad(px[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1], ((pad, pad), (pad, pad), (0, 0)))
            info["w"], info["h"] = px.shape[1], px.shape[0]
        info["ink"] = ink_box(px)
        Image.fromarray(px).save(OUT / f"Bag_{name}.png", optimize=True)
        manifest[name] = info
        print(f"{name}: {px.shape[1]}x{px.shape[0]} {note}")
    if only:
        old.write_text(json.dumps(manifest, indent=1))
        return
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
