#!/usr/bin/env python3
"""Rebuild group 03 from pinned Git sources; bake factors, clip repeat UVs and split lazy stages.
Requires the offline Python tooling numpy and Pillow; no runtime dependency is added.
"""
import argparse, collections, copy, hashlib, io, json, math, struct, subprocess
from pathlib import Path
import numpy as np
from PIL import Image
from check_group01_atlas import read_glb, accessor
from deduplicate_model_textures import encode_glb

ROOT = Path(__file__).resolve().parents[1]
GROUP = ROOT / 'models/objects/enviroments/03'
SOURCE_REF = 'a48e5a49028b0871852f4418eeb8eb2670671ea2'
TEXTURE_REF = '8d2452437ea8a6465b44bbb2cedcd402df302ce5'
METAL_REF = 'f49af602b5bb533bdf18e9d12e74a30b2706a9c4^'
SIZE, CELL, GUTTER = 2048, 512, 16
KINDS = ['albedo', 'normal', 'orm', 'emission']


def git_bytes(ref, path):
    return subprocess.check_output(['git', 'show', ref + ':' + path], cwd=ROOT)


def source_image(path, uri):
    relative = (path.parent / uri).resolve().relative_to(ROOT).as_posix()
    ref = METAL_REF if '/05/' in relative else TEXTURE_REF
    data = git_bytes(ref, relative)
    return Image.open(io.BytesIO(data)).convert('RGB'), {'path': relative, 'ref': ref, 'sha256': hashlib.sha256(data).hexdigest()}


def tile_key(material):
    return material['name'].replace('INDICATORS_OFF', 'INDICATORS_ON')


def bake_material(path, doc, mat):
    pbr = mat.get('pbrMetallicRoughness', {})
    sources = []
    def sample(slot, default):
        if slot is None: return np.full((CELL-2*GUTTER, CELL-2*GUTTER, 3), default, dtype=float)
        image = doc['images'][doc['textures'][slot['index']]['source']]
        im, receipt = source_image(path, image['uri']); sources.append(receipt)
        return np.asarray(im.resize((CELL-2*GUTTER, CELL-2*GUTTER), Image.Resampling.LANCZOS), dtype=float)/255
    albedo = sample(pbr.get('baseColorTexture'), [1,1,1])
    linear = np.where(albedo<=.04045,albedo/12.92,((albedo+.055)/1.055)**2.4)
    linear *= pbr.get('baseColorFactor', [1,1,1,1])[:3]
    albedo = np.where(linear<=.0031308,linear*12.92,1.055*np.maximum(linear,0)**(1/2.4)-.055)
    orm = sample(pbr.get('metallicRoughnessTexture'), [1,1,1])
    orm[:,:,1] *= pbr.get('roughnessFactor',1); orm[:,:,2] *= pbr.get('metallicFactor',1)
    if 'occlusionTexture' in mat: orm[:,:,0] = sample(mat['occlusionTexture'],[1,1,1])[:,:,0]
    normal = sample(mat.get('normalTexture'), [.5,.5,1])*2-1
    normal[:,:,:2] *= mat.get('normalTexture',{}).get('scale',1)
    normal /= np.maximum(np.linalg.norm(normal,axis=2,keepdims=True),1e-10)
    normal = normal*.5+.5
    emission = sample(mat.get('emissiveTexture'), [1,1,1])
    # glTF emissive textures are sRGB; store the scaled linear result as sRGB.
    emission = np.where(emission<=.04045,emission/12.92,((emission+.055)/1.055)**2.4)
    emission *= np.array(mat.get('emissiveFactor',[0,0,0])) * mat.get('extensions',{}).get('KHR_materials_emissive_strength',{}).get('emissiveStrength',1)/2.5
    emission = np.where(emission<=.0031308,emission*12.92,1.055*np.maximum(emission,0)**(1/2.4)-.055)
    return [Image.fromarray(np.uint8(np.clip(v,0,1)*255+.5)) for v in [albedo,normal,orm,emission]], sources


def build_atlas(documents):
    candidates = {}
    for path,doc,_ in documents:
        for mat in doc['materials']:
            if mat.get('alphaMode') == 'BLEND' or 'INDICATORS_OFF' in mat['name']: continue
            candidates.setdefault(tile_key(mat),(path,doc,mat))
    assert len(candidates)==16
    atlases=[Image.new('RGB',(SIZE,SIZE),v) for v in [(0,0,0),(128,128,255),(255,255,0),(0,0,0)]]
    tiles=[]; mapping={}
    for i,(key,(path,doc,mat)) in enumerate(sorted(candidates.items())):
        images,sources=bake_material(path,doc,mat); x,y=(i%4)*CELL,(i//4)*CELL
        for atlas,image in zip(atlases,images):
            a=np.array(image); padded=np.pad(a,((GUTTER,GUTTER),(GUTTER,GUTTER),(0,0)),mode='edge');atlas.paste(Image.fromarray(padded),(x,y))
        rect=[(x+GUTTER)/SIZE,(y+GUTTER)/SIZE,(CELL-2*GUTTER)/SIZE,(CELL-2*GUTTER)/SIZE]
        mapping[key]=rect;tiles.append({'id':key,'uv_rect':rect,'sources':sources})
    out=GROUP/'textures/unified';out.mkdir(parents=True,exist_ok=True)
    for kind,im in zip(KINDS,atlases): im.save(out/f'group03_{kind}.png',optimize=True)
    return mapping,tiles


def transform(node):
    if 'matrix' in node: return np.array(node['matrix']).reshape(4,4).T
    x,y,z,w=node.get('rotation',[0,0,0,1]);m=np.eye(4)
    m[:3,:3]=np.array([[1-2*y*y-2*z*z,2*x*y-2*z*w,2*x*z+2*y*w],[2*x*y+2*z*w,1-2*x*x-2*z*z,2*y*z-2*x*w],[2*x*z-2*y*w,2*y*z+2*x*w,1-2*x*x-2*y*y]])@np.diag(node.get('scale',[1,1,1]))
    m[:3,3]=node.get('translation',[0,0,0]);return m


def collect(doc, roots, parent=None):
    result=[];parent=np.eye(4) if parent is None else parent
    for index in roots:
        node=doc['nodes'][index];matrix=parent@transform(node)
        if 'mesh' in node: result.append((node,matrix))
        result.extend(collect(doc,node.get('children',[]),matrix))
    return result


def clip(poly,axis,edge,above):
    out=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        av,bv=a[6+axis],b[6+axis];ai=av>=edge if above else av<=edge;bi=bv>=edge if above else bv<=edge
        if ai:out.append(a)
        if ai!=bi:out.append(a+(b-a)*((edge-av)/(bv-av)))
    return out


def repeat_tri(tri,rect):
    # A single atlas tile may repeat in authored UV; split at each integer seam.
    uv=tri[:,6:8];lo=np.floor(uv.min(axis=0)).astype(int);hi=np.ceil(uv.max(axis=0)).astype(int)
    hi=np.maximum(hi,lo+1)
    for u in range(lo[0],hi[0]):
        for v in range(lo[1],hi[1]):
            poly=list(tri)
            for axis,edge,above in [(0,u,True),(0,u+1,False),(1,v,True),(1,v+1,False)]:
                if not poly:break
                poly=clip(poly,axis,edge,above)
            for i in range(1,len(poly)-1):
                t=np.array([poly[0],poly[i],poly[i+1]],copy=True)
                if np.linalg.norm(np.cross(t[1,:3]-t[0,:3],t[2,:3]-t[0,:3]))<1e-12:continue
                t[:,6:8]=np.clip(t[:,6:8]-[u,v],0,1)*rect[2:]+rect[:2]
                yield t


def material_class(mat):
    if mat.get('alphaMode')=='BLEND':return 2
    if any(mat.get('emissiveFactor',[0,0,0])):return 1
    return 0 if mat.get('doubleSided',False) else 3


def geometry(doc,binary,entries,mapping):
    groups=collections.defaultdict(list)
    for node,matrix in entries:
        normal_matrix=np.linalg.inv(matrix[:3,:3]).T
        for p in doc['meshes'][node['mesh']]['primitives']:
            assert p.get('mode',4)==4
            attrs=p['attributes'];pos=np.array(accessor(doc,binary,attrs['POSITION']));ns=np.array(accessor(doc,binary,attrs['NORMAL']));uv=np.array(accessor(doc,binary,attrs['TEXCOORD_0']))
            pos=pos@matrix[:3,:3].T+matrix[:3,3];ns=ns@normal_matrix.T;ns/=np.maximum(np.linalg.norm(ns,axis=1,keepdims=True),1e-10)
            # Bake any authored vertex-color modulation before combining surfaces.
            colors=np.array(accessor(doc,binary,attrs['COLOR_0'])) if 'COLOR_0'in attrs else np.ones((len(pos),4))
            if colors.shape[1]==3:colors=np.column_stack([colors,np.ones(len(pos))])
            verts=np.column_stack([pos,ns,uv,colors]);ids=[x[0] for x in accessor(doc,binary,p['indices'])] if 'indices'in p else range(len(pos))
            mat=doc['materials'][p['material']];kind=material_class(mat)
            for i in range(0,len(ids),3):
                tri=verts[list(ids[i:i+3])]
                if np.linalg.det(matrix[:3,:3])<0:tri=tri[[0,2,1]]
                if kind==2:groups[kind].append(tri)
                else:groups[kind].extend(repeat_tri(tri,mapping[tile_key(mat)]))
    return {k:np.concatenate(v) for k,v in groups.items() if v}


def tangents(vertices):
    triangles=vertices.reshape(-1,3,12);p=triangles[:,:,:3];uv=triangles[:,:,6:8]
    e1,e2=p[:,1]-p[:,0],p[:,2]-p[:,0];a,b=uv[:,1]-uv[:,0],uv[:,2]-uv[:,0]
    det=a[:,0]*b[:,1]-a[:,1]*b[:,0];den=np.where(np.abs(det)<1e-12,1,det)
    ts=(e1*b[:,1,None]-e2*a[:,1,None])/den[:,None];bs=(-e1*b[:,0,None]+e2*a[:,0,None])/den[:,None]
    n=vertices[:,3:6];t=np.repeat(ts,3,axis=0);t-=n*np.sum(n*t,axis=1,keepdims=True)
    deg=np.linalg.norm(t,axis=1)<1e-8
    if deg.any():
        axis=np.zeros_like(n);axis[:,0]=1;axis[np.abs(n[:,0])>.9]=[0,1,0];t[deg]=np.cross(axis,n)[deg]
    t/=np.maximum(np.linalg.norm(t,axis=1,keepdims=True),1e-10)
    hand=np.where(np.sum(np.cross(n,t)*np.repeat(bs,3,axis=0),axis=1)<0,-1,1)
    return np.column_stack([t,hand])


class Writer:
    def __init__(self):self.binary=bytearray();self.accessors=[];self.views=[];self.meshes=[]
    def add(self,values,kind):
        values=np.asarray(values,dtype=np.float32);self.binary.extend(b'\0'*(-len(self.binary)%4));offset=len(self.binary);payload=values.tobytes();self.binary.extend(payload)
        view=len(self.views);self.views.append({'buffer':0,'byteOffset':offset,'byteLength':len(payload),'target':34962})
        index=len(self.accessors);self.accessors.append({'bufferView':view,'componentType':5126,'count':len(values),'type':kind,'min':values.min(axis=0).tolist(),'max':values.max(axis=0).tolist()});return index
    def mesh(self,name,groups):
        ps=[]
        for mat,v in sorted(groups.items()):
            # Weld identical vertices including tile seams/normals; retain flat shading.
            allv=np.column_stack([v,tangents(v)]).astype(np.float32);unique,ids=np.unique(allv,axis=0,return_inverse=True)
            attrs={k:self.add(unique[:,a:b],kind) for k,a,b,kind in [('POSITION',0,3,'VEC3'),('NORMAL',3,6,'VEC3'),('TEXCOORD_0',6,8,'VEC2'),('TANGENT',12,16,'VEC4')]}
            if not np.all(unique[:,8:12]==1):attrs['COLOR_0']=self.add(unique[:,8:12],'VEC4')
            component=5123 if len(unique)<65536 else 5125;ids=ids.astype(np.uint16 if component==5123 else np.uint32);self.binary.extend(b'\0'*(-len(self.binary)%4));offset=len(self.binary);self.binary.extend(ids.tobytes());view=len(self.views);self.views.append({'buffer':0,'byteOffset':offset,'byteLength':ids.nbytes,'target':34963});index=len(self.accessors);self.accessors.append({'bufferView':view,'componentType':component,'count':len(ids),'type':'SCALAR'})
            ps.append({'attributes':attrs,'indices':index,'material':mat})
        index=len(self.meshes);self.meshes.append({'name':name,'primitives':ps});return index
    def save(self,path,nodes,scenes):
        mats=[]
        for name in ['Group03Opaque','Group03Emission','Group03Glass','Group03OpaqueSingleSided']:
            mat={'name':name,'doubleSided':name!='Group03OpaqueSingleSided','pbrMetallicRoughness':{'baseColorTexture':{'index':0},'metallicRoughnessTexture':{'index':2},'metallicFactor':1,'roughnessFactor':1},'normalTexture':{'index':1},'occlusionTexture':{'index':2}}
            if name=='Group03Emission':mat.update(emissiveTexture={'index':3},emissiveFactor=[1,1,1],extensions={'KHR_materials_emissive_strength':{'emissiveStrength':2.5}})
            if name=='Group03Glass':mat={'name':name,'doubleSided':True,'alphaMode':'BLEND','pbrMetallicRoughness':{'baseColorFactor':[.04323364,.06838485,.09462963,.35],'metallicFactor':0,'roughnessFactor':.2}}
            mats.append(mat)
        prefix='../' if path.parent.name=='damage' else ''
        doc={'asset':{'version':'2.0','generator':'Infection Shooter group03 atlas pipeline'},'scene':0,'scenes':scenes,'nodes':nodes,'meshes':self.meshes,'accessors':self.accessors,'bufferViews':self.views,'buffers':[{'byteLength':len(self.binary)}],'materials':mats,'images':[{'uri':prefix+f'textures/unified/group03_{k}.png'} for k in KINDS],'textures':[{'source':i,'sampler':0} for i in range(4)],'samplers':[{'magFilter':9729,'minFilter':9987,'wrapS':33071,'wrapT':33071}],'extensionsUsed':['KHR_materials_emissive_strength']}
        # Remove unused materials and images for strict audits and cheaper imports.
        used=sorted({p['material'] for m in self.meshes for p in m['primitives']});remap={old:i for i,old in enumerate(used)}
        doc['materials']=[mats[i] for i in used]
        for mesh in self.meshes:
            for p in mesh['primitives']:p['material']=remap[p['material']]
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(encode_glb(doc,bytes(self.binary)))


def stages(doc):
    if len(doc['scenes'])>1:return [(s['name'],s['nodes'],np.eye(4)) for s in doc['scenes'] if s.get('nodes')]
    result=[]
    def visit(index,parent):
        node=doc['nodes'][index];name=node.get('name','');matrix=parent@transform(node)
        if name in ['Intact','Dent_01','Dent_02','Dent_03','Modular','Primary','Medium','Fine']:
            # Stage zero scale is visibility convention, not authored geometry.
            matrix=parent@transform(dict(node,scale=[1,1,1]))
            result.append((name,node.get('children',[]),matrix));return
        for child in node.get('children',[]):visit(child,matrix)
    for i in doc['scenes'][doc.get('scene',0)]['nodes']:visit(i,np.eye(4))
    return result


def chunks(entries,stage):
    if stage in ['Intact','Dent_01','Dent_02','Dent_03']:return [('Group03IntactGeometry' if stage=='Intact' else stage+'Geometry',entries)]
    if stage=='SmallFragments':
        families=collections.defaultdict(list)
        for entry in entries:families[entry[0].get('extras',{}).get('source_part') or entry[0]['name'].split('_Fragment_')[0]].append(entry)
        result=[]
        for family,parts in families.items():
            # Adjacent pairs retain panel identity; at most two fragments per family.
            axis=int(np.argmax(np.ptp(np.array([matrix[:3,3] for _,matrix in parts]),axis=0)))
            parts.sort(key=lambda entry:entry[1][axis,3]);half=(len(parts)+1)//2
            for i,part in enumerate([parts[:half],parts[half:]],1):
                if part:result.append((family+'_Fragment_'+str(i),part))
        return result
    return [(node['name'],[(node,matrix)]) for node,matrix in entries]


def build_model(path,doc,binary,mapping):
    manifest=[];statistics=[]
    all_stages=stages(doc)
    for stage,roots,parent in all_stages:
        entries=collect(doc,roots,parent);writer=Writer();nodes=[]
        for name,part in chunks(entries,stage):
            groups=geometry(doc,binary,part,mapping)
            # Separate glass so collisions and shattering never hide the metal frame.
            if 2 in groups and len(groups)>1:
                opaque={k:v for k,v in groups.items() if k!=2};mesh=writer.mesh(name,opaque);nodes.append({'name':name,'mesh':mesh});nodes.append({'name':name+'_Glass','mesh':writer.mesh(name+'_Glass',{2:groups[2]})})
            else:nodes.append({'name':name,'mesh':writer.mesh(name,groups)})
        mesh_nodes=list(range(len(nodes)));nodes.append({'name':stage,'children':mesh_nodes});root_index=len(nodes)-1
        target=path if stage=='Intact' else GROUP/'damage'/f'{path.stem}_{stage.lower()}.glb'
        writer.save(target,nodes,[{'name':path.stem,'nodes':[root_index]}])
        if stage!='Intact':manifest.append({'name':stage,'path':'res://'+target.relative_to(ROOT).as_posix()})
        statistics.append({'stage':stage,'source_mesh_nodes':len(entries),'mesh_nodes':len(mesh_nodes),'surfaces':sum(len(m['primitives']) for m in writer.meshes),'bytes':target.stat().st_size})
    return manifest,statistics


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--apply',action='store_true',required=True);parser.parse_args()
    paths=sorted(GROUP.glob('*.glb'));docs=[(p,*read_glb(git_bytes(SOURCE_REF,p.relative_to(ROOT).as_posix()))) for p in paths]
    mapping,tiles=build_atlas(docs);manifest={};stats={}
    for path,doc,binary in docs:
        manifest[path.name],stats[path.name]=build_model(path,doc,binary,mapping);print(path.name,stats[path.name],flush=True)
    (GROUP/'lazy_stages.json').write_text(json.dumps(manifest,indent=2)+'\n')
    layout={'source_ref':SOURCE_REF,'texture_ref':TEXTURE_REF,'metal_ref':METAL_REF,'size':SIZE,'gutter':GUTTER,'tiles':tiles,'models':stats}
    (GROUP/'atlas_layout.json').write_text(json.dumps(layout,indent=2)+'\n')

if __name__=='__main__':main()
