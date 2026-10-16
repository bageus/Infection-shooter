"""Offline SFX ownership, conflict checks and staged publication (stdlib only)."""
from __future__ import annotations

import hashlib
import json
import re
import tempfile
from pathlib import Path

MANIFEST = Path(__file__).with_name("audio_generation_manifest.json")
NAME = re.compile(r"[a-z][a-z0-9_]*")
SHA256 = re.compile(r"[0-9a-f]{64}")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def protected_events(root: Path) -> set[str]:
    """Import receipts remain authoritative when new recordings are admitted."""
    result = set()
    for name in ("audio_refresh_processing.json", "added_audio_processing.json", "enemy_voice_groups.json"):
        receipt = root.parent / name
        if not receipt.exists():
            continue
        data = json.loads(receipt.read_text(encoding="utf-8"))
        def visit(value):
            if isinstance(value, dict):
                for key, item in value.items():
                    if key in ("output", "files"):
                        paths = item if isinstance(item, list) else [item]
                        for path in paths:
                            prefix = "assets/audio/sfx/"
                            path = str(path).removeprefix("res://")
                            if path.startswith(prefix):
                                result.add(path[len(prefix):].split("/")[0])
                    else:
                        visit(item)
            elif isinstance(value, list):
                for item in value:
                    visit(item)
        visit(data)
    return result


class AudioBuild:
    def __init__(self, root: Path, owner: str, only=None, manifest: Path = MANIFEST):
        self.root = root
        self.owner = owner
        self.manifest = manifest
        self.original_manifest = manifest.read_bytes()
        self.data = json.loads(self.original_manifest)
        if self.data.get("version") != 1 or owner not in self.data["generators"]:
            raise ValueError("Unsupported audio generation manifest/owner")
        self.blocked = set(self.data["protected_events"]) | set(self.data["retired_events"]) | protected_events(root)
        seen = set()
        for outputs in self.data["generators"].values():
            for relative, sha in outputs.items():
                event, sep, filename = relative.partition("/")
                if not NAME.fullmatch(event) or not sep or not re.fullmatch(re.escape(event) + r"_[1-9][0-9]*\.ogg", filename):
                    raise ValueError("Invalid generated audio path: " + relative)
                if relative in seen or event in self.blocked or not isinstance(sha, str) or not SHA256.fullmatch(sha):
                    raise ValueError("Conflicting audio ownership: " + relative)
                seen.add(relative)
        self.owned = self.data["generators"][owner]
        self.events = {p.split("/")[0] for p in self.owned}
        if only is not None:
            if not only or not set(only) <= self.events:
                raise ValueError("Unknown, authored or retired audio event: " + ", ".join(sorted(set(only) - self.events)))
            self.events = set(only)
        self.outputs = sorted(p for p in self.owned if p.split("/")[0] in self.events)
        self.preflight()

    def preflight(self):
        if self.manifest.read_bytes() != self.original_manifest:
            raise ValueError("Audio manifest changed during generation; retry from the new manifest")
        if protected_events(self.root) & self.events:
            raise ValueError("An import receipt protects a selected event")
        for relative in self.outputs:
            path = self.root / relative
            if self.root.is_symlink() or path.parent.is_symlink() or path.is_symlink():
                raise ValueError("Symlink is not a generated audio destination: " + str(path))
            if path.exists() and (not path.is_file() or digest(path) != self.owned[relative]):
                raise ValueError("Audio was changed outside its generator: " + str(path))
        credits = self.root.parent / "CREDITS.md"
        if credits.is_symlink() or self.manifest.is_symlink():
            raise ValueError("Credits/manifest must be regular files")

    def describe(self):
        print(json.dumps({"generator": self.owner, "replace_or_restore": self.outputs,
                          "delete": [], "protected_events": sorted(self.blocked)}, indent=2))

    def publish(self, stage: Path, credits: dict[str, str]):
        """Only complete encodes are admitted; unlisted files are never cleaned up."""
        staged = sorted(p.relative_to(stage).as_posix() for p in stage.rglob("*") if p.is_file())
        if staged != self.outputs or set(credits) != self.events:
            raise ValueError("Recipe outputs/credits differ from the selected manifest paths")
        self.preflight()  # Recheck edits made while decoding/encoding was running.
        credits_path = self.root.parent / "CREDITS.md"
        text = credits_path.read_bytes().decode("utf-8") if credits_path.exists() else "# Sound credits\n"
        for event, content in sorted(credits.items()):
            begin = f"<!-- BEGIN GENERATED AUDIO {self.owner}:{event} -->"
            end = f"<!-- END GENERATED AUDIO {self.owner}:{event} -->"
            block = begin + "\n" + content.rstrip() + "\n" + end
            if text.count(begin) != text.count(end) or text.count(begin) > 1:
                raise ValueError("Malformed generated credits section: " + event)
            if begin in text:
                start, finish = text.index(begin), text.index(end)
                if start >= finish:
                    raise ValueError("Reversed credits markers: " + event)
                text = text[:start] + block + text[finish + len(end):]
            else:
                text = text + ("" if text.endswith("\n\n") else "\n\n") + block + "\n"
        for relative in self.outputs:
            self.owned[relative] = digest(stage / relative)
        writes = {self.root / p: (stage / p).read_bytes() for p in self.outputs}
        writes[credits_path] = text.encode("utf-8")
        writes[self.manifest] = (json.dumps(self.data, indent=2, sort_keys=True) + "\n").encode()
        backups = {p: p.read_bytes() if p.exists() else None for p in writes}
        completed = []
        try:
            for path, content in writes.items():
                _replace(path, content)
                completed.append(path)
        except Exception:
            for path in reversed(completed):
                if backups[path] is None:
                    path.unlink()
                else:
                    _replace(path, backups[path])
            raise


def _replace(path: Path, content: bytes):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".audio_", delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(content)
            stream.close()
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
