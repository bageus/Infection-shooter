#!/usr/bin/env python3
"""Rebuild destruction/weapon handling cues from the project's licensed Oggs.

Uses the same numpy/scipy/ffmpeg toolchain as build_weapon_sounds.py.
Source attribution and inherited licences are in assets/audio/CREDITS.md.
"""
from pathlib import Path
import subprocess
import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parents[1] / 'assets/audio/sfx'
RATE = 44100
RECIPES = {
    'break_wood': [('hit_wood', 0, 1.0), ('hit_wood', .075, .65), ('fall_wood', .14, .8)],
    'break_furniture': [('hit_wood', 0, 1.0), ('hit_metal', .04, .45), ('fall_wood', .12, .8), ('fall_debris', .22, .6)],
    'break_cardboard': [('hit_paper', 0, 1.0), ('hit_paper', .09, .75), ('fall_light', .19, .6)],
    'break_metal': [('hit_metal', 0, 1.0), ('fall_metal', .08, .8), ('fall_debris', .24, .45)],
    'break_electronics': [('hit_electronics', 0, 1.0), ('hit_metal', .035, .5), ('glass_break', .075, .32), ('fall_tech', .16, .7)],
    'break_lamp': [('hit_glass', 0, .8), ('glass_break', .03, .65), ('hit_electronics', .04, .5), ('fall_metal', .12, .35)],
    'weapon_switch': [('weapon_pickup', 0, .65), ('dry_fire', .10, .4)],
}


def decode(event, variant):
    files = sorted((ROOT / event).glob('*.ogg'))
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(files[variant % len(files)]),
                          '-f', 'f32le', '-ac', '1', '-ar', str(RATE), '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def build(event, variant):
    length = .32 if event == 'weapon_switch' else 1.35
    output = np.zeros(round(RATE * length))
    for source, delay, gain in RECIPES[event]:
        x = decode(source, variant)
        # Slight varispeed between authored variants; runtime adds subtle jitter.
        x = signal.resample_poly(x, 100, 96 + variant * 4)
        if event == 'weapon_switch':
            x = x[:round(RATE * .20)]
        else:
            x = x[:round(RATE * 1.0)]
        fade = min(round(RATE * .035), len(x) // 2)
        x[:fade] *= np.linspace(0, 1, fade)
        x[-fade:] *= np.linspace(1, 0, fade)
        start = round(RATE * delay)
        count = min(len(x), len(output) - start)
        output[start:start + count] += x[:count] * gain
    output = signal.sosfilt(signal.butter(2, 65, 'highpass', fs=RATE, output='sos'), output)
    output *= .78 / max(np.max(np.abs(output)), .001)
    if event == 'weapon_switch':
        output *= .5
    output[-round(RATE * .06):] *= np.linspace(1, 0, round(RATE * .06))
    directory = ROOT / event
    directory.mkdir(exist_ok=True)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(RATE), '-ac', '1',
                    '-i', '-', '-c:a', 'libvorbis', '-q:a', '5', str(directory / f'{event}_{variant+1}.ogg')],
                   input=output.astype(np.float32).tobytes(), check=True)


if __name__ == '__main__':
    for event in RECIPES:
        for variant in range(2 if event in ['break_lamp', 'weapon_switch'] else 3):
            build(event, variant)
