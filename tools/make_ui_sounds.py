"""Generates the round, cartoony two-note menu sounds into Assets/SFX/ui:
UiOpen.ogg (up-beat, rising) and UiClose.ogg (down-beat, falling)."""
import os
import numpy as np, soundfile as sf

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'Assets', 'SFX', 'ui')
rng = np.random.default_rng(7)

def note(y, start, f, dur, amp, bloop, decay=30):
    """One bubbly note. bloop > 0: pitch scoops up into the note; < 0: drops into it."""
    t = np.arange(int(dur * SR)) / SR
    fr = f * (1 + bloop * np.exp(-t * 80))
    w = np.zeros_like(t)
    for det, g in ((1.0, 1.0), (1.002, 0.3)):      # light chorus = fuller
        ph = 2 * np.pi * np.cumsum(fr * det) / SR
        w += g * (np.sin(ph) + 0.2 * np.sin(2 * ph) + 0.1 * np.sin(0.5 * ph))  # mostly sine
    w *= np.minimum(t / 0.005, 1.0) * np.exp(-t * decay) * amp
    i = int(start * SR)
    y[i:i + len(w)] += w

def make(name, f1, f2, bloop, gap=0.07):
    n = int((gap + 0.18) * SR)
    y = np.zeros(n)
    t = np.arange(n) / SR
    note(y, 0, f1, 0.16, 1.0, bloop)
    note(y, gap, f2, 0.16, 0.9, bloop)
    # soft low-passed "pop" at the start instead of a sharp tick
    pop = np.convolve(rng.standard_normal(n), np.ones(24) / 24, mode='same')
    y += 0.8 * pop * np.exp(-t * 350)
    # short echo tail so it does not feel empty
    for d, g in ((0.03, 0.12),):
        k = int(d * SR)
        y[k:] += g * y[:-k].copy()
    y *= np.minimum(((n / SR) - t) / 0.02, 1.0)
    y = 0.55 * y / np.max(np.abs(y))
    sf.write(os.path.join(OUT, name), y.astype('float32'), SR, format='OGG', subtype='VORBIS')

make('UiOpen.ogg',  523, 784, +0.05)   # C5 -> G5, scoops up
make('UiClose.ogg', 659, 440, -0.04)   # E5 -> A4, drops down
