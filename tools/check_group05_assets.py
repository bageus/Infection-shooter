#!/usr/bin/env python3
"""Verify exact group-05 triangle attributes, stage membership and atlas provenance."""
import json, subprocess
from pathlib import Path
from build_group05_assets import GROUP, ROOT, source, stages, canonical
from check_group01_atlas import read_glb, expanded
from check_model_textures import audit, validate_png


def signature(doc,binary,roots):
    result=[]
    def visit(i):
        node=doc['nodes'][i]
        if 'mesh'in node:
            attributes=[]
            for p in doc['meshes'][node['mesh']]['primitives']:
                attributes.append((canonical(doc['materials'][p['material']]), {k:expanded(doc,binary,p,k) for k in p['attributes']}))
            # Stage wrappers and geometry suffixes are the only renamed nodes.
            name=node['name'].removesuffix('Geometry')
            result.append((name,{k:node[k] for k in ['matrix','translation','rotation','scale'] if k in node},attributes))
        for child in node.get('children',[]):visit(child)
    for root in roots:visit(root)
    return result


def main():
    manifest=json.loads((GROUP/'lazy_stages.json').read_text())
    assert len(manifest)==22
    count=0
    for path in sorted(GROUP.glob('*.glb')):
        old,oldbin=read_glb(source(path))
        targets={'Intact':path,**{e['name']:ROOT/e['path'][6:] for e in manifest[path.name]}}
        assert set(targets)==set(stages(old)),path.name
        for stage,roots in stages(old).items():
            target=targets[stage];new,newbin=read_glb(target.read_bytes())
            assert len(new['scenes'])==1
            before=signature(old,oldbin,roots);after=signature(new,newbin,new['scenes'][0]['nodes'])
            # New material names carry a deterministic semantic suffix.
            for sig in after:
                for mat,attrs in sig[2]:
                    mat['name']=mat['name'].split('__')[0]
            for sig in before:
                for mat,attrs in sig[2]:mat['name']=mat['name'].split('__')[0]
            assert before==after,path.name+'/'+stage+': authored triangles/UV/normals/transforms changed'
            assert not audit(target)['errors'],str(target)
            live={a for m in new['meshes']for p in m['primitives']for a in [*p['attributes'].values(),p['indices']]}
            assert live==set(range(len(new['accessors'])))
            assert {a['bufferView']for a in new['accessors']}==set(range(len(new['bufferViews'])))
            assert 'group05_material_post_import.gd' in Path(str(target)+'.import').read_text()
            count+=1
    for kind,limit in [('basecolor',2048),('normal',1024),('orm',1024)]:
        p=GROUP/'atlas'/f'05_shared_{kind}.png'
        original=source(p);assert p.read_bytes()==original,'Atlas pixels changed'
        validate_png(original);profile=Path(str(p)+'.import').read_text()
        for setting in ['compress/mode=2','mipmaps/generate=true',f'process/size_limit={limit}']:assert setting in profile
    # No remaining GLB anywhere may refer to the removed electronics maps.
    for p in (ROOT/'models').rglob('*.glb'):
        doc,_=read_glb(p.read_bytes())
        for image in doc.get('images',[]):
            assert 'electronics_' not in image.get('uri','') or '/05/' not in str((p.parent/image['uri']).resolve())
    print(f'Group05: {len(manifest)} intact models, {count-len(manifest)} lazy stages; exact geometry/UV/material factors/atlas/import PASS')

if __name__=='__main__':main()
