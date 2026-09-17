#!/usr/bin/env python3
"""Validate continuity files that keep AI work focused across sessions."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLACEHOLDER = re.compile(r"\{\{[^{}]+\}\}")
META_LINE = re.compile(r"^([a-z_]+):\s*(.+?)\s*$")

FILES = {
    "spec": ROOT / "GAME_SPEC.md",
    "project": ROOT / "PROJECT_STATE.md",
    "task": ROOT / "ACTIVE_TASK.md",
    "backlog": ROOT / "BACKLOG.md",
    "agreement": ROOT / "docs" / "WORKING_AGREEMENT.md",
}

REQUIRED_SECTIONS = {
    "project": (
        "## Current outcome",
        "## Current phase",
        "## Current milestone",
        "## Active task",
        "## Build and validation",
        "## Known blockers",
        "## Next action",
        "## Handoff notes",
    ),
    "task": (
        "## Goal",
        "## In scope",
        "## Out of scope",
        "## Acceptance criteria",
        "## Progress",
        "## Validation evidence",
        "## Blockers",
        "## Next exact action",
        "## Session handoff",
    ),
    "backlog": ("## Ready queue", "## Planned", "## Icebox", "## Completed"),
    "agreement": (
        "## Roles by mode",
        "## Communication",
        "## Autonomy",
        "## Git workflow",
        "## Validation",
        "## Owner confirmation",
    ),
}


def front_matter(text: str) -> dict[str, str]:
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


def read_all(errors: list[str]) -> dict[str, tuple[str, dict[str, str]]]:
    values = {}
    for key, path in FILES.items():
        try:
            text = path.read_text(encoding="utf-8")
        except FileNotFoundError:
            errors.append(f"missing file: {path.relative_to(ROOT)}")
            continue
        values[key] = (text, front_matter(text))
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ready", action="store_true")
    args = parser.parse_args()
    errors: list[str] = []
    values = read_all(errors)

    for key, sections in REQUIRED_SECTIONS.items():
        if key not in values:
            continue
        text = values[key][0]
        cursor = -1
        for section in sections:
            pos = text.find(section)
            if pos < 0:
                errors.append(f"{FILES[key].relative_to(ROOT)}: missing '{section}'")
            elif pos <= cursor:
                errors.append(f"{FILES[key].relative_to(ROOT)}: section out of order '{section}'")
            else:
                cursor = pos

    spec = values.get("spec", ("", {}))[1]
    project = values.get("project", ("", {}))[1]
    task = values.get("task", ("", {}))[1]
    agreement = values.get("agreement", ("", {}))[1]

    spec_status = spec.get("status")
    task_status = task.get("status")
    if spec_status not in {"DRAFT", "READY", "LOCKED"}:
        errors.append("GAME_SPEC.md: invalid status")
    if task_status not in {"EMPTY", "READY", "IN_PROGRESS", "BLOCKED", "REVIEW", "DONE"}:
        errors.append("ACTIVE_TASK.md: invalid status")

    if spec_status == "DRAFT":
        if project.get("status") != "DISCOVERY":
            errors.append("PROJECT_STATE.md must be DISCOVERY while specification is DRAFT")
        if task.get("task_id") != "NONE" or task_status != "EMPTY":
            errors.append("ACTIVE_TASK.md must be EMPTY/NONE during discovery")

    if args.ready:
        if spec_status not in {"READY", "LOCKED"}:
            errors.append("GAME_SPEC.md is not ready")
        if agreement.get("status") != "ACCEPTED":
            errors.append("working agreement is not ACCEPTED")
        for key in ("spec", "project", "task", "agreement"):
            if key in values:
                count = len(PLACEHOLDER.findall(values[key][0]))
                if count:
                    errors.append(f"{FILES[key].relative_to(ROOT)} has {count} placeholder(s)")
        spec_phase = spec.get("current_phase")
        if project.get("current_phase") != spec_phase:
            errors.append("PROJECT_STATE and GAME_SPEC phases differ")
        if task.get("phase") != spec_phase:
            errors.append("ACTIVE_TASK and GAME_SPEC phases differ")
        task_id = task.get("task_id", "NONE")
        if task_id == "NONE" or task_status == "EMPTY":
            errors.append("no active implementation task")
        elif task_id not in values.get("backlog", ("", {}))[0]:
            errors.append(f"active task '{task_id}' is absent from BACKLOG.md")
        if project.get("active_task_id") != task_id:
            errors.append("PROJECT_STATE active_task_id differs from ACTIVE_TASK")

    if errors:
        print("Workflow state validation failed:")
        for error in errors:
            print(f"  - {error}")
        return 1

    print(
        f"Workflow state valid: spec={spec_status}, "
        f"project={project.get('status')}, task={task.get('task_id')}/{task_status}."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
