"""Original dice knocks, v2 (heat-map matched): mid plateau + bright opening burst + light weight + micro-bounces.
Run: python make_dice_hits.py   (writes DiceHits/*.wav)"""
import wave, numpy as np
SR = 192000   # internal synthesis rate: 4x oversampled so saturation/noise cannot alias
OUT = 48000   # delivered rate
THUMP, SNAP, SAT = 0.0, 0.2, 0.01
CRISP, LOWTRIM = 1.6, 6.0   # attack sharpness; fit-target cut (dB) at 150-420 Hz
STRIPE_TAU = 0.001   # contact-stripe decay time constant (s)
STRIPE_LO = 180   # contact-stripe low edge (Hz)
STRIPE_T0, STRIPE_HOLD = 0.0035, 0.004   # contact-stripe start delay and hold (s)
MID_RISE, SOFT = 0.003, (0.0, 0.0)   # body build-up time (s); softening (dB) of the fit target above 3 kHz / 6 kHz
STRIPE, MID_RATE, CAP_LOW = 1.0, (100, 160), [10, 3, 0]   # contact-stripe level, mid-mode decay rates, fit boost allowance below 700 Hz
CAP_LO, CAP_HI = [18, 18, 0], [12, 8, 2]   # fit boost allowance (dB) at 0/12/30 ms and for >2.8 kHz at 0/12/25 ms
SPK_RATE, SPK_AMP = (70, 130), (-20, -10)   # sparkle decay rates (1/s) and level range (dB)        # weight (kept light), snap, saturation
BOUNCES = [(0.024, 0.14), (0.046, 0.20)]   # (delay s, level): the die chattering = the "grab"

EQ_DB = np.zeros(12)   # tuned in __main__ against the reference's first-40 ms band profile
EQ_C = np.array([75, 225, 450, 800, 1250, 1850, 2700, 3850, 5500, 7700, 11000, 18000])
EDGES = [0, 150, 300, 600, 1000, 1500, 2200, 3200, 4500, 6500, 9000, 13000, 24000]
TARGET = np.array([-16.6, -10.3, -5.9, -2.8, -4.2, -9.7, -7.2, -14.9, -16.4, -18.1, -21.4, -31.2])   # presence nudged up for clarity

def eq(y):
    n = len(y); X = np.concatenate([y, np.zeros(n)]); f = np.fft.rfftfreq(2*n, 1/SR)
    g = 10**(np.interp(np.log(np.maximum(f, 20)), np.log(EQ_C), EQ_DB)/20)
    return np.fft.irfft(np.fft.rfft(X)*g, 2*n)[:n]

def profile(x):
    o = np.argmax(np.abs(x) > 0.1*np.abs(x).max()); seg = x[o:o+int(.04*OUT)]
    F = np.abs(np.fft.rfft(seg*np.hanning(len(seg)), 16384))**2; f = np.fft.rfftfreq(16384, 1/OUT)
    v = np.array([F[(f >= a) & (f < b)].sum() for a, b in zip(EDGES, EDGES[1:])]); return 10*np.log10(v/v.max()+1e-12)

def bp(x, lo, hi, order=4):
    N = len(x); X = np.concatenate([x, np.zeros(N)]); F = np.fft.rfft(X); f = np.fft.rfftfreq(2*N, 1/SR)
    F *= (1/(1+(lo/np.maximum(f, 1))**order)) * (1/(1+(f/hi)**order)); return np.fft.irfft(F, 2*N)[:N]

def contact(r, centre, n, small=False):
    """One strike: dense mid modes (plateau), light low modes, sparkle cloud, opening burst."""
    t = np.arange(n)/SR; y = np.zeros(n)
    k = 12 if small else 64
    for f in np.exp(r.uniform(np.log(700), np.log(1900), k)):                   # mid plateau 650-2100 Hz
        a = 10**(-16/20) + (1-10**(-16/20))*np.exp(-0.5*(np.log(f/centre)/0.2)**2)
        y += a*10**(r.uniform(-3, 0)/20)*np.cos(2*np.pi*f*t + r.uniform(0, 6.28))*np.exp(-t*r.uniform(*MID_RATE)*(2.0 if small else 1))*(1-np.exp(-t/MID_RISE) if MID_RISE > 0 else 1)   # tau 4-7 ms
    for f in np.exp(r.uniform(np.log(180), np.log(620), 14)):                   # light low modes
        y += 10**(r.uniform(-42, -34)/20)*np.cos(2*np.pi*f*t + r.uniform(0, 6.28))*np.exp(-t*r.uniform(160, 240))
    for f in np.exp(r.uniform(np.log(2300), np.log(9500), 30)):                 # sparkle
        y += 10**(r.uniform(*SPK_AMP)/20)*np.cos(2*np.pi*f*t + r.uniform(0, 6.28))*np.exp(-t*r.uniform(*SPK_RATE))
    st = bp(r.standard_normal(n), STRIPE_LO, 3500)                                    # contact stripe: broadband ~5 ms hold (the 'body' of the strike)
    y += STRIPE*(0.5 if small else 1.0)*st/np.abs(st).max()*(1-np.exp(-np.maximum(t-STRIPE_T0, 0)/0.0007))*(t >= STRIPE_T0)*np.exp(-np.maximum(t-STRIPE_T0-STRIPE_HOLD, 0)/STRIPE_TAU)*np.abs(y).max()
    nb = bp(r.standard_normal(n), 2000, 3800)                                   # opening burst 2-3.5 kHz
    y += (0.5 if small else 1.0)*1.3*nb/np.abs(nb).max()*np.exp(-t/0.0035)*np.abs(y).max()
    tk = bp(r.standard_normal(n), 4500, 9500)                                   # high speckle tick
    y += 0.16*tk/np.abs(tk).max()*np.exp(-t/0.004)*np.abs(y).max()
    pl = int(SR*0.0005); pulse = np.sin(np.pi*np.arange(pl)/pl)
    return np.convolve(y, pulse/pulse.sum())[:n]

def hit(seed, centre=1100.0, dur=0.12):
    r = np.random.default_rng(seed); n = int(SR*dur); t = np.arange(n)/SR
    y = contact(r, centre, n)
    for dly, lv in BOUNCES:                                                    # micro-bounces, each a smaller re-strike
        d = int((dly*r.uniform(0.9, 1.12))*SR); c = contact(r, centre*r.uniform(0.9, 1.15), n-d, small=True)
        y[d:] += lv*np.abs(y[:int(.01*SR)]).max()*c/np.abs(c).max()
    pk = np.abs(y).max()
    ph = 2*np.pi*np.cumsum(120 + 70*np.exp(-t/0.010))/SR                       # light weight
    y += THUMP*pk*np.tanh(2.5*np.sin(ph))*np.exp(-t/0.014)
    y *= 1 + SNAP*np.exp(-t/0.003)
    pk = np.abs(y).max(); y = np.tanh(SAT*y/pk)/np.tanh(SAT)*pk
    y = eq(y)
    y *= np.minimum(1, (dur-t)*60)
    F = np.fft.rfft(y); f = np.fft.rfftfreq(len(y), 1/SR); F *= 1/(1+(f/12000)**6)    # smooth anti-alias + top end
    y = np.fft.irfft(F, len(y))[::SR//OUT]
    return y/np.abs(y).max()


# ---- heat-map matching: nudge MY hits toward the reference's average time-frequency energy (fine structure stays mine)
REF_PATH = r'C:/Users/asus/Downloads/RandomDiceSample.wav'
REF_HITS = [0.46, 0.825, 1.185, 1.465, 2.155]          # isolated hits in the reference
WIN, HOP, NF = 512, 128, 14                              # ~10.7 ms window, ~2.7 ms hop, 14 frames = ~37 ms+...
NFR = 26                                                 # frames matched (~70 ms); later frames are left alone

def onset(x):
    thr = 0.15*np.abs(x[:int(.03*OUT)]).max(); return int(np.argmax(np.abs(x) > thr))

def stft(x):
    w = np.hanning(WIN); x = np.concatenate([x, np.zeros(WIN*2)])
    return np.array([np.fft.rfft(x[i:i+WIN]*w) for i in range(0, len(x)-WIN, HOP)])

def istft(S, n):
    w = np.hanning(WIN); y = np.zeros(len(S)*HOP + WIN); ws = np.zeros_like(y)
    for k, fr in enumerate(S):
        y[k*HOP:k*HOP+WIN] += np.fft.irfft(fr)*w; ws[k*HOP:k*HOP+WIN] += w*w
    return (y/np.maximum(ws, 1e-6))[:n]

LEAD = 96
def aligned(x):
    o = onset(x); return (x[o-LEAD:] if o >= LEAD else np.pad(x, (LEAD-o, 0))), max(0, LEAD-o)

def avg_power(sigs):
    P = 0
    for x in sigs:
        seg = aligned(x)[0][:int(.12*OUT)]; seg = np.pad(seg, (0, max(0, int(.12*OUT)-len(seg))))
        S = np.abs(stft(seg))[:NFR]; P = P + S**2
    return P/len(sigs)

def smooth(P):
    k = np.hanning(7); k /= k.sum(); P = np.apply_along_axis(lambda v: np.convolve(v, k, 'same'), 1, P)   # along frequency
    return np.apply_along_axis(lambda v: np.convolve(v, [1/9, 2/9, 3/9, 2/9, 1/9], 'same'), 0, P)                    # along time

def apply_mask(x, G):
    xa, lead = aligned(x); PADF = WIN                                       # pad so the first samples are not divided by ~0
    x2 = np.concatenate([np.zeros(PADF), xa, np.zeros(WIN)]); S = stft(x2); n = len(S)
    tail = np.linspace(1, 0, 8)[:, None]*(G[-1]-1) + 1                       # ease back to unity gain after the matched window
    gm = np.vstack([np.ones((PADF//HOP, G.shape[1])), G, tail, np.ones((max(0, n-PADF//HOP-len(G)-8), G.shape[1]))])[:n]
    y2 = istft(S*gm, len(x2))[PADF:PADF+len(xa)]
    return y2[lead:lead+len(x)] if lead else (np.pad(y2, (len(x)-len(y2), 0)) if len(y2) < len(x) else y2)

def match(sigs, iters=5):
    import os
    if not os.path.exists(REF_PATH): print('reference not found, skipping match'); return sigs
    w = wave.open(REF_PATH); ref = np.frombuffer(w.readframes(w.getnframes()), '<i2')/32768.
    R = smooth(avg_power([ref[int(o*OUT)-480:int(o*OUT)+int(.2*OUT)] for o in REF_HITS]))
    fq = np.fft.rfftfreq(WIN, 1/OUT)
    R[:, fq > 3000] *= 10**(-SOFT[0]/10); R[:, fq > 6000] *= 10**(-SOFT[1]/10)   # aim a little softer above 3 / 6 kHz
    R[:, (fq > 150) & (fq < 420)] *= 10**(-LOWTRIM/10)                               # less low-mid roundness
    tms = np.arange(R.shape[0])*HOP/OUT*1000
    cap_lo = np.interp(tms, [0, 12, 30], CAP_LO); cap_hi = np.interp(tms, [0, 12, 25], CAP_HI); cap_low = np.interp(tms, [0, 12, 30], CAP_LOW)
    cap = np.where(fq[None, :] > 2800, cap_hi[:, None], np.where(fq[None, :] < 700, cap_low[:, None], cap_lo[:, None]))
    top = 10**(cap/20); floor = 10**(-24/20)
    G = np.ones_like(R); orig = sigs                                           # cumulative gain, always applied to the ORIGINAL signals
    for _ in range(iters):
        cur = [y/np.abs(y).max() for y in [apply_mask(x, G) for x in orig]]
        M = smooth(avg_power(cur)); hi = fq > 600; M *= R[:, hi].sum()/M[:, hi].sum()   # level-match on mids+highs so excess lows get cut, not accepted
        G = np.minimum(np.maximum(G*np.sqrt(R/(M+1e-12))**0.8, floor), top)    # damped update, total gain capped (no stacking)
        G[:, fq < 200] = np.minimum(G[:, fq < 200], 1.0); G[:, fq < 90] = 0   # never boost the sub/low bins; remove DC / sub-bass
    return [y/np.abs(y).max() for y in [apply_mask(x, G) for x in orig]]

def save(name, y, peak=0.5):
    import soundfile as sf
    y = y/np.abs(y).max()*peak
    sf.write(f'DiceHits/{name}.ogg', y.astype('float32'), OUT, format='OGG', subtype='VORBIS')

def build(verbose=True):
    global EQ_DB
    EQ_DB = np.zeros(12)
    SEEDS = list(zip([31, 32, 33, 34], [1000, 1120, 1250, 920]))
    for _ in range(14):                                   # match the reference's average spectrum
        P = np.mean([profile(hit(a, c)) for a, c in SEEDS], 0)
        err = TARGET - P; err[:3] = 0; err[3:] -= err[3:].mean()   # EQ leaves <600 Hz to the model
        EQ_DB = np.clip(EQ_DB + 0.8*err, -10, 20); EQ_DB[3:] -= EQ_DB[3:].mean(); EQ_DB[:3] = [-24, -3, 0]   # high-pass the sub-150 boom
    if verbose: print('EQ dB:', np.round(EQ_DB, 1)); print('final band diff vs ref:', np.round(np.mean([profile(hit(a, c)) for a, c in SEEDS], 0) - TARGET, 1))
    singles = match([hit(a, c) for a, c in SEEDS])
    tt = np.arange(len(singles[0]))/OUT                                                   # no ring-out: gate the tail after 55 ms
    singles = [y*np.exp(-np.maximum(tt-0.055, 0)/0.012) for y in singles]
    def crisp(y, amt=None):
        amt = CRISP if amt is None else amt                                                                  # edge: add a bright copy of the first ~2 ms
        F = np.fft.rfft(y); f = np.fft.rfftfreq(len(y), 1/OUT); hp = np.fft.irfft(F*(f > 2200)/(1+(f/9000)**4), len(y))
        return y + amt*hp*np.exp(-tt/0.0022)
    singles = [crisp(y) for y in singles]
    def share(y):                                                                          # fraction of energy at 150-500 Hz in the first 70 ms
        F = np.abs(np.fft.rfft(y[:int(.07*OUT)]))**2; f = np.fft.rfftfreq(int(.07*OUT), 1/OUT); return F[(f > 150) & (f < 500)].sum()/F.sum()
    def balance(y, target=0.13):                                                            # pull every variant's low-mid share to the reference's (~13%)
        for _ in range(3):
            sh = share(y); gdb = float(np.clip(10*np.log10((target/(1-target))/(sh/(1-sh))), -12, 9))
            f = np.fft.rfftfreq(len(y), 1/OUT); bell = np.exp(-0.5*(np.log(np.maximum(f, 1)/270)/0.55)**2)
            y = np.fft.irfft(np.fft.rfft(y)*10**(gdb*bell/20), len(y))
        return y
    singles = [balance(y) for y in singles]
    return singles, SEEDS


if __name__ == '__main__':
    singles, SEEDS = build()
    for i, s in enumerate(singles, 1): save(f'dice_hit_{i}', s)
    rng = np.random.default_rng(3); rat = np.zeros(int(OUT*1.6)); t0 = 0.0
    for k, g in enumerate([0, .11, .09, .17, .08, .13, .22, .10, .28]):
        t0 += g; s = int(t0*OUT); snd = singles[(k*3+1) % 4]*rng.uniform(0.7, 1.0)*(1-0.04*k)
        rat[s:s+len(snd)] += snd[:len(rat)-s]
    save('dice_rattle', rat); print('done')
