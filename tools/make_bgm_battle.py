"""Compose and render "Dice Battle", the battle BGM loop (D minor, 4/4, ~5 minutes: three climaxes, several lulls, ritardandos and accelerandos).
The darker sibling of make_bgm.py: minor key, galloping string ostinato, taiko/toms, brass stabs, a tolling bell
in the break. No glockenspiel, harp or arcade square lead.

One score (the tables below) drives both outputs, so the sheet music and the audio can never disagree:
  Assets/Music/DiceBattle.ogg   - layered synth voices + reverb, loop-safe (reverb tail wraps onto bar 1)
  docs/music/DiceBattle.musicxml - Lead / Strings / Bass parts + chord symbols (open in MuseScore, Flat, Finale...)

Usage: python tools/make_bgm_battle.py [out_dir]   Needs numpy, scipy, soundfile.
"""
import os
import re
import sys

import numpy as np
import soundfile as sf
from scipy.signal import butter, oaconvolve, lfilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'Assets', 'Music')
SCORE_DIR = os.path.join(ROOT, 'docs', 'music')
SR = 44100
SPB, T0 = 0.0, 0.0                  # seconds per beat / start of the current bar; both set bar by bar (tempo changes)
rng = np.random.default_rng(11)

# ---------------------------------------------------------------- the score
# Melody tokens: "pitch/beats" ("r" = rest). 8-bar sections; harmony is one chord per bar.
M1 = ("D5/1.5 D5/.5 F5/1 E5/.5 D5/.5;A5/1.5 F5/.5 D5/2;Bb5/1.5 A5/.5 F5/1 D5/1;E5/1.5 G5/.5 C6/2;"
      "D5/1.5 D5/.5 F5/1 A5/1;D6/1.5 C6/.5 A5/1 F5/1;G5/1 Bb5/1 D6/1.5 C6/.5;C#6/1 E6/1 A5/1 C#6/1")
M2 = ("D6/1.5 D6/.5 F6/1 D6/1;E6/1.5 E6/.5 G6/1 E6/1;F6/1.5 F6/.5 A6/1 F6/1;A6/1 G6/1 F6/1 C6/1;"
      "D6/1 F6/1 Bb6/1.5 A6/.5;G6/1 E6/1 C6/1.5 E6/.5;A6/1 G6/.5 F6/.5 E6/1 C#6/1;E6/.5 C#6/.5 A5/1 r/.5 A5/.5 A5/1")
M3 = ("G5/2 Bb5/2;A5/1 G5/1 D5/2;F5/2 A5/2;D6/3 r/1;Bb5/2 D6/2;C6/1 Bb5/1 F5/2;A5/1.5 C#6/.5 E6/2;E6/3 r/1")
M4 = ("A5/.5 A5/.5 D6/1 F6/1 A6/1;Bb6/1 A6/.5 F6/.5 D6/2;G6/.5 G6/.5 E6/1 C6/1 E6/1;E6/1 C#6/1 A5/1 E6/1;"
      "D6/.5 F6/.5 A6/1 D7/2;Bb6/1 A6/1 F6/1 D6/1;G6/1 Bb6/1 D7/1 Bb6/1;E6/.5 E6/.5 C#6/.5 E6/.5 A6/2")
CH = {  # name: (bass root, fifth, triad)
    'Dm': (50, 57, (62, 65, 69)), 'Bb': (46, 53, (58, 62, 65)), 'C': (48, 55, (60, 64, 67)),
    'Gm': (43, 50, (58, 62, 67)), 'A': (45, 52, (61, 64, 69)), 'F': (41, 48, (60, 65, 69)),
}
C1, C2, C3, C4 = 'Dm Dm Bb C Dm Dm Gm A', 'Bb C Dm F Bb C A A', 'Gm Gm Dm Dm Bb Bb A A', 'Dm Bb C A Dm Bb Gm A'
M5 = "A5/2 F5/1 A5/1;D6/2 Bb5/2;G5/1.5 Bb5/.5 D6/2;C#6/2 E6/2;F6/2 D6/1 A5/1;A5/2 C6/2;E6/1.5 D6/.5 C6/2;A5/2 C#6/2"
C5 = 'Dm Bb Gm A Dm F C A'
SECTIONS = [  # label, melody, chords, style, harmony voice, bpm at start, bpm at end (linear ramp across the 8 bars)
    ('A', M1, C1, 'verse', 0, 138, 138),
    ('B', M2, C2, 'rise', 0, 138, 146),
    ('A2', M1, C1, 'full', 0, 146, 146),               # climax 1 (small)
    ('Break', M3, C3, 'bridge', 0, 146, 104),          # slow down
    ('Lull', M5, C5, 'bridge', 0, 96, 96),             # low 1
    ('Break2', M3, C3, 'bridge', 0, 92, 110),          # creeping up
    ('B2', M2, C2, 'rise', 0, 110, 140),               # speed up
    ('C', M4, C4, 'full', 1, 140, 150),                # climax 2
    ('A3', M1, C1, 'full', 1, 150, 150),
    ('Drop', M3, C3, 'bridge', 0, 150, 84),            # big slow down
    ('Doom', M1, C1, 'verse', 1, 88, 88),              # low 2: heavy half-time march
    ('B3', M2, C2, 'rise', 1, 88, 120),                # speed up
    ('C2', M4, C4, 'full', 1, 120, 156),               # climax 3 begins, accelerating
    ('B4', M2, C2, 'full', 1, 156, 156),
    ('A4', M1, C1, 'full', 1, 156, 156),               # peak
    ('Fall', M5, C5, 'bridge', 0, 156, 90),            # slow down
    ('Lull2', M5, C5, 'bridge', 0, 90, 90),            # low 3
    ('B5', M2, C2, 'rise', 1, 90, 150),                # speed up
    ('C3', M4, C4, 'full', 1, 152, 152),               # final climax
    ('Charge', M4, C4, 'build', 1, 152, 152),          # snare rolls; the A chord leads back into Dm at the top
]
BAR_BPM = [b0 + (b1 - b0) * i / 8 for _, _, _, _, _, b0, b1 in SECTIONS for i in range(8)]
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
            out.append((b, None if p == 'r' else midi(p) - 12, float(d)))  # whole tune sits an octave low: dark and heavy
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
    """big war-drum snare: pitch-dropping shell, band-limited wires with a snap and a short tail (no thin hiss)"""
    t = np.arange(int(0.34 * SR)) / SR
    shell = np.sin(2 * np.pi * np.cumsum(165 * (1 + 0.6 * np.exp(-t * 45))) / SR) * np.exp(-t * 16)
    wires = hp(lp(noise(len(t)), 6500), 1100) * (0.65 * np.exp(-t * 11) + 0.35 * np.exp(-t * 38))
    return shell * 0.75 + wires * 0.7

def hat(open_=False):
    t = np.arange(int((0.18 if open_ else 0.04) * SR)) / SR
    return hp(noise(len(t)), 7000) * np.exp(-t * (14 if open_ else 90)) * 0.14

def crash():
    t = np.arange(int(1.6 * SR)) / SR
    return hp(noise(len(t)), 4500) * np.exp(-t * 2.6) * 0.4

def timp(f):
    t = np.arange(int(0.9 * SR)) / SR
    return np.sin(2 * np.pi * np.cumsum(f * (1 + 0.25 * np.exp(-t * 18))) / SR) * np.exp(-t * 4.5)

# ---------------------------------------------------------------- mixer
N = int(sum(240 / x for x in BAR_BPM) * SR)
TAIL = 3 * SR
dry = np.zeros((2, N + TAIL))
wet = np.zeros((2, N + TAIL))

def put(t_beat, sig, gain, pan=0.0, send=0.0):
    i = int((T0 + t_beat * SPB) * SR)
    sig = sig[:N + TAIL - i]
    for ch, side in ((0, -1), (1, 1)):
        g = gain * np.sqrt(0.5 * (1 + side * pan))  # equal-power pan, pan in [-1, 1]
        dry[ch, i:i + len(sig)] += sig * g
        wet[ch, i:i + len(sig)] += sig * g * send

# ---------------------------------------------------------------- arrangement
SCALE = [12 * o + d for o in range(2, 8) for d in (0, 2, 4, 5, 7, 9, 11)]  # D natural minor shares C major's notes
# sub (tri) + growl (saw) + an octave-up layer with a sharp attack, so the bass is audible on phone speakers too
growl = lambda f, dur: tri(f, dur, 3) + saw(f, dur, 900, a=0.003, rel=0.03) * 0.6 + saw(f * 2, dur, 1600, a=0.002, rel=0.03) * 0.5
for s, (label, mel, chords, style, harm, *_) in enumerate(SECTIONS):
    bars = parse(mel)
    chs = chords.split()
    full, build, bridge, rise = style in ('full', 'build'), style == 'build', style == 'bridge', style == 'rise'
    for b in range(8):
        SPB = 60 / BAR_BPM[s * 8 + b]
        base = 0  # beats are local to the bar; T0 carries the time
        root, fifth, triad = CH[chs[b]]
        last, mid = b == 7, b == 3

        # LEAD: brass-like detuned saws (flute in the break); "full" adds a brass octave below, `harm` a third below
        for beat, m, d in bars[b]:
            if m is None:
                continue
            dur = d * SPB * 0.95
            if bridge:
                put(base + beat, flute(hz(m), dur), 0.2, 0, 0.35)
            else:
                put(base + beat, saw(hz(m), dur, 1800, a=0.025, detune=(0.996, 1.004), vib=0.004), 0.17, 0, 0.2)
            if harm:
                i = max(j for j in range(len(SCALE)) if SCALE[j] <= m)
                put(base + beat, saw(hz(SCALE[i - 2]), dur, 2000, a=0.02, detune=(0.997, 1.003), vib=0.004), 0.09, -0.3, 0.2)
            if full:
                put(base + beat, saw(hz(m) / 2, dur, 1600, detune=(1.0, 1.006)), 0.1, -0.2, 0.2)

        # STRINGS pad (dark, slow): break, rise, full
        if bridge or rise or full:
            for m in triad:
                put(base, saw(hz(m - 24), 4 * SPB, 1100, a=0.25, rel=0.4, detune=(0.997, 1.003)), 0.05, 0, 0.6)

        # BRASS stabs on the full sections
        if full and not build:
            for beat, d in ((0, 1.5), (2, .5), (3, 1)):
                for m in triad:
                    put(base + beat, saw(hz(m - 12), d * SPB, 1500, a=0.012, rel=0.05), 0.055, 0.3, 0.25)

        # GALLOPING OSTINATO: short low strings on the root (8ths; 16ths in full/build); silent in the break
        if not bridge:
            steps = 16 if full else 8
            for i in range(steps):
                acc = (1.0, .55, .8, .55)[i % 4] if full else (1.0, .6)[i % 2]
                put(base + i * 4 / steps, saw(hz(root), 4 / steps * SPB * 0.8, 1000, a=0.004, rel=0.02, detune=(0.997, 1.003)),
                    (0.09 if full else 0.075) * acc, -0.3, 0.15)

        # TOLLING BELL under the break, every other bar
        if bridge and b % 2 == 0:
            put(base, bell(hz(root - 12), 3.5), 0.14, 0, 0.6)

        # BASS: half notes in the break, growling 8ths everywhere else
        if bridge:
            put(base, growl(hz(root - 12), 3.8 * SPB), 0.47, 0)
        else:
            for i in range(8):
                put(base + i / 2, growl(hz(root - 12), SPB * 0.45), 0.5 if i % 2 == 0 else 0.37, 0)

        # DRUMS: taiko (low timpani) and toms carry it; snare/kick only where the energy is up
        if bridge:
            put(base, timp(hz(root - 12)), 0.55, 0, 0.3)
            put(base + 0.5, timp(hz(root - 12)), 0.3, 0, 0.3)
        elif style == 'verse':
            put(base, kick(), 0.6)
            for k, g in ((0, .6), (2.5, .5)):
                put(base + k, timp(hz(38)), g, -0.1, 0.25)
            put(base + 3, snare(), 0.35, 0.05, 0.1)
            put(base + 3.5, timp(hz(55)), 0.3, 0.3, 0.2)
        elif rise:
            for k in (0, 2, 3.5):
                put(base + k, kick(), 0.6)
            for k, g in ((0, .55), (1.5, .45)):
                put(base + k, timp(hz(38)), g, -0.1, 0.25)
            for k in (1, 3):
                put(base + k, snare(), 0.45, 0.05, 0.1)
        else:
            for k in ((0, 1, 2, 3) if build else (0, 1, 1.5, 2.5, 3)):
                put(base + k, kick(), 0.65)
            for k in (0, 2):
                put(base + k, timp(hz(38)), 0.5, -0.1, 0.25)
            for k in (1, 3):
                put(base + k, snare(), 0.55, 0.05, 0.1)
            for i in range(8):
                put(base + i / 2, hat(), 0.5 if i % 2 else 0.8, 0.3)
        if last or (build and mid):  # fills: 16th snare roll, crescendo
            for i in range(8 if last else 4):
                put(base + 4 - (8 if last else 4) / 4 + i / 4, snare(), 0.25 + 0.05 * i, 0, 0.1)
        if b == 0 and (full or s == 0):
            put(base, crash(), 0.5, 0, 0.3)
        T0 += 4 * SPB

# ---------------------------------------------------------------- reverb (stereo noise IR), loop-wrap, normalise, encode
ir = np.stack([noise(int(1.8 * SR)) * np.exp(-np.arange(int(1.8 * SR)) / SR * 2.6) for _ in range(2)])
ir = np.stack([lp(x, 4000) for x in ir]) * 0.02
mix = dry + np.stack([oaconvolve(wet[c], ir[c])[:N + TAIL] for c in (0, 1)])
loop = mix[:, :N].copy()
loop[:, :TAIL] += mix[:, N:N + TAIL]          # tail of the last bar rings into bar 1 -> seamless loop
loop = np.tanh(loop * 0.9) / np.tanh(0.9)     # gentle glue limiter
loop *= 0.8 / np.abs(loop).max()
os.makedirs(OUT, exist_ok=True)
assert np.isfinite(loop).all()
with sf.SoundFile(os.path.join(OUT, 'DiceBattle.ogg'), 'w', SR, 2, format='OGG', subtype='VORBIS') as f:
    for i in range(0, N, SR):  # chunked: one huge write overflows libsndfile's stack on this machine
        f.write(loop[:, i:i + SR].T.astype(np.float32))
print('ogg: %.1f s, peak %.2f, rms %.3f' % (N / SR, np.abs(loop).max(), np.sqrt((loop ** 2).mean())))

# ---------------------------------------------------------------- MusicXML (same data)
def spell(m):
    step, alt = {0: ('C', 0), 1: ('C', 1), 2: ('D', 0), 4: ('E', 0), 5: ('F', 0), 7: ('G', 0), 9: ('A', 0), 10: ('B', -1), 11: ('B', 0)}[m % 12]
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
                x.append('<direction placement="above"><direction-type><words>Relentless march</words></direction-type>'
                         '</direction>')
        if harmony:
            if b == 0:
                x.append('<direction placement="above"><direction-type><rehearsal>%s</rehearsal></direction-type><sound tempo="%d"/></direction>' % (SECTIONS[s][0], SECTIONS[s][5]))
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
        return [xnote(None, 4)]  # first verse is lead + ostinato only
    return [xnote(m - 24, 4, i > 0) for i, m in enumerate(tri_)]

def bass_bar(s, b):
    root = CH[SECTIONS[s][2].split()[b]][0] - 12
    return [xnote(root, 4 if SECTIONS[s][3] == 'bridge' else .5) for _ in range(1 if SECTIONS[s][3] == 'bridge' else 8)]

xml = ('<?xml version="1.0" encoding="UTF-8"?><score-partwise version="3.1"><work><work-title>Dice Battle</work-title></work>'
       '<part-list><score-part id="P1"><part-name>Lead (brass / flute)</part-name></score-part>'
       '<score-part id="P2"><part-name>Strings / Brass chords</part-name></score-part>'
       '<score-part id="P3"><part-name>Bass</part-name></score-part></part-list>'
       + part('P1', 'Lead', ('G', 2), lead_bar, True)
       + part('P2', 'Strings', ('G', 2), strings_bar)
       + part('P3', 'Bass', ('F', 4), bass_bar) + '</score-partwise>')
os.makedirs(SCORE_DIR, exist_ok=True)
with open(os.path.join(SCORE_DIR, 'DiceBattle.musicxml'), 'w', encoding='utf-8') as f:
    f.write(xml)
print('musicxml written')
