"""Check native apparel connectivity independently of body and weapon pixels."""
from pathlib import Path
from collections import deque
import hashlib,json
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[4];BASE=Path(__file__).resolve().parent
recipe=json.loads((BASE/'dash_recipe.json').read_text())
source=json.loads((ROOT/'data/swordman_r0.json').read_text())['animations']['dash']['frames']
cases=[]
for frame in range(8):
    for sub in range(3):
        actual=np.asarray(Image.open(BASE/f'apparel/dash_{frame:02}_{sub}.png').convert('RGBA'))
        alpha=actual[...,3]==255;labels=np.full(alpha.shape,-1,dtype=int);components=[]
        for yy,xx in zip(*np.where(alpha)):
            if labels[yy,xx]>=0:continue
            ident=len(components);q=deque([(int(xx),int(yy))]);labels[yy,xx]=ident;points=[]
            while q:
                x,y=q.popleft();points.append((x,y))
                for dx in [-1,0,1]:
                    for dy in [-1,0,1]:
                        nx,ny=x+dx,y+dy
                        if 0<=nx<320 and 0<=ny<224 and alpha[ny,nx] and labels[ny,nx]<0:labels[ny,nx]=ident;q.append((nx,ny))
            p=np.array(points);components.append({'id':ident,'pixels':len(points),'min_y':int(p[:,1].min()),'connected_to_hip':bool((p[:,1]<=recipe['hip_y']+1).any()),'bbox':p.min(axis=0).tolist()+(p.max(axis=0)+1).tolist()})
        connected_ids=[c['id'] for c in components if c['connected_to_hip']]
        legs=[]
        template=frame if sub<2 else (frame+1)%8;phase=sub/3
        for leg in range(2):
            boot=recipe['boots'][template][leg];layer=source[template]['layers'][boot['slot']]
            a=np.asarray(Image.open(ROOT/layer['texture'].removeprefix('res://')).convert('RGBA'));ox,oy=np.array(layer['offset'])+[133,167]
            target=np.array(recipe['boots'][frame][leg]['center'])*(1-phase)+np.array(recipe['boots'][(frame+1)%8][leg]['center'])*phase
            shift=target-np.array(boot['center']);yy,xx=np.mgrid[:224,:320];p=np.stack([xx+.5,yy+.5],axis=-1)-shift
            xy=np.floor(p-[ox,oy]).astype(int);sx,sy=xy[...,0],xy[...,1]
            inside=(sx>=0)&(sy>=0)&(sx<a.shape[1])&(sy<a.shape[0]);cx=np.clip(sx,0,a.shape[1]-1);cy=np.clip(sy,0,a.shape[0]-1)
            l,t,r,b=boot['bbox'];inside&=(p[...,0]>=l)&(p[...,0]<r)&(p[...,1]>=t)&(p[...,1]<b)&(a[cy,cx,3]==255)
            visible=inside&(actual==a[cy,cx]).all(axis=-1)
            disconnected=visible&~np.isin(labels,connected_ids)
            legs.append({'physical_leg':leg,'visible_boot_pixels':int(visible.sum()),'disconnected_boot_pixels':int(disconnected.sum()),'examples':np.argwhere(disconnected)[:8,::-1].tolist()})
        detached=[c for c in components if not c['connected_to_hip'] and c['pixels']>=5]
        cases.append({'frame':frame,'subframe':sub,'legs':legs,'detached_apparel_components':detached,'pass':not detached and all(l['visible_boot_pixels']>60 and l['disconnected_boot_pixels']==0 for l in legs)})
result={'study':'R1/26 native apparel8-neighbour connectivity to hip band','cases':cases,'failed':[c for c in cases if not c['pass']],
        'analysis_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'note':'Source and derived apparel only; body and weapon cannot falsely bridge a disconnected leg. Connected silhouettes still require visual review.'}
(ROOT/'docs/r1_26_apparel_checks.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'cases':len(cases),'failed':result['failed']}))
