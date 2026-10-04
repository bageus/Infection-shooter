#!/usr/bin/env python3
"""Fail when a committed Godot .import file records a failed import.

An editor that cannot import an asset (crash mid-import, failed VRAM
compression, locked file) writes `valid=false` and drops the imported path;
the game then cannot load that texture or model at all.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    tracked = subprocess.run(["git", "ls-files", "*.import"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.splitlines()
    broken = []
    for rel in tracked:
        path = ROOT / rel
        if path.is_file() and "\nvalid=false" in path.read_text(encoding="utf-8", errors="ignore"):
            broken.append(rel)
    if broken:
        print("Failed imports committed (valid=false) — reimport them in the editor:")
        for rel in broken:
            print("  -", rel)
        return 1
    print(f"Import files valid: {len(tracked)} checked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
