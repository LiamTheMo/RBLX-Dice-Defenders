"""Export the Settings menu sprites: python tools/slice_settings.py

The new Settings sheets add no new art: every sprite the rebuilt menu draws is one of the already-cut PNGs in
Assets/UI/new/settings menu/reused/ (byte-identical to the old uploads in Assets/UI/old/settings menu/export, so the
asset ids carry over). This copies the used ones to Assets/UI/new/settings menu/export/Settings_<Name>.png and writes
manifest.json {name: {sheet, w, h, ink [x0, y0, x1, y1] (alpha > 60), slice false, asset}}; it also checks each PNG's edge:
no opaque pixel on the border, and no light matte on the semi-transparent ring. Row bars, panel, value pill, slider track
and dividers are code-drawn, so RowFrame / ValuePill / Rule / Diamond / GearPair / Die / tab icons are not exported.
"""

import json
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slice_common as sc  # noqa: E402

SRC = sc.UI / "settings menu"
OUT = SRC / "export"
OLD = sc.UI.parent / "old" / "settings menu" / "export" / "manifest.json"
USED = [
    "ToggleOn", "ToggleOff", "Knob", "ArrowLeft", "ArrowRight", "RefreshWhite",
    "MasterVolume", "Music", "SoundEffects", "InterfaceSounds", "Ambience",
    "EffectsQuality", "Projectile", "Shadows", "ScreenShake", "UiScale", "EffectScale",
    "AutoSkip", "DamageNumbers", "Announce", "AutoClose",
    "ReducedMotion", "HighContrast", "ShowFps", "HideOthers", "Notifications",
]  # fmt: skip


def main() -> None:
    OUT.mkdir(exist_ok=True)
    ids = json.loads(OLD.read_text())
    manifest = {}
    for name in USED:
        src = SRC / "reused" / f"Settings_{name}.png"
        a = np.array(Image.open(src).convert("RGBA"))
        edge = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
        assert edge[:, 3].max() == 0, f"{name}: opaque pixel on the border"
        ring = a[(a[..., 3] > 0) & (a[..., 3] < 128)]
        lum = ring[:, :3].astype(int).sum(axis=1) / 3 if len(ring) else np.array([0])
        halo = float((lum > 200).mean())
        ys, xs = np.where(a[..., 3] > 60)
        shutil.copyfile(src, OUT / src.name)
        manifest[name] = {
            "sheet": "reused",
            "w": a.shape[1],
            "h": a.shape[0],
            "ink": [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1],
            "slice": False,
            "asset": ids[name]["asset"],
        }
        print(f"{name:16} {a.shape[1]:3}x{a.shape[0]:3} light-ring {halo:.2f}")
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))
    print(len(manifest), "sprites ->", OUT)


if __name__ == "__main__":
    main()
