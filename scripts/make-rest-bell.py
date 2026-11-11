#!/usr/bin/env python3
# Usage: scripts/make-rest-bell.py App/iOS/RestBell.wav
"""Synthesizes a boxing/wrestling ring bell: three quick strikes on a brass dome."""
import math, random, struct, sys, wave

RATE = 44100
LENGTH = 2.6
STRIKES = [0.0, 0.22, 0.44]          # ding-ding-ding
# Inharmonic partials of a struck dome bell (frequency Hz, level, decay per second).
PARTIALS = [(720, 1.0, 2.2), (1680, 0.55, 3.0), (2990, 0.38, 4.5), (4470, 0.22, 6.5), (6150, 0.12, 9.0)]
random.seed(7)

n = int(RATE * LENGTH)
out = [0.0] * n
for k, t0 in enumerate(STRIKES):
    level = 1.0 if k < len(STRIKES) - 1 else 1.1      # the last strike rings longest
    start = int(t0 * RATE)
    for i in range(start, n):
        t = (i - start) / RATE
        v = 0.0
        for f, a, d in PARTIALS:
            # A slight detune pair per partial gives the shimmer of real brass.
            v += a * math.exp(-d * t) * (math.sin(2 * math.pi * f * t) + 0.5 * math.sin(2 * math.pi * f * 1.003 * t))
        if t < 0.004:                                   # the hammer's click
            v += (random.random() * 2 - 1) * 0.8 * (1 - t / 0.004)
        out[i] += level * v * min(1.0, t / 0.0008)      # no pop at the onset

peak = max(abs(x) for x in out)
gain = 0.7 / peak                                       # about -3 dBFS
tail = int(0.15 * RATE)
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
    frames = bytearray()
    for i, x in enumerate(out):
        fade = min(1.0, (n - i) / tail)
        frames += struct.pack("<h", int(max(-1, min(1, x * gain * fade)) * 32767))
    w.writeframes(bytes(frames))
