"""Build shared modern stairs/elevator atlas. Requires numpy, Pillow, scipy."""
import argparse,csv,json,shutil,io
from pathlib import Path
from PIL import Image
import build_architecture_pack as base

FILES=['01_stairs.glb','01_stairs_2.glb','01_elevator_cabin_freight.glb','01_elevator_cabin_passenger.glb']
base.TILES=[
 ('graphite_coating','Графитовая краска',.57,0,.000045),
 ('light_epoxy','Светло-серая эпоксидная краска',.55,0,.000035),
 ('stair_grip','Нескользящее покрытие ступеней',.87,0,.00012),
 ('passenger_terrazzo','Тёмный мелкозернистый терраццо',.53,0,.000025),
 ('brushed_steel','Шлифованная сталь',.34,1,.000018),
 ('freight_rubber','Резиновый пол грузового лифта',.89,0,.00012),
 ('smoked_steel','Тонированная шлифованная сталь',.39,1,.000018),
 ('ceiling_white','Светлое покрытие потолка',.57,0,.00003)]

def select_tile(filename,material):
    name=material.get('name','').lower()
    if name.startswith('light') or name.startswith('door_gap'):return None
    if name.startswith('steel_trim') or name.startswith('dark_steel'):return 0
    if name.startswith('steel_epoxy'):return 1
    if name.startswith('floor_grip'):return 2
    if name.startswith('cabin_wall') or name.startswith('brushed_steel') or name.startswith('rail') or name.startswith('buttons'):return 4
    if name.startswith('ceiling'):return 7
    if name.startswith('floor'):return 5 if 'freight' in filename else 3
    if name.startswith('rear_panel'):return 6
    raise ValueError((filename,name))

base.select_tile=select_tile

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--inputs',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();out=args.output;out.mkdir(parents=True,exist_ok=True)
    rects=base.make_atlases(args.source,out)
    # Re-encode from complete in-memory buffers and validate PNG checksums.
    for image_path in (out/'textures').rglob('*.png'):
        image=Image.open(image_path);image.load()
        buffer=io.BytesIO();image.save(buffer,format='PNG',compress_level=6)
        image_path.write_bytes(buffer.getvalue());Image.open(image_path).verify()
    mappings=[];converted=[];checks=[]
    for filename in FILES:
        source=args.inputs/filename
        rows,stats=base.convert(source,out,rects)
        target=out/'models'/filename
        doc,binary=base.load_glb(target)
        doc['asset']['generator']='Infection Shooter modern stairs/elevators atlas v1'
        doc['extras']['stairs_elevators_atlas_v1']=doc['extras'].pop('architecture_atlas_v1')
        doc['extras']['stairs_elevators_atlas_v1'].pop('wood_endgrain_slot',None)
        for material in doc['materials']:
            if 'architecture_atlas_v1' in material.get('extras',{}):
                material['extras']['stairs_elevators_atlas_v1']=material['extras'].pop('architecture_atlas_v1')
        base.write_glb(target,doc,binary)
        check=base.validate_model(source,target,out)
        check['untextured_light_and_display_surfaces_preserved']=check.pop('glass_primitives_unchanged')
        stats['untextured_light_and_display_surfaces_preserved']=stats.pop('glass_surfaces_preserved')
        mappings.extend(rows);converted.append(stats);checks.append(check)
        print(filename,'PASS',flush=True)
    with (out/'material_assignments.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(mappings[0]));writer.writeheader();writer.writerows(mappings)
    (out/'validation.json').write_text(json.dumps({'models':checks,'conversion':converted,'note':'Authored node hierarchy, transforms, triangle positions and normals preserved; Light and Door_Gap materials and primitives unchanged.'},indent=2))
    base.atlas_preview(out)
    for folder in ['sources','scripts']:(out/folder).mkdir(exist_ok=True)
    shutil.copy2(args.source,out/'sources/albedo_source.png')
    shutil.copy2(__file__,out/'scripts/build_stairs_elevators_pack.py')
    shutil.copy2(Path(base.__file__),out/'scripts/build_architecture_pack.py')

if __name__=='__main__':main()
