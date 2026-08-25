#!/usr/bin/env python3
"""Generate the three ambience loops for Drip Drop Dont Stop.

Matches the existing SFX format (22050 Hz, mono, Int16). Every LFO is an
integer number of cycles per loop, and the noise beds get an equal-power
tail-to-head crossfade, so all three files loop seamlessly.

  ambience.wav  - 16s cave bed: brown rumble + air + sparse echoing drips
  amb_ice.wav   -  8s crystalline shimmer (faded in while frozen)
  amb_steam.wav -  6s soft band-passed hiss (faded in as vapor)
"""
import numpy as np
import wave, sys, os

SR = 22050
rng = np.random.default_rng(7)

def lowpass(x, alpha):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y

def loopify(x, fade_s=0.6):
    """Equal-power crossfade of the tail onto the head, then trim."""
    n = int(fade_s * SR)
    t = np.linspace(0, np.pi / 2, n)
    head, tail = x[:n].copy(), x[-n:].copy()
    x = x[:-n]
    x[:n] = tail * np.cos(t) + head * np.sin(t)
    return x

def normalize(x, peak):
    return x / (np.abs(x).max() + 1e-9) * peak

def write(name, x):
    path = os.path.join(sys.argv[1], name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    print(name, f"{len(x)/SR:.2f}s")

def drip(f0=1400, decay=28.0, echo=3, dur=1.8):
    """A pitch-bending plink with fading echoes, like a drop in a cistern."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + 0.25 * np.exp(-t * 30))           # quick pitch-down
    ping = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * decay)
    out = np.zeros(n)
    for e in range(echo + 1):
        d = int(e * 0.26 * SR)
        g = 0.55 ** e
        seg = ping[: n - d] * g
        out[d:] += seg
    return out * 0.8

# ---- ambience.wav : the cave bed -------------------------------------
DUR = 16.0
n = int(DUR * SR)
t = np.arange(n) / SR

# Brown-noise rumble, heavily low-passed; two slow integer-cycle LFOs so
# the swell breathes but the seam still matches.
rumble = lowpass(rng.standard_normal(n), 0.015)
rumble = lowpass(rumble, 0.03)
swell = 0.72 + 0.20 * np.sin(2 * np.pi * 3 * t / DUR) \
             + 0.08 * np.sin(2 * np.pi * 5 * t / DUR + 1.3)
rumble = normalize(rumble * swell, 1.0)

# Faint cave "air": band-limited noise an octave up, much quieter.
air = lowpass(rng.standard_normal(n), 0.12) - lowpass(rng.standard_normal(n), 0.02)
air = normalize(air, 1.0) * 0.10 * (0.8 + 0.2 * np.sin(2 * np.pi * 2 * t / DUR))

bed = loopify(rumble + air)

# Sparse drips, kept clear of the crossfaded seam.
amb = bed.copy()
for when, f0, gain in [(2.1, 1250, 0.30), (5.8, 1650, 0.22),
                       (9.3, 980, 0.28), (12.6, 1450, 0.18)]:
    d = drip(f0=f0)
    i = int(when * SR)
    j = min(len(amb), i + len(d))
    amb[i:j] += d[: j - i] * gain
write("ambience.wav", normalize(amb, 0.62))

# ---- amb_ice.wav : crystalline shimmer -------------------------------
DUR = 8.0
n = int(DUR * SR)
t = np.arange(n) / SR
shimmer = np.zeros(n)
# Detuned glassy partials, each amplitude-modulated by an integer-cycle LFO.
for k, (f, cyc, g) in enumerate([(2093, 2, 0.30), (2637, 3, 0.22),
                                 (3136, 5, 0.18), (4186, 7, 0.10)]):
    am = 0.5 * (1 + np.sin(2 * np.pi * cyc * t / DUR + k * 1.7))
    shimmer += np.sin(2 * np.pi * f * t + k) * am ** 2 * g
# High glints: sparse filtered noise.
glint = rng.standard_normal(n)
glint = glint - lowpass(glint, 0.4)          # high-pass
gate = np.clip(np.sin(2 * np.pi * 4 * t / DUR) - 0.75, 0, None) * 4
shimmer += glint * gate * 0.12
write("amb_ice.wav", normalize(loopify(shimmer, 0.4), 0.5))

# ---- amb_steam.wav : soft hiss ---------------------------------------
DUR = 6.0
n = int(DUR * SR)
t = np.arange(n) / SR
hiss = lowpass(rng.standard_normal(n), 0.35) - lowpass(rng.standard_normal(n), 0.08)
mod = 0.75 + 0.25 * np.sin(2 * np.pi * 2 * t / DUR)
write("amb_steam.wav", normalize(loopify(hiss * mod, 0.4), 0.42))
