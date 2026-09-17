#!/usr/bin/env python3
"""Validate the active GAME_SPEC.md structure and readiness."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / "GAME_SPEC.md"

REQUIRED_META = (
    "spec_version",
    "status",
    "current_phase",
    "game_id",
    "title",
    "owner",
    "last_updated",
)

REQUIRED_SECTIONS = (
    "## 00. AI operating contract",
    "## 01. Document status",
    "## 02. Game identity",
    "## 03. Audience and product",
    "## 04. Experience pillars",
    "## 05. Platforms, input and constraints",
    "## 06. Core loop",
    "## 07. Game flow and states",
    "## 08. Mechanics registry",
    "## 09. Mechanic specification",
    "## 10. Player and controllable entities",
    "## 11. World and level structure",
    "## 12. Content model",
    "## 13. Progression and economy",
    "## 14. Combat or primary conflict",
    "## 15. NPC and game AI",
    "## 16. UI, UX and accessibility",
    "## 17. Visual and audio direction",
    "## 18. Save, loading and settings",
    "## 19. Multiplayer and social",
    "## 20. Technical budgets",
    "## 21. Scope",
    "## 22. Quality and acceptance",
    "## 23. Risks, legal and dependencies",
    "## 24. Sequential development plan",
    "## 25. Current milestone and task queue",
    "## 26. Decisions and open questions",
    "## 27. Change log",
)

PLACEHOLDER = re.compile(r"\{\{[^{}]+\}\}")
META_LINE = re.compile(r"^([a-z_]+):\s*(.+?)\s*$")


def parse_front_matter(text: str) -> dict[str, str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    result: dict[str, str] = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        match = META_LINE.match(line)
        if match:
            result[match.group(1)] = match.group(2)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--ready",
        action="store_true",
        help="Fail unless the specification is ready for gameplay implementation.",
    )
    args = parser.parse_args()

    errors: list[str] = []
    try:
        text = SPEC.read_text(encoding="utf-8")
    except FileNotFoundError:
        print("GAME_SPEC.md is missing.")
        return 1

    meta = parse_front_matter(text)
    for key in REQUIRED_META:
        if key not in meta:
            errors.append(f"front matter is missing '{key}'")

    status = meta.get("status")
    if status not in {"DRAFT", "READY", "LOCKED"}:
        errors.append("status must be DRAFT, READY, or LOCKED")

    phase = meta.get("current_phase", "")
    if not phase.isdigit() or not 0 <= int(phase) <= 8:
        errors.append("current_phase must be an integer from 0 to 8")

    cursor = -1
    for section in REQUIRED_SECTIONS:
        position = text.find(section)
        if position < 0:
            errors.append(f"missing section: {section}")
        elif position <= cursor:
            errors.append(f"section is out of order: {section}")
        else:
            cursor = position

    if args.ready:
        if status not in {"READY", "LOCKED"}:
            errors.append("status must be READY or LOCKED")
        placeholders = PLACEHOLDER.findall(text)
        if placeholders:
            errors.append(f"{len(placeholders)} placeholder(s) remain")
        blockers = text.count("[BLOCKER]")
        if blockers:
            errors.append(f"{blockers} blocking question marker(s) remain")

    if errors:
        print("Game specification validation failed:")
        for error in errors:
            print(f"  - {error}")
        return 1

    if args.ready:
        print(f"Game specification is ready for phase {phase}.")
    else:
        placeholders = len(PLACEHOLDER.findall(text))
        print(
            f"Game specification structure is valid: status={status}, "
            f"phase={phase}, placeholders={placeholders}."
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
