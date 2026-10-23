"""Read-only source-pixel comparisons of the native single-transition renders."""
from pathlib import Path
from PIL import Image
import hashlib,json
import numpy as np

ROOT=Path(__file__).resolve().parents[4]
raw=json.loads((ROOT/'data/swordman_r0.json').read_text())['animations']['move']['frames']
owner=np.full((224,320),-1)
for slot,layer in enumerate(raw[1]['layers']):
    image=np.asarray(Image.open(ROOT/layer['texture'].removeprefix('res://')).convert('RGBA'))
    h,w=image.shape[:2];x,y=np.asarray(layer['offset'])+[133,167]
    if x<0 or y<0 or x+w>320 or y+h>224:continue
    owner[y:y+h,x:x+w][image[...,3]>=254]=slot
protected=np.isin(owner,[0,6,7,8])|((owner==1)&(np.arange(224)[:,None]<96))
renders=[np.asarray(Image.open(ROOT/f'docs/previews/r1_23_stance_{i}.png').convert('RGB')) for i in range(4)]
logical=[image[33:481:2,1:640:2] for image in renders]
assert all(image.shape==(224,320,3) for image in logical)
cases=[]
for case in [1,2]:
    equal=(logical[case]==logical[0]).all(axis=-1)
    layer=raw[2]['layers'][5]
    shoe=np.asarray(Image.open(ROOT/layer['texture'].removeprefix('res://')).convert('RGBA'))
    offset=np.asarray(layer['offset'])+[133,167];yy,xx=np.mgrid[:224,:320]
    shift=np.array([-13.7,-3.6])*(1-case/3)
    coordinates=np.floor(np.stack([xx+.5,yy+.5],axis=-1)-offset-shift).astype(int)
    x,y=coordinates[...,0],coordinates[...,1]
    valid=(x>=0)&(y>=0)&(x<shoe.shape[1])&(y<shoe.shape[0])
    cx,cy=np.clip(x,0,shoe.shape[1]-1),np.clip(y,0,shoe.shape[0]-1)
    valid&=shoe[cy,cx,3]==255
    matches=(logical[case]==shoe[cy,cx,:3]).all(axis=-1)
    block=renders[case][32:480,:640]
    record={'case':case,'protected_head_coat_weapon_samples':int(protected.sum()),
            'identical':int((equal&protected).sum()),'mismatched':int((~equal&protected).sum()),
            'front_boot_opaque_samples':int(valid.sum()),'front_boot_exact':int((valid&matches).sum()),
            'front_boot_mismatches':int((valid&~matches).sum()),
            'integer_grid_2x_blocks_equal':bool(np.array_equal(block[::2,::2],block[1::2,::2]) and np.array_equal(block[::2,::2],block[::2,1::2]))}
    assert record['mismatched']==record['front_boot_mismatches']==0 and record['integer_grid_2x_blocks_equal']
    cases.append(record)
report={'study':'R1/23 manually authored source-layer single transition','source_pair':['move_01','move_02'],
        'phases':[1/3,2/3],'cases':cases,'native_render':'Godot CanvasItem2x, original source colors, numeric visibility mask',
        'scope':'One transition; no full cycle or R1 integration. Parameters are authored adaptations. Visual acceptance pending.',
        'qa_script_sha256':hashlib.sha256((ROOT/'source_art/r1/experiments/pose_inbetweens_23/stance_review.gd').read_bytes()).hexdigest(),
        'shader_sha256':hashlib.sha256((ROOT/'source_art/r1/experiments/pose_inbetweens_23/stance_shear.gdshader').read_bytes()).hexdigest(),
        'analysis_source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
(ROOT/'docs/r1_23_stance_checks.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'cases':len(cases),'protected_samples_each':int(protected.sum()),'front_boot_samples_each':cases[0]['front_boot_exact'],'mismatches':0}))
