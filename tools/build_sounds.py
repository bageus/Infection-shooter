#!/usr/bin/env python3
"""Build the game's sound effects from openly licensed source recordings.

Sources (clone them, then pass their parent folder):
  git clone https://github.com/Fris0uman/CDDA-Soundpacks cdda          (CC0 / CC-BY, per-file credits)
  git clone https://github.com/redeclipse/sounds redeclipse_sounds     (CC-BY-SA 4.0)

  python tools/build_sounds.py /path/to/sources [--only event,event]

Every recording is decoded to mono 44.1 kHz, cut to its useful part, cleaned
(DC/rumble removal, noise-floor gate, click-free fades), level matched per
category and soft limited, then varied (speed/pitch, tone) so repeated events
do not sound identical. Results are written as Ogg Vorbis to
assets/audio/sfx/<event>/<event>_<n>.ogg together with assets/audio/CREDITS.md.
Requires numpy, scipy and ffmpeg (libvorbis).
"""
from __future__ import annotations

import math
import re
import shutil
import subprocess
import sys
from fractions import Fraction
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio" / "sfx"
CDDA = "cdda/sound/CC-Sounds"
RE = "redeclipse_sounds"
RNG = np.random.default_rng(1977)

# Loudness targets: RMS of the loudest 50 ms window, dBFS.
LEVEL = {
    "gun": -9.0, "explosion": -8.0, "reload": -19.0, "casing": -23.0, "pickup": -17.0,
    "step": -22.0, "impact": -17.0, "glass": -14.0, "door": -18.0, "vocal": -15.0,
    "flesh": -15.0, "gore": -13.0, "fall": -18.0, "slam": -9.0, "spray": -17.0,
    "skill": -13.0, "field": -21.0,
}


# --------------------------------------------------------------------------- dsp

class Sound:
    def __init__(self, data: np.ndarray, sources: list[str]):
        self.x = data.astype(np.float64)
        self.sources = sources

    def copy(self) -> "Sound":
        return Sound(self.x.copy(), list(self.sources))


def load(base: Path, rel: str, start: float = 0.0, end: float | None = None) -> Sound:
    path = base / rel
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
        capture_output=True, check=True,
    ).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    a = int(start * SR)
    b = len(x) if end is None else int(end * SR)
    return Sound(x[a:b], [rel])


def silence(seconds: float) -> Sound:
    return Sound(np.zeros(int(seconds * SR)), [])


def highpass(s: Sound, hz: float, order: int = 4) -> Sound:
    sos = signal.butter(order, hz, "highpass", fs=SR, output="sos")
    s.x = signal.sosfilt(sos, s.x)
    return s


def lowpass(s: Sound, hz: float, order: int = 4) -> Sound:
    sos = signal.butter(order, min(hz, SR * 0.45), "lowpass", fs=SR, output="sos")
    s.x = signal.sosfilt(sos, s.x)
    return s


def tilt(s: Sound, low_db: float = 0.0, high_db: float = 0.0, split: float = 1200.0) -> Sound:
    """Gentle tone shaping: shelves below/above `split`."""
    low = signal.sosfilt(signal.butter(2, split, "lowpass", fs=SR, output="sos"), s.x)
    high = s.x - low
    s.x = low * 10 ** (low_db / 20) + high * 10 ** (high_db / 20)
    return s


def speed(s: Sound, ratio: float) -> Sound:
    """Varispeed: >1 is higher and shorter, like a lighter object."""
    if abs(ratio - 1.0) < 1e-4:
        return s
    frac = Fraction(ratio).limit_denominator(200)
    s.x = signal.resample_poly(s.x, frac.denominator, frac.numerator)
    return s


def gain(s: Sound, db: float) -> Sound:
    s.x = s.x * 10 ** (db / 20)
    return s


def envelope(x: np.ndarray, ms: float = 5.0) -> np.ndarray:
    n = max(1, int(SR * ms / 1000))
    return np.sqrt(np.convolve(x * x, np.ones(n) / n, mode="same") + 1e-12)


def trim(s: Sound, threshold_db: float = -48.0, pre_ms: float = 3.0, lead_db: float = -28.0) -> Sound:
    """Starts right before the first strong transient (no latency) and drops
    the trailing silence below `threshold_db` relative to the peak."""
    env = envelope(s.x, 2.0)
    peak = env.max()
    lead = np.where(env > peak * 10 ** (lead_db / 20))[0]
    tail = np.where(env > peak * 10 ** (threshold_db / 20))[0]
    if len(lead) and len(tail):
        a = max(0, lead[0] - int(SR * pre_ms / 1000))
        s.x = s.x[a: tail[-1] + 1]
    return s


def gate(s: Sound, floor_db: float = -42.0, release_ms: float = 60.0) -> Sound:
    """Smoothly removes the recording's noise floor once the sound decays."""
    env = envelope(s.x, 10.0)
    ref = env.max()
    level = 20 * np.log10(env / ref + 1e-12)
    g = np.clip((level - floor_db) / 12.0, 0.0, 1.0)
    alpha = 1.0 / max(1.0, SR * release_ms / 1000)
    smooth = signal.lfilter([alpha], [1, -(1 - alpha)], g)
    s.x = s.x * np.maximum(smooth, g * 0.0)
    return s


def fade(s: Sound, in_ms: float = 2.0, out_ms: float = 30.0) -> Sound:
    n_in = min(len(s.x), int(SR * in_ms / 1000))
    n_out = min(len(s.x), int(SR * out_ms / 1000))
    if n_in:
        s.x[:n_in] *= np.linspace(0, 1, n_in) ** 2
    if n_out:
        s.x[-n_out:] *= np.linspace(1, 0, n_out) ** 2
    return s


def decay_after(s: Sound, start: float, length: float) -> Sound:
    """Exponential tail from `start` seconds, fully faded after `length` more."""
    a = int(start * SR)
    if a >= len(s.x):
        return s
    t = np.arange(len(s.x) - a) / SR
    curve = np.exp(-5.0 * t / max(length, 0.01))
    curve[t > length] = 0.0
    s.x[a:] *= curve
    end = a + int(length * SR)
    s.x = s.x[: min(len(s.x), end)]
    return s


def cut(s: Sound, max_seconds: float, fade_ms: float = 40.0) -> Sound:
    if len(s.x) > max_seconds * SR:
        s.x = s.x[: int(max_seconds * SR)]
    return fade(s, 1.0, fade_ms)


def mix(*parts: tuple[Sound, float, float]) -> Sound:
    """Sum (sound, offset seconds, gain dB) layers."""
    length = max(int(off * SR) + len(snd.x) for snd, off, _ in parts)
    out = np.zeros(length)
    sources: list[str] = []
    for snd, off, db in parts:
        a = int(off * SR)
        out[a: a + len(snd.x)] += snd.x * 10 ** (db / 20)
        sources += snd.sources
    return Sound(out, sources)


def level(s: Sound, category: str, offset_db: float = 0.0) -> Sound:
    target = LEVEL[category] + offset_db
    n = int(SR * 0.05)
    if len(s.x) <= n:
        rms = math.sqrt(np.mean(s.x ** 2) + 1e-12)
    else:
        power = np.convolve(s.x * s.x, np.ones(n) / n, mode="valid")
        rms = math.sqrt(power.max() + 1e-12)
    s.x = s.x * (10 ** (target / 20) / rms)
    return limit(s)


def limit(s: Sound, ceiling_db: float = -1.0) -> Sound:
    """Soft knee limiter: transparent below the ceiling, no hard clipping."""
    c = 10 ** (ceiling_db / 20)
    s.x = np.where(np.abs(s.x) < c * 0.7, s.x, np.sign(s.x) * (c * 0.7 + c * 0.3 * np.tanh((np.abs(s.x) - c * 0.7) / (c * 0.3))))
    return s


def clean(s: Sound, hp: float = 35.0) -> Sound:
    s.x = s.x - np.mean(s.x)
    return highpass(s, hp, 2)


# ------------------------------------------------------------------ synthesis

def modal(freqs: list[float], decays: list[float], amps: list[float], seconds: float, click_ms: float = 2.0, rng=None) -> Sound:
    """Struck metal/glass: decaying partials plus a short noise click."""
    t = np.arange(int(seconds * SR)) / SR
    x = np.zeros_like(t)
    for f, d, a in zip(freqs, decays, amps):
        x += a * np.sin(2 * np.pi * f * t + (rng or RNG).uniform(0, 6.28)) * np.exp(-t / d)
    n = int(SR * click_ms / 1000)
    x[:n] += (rng or RNG).normal(0, 0.6, n) * np.linspace(1, 0, n)
    return Sound(x, ["synthesised"])


def noise_burst(seconds: float, low: float, high: float, attack_ms: float, decay: float, crackle: float = 0.0) -> Sound:
    t = np.arange(int(seconds * SR)) / SR
    x = RNG.normal(0, 1, len(t))
    sos = signal.butter(2, [low, high], "bandpass", fs=SR, output="sos")
    x = signal.sosfilt(sos, x)
    env = np.minimum(1.0, t / max(attack_ms / 1000, 1e-4)) * np.exp(-t / decay)
    if crackle > 0:
        grains = (RNG.random(len(t)) < crackle / SR * 1000).astype(float)
        grains = np.convolve(grains, np.hanning(int(SR * 0.004)), mode="same")
        env = env * (0.35 + grains)
    return Sound(x * env, ["synthesised"])


def onsets(s: Sound, threshold_db: float = -24.0, min_gap: float = 0.08) -> list[float]:
    env = envelope(s.x, 3.0)
    lvl = 20 * np.log10(env / env.max() + 1e-12)
    rising = np.where((lvl[1:] > threshold_db) & (lvl[:-1] <= threshold_db))[0]
    result: list[float] = []
    for i in rising:
        t = i / SR
        if not result or t - result[-1] >= min_gap:
            result.append(t)
    return result


# ------------------------------------------------------------------ recipes

def gunshot(base: Path, rel: str, length: float, tail: float, variants: list[tuple[float, float]], extra=None, hp: float = 45.0, start: float = 0.0) -> list[Sound]:
    out = []
    for ratio, bright in variants:
        s = load(base, rel, start)
        s = clean(trim(s, -40.0, 2.0, -16.0), hp)
        s = decay_after(s, length * 0.35, tail)
        s = cut(s, length, 25.0)
        s = tilt(speed(s, ratio), 0.0, bright)
        if extra is not None:
            s = extra(s)
        out.append(level(s, "gun"))
    return out


def take(base: Path, rel: str, category: str, start: float = 0.0, end: float | None = None, max_len: float = 2.0, ratio: float = 1.0,
         hp: float = 60.0, lp: float | None = None, gate_db: float | None = -44.0, offset_db: float = 0.0, fade_ms: float = 40.0) -> Sound:
    s = load(base, rel, start, end)
    s = clean(trim(s, -50.0), hp)
    if lp:
        s = lowpass(s, lp, 2)
    if gate_db is not None:
        s = gate(s, gate_db)
    s = trim(s, -55.0)
    s = cut(speed(s, ratio), max_len, fade_ms)
    return level(s, category, offset_db)


def split_hits(base: Path, rel: str, category: str, window: float, threshold_db: float = -22.0, limit_count: int = 6, **kw) -> list[Sound]:
    whole = load(base, rel)
    result = []
    for t in onsets(whole, threshold_db)[:limit_count]:
        result.append(take(base, rel, category, max(0.0, t - 0.004), t + window, **kw))
    return result


def recipes(base: Path) -> dict[str, list[Sound]]:
    C, R = CDDA, RE
    ev: dict[str, list[Sound]] = {}
    # ---- weapons
    ev["pistol_fire"] = gunshot(base, f"{C}/fire_gun/handguns/handgun_1.ogg", 0.75, 0.42, [(1.0, 0.0), (1.035, 0.8), (0.97, -0.8)])
    ev["shotgun_fire"] = gunshot(base, f"{C}/fire_gun/shotguns/shotgun_1.ogg", 1.25, 0.9, [(1.0, 0.0), (1.04, 0.6), (0.96, -0.6)], hp=38.0)
    ev["uzi_fire"] = gunshot(base, f"{C}/fire_gun/machineguns/machinegun_1.ogg", 0.42, 0.22, [(1.08, 1.0), (1.12, 0.4), (1.04, 1.5), (1.15, 0.0)])
    ev["rifle_fire"] = gunshot(base, f"{C}/fire_gun/rifles/rifle_1.ogg", 0.7, 0.45, [(1.0, 0.0), (0.97, -0.5), (1.03, 0.5)])
    ev["assault_rifle_fire"] = [s for i in (1, 2, 3) for s in gunshot(base, f"{C}/fire_gun/rifles/automatic_rifle/indoor_gunfire/556_auto_rifle_shot_0{i}.ogg", 0.48, 0.3, [(1.0, 0.0)])]
    ev["launcher_fire"] = gunshot(base, f"{C}/fire_gun/launchers/launcher_1.ogg", 0.6, 0.4, [(1.0, 0.0), (0.94, -1.0)], extra=lambda s: tilt(s, 2.0, 0.0, 300.0), hp=30.0)
    ev["dry_fire"] = [take(base, f"{C}/fire_gun/empty_1.ogg", "reload", max_len=0.3), take(base, f"{C}/fire_gun/empty.ogg", "reload", max_len=0.4)]
    # ---- explosions
    grenade = []
    for i, ratio in ((1, 1.0), (2, 0.92)):
        body = clean(trim(load(base, f"{C}/explosion/default/explosion_default_{i}.ogg"), -40.0), 28.0)
        rumble = lowpass(clean(load(base, f"{C}/explosion/huge/explosion_huge_2.ogg", 0.03, 2.4), 25.0), 260.0, 4)
        rumble = decay_after(rumble, 0.25, 1.9)
        s = mix((speed(body, ratio), 0.0, 0.0), (rumble, 0.0, -5.0))
        grenade.append(level(fade(decay_after(s, 0.6, 1.6), 1.0, 120.0), "explosion"))
    ev["grenade_explode"] = grenade
    extinguisher = []
    for ratio in (1.0, 1.08):
        pop = clean(trim(load(base, f"{C}/explosion/small/explosion_small.ogg"), -40.0), 40.0)
        hiss = highpass(clean(load(base, f"{R}/sfx/extinguish.ogg")), 900.0, 2)
        s = mix((speed(pop, ratio), 0.0, 0.0), (decay_after(hiss, 0.2, 1.4), 0.02, -7.0))
        extinguisher.append(level(fade(s, 1.0, 120.0), "explosion", -2.0))
    ev["extinguisher_burst"] = extinguisher
    # ---- reloads
    ev["pistol_reload"] = [take(base, f"{C}/reload/pocket_pistol/pocket_pistol_load_0{i}.ogg", "reload", max_len=1.4, gate_db=-46.0) for i in (1, 2, 4)]
    ev["uzi_reload"] = [take(base, f"{C}/reload/default.ogg", "reload", max_len=1.3, ratio=1.06), take(base, f"{R}/weapons/smg/reload.ogg", "reload", max_len=1.4, lp=9000.0)]
    ev["shotgun_shell_load"] = [take(base, f"{C}/reload/tube_fed_shotgun/shell_load_0{i}.ogg", "reload", max_len=0.75) for i in (1, 2, 3, 4)]
    ev["launcher_reload"] = [take(base, f"{C}/reload/mag_fed_bolt_action_rifle/bolt_action_rifle_load_0{i}.ogg", "reload", 0.0, None, max_len=2.2, ratio=0.86, hp=40.0) for i in (1, 3)]
    ev["rifle_reload"] = [take(base, f"{C}/reload/mag_fed_bolt_action_rifle/bolt_action_rifle_load_0{i}.ogg", "reload", max_len=1.9) for i in (2, 4)]
    # ---- casings
    brass = split_hits(base, f"{C}/fire_gun/brass_eject.ogg", "casing", 0.28, hp=900.0) + split_hits(base, f"{C}/fire_gun/brass_eject_1.ogg", "casing", 0.28, hp=900.0)
    brass += [take(base, f"{R}/sfx/shell{n}.ogg", "casing", hp=900.0, gate_db=None) for n in ("", "2", "3", "4")]
    ev["casing_brass"] = brass[:8]
    ev["casing_shell"] = [lowpass(take(base, f"{R}/sfx/shell{n}.ogg", "casing", ratio=0.62, hp=300.0, gate_db=None), 3500.0) for n in ("", "3", "5", "6")]
    ev["casing_shell"] = [level(s, "casing", -1.0) for s in ev["casing_shell"]]
    ev["casing_heavy"] = [take(base, f"{C}/smash_fail/metal/smash_fail_metal_{i}.ogg", "casing", 0.0, 0.3, ratio=1.25, hp=250.0, offset_db=2.0, fade_ms=90.0) for i in (1, 2, 4)]
    # ---- pickups and items
    ev["weapon_pickup"] = [mix((take(base, f"{C}/reload/pocket_pistol/pocket_pistol_load_03.ogg", "pickup", 1.15, 1.75, max_len=0.6), 0.0, 0.0), (take(base, f"{C}/plmove/clear_obstacle/clear_obstacle_2.ogg", "pickup", max_len=0.4, hp=200.0), 0.0, -9.0))]
    ev["weapon_pickup"] = [level(s, "pickup") for s in ev["weapon_pickup"]] + [take(base, f"{C}/reload/default.ogg", "pickup", 0.5, 1.1, max_len=0.6)]
    ev["ammo_pickup"] = [take(base, f"{C}/reload/pocket_pistol/pocket_pistol_load_0{i}.ogg", "pickup", 0.0, 0.55, max_len=0.5, offset_db=-2.0) for i in (1, 2)]
    case_click = take(base, f"{C}/smash_fail/plastic/smash_fail_plastic_2.ogg", "pickup", max_len=0.25)
    rustle = take(base, f"{C}/close_door/window/close_curtain.ogg", "pickup", max_len=0.6, hp=300.0)
    ev["medkit_pickup"] = [level(mix((case_click.copy(), 0.0, 0.0), (rustle.copy(), 0.06, -6.0)), "pickup")]
    tear = take(base, f"{C}/melee_swing/small_cutting/small_cutting_swing_2.ogg", "pickup", hp=700.0, max_len=0.35)
    ev["medkit_use"] = [level(mix((rustle.copy(), 0.0, -3.0), (tear.copy(), 0.25, 0.0), (case_click.copy(), 0.62, -5.0)), "pickup")]
    syringe_click = take(base, f"{C}/fire_gun/empty_1.ogg", "pickup", max_len=0.2, hp=600.0)
    puff = take(base, f"{R}/sfx/extinguish.ogg", "pickup", max_len=0.45, hp=2500.0, gate_db=None, fade_ms=200.0)
    ev["antidote_use"] = [level(mix((syringe_click, 0.0, -2.0), (puff, 0.05, -7.0)), "pickup", -2.0)]
    ev["antidote_pickup"] = [level(mix((take(base, f"{C}/smash_fail/glass/smash_fail_glass_1.ogg", "pickup", max_len=0.2, hp=1500.0), 0.0, -4.0), (case_click.copy(), 0.0, -6.0)), "pickup", -3.0)]
    keys = []
    for k in range(2):
        hits = [modal([2150 * f, 3870 * f, 5310 * f, 7400 * f], [0.09, 0.06, 0.04, 0.025], [1.0, 0.6, 0.35, 0.2], 0.4) for f in RNG.uniform(0.9, 1.25, 5)]
        keys.append(level(lowpass(mix(*[(h, 0.035 * i + RNG.uniform(0, 0.02), RNG.uniform(-6, 0)) for i, h in enumerate(hits)]), 11000.0), "pickup", -3.0))
    ev["key_pickup"] = keys
    ev["dna_pickup"] = [level(mix((take(base, f"{R}/sfx/itemuse.ogg", "pickup", 0.5, None, max_len=0.5, lp=7000.0), 0.0, -2.0), (take(base, f"{C}/melee_hit_flesh/small_stabbing/small_stabbing_flesh_{i}.ogg", "pickup", max_len=0.3, lp=2500.0), 0.0, -4.0)), "pickup") for i in (2, 5)]
    # ---- footsteps
    ev["step_player"] = [take(base, f"{C}/plmove/walk_t_floor/walk_t_floor_{i}.ogg", "step", max_len=0.3, hp=70.0, fade_ms=80.0) for i in range(1, 7)]
    ev["step_player"] += [take(base, f"{R}/player/step{side}{n}.ogg", "step", max_len=0.3, hp=70.0, lp=9000.0, gate_db=None) for side in ("l", "r") for n in ("", "3")]
    ev["step_light"] = [take(base, f"{C}/plmove/walk_barefoot_{i}.ogg", "step", max_len=0.3, ratio=0.9, hp=60.0, offset_db=1.0) for i in range(1, 7)]
    ev["step_heavy"] = [level(mix((take(base, f"{R}/player/concstep{n}.ogg", "step", ratio=0.68, hp=30.0, gate_db=None), 0.0, 0.0), (lowpass(take(base, f"{C}/smash_fail/t_wall/smash_fail_wall.ogg", "step", hp=30.0, ratio=0.7), 300.0), 0.0, -4.0)), "step", 4.0) for n in ("", "2", "3", "4")]
    ev["step_horde"] = [level(lowpass(take(base, f"{C}/melee_hit_flesh/small_stabbing/small_stabbing_flesh_{i}.ogg", "step", ratio=0.75, hp=40.0), 2200.0), "step", 1.0) for i in (1, 3, 4, 6)]
    # ---- bullet impacts
    ev["hit_metal"] = [take(base, f"{C}/smash_fail/metal/smash_fail_metal{s}.ogg", "impact", 0.0, 0.5, ratio=1.15, hp=200.0, fade_ms=200.0) for s in ("", "_1", "_3")] + [take(base, f"{R}/weapons/ricochet.ogg", "impact", hp=400.0, offset_db=-3.0)]
    ev["hit_wood"] = [take(base, f"{C}/smash_fail/wood_furn/smash_fail_wood{s}.ogg", "impact", 0.0, 0.35, ratio=1.1, hp=90.0, fade_ms=120.0) for s in ("", "_2", "_4")] + [take(base, f"{C}/smash_fail/door_wood/door_smash_fail_{i}.ogg", "impact", max_len=0.3, ratio=1.15) for i in (1, 3)]
    paper = []
    for i in range(3):
        rip = noise_burst(0.22, 1800.0, 7500.0, 1.5, 0.05, crackle=0.9)
        tick = take(base, f"{C}/smash_fail/plastic/smash_fail_plastic{('', '_1', '_2')[i]}.ogg", "impact", max_len=0.15, hp=500.0)
        paper.append(level(fade(mix((rip, 0.0, 0.0), (tick, 0.0, -8.0)), 1.0, 40.0), "impact", -5.0))
    ev["hit_paper"] = paper
    ev["hit_electronics"] = [level(mix((take(base, f"{C}/smash_fail/plastic/smash_fail_plastic{s}.ogg", "impact", max_len=0.2, hp=300.0), 0.0, 0.0), (take(base, f"{R}/weapons/bzzt.ogg", "impact", max_len=0.32, hp=500.0, gate_db=None, fade_ms=120.0), 0.01, -7.0)), "impact") for s in ("", "_1", "_2")]
    ev["hit_wall"] = [take(base, f"{C}/smash_fail/concrete/smash_fail_concrete{s}.ogg", "impact", max_len=0.25, hp=120.0, offset_db=-1.0) for s in ("", "_3", "_4")] + [take(base, f"{C}/smash_fail/brick/smash_fail_brick{s}.ogg", "impact", max_len=0.3, hp=120.0) for s in ("_1", "_2")]
    ev["hit_glass"] = [take(base, f"{C}/smash_fail/glass/smash_fail_glass{s}.ogg", "glass", max_len=0.45, hp=600.0, offset_db=-4.0, fade_ms=120.0) for s in ("", "_1", "_2", "_reinforced_1")]
    ev["glass_break"] = [take(base, f"{C}/smash_success/glass/smash_success_glass{s}.ogg", "glass", max_len=1.6, hp=150.0, gate_db=-46.0, fade_ms=250.0) for s in ("", "_1", "_2")] + [take(base, f"{C}/smash_success/window/window_smash_success.ogg", "glass", max_len=1.4, hp=150.0, fade_ms=250.0)]
    # ---- enemies
    ev["flesh_hit"] = [take(base, f"{C}/melee_hit_flesh/small_stabbing/small_stabbing_flesh_{i}.ogg", "flesh", max_len=0.3, hp=90.0) for i in (1, 2, 4, 5)] + [take(base, f"{C}/melee_hit_flesh/default/unarmed_hit_flesh_{i}.ogg", "flesh", max_len=0.3, hp=90.0, offset_db=-2.0) for i in (2, 4)]
    ev["dismember"] = [level(mix((take(base, f"{C}/mon_death/zombie_gibbed/zombie_gibbed_{i}.ogg", "gore", max_len=1.0, hp=60.0, fade_ms=200.0), 0.0, 0.0), (take(base, f"{C}/melee_hit_flesh/big_cutting/big_cutting_flesh_{i}.ogg", "gore", max_len=0.5), 0.0, -3.0)), "gore") for i in (1, 2)]
    ev["body_part_fall"] = [level(lowpass(take(base, f"{C}/melee_hit_flesh/big_bash/big_bash_flesh_{i}.ogg", "fall", max_len=0.45, ratio=0.85), 2500.0), "fall") for i in (1, 2)]
    groans = [f"{C}/speech/zombie/speech_zombie_groan{s}.ogg" for s in ("", "_1", "_2", "_3", "_4")]
    def vocal(rel: str, ratio: float, lp: float = 9000.0, offset: float = 0.0, max_len: float = 1.2) -> Sound:
        return take(base, rel, "vocal", max_len=max_len, ratio=ratio, hp=70.0, lp=lp, gate_db=-40.0, offset_db=offset, fade_ms=150.0)
    ev["growl_zombie"] = [vocal(g, 1.0) for g in groans]
    ev["growl_hunger"] = [vocal(f"{C}/speech/ferals/male_heavy_breathing_1.ogg", 1.05, max_len=0.9), vocal(f"{C}/speech/ferals/female_scream_1.ogg", 0.82, 6000.0, -2.0), vocal(groans[3], 1.18)]
    ev["growl_revenant"] = [vocal(f"{C}/speech/ferals/female_mad_whisper_2.ogg", 0.85, offset=-3.0), vocal(groans[1], 1.12), vocal(f"{C}/speech/ferals/creepy_laugh.ogg", 0.8, 5000.0, -3.0)]
    ev["growl_brute"] = [vocal(g, 0.8, 6000.0) for g in groans[:3]]
    ev["growl_titan"] = [vocal(g, 0.68, 4500.0, max_len=1.4) for g in groans[1:4]]
    rumble = lowpass(clean(load(base, f"{C}/explosion/huge/explosion_huge_2.ogg", 0.5, 2.0), 25.0), 180.0, 4)
    ev["growl_colossus"] = [level(mix((vocal(g, 0.56, 3500.0, max_len=1.6), 0.0, 0.0), (fade(rumble.copy(), 200.0, 400.0), 0.0, -14.0)), "vocal", 1.0) for g in groans[:3]]
    ev["growl_horde"] = [level(mix((vocal(groans[a], 0.74, 4000.0), 0.0, 0.0), (vocal(groans[b], 0.9, 5000.0), 0.11, -3.0), (vocal(groans[c], 1.1, 6000.0), 0.23, -6.0)), "vocal") for a, b, c in ((0, 2, 4), (1, 3, 0))]
    ev["attack_swing"] = [take(base, f"{C}/melee_swing/big_bash/big_bash_swing_1.ogg", "flesh", max_len=0.35, hp=150.0, offset_db=-6.0)] + [take(base, f"{C}/melee_swing/small_bash/small_bash_swing_{i}.ogg", "flesh", max_len=0.35, hp=150.0, offset_db=-6.0) for i in (1, 3, 5)]
    ev["attack_hit"] = [take(base, f"{C}/melee_attack/monster_melee_hit/monster_melee_hit_{i}.ogg", "flesh", max_len=0.5, hp=60.0) for i in (1, 2, 3, 4)]
    ev["attack_bite"] = [take(base, f"{C}/mon_bite/bite_hit/bite_hit_{i}.ogg", "flesh", max_len=0.6, hp=70.0) for i in (1, 3, 5)]
    ev["enemy_death"] = [vocal(f"{C}/mon_death/zombie_death/zombie_death_{i}.ogg", 1.0, max_len=1.0) for i in (1, 2, 3, 4)]
    slam = []
    for ratio in (1.0, 0.9):
        boom = clean(trim(load(base, f"{C}/explosion/small/explosion_small.ogg"), -40.0), 25.0)
        crack = clean(trim(load(base, f"{C}/smash_success/concrete/smash_success_concrete.ogg"), -40.0), 60.0)
        thud = lowpass(clean(load(base, f"{C}/melee_hit_flesh/big_bash/big_bash_flesh_1.ogg")), 900.0)
        s = mix((speed(boom, 0.7 * ratio), 0.0, 0.0), (speed(crack, ratio), 0.01, -4.0), (speed(thud, 0.6), 0.0, -2.0), (decay_after(rumble.copy(), 0.1, 1.2), 0.0, -6.0))
        slam.append(level(fade(s, 1.0, 200.0), "slam"))
    ev["colossus_slam"] = slam
    ev["horde_ram_hit"] = [level(mix((take(base, f"{C}/melee_hit_flesh/big_bash/big_bash_flesh_{i}.ogg", "flesh", max_len=0.6, ratio=0.75), 0.0, 0.0), (take(base, f"{C}/smash_success/wood_furn/smash_success_wood.ogg", "flesh", max_len=0.5, ratio=0.85), 0.0, -6.0)), "slam", -3.0) for i in (1, 2)]
    hum = clean(load(base, f"{C}/humming/electric.ogg"), 40.0)
    ev["horde_summon"] = [level(mix((speed(fade(hum.copy(), 80.0, 300.0), 0.6), 0.0, -4.0), (vocal(groans[i], 0.62, 3000.0, max_len=1.4), 0.15, 0.0), (vocal(groans[(i + 2) % 5], 0.5, 2500.0, max_len=1.4), 0.3, -4.0)), "vocal", 2.0) for i in (0, 1)]
    # ---- doors
    ev["door_open"] = [take(base, f"{C}/open_door/door_wood/open_door.ogg", "door", max_len=0.6), take(base, f"{C}/open_door/door_wood/open_door.ogg", "door", max_len=0.6, ratio=0.94)]
    ev["door_close"] = [take(base, f"{C}/close_door/door_wood/close_door.ogg", "door", max_len=0.6), take(base, f"{C}/close_door/door_wood/close_door.ogg", "door", max_len=0.6, ratio=0.95)]
    ev["metal_door_open"] = [take(base, f"{C}/open_door/door_metal/open_door_metal.ogg", "door", max_len=0.8)]
    ev["metal_door_close"] = [take(base, f"{C}/close_door/door_metal/close_door_metal.ogg", "door", max_len=0.7)]
    ev["glass_door_open"] = [take(base, f"{C}/open_door/window/open_window.ogg", "door", max_len=0.5, offset_db=-3.0), take(base, f"{C}/open_door/door_fence/open_door_fence.ogg", "door", max_len=0.6, hp=300.0, offset_db=-4.0)]
    ev["glass_door_close"] = [take(base, f"{C}/close_door/window/close_window.ogg", "door", max_len=0.8, offset_db=-3.0)]
    motor = lowpass(clean(load(base, f"{C}/humming/machinery.ogg")), 1800.0)
    slide = clean(load(base, f"{C}/open_door/gun_safe/open_safe.ogg", 0.15, 1.7), 80.0)
    ding = mix((modal([1318.5, 2637.0, 3955.5], [0.9, 0.5, 0.3], [1.0, 0.3, 0.12], 1.6, 0.5), 0.0, 0.0), (modal([1046.5, 2093.0], [1.0, 0.5], [0.9, 0.25], 1.6, 0.5), 0.32, -1.0))
    ev["elevator_open"] = [level(fade(mix((level(ding.copy(), "door", -6.0), 0.0, 0.0), (fade(speed(motor.copy(), 0.85), 80.0, 300.0), 0.25, -10.0), (speed(slide.copy(), 0.8), 0.32, -2.0)), 1.0, 300.0), "door", 1.0)]
    ev["elevator_close"] = [level(fade(mix((fade(speed(motor.copy(), 0.85), 80.0, 300.0), 0.0, -10.0), (speed(slide.copy(), 0.75), 0.05, -2.0), (take(base, f"{C}/close_door/door_metal/close_door_metal.ogg", "door", max_len=0.6, ratio=0.8), 1.1, -1.0)), 1.0, 250.0), "door", 1.0)]
    # ---- falling objects
    ev["fall_wood"] = [take(base, f"{C}/smash_fail/wood_furn/smash_fail_wood_{i}.ogg", "fall", 0.0, 0.6, ratio=0.85, hp=50.0, fade_ms=200.0) for i in (1, 3)] + [take(base, f"{R}/weapons/thud{n}.ogg", "fall", max_len=0.5, hp=50.0) for n in ("", "2")]
    ev["fall_metal"] = [take(base, f"{C}/smash_fail/metal/smash_fail_metal_{i}.ogg", "fall", 0.0, 0.8, ratio=0.85, hp=60.0, fade_ms=300.0) for i in (2, 4)]
    ev["fall_light"] = [take(base, f"{C}/smash_fail/plastic/smash_fail_plastic{s}.ogg", "fall", max_len=0.3, hp=150.0, offset_db=-3.0) for s in ("", "_1", "_2")] + [take(base, f"{R}/sfx/drop.ogg", "fall", max_len=0.4, offset_db=-3.0)]
    ev["fall_tech"] = [level(mix((take(base, f"{C}/smash_fail/plastic/smash_fail_plastic_2.ogg", "fall", max_len=0.3), 0.0, 0.0), (take(base, f"{C}/smash_fail/metal/smash_fail_metal_1.ogg", "fall", 0.0, 0.35, ratio=1.3, hp=400.0), 0.0, -8.0)), "fall")]
    ev["fall_debris"] = [take(base, f"{R}/sfx/debris{n}.ogg", "fall", max_len=0.6, hp=80.0, offset_db=-4.0) for n in ("", "2", "3")]
    extinguisher_events(base, ev)
    skill_events(base, ev)
    scream_events(base, ev)
    return ev


# Fire extinguisher (own RNG so earlier events stay bit-identical).
XRNG = np.random.default_rng(2026)


def band_noise(seconds: float, low: float, high: float, order: int = 2) -> np.ndarray:
    x = XRNG.normal(0, 1, int(seconds * SR))
    return signal.sosfilt(signal.butter(order, [low, high], "bandpass", fs=SR, output="sos"), x)


def turbulence(seconds: float, low_hz: float, high_hz: float, depth: float) -> np.ndarray:
    """Slow random amplitude wobble of a gas jet."""
    n = int(seconds * SR)
    x = signal.sosfilt(signal.butter(2, [low_hz, high_hz], "bandpass", fs=SR, output="sos"), XRNG.normal(0, 1, n))
    return 1.0 + depth * x / (np.abs(x).max() + 1e-9)


def extinguisher_spray(base: Path, seconds: float, ratio: float) -> Sound:
    t = np.arange(int(seconds * SR)) / SR
    # Pressure: full blast, then the jet weakens like the gameplay spray (1.0 -> ~0.5).
    pressure = np.minimum(1.0, t / 0.012) * (0.5 + 0.5 * np.exp(-np.maximum(t - 0.35, 0.0) / 1.4))
    bright = band_noise(seconds, 2200.0 * ratio, 11000.0, 3)
    body = band_noise(seconds, 350.0 * ratio, 1800.0 * ratio, 2)
    dull = band_noise(seconds, 900.0 * ratio, 4200.0 * ratio, 2)
    fade_bright = np.clip(1.0 - (t - 0.4) / (seconds - 0.4), 0.25, 1.0)
    x = bright * fade_bright + dull * (1.15 - fade_bright) * 0.8 + body * 0.32
    x *= turbulence(seconds, 3.0, 14.0, 0.22) * pressure
    # The last half second sputters as the charge runs out.
    tail = t > seconds - 0.65
    gaps = signal.sosfilt(signal.butter(2, 18.0, "lowpass", fs=SR, output="sos"), (XRNG.random(len(t)) < 0.0009).astype(float) * 400.0)
    x[tail] *= np.clip(0.25 + gaps[tail], 0.0, 1.0)
    jet = Sound(x, ["synthesised"])
    valve = cut(clean(trim(load(base, f"{RE}/sfx/extinguish2.ogg"), -40.0), 300.0), 0.3, 120.0)
    s = mix((jet, 0.0, 0.0), (valve, 0.0, -4.0))
    return level(fade(s, 2.0, 220.0), "spray")


def canister_drop(base: Path, ratio: float, roll: float) -> Sound:
    def strike(scale: float) -> Sound:
        return modal([410.0 * ratio, 1090.0 * ratio, 2120.0 * ratio, 3370.0 * ratio, 5150.0 * ratio],
                     [0.42, 0.26, 0.16, 0.09, 0.05], [1.0, 0.7, 0.45, 0.3, 0.16], 1.2, 3.0, XRNG)
    thud = lowpass(take(base, f"{CDDA}/smash_fail/metal/smash_fail_metal_2.ogg", "fall", 0.0, 0.5, ratio=0.8), 1800.0, 2)
    t = np.arange(int(0.9 * SR)) / SR
    rattle = band_noise(0.9, 700.0, 3200.0) * (0.5 + 0.5 * np.sin(2 * np.pi * roll * t) ** 8) * np.exp(-t / 0.35)
    s = mix((strike(1.0), 0.0, -2.0), (thud, 0.0, 0.0), (strike(0.6), 0.17, -10.0), (strike(0.3), 0.29, -17.0),
            (Sound(rattle, ["synthesised"]), 0.33, -14.0))
    return level(fade(clean(s, 50.0), 1.0, 260.0), "fall", 3.0)


def extinguisher_rupture(base: Path, ratio: float) -> Sound:
    pop = clean(trim(load(base, f"{CDDA}/explosion/small/explosion_small.ogg"), -40.0), 40.0)
    ring = modal([520.0 * ratio, 1380.0 * ratio, 2650.0 * ratio, 4100.0 * ratio], [0.5, 0.3, 0.18, 0.1], [1.0, 0.6, 0.4, 0.25], 1.4, 1.0, XRNG)
    t = np.arange(int(1.8 * SR)) / SR
    whoosh = band_noise(1.8, 250.0, 2600.0) * np.minimum(1.0, t / 0.03) * np.exp(-t / 0.55)
    hiss = highpass(clean(load(base, f"{RE}/sfx/extinguish.ogg")), 900.0, 2)
    s = mix((speed(pop, ratio), 0.0, 0.0), (ring, 0.004, -15.0), (Sound(whoosh, ["synthesised"]), 0.01, -7.0),
            (decay_after(hiss, 0.2, 1.2), 0.03, -9.0))
    return level(fade(s, 1.0, 200.0), "explosion", -1.0)


def extinguisher_events(base: Path, ev: dict[str, list[Sound]]) -> None:
    ev["extinguisher_spray"] = [extinguisher_spray(base, 3.4, r) for r in (1.0, 0.93)]
    ev["canister_drop"] = [canister_drop(base, r, roll) for r, roll in ((1.0, 9.0), (0.94, 7.5), (1.06, 10.5))]
    ev["extinguisher_burst"] = [extinguisher_rupture(base, r) for r in (1.0, 1.07)]


# Mutation skills and enemy screams (own RNG so earlier events stay bit-identical).
SRNG = np.random.default_rng(2027)


def saturate(s: Sound, drive: float) -> Sound:
    """Throat rasp / overdriven electrics: soft tanh saturation."""
    peak = np.abs(s.x).max() + 1e-9
    s.x = np.tanh(s.x / peak * drive) * peak / np.tanh(drive)
    return s


def reverb(s: Sound, seconds: float, wet_db: float, bright: float = 4000.0) -> Sound:
    """Short diffuse tail (office corridor), so howls carry and fade naturally."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = SRNG.normal(0, 1, n) * np.exp(-6.0 * t / seconds)
    ir = signal.sosfilt(signal.butter(2, bright, "lowpass", fs=SR, output="sos"), ir)
    wet = signal.fftconvolve(s.x, ir)[: len(s.x) + n]
    wet *= np.abs(s.x).max() / (np.abs(wet).max() + 1e-9)
    dry = np.concatenate([s.x, np.zeros(len(wet) - len(s.x))])
    s.x = dry + wet * 10 ** (wet_db / 20)
    # Drop the inaudible end of the tail so voices free their slot sooner.
    env = envelope(s.x, 10.0)
    audible = np.where(env > env.max() * 10 ** (-54.0 / 20))[0]
    s.x = s.x[: audible[-1] + 1] if len(audible) else s.x
    return fade(s, 0.0, 120.0)


def tone(seconds: float, f0: float, f1: float, decay: float, harmonics: tuple[float, ...] = (1.0,), attack_ms: float = 3.0) -> Sound:
    """Pitch-gliding partial stack with an exponential decay (thumps, whines)."""
    t = np.arange(int(seconds * SR)) / SR
    freq = f0 * (f1 / f0) ** (t / seconds)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    x = sum(a * np.sin(phase * (i + 1)) for i, a in enumerate(harmonics))
    env = np.minimum(1.0, t / max(attack_ms / 1000, 1e-4)) * np.exp(-t / decay)
    return Sound(x * env, ["synthesised"])


def heartbeat(beats: int, interval: float, depth: float = 1.0) -> Sound:
    """Lub-dub: two low chest thumps per beat with a soft flesh knock."""
    parts = []
    for i in range(beats):
        lub = tone(0.32, 72.0, 44.0, 0.07, (1.0, 0.35, 0.12), 4.0)
        dub = tone(0.28, 64.0, 40.0, 0.055, (1.0, 0.3), 4.0)
        knock = Sound(signal.sosfilt(signal.butter(2, [120.0, 700.0], "bandpass", fs=SR, output="sos"), SRNG.normal(0, 1, int(0.05 * SR)))
                      * np.exp(-np.arange(int(0.05 * SR)) / SR / 0.012), ["synthesised"])
        at = i * interval
        parts += [(lub, at, 0.0), (knock, at, -14.0), (dub, at + 0.24 * min(1.0, interval / 0.6), -3.0 * depth)]
    return mix(*parts)


def crackle(seconds: float, rate: float, low: float = 1500.0, high: float = 9000.0, floor: float = 0.04, decay: float | None = None) -> Sound:
    """Electric arcing: random sparks over a mains buzz; `decay` makes a burst."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    sparks = (SRNG.random(n) < rate / SR).astype(float) * SRNG.uniform(0.3, 1.0, n)
    sparks = np.convolve(sparks, np.exp(-np.arange(int(0.004 * SR)) / (0.0009 * SR)), mode="same")
    noise = signal.sosfilt(signal.butter(2, [low, high], "bandpass", fs=SR, output="sos"), SRNG.normal(0, 1, n))
    buzz = sum(np.sign(np.sin(2 * np.pi * 100.0 * k * t)) / k for k in (1, 3, 5)) * 0.08
    buzz = signal.sosfilt(signal.butter(2, 2500.0, "lowpass", fs=SR, output="sos"), buzz)
    x = noise * (floor + 3.0 * sparks) + buzz
    if decay is not None:
        x *= np.minimum(1.0, t / 0.003) * np.exp(-t / decay)
    return fade(Sound(x, ["synthesised"]), 1.0, 30.0)


def whoosh(seconds: float, low: float, high: float, peak: float = 0.35) -> Sound:
    """Band-passed air rush that swells to `peak` (0..1 of length) and dies."""
    n = int(seconds * SR)
    t = np.arange(n) / SR / seconds
    x = signal.sosfilt(signal.butter(2, [low, high], "bandpass", fs=SR, output="sos"), SRNG.normal(0, 1, n))
    env = np.where(t < peak, (t / peak) ** 2, np.exp(-(t - peak) / (1 - peak) * 4.0))
    return Sound(x * env, ["synthesised"])


def chitter(seconds: float, rate: float, centre: float) -> Sound:
    """Insect-like wet clicking: fast amplitude-chopped band noise."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    x = signal.sosfilt(signal.butter(2, [centre * 0.6, centre * 1.6], "bandpass", fs=SR, output="sos"), SRNG.normal(0, 1, n))
    wobble = rate * (1.0 + 0.3 * np.sin(2 * np.pi * 3.1 * t))
    gate_curve = np.clip(np.sin(2 * np.pi * np.cumsum(wobble) / SR), 0.0, 1.0) ** 6
    env = np.minimum(1.0, t / 0.05) * np.exp(-t / (seconds * 0.5))
    return Sound(x * gate_curve * env, ["synthesised"])


def bubbles(seconds: float, rate: float, low: float, high: float) -> Sound:
    """Popping bubbles: short upward chirps at random times (acid, spores)."""
    n = int(seconds * SR)
    x = np.zeros(n)
    for at in np.sort(SRNG.uniform(0, seconds, int(rate * seconds))):
        f = SRNG.uniform(low, high)
        b = tone(0.035, f, f * 1.8, 0.012).x * SRNG.uniform(0.3, 1.0)
        a = int(at * SR)
        x[a: a + len(b)] += b[: n - a]
    return Sound(x, ["synthesised"])


def scatter(pool: list[Sound], seconds: float, rate: float, gains: tuple[float, float], ratios: tuple[float, float]) -> Sound:
    """Random placement of short recorded snippets (arcs in a field, blade passes)."""
    parts = [(silence(seconds), 0.0, 0.0)]
    at = 0.0
    while True:
        at += SRNG.exponential(1.0 / rate)
        if at > seconds - 0.2:
            break
        snd = speed(pool[int(SRNG.integers(len(pool)))].copy(), SRNG.uniform(*ratios))
        parts.append((snd, at, SRNG.uniform(*gains)))
    return mix(*parts)


def field_shape(s: Sound, seconds: float, fade_in: float, fade_out: float) -> Sound:
    """Lasting effects: swell in, hold, fade over the buff's last moments."""
    s.x = s.x[: int(seconds * SR)]
    if len(s.x) < int(seconds * SR):
        s.x = np.concatenate([s.x, np.zeros(int(seconds * SR) - len(s.x))])
    t = np.arange(len(s.x)) / SR
    s.x *= np.minimum(1.0, t / fade_in) * np.clip((seconds - t) / fade_out, 0.0, 1.0)
    return s


def skill_events(base: Path, ev: dict[str, list[Sound]]) -> None:
    C, R = CDDA, RE
    def raw(rel: str, start: float = 0.0, end: float | None = None, hp: float = 40.0) -> Sound:
        return fade(clean(trim(load(base, rel, start, end), -50.0), hp), 1.0, 60.0)
    def flesh(kind: str, i: int, ratio: float = 1.0, lp: float = 6000.0) -> Sound:
        return lowpass(speed(raw(f"{C}/melee_hit_flesh/{kind}/{kind}_flesh_{i}.ogg"), ratio), lp, 2)

    # Blood Burst: chest thump, flesh rupture and bone spikes punching out in a ring.
    burst = []
    for i, ratio in ((1, 1.0), (2, 0.93)):
        thump = tone(0.5, 95.0 * ratio, 38.0, 0.12, (1.0, 0.4, 0.15))
        gib = raw(f"{C}/mon_death/zombie_gibbed/zombie_gibbed_{i}.ogg", hp=60.0)
        spikes = [(flesh("big_stabbing", k, SRNG.uniform(1.05, 1.3), 7000.0), 0.03 + 0.035 * j, -4.0 - 2.0 * j) for j, k in enumerate((1, 2, 3))]
        rush = whoosh(0.45, 600.0, 5000.0, 0.12)
        s = mix((thump, 0.0, 0.0), (speed(gib, ratio), 0.01, -3.0), (rush, 0.0, -9.0), *spikes)
        burst.append(level(fade(cut(s, 1.1, 200.0), 1.0, 200.0), "skill", 1.0))
    ev["skill_blood_burst"] = burst

    # Parasite: wet spit of a living larva, a squirm and chitter as it latches on.
    parasite = []
    for i, ratio in ((2, 1.0), (5, 0.9)):
        spit = mix((raw(f"{R}/sfx/splosh.ogg", hp=150.0), 0.0, 0.0), (flesh("small_stabbing", i, 0.8, 4000.0), 0.0, -4.0))
        squirm = speed(raw(f"{C}/mon_bite/bite_hit/bite_hit_{(1, 3)[i % 2]}.ogg"), 1.35 * ratio)
        s = mix((spit, 0.0, 0.0), (whoosh(0.25, 900.0, 4500.0, 0.2), 0.0, -10.0), (squirm, 0.14, -6.0), (chitter(0.55, 28.0 * ratio, 2600.0), 0.12, -9.0))
        parasite.append(level(fade(cut(s, 0.9, 200.0), 1.0, 200.0), "skill", -2.0))
    ev["skill_parasite"] = parasite

    # Living Harvest: the body wakes up to feed - heartbeat swell and a hungry organic rise.
    harvest = []
    for ratio in (1.0, 0.94):
        regen = lowpass(speed(raw(f"{R}/sfx/regen_begin.ogg"), 0.8 * ratio), 3500.0, 2)
        wet = flesh("small_bash", 2, 0.75, 2500.0)
        s = mix((heartbeat(2, 0.55), 0.0, 0.0), (regen, 0.05, -6.0), (wet, 0.0, -8.0), (wet.copy(), 0.55, -10.0))
        harvest.append(level(fade(cut(s, 1.6, 300.0), 1.0, 300.0), "skill", -2.0))
    ev["skill_living_harvest"] = harvest

    # Discharge: hard electric crack jumping enemy to enemy.
    discharge = []
    for i, ratio in (("", 1.0), ("2", 1.08)):
        bolt = raw(f"{R}/weapons/zapper/secondary{i}.ogg", hp=80.0)
        zap = raw(f"{R}/weapons/bzap.ogg", hp=200.0)
        hops = [(speed(raw(f"{R}/weapons/bzzt.ogg", hp=300.0), SRNG.uniform(0.9, 1.2)), 0.08 + 0.09 * k, -6.0 - 2.0 * k) for k in range(3)]
        s = mix((speed(bolt, ratio), 0.0, 0.0), (zap, 0.0, -3.0), (crackle(0.5, 900.0, decay=0.15), 0.0, -8.0), *hops)
        discharge.append(level(fade(cut(s, 1.0, 220.0), 1.0, 220.0), "skill", 1.0))
    ev["skill_discharge"] = discharge

    # Overload: nervous system revving up - rising electric whine with a charge hum.
    overload = []
    for ratio in (1.0, 1.06):
        whine = tone(0.9, 180.0 * ratio, 900.0 * ratio, 0.6, (1.0, 0.5, 0.3, 0.2), 60.0)
        whine.x = whine.x * np.minimum(1.0, np.arange(len(whine.x)) / SR / 0.5)
        charge = lowpass(speed(raw(f"{R}/weapons/plasma/power.ogg", 0.0, 1.6), 1.4 * ratio), 6000.0, 2)
        snap = raw(f"{R}/weapons/zapper/power.ogg", hp=300.0)
        s = mix((charge, 0.0, -2.0), (saturate(whine, 2.0), 0.0, -6.0), (crackle(0.9, 300.0, decay=0.4), 0.2, -14.0), (snap, 0.72, 0.0))
        overload.append(level(fade(cut(s, 1.2, 250.0), 1.0, 250.0), "skill", -1.0))
    ev["skill_overload"] = overload

    # Storm Pulse: an electric blast out of the body, then the field crackles for the buff.
    arcs = [raw(f"{R}/weapons/bzzt.ogg", hp=300.0), raw(f"{R}/weapons/bzap.ogg", hp=300.0)] + [raw(f"{R}/weapons/zapper/beam{n}.ogg", hp=200.0) for n in ("", "2", "3")]
    pulse = []
    for i, ratio in (("", 1.0), ("2", 0.92)):
        blast = lowpass(speed(raw(f"{R}/weapons/smallblast{i if i else ''}.ogg", hp=30.0), 0.8 * ratio), 3000.0)
        start = raw(f"{R}/weapons/zapper/primary_begin{i}.ogg", hp=80.0)
        s = mix((blast, 0.0, -2.0), (start, 0.0, 0.0), (crackle(0.8, 1500.0, decay=0.25), 0.0, -6.0), (scatter(arcs, 0.9, 10.0, (-8.0, -3.0), (0.85, 1.2)), 0.05, -3.0))
        pulse.append(level(fade(cut(s, 1.1, 250.0), 1.0, 250.0), "skill", 1.0))
    ev["skill_storm_pulse"] = pulse
    storm = []
    for ratio in (1.0, 0.95):
        hum = lowpass(speed(raw(f"{R}/weapons/hum.ogg"), 0.7 * ratio), 1500.0)
        hum = Sound(np.tile(hum.x, 5), hum.sources)
        s = mix((field_shape(hum, 6.0, 0.3, 1.0), 0.0, -4.0), (crackle(6.0, 160.0), 0.0, -8.0), (scatter(arcs, 6.0, 3.2, (-9.0, 0.0), (0.8, 1.25)), 0.0, 0.0))
        storm.append(level(field_shape(s, 6.0, 0.15, 0.9), "field", 1.0))
    ev["skill_storm_field"] = storm

    # Acid Spit: a gob of acid splats, then the pool sizzles and bubbles while it lasts.
    spit = []
    for i, ratio in ((4, 1.0), (5, 0.9)):
        gob = raw(f"{R}/weapons/corroder/secondary{i}.ogg", hp=100.0)
        hock = whoosh(0.22, 400.0, 3000.0, 0.5)
        splat = raw(f"{R}/sfx/splosh{('', '2')[i % 2]}.ogg", hp=120.0)
        s = mix((hock, 0.0, -8.0), (speed(gob, ratio), 0.05, 0.0), (splat, 0.2, -4.0), (crackle(0.4, 1800.0, 3000.0, 10000.0, decay=0.12), 0.22, -12.0))
        spit.append(level(fade(cut(s, 1.0, 200.0), 1.0, 200.0), "skill", -2.0))
    ev["skill_acid_spit"] = spit
    sizzle = []
    for ratio in (1.0, 0.92):
        fry = crackle(6.0, 900.0 * ratio, 2500.0, 9000.0, 0.02)
        fry.x -= signal.sosfilt(signal.butter(2, 1500.0, "lowpass", fs=SR, output="sos"), fry.x)
        corrode = highpass(raw(f"{R}/sfx/corrodedamage.ogg"), 600.0)
        s = mix((fry, 0.0, 0.0), (bubbles(6.0, 9.0, 260.0 * ratio, 700.0 * ratio), 0.0, -4.0), (corrode, 0.0, -6.0), (corrode.copy(), 2.4, -10.0))
        sizzle.append(level(field_shape(s, 6.0, 0.08, 1.4), "field"))
    ev["acid_sizzle"] = sizzle

    # Spore Cocoon: a soft fleshy pod lands and swells; two seconds later it bursts in a spore puff.
    cocoon = []
    for i, ratio in ((1, 1.0), (3, 0.9)):
        plop = mix((raw(f"{R}/sfx/splosh3.ogg", hp=120.0), 0.0, 0.0), (flesh("small_bash", i, 0.7, 2500.0), 0.0, -3.0))
        swell = lowpass(speed(raw(f"{R}/sfx/regen_begin.ogg"), 0.55 * ratio), 1800.0, 2)
        s = mix((plop, 0.0, 0.0), (swell, 0.12, -10.0), (bubbles(1.2, 6.0, 180.0, 420.0), 0.2, -10.0))
        cocoon.append(level(fade(cut(s, 1.4, 350.0), 1.0, 350.0), "skill", -4.0))
    ev["skill_spore_cocoon"] = cocoon
    spores = []
    for i, ratio in ((1, 1.0), (2, 0.9)):
        pop = lowpass(speed(raw(f"{R}/weapons/corroder/explode{('', '2')[i - 1]}.ogg", hp=50.0), ratio), 4500.0)
        puff = highpass(clean(load(base, f"{R}/sfx/extinguish.ogg")), 1200.0, 2)
        puff = decay_after(puff, 0.05, 0.9)
        gib = lowpass(raw(f"{C}/mon_death/zombie_gibbed/zombie_gibbed_{i}.ogg", hp=80.0), 3000.0)
        s = mix((pop, 0.0, 0.0), (gib, 0.0, -6.0), (puff, 0.02, -6.0), (whoosh(1.0, 300.0, 2500.0, 0.08), 0.0, -8.0))
        spores.append(level(fade(cut(s, 1.4, 350.0), 1.0, 350.0), "skill", 0.0))
    ev["spore_burst"] = spores

    # Epidemic: an infectious hiss rolls outward, a swarm of wet chittering spreading through the crowd.
    epidemic = []
    for i, ratio in ((1, 1.0), (2, 0.9)):
        breath = lowpass(speed(raw(f"{C}/speech/ferals/female_anguish_heavy_breathing_{i}.ogg", hp=120.0), 0.8 * ratio), 3500.0)
        spread = whoosh(1.3, 500.0 * ratio, 6000.0, 0.25)
        s = mix((spread, 0.0, -2.0), (breath, 0.0, -6.0), (chitter(1.3, 22.0, 3000.0 * ratio), 0.1, -6.0), (chitter(1.1, 31.0, 1800.0 * ratio), 0.25, -9.0), (raw(f"{R}/sfx/splosh2.ogg", hp=150.0), 0.0, -6.0))
        epidemic.append(level(fade(cut(s, 1.5, 400.0), 1.0, 400.0), "skill", -2.0))
    ev["skill_epidemic"] = epidemic

    # Predator Dash: a lunge - burst of air past the ears with a feral snarl.
    dash = []
    for i, ratio in ((1, 1.0), (2, 1.08)):
        lunge = raw(f"{R}/player/impulse{('', '2')[i - 1]}.ogg", hp=80.0)
        swing = raw(f"{C}/melee_swing/big_cutting/big_cutting_swing_1.ogg", hp=150.0)
        snarl = saturate(lowpass(speed(raw(f"{C}/deal_damage/hurt_m/hurt_m_{i}.ogg", hp=90.0), 0.72 * ratio), 3500.0), 2.5)
        s = mix((lunge, 0.0, 0.0), (speed(swing, 0.85 * ratio), 0.02, -2.0), (whoosh(0.5, 300.0, 3500.0, 0.3), 0.0, -6.0), (snarl, 0.0, -5.0))
        dash.append(level(fade(cut(s, 0.9, 200.0), 1.0, 200.0), "skill", 0.0))
    ev["skill_predator_dash"] = dash

    # Bone Blades: bone cracks out of the arms with a blade ring; the blades whirl while active.
    blades = []
    for i, ratio in ((1, 1.0), (2, 0.94)):
        crack = speed(raw(f"{C}/smash_fail/wood_furn/smash_fail_wood_{(1, 3)[i - 1]}.ogg", 0.0, 0.4, hp=200.0), 1.35 * ratio)
        stab = flesh("big_stabbing", i, 0.9, 5000.0)
        draw = raw(f"{R}/weapons/sword/switch.ogg", hp=200.0)
        s = mix((crack, 0.0, 0.0), (stab, 0.0, -4.0), (speed(draw, 1.1 * ratio), 0.08, -3.0))
        blades.append(level(fade(cut(s, 1.0, 220.0), 1.0, 220.0), "skill", -1.0))
    ev["skill_bone_blades"] = blades
    passes = [lowpass(raw(f"{C}/melee_swing/small_cutting/small_cutting_swing_{k}.ogg", hp=300.0), 7000.0) for k in (1, 3, 4, 6)]
    whirl = []
    for ratio in (1.0, 1.05):
        beat = mix(*[(speed(passes[k % 4].copy(), SRNG.uniform(1.0, 1.25) * ratio), k * 0.3 + SRNG.uniform(0, 0.03), SRNG.uniform(-4.0, 0.0)) for k in range(20)])
        s = mix((beat, 0.0, 0.0), (whoosh(6.0, 250.0, 1600.0, 0.5), 0.0, -18.0))
        whirl.append(level(field_shape(s, 6.0, 0.2, 0.8), "field", 1.0))
    ev["bone_blades_whirl"] = whirl

    # Berserk: a monstrous roar over a racing heart.
    roar = []
    groans = [f"{C}/speech/zombie/speech_zombie_groan{s}.ogg" for s in ("", "_1", "_2", "_3", "_4")]
    for i, ratio in ((1, 1.0), (2, 0.93)):
        scream = saturate(lowpass(speed(raw(f"{C}/speech/ferals/male_scream_{i}.ogg", hp=80.0), 0.62 * ratio), 3800.0), 3.0)
        groan = lowpass(speed(raw(groans[i], hp=60.0), 0.6 * ratio), 2500.0)
        s = mix((scream, 0.0, 0.0), (groan, 0.0, -4.0), (heartbeat(3, 0.33, 0.6), 0.0, -6.0), (tone(1.5, 60.0, 45.0, 0.8, (1.0, 0.5)), 0.0, -12.0))
        roar.append(level(reverb(fade(cut(s, 1.8, 400.0), 1.0, 400.0), 0.8, -14.0), "skill", 2.0))
    ev["skill_berserk"] = roar

    # Passives with a clear moment: Second Heart's restart and Retaliation's shock.
    restart = mix((heartbeat(3, 0.62), 0.0, 0.0), (lowpass(raw(f"{C}/speech/ferals/male_scared_heavy_breathing_1.ogg", hp=120.0), 4000.0), 0.15, -9.0),
                  (lowpass(speed(raw(f"{R}/sfx/regen_begin.ogg"), 0.7), 3000.0), 0.1, -12.0))
    ev["skill_second_heart"] = [level(fade(cut(restart, 2.0, 400.0), 1.0, 400.0), "skill", -1.0)]
    shock = []
    for ratio in (1.0, 1.1):
        s = mix((raw(f"{R}/sfx/shockdamage.ogg", hp=150.0), 0.0, 0.0), (speed(raw(f"{R}/weapons/bzap.ogg", hp=200.0), ratio), 0.0, -2.0),
                (lowpass(speed(raw(f"{R}/weapons/smallblast.ogg", hp=30.0), 0.85), 2500.0), 0.0, -8.0), (crackle(0.4, 1200.0, decay=0.12), 0.0, -8.0))
        shock.append(level(fade(cut(s, 0.8, 200.0), 1.0, 200.0), "skill", -1.0))
    ev["skill_retaliation"] = shock


def scream_events(base: Path, ev: dict[str, list[Sound]]) -> None:
    C = CDDA
    ferals = f"{C}/speech/ferals"
    groans = [f"{C}/speech/zombie/speech_zombie_groan{s}.ogg" for s in ("", "_1", "_2", "_3", "_4")]
    def voice(rel: str, ratio: float, lp: float, drive: float, hp: float = 90.0, max_len: float = 1.6) -> Sound:
        s = clean(trim(load(base, rel), -50.0), hp)
        s = gate(s, -40.0)
        s = lowpass(speed(trim(s, -55.0), ratio), lp)
        return cut(saturate(s, drive), max_len, 200.0)

    # Infected screams: human screams slowed, torn by throat rasp, a groan under it.
    zombie = []
    for rel, ratio, g in ((f"{ferals}/male_scream_1.ogg", 0.86, 0), (f"{ferals}/male_scream_2.ogg", 0.8, 2), (f"{ferals}/female_scream_1.ogg", 0.74, 1),
                          (f"{ferals}/female_scream_2.ogg", 0.7, 3), (f"{C}/deal_damage/hurt_m/hurt_m_1.ogg", 0.78, 4)):
        s = mix((voice(rel, ratio, 5500.0, 2.6), 0.0, 0.0), (voice(groans[g], 0.9, 4000.0, 1.5), 0.0, -9.0))
        zombie.append(level(reverb(s, 0.6, -15.0), "vocal", 1.0))
    ev["scream_zombie"] = zombie
    # Hunger and Revenant: thin, shrill shrieks.
    shrill = []
    for rel, ratio in ((f"{ferals}/female_scream_1.ogg", 1.04), (f"{ferals}/female_scream_2.ogg", 0.96), (f"{C}/deal_damage/hurt_f/hurt_f_3.ogg", 0.9), (f"{ferals}/creepy_laugh.ogg", 1.15)):
        s = tilt(voice(rel, ratio, 8000.0, 3.2, 180.0), -3.0, 3.0, 1500.0)
        shrill.append(level(reverb(s, 0.7, -14.0, 6000.0), "vocal", 0.0))
    ev["scream_shrill"] = shrill
    # Brute, Titan, Colossus, Horde: deep roars.
    roars = []
    for rel, ratio, g in ((f"{ferals}/male_scream_1.ogg", 0.58, 1), (f"{ferals}/male_scream_2.ogg", 0.54, 3), (f"{ferals}/female_scream_1.ogg", 0.46, 0), (f"{C}/deal_damage/hurt_m/hurt_m_2.ogg", 0.5, 2)):
        s = mix((voice(rel, ratio, 3200.0, 3.0, 50.0, 2.0), 0.0, 0.0), (voice(groans[g], 0.6, 2500.0, 2.0, 50.0, 2.0), 0.0, -5.0), (tone(1.6, 55.0, 40.0, 0.9, (1.0, 0.4)), 0.0, -14.0))
        roars.append(level(reverb(s, 0.9, -13.0, 2500.0), "vocal", 2.0))
    ev["roar_heavy"] = roars
    # Distant hunting howls: long eerie wails with a corridor tail.
    howls = []
    for rel, ratio in ((f"{ferals}/female_scream_1.ogg", 0.62), (f"{ferals}/male_scream_1.ogg", 0.7), (f"{ferals}/female_scream_2.ogg", 0.58), (f"{ferals}/male_scream_2.ogg", 0.66)):
        s = voice(rel, ratio, 3800.0, 1.8, 120.0, 2.2)
        s.x = s.x * (1.0 + 0.25 * np.sin(2 * np.pi * 5.5 * np.arange(len(s.x)) / SR))
        howls.append(level(reverb(s, 1.4, -8.0, 3000.0), "vocal", -1.0))
    ev["howl_infected"] = howls


# ------------------------------------------------------------------ output

def credit_rows(base: Path, sources: set[str]) -> list[str]:
    rows = []
    for rel in sorted(sources):
        if rel == "synthesised":
            continue
        if rel.startswith(CDDA):
            folder = (base / rel).parent
            author, license_name, link = "CC-Sounds contributors", "see CC-Sounds credits", "https://github.com/Fris0uman/CDDA-Soundpacks"
            credits = folder / "credits.md"
            if credits.exists():
                for line in credits.read_text(encoding="utf-8", errors="ignore").splitlines():
                    cells = [c.strip() for c in line.strip().strip("|").split("|")]
                    if len(cells) >= 4 and cells[0] == Path(rel).name:
                        author, license_name, link = cells[1], cells[2].strip("* "), cells[3]
                        break
            rows.append(f"| {rel[len(CDDA) + 1:]} | {author} | {license_name} | {link} | CC-Sounds (Fris0uman/CDDA-Soundpacks) |")
        else:
            rows.append(f"| {rel[len(RE) + 1:]} | Red Eclipse team | CC-BY-SA 4.0 | https://github.com/redeclipse/sounds | Red Eclipse sounds |")
    return rows


def encode(s: Sound, path: Path) -> None:
    s = fade(s, 1.0, 8.0)
    pcm = (np.clip(s.x, -1.0, 1.0) * 32767).astype(np.int16).tobytes()
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", "5", str(path)], input=pcm, check=True)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    base = Path(sys.argv[1]).resolve()
    # --only a,b re-encodes just those events and keeps every other file as is
    # (encoder versions differ, so untouched events stay byte-identical).
    only = set(sys.argv[sys.argv.index("--only") + 1].split(",")) if "--only" in sys.argv else None
    events = recipes(base)
    if only is None and OUT.exists():
        shutil.rmtree(OUT)
    used: set[str] = set()
    per_event: dict[str, set[str]] = {}
    for name, sounds in events.items():
        for index, sound in enumerate(sounds, 1):
            if only is None or name in only:
                encode(sound, OUT / name / f"{name}_{index}.ogg")
            used.update(sound.sources)
            per_event.setdefault(name, set()).update(sound.sources)
        print(f"{name}: {len(sounds)} variant(s)")
    lines = [
        "# Sound credits",
        "",
        "Game sound effects in `assets/audio/sfx` are processed (cut, cleaned, level matched,",
        "pitch/tone varied, layered) by `tools/build_sounds.py` from the recordings below.",
        "Sounds marked *synthesised* were generated by the tool. Files derived from",
        "Red Eclipse recordings are shared under CC-BY-SA 4.0; all other derivatives keep",
        "the licence of their source (CC0 / CC-BY).",
        "",
        "| Source file | Author | Licence | Link | Collection |",
        "|---|---|---|---|---|",
        *credit_rows(base, used),
        "",
        "## Events and their sources",
        "",
    ]
    for name in sorted(per_event):
        lines.append(f"- `{name}`: " + ", ".join(sorted(per_event[name])))
    lines += [
        "",
        "## Interface cues (2026-10-05)",
        "",
        "assets/audio/ui/*.tres: original procedural synthesis for this project, dedicated to CC0-1.0. Generated reproducibly by tools/build_ui_sounds.py using Python standard library only; no source recordings. Menu hover, mutation hover/click, lock and its reversed unlock cue.",
    ]
    (OUT.parent / "CREDITS.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{sum(len(v) for v in events.values())} files written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
