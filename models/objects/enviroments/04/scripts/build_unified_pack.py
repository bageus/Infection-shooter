"""Build group 04 from the unmodified assets at SOURCE_REF.

Requires numpy/Pillow/scipy, as the group-01 authoring pipeline does.
Export that revision's group directory with git archive; output must be separate.
Geometry is subdivided only at texture-repeat boundaries, never decimated.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / '01/scripts'))
import build_architecture_pack as base
from build_unified_pack import clip_polygon

SOURCE_REF = 'a48e5a49028b0871852f4418eeb8eb2670671ea2'
SIZE, GUTTER = 1024, 8
KINDS = ('albedo', 'normal', 'orm')
TILES = ('light_cardboard', 'brown_cardboard', 'dark_interior',
         'ivory', 'tan_cardboard', 'brown_flat_cardboard', 'olive_painted_wood')
COLORS = ([223.5, 157.5, 85.5], [185.5, 113.5, 57.5], [20, 25, 35],
          [.921568632, .909803927, .862745106], [.835294127, .654901981, .411764711],
          [.686274529, .509803951, .313725501], [.372549, .435294, .176471])
ROUGHNESS = (.82, .82, .82, .78, .65, .65, .56)


def repeat_pieces(uv):
    lo = np.floor(uv.min(0)).astype(int)
    hi = np.maximum(np.ceil(uv.max(0)).astype(int), lo + 1)
    assert np.prod(hi-lo) <= 256
    for x in range(lo[0], hi[0]):
        for y in range(lo[1], hi[1]):
            polygon = list(np.c_[uv.astype(float), np.eye(3)])
            for axis, low in [(0, x), (1, y)]:
                polygon = clip_polygon(polygon, axis, low, True)
                if polygon:
                    polygon = clip_polygon(polygon, axis, low+1, False)
                if not polygon:
                    break
            for i in range(1, len(polygon)-1):
                tri = np.asarray([polygon[0], polygon[i], polygon[i+1]])
                # Cardboard has extremely narrow UV triangles, unlike the carpet.
                # Reject only zero-area intersections, not thin authored faces.
                if abs(np.linalg.det(np.stack([tri[1, :2]-tri[0, :2], tri[2, :2]-tri[0, :2]]))) > 1e-15:
                    yield tri[:, 2:], tri[:, :2]-[x, y]


def rect(slot):
    if slot < 3:
        return [(slot % 2) * 512 + GUTTER, (slot // 2) * 512 + GUTTER, 496, 496]
    i = slot - 3
    return [512 + (i % 2) * 256 + GUTTER, 512 + (i // 2) * 256 + GUTTER, 240, 240]


def srgb(linear):
    a = np.asarray(linear)
    return np.where(a <= .0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - .055)


def build_maps(source, output):
    maps = {k: np.zeros((SIZE, SIZE, 3), dtype='uint8') for k in KINDS}
    originals = ['04_cardboard_box_closed_Image_0.png', '04_cardboard_archive_box_Image_0.png']
    for slot in range(7):
        x, y, w, h = rect(slot)
        if slot < 2:
            albedo = np.asarray(Image.open(source / originals[slot]).convert('RGB').resize((w, h), Image.Resampling.LANCZOS))
        else:
            color = COLORS[slot] if slot == 2 else np.rint(srgb(COLORS[slot]) * 255)
            albedo = np.broadcast_to(np.array(color, dtype='uint8'), (h, w, 3)).copy()
        # Preserve mean authored roughness; grain adds subtle fibre relief only.
        normal = np.broadcast_to(np.array([128, 128, 255], dtype='uint8'), (h, w, 3)).copy()
        orm = np.broadcast_to(np.array([255, round(ROUGHNESS[slot] * 255), 0], dtype='uint8'), (h, w, 3)).copy()
        if slot < 2:
            grain = albedo.astype(float).mean(2)
            grain = np.clip((grain-grain.mean())/max(grain.std(), 1e-8), -2, 2)
            dy, dx = np.gradient(grain)
            normals = base.normalize(np.stack([-dx*.025, -dy*.025, np.ones_like(grain)], axis=2))
            normal = np.rint((normals*.5+.5)*255).astype('uint8')
            orm[:, :, 1] = np.rint(np.clip(ROUGHNESS[slot]+grain*.01, 0, 1)*255).astype('uint8')
        for kind, tile in zip(KINDS, [albedo, normal, orm]):
            maps[kind][y-GUTTER:y+h+GUTTER, x-GUTTER:x+w+GUTTER] = np.pad(tile, ((GUTTER, GUTTER), (GUTTER, GUTTER), (0, 0)), mode='edge')
    folder = output / 'textures/unified'
    folder.mkdir(parents=True, exist_ok=True)
    for kind, data in maps.items():
        image = Image.fromarray(data)
        if kind != 'albedo':
            image = image.resize((512, 512), Image.Resampling.LANCZOS)
            if kind == 'normal':
                normals = base.normalize(np.asarray(image).astype(float)/127.5-1)
                image = Image.fromarray(np.rint((normals*.5+.5)*255).astype('uint8'))
        image.save(folder / f'group04_{kind}.png', compress_level=9)
    layout = {'version': 1, 'source_ref': SOURCE_REF, 'size': [SIZE, SIZE],
              'runtime_size': {'albedo': [1024, 1024], 'normal': [512, 512], 'orm': [512, 512]},
              'gutter_px': GUTTER, 'origin': 'top-left', 'normal_convention': 'OpenGL +Y',
              'orm_channels': {'R': 'neutral AO', 'G': 'roughness', 'B': 'metallic'},
              'tiles': [{'id': name, 'pixel_rect': rect(i), 'uv_rect': [v / SIZE for v in rect(i)],
                         'roughness': ROUGHNESS[i], 'metallic': 0} for i, name in enumerate(TILES)]}
    (output / 'atlas_layout.json').write_text(json.dumps(layout, indent=2) + '\n')


def slot_for(doc, binary, material, source):
    pbr = material.get('pbrMetallicRoughness', {})
    if 'baseColorTexture' in pbr:
        image = doc['images'][doc['textures'][pbr['baseColorTexture']['index']]['source']]
        from io import BytesIO
        if 'uri' in image:
            data = (source / image['uri']).read_bytes()
        else:
            view = doc['bufferViews'][image['bufferView']]
            data = binary[view.get('byteOffset', 0):view.get('byteOffset', 0) + view['byteLength']]
        mean = np.asarray(Image.open(BytesIO(data)).convert('RGB')).mean((0, 1))
        return int(np.argmin([np.linalg.norm(mean - np.asarray(c)) for c in COLORS[:3]]))
    color = pbr.get('baseColorFactor', [1, 1, 1, 1])[:3]
    slot = 3 + int(np.argmin([np.linalg.norm(np.array(color) - c) for c in COLORS[3:]]))
    assert np.max(np.abs(np.asarray(color) - COLORS[slot])) < 1e-5, color
    return slot


def convert_primitive(old, source_binary, primitive, slot):
    attrs = primitive['attributes']
    assert primitive.get('mode', 4) == 4 and not primitive.get('targets')
    values = {k: base.accessor(old, source_binary, idx) for k, idx in attrs.items() if k != 'TANGENT'}
    values.setdefault('TEXCOORD_0', np.zeros((len(values['POSITION']), 2), dtype='<f4'))
    ids = base.accessor(old, source_binary, primitive['indices']).astype(int) if 'indices' in primitive else np.arange(len(values['POSITION']))
    emitted = {k: [] for k in values}
    origin, size = np.asarray(rect(slot), dtype=float).reshape(2, 2) / SIZE
    for tri in ids.reshape(-1, 3):
        uv = values['TEXCOORD_0'][tri]
        det = np.linalg.det(np.stack([uv[1]-uv[0], uv[2]-uv[0]]))
        if slot < 2 and abs(det) > 1e-10:
            pieces = repeat_pieces(uv)
        else:
            local = np.full((3, 2), .5) if slot >= 2 else np.tile(np.mod(uv.mean(0), 1), (3, 1))
            pieces = [(np.eye(3), local)]
        for weights, local in pieces:
            positions = weights @ values['POSITION'][tri]
            # UV clipping can create tiny slivers; retain all nonzero geometry.
            if np.linalg.norm(np.cross(positions[1]-positions[0], positions[2]-positions[0])) < 1e-13:
                continue
            for key in emitted:
                data = origin + np.clip(local, 0, 1) * size if key == 'TEXCOORD_0' else weights @ values[key][tri]
                emitted[key].append(data)
    arrays = {k: np.concatenate(v).astype('<f4') for k, v in emitted.items()}
    arrays['TANGENT'] = base.tangents(arrays['POSITION'], arrays['NORMAL'], arrays['TEXCOORD_0'])
    return arrays


def material(double):
    return {'name': 'Group04OpaqueDoubleSided' if double else 'Group04Opaque', 'doubleSided': double,
            'pbrMetallicRoughness': {'baseColorFactor': [1, 1, 1, 1], 'baseColorTexture': {'index': 0},
                                   'metallicFactor': 1, 'roughnessFactor': 1, 'metallicRoughnessTexture': {'index': 2}},
            'normalTexture': {'index': 1}, 'occlusionTexture': {'index': 2}}


def convert(path, output):
    old, source_binary = base.load_glb(path)
    doc = copy.deepcopy(old)
    doc['accessors'], doc['bufferViews'] = [], []
    doc['images'] = [{'uri': f'textures/unified/group04_{kind}.png'} for kind in KINDS]
    doc['textures'] = [{'source': i, 'sampler': 0} for i in range(3)]
    doc['samplers'] = [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071}]
    sides = sorted({bool(m.get('doubleSided', False)) for m in old['materials']})
    doc['materials'] = [material(double) for double in sides]
    slots = [slot_for(old, source_binary, m, path.parent) for m in old['materials']]
    binary = bytearray()
    source_triangles = target_triangles = 0
    for i, mesh in enumerate(doc['meshes']):
        groups = {}
        for p in old['meshes'][i]['primitives']:
            mid = sides.index(bool(old['materials'][p['material']].get('doubleSided', False)))
            arrays = convert_primitive(old, source_binary, p, slots[p['material']])
            groups.setdefault(mid, []).append(arrays)
            source_triangles += old['accessors'][p.get('indices', p['attributes']['POSITION'])]['count'] // 3
        mesh['primitives'] = []
        for mid, pieces in groups.items():
            arrays = {k: np.concatenate([p[k] for p in pieces]) for k in pieces[0]}
            target_triangles += len(arrays['POSITION']) // 3
            keys = sorted(arrays)
            _, first, inverse = np.unique(np.concatenate([arrays[k] for k in keys], axis=1), axis=0, return_index=True, return_inverse=True)
            primitive = {'material': mid, 'attributes': {}}
            for key in keys:
                width = arrays[key].shape[1]
                primitive['attributes'][key] = base.append_accessor(doc, binary, arrays[key][first], f'VEC{width}')
            primitive['indices'] = base.append_accessor(doc, binary, inverse.astype('<u2' if len(first) <= 65535 else '<u4'), 'SCALAR', 34963)
            mesh['primitives'].append(primitive)
    doc['asset']['generator'] = 'Infection Shooter group04 unified atlas v1'
    doc['extras'] = {'group04_atlas_v1': {'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest()}}
    assert doc['nodes'] == old['nodes'] and doc['scenes'] == old['scenes']
    base.write_glb(output / path.name, doc, binary)
    return {'file': path.name, 'source_bytes': path.stat().st_size, 'output_bytes': (output / path.name).stat().st_size,
            'source_surfaces': sum(len(m['primitives']) for m in old['meshes']),
            'output_surfaces': sum(len(m['primitives']) for m in doc['meshes']),
            'source_triangles': source_triangles, 'output_triangles': target_triangles,
            'nodes_preserved': len(old['nodes']), 'source_material_tiles': [TILES[s] for s in slots]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.inputs.resolve() == args.output.resolve():
        parser.error('Output must differ from inputs')
    args.output.mkdir(parents=True, exist_ok=True)
    build_maps(args.inputs, args.output)
    results = [convert(p, args.output) for p in sorted(args.inputs.glob('*.glb'))]
    assert len(results) == 7
    (args.output / 'unified_validation.json').write_text(json.dumps({'source_ref': SOURCE_REF, 'models': results}, indent=2) + '\n')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
