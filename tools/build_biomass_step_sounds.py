#!/usr/bin/env python3
"""Synthesises the wet footstep on floor biomass (a squelch with a short suck).

Output: assets/audio/sfx/biomass/step_biomass_1..4.ogg (needs ffmpeg).
"""
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx" / "biomass"
rng = np.random.default_rng(11)


def bandpass(noise: np.ndarray, low: float, high: float) -> np.ndarray:
    spectrum = np.fft.rfft(noise)
    freqs = np.fft.rfftfreq(len(noise), 1.0 / RATE)
    gain = np.clip((freqs - low) / (low * 0.5 + 1), 0, 1) * np.clip((high - freqs) / (high * 0.5), 0, 1)
    return np.fft.irfft(spectrum * gain, len(noise))


def squelch(index: int) -> np.ndarray:
    length = 0.34 + 0.03 * index
    t = np.linspace(0.0, length, int(RATE * length), endpoint=False)
    squash = bandpass(rng.standard_normal(len(t)), 120, 900) * np.exp(-t * 18.0)
    # Bubbling sweep as the foot pulls off the wet mass.
    start = 0.07 + 0.01 * index
    sweep = np.sin(2 * np.pi * np.cumsum(260.0 + 1400.0 * np.clip((t - start) / 0.18, 0, 1)) / RATE)
    pull = sweep * np.clip((t - start) / 0.02, 0, 1) * np.exp(-np.clip(t - start, 0, None) * 14.0) * (t >= start) * 0.35
    wet = bandpass(rng.standard_normal(len(t)), 1500, 5200) * np.exp(-t * 28.0) * 0.25
    out = squash + pull + wet
    return out / np.max(np.abs(out)) * 0.8


for i in range(1, 5):
    OUT.mkdir(parents=True, exist_ok=True)
    pcm = (squelch(i) * 32767).astype(np.int16)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "step.wav"
        with wave.open(str(wav), "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(RATE)
            handle.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "4", str(OUT / f"step_biomass_{i}.ogg")], check=True)
