#!/usr/bin/env python3
"""Rebuild original CC0 interface cues as OGG/Vorbis (requires ffmpeg)."""
import math
import random
import struct
import subprocess
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
    encode(OUT / (name + '.ogg'), bytes(data))


def encode(path, data, loop=False):
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 's16le', '-ar', str(RATE),
                    '-ac', '1', '-i', '-', '-c:a', 'libvorbis', '-q:a', '5', str(path)],
                   input=data, check=True)
    from build_added_audio import import_settings
    import_settings(path, loop)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Two whole tones (4 semitones) above the original 430-610 Hz chirp: a brighter sci-fi tick.
    up = 2 ** (4 / 12)
    save('menu_hover', cue(0.055, 430 * up, 610 * up, 0.15))
    save('mutation_hover', cue(0.075, 900, 1250, 0.06))
    save('mutation_click', cue(0.10, 320, 95, 0.25))
    opening = cue(0.28, 180, 1150, 0.10)
    save('mutation_open', opening)
    save('mutation_close', list(reversed(opening)))
    lock = cue(0.055, 650, 650) + [0.0] * 220 + cue(0.085, 1050, 1050)
    save('mutation_lock', lock)
    save('mutation_unlock', list(reversed(lock)))
    # Locked door: two handle rattles, then the latch thunking into the frame.
    rattle = cue(0.045, 1500, 1150, 0.5) + [0.0] * 500 + cue(0.04, 1500, 1100, 0.5)
    save('door_locked', rattle + [0.0] * 300 + cue(0.16, 150, 95, 0.35))
    click = [int(math.sin(math.tau * (270 * (i / RATE) - 625 * (i / RATE)**2))
                 * math.exp(-(i / RATE) * 60) * 16000) for i in range(2205)]
    encode(OUT / 'menu_click.ogg', struct.pack('<' + 'h' * len(click), *click))
    ringing = [round((0.75 * math.sin(i * math.tau * 2800 / RATE)
                      + 0.25 * math.sin(i * math.tau * 3200 / RATE)) * 2200)
               for i in range(11025)]
    encode(OUT.parent / 'vitals/blast_ringing.ogg',
           struct.pack('<' + 'h' * len(ringing), *ringing), loop=True)


if __name__ == '__main__':
    main()
