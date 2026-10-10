"""Repack group 01 into one PBR atlas, preserving authored nodes and damage stages.

Requires the existing authoring dependencies numpy, Pillow and scipy.
Input is an unmodified group directory (or one exported from the recorded Git ref).
Output is a separate directory; this tool never deletes source assets.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

import build_architecture_pack as base

SIZE = 2048
GUTTER = 16
KINDS = ('albedo', 'normal', 'orm')
TILES = [
    ('painted_plaster', 'architecture', 0),
    ('column_paint', 'architecture', 1),
    ('graphite_coating', 'architecture', 2),
    ('graphite_door', 'architecture', 3),
    ('brushed_steel', 'architecture', 4),
    ('oak_longitudinal', 'architecture', 5),
    ('oak_endgrain', 'architecture', 6),
    ('ivory_coating', 'architecture', 7),
    ('stair_grip', 'stairs_elevators', 2),
    ('passenger_terrazzo', 'stairs_elevators', 3),
    ('freight_rubber', 'stairs_elevators', 5),
    ('smoked_steel', 'stairs_elevators', 6),
]
STAIR_SLOTS = [2, 1, 8, 9, 4, 10, 11, 7]
EXCLUDED = {'01_column_2.glb', '01_stairs_2.glb'}


def rect(slot):
    if slot == 12:
        return [1024 + GUTTER, 1024 + GUTTER, 1024 - 2 * GUTTER, 1024 - 2 * GUTTER]
    x, y = (slot % 4) * 512, (slot // 4) * 512
    if slot >= 10:
        x, y = (slot - 10) * 512, 1536
    return [x + GUTTER, y + GUTTER, 512 - 2 * GUTTER, 512 - 2 * GUTTER]


def resize_map(image, size, normal=False):
    a = np.array(image.resize((size, size), Image.Resampling.LANCZOS).convert('RGB'))
    if normal:
        a = np.rint((base.normalize(a.astype(float) / 127.5 - 1) * .5 + .5) * 255).astype('uint8')
    return a


def build_maps(source, output):
    arrays = {kind: np.zeros((SIZE, SIZE, 3), dtype='uint8') for kind in KINDS}
    sources = {}
    for family in ['architecture', 'stairs_elevators']:
        for kind in KINDS:
            # The stairs pack's albedo is at the texture root after deduplication.
            p = source / f'textures/{family}/architecture_{kind}.png'
            if not p.exists():
                p = source / f'textures/architecture_{kind}.png'
            sources[family, kind] = Image.open(p).convert('RGB')
    rng = np.random.default_rng(20261010)
    for slot in range(13):
        x, y, width, height = rect(slot)
        tiles = {}
        for kind in KINDS:
            if slot == 12:
                image = Image.open(source / f'textures/carpet/carpet_{kind}.png')
            else:
                _, family, original_slot = TILES[slot]
                image = sources[family, kind]
                cell = image.width // 4
                sx, sy = (original_slot % 4) * cell, (original_slot // 4) * cell
                image = image.crop((sx + 16, sy + 16, sx + cell - 16, sy + cell - 16))
            tiles[kind] = resize_map(image, width, kind == 'normal')
        if slot == 1:
            # Large-scale variation remains visible after mipmapping; no baked light.
            field = gaussian_filter(rng.normal(size=(width, width)), 13, mode='wrap')
            field = np.clip(field / max(field.std(), .0001), -2, 2)
            fine = gaussian_filter(rng.normal(size=(width, width)), 1.2, mode='wrap')
            fine /= max(fine.std(), .0001)
            tiles['albedo'] = np.clip(tiles['albedo'].astype(float) * (1 + field[..., None] * .035), 0, 255).astype('uint8')
            tiles['orm'][:, :, 1] = np.rint(np.clip(.57 + .095 * field + .015 * fine, .32, .80) * 255).astype('uint8')
            tiles['orm'][:, :, 2] = 0
            normal = tiles['normal'].astype(float) / 127.5 - 1
            dy, dx = np.gradient(field)
            normal[:, :, 0] -= dx * .18
            normal[:, :, 1] -= dy * .18
            tiles['normal'] = np.rint((base.normalize(normal) * .5 + .5) * 255).astype('uint8')
        for kind, tile in tiles.items():
            # Extrude edge pixels into every gutter, across all three maps.
            padded = np.pad(tile, ((GUTTER, GUTTER), (GUTTER, GUTTER), (0, 0)), mode='edge')
            arrays[kind][y-GUTTER:y+height+GUTTER, x-GUTTER:x+width+GUTTER] = padded
    folder = output / 'textures/unified'
    folder.mkdir(parents=True, exist_ok=True)
    for kind, array in arrays.items():
        Image.fromarray(array).save(folder / f'group01_{kind}.png', compress_level=9)
    layout = {
        'version': 2, 'size': [SIZE, SIZE], 'gutter_px': GUTTER,
        'source_ref': '61e80037955ad211cb12055264381accd42ea0c2',
        'runtime_size': {'albedo': [2048, 2048], 'normal': [1024, 1024], 'orm': [1024, 1024]},
        'origin': 'top-left', 'normal_convention': 'OpenGL +Y',
        'orm_channels': {'R': 'neutral AO', 'G': 'roughness', 'B': 'metallic'},
        'tiles': [{'id': (TILES[i][0] if i < 12 else 'carpet'),
                   'pixel_rect': rect(i), 'uv_rect': [v / SIZE for v in rect(i)]} for i in range(13)],
    }
    (output / 'atlas_layout.json').write_text(json.dumps(layout, indent=2) + '\n')
    preview = Image.fromarray(arrays['albedo']).resize((1024, 1024))
    draw = ImageDraw.Draw(preview)
    for tile in layout['tiles']:
        x, y, w, h = [v // 2 for v in tile['pixel_rect']]
        draw.rectangle((x, y, x + w, y + h), outline='orange', width=2)
        draw.text((x + 5, y + 5), tile['id'], fill='white', stroke_width=2, stroke_fill='black')
    (output / 'previews').mkdir(exist_ok=True)
    preview.save(output / 'previews/unified_atlas.png')


def source_slot(filename, material, uv):
    if filename.startswith('01_floor_'):
        return 12
    if 'VECTRION' in filename:
        return 4
    if filename.startswith('01_stairs') or filename.startswith('01_elevator_cabin'):
        return STAIR_SLOTS[int(np.floor(uv.mean(0)[0] * 4) + 4 * np.floor(uv.mean(0)[1] * 2))]
    # Wood end grain shares a material with longitudinal grain; inspect each triangle.
    return int(np.floor(uv.mean(0)[0] * 4) + 4 * np.floor(uv.mean(0)[1] * 2))


def mapped_uv(uv, slot, carpet=False):
    x, y, w, h = np.asarray(rect(slot), dtype=float) / SIZE
    if carpet:
        local = uv
    else:
        # Existing 4x2 atlas has a 16-pixel gutter around each 512px cell.
        old_slot = int(np.floor(uv.mean(0)[0] * 4) + 4 * np.floor(uv.mean(0)[1] * 2))
        origin = np.array([(old_slot % 4 * 512 + 16) / 2048,
                           (old_slot // 4 * 512 + 16) / 1024])
        local = (uv - origin) / np.array([480 / 2048, 480 / 1024])
        if local.min() < -.0001 or local.max() > 1.0001:
            raise ValueError('A triangle crosses atlas cells')
    return np.array([x, y]) + np.clip(local, 0, 1) * np.array([w, h])


def clip_polygon(polygon, axis, value, greater):
    result = []
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        inside_a = a[axis] >= value - 1e-10 if greater else a[axis] <= value + 1e-10
        inside_b = b[axis] >= value - 1e-10 if greater else b[axis] <= value + 1e-10
        if inside_a:
            result.append(a)
        if inside_a != inside_b:
            t = (value - a[axis]) / (b[axis] - a[axis])
            result.append(a + t * (b - a))
    return result


def carpet_pieces(uv):
    """Clip a triangle at integer UV boundaries, carrying barycentric weights."""
    lo = np.floor(uv.min(0)).astype(int)
    hi = np.ceil(uv.max(0)).astype(int)
    if np.any(hi <= lo):
        hi = np.maximum(hi, lo + 1)
    if np.prod(hi - lo) > 256:
        raise ValueError('Unexpected carpet repeat count')
    for x in range(lo[0], hi[0]):
        for y in range(lo[1], hi[1]):
            polygon = list(np.c_[uv.astype(float), np.eye(3)])
            for axis, low in [(0, x), (1, y)]:
                polygon = clip_polygon(polygon, axis, low, True)
                if polygon:
                    polygon = clip_polygon(polygon, axis, low + 1, False)
                if not polygon:
                    break
            for i in range(1, len(polygon) - 1):
                tri = np.asarray([polygon[0], polygon[i], polygon[i+1]])
                v = tri[:, :2]
                if abs(np.linalg.det(np.stack([v[1]-v[0], v[2]-v[0]]))) > 1e-10:
                    yield tri[:, 2:], v - [x, y]


def build_primitive(doc, binary, old, source_binary, primitive, filename):
    attrs = primitive['attributes']
    values = {key: base.accessor(old, source_binary, idx) for key, idx in attrs.items()}
    if primitive.get('targets') or primitive.get('mode', 4) != 4:
        raise ValueError('Only static triangle primitives are expected in group 01')
    indices = base.accessor(old, source_binary, primitive['indices']).astype(int) if 'indices' in primitive else np.arange(len(values['POSITION']))
    material = old['materials'][primitive['material']]
    pbr = material.get('pbrMetallicRoughness', {})
    textured = 'baseColorTexture' in pbr and material.get('alphaMode', 'OPAQUE') == 'OPAQUE'
    emitted = {key: [] for key in values if key != 'TANGENT'}
    for triangle in indices.reshape(-1, 3):
        uv = values.get('TEXCOORD_0', np.zeros((len(values['POSITION']), 2)))[triangle]
        carpet = textured and filename.startswith('01_floor_')
        pieces = carpet_pieces(uv) if carpet else [(np.eye(3), uv)]
        for weights, local in pieces:
            slot = source_slot(filename, material, uv) if textured else None
            for key in emitted:
                data = weights @ values[key][triangle]
                if key == 'TEXCOORD_0' and textured:
                    data = mapped_uv(local, slot, carpet)
                emitted[key].append(data)
    result = copy.deepcopy(primitive)
    result['attributes'] = {}
    arrays = {key: np.concatenate(chunks).astype(values[key].dtype) for key, chunks in emitted.items()}
    if textured:
        arrays['TANGENT'] = base.tangents(arrays['POSITION'], arrays['NORMAL'], arrays['TEXCOORD_0']).astype('<f4')
    elif 'TANGENT' in values:
        arrays['TANGENT'] = values['TANGENT'][indices]
    # Weld only identical full vertices; UV/hard-normal seams stay split.
    keys = sorted(arrays)
    packed = np.concatenate([arrays[key].astype('<f4') for key in keys], axis=1)
    _, first, inverse = np.unique(packed, axis=0, return_index=True, return_inverse=True)
    for key in keys:
        data_type = 'VEC4' if key == 'TANGENT' else old['accessors'][attrs[key]]['type']
        result['attributes'][key] = base.append_accessor(doc, binary, arrays[key][first], data_type)
    dtype = '<u2' if len(first) <= 65535 else '<u4'
    result['indices'] = base.append_accessor(doc, binary, inverse.astype(dtype), 'SCALAR', 34963)
    return result


def geometry_fingerprint(doc, binary):
    rows = []
    for mesh in doc['meshes']:
        triangles = []
        for primitive in mesh['primitives']:
            positions = base.accessor(doc, binary, primitive['attributes']['POSITION'])
            ids = base.accessor(doc, binary, primitive['indices']).astype(int) if 'indices' in primitive else np.arange(len(positions))
            triangles.extend(tuple(row.flatten()) for row in positions[ids].reshape(-1, 3, 3))
        rows.append(hashlib.sha256(np.asarray(sorted(triangles), dtype='<f4').tobytes()).hexdigest())
    return rows


def convert(source, output):
    original, original_binary = base.load_glb(source)
    doc = copy.deepcopy(original)
    binary = bytearray()
    doc['accessors'] = []
    doc['bufferViews'] = []
    doc['images'] = [{'uri': f'textures/unified/group01_{kind}.png'} for kind in KINDS]
    doc['samplers'] = [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071}]
    doc['textures'] = [{'source': i, 'sampler': 0} for i in range(3)]
    materials, identities, remap, assignments = [], {}, {}, []
    for i, old_material in enumerate(original['materials']):
        material = copy.deepcopy(old_material)
        pbr = material.get('pbrMetallicRoughness', {})
        if 'baseColorTexture' in pbr and material.get('alphaMode', 'OPAQUE') == 'OPAQUE':
            tint = pbr.get('baseColorFactor', [1, 1, 1, 1])
            name = 'Group01OpaqueDoubleSided' if material.get('doubleSided', False) else 'Group01Opaque'
            if tint != [1, 1, 1, 1]:
                name += 'Dark'
            material = {'name': name, 'doubleSided': material.get('doubleSided', False),
                        'pbrMetallicRoughness': {'baseColorFactor': tint, 'baseColorTexture': {'index': 0},
                                               'metallicFactor': 1, 'roughnessFactor': 1,
                                               'metallicRoughnessTexture': {'index': 2}},
                        'normalTexture': {'index': 1, 'scale': 1},
                        'occlusionTexture': {'index': 2, 'strength': 1}}
            assignments.append({'original_material': old_material.get('name', ''), 'shared_material': name})
        elif any(key.endswith('Texture') for owner in [material, pbr] for key in owner):
            raise ValueError('Unexpected textured transparent material; preserve explicitly')
        material.pop('extras', None)
        identity = json.dumps({k: v for k, v in material.items() if k != 'name'}, sort_keys=True)
        if identity not in identities:
            identities[identity] = len(materials)
            materials.append(material)
        remap[i] = identities[identity]
    doc['materials'] = materials
    before = sum(len(m['primitives']) for m in original['meshes'])
    for i, mesh in enumerate(doc['meshes']):
        converted = []
        for primitive in original['meshes'][i]['primitives']:
            new = build_primitive(doc, binary, original, original_binary, primitive, source.name)
            new['material'] = remap[primitive['material']]
            converted.append(new)
        # Same-node, same-material surfaces can share one draw; nodes/stages are never merged.
        groups = {}
        for surface_index, primitive in enumerate(converted):
            # GlassPartition detaches the lower infill from frame surface 1.
            # Preserve that surface contract until it is migrated separately.
            protected = source.name in {'01_glass_partition_half_breakable.glb', '01_glass_wall_full_breakable.glb'}
            key = (primitive['material'], tuple(sorted(primitive['attributes'])), surface_index if protected else -1)
            groups.setdefault(key, []).append(primitive)
        mesh['primitives'] = []
        for pieces in groups.values():
            if len(pieces) == 1:
                mesh['primitives'].append(pieces[0])
                continue
            merged = copy.deepcopy(pieces[0]); arrays = {}; indices = []; count = 0
            for piece in pieces:
                for key, index in piece['attributes'].items():
                    arrays.setdefault(key, []).append(base.accessor(doc, binary, index))
                indices.append(base.accessor(doc, binary, piece['indices']).astype('<u4') + count)
                count += len(base.accessor(doc, binary, piece['attributes']['POSITION']))
            merged['attributes'] = {key: base.append_accessor(doc, binary, np.concatenate(data),
                                    doc['accessors'][pieces[0]['attributes'][key]]['type']) for key, data in arrays.items()}
            merged['indices'] = base.append_accessor(doc, binary, np.concatenate(indices).astype('<u2' if count <= 65535 else '<u4'), 'SCALAR', 34963)
            mesh['primitives'].append(merged)
    # Discard the intermediate arrays produced before merging; copy live data only.
    packed_doc = copy.deepcopy(doc); packed_doc['accessors'] = []; packed_doc['bufferViews'] = []
    packed_binary = bytearray(); live = {}
    for mesh in packed_doc['meshes']:
        for primitive in mesh['primitives']:
            for owner, key in [(primitive, 'indices')] + [(primitive['attributes'], k) for k in primitive['attributes']]:
                old_index = owner[key]
                if old_index not in live:
                    a = doc['accessors'][old_index]
                    live[old_index] = base.append_accessor(packed_doc, packed_binary,
                        base.accessor(doc, binary, old_index), a['type'], 34963 if key == 'indices' else 34962)
                owner[key] = live[old_index]
    packed_doc['asset']['generator'] = 'Infection Shooter unified group01 atlas v2'
    packed_doc.pop('extras', None)
    packed_doc['extras'] = {'group01_atlas_v2': {'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                                               'resolution': [SIZE, SIZE], 'carpet_repeat_meters': 1}}
    assert original['nodes'] == packed_doc['nodes'] and original['scenes'] == packed_doc['scenes']
    if not source.name.startswith('01_floor_'):
        assert geometry_fingerprint(original, original_binary) == geometry_fingerprint(packed_doc, packed_binary)
    base.write_glb(output / source.name, packed_doc, packed_binary)
    return {'file': source.name, 'source_bytes': source.stat().st_size,
            'output_bytes': (output / source.name).stat().st_size,
            'source_surfaces': before, 'output_surfaces': sum(len(m['primitives']) for m in packed_doc['meshes']),
            'nodes_preserved': len(original['nodes']), 'materials': assignments,
            'geometry': 'exact triangle positions' if not source.name.startswith('01_floor_') else 'same surface; split at 1m repeat boundaries'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.inputs.resolve() == args.output.resolve():
        parser.error('Output must differ from inputs')
    args.output.mkdir(parents=True, exist_ok=True)
    build_maps(args.inputs, args.output)
    results = [convert(p, args.output) for p in sorted(args.inputs.glob('*.glb')) if p.name not in EXCLUDED]
    (args.output / 'unified_validation.json').write_text(json.dumps({'models': results}, indent=2) + '\n')
    print('Converted', len(results), 'models;', sum(r['source_surfaces'] for r in results), '->', sum(r['output_surfaces'] for r in results), 'surfaces')


if __name__ == '__main__':
    main()
