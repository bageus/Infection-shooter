"""Check engine-generated PCK inventories without depending on a PCK version."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRS = (
    "models/objects/enviroments/01/textures/master_4k/",
    "models/objects/weapons/textures/master_4k/",
    "models/objects/textures/blood_decals_45/source/",
)


def check_sources():
    """Only these verified authoring folders may be excluded, never all models."""
    errors = []
    presets = (ROOT / "export_presets.cfg").read_text()
    filters = re.findall(r'^exclude_filter="(.*)"$', presets, re.M)
    for folder in SOURCE_DIRS:
        if not filters or any(folder + "*" not in value for value in filters):
            errors.append(f"Export preset lacks explicit exclusion: {folder}")
    for folder in (ROOT / "game", ROOT / "models", ROOT / "assets"):
        for path in folder.rglob("*"):
            if not path.is_file() or path.suffix not in {".gd", ".tscn", ".tres", ".import", ".json"}:
                continue
            if "tests" in path.parts:
                continue
            text = path.read_text(errors="replace")
            # Match quoted runtime paths; explanatory comments are not references.
            for target in re.findall(r'["\'](res://[^"\']+)["\']', text):
                if any(target.removeprefix("res://").startswith(source) for source in SOURCE_DIRS):
                    errors.append(f"Excluded source is referenced by {path.relative_to(ROOT)}: {target}")
    return errors


def check_inventory(inventory, baseline=None):
    errors = []
    current = set(json.loads(Path(inventory).read_text()))
    for path in current:
        if any(path.removeprefix("res://").startswith(folder) for folder in SOURCE_DIRS):
            errors.append(f"Authoring source included in PCK: {path}")
    if baseline:
        previous = set(json.loads(Path(baseline).read_text()))
        for path in sorted(previous - current):
            if not any(path.removeprefix("res://").startswith(folder) for folder in SOURCE_DIRS):
                errors.append(f"Runtime file lost from PCK: {path}")
    # String paths are not dependency edges: keep the all_resources export and
    # check the actual pack for every concrete existing production reference.
    required = set()
    for path in (ROOT / "game").rglob("*"):
        if not path.is_file() or "tests" in path.parts or path.suffix not in {".gd", ".tscn", ".tres"}:
            continue
        for target in re.findall(r'["\'](res://[^"\']+)["\']', path.read_text()):
            local = ROOT / target.removeprefix("res://")
            if local.is_file():
                required.add(target)
    for target in sorted(required):
        if not any(candidate in current for candidate in (target, target + ".import", target + ".remap")):
            errors.append(f"Concrete runtime reference missing from PCK: {target}")
    print(f"PCK: {len(current)} files; {len(required)} concrete runtime references checked")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory")
    parser.add_argument("--baseline")
    args = parser.parse_args()
    errors = check_sources()
    if args.inventory:
        errors += check_inventory(args.inventory, args.baseline)
    if errors:
        raise SystemExit("\n".join(errors))
    print("Export source/pack audit passed")


if __name__ == "__main__":
    main()
