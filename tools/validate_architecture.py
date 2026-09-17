#!/usr/bin/env python3
"""Validate Godot module boundaries and res:// references."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "architecture" / "policy.json"
RES_PATH = re.compile(r"""res://[^"'\s\)\]]+""")
AUTOLOAD_ENTRY = re.compile(r"""^[A-Za-z_][A-Za-z0-9_]*\s*=\s*"\*?(res://[^"]+)"\s*$""")


def add_error(errors: list[str], message: str) -> None:
    errors.append(message)


def load_json(path: Path, errors: list[str]) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        add_error(errors, f"Missing file: {path.relative_to(ROOT)}")
        return None
    except json.JSONDecodeError as exc:
        add_error(errors, f"Invalid JSON in {path.relative_to(ROOT)}: {exc}")
        return None
    if not isinstance(value, dict):
        add_error(errors, f"Expected JSON object: {path.relative_to(ROOT)}")
        return None
    return value


def discover_manifests(policy: dict[str, Any]) -> list[Path]:
    name = policy.get("manifest_name", "module.json")
    found: list[Path] = []
    for source_root in policy.get("source_roots", ["game"]):
        path = ROOT / source_root
        if path.exists():
            found.extend(sorted(path.rglob(name)))
    return found


def validate_manifest(
    path: Path,
    data: dict[str, Any],
    policy: dict[str, Any],
    errors: list[str],
) -> None:
    rel = path.relative_to(ROOT)
    for field in policy.get("module_required_fields", []):
        if field not in data:
            add_error(errors, f"{rel}: missing required field '{field}'")

    for field in ("id", "layer", "purpose"):
        if field in data and (not isinstance(data[field], str) or not data[field].strip()):
            add_error(errors, f"{rel}: '{field}' must be a non-empty string")

    for field in ("state_owner", "public_api", "dependencies"):
        value = data.get(field)
        if value is not None and (
            not isinstance(value, list)
            or any(not isinstance(item, str) or not item.strip() for item in value)
        ):
            add_error(errors, f"{rel}: '{field}' must be a list of non-empty strings")

    layer = data.get("layer")
    if layer not in policy.get("layers", {}):
        add_error(errors, f"{rel}: unknown layer '{layer}'")

    parts = rel.parts
    roots = set(policy.get("source_roots", []))
    if len(parts) >= 3 and parts[0] in roots:
        expected_layer = parts[1]
        if layer and layer != expected_layer:
            add_error(
                errors,
                f"{rel}: layer '{layer}' does not match directory '{expected_layer}'",
            )


def find_cycle(graph: dict[str, list[str]]) -> list[str] | None:
    visiting: set[str] = set()
    visited: set[str] = set()
    stack: list[str] = []

    def visit(node: str) -> list[str] | None:
        if node in visiting:
            return stack[stack.index(node):] + [node]
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


def owner_for(
    path: Path,
    modules: dict[str, tuple[Path, dict[str, Any]]],
) -> tuple[str, Path, dict[str, Any]] | None:
    matches: list[tuple[str, Path, dict[str, Any]]] = []
    for module_id, (manifest, data) in modules.items():
        module_root = manifest.parent
        try:
            path.relative_to(module_root)
        except ValueError:
            continue
        matches.append((module_id, module_root, data))
    if not matches:
        return None
    return max(matches, key=lambda item: len(item[1].parts))


def is_public_target(
    target: Path,
    target_root: Path,
    public_directories: set[str],
) -> bool:
    try:
        relative = target.relative_to(target_root)
    except ValueError:
        return False
    return bool(relative.parts) and relative.parts[0] in public_directories


def resolve_res_path(raw: str) -> Path:
    relative = raw.removeprefix("res://").split("::", 1)[0]
    return (ROOT / relative).resolve()


def validate_reference(
    source: Path,
    raw_target: str,
    modules: dict[str, tuple[Path, dict[str, Any]]],
    policy: dict[str, Any],
    errors: list[str],
) -> None:
    target = resolve_res_path(raw_target)
    rel_source = source.relative_to(ROOT)
    try:
        rel_target = target.relative_to(ROOT)
    except ValueError:
        add_error(errors, f"{rel_source}: reference escapes project: {raw_target}")
        return

    prefixes = tuple(policy.get("unowned_res_prefixes", []))
    if rel_target.as_posix().startswith(prefixes):
        return

    source_owner = owner_for(source, modules)
    target_owner = owner_for(target, modules)

    if source_owner is None:
        return
    if target_owner is None:
        source_roots = tuple(f"{root}/" for root in policy.get("source_roots", []))
        if rel_target.as_posix().startswith(source_roots):
            add_error(
                errors,
                f"{rel_source}: target inside game has no module manifest: {raw_target}",
            )
        return

    source_id, _, source_data = source_owner
    target_id, target_root, _ = target_owner
    if source_id == target_id:
        return

    dependencies = source_data.get("dependencies", [])
    if target_id not in dependencies:
        add_error(
            errors,
            f"{rel_source}: undeclared dependency '{target_id}' via {raw_target}",
        )
        return

    public_dirs = set(policy.get("public_directories", ["public"]))
    if not is_public_target(target, target_root, public_dirs):
        add_error(
            errors,
            f"{rel_source}: cross-module target is private: {raw_target}",
        )


def validate_godot_files(
    modules: dict[str, tuple[Path, dict[str, Any]]],
    policy: dict[str, Any],
    errors: list[str],
) -> None:
    extensions = set(policy.get("godot_reference_extensions", [".gd", ".tscn", ".tres"]))
    allowed_root_layers = set(policy.get("root_access_allowed_layers", []))

    for source_root in policy.get("source_roots", ["game"]):
        root = ROOT / source_root
        if not root.exists():
            continue
        for path in sorted(file for file in root.rglob("*") if file.suffix in extensions):
            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue

            owner = owner_for(path, modules)
            if path.suffix == ".gd" and owner is not None:
                layer = owner[2].get("layer")
                if layer not in allowed_root_layers and (
                    "/root/" in text or "get_tree().root" in text
                ):
                    add_error(
                        errors,
                        f"{path.relative_to(ROOT)}: SceneTree root access is forbidden "
                        f"in layer '{layer}'",
                    )

            for raw_target in sorted(set(RES_PATH.findall(text))):
                validate_reference(path, raw_target, modules, policy, errors)


def validate_autoloads(
    modules: dict[str, tuple[Path, dict[str, Any]]],
    policy: dict[str, Any],
    errors: list[str],
) -> None:
    project_file = ROOT / policy.get("engine", {}).get("project_file", "project.godot")
    try:
        lines = project_file.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return

    in_autoload = False
    allowed_layers = set(policy.get("autoload_allowed_layers", []))
    for line_number, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_autoload = stripped == "[autoload]"
            continue
        if not in_autoload or not stripped or stripped.startswith(";"):
            continue
        match = AUTOLOAD_ENTRY.match(stripped)
        if not match:
            add_error(errors, f"project.godot:{line_number}: invalid Autoload entry")
            continue
        raw_target = match.group(1)
        target = resolve_res_path(raw_target)
        owner = owner_for(target, modules)
        if owner is None:
            add_error(
                errors,
                f"project.godot:{line_number}: Autoload has no owning module: {raw_target}",
            )
            continue
        layer = owner[2].get("layer")
        if layer not in allowed_layers:
            add_error(
                errors,
                f"project.godot:{line_number}: Autoload layer '{layer}' is forbidden",
            )


def main() -> int:
    errors: list[str] = []
    policy = load_json(POLICY_PATH, errors)
    if policy is None:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    for required in policy.get("required_files", []):
        if not (ROOT / required).is_file():
            add_error(errors, f"Missing required architecture file: {required}")

    modules: dict[str, tuple[Path, dict[str, Any]]] = {}
    for path in discover_manifests(policy):
        data = load_json(path, errors)
        if data is None:
            continue
        validate_manifest(path, data, policy, errors)
        module_id = data.get("id")
        if not isinstance(module_id, str) or not module_id.strip():
            continue
        if module_id in modules:
            first = modules[module_id][0].relative_to(ROOT)
            add_error(
                errors,
                f"{path.relative_to(ROOT)}: duplicate id '{module_id}' "
                f"(first in {first})",
            )
        else:
            modules[module_id] = (path, data)

    graph: dict[str, list[str]] = {}
    for module_id, (path, data) in modules.items():
        dependencies = data.get("dependencies", [])
        if not isinstance(dependencies, list):
            continue
        graph[module_id] = [value for value in dependencies if isinstance(value, str)]
        source_layer = data.get("layer")
        allowed = set(
            policy.get("layers", {})
            .get(source_layer, {})
            .get("allowed_dependency_layers", [])
        )
        for dependency_id in graph[module_id]:
            target = modules.get(dependency_id)
            if target is None:
                add_error(
                    errors,
                    f"{path.relative_to(ROOT)}: unknown dependency '{dependency_id}'",
                )
                continue
            target_layer = target[1].get("layer")
            if target_layer not in allowed:
                add_error(
                    errors,
                    f"{path.relative_to(ROOT)}: layer '{source_layer}' may not depend "
                    f"on '{target_layer}' module '{dependency_id}'",
                )

    cycle = find_cycle(graph)
    if cycle:
        add_error(errors, "Dependency cycle: " + " -> ".join(cycle))

    validate_godot_files(modules, policy, errors)
    validate_autoloads(modules, policy, errors)

    if errors:
        print("Godot architecture validation failed:")
        for error in errors:
            print(f"  - {error}")
        return 1

    references = sum(
        1
        for root_name in policy.get("source_roots", ["game"])
        for path in (ROOT / root_name).rglob("*")
        if path.suffix in set(policy.get("godot_reference_extensions", []))
    )
    print(
        f"Godot architecture validation passed: {len(modules)} module(s), "
        f"{sum(len(items) for items in graph.values())} dependency edge(s), "
        f"{references} Godot source file(s)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
