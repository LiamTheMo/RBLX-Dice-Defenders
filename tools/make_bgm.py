"""Compose and render "Kingdom of Dice", the lobby/battle BGM loop (C major, 132 BPM, 4/4, 64 bars ~1:56).

One score (the tables below) drives both outputs, so the sheet music and the audio can never disagree:
  Assets/Music/KingdomOfDice.ogg   - layered synth voices + reverb, loop-safe (reverb tail wraps onto bar 1)
  docs/music/KingdomOfDice.musicxml - Lead / Strings / Bass parts + chord symbols (open in MuseScore, Flat, Finale...)

Usage: python tools/make_bgm.py [out_dir]   Needs numpy, scipy, soundfile.
"""
import os
import re
import sys

import numpy as np
import soundfile as sf
from scipy.signal import butter, fftconvolve, lfilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'Assets', 'Music')
SCORE_DIR = os.path.join(ROOT, 'docs', 'music')
SR, BPM = 44100, 132
SPB = 60 / BPM                      # seconds per beat
rng = np.random.default_rng(11)

# ---------------------------------------------------------------- the score
# Melody tokens: "pitch/beats". Four 8-bar sections; harmony is one chord per bar.
A_MEL = ("C5/1 E5/.5 G5/.5 C6/1.5 G5/.5;Bb5/1 G5/.5 D5/.5 F5/1 D5/1;A5/1 F5/.5 A5/.5 C6/1.5 A5/.5;"
         "B5/1 G5/.5 B5/.5 D6/2;E6/1 D6/.5 C6/.5 G5/1 E5/1;C6/.5 A5/.5 E5/1 A5/.5 C6/.5 E6/1;"
         "D6/1 F6/.5 D6/.5 A5/1 F5/1;G5/.5 A5/.5 B5/.5 C6/.5 D6/1 B5/1")
B_MEL = ("E5/1.5 A5/.5 C6/1 B5/.5 A5/.5;A5/1.5 C6/.5 F6/1 E6/.5 C6/.5;G5/1.5 C6/.5 E6/1 D6/.5 C6/.5;"
         "B5/1 D6/1 G6/1 F6/.5 D6/.5;E6/1.5 C6/.5 A5/1 C6/1;F6/1.5 A5/.5 C6/1 F6/1;"
         "D6/1 G6/1 B5/1 D6/1;G5/.5 B5/.5 D6/1 G6/2")
A2_MEL = A_MEL.rsplit(';', 1)[0] + ";G6/1.5 F6/.5 D6/1 B5/1"
C_MEL = ("A5/.5 C6/.5 F6/1 A6/1 F6/1;B5/.5 D6/.5 G6/1 B6/1 G6/1;G5/.5 B5/.5 E6/1 G6/1 E6/1;"
         "A5/.5 C6/.5 E6/1 A6/1 E6/1;D6/1 D6/.5 F6/.5 A6/1 F6/1;G6/1 G6/.5 F6/.5 D6/1 B5/1;"
         "F6/1 E6/.5 F6/.5 G6/1 A6/1;B6/.5 A6/.5 G6/.5 F6/.5 D6/1 G6/1")
CH = {  # name: (bass root, fifth, triad)
    'C': (48, 55, (60, 64, 67)), 'Bb': (46, 53, (58, 62, 65)), 'F': (41, 48, (60, 65, 69)),
    'G': (43, 50, (62, 67, 71)), 'Am': (45, 52, (60, 64, 69)), 'Em': (40, 47, (59, 64, 67)),
    'Dm': (50, 57, (62, 65, 69)),
}
D_MEL = ("E5/.5 E5/.5 G5/1 E5/.5 D5/.5 C5/1;C5/.5 C5/.5 E5/1 C5/.5 B4/.5 A4/1;D5/.5 D5/.5 F5/1 A5/1 F5/1;"
         "G5/1 F5/.5 E5/.5 D5/2;E5/.5 G5/.5 C6/1 B5/.5 C6/.5 E6/1;F6/1 E6/.5 D6/.5 C6/1 A5/1;"
         "B5/.5 D6/.5 G6/1 F6/.5 D6/.5 B5/1;C6/2 r/2")
SECTIONS = [  # label, melody, chords, style[, harmony voice]. Ends on the build, whose G chord leads back into A.
    ('A', A_MEL, 'C Bb F G C Am Dm G', 'verse'),
    ('B', B_MEL, 'Am F C G Am F G G', 'bridge'),
    ("A'", A2_MEL, 'C Bb F G C Am Dm G', 'full'),
    ('C', C_MEL, 'F G Em Am Dm G F G', 'build'),
    ('D', D_MEL, 'C Am Dm G C F G C', 'courtyard'),
    ("B'", B_MEL, 'Am F C G Am F G G', 'bridge'),
    ("A''", A2_MEL, 'C Bb F G C Am Dm G', 'full', 'harm'),
    ("C'", C_MEL, 'F G Em Am Dm G F G', 'build'),
]
BARS = 8 * len(SECTIONS)
NAMES = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}

def midi(tok):
    m = re.fullmatch(r'([A-G])([b#]?)(\d)', tok)
    return 12 * (int(m[3]) + 1) + NAMES[m[1]] + {'b': -1, '#': 1, '': 0}[m[2]]

def parse(mel):
    """-> list of bars, each [(beat_in_bar, midi_or_None, dur)]"""
    bars = []
    for bar in mel.split(';'):
        b, out = 0.0, []
        for tok in bar.split():
            p, d = tok.split('/')
            out.append((b, None if p == 'r' else midi(p), float(d)))
            b += float(d)
        assert b == 4, bar
        bars.append(out)
    return bars

# ---------------------------------------------------------------- instruments (all return mono arrays)
hz = lambda m: 440 * 2 ** ((m - 69) / 12)

def env(n, a=0.004, dec=0.0, rel=0.03):
    """attack, optional exponential decay (1/s), release over the last `rel` seconds"""
    t = np.arange(n) / SR
    e = np.minimum(t / a, 1) * np.exp(-t * dec)
    r = int(rel * SR)
    e[-r:] *= np.linspace(1, 0, min(r, n))
    return e

def phase(f, n, vib=0.0):
    t = np.arange(n) / SR
    fr = f * (1 + vib * np.sin(2 * np.pi * 5.5 * t) * np.minimum(t / 0.25, 1))
    return np.cumsum(fr) / SR  # in cycles

def additive(f, n, weights, ph=None, vib=0.0, maxhz=9000):
    ph = phase(f, n, vib) if ph is None else ph
    return sum(w * np.sin(2 * np.pi * k * ph) for k, w in weights(int(maxhz / f)))

def pulse(f, dur, duty, vib=0.004, dec=0.0):
    n = int(dur * SR)
    ph = phase(f, n, vib)
    w = additive(f, n, lambda K: ((k, np.sin(np.pi * k * duty) / k) for k in range(1, K + 1)), ph - duty / 2 + 0.25)
    return w * env(n, dec=dec)

def tri(f, dur, dec=3.0):
    n = int(dur * SR)
    w = additive(f, n, lambda K: ((k, (-1) ** (k // 2) / k ** 2) for k in range(1, K + 1, 2)))
    return w * env(n, dec=dec) * 1.6

def saw(f, dur, bright=3500, a=0.02, rel=0.08, detune=(1.0,), vib=0.0):
    n = int(dur * SR)
    w = sum(additive(f * d, n, lambda K: ((k, 1 / k) for k in range(1, K + 1)), vib=vib, maxhz=bright) for d in detune)
    return w / len(detune) * env(n, a=a, rel=rel)

def pluck(f, dur):
    """harp/pizzicato: harmonics that die faster the higher they are"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    w = sum(np.sin(2 * np.pi * f * k * t) / k ** 1.5 * np.exp(-t * (5 + 4 * k)) for k in range(1, int(7000 / f) + 1))
    return w * env(n, a=0.002, rel=0.02) * 1.4

def flute(f, dur):
    n = int(dur * SR)
    w = additive(f, n, lambda K: ((1, 1), (2, .25), (3, .12)), vib=0.006)
    w += lp(noise(n), 3000) * 0.04            # breath
    return w * env(n, a=0.06, rel=0.08)

def bell(f, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    w = sum(g * np.sin(2 * np.pi * f * r * t) * np.exp(-t * d)
            for r, g, d in ((1, 1, 5), (2.76, .5, 9), (5.4, .25, 14), (8.93, .12, 22)))
    return w * env(n, a=0.001, rel=0.02)

hp = lambda x, fc: lfilter(*butter(2, fc / (SR / 2), 'high'), x)
lp = lambda x, fc: lfilter(*butter(2, fc / (SR / 2), 'low'), x)

def noise(n): return rng.standard_normal(n)

def kick():
    t = np.arange(int(0.28 * SR)) / SR
    return np.sin(2 * np.pi * np.cumsum(48 + 110 * np.exp(-t * 28)) / SR) * np.exp(-t * 12) * 1.1

def snare():
    t = np.arange(int(0.22 * SR)) / SR
    return (hp(noise(len(t)), 1500) * 0.55 + np.sin(2 * np.pi * 190 * t) * 0.5) * np.exp(-t * 20)

def hat(open_=False):
    t = np.arange(int((0.18 if open_ else 0.04) * SR)) / SR
    return hp(noise(len(t)), 7000) * np.exp(-t * (14 if open_ else 90)) * 0.22

def crash():
    t = np.arange(int(1.6 * SR)) / SR
    return hp(noise(len(t)), 4500) * np.exp(-t * 2.6) * 0.4

def timp(f):
    t = np.arange(int(0.9 * SR)) / SR
    return np.sin(2 * np.pi * np.cumsum(f * (1 + 0.25 * np.exp(-t * 18))) / SR) * np.exp(-t * 4.5)

# ---------------------------------------------------------------- mixer
N = int(BARS * 4 * SPB * SR)
TAIL = 3 * SR
dry = np.zeros((2, N + TAIL))
wet = np.zeros((2, N + TAIL))

def put(t_beat, sig, gain, pan=0.0, send=0.0):
    i = int(t_beat * SPB * SR)
    sig = sig[:N + TAIL - i]
    for ch, side in ((0, -1), (1, 1)):
        g = gain * np.sqrt(0.5 * (1 + side * pan))  # equal-power pan, pan in [-1, 1]
        dry[ch, i:i + len(sig)] += sig * g
        wet[ch, i:i + len(sig)] += sig * g * send

# ---------------------------------------------------------------- arrangement
lead_cache = {}
SCALE = [12 * o + d for o in range(2, 8) for d in (0, 2, 4, 5, 7, 9, 11)]  # C major, for the harmony voice
for s, (label, mel, chords, style, *opt) in enumerate(SECTIONS):
    harm = bool(opt)
    bars = parse(mel)
    chs = chords.split()
    full, build, bridge = style in ('full', 'build'), style == 'build', style == 'bridge'
    for b in range(8):
        base = (s * 8 + b) * 4
        root, fifth, triad = CH[chs[b]]
        last, mid = b == 7, b == 3

        # LEAD: warm detuned-saw "horn" + a harp-like pluck for the attack + a whisper of square for arcade flavour;
        # the bridge uses a flute; the "full" section adds a brass octave below; `harm` adds a diatonic third below
        for beat, m, d in bars[b]:
            if m is None:
                continue
            dur = d * SPB * 0.95
            if bridge:
                put(base + beat, flute(hz(m), dur), 0.2, 0, 0.3)
            else:
                put(base + beat, saw(hz(m), dur, 2400, a=0.015, detune=(0.996, 1.004), vib=0.004), 0.15, 0, 0.2)
                put(base + beat, pluck(hz(m), 0.5), 0.1, 0, 0.2)
                put(base + beat, pulse(hz(m), dur, 0.25), 0.035, 0, 0.1)
            if harm:
                i = max(j for j in range(len(SCALE)) if SCALE[j] <= m)
                put(base + beat, saw(hz(SCALE[i - 2]), dur, 2000, a=0.02, detune=(0.997, 1.003), vib=0.004), 0.08, -0.3, 0.2)
            if full:
                put(base + beat, saw(hz(m) / 2, dur, 3000, detune=(1.0, 1.006)), 0.07, -0.2, 0.2)
            if s != 0 or bridge or full:  # glockenspiel doubles the tune an octave up (not in the first verse)
                put(base + beat, bell(hz(m + 12), 0.6), 0.07, 0.35, 0.5)

        # STRINGS pad (warm, slow): bridge, full, build
        if bridge or full or style == 'courtyard':
            for m in triad:
                put(base, saw(hz(m - 12), 4 * SPB, 1800, a=0.25, rel=0.4, detune=(0.997, 1.003)), 0.045, 0, 0.6)

        # BRASS stabs (full + build)
        if full:
            for beat, d in ((0, 1.5), (2, .5), (3, 1)):
                for m in triad:
                    put(base + beat, saw(hz(m), d * SPB, 2600, a=0.03, rel=0.05), 0.05, 0.3, 0.25)

        # ARPEGGIO: harp 16ths in the second half of the first verse, the courtyard, and build/full
        if full or style == 'courtyard' or (s == 0 and b >= 4):
            for i in range(16):
                put(base + i / 4, pluck(hz(triad[[0, 1, 2, 1][i % 4]] + 12), SPB / 2), 0.1 if full else 0.075, -0.6, 0.3)

        # GLOCKENSPIEL sparkle on the off-beats (first verse only; later it doubles the tune)
        if s == 0:
            for i in range(4):
                put(base + i + 0.5, bell(hz(triad[[0, 1, 2, 1][i]] + 24), 0.5), 0.045, 0.5, 0.5)

        # BASS: march (verse), half notes (bridge), bouncing octaves (full/build)
        if bridge:
            put(base, tri(hz(root), 1.9 * SPB, 1.2), 0.5, 0)
            put(base + 2, tri(hz(fifth), 1.9 * SPB, 1.2), 0.45, 0)
        elif full:
            for i in range(8):
                put(base + i / 2, tri(hz(root + 12 * (i % 2) if i < 6 else (fifth, root + 12)[i % 2]), SPB * 0.45, 5), 0.42, 0)
        else:
            for i in range(4):
                put(base + i, tri(hz((root, fifth)[i % 2]), SPB * 0.9, 4), 0.5, 0)

        # DRUMS
        if bridge:
            put(base, timp(hz(root + 12)), 0.45, -0.2, 0.3)
            put(base + 2, timp(hz(fifth)), 0.3, 0.2, 0.3)
            for i in range(4):
                put(base + i, hat(), 0.5, 0.3)
        else:
            for k in ((0, 1, 2, 3) if build else (0, 2) + ((2.5,) if full else ())):
                put(base + k, kick(), 0.65)
            for k in (1, 3):
                put(base + k, snare(), 0.5, 0.05, 0.1)
            for i in range(8):
                put(base + i / 2, hat(), 0.5 if i % 2 else 0.8, 0.3)
        if last or (build and mid):  # fills: 16th snare roll, crescendo
            for i in range(8 if last else 4):
                put(base + 4 - (8 if last else 4) / 4 + i / 4, snare(), 0.25 + 0.05 * i, 0, 0.1)
        if b == 0 and not bridge and s in (0, 2, 6):
            put(base, crash(), 0.5, 0, 0.3)

# ---------------------------------------------------------------- reverb (stereo noise IR), loop-wrap, normalise, encode
ir = np.stack([noise(int(1.8 * SR)) * np.exp(-np.arange(int(1.8 * SR)) / SR * 2.6) for _ in range(2)])
ir = np.stack([lp(x, 6000) for x in ir]) * 0.02
mix = dry + np.stack([fftconvolve(wet[c], ir[c])[:N + TAIL] for c in (0, 1)])
loop = mix[:, :N].copy()
loop[:, :TAIL] += mix[:, N:N + TAIL]          # tail of the last bar rings into bar 1 -> seamless loop
loop = np.tanh(loop * 0.9) / np.tanh(0.9)     # gentle glue limiter
loop *= 0.89 / np.abs(loop).max()
os.makedirs(OUT, exist_ok=True)
assert np.isfinite(loop).all()
with sf.SoundFile(os.path.join(OUT, 'KingdomOfDice.ogg'), 'w', SR, 2, format='OGG', subtype='VORBIS') as f:
    for i in range(0, N, SR):  # chunked: one huge write overflows libsndfile's stack on this machine
        f.write(loop[:, i:i + SR].T.astype(np.float32))
print('ogg: %.1f s, peak %.2f, rms %.3f' % (N / SR, np.abs(loop).max(), np.sqrt((loop ** 2).mean())))

# ---------------------------------------------------------------- MusicXML (same data)
def spell(m):
    step, alt = {0: ('C', 0), 2: ('D', 0), 4: ('E', 0), 5: ('F', 0), 7: ('G', 0), 9: ('A', 0), 10: ('B', -1), 11: ('B', 0)}[m % 12]
    return step, alt, m // 12 - 1

TYPE = {1: ('eighth', 0), 2: ('quarter', 0), 3: ('quarter', 1), 4: ('half', 0), 6: ('half', 1), 8: ('whole', 0)}

def xnote(m, d, chord=False):
    ty, dot = TYPE[int(d * 2)]
    if m is None:
        pitch = '<rest/>'
    else:
        st, al, oc = spell(m)
        pitch = '<pitch><step>%s</step>%s<octave>%d</octave></pitch>' % (st, '<alter>%d</alter>' % al if al else '', oc)
    return '<note>%s%s<duration>%d</duration><type>%s</type>%s</note>' % (
        '<chord/>' if chord else '', pitch, int(d * 2), ty, '<dot/>' if dot else '')

def part(pid, name, clef, bars_fn, harmony=False):
    out = ['<part id="%s">' % pid]
    for n in range(BARS):
        s, b = divmod(n, 8)
        x = ['<measure number="%d">' % (n + 1)]
        if n == 0:
            x.append('<attributes><divisions>2</divisions><key><fifths>0</fifths></key><time><beats>4</beats>'
                     '<beat-type>4</beat-type></time><clef><sign>%s</sign><line>%d</line></clef></attributes>' % clef)
            if harmony:
                x.append('<direction placement="above"><direction-type><words>Brave march</words></direction-type>'
                         '<sound tempo="%d"/></direction>' % BPM)
        if harmony:
            if b == 0:
                x.append('<direction placement="above"><direction-type><rehearsal>%s</rehearsal></direction-type></direction>' % SECTIONS[s][0])
            c = SECTIONS[s][2].split()[b]
            x.append('<harmony><root><root-step>%s</root-step>%s</root><kind text="%s">%s</kind></harmony>' % (
                c[0], '<root-alter>-1</root-alter>' if c[1:2] == 'b' else '', 'm' if c.endswith('m') else '',
                'minor' if c.endswith('m') else 'major'))
        x.append(''.join(bars_fn(s, b)))
        out.append(''.join(x) + '</measure>')
    return ''.join(out) + '</part>'

def lead_bar(s, b):
    return [xnote(m, d) for _, m, d in parse(SECTIONS[s][1])[b]]

def strings_bar(s, b):
    tri_ = CH[SECTIONS[s][2].split()[b]][2]
    if SECTIONS[s][3] in ('verse',):
        return [xnote(None, 4)]  # first verse is lead + march + arps only
    return [xnote(m - 12, 4, i > 0) for i, m in enumerate(tri_)]

def bass_bar(s, b):
    root, fifth, _ = CH[SECTIONS[s][2].split()[b]]
    style = SECTIONS[s][3]
    if style == 'bridge':
        return [xnote(root, 2), xnote(fifth, 2)]
    if style in ('full', 'build'):
        return [xnote(m, .5) for m in [root + 12 * (i % 2) if i < 6 else (fifth, root + 12)[i % 2] for i in range(8)]]
    return [xnote((root, fifth)[i % 2], 1) for i in range(4)]

xml = ('<?xml version="1.0" encoding="UTF-8"?><score-partwise version="3.1"><work><work-title>Kingdom of Dice</work-title></work>'
       '<part-list><score-part id="P1"><part-name>Lead (square) + Glockenspiel</part-name></score-part>'
       '<score-part id="P2"><part-name>Strings / Brass chords</part-name></score-part>'
       '<score-part id="P3"><part-name>Bass</part-name></score-part></part-list>'
       + part('P1', 'Lead', ('G', 2), lead_bar, True)
       + part('P2', 'Strings', ('G', 2), strings_bar)
       + part('P3', 'Bass', ('F', 4), bass_bar) + '</score-partwise>')
os.makedirs(SCORE_DIR, exist_ok=True)
with open(os.path.join(SCORE_DIR, 'KingdomOfDice.musicxml'), 'w', encoding='utf-8') as f:
    f.write(xml)
print('musicxml written')
