#!/usr/bin/env python3
"""Rebuild original CC0 interface cues as text Godot WAV resources (stdlib only)."""
import math
import random
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / 'assets/audio/ui'


def cue(length, start, finish, noise=0.0):
    rng = random.Random(22)
    samples = []
    for index in range(round(length * RATE)):
        t = index / RATE
        phase = math.tau * (start * t + (finish - start) * t * t / (2 * length))
        envelope = min(1.0, t / 0.004) * math.exp(-t * 5 / length)
        samples.append((math.sin(phase) + noise * rng.uniform(-1, 1)) * envelope)
    return samples


def save(name, samples):
    peak = max(abs(x) for x in samples) or 1.0
    data = []
    for sample in samples:
        value = round(sample / peak * 8191)
        data.extend([value & 255, (value >> 8) & 255])
    text = '[gd_resource type="AudioStreamWAV" format=3]\n\n[resource]\n'
    text += 'format = 1\nmix_rate = 22050\nstereo = false\n'
    text += 'data = PackedByteArray(' + ', '.join(map(str, data)) + ')\n'
    (OUT / (name + '.tres')).write_text(text)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Two whole tones (4 semitones) above the original 430-610 Hz chirp: a brighter sci-fi tick.
    up = 2 ** (4 / 12)
    save('menu_hover', cue(0.055, 430 * up, 610 * up, 0.15))
    save('mutation_hover', cue(0.075, 900, 1250, 0.06))
    save('mutation_click', cue(0.10, 320, 95, 0.25))
    lock = cue(0.055, 650, 650) + [0.0] * 220 + cue(0.085, 1050, 1050)
    save('mutation_lock', lock)
    save('mutation_unlock', list(reversed(lock)))


if __name__ == '__main__':
    main()
