#!/usr/bin/env python3
"""Dump imported GLB/GLTF node and mesh structure through Godot."""

from __future__ import annotations
import argparse, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = "res://tools/audit_model_structure.gd"
HEADER = "model_path,node_path,node_type,mesh_name,parent_node,child_count"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("model_structure_audit.csv"))
    args = parser.parse_args()
    godot = shutil.which("godot") or shutil.which("godot4")
    if godot is None:
        print("Godot executable not found. Add Godot to PATH or run the .gd script directly with Godot.", file=sys.stderr)
        return 2
    command = [godot, "--headless", "--path", str(ROOT), "--script", SCRIPT]
    print("+", " ".join(command), flush=True)
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    if result.stderr:
        print(result.stderr, file=sys.stderr, end="")
    lines = result.stdout.splitlines()
    csv_lines = [line for line in lines if line == HEADER or line.startswith('"res://models/objects/')]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(csv_lines) + ("\n" if csv_lines else ""), encoding="utf-8")
    print(f"Wrote {args.output} ({max(0, len(csv_lines)-1)} nodes)")
    summary = next((line for line in lines if line.startswith("MODEL_AUDIT_SUMMARY")), None)
    if summary:
        print(summary)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
