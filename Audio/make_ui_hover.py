"""Generates a short, soft UI hover blip: Audio/UiHover.ogg"""
import numpy as np, soundfile as sf

SR = 44100
dur = 0.12
t = np.arange(int(SR * dur)) / SR

# quick upward pitch glide 880 -> 1320 Hz, with a soft octave overtone
freq = 880 + (1320 - 880) * np.minimum(t / 0.05, 1.0)
phase = 2 * np.pi * np.cumsum(freq) / SR
y = np.sin(phase) + 0.25 * np.sin(2 * phase)

# 4 ms attack, exponential decay -> no clicks
env = np.minimum(t / 0.004, 1.0) * np.exp(-t * 32)
y *= env
y *= np.minimum((dur - t) / 0.01, 1.0)  # fade out the tail to zero

y = 0.5 * y / np.max(np.abs(y))
sf.write('UiHover.ogg', y.astype('float32'), SR, format='OGG', subtype='VORBIS')
