"""Shared helpers for the slice_*.py UI-sheet cutters (paths, labelling, cleaning, PNG/manifest writing). Library only, no CLI.

Needs Pillow + numpy. slice_bag.py, slice_quest.py and slice_shared.py also use these; every cutter imports this module.
"""

import io
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "Assets" / "UI" / "new"
OPEN = 5  # radius of the morphological opening in clean()


def load_rgba(path: Path) -> np.ndarray:
    return np.array(Image.open(path).convert("RGBA"))


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


def clean(arr: np.ndarray, opening: int = OPEN) -> np.ndarray:
    """Keep the solid blobs + 1 px ring, recolour partly transparent pixels from the solid outline, trim to the bbox."""
    a = arr[..., 3]
    lab = label8(a >= 128)
    sizes = np.bincount(lab.ravel())
    sizes[0] = 0
    keep = np.isin(lab, [i for i in range(1, len(sizes)) if sizes[i] >= 0.02 * sizes.max()])
    keep = (dilate(~dilate(~keep, opening), opening) & keep if opening else keep)  # opening: drops thin protrusions (glow drips, specks) narrower than 2 x opening + 1 px
    keep = dilate(keep, 1) & (a > 0)
    out = arr.copy()
    out[..., 3] = np.where(keep, a, 0)
    out[..., 3][out[..., 3] < 8] = 0
    out[..., 3][out[..., 3] >= 248] = 255
    h, w = out.shape[:2]
    todo = (out[..., 3] > 0) & (out[..., 3] < 250)
    pad = 4
    rgb = np.pad(out[..., :3], ((pad, pad), (pad, pad), (0, 0)))
    srcp = np.pad(out[..., 3] >= 250, pad)
    res = out[..., :3].copy()
    offs = sorted(((dy, dx) for dy in range(-pad, pad + 1) for dx in range(-pad, pad + 1) if dy or dx), key=lambda o: o[0] ** 2 + o[1] ** 2)
    for dy, dx in offs:
        ok = todo & srcp[pad + dy : pad + dy + h, pad + dx : pad + dx + w]
        res[ok] = rgb[pad + dy : pad + dy + h, pad + dx : pad + dx + w][ok]
        todo &= ~ok
    out[..., :3] = res
    ys, xs = np.where(out[..., 3] > 0)
    out = out[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
    return bleed(out)


def png_bytes(px: np.ndarray) -> bytes:
    buf = io.BytesIO()
    Image.fromarray(px).save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def save_png(path: Path, px: np.ndarray) -> None:
    """Write the PNG only when its bytes change, so a rerun never touches an uploaded file."""
    data = png_bytes(px)
    if not path.exists() or path.read_bytes() != data:
        path.write_bytes(data)


def entry(px: np.ndarray, sheet: str, rect) -> dict:
    """Manifest row for a whole (unsliced) asset."""
    return {"w": int(px.shape[1]), "h": int(px.shape[0]), "sheet": sheet, "rect": [int(v) for v in rect], "slice": False}


def write_manifest(out: Path, manifest) -> None:
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))
