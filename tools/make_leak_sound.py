"""Generate EnemyLeak.ogg (Assets/SFX/game, or the directory in argv[1]): the wood-block "tock" when an enemy slips into the exit portal.
A stick hitting a block of wood: a dense wooden body (tock) with a sharp, short TACK layered on its first few milliseconds.

Usage: python tools/make_leak_sound.py [out_dir]   Needs numpy, scipy, soundfile.
"""
import os
import sys

import numpy as np
import soundfile as sf
from scipy.signal import butter, lfilter

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Assets', 'SFX', 'game')
rng = np.random.default_rng(5)
t = np.arange(int(0.3 * SR)) / SR

lp = lambda x, fc: lfilter(*butter(2, fc / (SR / 2), 'low'), x)

# Two layers. BODY: damped, dense wood (short-ringing modes + a band of filtered noise, so it is solid, not a hollow "bonk").
# TACK: the dominant front edge: a deep-ish tick (~1 kHz) with a crisp, hiss-free stick tap.
bp = lambda x, lo, hi: lfilter(*butter(2, [lo / (SR / 2), hi / (SR / 2)], 'band'), x)
body = sum(g * np.sin(2 * np.pi * f * t) * np.exp(-t * d)
           for f, g, d in ((620, 1, 70), (880, .6, 85), (1330, .55, 100), (1650, .35, 120), (2250, .25, 140)))
body += bp(rng.standard_normal(len(t)), 400, 2800) * np.exp(-t * 55) * 0.7
tack = sum(g * np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, g, d in ((1000, 1, 150), (1650, .7, 210), (2600, .4, 280)))
tack += lp(rng.standard_normal(len(t)), 4200) * np.exp(-t * 700) * 1.0

y = body * 0.4 + tack * 1.3
y *= 0.85 / np.abs(y).max()
y[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
os.makedirs(OUT, exist_ok=True)
sf.write(os.path.join(OUT, 'EnemyLeak.ogg'), y.astype(np.float32), SR, format='OGG', subtype='VORBIS')
print('EnemyLeak.ogg %.2f s' % (len(y) / SR))
