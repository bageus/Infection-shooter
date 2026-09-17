#!/usr/bin/env python3
"""Run all repository gates, enabling strict checks after discovery."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / "GAME_SPEC.md"


def specification_status() -> str:
    text = SPEC.read_text(encoding="utf-8")
    match = re.search(r"^status:\s*(DRAFT|READY|LOCKED)\s*$", text, re.MULTILINE)
    if not match:
        return "INVALID"
    return match.group(1)


def run(command: list[str]) -> int:
    print("+", " ".join(command), flush=True)
    return subprocess.run(command, cwd=ROOT, check=False).returncode


def main() -> int:
    status = specification_status()
    if status == "INVALID":
        print("Unable to determine GAME_SPEC.md status.")
        return 1

    python = sys.executable
    commands = [
        [python, "tools/validate_game_spec.py"],
        [python, "tools/validate_workflow_state.py"],
        [python, "tools/validate_architecture.py"],
    ]

    if status in {"READY", "LOCKED"}:
        commands.insert(1, [python, "tools/validate_game_spec.py", "--ready"])
        commands.insert(3, [python, "tools/validate_workflow_state.py", "--ready"])

    print(f"Project validation mode: {status}")
    failed = False
    for command in commands:
        if run(command) != 0:
            failed = True

    if failed:
        print("Project validation failed.")
        return 1
    print("Project validation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
