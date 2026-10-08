"""Geometry regression checks for the reported v1 assembly defects."""
import json
import numpy as np
from weapon_geometry import ak,m4,sniper
from build_architecture_pack import accessor
from pathlib import Path

def parts(model):
    return {n['name']:accessor(model.doc,model.bin,model.doc['meshes'][n['mesh']]['primitives'][0]['attributes']['POSITION']) for n in model.doc['nodes'] if 'mesh' in n}

def overlap(a,b):
    return (np.minimum(a.max(0),b.max(0))-np.maximum(a.min(0),b.min(0))).tolist()

a=parts(ak());checks={}
for name in ['CurvedMagazine','Trigger','TriggerGuardFront','TriggerGuardRear']:
    penetration=overlap(a[name],a['Receiver'])
    assert min(penetration)>0,(name,penetration)
    checks['AK_'+name+'_receiver_overlap_m']=penetration
for factory,name,polygon,depth in [(ak,'AK',[(.004,.044),(.087,.044),(.122,-.13),(.157,-.235),(.105,-.264),(.062,-.183),(.028,-.109)],.049),(m4,'M4',[(.006,.035),(.072,.035),(.107,-.184),(.043,-.19)],.047)]:
    model=parts(factory());count=0
    for part,vertices in model.items():
        if not part.startswith('MagazineRib_'):continue
        count+=1
        for x,y,z in vertices:
            crossings=[]
            for a,b in zip(polygon,polygon[1:]+polygon[:1]):
                if min(a[1],b[1])<=y<=max(a[1],b[1]) and abs(b[1]-a[1])>1e-9:
                    crossings.append(a[0]+(y-a[1])*(b[0]-a[0])/(b[1]-a[1]))
            assert min(crossings)<x<max(crossings),(name,part,x,y)
        assert min(abs(vertices[:,2]))<depth/2<max(abs(vertices[:,2])),part
    checks[name+'_rib_parts_within_outline_and_embedded']=count
assert not any('Bipod' in n for n in parts(sniper()))
checks['sniper_bipod_removed']=True
p=Path('output/infection_weapon_pack_v2/revision_geometry_validation.json')
p.write_text(json.dumps(checks,indent=2));print(json.dumps(checks,indent=2))
