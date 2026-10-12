#!/usr/bin/env python3
"""Synthesises the looping vitals sounds: heavy breathing and mutagen pressure.

Output: assets/audio/vitals/heavy_breathing.ogg, mutagen_pressure.ogg (needs ffmpeg).
Both loops are built from whole cycles so they repeat without a click.
"""
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "vitals"
rng = np.random.default_rng(7)


def bandpass(noise: np.ndarray, low: float, high: float) -> np.ndarray:
    spectrum = np.fft.rfft(noise)
    freqs = np.fft.rfftfreq(len(noise), 1.0 / RATE)
    gain = np.clip((freqs - low) / (low * 0.5 + 1), 0, 1) * np.clip((high - freqs) / (high * 0.5), 0, 1)
    return np.fft.irfft(spectrum * gain, len(noise))


def normalise(signal: np.ndarray, peak: float) -> np.ndarray:
    return signal / np.max(np.abs(signal)) * peak


def breath(length: float) -> np.ndarray:
    t = np.linspace(0.0, 1.0, int(RATE * length), endpoint=False)
    noise = rng.standard_normal(len(t))
    # Inhale rises and is a little brighter, exhale is longer and rasps lower.
    inhale = np.sin(np.pi * np.clip(t / 0.4, 0, 1)) ** 2 * (t < 0.4)
    exhale = np.sin(np.pi * np.clip((t - 0.45) / 0.55, 0, 1)) ** 1.5 * (t >= 0.45)
    air = bandpass(noise, 350, 3200) * inhale * 0.8 + bandpass(noise, 200, 1800) * exhale
    rasp = bandpass(rng.standard_normal(len(t)), 1800, 5200) * (inhale * 0.25 + exhale * 0.15)
    return air + rasp


def heavy_breathing() -> np.ndarray:
    cycle = 2.4
    one = np.concatenate([breath(cycle), breath(cycle) * 0.9])
    fade = int(RATE * 0.02)
    one[:fade] *= np.linspace(0, 1, fade)
    one[-fade:] *= np.linspace(1, 0, fade)
    return normalise(one, 0.8)


def mutagen_pressure() -> np.ndarray:
    length = 6.0
    t = np.arange(int(RATE * length)) / RATE
    # Frequencies are multiples of 1/length so the loop closes exactly.
    low = np.sin(2 * np.pi * 54.0 * t) + 0.6 * np.sin(2 * np.pi * 54.5 * t) + 0.35 * np.sin(2 * np.pi * 108.0 * t)
    swell = 0.65 + 0.35 * np.sin(2 * np.pi * (1 / length) * 2 * t)
    ring = np.sin(2 * np.pi * 3996.0 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * (1 / length) * 3 * t))
    ring += 0.5 * np.sin(2 * np.pi * 5004.0 * t)
    hiss = bandpass(rng.standard_normal(len(t)), 120, 700)
    return normalise(low * swell * 0.7 + ring * 0.07 + hiss * 0.12, 0.8)


def encode(name: str, signal: np.ndarray) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(signal, -1, 1) * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / f"{name}.wav"
        with wave.open(str(wav_path), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(RATE)
            wav.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "3", str(OUT / f"{name}.ogg")], check=True)


if __name__ == "__main__":
    encode("heavy_breathing", heavy_breathing())
    encode("mutagen_pressure", mutagen_pressure())
