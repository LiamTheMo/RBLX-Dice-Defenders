"""Measure the shared window chrome in the Roll and Bag mockups (1672x941) and print the numbers (copied into
Assets/UI/new/_overhaul/shared-measure.md). Usage: python tools/measure_shared.py"""

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "Assets" / "UI" / "new"


def load(name):
    return np.array(Image.open(ROOT / name / "mockup.png").convert("RGB")).astype(int)


def bbox(mask, ox=0, oy=0):
    ys, xs = np.nonzero(mask)
    return (ox + xs.min(), oy + ys.min(), ox + xs.max(), oy + ys.max())


def rgb(im, x, y, r=2):
    return tuple(int(v) for v in im[y - r : y + r + 1, x - r : x + r + 1].reshape(-1, 3).mean(0).round())


def main():
    for name in ("roll menu", "bag menu"):
        im = load(name)
        print("==", name)
        # window rim peaks: left col 282 / right 1389 / top 89 / bottom 749 (brightest column near the edge at x=700 / y=400)
        row = im[400].sum(1)
        left = 270 + int(np.argmax(row[270:292]))
        right = 1380 + int(np.argmax(row[1380:1396]))
        col = im[:, 700].sum(1)
        top = 84 + int(np.argmax(col[84:96]))
        bot = 742 + int(np.argmax(col[742:756]))
        print("rim peaks x", left, right, "y", top, bot)
        print("rim colour (peak, left)", tuple(im[400, left]), "dark outer", tuple(im[400, left - 2]), "dark inner", tuple(im[400, left + 3]))
        print("fill grad (x 288..294 mean) y100", rgb(im, 291, 100, 3), "y400", rgb(im, 291, 400, 3), "y740", rgb(im, 291, 740, 3))
        # corner radius: rim leaves the straight line (top rim y=top is straight from x = left + r)
        xs = [x for x in range(left, left + 80) if im[top, x].min() > 150]
        ys = [y for y in range(top, top + 80) if im[y, left].min() > 150]
        print("corner radius (rim centre) ~", xs[0] - left if xs else None, ys[0] - top if ys else None)
        # title: white fill bbox
        sub = im[92:150, 700:980]
        print("title white bbox", bbox(sub.min(2) > 235, 700, 92))
        # close X
        sub = im[90:160, 1300:1400]
        print("close red bbox", bbox((sub[..., 0] > 200) & (sub[..., 1] < 90) & (sub[..., 2] < 90), 1300, 90))
        # tabs: body rows y 160..190 dark outline columns (lum < 22 next to lum > 40 inside)
        lum = im.mean(2)
        xs = [x for x in range(300, 1380) if lum[175, x] < 24 and lum[175, x + 3] > 40 and lum[175, x - 3] < 60]
        print("tab outline columns y175 (left edges)", xs)
        ys = [y for y in range(140, 215) if abs(lum[y, 380] - lum[y - 1, 380]) > 40]
        print("tab y edges at x380", ys)
        # tab body colour, underline colour
        print("tab body", rgb(im, 380, 175, 2), "tab top gloss", tuple(im[155, 380]), "underline y~201", rgb(im, 450, 201, 1))
        und = (im[..., 0] > 220) & (im[..., 1] > 150) & (im[..., 1] < 215) & (im[..., 2] < 80)
        print("underline bbox", bbox(und[190:215, 300:700], 300, 190))
        # tab label (white) bbox for first tab
        sub = im[158:196, 345:625]
        print("tab1 label white bbox", bbox(sub.min(2) > 230, 345, 158))
    im = load("roll menu")
    print("== roll panels (rim peaks)")
    print("featured L/R/T/B", 301.5, 1021.5, 225, 537, "fill", rgb(im, 320, 300), rgb(im, 320, 520), "rim", tuple(im[400, 301]), tuple(im[225, 600]))
    print("pity strip top/bot", 553, 629, "rim", tuple(im[553, 900]), "fill", rgb(im, 330, 590))
    track = im[600, 600:1310]
    print("pity track fill (empty part)", rgb(im, 1100, 601, 1), "bar yellow", rgb(im, 650, 601, 1))
    im = load("bag menu")
    print("== bag fields")
    print("search field fill", rgb(im, 600, 249, 3), "rim", tuple(im[230, 520]), "sort fill", rgb(im, 900, 249, 3))
    print("detail panel fill", rgb(im, 1040, 450, 3), "card fill", rgb(im, 330, 330, 3), "footer strip fill", rgb(im, 330, 720, 2))


if __name__ == "__main__":
    main()
