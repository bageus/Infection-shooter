#!/usr/bin/env python3
"""Run the O04 confirmed-hit fixture with current authored weapon rates/counts."""
from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = "game/features/infected/tests/profile_body_blood.gd"
WEAPONS = {"SHOTGUN": "shotgun.tscn", "MINIGUN": "minigun.tscn"}


def weapon_protocol(name: str) -> dict:
    path = ROOT / "game/features/combat/public" / WEAPONS[name]
    # Only root properties before the next [node] are relevant. Rifle defaults
    # supply pellets=1 when the authored scene does not override it.
    root_properties = path.read_text().split('[node name=', 1)[1].split('[node ', 1)[0]
    values = dict(re.findall(r'^([a-z_]+)\s*=\s*([^\n]+)', root_properties, re.M))
    rate = float(values["shots_per_second"])
    pellets = int(values.get("pellets_per_shot", "1"))
    if not (0 < rate <= 60 and pellets > 0):
        raise ValueError("Profile requires 0 < shots_per_second <= 60 and pellets > 0")
    return {"name": name, "source": str(path.relative_to(ROOT)), "rate": rate, "pellets": pellets}


def run_case(args, protocol: dict, mode: str, iteration: int, log_root: Path) -> dict:
    name = f"{protocol['name'].lower()}_{mode}_{iteration}"
    capture = args.captures / name if args.captures and iteration == 0 and mode != "scan" else None
    if capture:
        capture.mkdir(parents=True, exist_ok=True)
    command = [str(args.godot), "--audio-driver", "Dummy"]
    command += ["--rendering-method", "gl_compatibility"] if args.native else ["--headless"]
    command += ["--path", str(ROOT), "--script", SCRIPT, "--",
                f"--weapon={protocol['name']}", f"--mode={mode}", f"--actors={args.actors}",
                f"--frames={args.frames}", f"--rate={protocol['rate']}", f"--pellets={protocol['pellets']}"]
    if capture:
        command.append(f"--capture={capture.resolve()}")
    with tempfile.TemporaryDirectory(prefix="body-blood-user-") as user_dir:
        env = {**os.environ, "XDG_DATA_HOME": user_dir}
        process = subprocess.run(command, cwd=ROOT, env=env, capture_output=True,
                                 text=True, timeout=args.timeout)
    text = process.stdout + process.stderr
    (log_root / (name + ".log")).write_text(text)
    if process.returncode or re.search(r"SCRIPT ERROR|^ERROR:|ObjectDB.*leaked|RID.*leaked", text, re.M):
        raise RuntimeError(f"{name} failed; see {log_root / (name + '.log')}")
    rows = [line.removeprefix("BODY_BLOOD_METRICS ") for line in text.splitlines()
            if line.startswith("BODY_BLOOD_METRICS ")]
    if len(rows) != 1:
        raise RuntimeError(f"{name} did not produce exactly one metrics record")
    result = json.loads(rows[0])
    expected = 1 + math.floor((args.frames - 1) * protocol["rate"] / 60 + 1e-6)
    if result["series"]["bursts"] != expected or result["series"]["hits"] != expected * protocol["pellets"]:
        raise AssertionError("Confirmed-hit schedule does not match authored protocol")
    if mode == "stages":
        if result["repeated_counters"]["paint_updates"] or result["outside_counters"]["paint_updates"]:
            raise AssertionError("Repeated/off-body control unexpectedly changed masks")
    result["iteration"] = iteration
    result["protocol"]["capture"] = bool(capture)
    print(f"{name}: {result['series']['hits']} hits, "
          f"batch p95={result['series']['active_batch']['p95_usec']}us", flush=True)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--log-dir", required=True, type=Path)
    parser.add_argument("--captures", type=Path)
    parser.add_argument("--native", action="store_true")
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--actors", type=int, default=90)
    parser.add_argument("--frames", type=int, default=600)
    parser.add_argument("--repeat", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args()
    if args.smoke:
        args.actors, args.frames, args.repeat = 3, 30, 1
    if min(args.actors, args.frames, args.repeat, args.timeout) <= 0:
        parser.error("actors, frames, repeat and timeout must be positive")
    args.log_dir.mkdir(parents=True, exist_ok=True)
    protocols = [weapon_protocol(name) for name in WEAPONS]
    runs = []
    for iteration in range(args.repeat):
        for protocol in protocols:
            cases = [run_case(args, protocol, mode, iteration, args.log_dir)
                     for mode in ["full", "stages", "scan"]]
            if cases[0]["masks"] != cases[1]["masks"]:
                raise AssertionError("Full and decomposed production paths produced different masks")
            if cases[0]["topology"] != cases[1]["topology"]:
                raise AssertionError("Full and staged paths used different body geometry")
            runs.extend(cases)
    version = subprocess.check_output([str(args.godot), "--version"], text=True).strip()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    result = {"revision": revision, "godot": version, "native": args.native,
              "description": "Confirmed body wounds only: fixed mixed crowd, no AI/projectile/health/physics simulation. Native GPU update CPU submission is not GPU execution time.",
              "weapon_protocols": protocols, "runs": runs}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Saved {len(runs)} cases to {args.output}")


if __name__ == "__main__":
    main()
