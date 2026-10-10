#!/usr/bin/env python3
"""Soundtrack and sound effects for "Talkify - now for Omarchy" (30 s film).

Everything is synthesised here, no samples. 100 BPM, 4/4, D major / B minor.
The film cuts on the bar grid (beat 0.6 s, bar 2.4 s), so every event below
is placed with `at(bar, step)` and lands on an exact sample.

    python3 video/audio/compose.py [out_dir]     # default: video/public/sounds

Needs numpy, scipy and soundfile (pip install numpy scipy soundfile). Writes
music.wav (30.000 s, -16 LUFS integrated, true peak under -1 dBTP), key.wav,
whoosh.wav and glow.wav as 48 kHz 24-bit stereo, then prints the checks:
loudness, true peak, RMS and loudness per bar, kick and accent onset times,
octave-band spectrum, stereo correlation and a click scan of the tonal stems.
Rendering is deterministic (fixed seeds), so a re-run gives the same files.
"""

import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal
from scipy.ndimage import maximum_filter1d, minimum_filter1d

SR = 48000
BEAT = 0.6
BAR = 4 * BEAT
STEP = BEAT / 4
DUR = 30.0
N = int(round(DUR * SR))
BUF = N + 2 * SR

TARGET_LUFS = -16.0
CEILING_DBTP = -1.3
SFX_PEAK_DB = -12.0

# Chords: pad voicing (voice-led), warm body note, bass root, arp ladder.
CHORDS = {
    "Gmaj9": ([55, 59, 62, 66, 69], 43, 31, [71, 74, 78, 81, 83]),
    "A6sus2": ([57, 64, 66, 69, 71], 45, 33, [71, 76, 78, 81, 83]),
    "Dmaj9": ([57, 61, 64, 66, 69], 50, 38, [74, 76, 78, 81, 85]),
    "Bm11": ([57, 62, 64, 66, 69], 47, 35, [74, 76, 78, 81, 83]),
    "Gmaj7#11": ([59, 62, 66, 69, 73], 43, 31, [71, 74, 78, 81, 85]),
    "A6/9": ([61, 64, 66, 69, 71], 45, 33, [73, 76, 78, 81, 83]),
    "Bm11/A": ([57, 62, 66, 69, 71], 45, 33, [74, 78, 81, 83, 86]),
    "Asus2": ([59, 64, 69, 71, 76], 45, 33, [71, 76, 81, 83, 88]),
    "Dmaj9+": ([57, 61, 64, 66, 69, 73, 76], 50, 38, [74, 76, 78, 81, 85]),
    "Gmaj13#11": ([59, 62, 66, 69, 73, 76], 43, 31, [71, 74, 78, 81, 85]),
    "Gm6/9": ([58, 62, 64, 69, 76], 43, 31, [74, 76, 79, 81, 86]),
    "Dmaj9 final": ([50, 57, 61, 64, 66, 69, 76], 50, 38, [74, 78, 81, 86, 90]),
}

# (start s, end s, chord, attack s, release s, level)
PROGRESSION = [
    (0.0, 2.7, "Gmaj9", 2.3, 1.2, 0.85),
    (2.4, 4.8, "A6sus2", 0.9, 0.12, 1.0),
    (4.8, 7.2, "Dmaj9", 0.03, 0.25, 1.0),
    (7.2, 9.6, "Bm11", 0.05, 0.25, 1.0),
    (9.6, 12.0, "Gmaj7#11", 0.05, 0.25, 1.0),
    (12.0, 14.4, "A6/9", 0.05, 0.25, 1.0),
    (14.4, 16.8, "Dmaj9", 0.05, 0.25, 1.0),
    (16.8, 18.0, "Bm11", 0.02, 0.22, 1.05),
    (18.0, 19.2, "Bm11/A", 0.02, 0.22, 1.05),
    (19.2, 20.4, "Gmaj7#11", 0.02, 0.22, 1.05),
    (20.4, 21.6, "Asus2", 0.02, 0.22, 1.1),
    (21.6, 24.0, "Dmaj9+", 0.03, 0.25, 1.05),
    (24.0, 25.2, "Gmaj13#11", 0.04, 0.12, 1.05),
    (25.2, 26.4, "Gm6/9", 0.06, 0.2, 1.0),
    (26.4, 30.0, "Dmaj9 final", 0.03, 0.5, 1.15),
]

GRID_KICKS = [round(4.8 + i * BEAT, 6) for i in range(36)]
ACCENTS = [16.8, 18.0, 19.2, 20.4]


def at(bar, step=0.0):
    """Seconds at 16th `step` of 1-indexed `bar`."""
    return round((bar - 1) * BAR + step * STEP, 6)


def idx(t):
    return int(round(t * SR))


def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def db(x):
    return 20 * np.log10(np.maximum(np.abs(x), 1e-12))


def undb(x):
    return 10.0 ** (np.asarray(x) / 20.0)


def pan_gains(p):
    a = (p + 1) * np.pi / 4
    return np.cos(a), np.sin(a)


def rise(n):
    """Raised cosine 0 -> 1 over n samples (zero first sample, no step)."""
    n = max(int(n), 1)
    return 0.5 - 0.5 * np.cos(np.pi * np.arange(n) / n)


def gate(n, attack, hold, release):
    """Raised-cosine attack, sustain to `hold` s, raised-cosine release."""
    i = np.arange(n)
    a = max(1, int(attack * SR))
    up = np.where(i < a, 0.5 - 0.5 * np.cos(np.pi * i / a), 1.0)
    h = int(round(hold * SR))
    r = max(1, int(release * SR))
    j = i - h
    down = np.where(j < 0, 1.0, np.where(j < r, 0.5 + 0.5 * np.cos(np.pi * np.clip(j, 0, r) / r), 0.0))
    return up * down


def fade_out(x, seconds):
    n = min(len(x), max(1, int(seconds * SR)))
    g = np.ones(len(x))
    g[-n:] = 1 - rise(n)
    g[-1] = 0.0
    return x * (g if x.ndim == 1 else g[:, None])


def stereo(x, pan=0.0):
    gl, gr = pan_gains(pan)
    return np.stack([x * gl, x * gr], axis=1)


def place(bus, t, x, gain=1.0, pan=0.0):
    if x.ndim == 1:
        x = stereo(x, pan)
    i = idx(t)
    j = min(len(bus), i + len(x))
    if j > i:
        bus[i:j] += gain * x[: j - i]


def butter(x, kind, freq, order=2):
    sos = signal.butter(order, freq, btype=kind, fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def peaking(x, f0, gain_db, q):
    a = 10 ** (gain_db / 40)
    w = 2 * np.pi * f0 / SR
    alpha = np.sin(w) / (2 * q)
    b = np.array([1 + alpha * a, -2 * np.cos(w), 1 - alpha * a])
    den = np.array([1 + alpha / a, -2 * np.cos(w), 1 - alpha / a])
    return signal.lfilter(b / den[0], den / den[0], x, axis=0)


def shelf(x, f0, gain_db, high=True):
    a = 10 ** (gain_db / 40)
    w = 2 * np.pi * f0 / SR
    cw, sw = np.cos(w), np.sin(w)
    alpha = sw / 2 * np.sqrt(2)
    s = 2 * np.sqrt(a) * alpha
    if high:
        b = [a * ((a + 1) + (a - 1) * cw + s), -2 * a * ((a - 1) + (a + 1) * cw), a * ((a + 1) + (a - 1) * cw - s)]
        den = [(a + 1) - (a - 1) * cw + s, 2 * ((a - 1) - (a + 1) * cw), (a + 1) - (a - 1) * cw - s]
    else:
        b = [a * ((a + 1) - (a - 1) * cw + s), 2 * a * ((a - 1) - (a + 1) * cw), a * ((a + 1) - (a - 1) * cw - s)]
        den = [(a + 1) + (a - 1) * cw + s, -2 * ((a - 1) + (a + 1) * cw), (a + 1) + (a - 1) * cw - s]
    b, den = np.array(b), np.array(den)
    return signal.lfilter(b / den[0], den / den[0], x, axis=0)


def svf(x, cutoff, q=0.707, mode="lp"):
    """Zavalishin TPT state-variable filter, safe under per-sample cutoff."""
    if x.ndim == 2:
        return np.stack([svf(x[:, c], cutoff, q, mode) for c in range(x.shape[1])], axis=1)
    n = len(x)
    fc = np.broadcast_to(np.asarray(cutoff, dtype=float), (n,))
    g = np.tan(np.pi * np.minimum(fc, SR * 0.45) / SR)
    k = 1.0 / q
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    xs, A1, A2, A3 = x.tolist(), a1.tolist(), a2.tolist(), a3.tolist()
    lp = [0.0] * n
    bp = [0.0] * n
    ic1 = ic2 = 0.0
    for i in range(n):
        v3 = xs[i] - ic2
        v1 = A1[i] * ic1 + A2[i] * v3
        v2 = ic2 + A2[i] * ic1 + A3[i] * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        lp[i] = v2
        bp[i] = v1
    if mode == "lp":
        return np.array(lp)
    return np.array(bp) * k


def curve(points, n=BUF, log=False):
    """Piecewise automation from (time s, value) points; log interpolates ratios."""
    t = np.arange(n) / SR
    ts = [p[0] for p in points]
    vs = np.array([p[1] for p in points], dtype=float)
    if log:
        return np.exp(np.interp(t, ts, np.log(vs)))
    return np.interp(t, ts, vs)


def pink(n, rng):
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    spec[1:] /= np.sqrt(f[1:])
    spec[0] = 0
    y = np.fft.irfft(spec, n)
    return y / np.sqrt(np.mean(y ** 2))


TABLE = 4096
_saws = {}


def saw_table(f0, top=9000.0):
    """Band-limited saw, harmonics only up to `top` Hz (no aliasing)."""
    nh = max(1, int(top / f0))
    if nh not in _saws:
        ph = 2 * np.pi * np.arange(TABLE) / TABLE
        k = np.arange(1, nh + 1)
        sigma = np.sinc(k / (nh + 1))
        tab = (np.sin(np.outer(ph, k)) * (sigma / k)).sum(axis=1)
        tab /= np.abs(tab).max()
        _saws[nh] = np.append(tab, tab[0])
    return _saws[nh]


def table_osc(tab, cycles):
    p = np.mod(cycles, 1.0) * TABLE
    i = np.minimum(p.astype(np.int64), TABLE - 1)
    f = p - i
    return tab[i] * (1 - f) + tab[i + 1] * f


def pad_note(midi, hold, attack, release, rng, decay=None, voices=5, detune=7.0):
    """Detuned band-limited saws with slow drift, spread across the field."""
    f0 = mtof(midi)
    n = int((hold + release) * SR) + 1
    t = np.arange(n) / SR
    tab = saw_table(f0)
    out = np.zeros((n, 2))
    cents = np.linspace(-detune, detune, voices) + rng.uniform(-1.2, 1.2, voices)
    pans = np.linspace(-0.9, 0.9, voices)
    rng.shuffle(pans)
    for v in range(voices):
        drift = 1.6 * np.sin(2 * np.pi * rng.uniform(0.06, 0.2) * t + rng.uniform(0, 6.3))
        drift += 0.8 * np.sin(2 * np.pi * rng.uniform(0.3, 0.7) * t + rng.uniform(0, 6.3))
        f = f0 * 2 ** ((cents[v] + drift) / 1200)
        x = table_osc(tab, rng.uniform() + np.cumsum(f) / SR)
        gl, gr = pan_gains(pans[v])
        out[:, 0] += x * gl
        out[:, 1] += x * gr
    out /= np.sqrt(voices)
    env = gate(n, attack, hold, release)
    if decay:
        env *= np.exp(-np.maximum(t - attack, 0) / decay)
    return out * env[:, None]


def body_note(midi, hold, attack, release, rng, decay=None):
    """Warm sine body for the low register; the second voice is quiet and only
    4 cents off, so the pair shimmers without the low end cancelling."""
    f0 = mtof(midi)
    n = int((hold + release) * SR) + 1
    t = np.arange(n) / SR
    y = np.zeros(n)
    for c, lvl in ((0.0, 0.8), (4.0, 0.2)):
        ph = 2 * np.pi * (f0 * 2 ** (c / 1200) * t + rng.uniform())
        y += lvl * (np.sin(ph) + 0.22 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph))
    env = gate(n, attack, hold, release)
    if decay:
        env *= np.exp(-np.maximum(t - attack, 0) / decay)
    return stereo(y * env)


def bell(midi, vel=1.0, decay=0.8, bright=1.0):
    """Soft FM pluck/bell: a bright 1:1 FM onset settling to a pure tone."""
    f = mtof(midi)
    n = int(min(4.0, decay * 6.0 + 0.1) * SR)
    t = np.arange(n) / SR
    ph = 2 * np.pi * f * t
    index = bright * (1.7 * np.exp(-t / 0.05) + 0.3 * np.exp(-t / 0.4))
    fm = np.sin(ph + index * np.sin(ph))
    y = 0.5 * fm * np.exp(-t / (decay * 0.55))
    y += 0.6 * np.sin(ph) * np.exp(-t / decay)
    y += 0.1 * bright * np.sin(2 * ph + 0.4) * np.exp(-t / (decay * 0.3))
    y += 0.09 * bright * np.sin(3 * ph + 1.1) * np.exp(-t / 0.05)
    a = int(0.002 * SR)
    y[:a] *= rise(a)
    return vel * fade_out(y, 0.04)


def kick(vel=1.0):
    """Soft round kick: pitch-dropping sine, gently saturated, low-passed."""
    n = int(0.55 * SR)
    t = np.arange(n) / SR
    f = 46 + 70 * np.exp(-t / 0.028) + 30 * np.exp(-t / 0.004)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR)
    y *= np.exp(-t / 0.22)
    a = int(0.0015 * SR)
    y[:a] *= rise(a)
    y = np.tanh(1.5 * y) / np.tanh(1.5)
    beater = butter(np.random.default_rng(3).standard_normal(n), "lowpass", 700) * np.exp(-t / 0.006) * 0.25
    beater[:a] *= rise(a)
    y = butter(y + beater, "lowpass", 1600)
    return vel * fade_out(y, 0.05)


def boom(vel=1.0, decay=0.7):
    """Felt low impact under a landing: sub sine sliding down, plus a thump."""
    n = int(min(5.0, decay * 6) * SR)
    t = np.arange(n) / SR
    f = 37 + 28 * np.exp(-t / 0.12)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / decay)
    thump = butter(np.random.default_rng(5).standard_normal(n), "lowpass", 220) * np.exp(-t / 0.05) * 0.35
    y += thump
    a = int(0.004 * SR)
    y[:a] *= rise(a)
    return vel * fade_out(butter(y, "lowpass", 500), 0.1)


def shaker(vel, rng, open_hat=False):
    n = int((0.45 if open_hat else 0.12) * SR)
    t = np.arange(n) / SR
    y = butter(rng.standard_normal(n), "highpass", 7000 if open_hat else 6500, 4)
    y = butter(y, "lowpass", 11000)
    env = np.exp(-t / (0.12 if open_hat else 0.022))
    a = int((0.006 if open_hat else 0.004) * SR)
    env[:a] *= rise(a)
    return vel * fade_out(y * env, 0.02)


def snap(vel, rng):
    """Soft distant clap: three quick bursts and a short tail, band-limited."""
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    env = np.zeros(n)
    for k, d in enumerate((0.0, 0.008, 0.017)):
        tt = np.maximum(t - d, 0)
        env += (t >= d) * np.exp(-tt / 0.004) * (0.7 if k < 2 else 1.0)
    env += 0.5 * np.exp(-t / 0.06)
    a = int(0.001 * SR)
    env[:a] *= rise(a)
    y = butter(rng.standard_normal(n), "bandpass", (900, 2600))
    y = butter(y * env, "lowpass", 3200)
    return vel * fade_out(y, 0.05)


def shimmer_tone(midi, hold, attack, release, rng):
    n = int((hold + release) * SR) + 1
    t = np.arange(n) / SR
    vib = 1 + 0.0015 * np.sin(2 * np.pi * rng.uniform(4, 5.5) * t + rng.uniform(0, 6.3))
    ph = 2 * np.pi * (np.cumsum(mtof(midi) * vib) / SR + rng.uniform())
    am = 0.55 + 0.45 * np.sin(2 * np.pi * rng.uniform(0.15, 0.4) * t + rng.uniform(0, 6.3))
    return np.sin(ph) * am * gate(n, attack, hold, release)


def make_ir(seconds, rts, predelay, seed, early=True):
    """Stereo decorrelated noise IR with frequency-dependent decay."""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = np.zeros((n, 2))
    bands = (("lowpass", 350), ("bandpass", (350, 2500)), ("highpass", 2500))
    for ch in range(2):
        noise = rng.standard_normal(n)
        acc = np.zeros(n)
        for (kind, f), rt in zip(bands, rts):
            acc += butter(noise, kind, f) * 10 ** (-3 * t / rt)
        acc *= 1 - np.exp(-t / 0.02)
        if early:
            for _ in range(12):
                d = rng.uniform(0.004, 0.06)
                acc[int(d * SR)] += rng.choice((-1, 1)) * rng.uniform(1.5, 4.0) * np.exp(-d / 0.04)
        ir[:, ch] = acc
    ir = butter(ir, "lowpass", 9000)
    ir = fade_out(ir, seconds * 0.2)
    ir = np.concatenate([np.zeros((int(predelay * SR), 2)), ir])
    return ir / np.sqrt(np.sum(ir ** 2) / 2)


def reverb(x, ir, width=1.0):
    """Mid feeds two decorrelated IRs; `width` < 1 blends them for a narrower tail."""
    mid = x.mean(axis=1)
    wl = signal.fftconvolve(mid, ir[:, 0])[: len(mid)]
    wr = signal.fftconvolve(mid, ir[:, 1])[: len(mid)]
    m = 0.5 * (wl + wr)
    s = 0.5 * (wl - wr) * width
    return np.stack([m + s, m - s], axis=1)


def ping_pong(x, delay, feedback, repeats):
    mono = x.mean(axis=1)
    out = np.zeros_like(x)
    d = idx(delay)
    tap = mono
    for k in range(1, repeats + 1):
        tap = butter(butter(tap, "lowpass", 3800), "highpass", 350) * feedback
        gl, gr = (0.95, 0.3) if k % 2 else (0.3, 0.95)
        out[k * d :, 0] += tap[: len(mono) - k * d] * gl
        out[k * d :, 1] += tap[: len(mono) - k * d] * gr
    return out


def duck(times, depth, n=BUF, attack=0.004, release=0.24):
    """Sidechain gain curve: dips by `depth` on each kick, smooth recovery."""
    a, r = int(attack * SR), int(release * SR)
    shape = np.concatenate([rise(a), 1 - rise(r)])
    g = np.ones(n)
    for t in times:
        i = idx(t)
        j = min(n, i + len(shape))
        g[i:j] = np.minimum(g[i:j], 1 - depth * shape[: j - i])
    return g


def reverse_swell(notes, length, ir, rng):
    """The landing chord's reverb tail, reversed, so it breathes in to the hit."""
    n = int(3.6 * SR)
    chord = np.zeros((n, 2))
    for m in notes:
        place(chord, 0.0, pad_note(m, 0.3, 0.005, 0.25, rng, voices=3), 0.15)
    wet = reverb(butter(butter(chord, "highpass", 200), "lowpass", 4500), ir)
    env = np.convolve((wet ** 2).sum(axis=1), np.ones(idx(0.01)), "same")
    top = int(np.argmax(env[: idx(0.4)]))
    seg = wet[top : top + int(length * SR)][::-1].copy()
    m = len(seg)
    shape = (np.arange(m) / m) ** 2.2
    seg *= shape[:, None]
    tail = int(0.004 * SR)
    seg[-tail:] *= (1 - rise(tail))[:, None]
    return seg / np.max(np.abs(seg))


def noise_riser(length, f0, f1, rng, power=3.0, q=0.9):
    n = int(length * SR)
    x = np.stack([pink(n, rng), pink(n, rng)], axis=1)
    fc = f0 * (f1 / f0) ** (np.arange(n) / n)
    y = svf(x, fc, q, "bp")
    env = (np.arange(n) / n) ** power
    tail = int(0.006 * SR)
    env[-tail:] *= 1 - rise(tail)
    y *= env[:, None]
    return y / np.max(np.abs(y))


def bass_line():
    """(start s, length s, midi) per note; re-articulated, approach notes into bars."""
    D2, B1, G1, A1 = 38, 35, 31, 33
    bars = {
        3: [(0, 6, D2), (6, 10, D2)],
        4: [(0, 6, B1), (6, 10, B1)],
        5: [(0, 6, G1), (6, 4, G1), (10, 4, D2), (14, 2, B1)],
        6: [(0, 6, A1), (6, 4, A1), (10, 4, 40), (14, 2, 37)],
        7: [(0, 6, D2), (6, 4, D2), (10, 4, 45), (14, 2, 37)],
        8: [(0, 6, B1), (6, 2, B1), (8, 8, A1)],
        9: [(0, 6, G1), (6, 2, G1), (8, 6, A1), (14, 2, 37)],
        10: [(0, 6, D2), (6, 4, D2), (10, 4, 45), (14, 2, A1)],
        11: [(0, 6, G1), (6, 2, G1), (8, 8, G1)],
    }
    notes = []
    for bar, pattern in bars.items():
        for step, length, m in pattern:
            notes.append((at(bar, step), length * STEP, m))
    return notes


def render_bass(notes, final):
    n = BUF
    target = np.full(n, np.nan)
    amp = np.zeros(n)
    for start, length, m in notes:
        i = idx(start)
        target[i : idx(start + length)] = mtof(m)
        k = int((length + 0.06) * SR)
        e = gate(k, 0.006, length - 0.03, 0.05)
        j = min(n, i + k)
        amp[i:j] = np.maximum(amp[i:j], e[: j - i])
    start, m, decay = final
    i = idx(start)
    target[i:] = mtof(m)
    k = n - i
    tt = np.arange(k) / SR
    e = gate(k, 0.008, k / SR, 0.01) * np.exp(-tt / decay)
    amp[i:] = np.maximum(amp[i:], e)
    valid = ~np.isnan(target)
    pos = np.where(valid, np.arange(n), 0)
    np.maximum.accumulate(pos, out=pos)
    filled = target[pos]
    filled[np.isnan(filled)] = mtof(38)
    lf = np.log(filled)
    alpha = 1 - np.exp(-1 / (0.012 * SR))
    lf = signal.lfilter([alpha], [1, alpha - 1], lf, zi=[lf[0] * (1 - alpha)])[0]
    ph = 2 * np.pi * np.cumsum(np.exp(lf)) / SR
    sub = np.sin(ph)
    harm = sum(np.sin(k * ph) * (0.32 / k ** 1.3) for k in range(2, 8))
    y = np.tanh(1.2 * (sub + harm)) / np.tanh(1.2)
    y = butter(y, "lowpass", 700) * amp
    return stereo(y)


def compose():
    rng = np.random.default_rng(20261010)
    hall = make_ir(4.5, (3.4, 2.8, 1.5), 0.024, seed=11)
    room = make_ir(1.0, (0.55, 0.45, 0.3), 0.006, seed=12)
    s = {k: np.zeros((BUF, 2)) for k in (
        "pad", "body", "bass", "kick", "hats", "snap", "arp", "accent", "shimmer", "swell", "air", "impact")}

    for start, end, name, attack, release, level in PROGRESSION:
        pad, body, _, _ = CHORDS[name]
        final = name == "Dmaj9 final"
        hold = end - start
        scale = level * np.sqrt(5.0 / len(pad)) * 0.16
        for m in pad:
            w = 2 ** (-(m - 62) / 24)
            x = pad_note(m, hold, attack, release, rng, decay=3.0 if final else None)
            place(s["pad"], start, x, scale * w)
        place(s["body"], start, body_note(body, hold, attack, release, rng, decay=2.6 if final else None), 0.15 * level)

    halo = np.zeros((BUF, 2))
    for start, end, name, attack, release, level in PROGRESSION:
        if start >= 16.8:
            top = sorted(CHORDS[name][0])[-3:]
            final = name == "Dmaj9 final"
            for m in top:
                x = pad_note(m + 12, end - start, 0.12, release + 0.2, rng, decay=2.2 if final else None, voices=3, detune=9.0)
                place(halo, start, x, 0.08 * 2 ** (-(m + 12 - 74) / 24))

    shimmer_plan = [
        (0.5, 1.9, [86, 90], 1.6, 1.0, 1.0),
        (1.3, 2.4, [93], 1.4, 1.4, 0.7),
        (2.4, 2.6, [88, 90, 95], 1.0, 1.4, 0.9),
        (16.8, 4.8, [88, 93], 3.0, 1.0, 0.45),
        (21.6, 3.2, [90], 1.0, 0.4, 0.55),
        (21.6, 4.8, [93], 1.0, 0.6, 0.55),
        (26.4, 3.6, [86, 90, 93], 0.9, 0.5, 1.0),
    ]
    for start, hold, notes, attack, release, level in shimmer_plan:
        for m in notes:
            place(s["shimmer"], start, shimmer_tone(m, hold, attack, release, rng), 0.065 * level, rng.uniform(-0.5, 0.5))
    air = butter(pink(BUF, rng), "bandpass", (7000, 13000), 2)
    air_r = butter(pink(BUF, rng), "bandpass", (7000, 13000), 2)
    air_env = curve([(0, 0), (1.5, 0.6), (4.79, 1.0), (4.8, 0.25), (16.8, 0.25), (21.6, 0.6), (26.39, 0.8), (26.4, 0.6), (27.5, 0.9), (30, 0.3), (BUF / SR, 0)])
    s["air"] += np.stack([air, air_r], axis=1) * air_env[:, None] * 0.008

    place(s["swell"], 4.8 - 2.4, reverse_swell(CHORDS["Dmaj9"][0], 2.4, hall, rng), 0.3)
    place(s["swell"], 26.4 - 2.4, reverse_swell(CHORDS["Dmaj9 final"][0], 2.4, hall, rng), 0.5)
    place(s["air"], 4.8 - 1.8, noise_riser(1.8, 300, 2400, rng), 0.05)
    place(s["air"], 16.8, noise_riser(4.8, 400, 3200, rng, power=2.4), 0.03)
    place(s["air"], 26.4 - 1.2, noise_riser(1.2, 350, 2600, rng), 0.06)
    for t in ACCENTS[1:]:
        place(s["air"], t - 0.3, noise_riser(0.3, 3000, 7000, rng, power=2.0, q=0.7), 0.018)

    place(s["impact"], 4.8, boom(1.0, 0.6), 0.32)
    place(s["impact"], 26.4, boom(1.0, 1.3), 0.36)

    for t in GRID_KICKS:
        vel = 0.8 if t < 9.6 else 0.9 if t < 16.8 else 0.96
        if abs((t - 4.8) % BAR) < 1e-6:
            vel *= 1.06
        if any(abs(t - a) < 1e-6 for a in ACCENTS):
            vel *= 1.1
        place(s["kick"], t, kick(vel), 0.28)

    hat_vel = (0.55, 0.3, 0.85, 0.35)
    for i in range(int(round((26.4 - 4.8) / STEP))):
        t = round(4.8 + i * STEP, 6)
        sect = 0.5 if t < 9.6 else 0.72 if t < 16.8 else 0.85 if t < 21.6 else 0.95
        v = hat_vel[i % 4] * sect * rng.uniform(0.88, 1.08)
        if t >= 25.8:
            v *= 1 - 0.6 * (t - 25.8) / 0.6
        place(s["hats"], t, shaker(v, rng), 0.26, 0.22)
        if t >= 16.8 and i % 4 == 2:
            place(s["hats"], t, shaker(v * (0.5 if t < 21.6 else 0.6), rng, open_hat=True), 0.16, -0.25)

    for bar in range(5, 12):
        for step in (4, 12):
            place(s["snap"], at(bar, step), snap(rng.uniform(0.9, 1.05), rng), 0.4)

    arp_plan = []
    one_bar = ([0, 3, 6, 10], [0, 3, 2, 1])
    for bar, name in ((5, "Gmaj7#11"), (6, "A6/9"), (7, "Dmaj9")):
        for step, k in zip(*one_bar):
            arp_plan.append((at(bar, step), CHORDS[name][3][k], 0.8, False))
    for half, name in enumerate(("Bm11", "Bm11/A", "Gmaj7#11", "Asus2")):
        base = 16.8 + half * 1.2
        for j, (step, k) in enumerate(zip((0, 3, 6), (1, 4, 2))):
            arp_plan.append((round(base + step * STEP, 6), CHORDS[name][3][k], 0.95 if j == 0 else 0.82, True))
    for step, k in zip((0, 3, 6, 8, 11, 14), (1, 3, 2, 0, 4, 2)):
        arp_plan.append((at(10, step), CHORDS["Dmaj9+"][3][k], 0.88, True))
    for step, k in zip((0, 3, 6), (2, 3, 1)):
        arp_plan.append((at(11, step), CHORDS["Gmaj13#11"][3][k], 0.85, True))
    for step, k in zip((8, 11, 14), (0, 4, 2)):
        arp_plan.append((at(11, step), CHORDS["Gm6/9"][3][k], 0.8, True))
    for t, m, vel, double in arp_plan:
        v = vel * rng.uniform(0.92, 1.05)
        place(s["arp"], t, bell(m, v, decay=0.7), 0.14, 0.08)
        if double and m + 12 <= 93:
            place(s["arp"], t, bell(m + 12, v * 0.38, decay=0.5, bright=0.5), 0.14, -0.3)

    for t, name in zip(ACCENTS, ("Bm11", "Bm11/A", "Gmaj7#11", "Asus2")):
        lad = CHORDS[name][3]
        for m in (lad[0], lad[2], lad[3]):
            place(s["accent"], t, bell(m - 12, 0.5, decay=0.9, bright=0.6), 0.14, rng.uniform(-0.4, 0.4))
    place(s["accent"], 26.4, bell(86, 0.85, decay=1.6, bright=0.7), 0.12, 0.05)
    place(s["accent"], 26.4, bell(74, 0.5, decay=2.0, bright=0.5), 0.12, -0.05)

    bass_gain = curve([(0, 0.62), (4.8, 0.62), (9.5, 0.62), (9.6, 0.85), (16.8, 0.9), (21.6, 1.0), (BUF / SR, 1.0)])
    s["bass"] = render_bass(bass_line(), (26.4, 38, 1.8)) * (0.19 * bass_gain)[:, None]

    cutoff = curve([(0, 380), (2.4, 1100), (4.6, 2100), (4.8, 2300), (9.6, 2800), (16.8, 2900),
                    (21.6, 5200), (24.0, 4800), (25.6, 4400), (26.38, 2200), (26.4, 2300),
                    (26.55, 4600), (30.0, 1400), (BUF / SR, 1300)], log=True)
    halo_gain = curve([(0, 0.0), (16.8, 0.0), (17.0, 0.35), (21.4, 0.85), (21.6, 1.0), (26.4, 1.0), (27.0, 0.7), (BUF / SR, 0.7)])
    pad = butter(s["pad"] + halo * halo_gain[:, None], "highpass", 140)
    pad = svf(svf(pad, cutoff, 0.6), cutoff, 0.9)
    pad_gain = curve([(0, 0.4), (2.4, 0.42), (4.7, 0.64), (4.8, 0.62), (9.6, 0.85), (16.8, 0.92), (21.6, 1.12), (26.4, 1.15), (BUF / SR, 1.15)])
    s["pad"] = pad * pad_gain[:, None]
    body_gain = curve([(0, 0.9), (2.4, 1.0), (4.7, 1.25), (4.8, 1.0), (BUF / SR, 1.0)])
    s["body"] = butter(s["body"], "lowpass", 600) * body_gain[:, None]
    s["arp"] = butter(butter(s["arp"], "highpass", 220), "lowpass", 9000)
    s["arp"] += ping_pong(s["arp"], 0.45, 0.4, 6) * 0.55
    s["accent"] = butter(s["accent"], "lowpass", 8000)
    s["shimmer"] = butter(s["shimmer"], "lowpass", 12000)

    kick_times = GRID_KICKS
    s["pad"] *= duck(kick_times, 0.2)[:, None]
    s["body"] *= duck(kick_times, 0.35)[:, None]
    s["bass"] *= duck(kick_times, 0.45, release=0.18)[:, None]

    sends = (s["pad"] * 0.32 + s["arp"] * 0.4 + s["accent"] * 0.6 + s["shimmer"] * 1.2
             + s["snap"] * 0.9 + s["swell"] * 0.2 + s["air"] * 0.3 + s["body"] * 0.05)
    wet = reverb(butter(sends, "highpass", 220), hall, width=1.0) * 0.5
    wet = butter(wet, "lowpass", 7500)
    s["hall"] = wet * duck(kick_times, 0.15, release=0.3)[:, None]
    s["room"] = reverb(butter(s["hats"] * 0.6 + s["snap"] * 0.8 + s["kick"] * 0.05, "highpass", 300), room) * 0.18
    return s


def lufs(x):
    """ITU-R BS.1770-4 integrated loudness (48 kHz K-weighting, gated)."""
    y = signal.lfilter([1.53512485958697, -2.69169618940638, 1.19839281085285],
                       [1.0, -1.69065929318241, 0.73248077421585], x, axis=0)
    y = signal.lfilter([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621], y, axis=0)
    blk, hop = int(0.4 * SR), int(0.1 * SR)
    c = np.concatenate([[0.0], np.cumsum((y ** 2).sum(axis=1))])
    starts = np.arange(0, len(y) - blk + 1, hop)
    ms = (c[starts + blk] - c[starts]) / blk
    loud = -0.691 + 10 * np.log10(np.maximum(ms, 1e-20))
    g = ms[loud > -70]
    rel = -0.691 + 10 * np.log10(g.mean()) - 10
    g = ms[(loud > -70) & (loud > rel)]
    return -0.691 + 10 * np.log10(g.mean())


def bar_loudness(x):
    """Ungated K-weighted loudness of one stretch (LUFS), for the energy curve."""
    y = signal.lfilter([1.53512485958697, -2.69169618940638, 1.19839281085285],
                       [1.0, -1.69065929318241, 0.73248077421585], x, axis=0)
    y = signal.lfilter([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621], y, axis=0)
    return -0.691 + 10 * np.log10(np.mean(y ** 2, axis=0).sum() + 1e-20)


def true_peak_db(x):
    up = signal.resample_poly(x, 4, 1, axis=0)
    return db(np.abs(up).max())


def compress(x, threshold_db, ratio, attack, release, knee=6.0):
    det = signal.lfilter([1 - np.exp(-1 / (0.008 * SR))], [1, -np.exp(-1 / (0.008 * SR))], (x ** 2).mean(axis=1))
    over = 10 * np.log10(np.maximum(det, 1e-20)) - threshold_db
    gr = np.where(over <= -knee / 2, 0.0,
                  np.where(over >= knee / 2, over * (1 - 1 / ratio), (1 - 1 / ratio) * (over + knee / 2) ** 2 / (2 * knee)))
    dec = 16
    g = gr[::dec].tolist()
    ca, cr = np.exp(-dec / (attack * SR)), np.exp(-dec / (release * SR))
    out, state = [], 0.0
    for v in g:
        coef = ca if v > state else cr
        state = coef * state + (1 - coef) * v
        out.append(state)
    sm = np.interp(np.arange(len(x)), np.arange(len(out)) * dec, out)
    return x * undb(-sm)[:, None], sm


def limit(x, ceiling_db, lookahead=0.003, release=0.12):
    c = undb(ceiling_db)
    up = signal.resample_poly(x, 4, 1, axis=0)
    pk = np.abs(up).max(axis=1)[: 4 * len(x)].reshape(-1, 4).max(axis=1)
    need = np.minimum(1.0, c / np.maximum(pk, 1e-9))
    la = int(lookahead * SR)
    ahead = minimum_filter1d(need, size=la + 1, origin=-(la // 2))
    smooth = np.convolve(np.concatenate([np.ones(la), ahead]), np.ones(la) / la)[la : la + len(ahead)]
    smooth = np.minimum(smooth, ahead)
    rc = 1 - np.exp(-1 / (release * SR))
    out, state = [], 1.0
    for v in smooth.tolist():
        state = v if v < state else state + (min(1.0, v) - state) * rc
        out.append(state)
    g = np.array(out)
    return x * g[:, None], g


def master(stems):
    mix = sum(stems[k] for k in stems)[:N].copy()
    mix = butter(mix, "highpass", 28)
    mix = peaking(mix, 5000, 2.0, 0.8)
    mix = shelf(mix, 7000, 2.0, high=True)
    mix -= mix.mean(axis=0)
    mix /= np.abs(mix).max()
    mix, gr = compress(mix * undb(-6), -20.0, 1.8, 0.03, 0.25)
    gain = 0.0
    for _ in range(6):
        trial = mix * undb(gain)
        out, g = limit(trial, CEILING_DBTP)
        loud = lufs(out)
        gain += TARGET_LUFS - loud
        if abs(TARGET_LUFS - loud) < 0.05:
            break
    out, g = limit(mix * undb(gain), CEILING_DBTP)
    fade = idx(0.6)
    out[-fade:] *= (0.5 + 0.5 * np.cos(np.pi * np.arange(fade) / (fade - 1)))[:, None]
    out[: idx(0.005)] *= rise(idx(0.005))[:, None]
    for _ in range(4):
        tp = true_peak_db(out)
        if tp <= CEILING_DBTP + 0.05:
            break
        out *= undb(CEILING_DBTP - tp - 0.05)
    return out, gr, g


def dither_write(path, x):
    lsb = 2.0 ** -23
    rng = np.random.default_rng(1)
    d = (rng.uniform(-0.5, 0.5, x.shape) + rng.uniform(-0.5, 0.5, x.shape)) * lsb
    sf.write(str(path), np.clip(x + d, -1, 1 - lsb), SR, subtype="PCM_24")


def sfx_key(rng):
    """Soft deep keyboard thock tuned to D: damped body modes, a wooden
    mid layer and a felt tap, gone within ~150 ms."""
    n = idx(0.15)
    t = np.arange(n) / SR
    bend = 1 + 0.3 * np.exp(-t / 0.005)
    y = np.sin(2 * np.pi * np.cumsum(mtof(50) * bend) / SR) * np.exp(-t / 0.022)
    y += 0.5 * np.sin(2 * np.pi * np.cumsum(mtof(62) * bend) / SR) * np.exp(-t / 0.012)
    y += 0.2 * np.sin(2 * np.pi * mtof(69) * t) * np.exp(-t / 0.008)
    y += 0.18 * np.sin(2 * np.pi * mtof(74) * t) * np.exp(-t / 0.005)
    wood = butter(rng.standard_normal(n), "bandpass", (350, 1400)) * np.exp(-t / 0.009) * 1.2
    tap = butter(rng.standard_normal(n), "lowpass", 2400) * np.exp(-t / 0.003) * 0.8
    tap = butter(tap + wood, "highpass", 150)
    a = int(0.0012 * SR)
    y = (y + tap)
    y[:a] *= rise(a)
    x = np.stack([y, y], axis=1)
    small = make_ir(0.12, (0.08, 0.07, 0.05), 0.002, seed=21, early=False)
    x = x + reverb(x, small) * 0.12
    x = butter(x, "lowpass", 5000)
    return fade_out(x, 0.03)


def sfx_whoosh(rng):
    """Airy swell: pink noise through a rising band-pass, gliding left to right."""
    n = idx(0.7)
    u = np.arange(n) / n
    x = np.stack([pink(n, rng), pink(n, rng)], axis=1)
    fc = 280 * (2400 / 280) ** (u ** 1.3)
    body = svf(x, fc, 0.8, "bp")
    air = butter(x, "bandpass", (5500, 11000)) * 0.25
    env = np.where(u < 0.68, (u / 0.68) ** 2.2, np.cos(np.pi / 2 * (u - 0.68) / 0.32) ** 2)
    y = (body + air * (u ** 2)[:, None]) * env[:, None]
    d = int(SR / mtof(62))
    comb = y.copy()
    comb[d:] += 0.45 * y[:-d]
    y = 0.75 * y + 0.25 * comb
    p = -0.5 + u
    gl, gr = pan_gains(p)
    y[:, 0] *= gl * np.sqrt(2)
    y[:, 1] *= gr * np.sqrt(2)
    y = peaking(y, 3200, -3, 0.8)
    a = idx(0.01)
    y[:a] *= rise(a)[:, None]
    return fade_out(y, 0.02)


def sfx_glow(rng, hall):
    """Shimmering D: D4/D5/A5/D6/F#6 partials, each a main voice with two
    quiet detuned neighbours (a shallow chorus, not a warble), slow bloom."""
    n = idx(1.5)
    t = np.arange(n) / SR
    x = np.zeros((n, 2))
    for m, lvl, trem in ((62, 0.35, 0.0), (74, 1.0, 0.08), (81, 0.3, 0.15), (86, 0.38, 0.2), (90, 0.12, 0.25)):
        for ch in range(2):
            for c, v in ((0.0, 1.0), (-3.0, 0.3), (3.0, 0.3)):
                f = mtof(m) * 2 ** ((c + rng.uniform(-0.5, 0.5)) / 1200)
                ph = 2 * np.pi * (f * t + rng.uniform())
                am = 1 - trem * (0.5 + 0.5 * np.sin(2 * np.pi * 5.5 * t + rng.uniform(0, 6.3)))
                x[:, ch] += lvl * v * np.sin(ph) * am
    env = np.minimum(1, t / 0.18)
    env = (0.5 - 0.5 * np.cos(np.pi * env)) * np.exp(-np.maximum(t - 0.18, 0) / 0.7)
    x *= env[:, None]
    x = x + reverb(x, hall) * 0.25
    x /= np.sqrt(np.mean(x ** 2, axis=0))
    return fade_out(x, 0.35)


def normalize_peak(x, peak_db):
    return x * undb(peak_db) / np.abs(x).max()


def onsets(x, min_gap=0.25, jump=2.0, rel=0.1):
    """Hit starts: 2 ms RMS jumps `jump` times over the loudest 2 ms of the
    50 ms that end 5 ms earlier; then the first sample clearly above that tail."""
    p = (x ** 2).sum(axis=1) if x.ndim == 2 else x ** 2
    a = np.sqrt(p)
    w = idx(0.002)
    env = np.sqrt(np.convolve(p, np.ones(w) / w)[w - 1 :])
    span = idx(0.05)
    trailing = maximum_filter1d(env, size=span, origin=(span - 1) // 2)
    gap = idx(0.005)
    prior = np.concatenate([np.zeros(gap), trailing[:-gap]])
    hit = (env > jump * prior + 1e-9) & (env > rel * env.max())
    found, last = [], -10 * SR
    for i in np.flatnonzero(hit):
        if i - last > min_gap * SR:
            lo = max(0, i - idx(0.035))
            hi = max(lo, i - idx(0.004))
            floor = a[lo:hi].max() if hi > lo else 0.0
            s0 = max(0, i - idx(0.004))
            above = np.flatnonzero(a[s0 : i + idx(0.01)] > max(1.5 * floor, 1e-4 * a.max()))
            found.append((s0 + above[0]) / SR if len(above) else i / SR)
            last = i
    return found


def align(mix, template, t, search=0.03, length=0.12):
    """Lag (ms) at which `template` best matches `mix` around `t` (normalised xcorr)."""
    lo = idx(t - search)
    seg = butter(mix[lo : idx(t + search + length)], "bandpass", (30, 400))
    tpl = butter(template[: idx(length)], "bandpass", (30, 400))
    xc = signal.correlate(seg, tpl, mode="valid")
    energy = np.sqrt(np.convolve(seg ** 2, np.ones(len(tpl)), "valid"))
    return 1000 * (lo + int(np.argmax(xc / (energy + 1e-12))) - idx(t)) / SR


def report(out, stems, gr, lim):
    mono = out.mean(axis=1)
    print("\n== music.wav ==")
    print(f"length {len(out)} samples = {len(out) / SR:.6f} s")
    print(f"integrated {lufs(out):.2f} LUFS (internal), true peak {true_peak_db(out):.2f} dBTP, "
          f"sample peak {db(np.abs(out).max()):.2f} dBFS")
    print(f"DC L {out[:, 0].mean():.2e} R {out[:, 1].mean():.2e}; samples >= -0.1 dBFS: "
          f"{int((np.abs(out) >= undb(-0.1)).sum())}")
    print(f"glue compressor max GR {gr.max():.2f} dB; limiter max GR {-db(lim.min()):.2f} dB, "
          f"limiting active {100 * np.mean(lim < 0.999):.2f}% of samples")
    print("\nbar  start   RMS dBFS  LUFS(bar)  corr   width(S/M dB)")
    for b in range(13):
        i, j = idx(b * BAR), min(N, idx((b + 1) * BAR))
        seg = out[i:j]
        rms = db(np.sqrt(np.mean(seg ** 2)))
        l, r = seg[:, 0], seg[:, 1]
        corr = np.sum(l * r) / np.sqrt(np.sum(l * l) * np.sum(r * r))
        m, s_ = (l + r) / 2, (l - r) / 2
        print(f"{b + 1:>3}  {b * BAR:5.1f}   {rms:7.2f}  {bar_loudness(seg):8.2f}  {corr:5.2f}  {db(np.sqrt(np.mean(s_ ** 2)) / np.sqrt(np.mean(m ** 2))):6.1f}")
    l, r = out[:, 0], out[:, 1]
    print(f"overall L/R correlation {np.sum(l * r) / np.sqrt(np.sum(l * l) * np.sum(r * r)):.3f}")

    k_on = onsets(stems["kick"][:N])
    errs = [1000 * (o - g) for o, g in zip(k_on, GRID_KICKS)]
    print(f"\nkick onsets: {len(k_on)} found, expected {len(GRID_KICKS)}; first {[round(o, 4) for o in k_on[:5]]} ... last {round(k_on[-1], 4)}")
    print(f"kick grid error max {max(abs(e) for e in errs):.3f} ms")
    acc = stems["accent"][:N].copy()
    acc[idx(26.0):] = 0
    a_on = onsets(acc, min_gap=0.5)
    print(f"accent onsets: {[round(float(o), 4) for o in a_on]} (want {ACCENTS})")
    marks = (4.8, 9.6, 16.8, 18.0, 19.2, 20.4, 21.6, 24.0, 25.8, 26.4)
    lags = [round(align(mono, boom(1.0, 1.3) if t == 26.4 else kick(1.0), t), 3) for t in marks]
    print(f"mix vs kick/boom waveform, best-fit lag (ms) at {marks}: {lags}")
    tail = out[idx(29.99):]
    print(f"last 10 ms peak {db(np.abs(tail).max()):.1f} dBFS, final sample {out[-1]}")

    print("\noctave bands (dB rel. loudest band): whole track | lift+peak 16.8-26.4")
    for seg_name, seg in (("all", mono), ("peak", mono[idx(16.8):idx(26.4)])):
        f, p = signal.welch(seg, SR, nperseg=8192)
        bands = []
        for fc in (31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000):
            sel = (f >= fc / np.sqrt(2)) & (f < fc * np.sqrt(2))
            bands.append(10 * np.log10(p[sel].sum() + 1e-30))
        bands = np.array(bands) - max(bands)
        print(f"  {seg_name:>4}: " + "  ".join(f"{int(fc) if fc >= 1 else fc}:{b:6.1f}" for fc, b in
                                              zip((31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000), bands)))
    harsh = []
    for b in range(13):
        seg = mono[idx(b * BAR):min(N, idx((b + 1) * BAR))]
        f, p = signal.welch(seg, SR, nperseg=4096)
        mid = p[(f >= 250) & (f < 2000)].sum()
        pres = p[(f >= 2000) & (f < 5000)].sum()
        harsh.append(round(float(10 * np.log10(pres / mid + 1e-30)), 1))
    print(f"2-5 kHz vs 250 Hz-2 kHz energy per bar (dB): {harsh}")

    print("\nclick scan, tonal stems: HF (>10 kHz) peak rel. stem peak; 1 ms HF spikes >15 dB over their 100 ms median and above -70 dB")
    for name in ("pad", "body", "bass", "arp", "accent", "shimmer", "swell", "impact", "hall"):
        x = stems[name][:N]
        hp = butter(x, "highpass", 10000, 4)
        win = idx(0.001)
        e = np.sqrt(np.convolve((hp ** 2).sum(axis=1), np.ones(win) / win, "same"))[::win]
        rel = db(e) - db(np.abs(x).max())
        spike = db(e) - db(signal.medfilt(e, 101))
        bad = np.flatnonzero((spike > 15) & (rel > -70))
        where = ", ".join(f"{i * win / SR:.3f}" for i in bad[:6])
        print(f"  {name:>8}: HF max {rel.max():7.1f} dB; spikes: {len(bad)}{' at ' + where if len(bad) else ''}")


def stem_levels(stems):
    print("stem RMS (dBFS pre-master) per section: intro 0-4.8 | groove 4.8-9.6 | speak 9.6-16.8 | lift 16.8-21.6 | peak 21.6-26.4 | end 26.4-30")
    cuts = (0, 4.8, 9.6, 16.8, 21.6, 26.4, 30.0)
    for k, x in stems.items():
        row = []
        for a, b in zip(cuts, cuts[1:]):
            seg = x[idx(a):idx(b)]
            row.append(f"{db(np.sqrt(np.mean(seg ** 2))):6.1f}")
        print(f"  {k:>8}: " + " | ".join(row) + f"   peak {db(np.abs(x).max()):6.1f}")


def main():
    default = Path(__file__).resolve().parent.parent / "public" / "sounds"
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else default
    out_dir.mkdir(parents=True, exist_ok=True)
    stems = compose()
    stem_levels(stems)
    out, gr, lim = master(stems)
    dither_write(out_dir / "music.wav", out)
    report(out, stems, gr, lim)

    rng = np.random.default_rng(99)
    hall = make_ir(1.4, (1.2, 1.0, 0.6), 0.015, seed=31)
    for name, x in (("key", sfx_key(rng)), ("whoosh", sfx_whoosh(rng)), ("glow", sfx_glow(rng, hall))):
        x = fade_out(butter(x, "highpass", 25), 0.01)
        x[: idx(0.0005)] *= rise(idx(0.0005))[:, None]
        x = normalize_peak(x, SFX_PEAK_DB)
        dither_write(out_dir / f"{name}.wav", x)
        mono = x.mean(axis=1)
        f, p = signal.welch(mono, SR, nperseg=min(4096, len(mono)))
        centroid = (f * p).sum() / p.sum()
        print(f"{name}.wav {len(x) / SR:.3f} s, peak {db(np.abs(x).max()):.1f} dBFS, "
              f"true peak {true_peak_db(x):.1f} dBTP, centroid {centroid:.0f} Hz")


if __name__ == "__main__":
    main()
