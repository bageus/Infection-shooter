#!/usr/bin/env python3
"""Validate declarative boundaries for the game architecture template."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "architecture" / "policy.json"


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def load_json(path: Path, errors: list[str]) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(errors, f"Missing file: {path.relative_to(ROOT)}")
        return None
    except json.JSONDecodeError as exc:
        fail(errors, f"Invalid JSON in {path.relative_to(ROOT)}: {exc}")
        return None
    if not isinstance(value, dict):
        fail(errors, f"Expected JSON object: {path.relative_to(ROOT)}")
        return None
    return value


def discover_manifests(policy: dict[str, Any]) -> list[Path]:
    name = policy.get("manifest_name", "module.json")
    manifests: list[Path] = []
    for source_root in policy.get("source_roots", ["src"]):
        root = ROOT / source_root
        if root.exists():
            manifests.extend(sorted(root.rglob(name)))
    return manifests


def validate_manifest_shape(
    path: Path,
    data: dict[str, Any],
    policy: dict[str, Any],
    errors: list[str],
) -> None:
    rel = path.relative_to(ROOT)
    for field in policy.get("module_required_fields", []):
        if field not in data:
            fail(errors, f"{rel}: missing required field '{field}'")

    for field in ("id", "layer", "purpose"):
        if field in data and (not isinstance(data[field], str) or not data[field].strip()):
            fail(errors, f"{rel}: '{field}' must be a non-empty string")

    for field in ("state_owner", "public_api", "dependencies"):
        if field in data and (
            not isinstance(data[field], list)
            or any(not isinstance(item, str) or not item.strip() for item in data[field])
        ):
            fail(errors, f"{rel}: '{field}' must be a list of non-empty strings")

    layer = data.get("layer")
    if layer not in policy.get("layers", {}):
        fail(errors, f"{rel}: unknown layer '{layer}'")

    parts = rel.parts
    if len(parts) >= 3 and parts[0] in policy.get("source_roots", []):
        expected_layer = parts[1]
        if layer and layer != expected_layer:
            fail(
                errors,
                f"{rel}: manifest layer '{layer}' does not match directory '{expected_layer}'",
            )


def find_cycle(graph: dict[str, list[str]]) -> list[str] | None:
    visiting: set[str] = set()
    visited: set[str] = set()
    stack: list[str] = []

    def visit(node: str) -> list[str] | None:
        if node in visiting:
            start = stack.index(node)
            return stack[start:] + [node]
        if node in visited:
            return None
        visiting.add(node)
        stack.append(node)
        for dependency in graph.get(node, []):
            cycle = visit(dependency)
            if cycle:
                return cycle
        stack.pop()
        visiting.remove(node)
        visited.add(node)
        return None

    for node in graph:
        cycle = visit(node)
        if cycle:
            return cycle
    return None


def main() -> int:
    errors: list[str] = []
    policy = load_json(POLICY_PATH, errors)
    if policy is None:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    for required in policy.get("required_files", []):
        if not (ROOT / required).is_file():
            fail(errors, f"Missing required architecture file: {required}")

    modules: dict[str, tuple[Path, dict[str, Any]]] = {}
    for path in discover_manifests(policy):
        data = load_json(path, errors)
        if data is None:
            continue
        validate_manifest_shape(path, data, policy, errors)
        module_id = data.get("id")
        if not isinstance(module_id, str) or not module_id.strip():
            continue
        if module_id in modules:
            first = modules[module_id][0].relative_to(ROOT)
            fail(
                errors,
                f"{path.relative_to(ROOT)}: duplicate module id '{module_id}' "
                f"(first declared in {first})",
            )
        else:
            modules[module_id] = (path, data)

    graph: dict[str, list[str]] = {}
    for module_id, (path, data) in modules.items():
        rel = path.relative_to(ROOT)
        dependencies = data.get("dependencies", [])
        if not isinstance(dependencies, list):
            continue
        graph[module_id] = [dep for dep in dependencies if isinstance(dep, str)]
        source_layer = data.get("layer")
        allowed = set(
            policy.get("layers", {})
            .get(source_layer, {})
            .get("allowed_dependency_layers", [])
        )
        for dependency_id in graph[module_id]:
            target = modules.get(dependency_id)
            if target is None:
                fail(errors, f"{rel}: unknown dependency '{dependency_id}'")
                continue
            target_layer = target[1].get("layer")
            if target_layer not in allowed:
                fail(
                    errors,
                    f"{rel}: layer '{source_layer}' may not depend on "
                    f"'{target_layer}' module '{dependency_id}'",
                )

    cycle = find_cycle(graph)
    if cycle:
        fail(errors, "Dependency cycle: " + " -> ".join(cycle))

    if errors:
        print("Architecture validation failed:")
        for error in errors:
            print(f"  - {error}")
        return 1

    print(
        f"Architecture validation passed: {len(modules)} module(s), "
        f"{sum(len(deps) for deps in graph.values())} dependency edge(s)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
