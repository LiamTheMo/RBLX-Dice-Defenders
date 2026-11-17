#!/usr/bin/env python
"""Compare a Roblox Studio capture of a menu against its 1672x941 mockup.

Outputs in --out: side.png, overlay.png, diff.png (abs diff x3), report.md,
crops/<element>.png (mockup | capture, x2 zoom) for every --boxes element.
"""
import argparse
import json
import os
import re

import numpy as np
from PIL import Image

W, H = 1672, 941
TOL_XW, TOL_YH = 17.0, 9.4  # 1% of frame width / height


def load_boxes(path):
    if not path:
        return {}
    with open(path, encoding="utf-8") as f:
        return {k: [float(v) for v in d["box"]] for k, d in json.load(f).items()}


def capture_crop(cap, a):
    if a.crop:
        x, y, w, h = [float(v) for v in a.crop.split(",")]
    else:
        k = cap.width / a.vw  # capture px per logical px
        x, y = 0.0, a.topbar * k
        w, h = W * a.uiscale * k, H * a.uiscale * k
    box = (round(x), round(y), round(x + w), round(y + h))
    return cap.crop(box).resize((W, H), Image.LANCZOS), box


def clamp_box(box, w, h):
    x0 = min(max(0, round(box[0])), w - 1)
    y0 = min(max(0, round(box[1])), h - 1)
    x1 = min(max(x0 + 1, round(box[0] + box[2])), w)
    y1 = min(max(y0 + 1, round(box[1] + box[3])), h)
    return x0, y0, x1, y1


def mean_rgb(arr, box):
    x0, y0, x1, y1 = clamp_box(box, arr.shape[1], arr.shape[0])
    return arr[y0:y1, x0:x1].reshape(-1, 3).mean(axis=0)


def fmt(box):
    return ", ".join(f"{v:.1f}" for v in box)


def safe(name):
    return re.sub(r'[\\/:*?"<>|]', "_", name)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mockup", required=True)
    ap.add_argument("--capture", required=True)
    ap.add_argument("--crop", help="x,y,w,h in capture px; overrides the default crop math")
    ap.add_argument("--vw", type=float, default=1235.33, help="logical viewport width the capture shows")
    ap.add_argument("--topbar", type=float, default=58, help="logical top bar height")
    ap.add_argument("--uiscale", type=float, default=0.7240, help="emulated root scale")
    ap.add_argument("--boxes", help='JSON {"name": {"box": [x,y,w,h]}} measured on the mockup')
    ap.add_argument("--dump", help='JSON {"name": {"box": [x,y,w,h]}} built UI boxes, design px')
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    os.makedirs(os.path.join(a.out, "crops"), exist_ok=True)
    mock = Image.open(a.mockup).convert("RGB")
    if mock.size != (W, H):
        mock = mock.resize((W, H), Image.LANCZOS)
    cap_full = Image.open(a.capture).convert("RGB")
    cap, crop_box = capture_crop(cap_full, a)

    m = np.asarray(mock, dtype=np.float64)
    c = np.asarray(cap, dtype=np.float64)
    d = np.abs(m - c)
    mean_all = d.mean()

    gap = 8
    side = Image.new("RGB", (2 * W + gap, H), (128, 128, 128))
    side.paste(mock, (0, 0))
    side.paste(cap, (W + gap, 0))
    side.save(os.path.join(a.out, "side.png"))
    Image.blend(mock, cap, 0.5).save(os.path.join(a.out, "overlay.png"))
    Image.fromarray(np.clip(d * 3, 0, 255).astype(np.uint8)).save(os.path.join(a.out, "diff.png"))

    boxes = load_boxes(a.boxes)
    dump = load_boxes(a.dump)
    lines = [
        "# UI compare",
        "",
        f"- mockup: `{a.mockup}`",
        f"- capture: `{a.capture}` ({cap_full.width}x{cap_full.height})",
        f"- capture crop (x,y,w,h px): {crop_box[0]}, {crop_box[1]}, {crop_box[2] - crop_box[0]}, {crop_box[3] - crop_box[1]}",
        f"- whole-image mean abs diff: {mean_all:.2f} / 255",
    ]

    if boxes and dump:
        lines += ["", "## Built vs mockup boxes (design px)", "",
                  "element | mockup box | built box | dx | dy | dw | dh | within 1% of frame",
                  "--- | --- | --- | --- | --- | --- | --- | ---"]
        for name, mb in boxes.items():
            if name not in dump:
                continue
            bb = dump[name]
            dx, dy, dw, dh = bb[0] - mb[0], bb[1] - mb[1], bb[2] - mb[2], bb[3] - mb[3]
            ok = abs(dx) <= TOL_XW and abs(dw) <= TOL_XW and abs(dy) <= TOL_YH and abs(dh) <= TOL_YH
            lines.append(f"{name} | {fmt(mb)} | {fmt(bb)} | {dx:.1f} | {dy:.1f} | {dw:.1f} | {dh:.1f} | {'yes' if ok else 'no'}")
        missing = [n for n in boxes if n not in dump]
        extra = [n for n in dump if n not in boxes]
        lines += ["", f"Missing from build: {', '.join(missing) or 'none'}",
                  f"Extra in build: {', '.join(extra) or 'none'}"]

    if boxes:
        lines += ["", "## Box colour (mean RGB inside each mockup box)", "",
                  "element | mockup mean RGB | capture mean RGB | max channel delta (|mean diff|)",
                  "--- | --- | --- | ---"]
        for name, box in boxes.items():
            mm, mc = mean_rgb(m, box), mean_rgb(c, box)
            lines.append(f"{name} | {tuple(int(round(v)) for v in mm)} | "
                         f"{tuple(int(round(v)) for v in mc)} | {np.abs(mm - mc).max():.1f}")
            mx0, my0, mx1, my1 = clamp_box(box, W, H)
            pair = Image.new("RGB", (2 * (2 * (mx1 - mx0)) + gap, 2 * (my1 - my0)), (128, 128, 128))
            pair.paste(mock.crop((mx0, my0, mx1, my1)).resize((2 * (mx1 - mx0), 2 * (my1 - my0)), Image.NEAREST), (0, 0))
            pair.paste(cap.crop((mx0, my0, mx1, my1)).resize((2 * (mx1 - mx0), 2 * (my1 - my0)), Image.NEAREST),
                       (2 * (mx1 - mx0) + gap, 0))
            pair.save(os.path.join(a.out, "crops", safe(name) + ".png"))
        lines += ["", "Crops: crops/<element>.png (mockup left, capture right, x2)."]

    with open(os.path.join(a.out, "report.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"mean abs diff {mean_all:.2f}/255; outputs in {a.out}")


if __name__ == "__main__":
    main()
