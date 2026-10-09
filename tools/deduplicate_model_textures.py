#!/usr/bin/env python3
"""Share byte-identical model images without changing texture import profiles.

Default: inspect only. --apply rewrites GLB image URIs, removes redundant
embedded payloads and deletes replaced tracked textures with their imports.
Ignored authoring directories are excluded. No image is resized or re-encoded.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import struct
import subprocess
from collections import defaultdict
from pathlib import Path
from urllib.parse import quote, unquote

ROOT = Path(__file__).resolve().parents[1]
IMAGE_TYPES = {'.png', '.jpg', '.jpeg'}
TEXT_TYPES = {'.gd', '.gdshader', '.tscn', '.tres', '.json', '.py', '.cfg', '.godot', '.import'}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def active(path: Path, root: Path | None = None) -> bool:
    root = ROOT if root is None else root
    return not any((parent / '.gdignore').exists() for parent in path.parents if parent != root.parent)


def read_glb(data: bytes, path: Path | None = None) -> tuple[dict, bytes]:
    magic, version, length = struct.unpack_from('<III', data)
    if magic != 0x46546C67 or version != 2 or length != len(data):
        raise ValueError('Invalid GLB header')
    offset, document, binary = 12, None, b''
    while offset < len(data):
        size, kind = struct.unpack_from('<II', data, offset)
        payload = data[offset + 8:offset + 8 + size]
        if len(payload) != size:
            raise ValueError('Truncated GLB chunk')
        if kind == 0x4E4F534A:
            document = json.loads(payload)
        elif kind == 0x004E4942:
            binary = payload
        else:
            raise ValueError('Unsupported GLB chunk')
        offset += 8 + size
    if document is None or not document.get('buffers'):
        raise ValueError('Expected a GLB buffer')
    if len(document['buffers']) > 1:
        if path is None:
            raise ValueError('Model path required for external buffers')
        packed = bytearray(binary[:document['buffers'][0]['byteLength']])
        offsets = [0]
        for buffer in document['buffers'][1:]:
            packed.extend(b'\0' * (-len(packed) % 4))
            offsets.append(len(packed))
            payload = (path.parent / unquote(buffer['uri'])).read_bytes()
            if len(payload) != buffer['byteLength']:
                raise ValueError('Invalid external buffer length')
            packed.extend(payload)
        for view in document.get('bufferViews', []):
            view['byteOffset'] = view.get('byteOffset', 0) + offsets[view['buffer']]
            view['buffer'] = 0
        document['buffers'] = [{'byteLength': len(packed)}]
        binary = bytes(packed)
    return document, binary


def view_bytes(document: dict, binary: bytes, index: int) -> bytes:
    view = document['bufferViews'][index]
    start, size = view.get('byteOffset', 0), view['byteLength']
    if view.get('buffer', 0) != 0 or start + size > len(binary):
        raise ValueError('Invalid GLB buffer view')
    return binary[start:start + size]


def image_bytes(path: Path, document: dict, binary: bytes, image: dict) -> bytes:
    if 'bufferView' in image:
        return view_bytes(document, binary, image['bufferView'])
    uri = image.get('uri', '')
    if not uri or uri.startswith('data:'):
        raise ValueError('Expected an embedded image or a local URI')
    return (path.parent / unquote(uri)).read_bytes()


def import_profile(path: Path) -> str | None:
    config = Path(str(path) + '.import')
    if not config.is_file():
        return None
    params = dict(line.split('=', 1) for line in config.read_text().split('[params]', 1)[1].splitlines()
                  if '=' in line)
    source = params.get('roughness/src_normal', '""').strip('"')
    # A normal reference has no effect while roughness processing is disabled.
    if params.get('roughness/mode', '0') == '0':
        params['roughness/src_normal'] = '""'
    elif source.startswith('res://') and (ROOT / source[6:]).is_file():
        params['roughness/src_normal'] = digest((ROOT / source[6:]).read_bytes())
    return json.dumps(params, sort_keys=True)


def map_views(value, remap: dict[int, int]) -> None:
    if isinstance(value, dict):
        for key, item in value.items():
            if key == 'bufferView':
                value[key] = remap[item]
            else:
                map_views(item, remap)
    elif isinstance(value, list):
        for item in value:
            map_views(item, remap)


def encode_glb(document: dict, binary: bytes) -> bytes:
    encoded = json.dumps(document, separators=(',', ':'), ensure_ascii=False).encode()
    encoded += b' ' * (-len(encoded) % 4)
    binary += b'\0' * (-len(binary) % 4)
    chunks = struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
    chunks += struct.pack('<II', len(binary), 0x004E4942) + binary
    return struct.pack('<III', 0x46546C67, 2, 12 + len(chunks)) + chunks


def rewrite_glb(path: Path, data: bytes, targets: dict[int, Path], aliases: dict[Path, Path]) -> bytes:
    document, binary = read_glb(data, path)
    old_views = document.get('bufferViews', [])
    removable, changed = set(), False
    for index, image in enumerate(document.get('images', [])):
        target = targets.get(index)
        if target is None and 'uri' in image:
            source = (path.parent / unquote(image['uri'])).resolve()
            target = aliases.get(source)
        if target is None:
            continue
        if 'bufferView' in image:
            removable.add(image.pop('bufferView'))
        image['uri'] = quote(os.path.relpath(target, path.parent).replace(os.sep, '/'), safe='/')
        changed = True
    if not changed:
        return data
    # A view shared with another accessor/image cannot be removed.
    referenced = set()
    def collect(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key == 'bufferView': referenced.add(item)
                else: collect(item)
        elif isinstance(value, list):
            for item in value: collect(item)
    collect(document)
    removable -= referenced
    packed, views, remap = bytearray(), [], {}
    for index, view in enumerate(old_views):
        if index in removable:
            continue
        packed.extend(b'\0' * (-len(packed) % 4))
        replacement = dict(view, byteOffset=len(packed))
        packed.extend(view_bytes(document, binary, index))
        remap[index] = len(views)
        views.append(replacement)
    document['bufferViews'] = views
    map_views(document, remap)
    document['buffers'][0]['byteLength'] = len(packed)
    return encode_glb(document, bytes(packed))


def semantic_digest(path: Path, data: bytes) -> str:
    """Geometry, scene/material definitions and image payloads, independent of storage."""
    document, binary = read_glb(data, path)
    normalized = copy.deepcopy(document)
    image_views = {image['bufferView'] for image in document.get('images', []) if 'bufferView' in image}
    views = []
    remap = {}
    for index, view in enumerate(document.get('bufferViews', [])):
        remap[index] = digest(view_bytes(document, binary, index))
        if index not in image_views:
            normalized_view = {key: value for key, value in view.items() if key not in ('byteOffset', 'buffer')}
            views.append(dict(normalized_view, payload=remap[index]))
    for source, image in zip(document.get('images', []), normalized.get('images', [])):
        image.pop('bufferView', None)
        image.pop('uri', None)
        image['payload'] = digest(image_bytes(path, document, binary, source))
    normalized['bufferViews'] = views
    normalized['buffers'] = [{key: value for key, value in buffer.items() if key != 'byteLength'}
                             for buffer in normalized['buffers']]
    map_views(normalized, remap)
    return digest(json.dumps(normalized, sort_keys=True, separators=(',', ':')).encode())


def tracked() -> list[Path]:
    return [ROOT / name for name in subprocess.check_output(['git', 'ls-files'], cwd=ROOT, text=True).splitlines()]


def plan(files: list[Path]) -> tuple[dict[Path, Path], dict[Path, dict[int, Path]], dict]:
    groups = defaultdict(list)
    by_hash = defaultdict(list)
    text = '\n'.join(path.read_text(errors='ignore') for path in files
                     if path.suffix in TEXT_TYPES and path.suffix != '.import' and active(path))
    for path in files:
        if path.suffix.lower() not in IMAGE_TYPES or not path.is_relative_to(ROOT / 'models') or not active(path):
            continue
        image_hash, profile = digest(path.read_bytes()), import_profile(path)
        by_hash[image_hash].append(path)
        if profile is not None:
            groups[image_hash, profile].append(path)
    aliases, canonical = {}, {}
    for key, paths in groups.items():
        # Prefer an existing runtime reference, then a generic texture directory.
        chosen = min(paths, key=lambda p: (p.name not in text, '/textures/' not in p.as_posix(), len(p.name), p.as_posix()))
        canonical[key] = chosen
        aliases.update((path.resolve(), chosen) for path in paths if path != chosen)
    targets, unmatched = {}, []
    for path in files:
        if path.suffix.lower() != '.glb' or not active(path):
            continue
        document, binary = read_glb(path.read_bytes(), path)
        for index, image in enumerate(document.get('images', [])):
            if 'bufferView' not in image:
                continue
            image_hash = digest(image_bytes(path, document, binary, image))
            candidates = [p for p in by_hash[image_hash] if p.parent == path.parent
                          and p.stem in (path.stem + '_' + image.get('name', 'Image_' + str(index)), path.stem + '_' + str(index))]
            if not candidates:
                candidates = [p for p in by_hash[image_hash] if p.parent == path.parent and p.stem.startswith(path.stem + '_')]
            profiles = {import_profile(p) for p in candidates}
            if len(profiles) != 1 or None in profiles:
                unmatched.append(f'{path.relative_to(ROOT)}: image {index}')
                continue
            target = canonical[image_hash, profiles.pop()]
            targets.setdefault(path, {})[index] = target
    return aliases, targets, {'duplicate_files': len(aliases), 'externalized_images': sum(map(len, targets.values())),
                              'unmatched_embedded_images': unmatched}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--apply', action='store_true')
    mode.add_argument('--check', action='store_true', help='Fail if compatible tracked image copies remain')
    args = parser.parse_args()
    files = tracked()
    aliases, targets, report = plan(files)
    output, saved = {}, 0
    for path in files:
        if path.suffix.lower() == '.glb' and active(path):
            original = path.read_bytes()
            rewritten = rewrite_glb(path, original, targets.get(path, {}), aliases)
            if original != rewritten:
                if semantic_digest(path, original) != semantic_digest(path, rewritten):
                    raise ValueError(f'Semantic change in {path}')
                output[path] = rewritten
                saved += len(original) - len(rewritten)
    replacements = {}
    deleted_imports = {Path(str(path) + '.import') for path in aliases}
    for source, destination in aliases.items():
        replacements['res://' + source.relative_to(ROOT).as_posix()] = 'res://' + destination.relative_to(ROOT).as_posix()
        old_uid = re.search(r'^uid="([^"]+)"', Path(str(source) + '.import').read_text(), re.M)
        new_uid = re.search(r'^uid="([^"]+)"', Path(str(destination) + '.import').read_text(), re.M)
        if old_uid and new_uid:
            replacements[old_uid[1]] = new_uid[1]
    pattern = re.compile('|'.join(re.escape(key) for key in sorted(replacements, key=len, reverse=True))) if replacements else None
    for path in files:
        if path.suffix not in TEXT_TYPES or path in deleted_imports or not active(path) or path.name == Path(__file__).name:
            continue
        original = path.read_text(errors='strict')
        rewritten = pattern.sub(lambda match: replacements[match[0]], original) if pattern else original
        if original != rewritten:
            output[path] = rewritten.encode()
    report.update(changed_models=sum(p.suffix == '.glb' for p in output), changed_text_files=sum(p.suffix != '.glb' for p in output),
                  embedded_saved_mib=round(saved / 1048576, 2), files_saved_mib=round(sum(p.stat().st_size for p in aliases) / 1048576, 2))
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if args.apply:
        for path, content in output.items():
            path.write_bytes(content)
        for path in aliases:
            path.unlink()
            Path(str(path) + '.import').unlink()
    return int(bool(aliases)) if args.check else 0


if __name__ == '__main__':
    raise SystemExit(main())
