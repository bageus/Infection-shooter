"""Deterministic faceted weapon meshes, in meters; forward +X, up +Y."""
import math
from pathlib import Path
import numpy as np
from build_architecture_pack import append_accessor,write_glb,accessor

MATERIALS=['gunmetal','edges','black','tan','olive','walnut','cordura','brass']

class Model:
    def __init__(self,name):
        self.doc={'asset':{'version':'2.0','generator':'Infection Shooter low-poly weapon kit v1'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':'WeaponRoot','children':[1]},{'name':name+'_Visual','children':[]}],'meshes':[],'materials':[{'name':n,'pbrMetallicRoughness':{'baseColorFactor':[.25,.25,.25,1],'metallicFactor':0,'roughnessFactor':.7}} for n in MATERIALS],'buffers':[{'byteLength':0}]}
        self.bin=bytearray();self.triangles=0
    def part(self,name,faces,material):
        positions=[];normals=[]
        for face in faces:
            for i in range(1,len(face)-1):
                p=np.array([face[0],face[i],face[i+1]],dtype=float)
                n=np.cross(p[1]-p[0],p[2]-p[0]);length=np.linalg.norm(n)
                if length<1e-10:continue
                n/=length;positions.extend(p);normals.extend([n]*3)
        if not positions:return
        p=np.asarray(positions,dtype='<f4');n=np.asarray(normals,dtype='<f4')
        primitive={'attributes':{'POSITION':append_accessor(self.doc,self.bin,p,'VEC3'),'NORMAL':append_accessor(self.doc,self.bin,n,'VEC3')},'mode':4,'material':material}
        mesh=len(self.doc['meshes']);self.doc['meshes'].append({'name':name,'primitives':[primitive]})
        node=len(self.doc['nodes']);self.doc['nodes'].append({'name':name,'mesh':mesh});self.doc['nodes'][1]['children'].append(node)
        self.triangles+=len(p)//3
    def marker(self,name,point):
        node=len(self.doc['nodes']);self.doc['nodes'].append({'name':name,'translation':list(point)});self.doc['nodes'][0]['children'].append(node)
    def profile(self,name,polygon,z,depth,material):
        # Outline is counterclockwise in XY. Front at +Z, back at -Z.
        area=sum(polygon[i][0]*polygon[(i+1)%len(polygon)][1]-polygon[(i+1)%len(polygon)][0]*polygon[i][1] for i in range(len(polygon)))
        if area<0:polygon=list(reversed(polygon))
        front=[(x,y,z+depth/2) for x,y in polygon];back=[(x,y,z-depth/2) for x,y in polygon]
        # Ear clipping keeps concave stocks and curved magazines watertight.
        cross=lambda a,b,c:(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
        remaining=list(range(len(polygon)));triangles=[]
        while len(remaining)>3:
            found=False
            for k in range(len(remaining)):
                a,b,c=remaining[k-1],remaining[k],remaining[(k+1)%len(remaining)]
                if cross(polygon[a],polygon[b],polygon[c])<=1e-12:continue
                inside=lambda p:all(cross(polygon[i],polygon[j],p)>=-1e-12 for i,j in [(a,b),(b,c),(c,a)])
                if any(inside(polygon[t]) for t in remaining if t not in [a,b,c]):continue
                triangles.append([a,b,c]);remaining.pop(k);found=True;break
            if not found:raise ValueError('Invalid outline '+name)
        triangles.append(remaining)
        faces=[]
        for triangle in triangles:faces.extend([[front[i] for i in triangle],[back[i] for i in reversed(triangle)]])
        for i in range(len(front)):
            j=(i+1)%len(front);faces.append([back[i],back[j],front[j],front[i]])
        self.part(name,faces,material)
    def box(self,name,center,size,material,bevel=0):
        x,y,z=center;w,h,d=size;w/=2;h/=2
        k=min(bevel,w*.45,h*.45)
        polygon=[(x-w+k,y-h),(x+w-k,y-h),(x+w,y-h+k),(x+w,y+h-k),(x+w-k,y+h),(x-w+k,y+h),(x-w,y+h-k),(x-w,y-h+k)] if k else [(x-w,y-h),(x+w,y-h),(x+w,y+h),(x-w,y+h)]
        self.profile(name,polygon,z,d,material)
    def cylinder(self,name,center,length,radius,material,axis='x',segments=10,inner=0):
        a=np.array([1,0,0] if axis=='x' else ([0,1,0] if axis=='y' else [0,0,1]),float)
        self.between(name,np.array(center)-a*length/2,np.array(center)+a*length/2,radius,material,segments,inner)
    def between(self,name,start,end,radius,material,segments=10,inner=0):
        start=np.array(start,float);end=np.array(end,float);a=end-start;a/=np.linalg.norm(a)
        ref=np.array([0,1,0] if abs(a[1])<.9 else [1,0,0],float)
        u=np.cross(ref,a);u/=np.linalg.norm(u);v=np.cross(a,u)
        ring=lambda p,r:[p+r*(u*math.cos(i*2*math.pi/segments)+v*math.sin(i*2*math.pi/segments)) for i in range(segments)]
        one=ring(start,radius);two=ring(end,radius);faces=[]
        for i in range(segments):
            j=(i+1)%segments;faces.append([one[i],one[j],two[j],two[i]])
        if inner:
            i1=ring(start,inner);i2=ring(end,inner)
            for i in range(segments):
                j=(i+1)%segments
                faces.extend([[i1[j],i1[i],i2[i],i2[j]],[one[j],one[i],i1[i],i1[j]],[two[i],two[j],i2[j],i2[i]]])
        else:faces.extend([list(reversed(one)),two])
        self.part(name,faces,material)
    def compact(self):
        # Keep movable assemblies separate; batch static details by material.
        groups={}
        for node in self.doc['nodes']:
            if 'mesh' not in node:continue
            name=node['name'];group='Body'
            if 'Magazine' in name:group='Magazine'
            elif name.startswith('Bolt'):group='Bolt'
            elif name in ['ScopeTube','Objective','ScopeLens','Eyepiece','ScopeTurret']:group='Scope'
            elif name=='Rotor' or name.startswith(('Barrel_','BarrelClamp','MuzzleRim_','Bore_')):group='BarrelCluster'
            for part in self.doc['meshes'][node['mesh']]['primitives']:
                material=part['material'];bucket=groups.setdefault(group,{}).setdefault(material,[])
                bucket.append((accessor(self.doc,self.bin,part['attributes']['POSITION']),accessor(self.doc,self.bin,part['attributes']['NORMAL'])))
        markers=[node for node in self.doc['nodes'][2:] if 'mesh' not in node]
        self.doc['meshes']=[];self.doc['nodes']=self.doc['nodes'][:2]
        self.doc['nodes'][0]['children']=[1];self.doc['nodes'][1]['children']=[]
        for name,materials in groups.items():
            primitives=[]
            for material,parts in materials.items():
                p=np.concatenate([part[0] for part in parts]);n=np.concatenate([part[1] for part in parts])
                primitives.append({'attributes':{'POSITION':append_accessor(self.doc,self.bin,p,'VEC3'),'NORMAL':append_accessor(self.doc,self.bin,n,'VEC3')},'mode':4,'material':material})
            mesh=len(self.doc['meshes']);self.doc['meshes'].append({'name':name,'primitives':primitives})
            node=len(self.doc['nodes']);self.doc['nodes'].append({'name':name,'mesh':mesh});self.doc['nodes'][1]['children'].append(node)
        for marker in markers:
            node=len(self.doc['nodes']);self.doc['nodes'].append(marker);self.doc['nodes'][0]['children'].append(node)
    def save(self,path):
        self.compact()
        write_glb(path,self.doc,self.bin)

def grip(m,x,y,z=0,material=2):
    m.profile('PistolGrip',[(x-.035,y-.15),(x+.025,y-.15),(x+.048,y-.025),(x+.03,y+.025),(x-.032,y+.022)],z,.06,material)
    for i in range(4):m.box('GripRib_%02d'%i,(x-.003,y-.045-i*.021,z+.031),(.045,.006,.006),2)
    m.marker('Grip_R',(x,y-.025,z))

def guard(m,x,y):
    m.box('TriggerGuardBottom',(x+.028,y-.082,0),(.11,.009,.018),1,.003)
    m.box('TriggerGuardFront',(x+.077,y-.031,0),(.01,.102,.018),0,.003)
    m.box('TriggerGuardRear',(x-.021,y-.031,0),(.01,.102,.018),0,.003)
    m.profile('Trigger',[(x+.025,y-.065),(x+.034,y-.059),(x+.015,y+.026),(x+.006,y+.026)],0,.012,2)

def magazine_ribs(m,polygon,depth,count,ys):
    # Follow the magazine outline at each height; all strips stay inside its cap.
    def bounds(y):
        intersections=[]
        for a,b in zip(polygon,polygon[1:]+polygon[:1]):
            if min(a[1],b[1])<=y<=max(a[1],b[1]) and abs(b[1]-a[1])>1e-9:
                intersections.append(a[0]+(y-a[1])*(b[0]-a[0])/(b[1]-a[1]))
        return min(intersections),max(intersections)
    for side in [-1,1]:
        for i in range(count):
            fraction=(i+1)/(count+1)
            for j in range(len(ys)-1):
                pts=[]
                for y in ys[j:j+2]:
                    left,right=bounds(y);x=left+(right-left)*fraction
                    half=.0025
                    assert left+.003<x-half and x+half<right-.003
                    pts.append((x-half,x+half,y))
                a,b=pts
                m.profile('MagazineRib_%s_%02d_%02d'%(side,i,j),[(a[0],a[2]),(a[1],a[2]),(b[1],b[2]),(b[0],b[2])],side*depth/2,.003,0)

def rail(m,start,end,y,z=0):
    m.box('OpticsRailBase',((start+end)/2,y,z),(end-start,.018,.045),0,.004)
    count=max(2,round((end-start)/.022))
    for i in range(count):m.box('RailTooth_%02d'%i,(start+.011+i*(end-start)/count,y+.013,z),(.013,.012,.05),1,.002)

def sniper():
    m=Model('Sniper')
    m.box('Receiver',(.055,.09,0),(.31,.09,.075),0,.012)
    m.profile('Stock', [(-.59,-.028),(-.34,-.025),(-.17,.025),(-.03,.04),(-.07,.105),(-.27,.123),(-.57,.102)],0,.074,4)
    m.box('ButtPad',(-.59,.025,0),(.025,.16,.085),2,.01)
    m.box('CheekRest',(-.38,.129,0),(.23,.035,.067),3,.012)
    m.box('Handguard',(.225,.039,0),(.34,.075,.084),4,.013)
    for i in range(5):m.box('ForegripRib_%02d'%i,(.1+i*.055,.039,.043),(.013,.055,.006),2,.003)
    m.cylinder('Barrel',(.49,.09,0),.64,.018,0,segments=12,inner=.008)
    m.cylinder('MuzzleBrake',(.833,.09,0),.085,.03,1,segments=10,inner=.012)
    m.cylinder('MuzzleInterior',(.812,.09,0),.006,.011,2,segments=10)
    for x in [.807,.827,.847]:m.box('BrakePort',(x,.092,.03),(.01,.018,.004),2)
    rail(m,-.085,.18,.153)
    for x in [-.055,.15]:m.box('ScopeMount',(x,.183,0),(.04,.055,.05),1,.005)
    m.cylinder('ScopeTube',(.04,.225,0),.36,.028,0,segments=12)
    m.cylinder('Objective',(.23,.225,0),.083,.052,0,segments=12,inner=.039)
    m.cylinder('ScopeLens',(.26,.225,0),.004,.039,2,segments=12)
    m.cylinder('Eyepiece',(-.16,.225,0),.065,.036,2,segments=12)
    m.cylinder('ScopeTurret',(.042,.271,0),.035,.021,1,axis='y',segments=8)
    m.between('BoltHandle',(-.02,.105,.04),(-.05,.054,.09),.009,1,8)
    m.cylinder('BoltKnob',(-.05,.05,.094),.025,.016,2,axis='z',segments=8)
    m.box('Magazine',(.023,-.01,0),(.11,.093,.055),2,.009)
    grip(m,-.16,.015,material=3);guard(m,-.085,.027)
    m.marker('Grip_L',(.22,.02,0));m.marker('Muzzle',(.88,.09,0));m.marker('WeaponSocket_R',(-.16,-.01,0))
    return m

def ak():
    m=Model('AK')
    m.box('Receiver',(.01,.074,0),(.32,.09,.073),0,.009)
    m.box('TopCover',(.015,.127,0),(.27,.026,.062),1,.009)
    m.profile('WoodStock',[(-.48,-.037),(-.23,-.04),(-.13,.014),(-.12,.082),(-.39,.098),(-.48,.078)],0,.071,5)
    m.box('ButtPlate',(-.482,.024,0),(.015,.125,.081),1,.006)
    m.box('WoodLowerHandguard',(.217,.049,0),(.22,.062,.072),5,.012)
    m.box('WoodUpperHandguard',(.21,.106,0),(.20,.04,.064),5,.01)
    m.cylinder('Barrel',(.397,.086,0),.40,.014,0,segments=10,inner=.006)
    m.cylinder('GasTube',(.35,.134,0),.21,.014,1,segments=8)
    m.box('GasBlock',(.434,.112,0),(.027,.07,.041),0,.003)
    m.box('FrontSightBase',(.55,.116,0),(.018,.055,.03),1,.004)
    m.cylinder('FrontSightRing',(.55,.153,0),.012,.017,0,segments=8,inner=.011)
    m.cylinder('MuzzleDevice',(.61,.086,0),.053,.018,1,segments=10,inner=.008)
    m.cylinder('MuzzleInterior',(.594,.086,0),.003,.007,2,segments=8)
    polygon=[(.004,.044),(.087,.044),(.122,-.13),(.157,-.235),(.105,-.264),(.062,-.183),(.028,-.109)]
    m.profile('CurvedMagazine',polygon,0,.049,0)
    magazine_ribs(m,polygon,.049,4,[-.06,-.11,-.17,-.217])
    grip(m,-.117,.008,material=3);guard(m,-.053,.025)
    m.box('RearSight',(.068,.153,0),(.057,.023,.04),1,.003)
    m.box('ChargingHandle',(.075,.104,.057),(.07,.012,.038),1,.003)
    m.box('Selector',(-.032,.057,.043),(.087,.014,.007),1,.004)
    for x in [-.08,.012,.09]:m.cylinder('ReceiverPin',(x,.065,.039),.006,.005,1,axis='z',segments=8)
    m.marker('Grip_L',(.23,.034,0));m.marker('Muzzle',(.637,.086,0));m.marker('WeaponSocket_R',(-.117,-.017,0))
    return m

def m4():
    m=Model('M4')
    m.box('LowerReceiver',(-.035,.054,0),(.22,.069,.064),0,.008)
    m.box('UpperReceiver',(-.017,.112,0),(.265,.052,.071),0,.009)
    m.cylinder('BufferTube',(-.257,.094,0),.23,.025,1,segments=10)
    m.profile('AdjustableStock',[(-.43,-.022),(-.37,-.025),(-.235,.056),(-.18,.063),(-.18,.11),(-.43,.114)],0,.078,3)
    m.box('StockButtPad',(-.434,.036,0),(.018,.16,.084),2,.007)
    m.box('StockCheek',(-.32,.115,0),(.20,.024,.071),3,.007)
    m.box('Handguard',(.239,.094,0),(.31,.089,.077),3,.014)
    for i in range(8):
        x=.115+i*.035
        for z in [-.041,.041]:m.box('HandguardSlot_%02d'%i,(x,.097,z),(.024,.018,.004),2,.005)
    rail(m,-.13,.392,.153)
    m.cylinder('Barrel',(.475,.105,0),.19,.014,0,segments=10,inner=.006)
    m.cylinder('FlashHider',(.577,.105,0),.052,.019,1,segments=10,inner=.008)
    m.cylinder('MuzzleInterior',(.567,.105,0),.003,.007,2,segments=8)
    m.box('FrontSight',(.371,.196,0),(.025,.055,.025),1,.003)
    m.box('RearSight',(-.114,.19,0),(.039,.038,.031),1,.003)
    polygon=[(.006,.035),(.072,.035),(.107,-.184),(.043,-.19)]
    m.profile('Magazine',polygon,0,.047,2)
    magazine_ribs(m,polygon,.047,3,[-.014,-.164])
    grip(m,-.11,.011,material=3);guard(m,-.052,.029)
    m.box('VerticalForegrip',(.242,-.012,0),(.042,.15,.05),2,.009)
    m.box('EjectionPort',(-.01,.113,.038),(.072,.027,.006),2,.004)
    m.box('ForwardAssist',(-.094,.099,.052),(.028,.022,.027),1,.004)
    m.box('ChargingLatch',(-.144,.147,0),(.034,.014,.09),1,.004)
    m.marker('Grip_L',(.242,-.016,0));m.marker('Muzzle',(.608,.105,0));m.marker('WeaponSocket_R',(-.11,-.016,0))
    return m

def minigun():
    m=Model('AviationMinigun')
    m.cylinder('MainHousing',(-.18,.103,0),.33,.137,0,segments=12)
    m.cylinder('RearHousing',(-.37,.103,0),.076,.113,1,segments=12)
    m.cylinder('Rotor',(.012,.103,0),.12,.114,1,segments=12)
    for i in range(6):
        angle=i*math.pi/3;y=.103+.07*math.cos(angle);z=.07*math.sin(angle)
        m.cylinder('Barrel_%02d'%i,(.426,y,z),.75,.019,0,segments=8,inner=.009)
        m.cylinder('MuzzleRim_%02d'%i,(.813,y,z),.027,.024,1,segments=8,inner=.012)
        m.cylinder('Bore_%02d'%i,(.802,y,z),.003,.011,2,segments=8)
    for x in [.12,.43,.748]:m.cylinder('BarrelClamp', (x,.103,0),.026,.11,1,segments=12,inner=.085)
    m.cylinder('Motor',(-.145,-.069,.075),.28,.056,1,segments=10)
    m.box('MotorMount',(-.13,.013,.052),(.22,.03,.079),0,.005)
    m.box('CarryHandleTop',(-.152,.298,0),(.26,.04,.059),2,.012)
    for x in [-.262,-.042]:m.box('CarryHandlePost',(x,.22,0),(.027,.13,.04),1,.004)
    m.box('FeedHousing',(-.215,.102,.17),(.22,.13,.08),4,.013)
    m.cylinder('FeedSocket',(-.2,.103,.235),.05,.038,2,axis='z',segments=10,inner=.025)
    for x in [-.27,-.22,-.17]:m.box('CoolingSlot',(x,.15,.129),(.022,.045,.007),2,.005)
    grip(m,-.303,.016,material=3);guard(m,-.25,.029)
    m.box('FrontSupportGrip',(-.01,.028,-.153),(.07,.09,.16),2,.01)
    m.marker('Grip_L',(-.01,.034,-.19));m.marker('Muzzle',(.837,.103,0));m.marker('FeedPort',(-.2,.103,.265));m.marker('WeaponSocket_R',(-.303,-.008,0))
    return m

def backpack():
    m=Model('MinigunAmmoBackpack');m.doc['nodes'][0]['name']='BackpackRoot'
    m.box('FabricShell',(0,.05,0),(.37,.55,.225),6,.045)
    m.box('AmmoBox',(0,.08,.046),(.302,.38,.17),4,.027)
    m.box('Lid',(0,.286,.02),(.353,.048,.223),4,.017)
    m.box('LowerPouch',(0,-.183,.128),(.29,.107,.07),6,.016)
    m.box('BackPadding',(0,.055,-.128),(.29,.435,.034),2,.027)
    for x in [-.12,.12]:
        m.box('ShoulderStrap',(x,.04,-.154),(.05,.47,.025),6,.018)
        m.box('StrapBuckle',(x,-.12,-.173),(.062,.043,.018),1,.007)
    m.box('TopHandle',(0,.328,0),(.19,.025,.035),2,.007)
    for x in [-.083,.083]:m.box('TopHandlePost',(x,.312,0),(.022,.029,.024),2,.003)
    for x in [-.138,.138]:m.box('VerticalWebbing',(x,.065,.147),(.023,.46,.012),2,.003)
    for x in [-.07,.07]:m.box('LidLatch',(x,.223,.153),(.025,.066,.015),1,.003)
    m.box('FeedMechanism',(.208,.112,.03),(.07,.127,.13),0,.01)
    m.cylinder('FeedCoupling',(.265,.112,.03),.07,.042,1,segments=10,inner=.028)
    for i in range(6):m.cylinder('VisibleCartridge_%02d'%i,(-.09+i*.034,.072,.154),.076,.01,7,axis='y',segments=6)
    m.marker('BackSocket',(0,.055,-.145));m.marker('FeedPort',(.305,.112,.03))
    return m

def create_models(folder):
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    models={'sniper_rifle_lowpoly.glb':sniper(),'ak_rifle_lowpoly.glb':ak(),'m4_rifle_lowpoly.glb':m4(),'aviation_minigun_lowpoly.glb':minigun(),'minigun_ammo_backpack_lowpoly.glb':backpack()}
    for name,m in models.items():m.save(folder/name);print(name,m.triangles,'triangles',flush=True)
    return models
