"""Build shared PBR atlases and UV-ready GLBs without changing their node hierarchy.

Dependencies: numpy, Pillow, scipy. Run with --inputs, --source, and --output.
The supplied GLBs are read-only. All output is written to a new directory.
"""
from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter

TILES = [
    ("painted_plaster", "Окрашенная штукатурка", 0.82, 0.0, 0.00012),
    ("column_paint", "Светло-серая колонна", 0.72, 0.0, 0.00006),
    ("graphite_coating", "Графитовые рамы и профили", 0.57, 0.0, 0.000045),
    ("graphite_door", "Тёмное дверное полотно", 0.61, 0.0, 0.000025),
    ("brushed_steel", "Шлифованный металл", 0.34, 1.0, 0.000018),
    ("oak_longitudinal", "Дуб: продольные волокна", 0.60, 0.0, 0.00008),
    ("oak_endgrain", "Дуб: торцы", 0.67, 0.0, 0.00010),
    ("ivory_coating", "Светлое покрытие / VECTRION", 0.62, 0.0, 0.000035),
]
COMPONENTS = {5120: np.dtype('i1'), 5121: np.dtype('u1'), 5122: np.dtype('<i2'),
              5123: np.dtype('<u2'), 5125: np.dtype('<u4'), 5126: np.dtype('<f4')}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load_glb(path):
    raw = Path(path).read_bytes()
    magic, version, length = struct.unpack_from('<4sII', raw, 0)
    assert magic == b'glTF' and version == 2 and length == len(raw)
    offset = 12
    doc, binary = None, b''
    while offset < length:
        count, kind = struct.unpack_from('<II', raw, offset)
        offset += 8
        chunk = raw[offset:offset + count]
        offset += count
        if kind == 0x4e4f534a:
            doc = json.loads(chunk)
        elif kind == 0x004e4942:
            binary = chunk
    assert doc is not None
    return doc, binary


def accessor(doc, binary, index):
    item = doc['accessors'][index]
    assert 'sparse' not in item, 'Sparse accessor needs an explicit conversion'
    view = doc['bufferViews'][item['bufferView']]
    dtype = COMPONENTS[item['componentType']]
    width = WIDTHS[item['type']]
    result = np.ndarray((item['count'], width), dtype=dtype, buffer=binary,
                        offset=view.get('byteOffset', 0) + item.get('byteOffset', 0),
                        strides=(view.get('byteStride', width * dtype.itemsize), dtype.itemsize)).copy()
    return result[:, 0] if width == 1 else result


def append_accessor(doc, binary, values, data_type, target=34962):
    values = np.ascontiguousarray(values)
    pad = (-len(binary)) % 4
    binary.extend(b'\0' * pad)
    start = len(binary)
    binary.extend(values.tobytes())
    view = len(doc.setdefault('bufferViews', []))
    doc['bufferViews'].append({'buffer': 0, 'byteOffset': start, 'byteLength': values.nbytes, 'target': target})
    component = 5126 if values.dtype.kind == 'f' else (5125 if values.dtype.itemsize == 4 else 5123)
    item = {'bufferView': view, 'componentType': component, 'count': len(values), 'type': data_type}
    if data_type == 'VEC3':
        item['min'] = values.min(axis=0).astype(float).tolist()
        item['max'] = values.max(axis=0).astype(float).tolist()
    doc.setdefault('accessors', []).append(item)
    return len(doc['accessors']) - 1


def write_glb(path, doc, binary):
    doc['buffers'][0]['byteLength'] = len(binary)
    data = json.dumps(doc, ensure_ascii=False, separators=(',', ':')).encode('utf8')
    data += b' ' * ((-len(data)) % 4)
    binary = bytes(binary) + b'\0' * ((-len(binary)) % 4)
    size = 12 + 8 + len(data) + 8 + len(binary)
    Path(path).write_bytes(struct.pack('<4sII', b'glTF', 2, size)
                          + struct.pack('<II', len(data), 0x4e4f534a) + data
                          + struct.pack('<II', len(binary), 0x004e4942) + binary)


def normalize(values):
    return values / np.maximum(np.linalg.norm(values, axis=-1, keepdims=True), 1e-12)


def node_matrix(node):
    if 'matrix' in node:
        return np.asarray(node['matrix'], dtype=float).reshape(4, 4).T
    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
    rotation = np.array([[1-2*y*y-2*z*z, 2*x*y-2*z*w, 2*x*z+2*y*w],
                         [2*x*y+2*z*w, 1-2*x*x-2*z*z, 2*y*z-2*x*w],
                         [2*x*z-2*y*w, 2*y*z+2*x*w, 1-2*x*x-2*y*y]])
    # Zero scales hide authored break states; only the UV reference pose uses 1.
    # The actual GLB nodes, transforms and zero scales are never edited.
    scale = np.asarray(node.get('scale', [1, 1, 1]), dtype=float)
    scale[np.abs(scale) < 1e-12] = 1
    result = np.eye(4)
    result[:3, :3] = rotation @ np.diag(scale)
    result[:3, 3] = node.get('translation', [0, 0, 0])
    return result


def mesh_reference_matrices(doc):
    parents = {child: i for i, node in enumerate(doc['nodes']) for child in node.get('children', [])}
    memo = {}
    def world(i):
        if i not in memo:
            memo[i] = (world(parents[i]) if i in parents else np.eye(4)) @ node_matrix(doc['nodes'][i])
        return memo[i]
    refs = {}
    for i, node in enumerate(doc['nodes']):
        if 'mesh' in node:
            refs.setdefault(node['mesh'], world(i))
    return refs


def select_tile(filename, material):
    name = material.get('name', '')
    base = name.rsplit('.', 1)[0] if name.rsplit('.', 1)[-1].isdigit() else name
    if material.get('alphaMode', 'OPAQUE') == 'BLEND' or 'Glass' in name or 'glass' in name:
        return None
    if 'wood_slat' in filename:
        return 5
    if 'VECTRION' in filename:
        return 7
    if 'column' in filename:
        return 1 if 'column_1' in name else 2
    if 'elevator' in filename:
        if 'Wall_Painted' in name:
            return 0
        return 2 if ('Frame_Metal' in name or 'Shaft_Dark' in name) else 4
    if 'glass_partition_blinds' in filename:
        return 2 if base == 'Material_0' else 7
    if 'glass_partition_half' in filename:
        return 2 if base == 'Material_0' else 1
    if 'glass_wall_full' in filename:
        return 2 if base == 'Material_0' else 3
    if 'glass_door' in filename:
        return 2
    if 'emergency' in filename:
        if base in ['Material_2', 'Material_4'] or 'wall_door_3' in name:
            return 4
        if base == 'Material_1':
            return 3
    if 'wall_door_3' in name:
        return 4
    if 'wall_door_2' in name:
        return 3
    color = material.get('pbrMetallicRoughness', {}).get('baseColorFactor', [1, 1, 1, 1])
    return 0 if np.mean(color[:3]) > 0.5 else 2


def make_atlases(source, output, period_m=4.0):
    source = Image.open(source).convert('RGB')
    resolution, gutter = 4096, 32
    cell = resolution // 4
    inner = cell - 2 * gutter
    color_atlas = np.zeros((cell*2, cell*4, 3), dtype=np.uint8)
    normal_atlas = np.zeros_like(color_atlas)
    orm_atlas = np.zeros_like(color_atlas)
    rng = np.random.default_rng(20261008)
    for i, (name, title, roughness, metalness, relief_m) in enumerate(TILES):
        col, row = i % 4, i // 4
        # Avoid pixels at AI source sheet boundaries; layout is deterministic.
        rect = (round(col*source.width/4)+3, round(row*source.height/2)+3,
                round((col+1)*source.width/4)-3, round((row+1)*source.height/2)-3)
        tile = np.asarray(source.crop(rect).resize((inner, inner), Image.Resampling.LANCZOS), dtype=float)/255
        luminance = np.mean(tile, axis=2)
        fine = luminance - gaussian_filter(luminance, 8)
        fine /= max(float(np.std(fine)), 0.005)
        micro = gaussian_filter(rng.normal(size=(inner, inner)), 0.8)
        micro /= max(float(np.std(micro)), 0.01)
        height = gaussian_filter(0.7*fine + 0.3*micro, 0.65) * relief_m
        if name in ["brushed_steel", "worn_steel"]:
            lines = gaussian_filter(rng.normal(size=(inner, inner)), (8, 0.7))
            height = lines / max(float(np.std(lines)), 0.01) * relief_m
        # A modest fine relief field; normal and roughness share the same detail.
        dy, dx = np.gradient(height, period_m / inner)
        normal = normalize(np.stack((-dx, -dy, np.ones_like(dx)), axis=-1))
        normal = np.round((normal * 0.5 + 0.5)*255).clip(0, 255).astype(np.uint8)
        rough = np.clip(roughness + 0.018 * np.clip(fine, -2, 2), 0, 1)
        # No object-specific AO is baked into reusable surface textures.
        orm = np.stack((np.ones_like(rough), rough, np.full_like(rough, metalness)), axis=-1)
        orm = np.round(orm * 255).astype(np.uint8)
        # Native output microvariation is restrained; avoid adding baked lighting.
        tile = np.clip(tile + micro[..., None]*0.0012, 0, 1)
        color = np.round(tile*255).astype(np.uint8)
        for dest, content in [(color_atlas, color), (normal_atlas, normal), (orm_atlas, orm)]:
            padded = np.pad(content, ((gutter, gutter), (gutter, gutter), (0, 0)), mode='edge')
            dest[row*cell:(row+1)*cell, col*cell:(col+1)*cell] = padded
    texture_dir = output/'textures'
    master_dir = texture_dir/'master_4k'
    master_dir.mkdir(parents=True, exist_ok=True)
    for key, array in [('albedo', color_atlas), ('normal', normal_atlas), ('orm', orm_atlas)]:
        full = Image.fromarray(array)
        encoded=io.BytesIO()
        full.save(encoded,format='PNG',compress_level=6)
        full_path=master_dir/f'architecture_{key}_4k.png'
        full_path.write_bytes(encoded.getvalue())
        Image.open(full_path).verify()
        runtime = np.asarray(full.resize((2048, 1024), Image.Resampling.LANCZOS)).copy()
        if key == 'normal':
            vector = normalize(runtime.astype(float)/255*2-1)
            runtime = np.round((vector*.5+.5)*255).clip(0,255).astype(np.uint8)
        encoded=io.BytesIO()
        Image.fromarray(runtime).save(encoded,format='PNG',compress_level=6)
        runtime_path=texture_dir/f'architecture_{key}.png'
        runtime_path.write_bytes(encoded.getvalue())
        Image.open(runtime_path).verify()
    rects = []
    for i, tile in enumerate(TILES):
        x, y = (i % 4)*cell+gutter, (i // 4)*cell+gutter
        rects.append({'slot': i+1, 'id': tile[0], 'title': tile[1],
                      'pixel_rect_master': [x, y, inner, inner],
                      'uv_rect': [x/4096, y/2048, inner/4096, inner/2048],
                      'roughness_mean': tile[2], 'metallic': tile[3]})
    (output/'atlas_layout.json').write_text(json.dumps({'master_size':[4096,2048],
        'runtime_size':[2048,1024], 'gutter_master_px':32,'gutter_runtime_px':16,
        'origin':'top-left', 'grid':[4,2], 'tiles':rects}, ensure_ascii=False, indent=2))
    return rects


def tangents(positions, normals, uvs):
    points = positions.reshape(-1,3,3)
    uv = uvs.reshape(-1,3,2)
    edge1, edge2 = points[:,1]-points[:,0], points[:,2]-points[:,0]
    delta1, delta2 = uv[:,1]-uv[:,0], uv[:,2]-uv[:,0]
    determinant = delta1[:,0]*delta2[:,1]-delta1[:,1]*delta2[:,0]
    valid = np.abs(determinant)>1e-12
    inv = np.divide(1, determinant, out=np.zeros_like(determinant), where=valid)
    tangent = (edge1*delta2[:,1,None]-edge2*delta1[:,1,None])*inv[:,None]
    bitangent = (-edge1*delta2[:,0,None]+edge2*delta1[:,0,None])*inv[:,None]
    tangent = np.repeat(tangent,3,axis=0)
    bitangent = np.repeat(bitangent,3,axis=0)
    n = normalize(normals)
    tangent -= n*np.sum(n*tangent,axis=1,keepdims=True)
    zero = np.linalg.norm(tangent,axis=1)<1e-10
    if zero.any():
        reference = np.tile([1.,0,0],(zero.sum(),1))
        reference[np.abs(n[zero,0])>.9] = [0,1.,0]
        tangent[zero] = np.cross(reference,n[zero])
    tangent = normalize(tangent)
    sign = np.where(np.sum(np.cross(n,tangent)*bitangent,axis=1)<0,-1.,1.)
    return np.c_[tangent,sign].astype('<f4')


def convert(path, output, rects, period_m=4.0):
    original, source_binary = load_glb(path)
    doc, binary = copy.deepcopy(original), bytearray(source_binary)
    refs = mesh_reference_matrices(original)
    sampler = len(doc.setdefault('samplers',[]))
    doc['samplers'].append({'magFilter':9729,'minFilter':9987,'wrapS':33071,'wrapT':33071})
    texture_indices = {}
    for name in ['albedo','normal','orm']:
        image_index = len(doc.setdefault('images',[]))
        doc['images'].append({'name':'architecture_'+name,'uri':'../textures/architecture_'+name+'.png'})
        tex_index = len(doc.setdefault('textures',[]))
        doc['textures'].append({'sampler':sampler,'source':image_index})
        texture_indices[name]=tex_index
    mapping=[]
    for material_index, material in enumerate(doc.get('materials',[])):
        tile = select_tile(path.name, material)
        if tile is None:
            continue
        source_pbr = copy.deepcopy(material.get('pbrMetallicRoughness',{}))
        material['pbrMetallicRoughness']={'baseColorFactor':[1,1,1,1],
            'baseColorTexture':{'index':texture_indices['albedo']},
            'metallicFactor':1,'roughnessFactor':1,
            'metallicRoughnessTexture':{'index':texture_indices['orm']}}
        if 'Shaft_Dark' in material.get('name',''):
            material['pbrMetallicRoughness']['baseColorFactor']=[.45,.45,.45,1]
        material['normalTexture']={'index':texture_indices['normal'],'scale':1.0}
        material['occlusionTexture']={'index':texture_indices['orm'],'strength':1.0}
        material.setdefault('extras',{})['architecture_atlas_v1']={'slot':tile+1,'id':TILES[tile][0],
            'source_pbr':source_pbr,'glass_excluded':True}
        mapping.append({'file':path.name,'material_index':material_index,
            'material_name':material.get('name',''),'slot':tile+1,'surface':TILES[tile][0]})
    opaque_parts=glass_parts=0
    old_vertices=new_vertices=0
    for mesh_index, mesh in enumerate(doc['meshes']):
        transform = refs.get(mesh_index,np.eye(4))
        for primitive in mesh['primitives']:
            material = original['materials'][primitive['material']]
            tile = select_tile(path.name,material)
            if tile is None:
                glass_parts+=1
                continue
            assert primitive.get('mode',4)==4 and not primitive.get('targets')
            attrs=primitive['attributes']
            source_points=accessor(original,source_binary,attrs['POSITION'])
            index=accessor(original,source_binary,primitive['indices']) if 'indices' in primitive else np.arange(len(source_points))
            points=source_points[index].astype('<f4')
            normals=accessor(original,source_binary,attrs['NORMAL'])[index].astype('<f4')
            world=points.astype(float)@transform[:3,:3].T+transform[:3,3]
            triangles=world.reshape(-1,3,3)
            face_normal=normalize(np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0]))
            axes=np.argmax(np.abs(face_normal),axis=1)
            projection=np.empty((len(world),2),dtype=float)
            slots=np.full(len(world),tile,dtype=int)
            center=(world.min(axis=0)+world.max(axis=0))*.5
            period=max(period_m,float(np.ptp(world,axis=0).max())*1.06)
            for axis in range(3):
                mask=np.repeat(axes==axis,3)
                # Side faces keep texture V aligned with world vertical Y.
                u_axis,v_axis={0:(2,1),1:(0,2),2:(0,1)}[axis]
                projection[mask,0]=.5+(world[mask,u_axis]-center[u_axis])/period
                projection[mask,1]=.5-(world[mask,v_axis]-center[v_axis])/period
                if TILES[tile][0]=='oak_longitudinal' and axis==1:
                    slots[mask]=6
            assert projection.min()>=0 and projection.max()<=1
            uv=np.empty_like(projection)
            for slot in np.unique(slots):
                mask=slots==slot
                x,y,w,h=rects[int(slot)]['uv_rect']
                uv[mask]=[x,y]+projection[mask]*[w,h]
            uv=uv.astype('<f4')
            attrs['POSITION']=append_accessor(doc,binary,points,'VEC3')
            attrs['NORMAL']=append_accessor(doc,binary,normals,'VEC3')
            attrs['TEXCOORD_0']=append_accessor(doc,binary,uv,'VEC2')
            attrs['TANGENT']=append_accessor(doc,binary,tangents(points,normals,uv),'VEC4')
            for key, attribute_index in list(attrs.items()):
                if key not in ['POSITION','NORMAL','TEXCOORD_0','TANGENT']:
                    values=accessor(original,source_binary,attribute_index)[index]
                    attrs[key]=append_accessor(doc,binary,values,original['accessors'][attribute_index]['type'])
            primitive['indices']=append_accessor(doc,binary,np.arange(len(points),dtype='<u4'),'SCALAR',34963)
            old_vertices+=len(source_points);new_vertices+=len(points);opaque_parts+=1
    doc.setdefault('asset',{})['generator']='Infection Shooter architecture atlas v1; preserved authored hierarchy'
    doc.setdefault('extras',{})['architecture_atlas_v1']={
        'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'maps_shared':True,'glass_preserved':True,'uv_period_m':period_m,
        'runtime_resolution':[2048,1024],'master_resolution':[4096,2048],
        'wood_endgrain_slot':7,'normal_convention':'OpenGL/glTF tangent-space',
        'uv_mapping':'per-face planar, physical scale where span permits; fixed atlas regions, no repeat shader'}
    destination=output/'models'/path.name
    destination.parent.mkdir(parents=True,exist_ok=True)
    write_glb(destination,doc,binary)
    return mapping, {'file':path.name,'opaque_surfaces':opaque_parts,'glass_surfaces_preserved':glass_parts,
        'original_opaque_vertices':old_vertices,'atlas_opaque_vertices':new_vertices,
        'source_bytes':path.stat().st_size,'output_bytes':destination.stat().st_size}


def validate_model(source, converted, output):
    a,ab=load_glb(source);b,bb=load_glb(converted)
    assert a['nodes']==b['nodes'], 'Node hierarchy/transforms changed'
    assert a.get('scenes')==b.get('scenes') and a.get('scene')==b.get('scene')
    assert len(a['meshes'])==len(b['meshes'])
    triangles=glass=0
    for old,new in zip(a['meshes'],b['meshes']):
        assert old.get('name')==new.get('name') and len(old['primitives'])==len(new['primitives'])
        for p,q in zip(old['primitives'],new['primitives']):
            assert p['material']==q['material']
            def expanded(doc,binary,part,attribute):
                values=accessor(doc,binary,part['attributes'][attribute])
                index=accessor(doc,binary,part['indices']) if 'indices' in part else np.arange(len(values))
                return values[index]
            assert np.array_equal(expanded(a,ab,p,'POSITION'),expanded(b,bb,q,'POSITION'))
            assert np.array_equal(expanded(a,ab,p,'NORMAL'),expanded(b,bb,q,'NORMAL'))
            n=len(expanded(b,bb,q,'POSITION'));assert n%3==0;triangles+=n//3
            if select_tile(source.name,a['materials'][p['material']]) is None:
                assert p==q and a['materials'][p['material']]==b['materials'][q['material']]
                glass+=1
            else:
                uv=expanded(b,bb,q,'TEXCOORD_0').reshape(-1,3,2)
                assert np.isfinite(uv).all() and uv.min()>=0 and uv.max()<=1
                assigned=np.floor(uv[:,:,0]*4)+4*np.floor(uv[:,:,1]*2)
                assert (assigned==assigned[:,0,None]).all(), 'Triangle crosses atlas cells'
                tangent=expanded(b,bb,q,'TANGENT')
                assert np.isfinite(tangent).all()
                assert np.max(np.abs(np.linalg.norm(tangent[:,:3],axis=1)-1))<1e-5
                for attribute in ['normalTexture','occlusionTexture']:
                    assert attribute in b['materials'][q['material']]
    for image in b.get('images',[]):
        if 'uri' in image:
            assert (converted.parent/image['uri']).is_file()
    return {'file':source.name,'status':'PASS','triangle_count_preserved':triangles,
            'glass_primitives_unchanged':glass,'nodes_preserved':len(a['nodes'])}


def atlas_preview(output):
    image=Image.open(output/'textures/master_4k/architecture_albedo_4k.png').resize((1600,800))
    draw=ImageDraw.Draw(image)
    font_path='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
    try:font=ImageFont.truetype(font_path,19)
    except OSError:font=ImageFont.load_default()
    for i,item in enumerate(TILES):
        x,y=(i%4)*400,(i//4)*400
        draw.rectangle((x+8,y+8,x+392,y+48),fill=(15,20,23))
        draw.text((x+18,y+17),f'{i+1:02d}  {item[0]}',fill=(238,238,230),font=font)
    preview=output/'previews';preview.mkdir(exist_ok=True)
    image.save(preview/'atlas_materials.png')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--inputs',type=Path,required=True)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    rects=make_atlases(args.source,args.output)
    mappings,stats,validation=[],[],[]
    for path in sorted(args.inputs.glob('*.glb')):
        mapping,item=convert(path,args.output,rects);mappings.extend(mapping);stats.append(item)
        validation.append(validate_model(path,args.output/'models'/path.name,args.output))
        print(path.name,'PASS',flush=True)
    with (args.output/'material_assignments.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(mappings[0]));writer.writeheader();writer.writerows(mappings)
    (args.output/'validation.json').write_text(json.dumps({'models':validation,'conversion':stats,
        'note':'No node, transform, triangle positions, triangle normals or glass materials changed.'},ensure_ascii=False,indent=2))
    atlas_preview(args.output)
    print('Complete:',len(validation),'models',flush=True)


if __name__=='__main__':main()
