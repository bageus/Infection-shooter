#!/usr/bin/env python3
"""Verify all outputs before deleting either owner WAV. Safe to rerun."""
import argparse, hashlib, json, subprocess, tempfile
from pathlib import Path
import numpy as np
from build_added_audio import import_settings
ROOT = Path(__file__).resolve().parents[1]
RATE = 48000
MUSIC = ROOT / "assets/audio/music"
RECEIPT = ROOT / "assets/audio/mission_music_processing.json"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def decode(path):
    raw = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(path),
                                  "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-"])
    return np.frombuffer(raw, dtype="<f4").reshape(-1, 2).copy()

def encode(samples, target, loop=False, offset=0.0):
    samples *= min(1.0, .89 / max(float(np.abs(samples).max()), .0001))
    with tempfile.TemporaryDirectory() as tmp:
        output = Path(tmp) / target.name
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE),
                        "-ac", "2", "-i", "-", "-c:a", "libvorbis", "-q:a", "5", str(output)],
                       input=samples.astype("<f4").tobytes(), check=True)
        actual = decode(output)
        assert abs(len(actual) - len(samples)) <= 64, "Truncated encoding"
        assert np.isfinite(actual).all()
        subprocess.run(["ffmpeg", "-v", "error", "-i", str(output), "-f", "null", "-"], check=True)
        target.write_bytes(output.read_bytes())
    import_settings(target, loop)
    sidecar = Path(str(target) + ".import")
    import re
    sidecar.write_text(re.sub(r"(?m)^loop_offset=.*$", f"loop_offset={offset}", sidecar.read_text()))

def seam(samples, begin=0.0):
    overlap, start = round(.08 * RATE), round(begin * RATE)
    assert len(samples) > start + 2 * overlap
    t = np.linspace(0.0, 1.0, overlap)[:, None]
    samples[-overlap:] = samples[-overlap:] * (1-t) + samples[start:start+overlap] * t
    return begin + .08

def process():
    if RECEIPT.exists():
        check()
        return
    rows = []
    plans = [("tower_hold_1.wav", "tower_hold.ogg", "hold"),
             ("tower_threat_1.wav", "tower_threat.ogg", "threat"),
             ("server_oper.ogg", "server_oper_active.ogg", "calm")]
    for source_name, output_name, kind in plans:
        source, target = MUSIC / source_name, MUSIC / output_name
        assert source.exists() and not target.exists(), source
        samples = decode(source)
        original_seconds = len(samples) / RATE
        if kind == "hold":
            assert original_seconds >= 56
            samples = samples[:56 * RATE]
            samples[:240] *= np.linspace(0, 1, 240)[:, None]
            samples[-round(.75 * RATE):] *= np.linspace(1, 0, round(.75 * RATE))[:, None]
            offset, loop = 0.0, False
        elif kind == "threat":
            assert original_seconds > 35
            samples[:240] *= np.linspace(0, 1, 240)[:, None]
            offset, loop = seam(samples, 30.0), True
        else:
            assert original_seconds > 35
            samples = samples[20 * RATE:-10 * RATE]
            offset, loop = seam(samples), True
        encode(samples, target, loop, offset)
        rows.append(dict(source=str(source.relative_to(ROOT)), output=str(target.relative_to(ROOT)),
                         source_sha256=sha(source), output_sha256=sha(target),
                         source_seconds=original_seconds, output_seconds=len(samples)/RATE,
                         channels=2, sample_rate=RATE, loop=loop, loop_offset=offset,
                         overlap_seconds=.08 if loop else 0))
    RECEIPT.write_text(json.dumps({"version":1, "records":rows}, indent=2) + "\n")
    for source_name, _, kind in plans:
        if kind != "calm":
            source = MUSIC / source_name
            source.unlink()
            Path(str(source) + ".import").unlink(missing_ok=True)
    check()

def check():
    data = json.loads(RECEIPT.read_text())
    for row in data["records"]:
        target = ROOT / row["output"]
        assert sha(target) == row["output_sha256"], target
        assert abs(len(decode(target))/RATE-row["output_seconds"]) < .01
        if row["source"].endswith(".wav"):
            assert not (ROOT / row["source"]).exists()
            sidecar = ROOT / (row["source"] + ".import")
            assert not sidecar.exists(), f"Stale WAV import sidecar: {sidecar}"
    assert not list(MUSIC.glob("*.wav"))
    print(json.dumps(data, indent=2))
    print("Mission music conversions verified.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    check() if parser.parse_args().check else process()
