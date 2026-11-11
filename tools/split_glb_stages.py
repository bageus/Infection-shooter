#!/usr/bin/env python3
"""Split multi-scene destructible GLBs into a whole model plus lazily loaded stages.

Every model whose glTF has two or more filled scenes (Intact, LargeParts, ...)
keeps only its default scene in place. Each other scene becomes
<model dir>/damage/<model>_<stage>.glb, and lazy_stages.json (next to the
group folders) maps the model file name to its stages so the importer can add
placeholders that load them on demand (see addons/staged_glb_import).

Run without arguments to split, --check to verify nothing is left to split.
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / 'models/objects/enviroments'
STAGES_JSON = MODELS / 'lazy_stages.json'
SKIP = {'damage'}


def read_glb(path):
    data = path.read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    doc = json.loads(data[20:20 + length])
    binary = data[28 + length:]
    return doc, binary


def pad(data, fill):
    return data + fill * (-len(data) % 4)


def write_glb(path, doc, binary):
    js = pad(json.dumps(doc, separators=(',', ':')).encode(), b' ')
    binary = pad(binary, b'\0')
    body = struct.pack('<II', len(js), 0x4E4F534A) + js
    if binary:
        body += struct.pack('<II', len(binary), 0x004E4942) + binary
    path.write_bytes(struct.pack('<III', 0x46546C67, 2, 12 + len(body)) + body)


def filled_scenes(doc):
    return [i for i, s in enumerate(doc['scenes']) if s.get('nodes')]


def stage_file(stem, name):
    return f"{stem}_{re.sub(r'[^a-z0-9]+', '', name.lower())}.glb"


def extract_scene(doc, binary, scene_index, uri_prefix):
    """Return a self-contained glTF document and buffer for one scene."""
    for unsupported in ('skins', 'animations', 'cameras'):
        assert not doc.get(unsupported), f'{unsupported} are not supported'
    scene = doc['scenes'][scene_index]
    nodes, order = {}, []

    def visit(index):
        if index in nodes:
            return
        nodes[index] = len(order)
        order.append(index)
        for child in doc['nodes'][index].get('children', []):
            visit(child)

    for root in scene['nodes']:
        visit(root)
    meshes = {}
    for index in order:
        mesh = doc['nodes'][index].get('mesh')
        if mesh is not None:
            meshes.setdefault(mesh, len(meshes))
    accessors, views, materials, textures, images, samplers = {}, {}, {}, {}, {}, {}

    def take(table, index):
        return table[index]

    # Keep the source order of shared tables so atlas checks and diffs stay stable.
    used_materials, used_accessors = set(), set()
    for mesh in meshes:
        for primitive in doc['meshes'][mesh]['primitives']:
            used_accessors.update(primitive['attributes'].values())
            used_accessors.update([primitive['indices']] if 'indices' in primitive else [])
            if 'material' in primitive:
                used_materials.add(primitive['material'])
    used_textures = set()

    def find_textures(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key == 'index' and isinstance(item, int):
                    used_textures.add(item)
                else:
                    find_textures(item)

    for material in used_materials:
        find_textures(doc['materials'][material])
    used_images = {doc['textures'][t]['source'] for t in used_textures if 'source' in doc['textures'][t]}
    used_samplers = {doc['textures'][t]['sampler'] for t in used_textures if 'sampler' in doc['textures'][t]}
    for table, used in ((accessors, used_accessors), (materials, used_materials), (textures, used_textures),
                        (images, used_images), (samplers, used_samplers)):
        table.update({old: new for new, old in enumerate(sorted(used))})

    out_buffer = bytearray()
    new_views = []

    def view(index):
        if index in views:
            return views[index]
        source = doc['bufferViews'][index]
        start = source.get('byteOffset', 0)
        chunk = binary[start:start + source['byteLength']]
        out_buffer.extend(b'\0' * (-len(out_buffer) % 4))
        entry = {k: v for k, v in source.items() if k not in ('buffer', 'byteOffset')}
        entry.update(buffer=0, byteOffset=len(out_buffer))
        out_buffer.extend(chunk)
        views[index] = len(new_views)
        new_views.append(entry)
        return views[index]

    new_meshes = []
    for mesh in sorted(meshes, key=meshes.get):
        copy = json.loads(json.dumps(doc['meshes'][mesh]))
        for primitive in copy['primitives']:
            primitive['attributes'] = {k: take(accessors, v) for k, v in primitive['attributes'].items()}
            if 'indices' in primitive:
                primitive['indices'] = take(accessors, primitive['indices'])
            if 'material' in primitive:
                primitive['material'] = take(materials, primitive['material'])
        new_meshes.append(copy)
    new_materials = []
    for material in sorted(materials, key=materials.get):
        copy = json.loads(json.dumps(doc['materials'][material]))

        def remap_textures(value):
            if isinstance(value, dict):
                for key, item in value.items():
                    if key == 'index' and isinstance(item, int):
                        value[key] = take(textures, item)
                    else:
                        remap_textures(item)

        remap_textures(copy)
        new_materials.append(copy)
    new_textures, new_images, new_samplers = [], [], []
    for texture in sorted(textures, key=textures.get):
        copy = dict(doc['textures'][texture])
        if 'source' in copy:
            copy['source'] = take(images, copy['source'])
        if 'sampler' in copy:
            copy['sampler'] = take(samplers, copy['sampler'])
        new_textures.append(copy)
    for image in sorted(images, key=images.get):
        copy = dict(doc['images'][image])
        uri = copy.get('uri')
        if uri and not uri.startswith('data:'):
            copy['uri'] = uri_prefix + uri
        if 'bufferView' in copy:
            copy['bufferView'] = view(copy['bufferView'])
        new_images.append(copy)
    for sampler in sorted(samplers, key=samplers.get):
        new_samplers.append(doc['samplers'][sampler])
    new_accessors = []
    for accessor in sorted(accessors, key=accessors.get):
        copy = dict(doc['accessors'][accessor])
        assert 'sparse' not in copy, 'sparse accessors are not supported'
        if 'bufferView' in copy:
            copy['bufferView'] = view(copy['bufferView'])
        new_accessors.append(copy)
    new_nodes = []
    for index in order:
        copy = dict(doc['nodes'][index])
        if 'children' in copy:
            copy['children'] = [nodes[c] for c in copy['children']]
        if 'mesh' in copy:
            copy['mesh'] = meshes[copy['mesh']]
        new_nodes.append(copy)
    asset = dict(doc.get('asset', {'version': '2.0'}))
    asset['extras'] = {'staged_group': scene.get('name', 'Stage_%d' % scene_index)}
    result = {'asset': asset, 'scene': 0, 'scenes': [{'name': scene.get('name', ''), 'nodes': [nodes[r] for r in scene['nodes']]}],
              'nodes': new_nodes, 'meshes': new_meshes, 'accessors': new_accessors,
              'bufferViews': new_views, 'buffers': [{'byteLength': len(pad(bytes(out_buffer), b'\0'))}]}
    for key, value in (('materials', new_materials), ('textures', new_textures), ('images', new_images), ('samplers', new_samplers)):
        if value:
            result[key] = value
    if 'extensionsUsed' in doc:
        result['extensionsUsed'] = doc['extensionsUsed']
    return result, bytes(out_buffer)


def candidates():
    for path in sorted(MODELS.rglob('*.glb')):
        if SKIP.intersection(path.relative_to(MODELS).parts):
            continue
        yield path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    lazy = json.loads(STAGES_JSON.read_text()) if STAGES_JSON.exists() else {}
    pending = []
    for path in candidates():
        doc, binary = read_glb(path)
        filled = filled_scenes(doc)
        if len(filled) < 2:
            continue
        pending.append(path)
        if args.check:
            continue
        default = int(doc.get('scene', 0))
        assert default in filled, f'{path.name}: default scene is empty'
        entries = []
        for index in filled:
            if index == default:
                continue
            name = doc['scenes'][index].get('name') or f'Stage_{index}'
            target = path.parent / 'damage' / stage_file(path.stem, name)
            target.parent.mkdir(exist_ok=True)
            stage, stage_binary = extract_scene(doc, binary, index, '../')
            write_glb(target, stage, stage_binary)
            entries.append({'name': name, 'path': 'res://' + target.relative_to(ROOT).as_posix()})
        base, base_binary = extract_scene(doc, binary, default, '')
        write_glb(path, base, base_binary)
        assert path.name not in lazy, path.name
        lazy[path.name] = entries
        print(f'{path.relative_to(MODELS)}: {len(binary) // 1024} KB -> {len(base_binary) // 1024} KB + {len(entries)} stages')
    if args.check:
        if pending:
            sys.exit('Unsplit staged GLBs: ' + ', '.join(p.name for p in pending))
        return
    STAGES_JSON.write_text(json.dumps(lazy, indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    main()
