#!/usr/bin/env python3
"""Fail when code or scenes name a res:// file that is not in the repository.

ext_resource paths are covered by validate_scene_resources.py; this also
covers preload/load strings, exported model_path values and JSON data,
which Godot only reports when the game reaches them. It also reports
committed .import files whose source asset was deleted.

Not checked: tests (they probe missing files on purpose), formatted paths
("%s", "{...}"), directories, and dictionary keys ("res://old": "res://new"),
which hold migration sources that are expected to be gone.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUFFIXES = {".gd", ".tscn", ".tres", ".json", ".gdshader", ".cfg", ".godot"}
LITERAL = re.compile(r'"res://([^"]+)"(\s*:)?')


def tracked() -> list[str]:
    output = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    return [path for path in output.decode("utf-8").split("\0") if path]


def main() -> int:
    files = tracked()
    present = set(files)
    errors = []
    for rel in files:
        path = ROOT / rel
        if path.suffix not in SUFFIXES or "/tests/" in rel or rel.startswith((".github/", "templates/")):
            continue
        if path.suffix == ".import" or not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for number, line in enumerate(text.splitlines(), 1):
            for match in LITERAL.finditer(line):
                target, is_key = match.group(1), match.group(2)
                if is_key or any(mark in target for mark in ("%", "{", "*")) or target.endswith("/"):
                    continue
                if target.startswith(".godot/") or target in present or (ROOT / target).is_dir():
                    continue
                errors.append(f"{rel}:{number}: missing res://{target}")
    for rel in files:
        if rel.endswith(".import") and rel[: -len(".import")] not in present:
            errors.append(f"{rel}: source asset is gone; delete this .import file")
    if errors:
        print("Resource path check failed:")
        for error in errors:
            print("  -", error)
        return 1
    print("Resource paths OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
