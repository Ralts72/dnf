"""Analysis-only semantic leg tracking for the locomotion interpolation study."""
import heapq

import cv2
import numpy as np

FOOT_A_INDEX={'move':[0,1,1,1,1,0,0,0], 'dash':[1,1,1,1,1,0,0,0]}


def distance(points,a,b):
    line=b-a
    t=np.clip(((points-a)*line).sum(axis=-1)/(line@line+1e-6),0,1)
    return np.linalg.norm(points-a-t[...,None]*line,axis=-1)


def center_path(mask,start,end):
    ys,xs=np.nonzero(mask);points=np.stack([xs,ys],axis=-1)
    s=points[np.argmin(((points-start)**2).sum(axis=-1))]
    e=points[np.argmin(((points-end)**2).sum(axis=-1))]
    interior=cv2.distanceTransform(mask.astype(np.uint8),cv2.DIST_L2,3)
    h,w=mask.shape;cost=np.full((h,w),np.inf);parent={}
    sx,sy=map(int,s);ex,ey=map(int,e);cost[sy,sx]=0;queue=[(0.,sx,sy)]
    while queue:
        c,x,y=heapq.heappop(queue)
        if c>cost[y,x]+1e-7:continue
        if x==ex and y==ey:break
        for dx,dy in [(1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)]:
            nx,ny=x+dx,y+dy
            if not(0<=nx<w and 0<=ny<h and mask[ny,nx]):continue
            nc=c+np.hypot(dx,dy)*(1+2/(interior[ny,nx]+.2))
            if nc<cost[ny,nx]:
                cost[ny,nx]=nc;parent[(nx,ny)]=(x,y);heapq.heappush(queue,(nc,nx,ny))
    path=[(ex,ey)]
    while path[-1]!=(sx,sy) and path[-1] in parent:path.append(parent[path[-1]])
    return np.asarray(path[::-1],np.float32)


def make_rig(images,action,index):
    pants=(images[2][...,3]>=64)|(images[4][...,3]>=64)
    feet=[]
    for slot in [3,5]:
        count,labels,stats,centers=cv2.connectedComponentsWithStats((images[slot][...,3]>=128).astype(np.uint8),8)
        for component in range(1,count):
            if stats[component,cv2.CC_STAT_AREA]>24:
                feet.append({'center':centers[component].astype(np.float32),'mask':labels==component,'slot':slot})
    assert len(feet)==2,(action,index,len(feet))
    feet.sort(key=lambda foot:foot['center'][0])
    a=FOOT_A_INDEX[action][index];feet=[feet[a],feet[1-a]]
    ys,xs=np.nonzero(pants);hip_y=float(ys.min()+17)
    hip=np.array([xs[np.abs(ys-hip_y)<3].mean(),hip_y],np.float32)
    points=np.stack([xs,ys],axis=-1).astype(np.float32);legs=[]
    for foot in feet:
        iy,ix=np.nonzero(pants&foot['mask'])
        ankle=np.array([ix.mean(),iy.mean()],np.float32) if len(ix) else points[np.argmin(((points-foot['center'])**2).sum(axis=-1))]
        path=center_path(pants,hip,ankle)
        middle=path[int(len(path)*.2):max(int(len(path)*.8),int(len(path)*.2)+1)]
        bend=distance(middle,hip,ankle)
        knee=middle[np.argmax(bend)] if len(middle) and bend.max()>2 else hip*.45+ankle*.55
        if min(np.linalg.norm(knee-hip),np.linalg.norm(knee-ankle))<5:knee=(hip+ankle)*.5
        legs.append(np.stack([hip,knee,ankle]))
    return {'hip':hip,'legs':np.stack(legs),'feet':feet}


def bone_field(grid,a,b):
    axis=a[1]-a[0];target=b[1]-b[0]
    length=max(1e-5,np.linalg.norm(axis));target_length=max(1e-5,np.linalg.norm(target))
    u=axis/length;v=np.array([-u[1],u[0]])
    tu=target/target_length;tv=np.array([-tu[1],tu[0]])
    p=grid-a[0]
    return (b[0]+(p@u)[...,None]*tu*(target_length/length)+(p@v)[...,None]*tv-grid).astype(np.float32)


def semantic_labels(grid,images,owner,rig):
    labels=np.zeros(owner.shape,np.int32)
    curves=np.stack([np.minimum(distance(grid,leg[0],leg[1]),distance(grid,leg[1],leg[2])) for leg in rig['legs']])
    nearest=np.argmin(curves,axis=0)+1
    lower=np.isin(owner,[2,3,4,5])&(grid[...,1]>=rig['hip'][1]-2)
    lower|=(owner==1)&(grid[...,1]>=rig['hip'][1])&(curves.min(axis=0)<10)
    labels[lower]=nearest[lower]
    for i,foot in enumerate(rig['feet']):labels[foot['mask']]=i+3
    labels[owner==8]=5;labels[owner==0]=6
    labels[owner<0]=-1
    return labels


def coordinate_map(grid,source,target,owner,target_owner,source_rig,target_rig,endpoint,correspondence):
    labels=semantic_labels(grid,source,owner,source_rig)
    target_labels=semantic_labels(grid,target,target_owner,target_rig)
    def part(images,mask):
        composite=np.zeros_like(images[0])
        # Pixel colors are used only to estimate correspondence, not written as art.
        for rgba in images:
            alpha=rgba[...,3:4].astype(np.float32)/255
            composite[...,:3]=(rgba[...,:3]*alpha+composite[...,:3]*(1-alpha)).astype(np.uint8)
            composite[...,3]=np.maximum(composite[...,3],rgba[...,3])
        composite[~mask]=0
        return composite
    fields=[correspondence(part(source,labels==0),part(target,target_labels==0),False)]
    lower_fields=[]
    for a,b in zip(source_rig['legs'],target_rig['legs']):
        upper=bone_field(grid,a[:2],b[:2]);lower=bone_field(grid,a[1:],b[1:])
        du=distance(grid,a[0],a[1]);dl=distance(grid,a[1],a[2])
        weight=(dl+.25)**2/((du+.25)**2+(dl+.25)**2)
        fields.append(upper*weight[...,None]+lower*(1-weight[...,None]));lower_fields.append(lower)
    fields.extend(lower_fields)
    fields.extend([correspondence(source[8],target[8],True),correspondence(source[0],target[0],True)])
    # Body first; actual back/front boot appearance slots establish leg overlap.
    leg_order=sorted(range(2),key=lambda i:source_rig['feet'][i]['slot'])
    order=[6,0]+[part for i in leg_order for part in [i+1,i+3]]+[5]
    h,w=owner.shape;result=np.zeros((h,w,4),np.float16);contributions=[]
    for label in order:
        flow=fields[label];lookup=grid.copy()
        for _ in range(8):
            fx=cv2.remap(flow[...,0],lookup[...,0],lookup[...,1],cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE)
            fy=cv2.remap(flow[...,1],lookup[...,0],lookup[...,1],cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE)
            lookup=grid-np.stack([fx,fy],axis=-1)/3
        nearest=np.floor(lookup+.5).astype(np.int32);x,y=nearest[...,0],nearest[...,1]
        inside=(x>=0)&(x<w)&(y>=0)&(y<h)
        valid=inside&(labels[np.clip(y,0,h-1),np.clip(x,0,w-1)]==label)
        result[valid,0]=x[valid];result[valid,1]=y[valid];result[valid,2]=1;result[valid,3]=endpoint
        contributions.append(int(valid.sum()))
    return result,contributions
