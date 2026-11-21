"""Generates a button down + up pair: Audio/UiDown.ogg and Audio/UiUp.ogg"""
import numpy as np, soundfile as sf

SR = 44100
rng = np.random.default_rng(7)

def tone(dur, f0, f1, glide, decay, overtone):
    t = np.arange(int(SR * dur)) / SR
    freq = f1 + (f0 - f1) * np.exp(-t * glide)
    ph = 2 * np.pi * np.cumsum(freq) / SR
    y = np.sin(ph) + overtone * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)
    return t, y * np.minimum(t / 0.002, 1.0) * np.exp(-t * decay)

def tick(t, amt, rate):
    n = np.convolve(rng.standard_normal(len(t)), [1, -1], mode='same')
    return amt * n * np.exp(-t * rate)

def save(name, y, t, dur, peak):
    y = y * np.minimum((dur - t) / 0.008, 1.0)
    y = peak * y / np.max(np.abs(y))
    sf.write(name, y.astype('float32'), SR, format='OGG', subtype='VORBIS')

# DOWN: short, slight dip from 950 to 740 Hz with a crisp tick
d = 0.07
t, y = tone(d, 950, 740, 90, 55, 0.35)
save('UiDown.ogg', y + tick(t, 0.3, 700), t, d, 0.55)

# UP: lighter release, rising 1000 -> 1700 Hz, softer tick
d = 0.08
t, y = tone(d, 640, 1040, 45, 42, 0.25)    # f0 < f1 so it rises
save('UiUp.ogg', 0.8 * y + tick(t, 0.15, 900), t, d, 0.42)
