#!/usr/bin/env python3
"""Require every game/**/tests/run_*.gd to have an executable CI registration."""
from __future__ import annotations

from collections import Counter
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ".github/runtime_suites.txt"
SPECIAL = ".github/suite_jobs.json"
WORKFLOW = ".github/workflows/mission_runtime.yml"


def job_source(source: str, job: str) -> str:
    # Workflows use two-space job keys. Reject unknown structures rather than
    # treating a path in a trigger/filter/comment as a scheduled suite.
    lines = source.splitlines()
    start = next((i for i, line in enumerate(lines) if line == f"  {job}:"), None)
    if start is None:
        return ""
    end = next((i for i in range(start + 1, len(lines))
                if re.match(r"^  [\w-]+:", lines[i]) or
                (lines[i].strip() and not lines[i].startswith(" ") and not lines[i].startswith("#"))), len(lines))
    return "\n".join(lines[start + 1:end])


def run_commands(source: str) -> str:
    """Read the literal/inline run scalars used here; this is not a YAML parser."""
    commands = []
    lines = source.splitlines()
    for index, line in enumerate(lines):
        match = re.match(r"^(\s*)(?:- )?run: (.*)$", line)
        if not match:
            continue
        value = match[2]
        if value != "|":
            if value and not value.startswith(("#", ">", "'", '"')):
                commands.append(value)
            continue
        indent = len(match[1]) + (2 if line.lstrip().startswith("- ") else 0)
        for body in lines[index + 1:]:
            if body.strip() and len(body) - len(body.lstrip()) <= indent:
                break
            if body.strip() and not body.lstrip().startswith("#"):
                commands.append(body.strip())
    return "\n".join(commands)


def invokes_suite(commands: str, path: str) -> bool:
    target = r"(?:res://)?" + re.escape(path)
    godot = r"(?m)^(?:timeout \d+ )?(?:xvfb-run -a )?godot\b[^\n]*?--script\s+"
    if re.search(godot + target + r"(?=\s|$)", commands):
        return True
    # The existing integration/native jobs execute an explicit shell for list.
    for match in re.finditer(r"for (\w+) in ([^;\n]+); do\n", commands):
        variable, items = match.groups()
        body = commands[match.end():].split("\ndone", 1)[0]
        if path in items.split() and re.search(godot + r'"\$' + re.escape(variable) + r'"', body):
            return True
    return False


def validate(root: Path) -> tuple[list[str], str]:
    discovered = {p.relative_to(root).as_posix() for p in (root / "game").rglob("run_*.gd")
                  if "tests" in p.relative_to(root / "game").parts}
    suites = (root / MANIFEST).read_text().splitlines()
    special = json.loads((root / SPECIAL).read_text())
    errors = []
    if not discovered or not suites:
        errors.append("Empty test discovery or runtime manifest")
    for path, count in Counter(suites).items():
        if count > 1:
            errors.append(f"Duplicate runtime suite: {path}")
    for name, count in Counter(Path(p).stem for p in suites).items():
        if count > 1:
            errors.append(f"Runtime log/user-dir name collision: {name}")
    for path in sorted(set(suites) & set(special)):
        errors.append(f"Suite registered in both lists: {path}")
    registered = set(suites) | set(special)
    errors.extend(f"Unregistered suite: {p}" for p in sorted(discovered - registered))
    errors.extend(f"Stale or invalid suite: {p}" for p in sorted(registered - discovered))
    runtime = run_commands(job_source((root / WORKFLOW).read_text(), "runtime"))
    invocation = r"(?m)^(?:bash )?tools/run_runtime_suites\.sh " + re.escape(MANIFEST) + r"(?:\s|$)"
    if not re.search(invocation, runtime):
        errors.append("Runtime job does not execute the canonical manifest")
    for path, entry in special.items():
        if not isinstance(entry, dict) or set(entry) != {"workflow", "job", "mode", "reason"}:
            errors.append(f"Invalid special registration: {path}")
            continue
        if not all(isinstance(v, str) and v.strip() for v in entry.values()) or entry["mode"] not in {"headless", "native", "isolated"}:
            errors.append(f"Missing mode/job/reason: {path}")
            continue
        workflow = entry["workflow"]
        if not re.fullmatch(r"\.github/workflows/[\w-]+\.yml", workflow) or not (root / workflow).is_file():
            errors.append(f"Unknown workflow: {path}")
            continue
        commands = run_commands(job_source((root / workflow).read_text(), entry["job"]))
        if not invokes_suite(commands, path):
            errors.append(f"Special job does not execute suite: {path}")
    summary = f"{len(discovered)} discovered: {len(suites)} runtime, {len(special)} explicit job registrations"
    return errors, summary


def main() -> int:
    try:
        errors, summary = validate(ROOT)
    except (OSError, ValueError, TypeError, AttributeError) as error:
        print(f"CI suite coverage invalid: {error}")
        return 1
    for error in errors:
        print(error)
    print(f"CI suite coverage {'FAILED' if errors else 'PASS'}: {summary}")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
