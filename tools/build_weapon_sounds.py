#!/usr/bin/env python3
"""Build per-weapon fire variants, the minigun spin loop and pickup sounds.

  python tools/build_weapon_sounds.py [--only event,event]

AK, M4, sniper and minigun get their own events, derived from the rifle and
assault-rifle recordings already in assets/audio/sfx (their licences carry over,
see assets/audio/CREDITS.md). The minigun spin-up is synthesised. Every output
is level matched to its source and written as Ogg Vorbis (needs numpy, scipy, ffmpeg).
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
ROOT = Path(__file__).resolve().parents[1]
SFX = ROOT / "assets" / "audio" / "sfx"
RNG = np.random.default_rng(2026)


def decode(path: Path) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
        capture_output=True, check=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x * x)) + 1e-9)


def match_level(x: np.ndarray, reference: np.ndarray) -> np.ndarray:
    return x * (rms(reference) / rms(x))


def fade(x: np.ndarray, ms_in: float = 2.0, ms_out: float = 30.0) -> np.ndarray:
    n_in = int(SR * ms_in / 1000)
    n_out = int(SR * ms_out / 1000)
    x = x.copy()
    x[:n_in] *= np.linspace(0, 1, n_in)
    x[-n_out:] *= np.linspace(1, 0, n_out)
    return x


def resample_speed(x: np.ndarray, factor: float) -> np.ndarray:
    # factor > 1 plays faster and higher; the output keeps the original sample rate.
    return signal.resample(x, int(len(x) / factor))


def sources(event: str) -> list[np.ndarray]:
    return [decode(p) for p in sorted((SFX / event).glob("*.ogg"))]


def variants_of(source: str, transform) -> list[np.ndarray]:
    result = []
    for x in sources(source):
        y = transform(x)
        result.append(match_level(fade(y), x))
    return result


def sos_filter(x: np.ndarray, kind: str, hz: float, order: int = 2) -> np.ndarray:
    sos = signal.butter(order, hz, kind, fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def peak_boost(x: np.ndarray, hz: float, gain_db: float, q: float = 1.0) -> np.ndarray:
    b, a = signal.iirpeak(hz, q, fs=SR)
    return x + signal.lfilter(b, a, x) * (10 ** (gain_db / 20) - 1)


def ak(x: np.ndarray) -> np.ndarray:
    # Heavier and harsher: mid crack, a touch of drive.
    y = peak_boost(x, 2600, 4.0, 1.2)
    y = np.tanh(y * 1.6) / np.tanh(1.6)
    return sos_filter(y, "highpass", 70)




def sniper(x: np.ndarray) -> np.ndarray:
    # Lower, longer crack with a boom and a short echoed tail.
    y = resample_speed(x, 0.86)
    boom = sos_filter(y, "lowpass", 140, 3) * 1.2
    body = sos_filter(y, "highpass", 90)
    tail = np.zeros(int(SR * 0.7))
    tail[: len(body)] += body
    out = np.zeros(len(tail) + len(boom))
    out[: len(boom)] += boom
    out[: len(tail)] += tail * 0.5
    delay = int(SR * 0.17)
    for k in range(1, 4):
        out[k * delay: k * delay + len(tail)] += tail[: len(out) - k * delay] * (0.35 ** k)
    return out




def write_ogg(out: Path, x: np.ndarray) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    peak = float(np.max(np.abs(x)) + 1e-9)
    if peak > 0.95:
        x = x * (0.95 / peak)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "in.f32"
        wav.write_bytes(x.astype(np.float32).tobytes())
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", str(wav),
             "-c:a", "libvorbis", "-q:a", "5", str(out)],
            check=True,
        )


def envelope(n: int, decay: float) -> np.ndarray:
    return np.exp(-np.arange(n) / SR / decay)


def bandnoise(n: int, lo: float, hi: float) -> np.ndarray:
    return signal.lfilter(*signal.butter(2, [lo, hi], "bandpass", fs=SR), RNG.standard_normal(n))


def minigun_shot() -> np.ndarray:
    # Heavy aviation-style burst: deep thump, sharp breech crack and a mechanical clack.
    n = int(SR * 0.14)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * (110 - 40 * t / 0.14) * t) * envelope(n, 0.03)
    crack = bandnoise(n, 1500, 6000) * envelope(n, 0.018)
    clack = np.zeros(n)
    for offset in (0.0, 0.011):
        i = int(offset * SR)
        clack[i: i + 300] += RNG.standard_normal(min(300, n - i)) * np.linspace(1, 0, min(300, n - i))
    return fade(thump * 0.9 + crack * 0.8 + clack * 0.4, 0.5, 20.0)


def m4_shot() -> np.ndarray:
    # Sharp 5.56 crack with a short, light body.
    n = int(SR * 0.13)
    t = np.arange(n) / SR
    crack = bandnoise(n, 2000, 8000) * envelope(n, 0.014)
    body = np.sin(2 * np.pi * (200 - 80 * t / 0.13) * t) * envelope(n, 0.045)
    return fade(crack * 1.0 + body * 0.45, 0.3, 20.0)


def minigun_spin_loop() -> np.ndarray:
    # 2 s steady whine with ticks and a slight tremolo; the ends are crossfaded so it loops cleanly.
    n = int(SR * 2.0)
    t = np.arange(n) / SR
    whine = sum(np.sin(2 * np.pi * 190 * k * t) / k for k in (1, 2, 3, 4))
    tremolo = 0.9 + 0.1 * np.sin(2 * np.pi * 9 * t)
    ticks = np.zeros(n)
    step = int(SR / 30)
    ticks[::step] = 1.0
    ticks = signal.lfilter(*signal.butter(2, 2500, "highpass", fs=SR), ticks)
    y = whine * tremolo * 0.6 + bandnoise(n, 800, 4000) * 0.25 + ticks * 0.3
    fade_len = int(SR * 0.2)
    ramp = np.linspace(0, 1, fade_len)
    y[:fade_len] = y[:fade_len] * ramp + y[-fade_len:] * (1 - ramp)
    return y[:-fade_len]


def key_pickup(variant: int) -> np.ndarray:
    # Brass key rattle: three inharmonic metal partials struck in quick succession.
    n = int(SR * 0.5)
    out = np.zeros(n)
    partials = [(1137, 0.12), (2760, 0.09), (5410, 0.05)]
    for index, start in enumerate([0.0, 0.07, 0.15]):
        i = int(start * SR) + variant * 37
        length = n - i
        t = np.arange(length) / SR
        strike = sum(np.sin(2 * np.pi * f * (1 + 0.004 * index) * t) * a for f, a in partials)
        out[i:] += strike * envelope(length, 0.09 - 0.02 * index)
    out += bandnoise(n, 2000, 7000) * envelope(n, 0.01) * 0.6
    return fade(out, 1.0, 40.0)


def dna_pickup(variant: int) -> np.ndarray:
    # Warm organic pulse: a rising glide with vibrato over a soft body and a wet pop.
    n = int(SR * 0.45)
    t = np.arange(n) / SR
    freq = 260 + 420 * (t / t[-1]) ** 0.7 + 6 * np.sin(2 * np.pi * (6 + variant) * t)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    tone = sum(np.sin(k * phase) / k ** 1.4 for k in (1, 2, 3))
    body = np.sin(2 * np.pi * 150 * t) * envelope(n, 0.12) * 0.7
    pop = bandnoise(n, 400, 1800) * envelope(n, 0.02) * 0.35
    return fade(tone * envelope(n, 0.22) + body + pop, 4.0, 60.0)


SOURCED = {
    "ak_fire": ("rifle_fire", ak),
    "sniper_fire": ("rifle_fire", sniper),
}

EVENTS = {
    "minigun_fire": (None, minigun_shot),
    "m4_fire": (None, m4_shot),
}


def main(argv: list[str]) -> int:
    only = None
    if "--only" in argv:
        only = set(argv[argv.index("--only") + 1].split(","))
    for event, (source, transform) in SOURCED.items():
        if only and event not in only:
            continue
        clips = variants_of(source, transform)
        for index, clip in enumerate(clips, start=1):
            write_ogg(SFX / event / f"{event}_{index}.ogg", clip)
        print(f"{event}: {len(clips)} variants from {source}")
    for event, (_, make) in EVENTS.items():
        if only and event not in only:
            continue
        for variant in (1, 2, 3):
            write_ogg(SFX / event / f"{event}_{variant}.ogg", make())
        print(f"{event}: 3 variants (synthesised)")
    if not only or "minigun_spin" in only:
        write_ogg(SFX / "minigun_spin" / "minigun_spin_1.ogg", minigun_spin_loop())
        print("minigun_spin: 1 looping variant (synthesised)")
    for event, make in (("key_pickup", key_pickup), ("dna_pickup", dna_pickup)):
        if only and event not in only:
            continue
        for variant in (1, 2):
            write_ogg(SFX / event / f"{event}_{variant}.ogg", make(variant))
        print(f"{event}: 2 variants (synthesised)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
