#!/usr/bin/env python3
"""Check serialized resource paths without treating migration strings as loads."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
RESOURCE_PATH = re.compile(r'^\[ext_resource\b[^\n]*\bpath="res://([^"]+)"', re.MULTILINE)


def main() -> int:
    errors = []
    checked = 0
    for path in sorted((ROOT / "game").rglob("*")):
        if path.suffix not in {".tscn", ".tres"}:
            continue
        for target in RESOURCE_PATH.findall(path.read_text(encoding="utf-8")):
            checked += 1
            if not (ROOT / target).is_file():
                errors.append(f"{path.relative_to(ROOT)}: missing res://{target}")
    if errors:
        print("Scene resource validation failed:")
        for error in errors:
            print(f"  - {error}")
        return 1
    print(f"Scene resource validation passed: {checked} reference(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
