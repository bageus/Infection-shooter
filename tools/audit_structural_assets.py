#!/usr/bin/env python3
"""Run the Godot structural asset bounds audit and optionally write CSV output."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = "res://tools/audit_structural_assets.gd"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, help="Write audit CSV to this path.")
    args = parser.parse_args()

    godot = shutil.which("godot") or shutil.which("godot4")
    if godot is None:
        print("Godot executable not found. Run this tool from a machine with Godot 4.x installed.", file=sys.stderr)
        return 2

    command = [godot, "--headless", "--path", str(ROOT), "--script", SCRIPT]
    print("+", " ".join(command), flush=True)
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    if result.stderr:
        print(result.stderr, file=sys.stderr, end="")
    if result.stdout:
        print(result.stdout, end="")

    if args.output and result.stdout:
        lines = [line for line in result.stdout.splitlines() if line.startswith("asset,") or line.startswith(("Column,", "Elevator", "FloorPad,", "Glass", "OnlyDoor", "Sliding", "Wall", "Window"))]
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
        print(f"Wrote {args.output}")

    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
