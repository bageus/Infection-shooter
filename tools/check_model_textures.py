#!/usr/bin/env python3
"""Check active GLB texture payloads, material slots and UV coordinates."""
from __future__ import annotations

import argparse
import functools
import json
import struct
import subprocess
import zlib
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]


def validate_png(data: bytes) -> None:
    """Catch truncated chunks/streams before Godot's expensive import step."""
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('Invalid PNG signature')
    offset, compressed = 8, bytearray()
    while offset + 12 <= len(data):
        size = struct.unpack_from('>I', data, offset)[0]
        end = offset + size + 12
        if end > len(data):
            raise ValueError('Truncated PNG chunk')
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:end - 4]
        crc = struct.unpack_from('>I', data, end - 4)[0]
        if zlib.crc32(kind + payload) & 0xffffffff != crc:
            raise ValueError('Invalid PNG chunk CRC')
        if kind == b'IDAT':
            compressed.extend(payload)
        if kind == b'IEND':
            decoder = zlib.decompressobj()
            try:
                decoder.decompress(compressed)
            except zlib.error as error:
                raise ValueError('Invalid PNG image stream') from error
            if not decoder.eof:
                raise ValueError('Truncated PNG image stream')
            return
        offset = end
    raise ValueError('Missing PNG IEND')


@functools.lru_cache(maxsize=None)
def validate_external_png(path: Path) -> None:
    validate_png(path.read_bytes())


def active(path: Path) -> bool:
    return not any((parent / '.gdignore').exists() for parent in path.parents if parent != ROOT.parent)


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    magic, version, length = struct.unpack_from('<III', data)
    if magic != 0x46546C67 or version != 2 or length != len(data):
        raise ValueError('Invalid GLB header')
    offset = 12
    document, binary = None, b''
    while offset < len(data):
        size, kind = struct.unpack_from('<II', data, offset)
        payload = data[offset + 8:offset + 8 + size]
        if len(payload) != size:
            raise ValueError('Truncated GLB chunk')
        if kind == 0x4E4F534A:
            document = json.loads(payload)
        elif kind == 0x004E4942:
            binary = payload
        offset += 8 + size
    if document is None:
        raise ValueError('Missing GLB JSON')
    return document, binary


def texture_slots(material: dict) -> list[tuple[str, dict]]:
    result = []
    for owner in [material, material.get('pbrMetallicRoughness', {})]:
        result.extend((key, value) for key, value in owner.items()
                      if key.endswith('Texture') and isinstance(value, dict))
    for extension in material.get('extensions', {}).values():
        result.extend(texture_slots(extension))
    return result


def audit(path: Path) -> dict:
    document, binary = read_glb(path)
    images = document.get('images', [])
    textures = document.get('textures', [])
    materials = document.get('materials', [])
    errors = []
    for index, image in enumerate(images):
        if 'bufferView' in image:
            view = document['bufferViews'][image['bufferView']]
            start, size = view.get('byteOffset', 0), view['byteLength']
            if view.get('buffer', 0) != 0 or size <= 0 or start + size > len(binary):
                errors.append(f'image {index}: invalid embedded payload')
            elif image.get('mimeType') == 'image/png' or binary[start:start + 8] == b'\x89PNG\r\n\x1a\n':
                try:
                    validate_png(binary[start:start + size])
                except ValueError as error:
                    errors.append(f'image {index}: {error}')
        elif 'uri' not in image or (not image['uri'].startswith('data:')
                and not (path.parent / unquote(image['uri'])).is_file()):
            errors.append(f'image {index}: missing external image')
        elif not image['uri'].startswith('data:') and Path(unquote(image['uri'])).suffix.lower() == '.png':
            try:
                validate_external_png(path.parent / unquote(image['uri']))
            except ValueError as error:
                errors.append(f'image {index}: {error}')
    for index, texture in enumerate(textures):
        source = texture.get('source')
        if source is None:
            source = next((value['source'] for value in texture.get('extensions', {}).values()
                           if 'source' in value), None)
        if source is None or not 0 <= source < len(images):
            errors.append(f'texture {index}: invalid image source')
    textured, total, uv = 0, 0, 0
    slots_used = set()
    for mesh in document.get('meshes', []):
        for primitive in mesh.get('primitives', []):
            total += 1
            attributes = primitive.get('attributes', {})
            uv += 'TEXCOORD_0' in attributes
            material_index = primitive.get('material')
            if material_index is None:
                continue
            if not 0 <= material_index < len(materials):
                errors.append('Invalid primitive material index')
                continue
            slots = texture_slots(materials[material_index])
            textured += bool(slots)
            for name, slot in slots:
                slots_used.add(name)
                if not 0 <= slot.get('index', -1) < len(textures):
                    errors.append(f'{name}: invalid texture index')
                coord = slot.get('extensions', {}).get('KHR_texture_transform', {}).get(
                    'texCoord', slot.get('texCoord', 0))
                if f'TEXCOORD_{coord}' not in attributes:
                    errors.append(f'{name}: missing TEXCOORD_{coord}')
    return dict(path=path.relative_to(ROOT).as_posix(), images=len(images),
                textured=textured, surfaces=total, uv=uv,
                slots=sorted(slots_used), errors=errors)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    paths = subprocess.check_output(['git', 'ls-files', '*.glb'], cwd=ROOT, text=True).splitlines()
    rows = []
    for relative in paths:
        path = ROOT / relative
        if not active(path):
            continue
        try:
            rows.append(audit(path))
        except (ValueError, KeyError, IndexError, struct.error) as error:
            rows.append(dict(path=relative, images=0, textured=0, surfaces=0,
                             uv=0, slots=[], errors=[str(error)]))
    problems = [(row['path'], error) for row in rows for error in row['errors']]
    for path, error in problems:
        print(f'{path}: {error}')
    print(f"Active GLB models: {len(rows)}; textured: {sum(row['textured'] > 0 for row in rows)}; errors: {len(problems)}")
    if args.report:
        text = '# Аудит текстур моделей\n\n'
        text += 'Источник: активные GLB текущего репозитория; папки с `.gdignore` исключены. '
        text += 'Проверяются изображения, привязки материалов и UV. Наличие изображений само по себе не означает их использование.\n\n'
        text += '| Модель | Изображения | Поверхности с текстурами / всего | UV0 / всего | Карты |\n|---|---:|---:|---:|---|\n'
        for row in rows:
            text += f"| `{row['path']}` | {row['images']} | {row['textured']}/{row['surfaces']} | {row['uv']}/{row['surfaces']} | {', '.join(row['slots']) or 'Только материал/цвет'} |\n"
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text, encoding='utf-8')
    return bool(problems)


if __name__ == '__main__':
    raise SystemExit(main())
