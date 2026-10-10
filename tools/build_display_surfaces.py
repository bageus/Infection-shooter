"""Extract only planar screen faces from the authored staged GLBs (stdlib only)."""
import argparse
import hashlib
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / 'models/objects/enviroments/05'
OUTPUT = ROOT / 'game/presentation/office_floor/display_surfaces.json'
# Name, authored stage, surface material, display-facing direction.
PROFILES = {
    '05_monitor_destructible': ('Power_Off', 1, (1, 0, 0)),
    '05_monitor_wide_destructible': ('Power_Off', 1, (1, 0, 0)),
    '05_monitor2_destructible': ('Power_Off', 1, (0, 0, 1)),
    '05_monitor3_server_destructible': ('Power_Off', 1, (0, 0, 1)),
    '05_monitor4_server_destructible': ('Power_Off', 1, (0, 0, 1)),
    '05_laptop_destructible': ('Intact', 4, (1, .233, 0)),
    '05_laptop2_destructible': ('Power_Off', 1, (0, .282, 1)),
    '05_wall_TV_destructible': ('TV_Intact', 1, (0, 1, 0)),
    '05_wall_TV_frameless_destructible': ('TV_Intact', 1, (0, 1, 0)),
}


def sub(a, b): return [a[i] - b[i] for i in range(3)]
def dot(a, b): return sum(x * y for x, y in zip(a, b))
def cross(a, b): return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
def unit(a): return [x / math.sqrt(dot(a, a)) for x in a]


def connected_triangles(candidates):
    """Dual screens can share one material primitive; keep disconnected faces separate."""
    parents=list(range(len(candidates)))
    def root(i):
        while parents[i]!=i:
            parents[i]=parents[parents[i]];i=parents[i]
        return i
    seen={}
    for i,(_,triangle) in enumerate(candidates):
        for point in triangle:
            key=tuple(round(v,6) for v in point)
            if key in seen:parents[root(i)]=root(seen[key])
            seen[key]=i
    groups={}
    for i,item in enumerate(candidates):groups.setdefault(root(i),[]).append(item)
    return list(groups.values())


def extract(name, profile):
    source = MODELS / (name + '.glb')
    deferred = MODELS / 'damage' / (name + '_' + profile[0].lower() + '.glb')
    if deferred.is_file():
        source = deferred
    data = source.read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    gltf = json.loads(data[20:20+length])
    buffer = data[28+length:]

    def accessor(index):
        a = gltf['accessors'][index]
        view = gltf['bufferViews'][a['bufferView']]
        count = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
        fmt = '<' + {5126: 'f', 5123: 'H', 5125: 'I', 5121: 'B'}[a['componentType']] * count
        stride = view.get('byteStride', struct.calcsize(fmt))
        offset = view.get('byteOffset', 0) + a.get('byteOffset', 0)
        return [struct.unpack_from(fmt, buffer, offset+i*stride) for i in range(a['count'])]

    stage, material, desired = profile
    # Material ordering can change when an asset receives new PBR materials.
    material = next((i for i, item in enumerate(gltf["materials"])
                     if item.get("name", "").split("__")[0].split(".")[0] == "Dark_Display_Glass"), material)
    front = unit(desired)
    node = next(n for n in gltf['nodes'] if 'mesh' in n and n.get('name') in [stage, stage+'Geometry'])
    assert 'rotation' not in node and 'scale' not in node, 'Re-export requires profile review'
    screens = []
    for primitive in gltf['meshes'][node['mesh']]['primitives']:
        if primitive.get('material') != material:
            continue
        vertices = accessor(primitive['attributes']['POSITION'])
        normals = accessor(primitive['attributes']['NORMAL'])
        indices = [x[0] for x in accessor(primitive['indices'])] if 'indices' in primitive else list(range(len(vertices)))
        candidates = []
        for i in range(0, len(indices), 3):
            ids = indices[i:i+3]
            triangle = [vertices[j] for j in ids]
            area = math.sqrt(dot(cross(sub(triangle[1], triangle[0]), sub(triangle[2], triangle[0])),
                                 cross(sub(triangle[1], triangle[0]), sub(triangle[2], triangle[0])))) / 2
            # The detailed laptop's exported screen normals are reversed.
            alignment = dot(normals[ids[0]], front)
            if area > .001 and (alignment > .98 or (name == '05_laptop_destructible' and alignment < -.98)):
                candidates.append((area, triangle))
        if not candidates:
            continue
        for candidates in connected_triangles(candidates) if '_server_' in name else [candidates]:
            largest = max(candidates, key=lambda item: item[0])[1]
            normal = unit(cross(sub(largest[1], largest[0]), sub(largest[2], largest[0])))
            if dot(normal, front) < 0:
                normal = [-x for x in normal]
            plane = dot(largest[0], normal)
            triangles = [t for _, t in candidates if all(abs(dot(p, normal)-plane) < .00001 for p in t)]
            up_hint = [0, 0, -1] if 'wall_TV' in name else [0, 1, 0]
            right = unit(cross(up_hint, normal))
            up = unit(cross(normal, right))
            points = [p for triangle in triangles for p in triangle]
            xs = [dot(p, right) for p in points]
            ys = [dot(p, up) for p in points]
            width, height = max(xs)-min(xs), max(ys)-min(ys)
            if '_server_' in name and min(width,height) < .08:
                continue # Thin bezel/support strips share the exported glass material.
            translation = node.get('translation', [0, 0, 0])
            center = [(min(xs)+max(xs))/2*right[i]+(min(ys)+max(ys))/2*up[i]+plane*normal[i]+translation[i] for i in range(3)]
            result = []
            for triangle in triangles:
                # Godot uses clockwise front faces.
                if dot(cross(sub(triangle[1],triangle[0]),sub(triangle[2],triangle[0])), normal) > 0:
                    triangle = [triangle[0], triangle[2], triangle[1]]
                for p in triangle:
                    result.append([*[round(p[i]+translation[i]+normal[i]*.0006, 8) for i in range(3)],
                                   (dot(p, right)-min(xs))/width, 1-(dot(p, up)-min(ys))/height])
            screens.append({'center': center, 'right': right, 'up': up, 'normal': normal,
                            'size': [width, height], 'vertices': result})
    if '_server_' in name and screens:
        # The updated dual monitors also assign display glass to the supports.
        # Both actual screens lie on the outermost forward-facing plane.
        front_plane = max(dot(screen['center'], front) for screen in screens)
        screens = [screen for screen in screens
                   if abs(dot(screen['center'], front) - front_plane) < .00001]
    assert len(screens) == (2 if '_server_' in name else 1), name
    return {'source_sha256': hashlib.sha256(data).hexdigest(), 'screens': screens}


def build(check=False):
    profiles = {name + '.glb': extract(name, profile) for name, profile in PROFILES.items()}
    result = {'version': 1, 'profiles': profiles}
    if check:
        if json.loads(OUTPUT.read_text()) != result:
            raise SystemExit('Display profiles are stale: run python tools/build_display_surfaces.py')
    else:
        OUTPUT.write_text(json.dumps(result, indent=2) + '\n')
    print('Screen profiles:', len(profiles))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
