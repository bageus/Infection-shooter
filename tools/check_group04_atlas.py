#!/usr/bin/env python3
"""Check group-04 buffers/UV budgets; optionally compare all authored geometry."""
import argparse
import hashlib
import json
import math
import struct
import subprocess
from pathlib import Path

from check_group01_atlas import ROOT, accessor, area, containing_tile, expanded, read_glb, triangles
from check_model_textures import validate_png

GROUP = ROOT / 'models/objects/enviroments/04'


def on_surface(point, normal, tri, normals):
    # Project onto the dominant plane to avoid cancellation on thin cardboard.
    a, b, c = tri
    u, v = [[p[i]-a[i] for i in range(3)] for p in [b, c]]
    cross = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
    omit = max(range(3), key=lambda i: abs(cross[i]))
    if abs(cross[omit]) < 1e-15:
        return False
    i, j = [axis for axis in range(3) if axis != omit]
    x, y = point[i]-a[i], point[j]-a[j]
    det = u[i]*v[j]-u[j]*v[i]
    s, t = (x*v[j]-y*v[i])/det, (u[i]*y-u[j]*x)/det
    weights = [1-s-t, s, t]
    # Account for float32 quantization in metres, rather than loose UV tolerance.
    for k, weight in enumerate(weights):
        edge = math.dist(tri[(k+1) % 3], tri[(k+2) % 3])
        altitude = 2*area(tri)/max(edge, 1e-15)
        if weight < 0 and -weight*altitude > 1e-7:
            return False
    return all(abs(sum(weights[k]*tri[k][i] for k in range(3))-point[i]) < 1e-7
               and abs(sum(weights[k]*normals[k][i] for k in range(3))-normal[i]) < 1e-5 for i in range(3))


def same_surface(tri, normals, source, source_normals):
    if not all(on_surface(p, n, source, source_normals) for p, n in zip(tri, normals)):
        return False
    def cross(t):
        u, v = [[p[i]-t[0][i] for i in range(3)] for p in t[1:]]
        return [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
    return sum(x*y for x, y in zip(cross(tri), cross(source))) > 0


def compare(source, target, name):
    old, oldbin = read_glb(source)
    new, newbin = read_glb(target)
    assert old['nodes'] == new['nodes'] and old['scenes'] == new['scenes'], name + ': stage/node changed'
    assert old.get('scene') == new.get('scene') and len(old['meshes']) == len(new['meshes'])
    assert new['extras']['group04_atlas_v1']['source_sha256'] == hashlib.sha256(source).hexdigest()
    for before, after in zip(old['meshes'], new['meshes']):
        assert before.get('name') == after.get('name')
        a, b = triangles(old, oldbin, before), triangles(new, newbin, after)
        if sorted(a) == sorted(b):
            continue
        # Integer UV clipping must preserve winding, area and interpolated normals.
        assert math.isclose(sum(area(t[0]) for t in a), sum(area(t[0]) for t in b), rel_tol=1e-6, abs_tol=1e-7), name + ': area changed'
        for tri, ns, _ in b:
            assert area(tri) > 1e-13
            assert any(same_surface(tri, ns, t, normals) for t, normals, _ in a), name + ': subdivision left source triangle or reversed winding'
        for axis in range(3):
            assert math.isclose(min(v[axis] for t in a for v in t[0]), min(v[axis] for t in b for v in t[0]), abs_tol=1e-6)
            assert math.isclose(max(v[axis] for t in a for v in t[0]), max(v[axis] for t in b for v in t[0]), abs_tol=1e-6)


def check(path, layout):
    doc, binary = read_glb(path.read_bytes())
    assert doc['images'] == [{'uri': f'textures/unified/group04_{k}.png'} for k in ['albedo', 'normal', 'orm']]
    assert len(doc['textures']) == 3
    live = set()
    for mesh in doc['meshes']:
        assert len(mesh['primitives']) == 1, 'Compatible surfaces were not merged'
        for p in mesh['primitives']:
            live.update(p['attributes'].values())
            live.add(p['indices'])
            m = doc['materials'][p['material']]
            assert m['name'] in {'Group04Opaque', 'Group04OpaqueDoubleSided'}
            assert m['pbrMetallicRoughness']['baseColorFactor'] == [1, 1, 1, 1]
            assert m['normalTexture']['index'] == 1 and m['occlusionTexture']['index'] == 2
            uv = expanded(doc, binary, p, 'TEXCOORD_0')
            for i in range(0, len(uv), 3):
                tile = containing_tile(uv[i:i+3], layout['tiles'])
                if 'crate_' in path.name:
                    assert tile == 'olive_painted_wood', 'Crate paint changed'
            for t in accessor(doc, binary, p['attributes']['TANGENT']):
                assert all(math.isfinite(v) for v in t) and abs(sum(v*v for v in t[:3])-1) < 1e-4
    assert live == set(range(len(doc['accessors'])))
    assert {a['bufferView'] for a in doc['accessors']} == set(range(len(doc['bufferViews'])))
    assert len(binary)-sum(v['byteLength'] for v in doc['bufferViews']) <= 4*len(doc['bufferViews'])
    assert 'import_script/path="res://addons/staged_glb_import/group04_material_post_import.gd"' in Path(str(path)+'.import').read_text()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compare-ref')
    args = parser.parse_args()
    layout = json.loads((GROUP / 'atlas_layout.json').read_text())
    paths = sorted(GROUP.glob('*.glb'))
    assert len(paths) == 7 and len(layout['tiles']) == 7
    assert not list(GROUP.glob('*_Image_*.png*')), 'Legacy extracted images remain'
    for path in paths:
        check(path, layout)
        if args.compare_ref:
            data = subprocess.check_output(['git', 'show', args.compare_ref+':'+path.relative_to(ROOT).as_posix()], cwd=ROOT)
            compare(data, path.read_bytes(), path.name)
    for kind, limit in [('albedo', 1024), ('normal', 512), ('orm', 512)]:
        path = GROUP / f'textures/unified/group04_{kind}.png'
        validate_png(path.read_bytes())
        assert struct.unpack('>II', path.read_bytes()[16:24]) == (limit, limit)
        profile = Path(str(path)+'.import').read_text()
        for setting in ['compress/mode=2', 'mipmaps/generate=true', 'detect_3d/compress_to=0', f'process/size_limit={limit}']:
            assert setting in profile
    print('Group 04 atlas: seven models; UV, live buffers and import budgets PASS' + ('; geometry/stages compared to '+args.compare_ref if args.compare_ref else ''))


if __name__ == '__main__':
    main()
