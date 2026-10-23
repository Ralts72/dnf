"""Build numeric source-coordinate maps using the retained appearance layers.

Source PNGs are read only. Runtime shaders sample their original colors.
Build dependency: opencv-python-headless==5.0.0.93, numpy, Pillow.
"""
from pathlib import Path
import hashlib
import importlib.metadata
import json

import cv2
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
cv2.setNumThreads(1)
SIZE=(320,224)
YY,XX=np.mgrid[:SIZE[1],:SIZE[0]].astype(np.float32)
GRID=np.stack([XX,YY],axis=-1)


def sha(data):return hashlib.sha256(data).hexdigest()
def image(path):return np.asarray(Image.open(ROOT/path.removeprefix('res://')).convert('RGBA'))


def layers(frame,anchor):
    result=[]
    for layer in frame['layers']:
        raw=image(layer['texture']);h,w=raw.shape[:2]
        x,y=np.array(layer['offset'])+anchor
        canvas=np.zeros((SIZE[1],SIZE[0],4),np.uint8)
        left,top=max(0,x),max(0,y)
        right,bottom=min(SIZE[0],x+w),min(SIZE[1],y+h)
        if right>left and bottom>top:
            canvas[top:bottom,left:right]=raw[top-y:bottom-y,left-x:right-x]
        result.append(canvas)
    owner=np.full((SIZE[1],SIZE[0]),-1,np.int32)
    for i,rgba in enumerate(result):owner[rgba[...,3]>=64]=i
    return result,owner


def feature(rgba):
    alpha=rgba[...,3:4].astype(np.float32)/255
    rgb=rgba[...,:3].astype(np.float32)*alpha+128*(1-alpha)
    return cv2.cvtColor(np.rint(rgb).astype(np.uint8),cv2.COLOR_RGB2GRAY)


def shape(rgba):
    y,x=np.nonzero(rgba[...,3]>=64)
    if len(x)==0:return None
    points=np.stack([x,y],axis=1).astype(np.float32)
    center=points.mean(axis=0)
    covariance=np.cov((points-center).T) if len(points)>2 else np.eye(2)
    _,vectors=np.linalg.eigh(covariance)
    return center,vectors[:,-1],len(points)


def correspondence(a,b,rigid):
    sa,sb=shape(a),shape(b)
    if sa is None or sb is None:return np.zeros((*a.shape[:2],2),np.float32)
    ca,axis_a,count_a=sa;cb,axis_b,count_b=sb
    if rigid:
        if np.dot(axis_a,axis_b)<0:axis_b=-axis_b
        angle=np.arctan2(axis_b[1],axis_b[0])-np.arctan2(axis_a[1],axis_a[0])
        angle=(angle+np.pi)%(2*np.pi)-np.pi
        angle=float(np.clip(angle,-np.pi/4,np.pi/4)) if min(count_a,count_b)>16 else 0.
        rotation=np.array([[np.cos(angle),-np.sin(angle)],[np.sin(angle),np.cos(angle)]],np.float32)
        return ((GRID-ca)@rotation.T+cb-GRID).astype(np.float32)
    delta=cb-ca
    aligned=cv2.warpAffine(feature(b),np.array([[1,0,-delta[0]],[0,1,-delta[1]]],np.float32),SIZE,
                           flags=cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT,borderValue=128)
    solver=cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
    solver.setFinestScale(0);solver.setPatchSize(8);solver.setPatchStride(3)
    solver.setGradientDescentIterations(25);solver.setVariationalRefinementIterations(5)
    residual=solver.calc(feature(a),aligned,None)
    result=residual+delta
    assert np.isfinite(result).all()
    return result


def coordinate_map(source_layers,target_layers,owner,endpoint):
    result=np.zeros((SIZE[1],SIZE[0],4),np.float16)
    contributions=[]
    for i,(a,b) in enumerate(zip(source_layers,target_layers)):
        # Weapons and the two shoe layers are rigid pieces; avoid blade bending
        # and preserve the identity of each boot when the legs cross.
        flow=correspondence(a,b,rigid=i in [0,3,5,8])
        lookup=GRID.copy()
        for _ in range(6):
            fx=cv2.remap(flow[...,0],lookup[...,0],lookup[...,1],cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE)
            fy=cv2.remap(flow[...,1],lookup[...,0],lookup[...,1],cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE)
            lookup=GRID-np.stack([fx,fy],axis=-1)/3.
        nearest=np.floor(lookup+.5).astype(np.int32)
        x,y=nearest[...,0],nearest[...,1]
        inside=(x>=0)&(x<SIZE[0])&(y>=0)&(y<SIZE[1])
        clipped_x=np.clip(x,0,SIZE[0]-1);clipped_y=np.clip(y,0,SIZE[1]-1)
        valid=inside&(owner[clipped_y,clipped_x]==i)
        result[valid,0]=x[valid];result[valid,1]=y[valid]
        result[valid,2]=1;result[valid,3]=endpoint
        contributions.append(int(valid.sum()))
    assert np.isfinite(result).all()
    return result,contributions


def main():
    source_path=ROOT/'data/swordman_r1.json'
    source=json.loads(source_path.read_text());raw_source=json.loads((ROOT/'data/swordman_r0.json').read_text())
    raw_dir=ROOT/'source_art/r1/motion';raw_dir.mkdir(parents=True,exist_ok=True)
    (ROOT/'assets/r1/motion').mkdir(parents=True,exist_ok=True)
    actions={};records=[];unique={}
    for action in ['move','dash']:
        frames=source['animations'][action]['frames'];raw_frames=raw_source['animations'][action]['frames'];actions[action]=[]
        assert len(frames)==8 and all(f['duration_ms']==100 for f in frames)
        aligned=[layers(f,np.array(source['foot_anchor'])) for f in raw_frames]
        for index,frame in enumerate(frames):
            ni=(index+1)%8;nxt=frames[ni]
            la,oa=aligned[index];lb,ob=aligned[ni]
            maps=[]
            for subframe,src,dst,owners,endpoint in [(1,la,lb,oa,0),(2,lb,la,ob,1)]:
                mapping,contributions=coordinate_map(src,dst,owners,endpoint)
                raw=mapping.astype('<f2').tobytes();digest=sha(raw)
                if digest not in unique:
                    name=f'{action}_{index:02d}_{subframe}'
                    (raw_dir/(name+'.posemap16')).write_bytes(raw);unique[digest]=name
                name=unique[digest]
                maps.append({'phase':subframe/3,'texture':f'res://assets/r1/motion/{name}.res',
                             'raw':f'res://source_art/r1/motion/{name}.posemap16','raw_sha256':digest,
                             'raw_bytes':len(raw),'endpoint':endpoint,'valid_pixels':int((mapping[...,2]>.5).sum()),
                             'layer_contributions':contributions})
            record={'current_texture':frame['texture'],'next_texture':nxt['texture'],
                    'current_png_sha256':sha((ROOT/frame['texture'].removeprefix('res://')).read_bytes()),
                    'next_png_sha256':sha((ROOT/nxt['texture'].removeprefix('res://')).read_bytes()),'maps':maps}
            actions[action].append(record);records.append({'action':action,'frame':index,**record})
    runtime={'schema':2,'source_animation_data':'res://data/swordman_r1.json','source_animation_sha256':sha(source_path.read_bytes()),
             'canvas_size':source['canvas_size'],'foot_anchor':source['foot_anchor'],'subframes_per_source_frame':3,'target_image_rate':30,
             'actions':actions,'numeric_channels':['source_x_integer','source_y_integer','valid','source_endpoint'],
             'notes':['Source PNGs and ANI timings are unchanged. Intermediate correspondence is an adaptation, not recovered original poses.',
                      'Each retained appearance layer is analyzed separately; rigid shoes/weapons and layer priority preserve part identity.',
                      'Runtime samples nearest original colors from one endpoint. No silhouette or RGB cross-fade is used.']}
    (ROOT/'data/swordman_inbetweens.json').write_text(json.dumps(runtime,ensure_ascii=False,indent=2)+'\n')
    report={'candidate':'R1/21','opencv':cv2.__version__,'build_requirement':'opencv-python-headless=='+importlib.metadata.version('opencv-python-headless'),
            'numpy':np.__version__,'threads':1,'pair_count':len(records),'unique_numeric_fields':len(unique),'format':'little-endian RGBA16F integer source coordinates',
            'method':'Separate appearance layers; centroid-aligned DIS; rigid weapon/shoe correspondence; per-layer inverse pull and source visibility priority',
            'official_reference':'https://docs.opencv.org/4.x/d4/dee/tutorial_optical_flow.html','source_data_sha256':runtime['source_animation_sha256'],
            'raw_layer_data_sha256':sha((ROOT/'data/swordman_r0.json').read_bytes()),'pairs':records,
            'notes':['Numeric maps encode source coordinates only. Original colors are sampled by Godot at runtime.',
                     'Quantized coordinates are exact integers in half float. Intermediate silhouettes still require visual review.',
                     'No client programs or skill scripts are executed.']}
    (ROOT/'docs/r1_21_motion_source_reference.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'pairs':len(records),'maps':len(unique),'valid_pixels_min':min(m['valid_pixels'] for p in records for m in p['maps'])}))


if __name__=='__main__':main()
