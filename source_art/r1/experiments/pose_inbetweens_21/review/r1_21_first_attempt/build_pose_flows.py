"""Estimate numeric pose displacement fields; never rewrite source PNGs.

Build dependency: opencv-python-headless==5.0.0.93, numpy, Pillow.
The Godot shader reconstructs intermediate poses from unchanged source textures.
Run pack_pose_flows.gd afterward to create portable numeric texture resources.
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


def sha(data):return hashlib.sha256(data).hexdigest()
def image(path):return np.asarray(Image.open(ROOT/path.removeprefix('res://')).convert('RGBA'))


def feature(rgba):
    alpha=rgba[...,3:4].astype(np.float32)/255
    rgb=rgba[...,:3].astype(np.float32)*alpha+128*(1-alpha)
    return cv2.cvtColor(np.rint(rgb).astype(np.uint8),cv2.COLOR_RGB2GRAY)


def estimate(a,b,method):
    if method=='DIS':
        solver=cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
        solver.setFinestScale(0)
        solver.setPatchSize(8)
        solver.setPatchStride(3)
        solver.setGradientDescentIterations(25)
        solver.setVariationalRefinementIterations(5)
        result=solver.calc(a,b,None)
    else:
        result=cv2.calcOpticalFlowFarneback(a,b,None,.5,5,21,7,7,1.5,cv2.OPTFLOW_FARNEBACK_GAUSSIAN)
    assert np.isfinite(result).all()
    length=np.linalg.norm(result,axis=2,keepdims=True)
    return result*np.minimum(1,80/np.maximum(length,.00001))


def reconstruction(source,target,backward):
    height,width=source.shape[:2]
    y,x=np.mgrid[:height,:width].astype(np.float32)
    sampled=cv2.remap(source,x+backward[...,0],y+backward[...,1],cv2.INTER_NEAREST,
                      borderMode=cv2.BORDER_CONSTANT,borderValue=0)
    a=sampled[...,3]>=128;b=target[...,3]>=128
    overlap=a&b;union=a|b
    iou=float(np.sum(overlap)/max(1,np.sum(union)))
    error=float(np.abs(sampled[overlap,:3].astype(np.float32)-target[overlap,:3]).mean()/255) if overlap.any() else 1.
    return {'alpha_iou':iou,'mean_rgb_error':error,'score':iou-.35*error}


def main():
    source_path=ROOT/'data/swordman_r1.json'
    source=json.loads(source_path.read_text())
    raw_dir=ROOT/'source_art/r1/motion';raw_dir.mkdir(parents=True,exist_ok=True)
    (ROOT/'assets/r1/motion').mkdir(parents=True,exist_ok=True)
    actions={};records=[];dedup={}
    for action in ['move','dash']:
        frames=source['animations'][action]['frames'];actions[action]=[]
        assert len(frames)==8 and all(f['duration_ms']==100 for f in frames)
        for index,frame in enumerate(frames):
            nxt=frames[(index+1)%len(frames)]
            a=image(frame['texture']);b=image(nxt['texture']);assert a.shape==b.shape==(224,320,4)
            candidates={};vectors={}
            for method in ['DIS','Farneback']:
                forward=estimate(feature(a),feature(b),method)
                backward=estimate(feature(b),feature(a),method)
                scores={'a_to_b':reconstruction(a,b,backward),'b_to_a':reconstruction(b,a,forward)}
                scores['score']=(scores['a_to_b']['score']+scores['b_to_a']['score'])/2
                candidates[method]=scores;vectors[method]=(forward,backward)
            method=max(candidates,key=lambda m:candidates[m]['score'])
            forward,backward=vectors[method]
            fields=np.concatenate([forward,backward],axis=2)
            quantized=fields.astype('<f2');raw=quantized.tobytes();digest=sha(raw)
            if digest not in dedup:
                name=f'{action}_{index:02d}'
                (raw_dir/(name+'.flow16')).write_bytes(raw)
                dedup[digest]=name
            name=dedup[digest]
            record={'current_texture':frame['texture'],'next_texture':nxt['texture'],
                    'current_png_sha256':sha((ROOT/frame['texture'].removeprefix('res://')).read_bytes()),
                    'next_png_sha256':sha((ROOT/nxt['texture'].removeprefix('res://')).read_bytes()),
                    'flow_texture':f'res://assets/r1/motion/{name}.res',
                    'raw_flow':f'res://source_art/r1/motion/{name}.flow16',
                    'raw_flow_sha256':digest,'raw_flow_bytes':len(raw)}
            actions[action].append(record)
            records.append({'action':action,'frame':index,'method':method,'candidates':candidates,
                            'max_displacement_pixels':float(np.linalg.norm(fields[...,:2],axis=2).max()),
                            'max_float16_quantization_error_pixels':float(np.max(np.abs(fields-quantized.astype(np.float32)))),
                            **record})
    runtime={'schema':1,'source_animation_data':'res://data/swordman_r1.json',
             'source_animation_sha256':sha(source_path.read_bytes()),'canvas_size':source['canvas_size'],
             'foot_anchor':source['foot_anchor'],'subframes_per_source_frame':3,'target_image_rate':30,
             'actions':actions,'numeric_channels':['forward_x','forward_y','backward_x','backward_y'],
             'notes':['Source PNGs and ANI timings are unchanged. These fields estimate correspondence, not recovered original poses.',
                      'Only move and dash use motion-compensated intermediate samples. Their cycles remain 800 ms.',
                      'Runtime chooses nearest sampled source colors rather than cross-fading two silhouettes.']}
    (ROOT/'data/swordman_inbetweens.json').write_text(json.dumps(runtime,ensure_ascii=False,indent=2)+'\n')
    report={'candidate':'R1/21','opencv':cv2.__version__,
            'build_requirement':'opencv-python-headless=='+importlib.metadata.version('opencv-python-headless'),
            'numpy':np.__version__,'threads':1,'pair_count':len(records),'unique_numeric_fields':len(dedup),
            'format':'little-endian RGBA16F displacement pixels, no color transfer function or mipmaps',
            'feature':'alpha-composited luminance on a neutral 128 background, used for analysis only',
            'official_reference':'https://docs.opencv.org/4.x/d4/dee/tutorial_optical_flow.html',
            'source_data_sha256':runtime['source_animation_sha256'],'pairs':records,
            'notes':['Endpoint reconstruction statistics rank the two flow estimates; they do not prove intermediate-pose quality.',
                     'Godot readback and visual review are required. No client programs or skill code are executed.']}
    (ROOT/'docs/r1_21_motion_source_reference.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'pairs':len(records),'unique_fields':len(dedup),
                      'methods':[r['method'] for r in records],
                      'endpoint_alpha_iou_min':min(r['candidates'][r['method']]['a_to_b']['alpha_iou'] for r in records)},ensure_ascii=False))


if __name__=='__main__':main()
