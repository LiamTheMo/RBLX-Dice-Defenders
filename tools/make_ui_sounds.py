"""Generates the round, cartoony two-note menu sounds into Assets/SFX/ui:
UiOpen.ogg (up-beat, rising), UiClose.ogg (down-beat, falling) and
UiClick.ogg (a tiny dice-tumble of plinks for plain button presses)."""
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


def plink(y, start, f, amp):
    """A very short hollow 'plink' (sine + a bright inharmonic overtone, fast decay) - far snappier than the menu notes."""
    n = int(0.05 * SR)
    t = np.arange(n) / SR
    w = (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t)) * np.exp(-t * 110) * np.minimum(t / 0.001, 1.0)
    i = int(start * SR)
    y[i:i + n] += w * amp

def make_click(name, dice):
    """A tiny dice tumble. Each die is four rapid plinks at wobbling pitches, getting quieter;
    `dice` is a list of (start offset, pitch multiplier, volume) so several dice overlap like a handful."""
    n = int(0.24 * SR)
    y = np.zeros(n)
    base = ((0.000, 1250, 0.9), (0.028, 1650, 0.8), (0.054, 1400, 0.6), (0.085, 1850, 0.45))
    for off, mult, vol in dice:
        for st, f, a in base:
            plink(y, off + st, f * mult, a * vol)
    t = np.arange(n) / SR
    y *= np.minimum(((n / SR) - t) / 0.03, 1.0)
    y = 0.45 * y / np.max(np.abs(y))
    sf.write(os.path.join(OUT, name), y.astype('float32'), SR, format='OGG', subtype='VORBIS')

make_click('UiClickSingle.ogg', [(0, 1.0, 1.0)])                       # one die (the first version)
make_click('UiClick.ogg', [(0, 1.0, 1.0), (0.012, 0.8, 0.8), (0.03, 1.2, 0.7), (0.05, 0.9, 0.55)])  # a handful
