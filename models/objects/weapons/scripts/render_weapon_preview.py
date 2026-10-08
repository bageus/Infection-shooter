"""CPU orthographic raster previews of real GLB geometry and albedo maps."""
import argparse,math
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from build_architecture_pack import load_glb,accessor,mesh_reference_matrices,normalize

def render(path,width=720,height=390,side=False):
    doc,binary=load_glb(path);refs=mesh_reference_matrices(doc);pieces=[];textures={}
    for i,mesh in enumerate(doc['meshes']):
        transform=refs[i]
        for part in mesh['primitives']:
            positions=accessor(doc,binary,part['attributes']['POSITION'])
            indices=accessor(doc,binary,part['indices']) if 'indices' in part else np.arange(len(positions))
            points=positions[indices]@transform[:3,:3].T+transform[:3,3]
            material=doc['materials'][part['material']];pbr=material.get('pbrMetallicRoughness',{})
            uv=accessor(doc,binary,part['attributes']['TEXCOORD_0'])[indices] if 'TEXCOORD_0' in part['attributes'] else None
            texture=None
            if 'baseColorTexture' in pbr:
                tid=pbr['baseColorTexture']['index'];iid=doc['textures'][tid]['source']
                uri=doc['images'][iid].get('uri')
                if uri:
                    if iid not in textures:textures[iid]=np.asarray(Image.open(path.parent/uri).convert('RGB'),dtype=float)/255
                    texture=textures[iid]
            color=np.asarray(pbr.get('baseColorFactor',[1,1,1,1])[:3],float)
            pieces.append((points,uv,texture,color))
    points=np.concatenate([p[0] for p in pieces]);rotate=np.eye(3)
    if np.ptp(points,axis=0)[2]>np.ptp(points,axis=0)[0] and 'backpack' not in path.name:
        rotate=np.array([[0,0,-1],[0,1,0],[1,0,0]])
    points=points@rotate.T
    view=normalize(np.array([.75,.48,2.8] if not side else [0,.08,3.]))
    right=normalize(np.cross([0,1,0],view));up=normalize(np.cross(view,right))
    camera=np.stack([right,up,view]);projected=points@camera.T
    center=(projected.min(0)+projected.max(0))/2;span=np.ptp(projected,axis=0)
    scale=min((width-80)/max(span[0],.01),(height-60)/max(span[1],.01))
    background=np.zeros((height,width,3),float);background[:]=[.105,.122,.15]
    buffer=np.full((height,width),-np.inf);light=normalize(np.array([-.3,.7,1.]))
    for positions,uv,texture,color in pieces:
        positions=positions@rotate.T;coordinates=positions@camera.T
        screen=np.c_[(coordinates[:,0]-center[0])*scale+width/2,height/2-(coordinates[:,1]-center[1])*scale,coordinates[:,2]]
        for ti,tri in enumerate(screen.reshape(-1,3,3)):
            x0=max(0,int(np.floor(tri[:,0].min())));x1=min(width-1,int(np.ceil(tri[:,0].max())))
            y0=max(0,int(np.floor(tri[:,1].min())));y1=min(height-1,int(np.ceil(tri[:,1].max())))
            if x1<x0 or y1<y0:continue
            a,b,c=tri;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
            if abs(den)<1e-8:continue
            xx,yy=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5)
            wa=((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den
            wb=((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den;wc=1-wa-wb
            depth=wa*a[2]+wb*b[2]+wc*c[2]
            mask=(wa>=-1e-6)&(wb>=-1e-6)&(wc>=-1e-6)&(depth>buffer[y0:y1+1,x0:x1+1])
            if not mask.any():continue
            vertices=positions[ti*3:ti*3+3];normal=normalize(np.cross(vertices[1]-vertices[0],vertices[2]-vertices[0]))
            shading=.52+.48*max(0,float(normal@light))
            if texture is not None and uv is not None:
                tuv=uv[ti*3:ti*3+3]
                sample=wa[...,None]*tuv[0]+wb[...,None]*tuv[1]+wc[...,None]*tuv[2]
                tx=np.clip((sample[:,:,0]*texture.shape[1]).astype(int),0,texture.shape[1]-1)
                ty=np.clip((sample[:,:,1]*texture.shape[0]).astype(int),0,texture.shape[0]-1)
                rgb=np.power(texture[ty,tx],2.2)*color*shading
            else:rgb=np.broadcast_to(color*shading,(*mask.shape,3))
            # Neutral albedo preview; no PBR reflections, normal or roughness shading.
            background[y0:y1+1,x0:x1+1][mask]=np.clip(np.power(rgb[mask],1/2.2)*1.2,0,1)
            buffer[y0:y1+1,x0:x1+1][mask]=depth[mask]
    return Image.fromarray(np.rint(background*255).astype('uint8'))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--models',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    names=['sniper_rifle_lowpoly.glb','ak_rifle_lowpoly.glb','m4_rifle_lowpoly.glb','aviation_minigun_lowpoly.glb','minigun_ammo_backpack_lowpoly.glb','pistol_lowpoly(2).glb','shotgun_lowpoly.glb','uzi_lowpoly.glb','six_chamber_launcher_lowpoly.glb']
    names=[n for n in names if (args.models/n).exists()]
    canvas=Image.new('RGB',(1440,math.ceil(len(names)/2)*430),(21,25,31));draw=ImageDraw.Draw(canvas)
    try:font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',21)
    except OSError:font=ImageFont.load_default()
    for i,name in enumerate(names):
        image=render(args.models/name);image.save(args.output/(Path(name).stem+'.png'))
        x=(i%2)*720;y=(i//2)*430;canvas.paste(image,(x,y+40));draw.text((x+22,y+10),name.replace('_lowpoly','').replace('_',' ').replace('.glb',''),font=font,fill=(230,235,241))
    canvas.save(args.output/'weapons_overview.png')

if __name__=='__main__':main()
