#!/usr/bin/env python3
"""Build per-weapon fire variants and the minigun spin-up from the existing sfx.

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


def m4(x: np.ndarray) -> np.ndarray:
    # Tighter and brighter, slightly faster report.
    y = resample_speed(x, 1.04)
    y = peak_boost(y, 4200, 3.0, 1.0)
    return sos_filter(y, "highpass", 130)


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


def minigun(x: np.ndarray) -> np.ndarray:
    # Short, rattling bursts: quicker, cleaner, with a light flutter.
    y = resample_speed(x, 1.12)[: int(SR * 0.09)]
    y = sos_filter(y, "highpass", 180)
    t = np.arange(len(y)) / SR
    flutter = 0.82 + 0.18 * np.sin(2 * np.pi * 38 * t)
    return y * flutter


def spin_up() -> np.ndarray:
    # 1.1 s whine: pitch and noise rise as the barrels reach speed, then fade out.
    n = int(SR * 1.1)
    t = np.arange(n) / SR
    progress = (t / t[-1]) ** 1.6
    freq = 150 + 430 * progress
    phase = 2 * np.pi * np.cumsum(freq) / SR
    whine = sum(np.sin(k * phase) / k for k in range(1, 5))
    noise = signal.lfilter(*signal.butter(2, [900, 4200], "bandpass", fs=SR), RNG.standard_normal(n))
    clicks = np.zeros(n)
    rate = 18 + 60 * progress
    tick_at = np.cumsum(rate) / SR
    for when in tick_at[tick_at < t[-1]]:
        clicks[int(when * SR)] = 1.0
    clicks = signal.lfilter(*signal.butter(2, 1800, "highpass", fs=SR), clicks)
    envelope = np.minimum(1.0, t / 0.25) * (0.35 + 0.65 * progress) * np.clip((t[-1] - t) / 0.12, 0, 1)
    y = whine * 0.7 + noise * (0.15 + 0.4 * progress) + clicks * 0.25
    return fade(y * envelope, 5.0, 40.0)


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


EVENTS = {
    "ak_fire": ("rifle_fire", ak),
    "m4_fire": ("assault_rifle_fire", m4),
    "sniper_fire": ("rifle_fire", sniper),
    "minigun_fire": ("assault_rifle_fire", minigun),
}


def main(argv: list[str]) -> int:
    only = None
    if "--only" in argv:
        only = set(argv[argv.index("--only") + 1].split(","))
    for event, (source, transform) in EVENTS.items():
        if only and event not in only:
            continue
        clips = variants_of(source, transform)
        for index, clip in enumerate(clips, start=1):
            write_ogg(SFX / event / f"{event}_{index}.ogg", clip)
        print(f"{event}: {len(clips)} variants from {source}")
    if not only or "minigun_spinup" in only:
        write_ogg(SFX / "minigun_spinup" / "minigun_spinup_1.ogg", spin_up())
        print("minigun_spinup: 1 variant (synthesised)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
