#!/usr/bin/env python3
"""Validate group-01 geometry, atlas UVs, live buffers, metal and import budgets.

Uses only the Python standard library. --compare-ref additionally compares
the complete authored geometry/stages against the pre-atlas Git revision.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GROUP = ROOT / 'models/objects/enviroments/01'
FORMATS = {5121: 'B', 5123: 'H', 5125: 'I', 5126: 'f'}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def read_glb(data):
    magic, version, length = struct.unpack_from('<III', data)
    assert magic == 0x46546C67 and version == 2 and length == len(data)
    size, kind = struct.unpack_from('<II', data, 12)
    assert kind == 0x4E4F534A
    doc = json.loads(data[20:20 + size])
    count, kind = struct.unpack_from('<II', data, 20 + size)
    assert kind == 0x004E4942
    return doc, data[28 + size:28 + size + count]


def accessor(doc, binary, index):
    a = doc['accessors'][index]
    assert 'sparse' not in a and not a.get('normalized', False)
    view = doc['bufferViews'][a['bufferView']]
    fmt = '<' + FORMATS[a['componentType']] * WIDTHS[a['type']]
    width = struct.calcsize(fmt)
    stride = view.get('byteStride', width)
    offset = view.get('byteOffset', 0) + a.get('byteOffset', 0)
    return [struct.unpack_from(fmt, binary, offset + i * stride) for i in range(a['count'])]


def expanded(doc, binary, primitive, attribute):
    values = accessor(doc, binary, primitive['attributes'][attribute])
    indices = [v[0] for v in accessor(doc, binary, primitive['indices'])] if 'indices' in primitive else range(len(values))
    return [values[i] for i in indices]


def triangles(doc, binary, mesh):
    result = []
    for p in mesh['primitives']:
        pos = expanded(doc, binary, p, 'POSITION')
        normals = expanded(doc, binary, p, 'NORMAL')
        m = doc['materials'][p['material']]
        glass = m.get('alphaMode', 'OPAQUE') != 'OPAQUE'
        for offset in range(0, len(pos), 3):
            result.append((tuple(pos[offset:offset+3]), tuple(normals[offset:offset+3]), glass))
    return result


def area(triangle):
    a, b, c = triangle
    u = [b[i] - a[i] for i in range(3)]
    v = [c[i] - a[i] for i in range(3)]
    cross = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
    return math.sqrt(sum(x*x for x in cross)) / 2


def compare_geometry(source_data, target_data, name):
    old, oldbin = read_glb(source_data)
    new, newbin = read_glb(target_data)
    assert old['nodes'] == new['nodes'], f'{name}: node identity/transforms changed'
    assert old['scenes'] == new['scenes'], f'{name}: damage stages changed'
    assert old.get('scene') == new.get('scene'), f'{name}: default stage changed'
    assert len(old['meshes']) == len(new['meshes']), f'{name}: meshes merged across nodes'
    for before, after in zip(old['meshes'], new['meshes']):
        assert before.get('name') == after.get('name')
        a, b = triangles(old, oldbin, before), triangles(new, newbin, after)
        if not name.startswith('01_floor_'):
            assert sorted(a) == sorted(b), f'{name}: positions/normals/glass geometry changed'
        else:
            # Carpet clipping may subdivide triangles, but must retain the same plane,
            # winding, total area, exact boundary bounds and interpolated normals.
            assert math.isclose(sum(area(t[0]) for t in a), sum(area(t[0]) for t in b), rel_tol=1e-6, abs_tol=1e-7)
            for axis in range(3):
                assert min(v[axis] for t in a for v in t[0]) == min(v[axis] for t in b for v in t[0])
                assert max(v[axis] for t in a for v in t[0]) == max(v[axis] for t in b for v in t[0])
            # Every generated vertex lies in at least one original triangle, using
            # signed barycentric coordinates (not merely an equal bounding box).
            for tri, ns, _ in b:
                assert area(tri) > 1e-10
                for point, normal in zip(tri, ns):
                    assert any(on_triangle(point, normal, t, n) for t, n, _ in a), f'{name}: subdivision left authored surface'
    if name in {'01_glass_partition_half_breakable.glb', '01_glass_wall_full_breakable.glb'}:
        for before, after in zip(old['meshes'], new['meshes']):
            assert len(before['primitives']) == len(after['primitives']), 'Breakaway surface indices changed'
            for a, b in zip(before['primitives'], after['primitives']):
                assert expanded(old, oldbin, a, 'POSITION') == expanded(new, newbin, b, 'POSITION')


def on_triangle(point, normal, tri, normals):
    a, b, c = tri
    u, v, w = [[p[i]-a[i] for i in range(3)] for p in [b, c, point]]
    dot = lambda x, y: sum(a*b for a, b in zip(x, y))
    uu, uv, vv, wu, wv = dot(u, u), dot(u, v), dot(v, v), dot(w, u), dot(w, v)
    det = uu*vv - uv*uv
    if abs(det) < 1e-14:
        return False
    s, t = (vv*wu - uv*wv)/det, (uu*wv - uv*wu)/det
    weights = [1-s-t, s, t]
    if min(weights) < -1e-6 or max(weights) > 1+1e-6:
        return False
    return all(abs(sum(weights[k]*tri[k][i] for k in range(3))-point[i]) < 1e-6
               and abs(sum(weights[k]*normals[k][i] for k in range(3))-normal[i]) < 1e-5 for i in range(3))


def containing_tile(uv, tiles):
    for tile in tiles:
        x, y, w, h = tile['uv_rect']
        if all(x-1e-6 <= u <= x+w+1e-6 and y-1e-6 <= v <= y+h+1e-6 for u, v in uv):
            return tile['id']
    raise AssertionError('Triangle crosses atlas cells or gutter')


def validate_model(path, layout):
    doc, binary = read_glb(path.read_bytes())
    assert doc['images'] == [{'uri': f'textures/unified/group01_{kind}.png'} for kind in ['albedo', 'normal', 'orm']], f'{path.name}: stale images'
    assert len(doc['textures']) == 3
    live = set()
    for mesh in doc['meshes']:
        for p in mesh['primitives']:
            live.update(p['attributes'].values())
            live.add(p['indices'])
            material = doc['materials'][p['material']]
            if 'baseColorTexture' not in material.get('pbrMetallicRoughness', {}):
                continue
            assert material['name'] in {'Group01Opaque', 'Group01OpaqueDoubleSided', 'Group01OpaqueDark'}
            uv = expanded(doc, binary, p, 'TEXCOORD_0')
            tangents = accessor(doc, binary, p['attributes']['TANGENT'])
            assert all(all(math.isfinite(x) for x in t) and abs(sum(x*x for x in t[:3])-1) < 1e-4 and abs(abs(t[3])-1)<1e-5 for t in tangents)
            for i in range(0, len(uv), 3):
                tile = containing_tile(uv[i:i+3], layout['tiles'])
                if 'VECTRION' in path.name:
                    assert tile == 'brushed_steel', 'VECTRION is not assigned to metal'
    assert live == set(range(len(doc['accessors']))), f'{path.name}: orphan accessors'
    assert {a['bufferView'] for a in doc['accessors']} == set(range(len(doc['bufferViews']))), f'{path.name}: orphan buffers'
    used_bytes = sum(v['byteLength'] for v in doc['bufferViews'])
    assert len(binary)-used_bytes <= 4*len(doc['bufferViews']), f'{path.name}: stale binary payload'
    profile = Path(str(path)+'.import').read_text()
    assert 'import_script/path="res://addons/staged_glb_import/group01_material_post_import.gd"' in profile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compare-ref', help='Pre-atlas source revision, e.g. atlas_layout.json source_ref')
    args = parser.parse_args()
    layout = json.loads((GROUP/'atlas_layout.json').read_text())
    paths = sorted(GROUP.glob('*.glb'))
    assert len(paths) == 25 and not (GROUP/'01_stairs_2.glb').exists()
    for path in paths:
        relative = path.relative_to(ROOT).as_posix()
        if path.name != '01_column_2.glb':
            validate_model(path, layout)
        if args.compare_ref:
            data = subprocess.check_output(['git', 'show', args.compare_ref+':'+relative], cwd=ROOT)
            if path.name == '01_column_2.glb':
                assert data == path.read_bytes(), 'Test column changed'
            else:
                compare_geometry(data, path.read_bytes(), path.name)
    if args.compare_ref:
        for path in [GROUP/'01_column_2.glb.import', *GROUP.glob('01_column_2_Image_*')]:
            data = subprocess.check_output(['git', 'show', args.compare_ref+':'+path.relative_to(ROOT).as_posix()], cwd=ROOT)
            assert data == path.read_bytes(), 'Test-column dependencies changed'
    for kind, size in [('albedo', 2048), ('normal', 1024), ('orm', 1024)]:
        p = GROUP/f'textures/unified/group01_{kind}.png'
        assert struct.unpack('>II', p.read_bytes()[16:24]) == (2048, 2048)
        profile = Path(str(p)+'.import').read_text()
        for setting in ['compress/mode=2', 'mipmaps/generate=true', 'process/size_limit='+str(size), 'detect_3d/compress_to=0']:
            assert setting in profile, f'{kind}: wrong import budget'
    print('Group 01 atlas: 24 production models + unchanged test column; UV, metal, buffers and budgets PASS' + ('; geometry/stages match '+args.compare_ref if args.compare_ref else ''))


if __name__ == '__main__':
    main()
