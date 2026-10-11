"""Build PBR textures for four supplied and five authored low-poly assets."""
import argparse,sys,csv,json,shutil
from pathlib import Path
import numpy as np
from PIL import Image
import build_architecture_pack as base
from weapon_geometry import create_models

FILES=['pistol_lowpoly(2).glb','shotgun_lowpoly.glb','uzi_lowpoly.glb','six_chamber_launcher_lowpoly.glb']
base.TILES=[('blued_gunmetal','Воронёный металл',.34,1,.000003),('worn_steel','Светлый металл кромок',.28,1,.000002),('black_polymer','Чёрный полимер',.52,0,.000004),('coyote_polymer','Коричневый полимер',.56,0,.000004),('olive_paint','Оливковая краска',.48,0,.000003),('walnut','Тёмный орех',.44,0,.000006),('cordura','Ткань рюкзака',.92,0,.000075),('brass','Латунь',.28,1,.000002)]

def select_tile(filename,material):
    name=material.get('name','').lower().split('.')[0]
    return {'metal':0,'gunmetal':0,'edge':1,'edges':1,'black':2,'dark_holes':2,'tan':3,'olive':4,'walnut':5,'cordura':6,'brass':7}[name]

base.select_tile=select_tile

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--inputs',type=Path,required=True);parser.add_argument('--source',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();out=args.output;out.mkdir(parents=True,exist_ok=True)
    raw=out/'sources/new_model_geometry';raw.mkdir(parents=True,exist_ok=True)
    create_models(raw)
    rects=base.make_atlases(args.source,out,period_m=.75)
    checks=[];mappings=[];stats=[]
    for source in [*(args.inputs/n for n in FILES),*sorted(raw.glob('*.glb'))]:
        rows,s=base.convert(source,out,rects,period_m=.75)
        target=out/'models'/source.name
        # Preserve the supplied filename, including (2), in this standalone pack.
        doc,binary=base.load_glb(target)
        doc['asset']['generator']='Infection Shooter textured low-poly weapons v2'
        info=doc['extras'].pop('architecture_atlas_v1');info.pop('wood_endgrain_slot',None)
        doc['extras']['weapon_atlas_v1']=info
        for material in doc['materials']:
            if 'architecture_atlas_v1' in material.get('extras',{}):material['extras']['weapon_atlas_v1']=material['extras'].pop('architecture_atlas_v1')
        base.write_glb(target,doc,binary)
        result=base.validate_model(source,target,out);result.pop('glass_primitives_unchanged',None)
        result['kind']='textured_original' if source.name in FILES else 'new_model'
        names=[n['name'] for n in doc['nodes']]
        required=['BackSocket','FeedPort'] if 'backpack' in source.name else ['Muzzle','Grip_L','Grip_R']
        assert all(n in names for n in required),source.name
        result['attachment_markers']=required
        triangles=0;all_points=[]
        refs=base.mesh_reference_matrices(doc)
        for mi,mesh in enumerate(doc['meshes']):
            for part in mesh['primitives']:
                p=base.accessor(doc,binary,part['attributes']['POSITION'])
                ix=base.accessor(doc,binary,part['indices']) if 'indices' in part else np.arange(len(p))
                p=p[ix];triangles+=len(p)//3
                tri=p.reshape(-1,3,3)
                assert (np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),'Degenerate triangles'
                transform=refs[mi];all_points.append(p@transform[:3,:3].T+transform[:3,3])
        result['dimensions_m']=np.ptp(np.concatenate(all_points),axis=0).tolist()
        result['triangles']=triangles
        checks.append(result);mappings.extend(rows);stats.append(s)
        print(source.name,'PASS',triangles,flush=True)
    (out/'validation.json').write_text(json.dumps({'models':checks,'conversion':stats,'source_texture_size':list(Image.open(args.source).size),'normal_maps':'artistic synthesized tangent-space OpenGL, not scanned','uv_scale_m':.75},indent=2))
    with (out/'material_assignments.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(mappings[0]));writer.writeheader();writer.writerows(mappings)
    base.atlas_preview(out)
    (out/'scripts').mkdir(exist_ok=True)
    for source in [Path(__file__),Path(base.__file__),Path(__file__).with_name('weapon_geometry.py')]:shutil.copy2(source,out/'scripts'/source.name)
    shutil.copy2(args.source,out/'sources/albedo_source.png')

if __name__=='__main__':main()
