#!/usr/bin/env python3
"""Validate group-03 atlas, lazy resource boundaries and authored surface preservation."""
import argparse, json, math
from pathlib import Path
import numpy as np
from build_group03_atlas import ROOT, GROUP, SOURCE_REF, git_bytes, stages, collect
from check_group01_atlas import read_glb, accessor, containing_tile
from check_model_textures import audit, validate_png


def triangles(doc,binary,entries):
    result=[]
    for node,matrix in entries:
        for p in doc['meshes'][node['mesh']]['primitives']:
            vertices=np.array(accessor(doc,binary,p['attributes']['POSITION']))
            ids=np.array([x[0] for x in accessor(doc,binary,p['indices'])]) if 'indices'in p else np.arange(len(vertices))
            positions=vertices@matrix[:3,:3].T+matrix[:3,3]
            result.extend(positions[ids].reshape(-1,3,3))
    return np.array(result)


def areas(tris):
    return np.linalg.norm(np.cross(tris[:,1]-tris[:,0],tris[:,2]-tris[:,0]),axis=1)/2


def preserve(before,after,label):
    assert math.isclose(areas(before).sum(),areas(after).sum(),rel_tol=2e-6,abs_tol=1e-7), label+': surface area changed'
    assert np.allclose(before.min(axis=(0,1)),after.min(axis=(0,1)),atol=2e-6), label+': minimum bounds changed'
    assert np.allclose(before.max(axis=(0,1)),after.max(axis=(0,1)),atol=2e-6), label+': maximum bounds changed'
    # Deterministic interior samples must lie on source triangles, not just share bounds.
    step=max(1,len(after)//200)
    points=after[::step].mean(axis=1)
    a=before[:,0];u=before[:,1]-a;v=before[:,2]-a
    uu=np.sum(u*u,axis=1);uv=np.sum(u*v,axis=1);vv=np.sum(v*v,axis=1);det=uu*vv-uv*uv
    valid=np.abs(det)>1e-20;den=np.where(valid,det,1)
    for point in points:
        w=point-a;wu=np.sum(w*u,axis=1);wv=np.sum(w*v,axis=1)
        s=(vv*wu-uv*wv)/den;t=(uu*wv-uv*wu)/den
        projected=a+u*s[:,None]+v*t[:,None]
        match=valid&(s>=-2e-5)&(t>=-2e-5)&(s+t<=1+2e-5)&(np.linalg.norm(projected-point,axis=1)<2e-6)
        assert match.any(),label+': generated surface left original geometry'


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--compare-source',action='store_true');args=parser.parse_args()
    layout=json.loads((GROUP/'atlas_layout.json').read_text());manifest=json.loads((GROUP/'lazy_stages.json').read_text())
    originals=list(GROUP.glob('*.glb'));assert len(originals)==15 and len(manifest)==15
    resources=list(GROUP.rglob('*.glb'));assert len(resources)==53
    for path in resources:
        assert not audit(path)['errors'],path.name
        doc,binary=read_glb(path.read_bytes());assert len(doc['scenes'])==1
        live=set()
        for mesh in doc['meshes']:
            for p in mesh['primitives']:
                live.update(p['attributes'].values());live.add(p['indices'])
                mat=doc['materials'][p['material']]
                if mat['name']=='Group03Glass':continue
                values=accessor(doc,binary,p['attributes']['TEXCOORD_0']);ids=[v[0] for v in accessor(doc,binary,p['indices'])]
                for i in range(0,len(ids),3):containing_tile([values[j] for j in ids[i:i+3]],layout['tiles'])
        assert live==set(range(len(doc['accessors']))),path.name+': orphan accessor'
        assert {a['bufferView'] for a in doc['accessors']}==set(range(len(doc['bufferViews']))),path.name+': orphan view'
        assert len(binary)-sum(v['byteLength'] for v in doc['bufferViews'])<=4*len(doc['bufferViews'])
        profile=Path(str(path)+'.import').read_text();assert 'group03_material_post_import.gd' in profile
    for kind,limit in [('albedo',2048),('normal',1024),('orm',1024),('emission',1024)]:
        path=GROUP/f'textures/unified/group03_{kind}.png';validate_png(path.read_bytes());profile=Path(str(path)+'.import').read_text()
        for setting in ['compress/mode=2','mipmaps/generate=true','process/size_limit='+str(limit)]:assert setting in profile
    if args.compare_source:
        for path in originals:
            old,oldbin=read_glb(git_bytes(SOURCE_REF,path.relative_to(ROOT).as_posix()))
            targets={'Intact':path,**{entry['name']:ROOT/entry['path'][6:] for entry in manifest[path.name]}}
            for name,roots,parent in stages(old):
                new,newbin=read_glb(targets[name].read_bytes());before=triangles(old,oldbin,collect(old,roots,parent));after=triangles(new,newbin,collect(new,new['scenes'][0]['nodes']))
                preserve(before,after,path.name+'/'+name)
    print('Group03 atlas: 15 intact models, 38 lazy stages, UV/PBR/import/geometry PASS')

if __name__=='__main__':main()
