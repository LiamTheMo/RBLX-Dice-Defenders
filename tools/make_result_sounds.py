"""Generate the end-of-match stingers into Assets/SFX/game (or the directory in argv[1]), in the battle theme's
palette (D minor, brass + timpani + bells + a little reverb):

  Victory.ogg  - rising brass fanfare that lands on D major (the Picardy third), bell sparkle, timpani roll and crash
  Defeat.ogg   - slow falling minor brass, a tolling low bell and a dull timpani; ends on a bare, sour D + E-flat
  GameOver.ogg - neutral "match finished": short snare roll, timpani hit and an open fifth (no third, so it is
                 neither happy nor sad) with a bell ping

Usage: python tools/make_result_sounds.py [out_dir]   Needs numpy, scipy, soundfile.
"""
import os
import sys

import numpy as np
import soundfile as sf
from scipy.signal import butter, lfilter, oaconvolve

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Assets', 'SFX', 'game')
rng = np.random.default_rng(3)
hz = lambda m: 440 * 2 ** ((m - 69) / 12)
lp = lambda x, fc: lfilter(*butter(2, fc / (SR / 2), 'low'), x)
hp = lambda x, fc: lfilter(*butter(2, fc / (SR / 2), 'high'), x)

def env(n, a, rel):
    t = np.arange(n) / SR
    e = np.minimum(t / a, 1)
    r = min(int(rel * SR), n)
    e[-r:] *= np.linspace(1, 0, r)
    return e

def brass(m, dur, bright=2800, droop=0.0, a=0.04, rel=0.12):
    """detuned saws with vibrato; `droop` sags the pitch over the note (fraction of the frequency)"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = hz(m) * (1 - droop * (t / dur) ** 2) * (1 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.minimum(t / 0.2, 1))
    w = 0
    for d in (0.996, 1.004):
        ph = np.cumsum(f * d) / SR
        w = w + sum(np.sin(2 * np.pi * k * ph) / k for k in range(1, int(bright / hz(m)) + 1))
    return w * env(n, a, rel) * 0.25

def bell(m, dur):
    t = np.arange(int(dur * SR)) / SR
    w = sum(g * np.sin(2 * np.pi * hz(m) * r * t) * np.exp(-t * d) for r, g, d in ((1, 1, 3.5), (2.76, .5, 6), (5.4, .25, 10), (8.93, .12, 16)))
    return w * env(len(t), 0.001, 0.05) * 0.5

def timp(m, dur=0.9):
    t = np.arange(int(dur * SR)) / SR
    return np.sin(2 * np.pi * np.cumsum(hz(m) * (1 + 0.25 * np.exp(-t * 18))) / SR) * np.exp(-t * 4.5) * 1.2

def snare():
    t = np.arange(int(0.25 * SR)) / SR
    shell = np.sin(2 * np.pi * np.cumsum(165 * (1 + 0.6 * np.exp(-t * 45))) / SR) * np.exp(-t * 16)
    wires = hp(lp(rng.standard_normal(len(t)), 6500), 1100) * (0.65 * np.exp(-t * 11) + 0.35 * np.exp(-t * 38))
    return shell * 0.75 + wires * 0.7

def crash(dur=1.8):
    t = np.arange(int(dur * SR)) / SR
    return hp(rng.standard_normal(len(t)), 4500) * np.exp(-t * 2.4) * 0.5

class Track:
    def __init__(self, seconds):
        self.dry = np.zeros(int(seconds * SR))
        self.wet = np.zeros_like(self.dry)

    def add(self, t0, sig, gain=1.0, send=0.0):
        i = int(t0 * SR)
        sig = sig[:len(self.dry) - i] * gain
        self.dry[i:i + len(sig)] += sig
        self.wet[i:i + len(sig)] += sig * send

    def save(self, name, tail=1.2):
        n = int(tail * SR)
        ir = lp(rng.standard_normal(n) * np.exp(-np.arange(n) / SR * 3.2), 4500) * 0.02
        y = self.dry + oaconvolve(self.wet, ir)[:len(self.dry)]
        y = np.tanh(y * 0.9) / np.tanh(0.9)
        y *= 0.7 / np.abs(y).max()
        y[-int(0.04 * SR):] *= np.linspace(1, 0, int(0.04 * SR))
        os.makedirs(OUT, exist_ok=True)
        sf.write(os.path.join(OUT, name), y.astype(np.float32), SR, format='OGG', subtype='VORBIS')
        print('%s %.2f s' % (name, len(y) / SR))

# ---- Victory: da-da-da-DAAA, then the sky opens up in D major
v = Track(3.2)
for i, (m, d) in enumerate(((62, .2), (66, .2), (69, .2))):          # D4 F#4 A4: a rising pickup
    v.add(0.1 + i * 0.22, brass(m, d, a=0.015, rel=0.03), 1, 0.2)
for m in (62, 66, 69, 74, 78):                                       # D major chord under the held D5
    v.add(0.78, brass(m, 1.7, a=0.05, rel=0.5), 0.9 if m < 74 else 1.1, 0.3)
for i in range(6):                                                   # timpani roll into the hit
    v.add(0.1 + i * 0.1, timp(50, 0.3), 0.15 + 0.05 * i)
v.add(0.78, timp(38), 1.0, 0.3)
v.add(0.78, crash(), 0.6, 0.3)
for i, m in enumerate((86, 90, 93, 98)):                             # bell sparkle D6 F#6 A6 D7
    v.add(1.0 + i * 0.12, bell(m, 1.2), 0.45, 0.6)
v.save('Victory.ogg')

# ---- Defeat: the horn sinks, the bell tolls, the last chord curdles
d = Track(3.6)
for i, m in enumerate((62, 60, 57)):                                 # D4 C4 A3: stepping down
    d.add(0.05 + i * 0.5, brass(m, 0.55, 1800, a=0.06, rel=0.15), 1, 0.3)
d.add(1.6, brass(50, 1.7, 1500, droop=0.07, a=0.08, rel=0.6), 1, 0.4)    # D3, sagging
d.add(1.6, brass(51, 1.7, 1500, droop=0.07, a=0.08, rel=0.6), 0.55, 0.4) # E-flat3 rubbing against it
d.add(0.05, timp(38), 0.9, 0.3)
d.add(1.6, timp(33), 1.1, 0.4)
d.add(0.0, bell(38, 3.0), 0.8, 0.6)                                   # low toll
d.add(1.6, bell(26, 3.0), 0.7, 0.6)
d.save('Defeat.ogg')

# ---- GameOver: neutral: a roll, a hit, an open fifth
g = Track(2.2)
for i in range(8):
    g.add(0.05 + i * 0.07, snare(), 0.15 + 0.06 * i, 0.15)
g.add(0.62, timp(38), 1.0, 0.3)
for m in (50, 57, 62, 69):                                            # D3 A3 D4 A4: root and fifth only
    g.add(0.62, brass(m, 1.2, 2000, a=0.05, rel=0.45), 0.9, 0.35)
g.add(0.7, bell(81, 1.4), 0.5, 0.6)                                   # A5 ping
g.save('GameOver.ogg')
