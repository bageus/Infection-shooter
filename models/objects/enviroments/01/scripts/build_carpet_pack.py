"""Shared repeating carpet PBR maps and six GLBs; numpy, Pillow, scipy required."""
from pathlib import Path
import argparse, copy, json, shutil, io
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
from build_architecture_pack import load_glb, accessor, append_accessor, write_glb, mesh_reference_matrices, normalize, tangents

def periodic(image):
    a=np.asarray(image,dtype=float)
    h,w=a.shape[:2]
    boundary=np.zeros_like(a)
    boundary[0]+=a[-1]-a[0]; boundary[-1]+=a[0]-a[-1]
    boundary[:,0]+=a[:,-1]-a[:,0]; boundary[:,-1]+=a[:,0]-a[:,-1]
    denominator=2*np.cos(2*np.pi*np.arange(h)/h)[:,None]+2*np.cos(2*np.pi*np.arange(w)/w)[None,:]-4
    denominator[0,0]=1
    spectrum=np.fft.fft2(boundary,axes=(0,1))/denominator[:,:,None]
    spectrum[0,0]=0
    return np.clip(a-np.fft.ifft2(spectrum,axes=(0,1)).real,0,255)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--inputs',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args(); out=args.output
    for folder in ['textures','textures/1k','models','previews','sources','scripts']:
        (out/folder).mkdir(parents=True,exist_ok=True)
    rgb=periodic(Image.open(args.source).convert('RGB').resize((2048,2048),Image.Resampling.LANCZOS))
    albedo=np.rint(rgb).astype('uint8')
    gray=rgb.mean(2)/255
    height=(gray-gaussian_filter(gray,8,mode='wrap'))*.0006
    dx=(np.roll(height,-1,1)-np.roll(height,1,1))*1024
    dy=(np.roll(height,-1,0)-np.roll(height,1,0))*1024
    n=normalize(np.stack([-dx,-dy,np.ones_like(dx)],axis=2))
    normal=np.rint((n*.5+.5)*255).astype('uint8')
    rough=np.clip(.91+(gray-gaussian_filter(gray,12,mode='wrap'))*.22,.82,.98)
    orm=np.stack([np.full_like(gray,255),rough*255,np.zeros_like(gray)],axis=2).astype('uint8')
    for name,array in [('albedo',albedo),('normal',normal),('orm',orm)]:
        image=Image.fromarray(array)
        encoded=io.BytesIO(); image.save(encoded,format='PNG',compress_level=9)
        destination=out/f'textures/carpet_{name}.png'
        destination.write_bytes(encoded.getvalue())
        Image.open(destination).verify()
        small=image.resize((1024,1024),Image.Resampling.LANCZOS)
        if name=='normal':
            sn=normalize(np.asarray(small,dtype=float)/127.5-1)
            small=Image.fromarray(np.rint((sn*.5+.5)*255).astype('uint8'))
        small.save(out/f'textures/1k/carpet_{name}.png')
    Image.fromarray(albedo).resize((700,700)).save(out/'previews/carpet_closeup.png')
    Image.fromarray(np.tile(albedo,(2,2,1))).resize((1000,1000)).save(out/'previews/carpet_repeat_2x2.png')
    results=[]
    for source in sorted(args.inputs.glob('01_floor*.glb')):
        original,original_bin=load_glb(source)
        doc=copy.deepcopy(original); binary=bytearray(original_bin)
        refs=mesh_reference_matrices(original)
        # All material texture assignments are replaced. Drop stale image entries:
        # some supplied embedded image payloads fail Godot decoding even if unused.
        doc['images']=[]; doc['textures']=[]; doc['samplers']=[]
        sampler=len(doc.setdefault('samplers',[]));doc['samplers'].append({'magFilter':9729,'minFilter':9987,'wrapS':10497,'wrapT':10497})
        texture_ids=[]
        for kind in ['albedo','normal','orm']:
            image_id=len(doc.setdefault('images',[]));doc['images'].append({'uri':f'../textures/carpet_{kind}.png'})
            texture_ids.append(len(doc.setdefault('textures',[])))
            doc['textures'].append({'source':image_id,'sampler':sampler})
        for i,material in enumerate(doc['materials']):
            material.setdefault('extras',{})['original_pbr']=copy.deepcopy(material.get('pbrMetallicRoughness',{}))
            if source.name=='01_floor_pad.glb' and i==0:
                material['pbrMetallicRoughness']={'baseColorFactor':[.025,.027,.03,1],'metallicFactor':0,'roughnessFactor':.96}
                material['extras']['finish']='graphite_rubber_border'
            else:
                material['pbrMetallicRoughness']={'baseColorFactor':[1,1,1,1],'baseColorTexture':{'index':texture_ids[0]},'metallicRoughnessTexture':{'index':texture_ids[2]},'metallicFactor':0,'roughnessFactor':1}
                material['normalTexture']={'index':texture_ids[1],'scale':1}
                material['occlusionTexture']={'index':texture_ids[2],'strength':1}
                material['extras']['finish']='modern_graphite_carpet'
        triangles=0
        for mi,mesh in enumerate(doc['meshes']):
            matrix=refs[mi]
            for pi,primitive in enumerate(mesh['primitives']):
                old=original['meshes'][mi]['primitives'][pi]
                indices=accessor(original,original_bin,old['indices']).astype(int) if 'indices' in old else np.arange(len(accessor(original,original_bin,old['attributes']['POSITION'])))
                assert old.get('mode',4)==4
                triangles+=len(indices)//3
                positions=accessor(original,original_bin,old['attributes']['POSITION'])[indices]
                normals=accessor(original,original_bin,old['attributes']['NORMAL'])[indices]
                world=positions@matrix[:3,:3].T+matrix[:3,3]
                uv=np.c_[world[:,0],-world[:,2]].astype('<f4')
                if source.name=='01_floor_pad.glb':
                    # Horizontal UVs for top; stable planar mapping for border side faces.
                    face=normalize(np.cross(world.reshape(-1,3,3)[:,1]-world.reshape(-1,3,3)[:,0],world.reshape(-1,3,3)[:,2]-world.reshape(-1,3,3)[:,0]))
                    for ti,axis in enumerate(np.abs(face).argmax(1)):
                        if axis!=1: uv[ti*3:ti*3+3]=world[ti*3:ti*3+3][:,[2 if axis==0 else 0,1]]
                newattrs={}
                for name,index in old['attributes'].items():
                    if name in ['TEXCOORD_0','TANGENT']: continue
                    values=accessor(original,original_bin,index)[indices]
                    newattrs[name]=append_accessor(doc,binary,values,original['accessors'][index]['type'])
                newattrs['TEXCOORD_0']=append_accessor(doc,binary,uv,'VEC2')
                newattrs['TANGENT']=append_accessor(doc,binary,tangents(positions,normals,uv),'VEC4')
                primitive['attributes']=newattrs
                primitive.pop('indices',None)
        target=out/'models'/source.name;write_glb(target,doc,binary)
        saved,saved_bin=load_glb(target)
        assert original['nodes']==saved['nodes'] and original['scenes']==saved['scenes']
        for mi,mesh in enumerate(original['meshes']):
            for pi,pr in enumerate(mesh['primitives']):
                new=saved['meshes'][mi]['primitives'][pi]
                ix=accessor(original,original_bin,pr['indices']).astype(int) if 'indices' in pr else slice(None)
                for attr in ['POSITION','NORMAL']:
                    assert np.array_equal(accessor(original,original_bin,pr['attributes'][attr])[ix],accessor(saved,saved_bin,new['attributes'][attr]))
                uv=accessor(saved,saved_bin,new['attributes']['TEXCOORD_0']);t=accessor(saved,saved_bin,new['attributes']['TANGENT'])
                assert np.isfinite(uv).all() and np.isfinite(t).all()
                assert np.allclose(np.linalg.norm(t[:,:3],axis=1),1,atol=1e-5)
                assert pr.get('material')==new.get('material')
        results.append({'file':source.name,'status':'PASS','triangles_preserved':triangles,'nodes_preserved':len(doc['nodes']),'texture_repeat_meters':1})
        print(source.name,'PASS',flush=True)
    npair=np.mean(np.abs(rgb[0]-rgb[-1])); ninner=np.mean(np.abs(rgb[1:]-rgb[:-1]))
    (out/'validation.json').write_text(json.dumps({'models':results,'seam_vertical_mean_rgb_difference':float(npair),'interior_mean_rgb_difference':float(ninner),'source_dimensions':list(Image.open(args.source).size),'output_dimensions':[2048,2048]},indent=2))
    shutil.copy2(args.source,out/'sources/carpet_generated_source.png')
    shutil.copy2(__file__,out/'scripts/build_carpet_pack.py')
    shutil.copy2(Path(__file__).with_name('build_architecture_pack.py'),out/'scripts/build_architecture_pack.py')

if __name__=='__main__': main()
