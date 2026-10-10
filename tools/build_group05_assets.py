#!/usr/bin/env python3
"""Compact group 05 without changing authored UVs, materials or triangle attributes.

Requires offline numpy. Sources are pinned to Git; no runtime dependency.
"""
import argparse, copy, hashlib, json, re, struct, subprocess
from pathlib import Path
from check_group01_atlas import read_glb, accessor
from deduplicate_model_textures import encode_glb

ROOT = Path(__file__).resolve().parents[1]
GROUP = ROOT / 'models/objects/enviroments/05'
SOURCE_REF = 'a48e5a49028b0871852f4418eeb8eb2670671ea2'
INDEX_EXTRAS = {'large_part_nodes', 'fragment_nodes', 'power_off_node', 'detachable_cover_node', 'persistent_inner_node'}


def source(path):
    return subprocess.check_output(['git', 'show', SOURCE_REF+':'+path.relative_to(ROOT).as_posix()], cwd=ROOT)


def stages(doc):
    filled = [s for s in doc['scenes'] if s.get('nodes')]
    if len(filled) > 1:
        result = {s['name']: s['nodes'] for s in filled}
        if result.get('SmallFragments') == result.get('LargeParts'):
            result.pop('SmallFragments', None) # No finer geometry exists in these seven sources.
        return result
    default = doc['scenes'][doc.get('scene', 0)]
    roots = default['nodes']
    # Seven exports lost scene membership, but retain explicit authored node names.
    if any(doc['nodes'][i].get('name') == 'Intact' for i in roots) and len(roots)>1:
        result = {'Intact': [], 'Power_Off': [], 'LargeParts': [], 'SmallFragments': []}
        for i in roots:
            name = doc['nodes'][i]['name']
            stage = name if name in ['Intact','Power_Off'] else ('SmallFragments' if '_fragment_' in name.lower() else 'LargeParts')
            result[stage].append(i)
        return {k:v for k,v in result.items() if v}
    return {'Intact': roots}


def canonical(mat):
    mat = copy.deepcopy(mat)
    mat.pop('extras', None)
    mat['name'] = re.sub(r'\.\d+$', '', mat['name'])
    digest = hashlib.sha256(json.dumps(mat,sort_keys=True).encode()).hexdigest()[:8]
    mat['name'] += '__' + digest
    return mat


class Writer:
    def __init__(self, doc, binary):
        self.doc, self.source_binary = doc, binary
        self.binary = bytearray()
        self.views, self.accessors, self.meshes = [], [], []
        self.mesh_map = {}

    def add(self, values, kind, index=False):
        import numpy as np
        values = np.asarray(values)
        component = (5123 if values.max()<65536 else 5125) if index else 5126
        values = values.astype({5123:np.uint16,5125:np.uint32,5126:np.float32}[component])
        self.binary.extend(b'\0'*(-len(self.binary)%4))
        offset = len(self.binary); self.binary.extend(values.tobytes())
        self.views.append({'buffer':0,'byteOffset':offset,'byteLength':values.nbytes,'target':34963 if index else 34962})
        item = {'bufferView':len(self.views)-1,'componentType':component,'count':len(values),'type':kind}
        if kind == 'VEC3': item.update(min=values.min(axis=0).tolist(),max=values.max(axis=0).tolist())
        self.accessors.append(item)
        return len(self.accessors)-1

    def mesh(self, old):
        import numpy as np
        if old in self.mesh_map: return self.mesh_map[old]
        mesh = copy.deepcopy(self.doc['meshes'][old]); primitives=[]
        for p in mesh['primitives']:
            keys=sorted(p['attributes'])
            arrays=[np.array(accessor(self.doc,self.source_binary,p['attributes'][k]),dtype=np.float32) for k in keys]
            values=np.concatenate(arrays,axis=1)
            unique, remap=np.unique(values,axis=0,return_inverse=True)
            ids=np.array([x[0] for x in accessor(self.doc,self.source_binary,p['indices'])]) if 'indices' in p else np.arange(len(values))
            attrs={}; offset=0
            for key,a in zip(keys,arrays):
                width=a.shape[1]
                attrs[key]=self.add(unique[:,offset:offset+width],self.doc['accessors'][p['attributes'][key]]['type']);offset+=width
            primitive=copy.deepcopy(p);primitive['attributes']=attrs;primitive['indices']=self.add(remap[ids],'SCALAR',True)
            primitives.append(primitive)
        mesh['primitives']=primitives;self.meshes.append(mesh);self.mesh_map[old]=len(self.meshes)-1
        return len(self.meshes)-1

    def save(self,path,stage,roots):
        nodes=[]
        def visit(index):
            n=copy.deepcopy(self.doc['nodes'][index]);new=len(nodes);nodes.append(n)
            if 'mesh' in n:n['mesh']=self.mesh(n['mesh'])
            if 'children' in n:n['children']=[visit(i) for i in n['children']]
            if 'extras' in n:n['extras']={k:v for k,v in n['extras'].items() if k not in INDEX_EXTRAS}
            # Avoid a duplicate Intact/Power_Off name under the named stage wrapper.
            if n.get('name')==stage:n['name']=stage+'Geometry'
            return new
        children=[visit(i) for i in roots];nodes.append({'name':stage,'children':children})
        out={k:copy.deepcopy(v) for k,v in self.doc.items() if k not in ['nodes','scenes','scene','meshes','accessors','bufferViews','buffers','materials']}
        out.update(nodes=nodes,scene=0,scenes=[{'name':path.stem,'nodes':[len(nodes)-1]}],meshes=self.meshes,accessors=self.accessors,bufferViews=self.views,buffers=[{'byteLength':len(self.binary)}])
        used=sorted({p['material'] for m in self.meshes for p in m['primitives']})
        out['materials']=[canonical(self.doc['materials'][i]) for i in used];mapping={v:i for i,v in enumerate(used)}
        for m in self.meshes:
            for p in m['primitives']:p['material']=mapping[p['material']]
        if path.parent.name=='damage':
            for image in out.get('images',[]):image['uri']='../'+image['uri']
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(encode_glb(out,bytes(self.binary)))


def material_resource(mat, index):
    pbr=mat.get('pbrMetallicRoughness',{}); linear=pbr.get('baseColorFactor',[1,1,1,1]); emission=mat.get('emissiveFactor',[0,0,0])
    srgb=lambda v:12.92*v if v<=0.0031308 else 1.055*v**(1/2.4)-0.055
    color=[srgb(v) for v in linear[:3]]+[linear[3]]
    emission=[srgb(v) for v in emission]
    lines=['[gd_resource type="StandardMaterial3D" load_steps=4 format=3]', '']
    for i,kind in enumerate(['basecolor','normal','orm'],1):lines.append(f'[ext_resource type="Texture2D" path="res://models/objects/enviroments/05/atlas/05_shared_{kind}.png" id="{i}"]')
    lines += ['', '[resource]',f'resource_name = "{mat["name"]}"','cull_mode = 2', 'albedo_color = Color('+', '.join(map(str,color))+')','albedo_texture = ExtResource("1")','metallic = '+str(pbr.get('metallicFactor',1)), 'metallic_texture = ExtResource("3")','metallic_texture_channel = 2','roughness = '+str(pbr.get('roughnessFactor',1)), 'roughness_texture = ExtResource("3")','roughness_texture_channel = 1','normal_enabled = true','normal_scale = '+str(mat.get('normalTexture',{}).get('scale',1)), 'normal_texture = ExtResource("2")','ao_enabled = true','ao_texture = ExtResource("3")','ao_texture_channel = 0','texture_filter = 5','texture_repeat = true']
    if any(emission):lines += ['emission_enabled = true','emission = Color('+', '.join(map(str,emission))+', 1)']
    path=GROUP/'materials'/f'group05_{index:02d}.tres';path.parent.mkdir(exist_ok=True);path.write_text('\n'.join(lines)+'\n')
    return 'res://'+path.relative_to(ROOT).as_posix()


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--apply',action='store_true',required=True);parser.parse_args()
    manifest={};report={};materials={}
    for path in sorted(GROUP.glob('*.glb')):
        original=source(path);doc,binary=read_glb(original);groups=stages(doc);manifest[path.name]=[];stats=[]
        for stage,roots in groups.items():
            target=path if stage=='Intact' else GROUP/'damage'/f'{path.stem}_{stage.lower()}.glb'
            writer=Writer(doc,binary);writer.save(target,stage,roots)
            if stage!='Intact':manifest[path.name].append({'name':stage,'path':'res://'+target.relative_to(ROOT).as_posix()})
            stats.append({'stage':stage,'bytes':target.stat().st_size,'meshes':len(writer.meshes),'surfaces':sum(len(m['primitives']) for m in writer.meshes)})
        used={p['material'] for m in doc['meshes'] for p in m['primitives']}
        for index in sorted(used):
            m=canonical(doc['materials'][index]);materials.setdefault(json.dumps(m,sort_keys=True),m)
        report[path.name]={'source_sha256':hashlib.sha256(original).hexdigest(),'source_bytes':len(original),'stages':stats,'repaired_scene_membership':len([s for s in doc['scenes']if s.get('nodes')])==1 and len(groups)>1}
    registry={}
    for i,(key,mat) in enumerate(sorted(materials.items())):registry[mat['name']]=material_resource(mat,i)
    (GROUP/'materials.json').write_text(json.dumps(registry,indent=2)+'\n')
    (GROUP/'lazy_stages.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (GROUP/'asset_report.json').write_text(json.dumps({'source_ref':SOURCE_REF,'models':report},indent=2)+'\n')
    # Keep the static preload table in sync when rebuilding from pinned sources.
    post=ROOT/'addons/staged_glb_import/group05_material_post_import.gd'
    text=post.read_text()
    table='const MATERIALS := {\n'+''.join('\t'+json.dumps(n)+': preload('+json.dumps(p)+'),\n' for n,p in registry.items())+'}'
    post.write_text(re.sub(r'const MATERIALS := \{.*?\n\}',lambda _:table,text,flags=re.S))
    print('Models:',len(report),'lazy stages:',sum(map(len,manifest.values())),'shared materials:',len(registry))

if __name__=='__main__':main()
