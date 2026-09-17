#!/usr/bin/env python3
"""Enforce source-size guardrails without encouraging arbitrary file splitting."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "architecture" / "policy.json"
FUNCTION_START = re.compile(r"^(?P<indent>[ \t]*)(?:static\s+)?func\s+[A-Za-z_][A-Za-z0-9_]*\s*\(")


def load_policy() -> dict[str, Any]:
    return json.loads(POLICY_PATH.read_text(encoding="utf-8"))


def indentation(line: str) -> int:
    prefix = line[: len(line) - len(line.lstrip(" \t"))]
    return sum(4 if char == "\t" else 1 for char in prefix)


def function_spans(lines: list[str]) -> list[tuple[int, int]]:
    starts: list[tuple[int, int]] = []
    for index, line in enumerate(lines):
        match = FUNCTION_START.match(line)
        if match:
            starts.append((index, indentation(line)))

    spans: list[tuple[int, int]] = []
    for start, base_indent in starts:
        end = len(lines)
        for index in range(start + 1, len(lines)):
            stripped = lines[index].strip()
            if not stripped or stripped.startswith("#") or stripped.startswith("@"):
                continue
            if indentation(lines[index]) <= base_indent:
                end = index
                break
        spans.append((start + 1, max(1, end - start)))
    return spans


def is_test(path: Path) -> bool:
    parts = {part.lower() for part in path.parts}
    name = path.name.lower()
    return "tests" in parts or name.startswith("test_") or name.endswith("_test.gd")


def exception_for(
    relative: str, exceptions: list[dict[str, Any]]
) -> dict[str, Any] | None:
    for item in exceptions:
        if item.get("path") == relative:
            return item
    return None


def main() -> int:
    policy = load_policy()
    config = policy.get("source_size_policy", {})
    extensions = set(config.get("extensions", [".gd"]))
    source_roots = policy.get("source_roots", ["game"])
    excluded = tuple(config.get("excluded_path_prefixes", []))
    exceptions = config.get("exceptions", [])

    warnings: list[str] = []
    errors: list[str] = []
    checked = 0

    for source_root in source_roots:
        root = ROOT / source_root
        if not root.exists():
            continue
        for path in sorted(file for file in root.rglob("*") if file.suffix in extensions):
            relative = path.relative_to(ROOT).as_posix()
            if relative.startswith(excluded):
                continue
            checked += 1
            lines = path.read_text(encoding="utf-8").splitlines()
            test_file = is_test(path)
            warning_limit = int(
                config.get("test_warning_lines" if test_file else "warning_lines", 300)
            )
            error_limit = int(
                config.get("test_error_lines" if test_file else "error_lines", 600)
            )

            exception = exception_for(relative, exceptions)
            if exception is not None:
                adr = exception.get("adr")
                maximum = exception.get("max_lines")
                if not isinstance(adr, str) or not (ROOT / adr).is_file():
                    errors.append(f"{relative}: size exception has no valid ADR")
                    continue
                if not isinstance(maximum, int) or maximum <= error_limit:
                    errors.append(f"{relative}: size exception max_lines must exceed default")
                    continue
                error_limit = maximum

            count = len(lines)
            if count > error_limit:
                errors.append(
                    f"{relative}: {count} lines exceeds hard limit {error_limit}; "
                    "split by responsibility or register an ADR-backed exception"
                )
            elif count > warning_limit:
                warnings.append(
                    f"{relative}: {count} lines exceeds review threshold {warning_limit}"
                )

            function_warning = int(config.get("function_warning_lines", 50))
            function_error = int(config.get("function_error_lines", 100))
            for start_line, span in function_spans(lines):
                if span > function_error:
                    errors.append(
                        f"{relative}:{start_line}: function spans {span} lines, "
                        f"hard limit is {function_error}"
                    )
                elif span > function_warning:
                    warnings.append(
                        f"{relative}:{start_line}: function spans {span} lines, "
                        f"review threshold is {function_warning}"
                    )

    if warnings:
        print("Source-size warnings:")
        for warning in warnings:
            print(f"  - {warning}")

    if errors:
        print("Source-size validation failed:")
        for error in errors:
            print(f"  - {error}")
        return 1

    print(
        f"Source-size validation passed: {checked} file(s), "
        f"{len(warnings)} warning(s)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
