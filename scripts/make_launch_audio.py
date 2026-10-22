#!/usr/bin/env python3
"""Generate Clementine's original, deterministic 20-second launch score."""
import math, struct, wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'brag-output/composition/assets/audio'
RATE = 44100

def write(name, values):
    peak = max(max(abs(v) for v in values), 1e-9)
    with wave.open(str(OUT / name), 'wb') as f:
        f.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        f.writeframes(b''.join(struct.pack('<h', round(v / peak * 26000)) for v in values))

def note(t, frequency, decay):
    return (math.sin(2 * math.pi * frequency * t) + .22 * math.sin(4 * math.pi * frequency * t)) * math.exp(-t / decay) * min(1, t / .012)

OUT.mkdir(parents=True, exist_ok=True)
score = []
beat = 60 / 112
chords = [(130.81, 164.81, 196), (110, 130.81, 164.81), (87.31, 130.81, 174.61), (98, 146.83, 196)]
for i in range(RATE * 20):
    t = i / RATE
    chord = chords[min(3, int(t / (8 * beat)))]
    step = int(t / beat)
    age = t - step * beat
    v = .13 * note(age, chord[step % 3] * 4, .24)
    v += .15 * note(age, chord[0], .16)
    for frequency in chord:
        v += .026 * math.sin(2 * math.pi * frequency * t) * (.8 + .2 * math.sin(2 * math.pi * .16 * t))
    v *= min(1, t / .6, (20 - t) / 1.5)
    score.append(v)
write('citrus-score.wav', score)
write('tap.wav', [.28 * note(i / RATE, 240, .025) for i in range(int(RATE * .14))])
write('done.wav', [sum(.13 * note(max(0, i / RATE - delay), f, .16) if i / RATE >= delay else 0 for delay, f in [(0, 659.25), (.1, 783.99)]) for i in range(int(RATE * .55))])
print('Wrote original score and interaction sounds')
