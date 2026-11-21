"""Generates a short, soft UI click: Audio/UiClick.ogg (same family as UiHover)"""
import numpy as np, soundfile as sf

SR = 44100
dur = 0.10
t = np.arange(int(SR * dur)) / SR

# quick downward pitch drop 1100 -> 600 Hz = a "press" feel (hover rises, click falls)
freq = 600 + (1100 - 600) * np.exp(-t * 70)
phase = 2 * np.pi * np.cumsum(freq) / SR
y = np.sin(phase) + 0.3 * np.sin(2 * phase)
y *= np.minimum(t / 0.002, 1.0) * np.exp(-t * 45)

# tiny filtered-noise tick at the very start for a crisp transient
rng = np.random.default_rng(7)
n = rng.standard_normal(len(t))
n = np.convolve(n, [1, -1], mode='same')  # high-pass-ish
y += 0.25 * n * np.exp(-t * 600)

y *= np.minimum((dur - t) / 0.01, 1.0)
y = 0.55 * y / np.max(np.abs(y))
sf.write('UiClick.ogg', y.astype('float32'), SR, format='OGG', subtype='VORBIS')
