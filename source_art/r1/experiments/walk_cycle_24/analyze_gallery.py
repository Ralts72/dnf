"""Read native captures. No generated or source image pixels are edited."""
from pathlib import Path
import json,hashlib
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[4]
data=json.loads((ROOT/'data/swordman_r0.json').read_text())['animations']['move']['frames']
derived=json.loads((ROOT/'data/swordman_r1.json').read_text())['animations']['move']['frames']
recipe=json.loads((ROOT/'source_art/r1/experiments/walk_cycle_24/walk_recipe.json').read_text())
cases=[]
for facing in [1,-1]:
    for frame in range(8):
        original=np.asarray(Image.open(ROOT/derived[frame]['texture'].removeprefix('res://')).convert('RGBA'))
        owner=np.full((224,320),-1)
        for slot,layer in enumerate(data[frame]['layers']):
            a=np.asarray(Image.open(ROOT/layer['texture'].removeprefix('res://')).convert('RGBA'))
            h,w=a.shape[:2];x,y=np.asarray(layer['offset'])+[133,167]
            left,top=max(0,x),max(0,y);right,bottom=min(320,x+w),min(224,y+h)
            if right>left and bottom>top:owner[top:bottom,left:right][a[top-y:bottom-y,left-x:right-x,3]==255]=slot
        protected=(original[...,3]==255)&((np.arange(224)[:,None]<114)|np.isin(owner,[0,8]))
        for subframe in range(3):
            path=ROOT/f'work/r1_24_cycle/{"r" if facing==1 else "l"}_{frame:02d}_{subframe}.png'
            pixels=np.asarray(Image.open(path).convert('RGB'))
            if facing==1:logical=pixels[1::2,1::2]
            else:
                logical=np.full((224,320,3),[51,64,71],np.uint8)
                columns=531-2*np.arange(320);valid=(columns>=0)&(columns<640)
                logical[:,valid]=pixels[1::2,columns[valid]]
            mask=original[...,3]==255 if subframe==0 else protected
            match=(logical==original[...,:3]).all(axis=-1)
            record={'facing':facing,'frame':frame,'subframe':subframe,'protected_samples':int(mask.sum()),'protected_mismatches':int((mask&~match).sum()),
                    'integer_2x_grid':bool(np.array_equal(pixels[::2,::2],pixels[1::2,::2]) and np.array_equal(pixels[::2,::2],pixels[::2,1::2]))}
            if subframe:
                source=frame if subframe==1 else (frame+1)%8
                layer=data[source]['layers'][5]
                shoe=np.asarray(Image.open(ROOT/layer['texture'].removeprefix('res://')).convert('RGBA'))
                offset=np.asarray(layer['offset'])+[133,167]
                feet=np.asarray(recipe['physical_feet_A_B'])
                shift=feet[frame,0]*(1-subframe/3)+feet[(frame+1)%8,0]*(subframe/3)-feet[source,0]
                yy,xx=np.mgrid[:224,:320];p=np.stack([xx+.5,yy+.5],axis=-1)-shift
                coords=np.floor(p-offset).astype(int);sx,sy=coords[...,0],coords[...,1]
                inside=(sx>=0)&(sy>=0)&(sx<shoe.shape[1])&(sy<shoe.shape[0])
                cx,cy=np.clip(sx,0,shoe.shape[1]-1),np.clip(sy,0,shoe.shape[0]-1)
                inside&=shoe[cy,cx,3]==255
                if source==6:inside&=p[...,0]<134
                matches=(logical==shoe[cy,cx,:3]).all(axis=-1)
                foreground=np.isin(owner,[6,7,8])
                record.update(front_boot_samples=int((inside&~foreground).sum()),
                              front_boot_mismatches=int((inside&~foreground&~matches).sum()),
                              boot_foreground_overlap_samples=int((inside&foreground).sum()),
                              boot_foreground_overlap_mismatches=int((inside&foreground&~match).sum()))
            cases.append(record)
failed=[c for c in cases if c['protected_mismatches'] or not c['integer_2x_grid'] or c.get('front_boot_mismatches',0) or c.get('boot_foreground_overlap_mismatches',0)]
report={'study':'R1/24 full walk source-layer native captures','cases':cases,'failed':failed,
        'source_endpoint_cases':16,'derived_cases':32,'protected_samples':sum(c['protected_samples'] for c in cases),
        'front_boot_samples':sum(c.get('front_boot_samples',0) for c in cases),'production_candidate':'R1/22',
        'analysis_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'note':'Original endpoints, upper-body/weapon invariants, front boot source RGB and logical pixel grid. Not full visual acceptance or R1-depth validation.'}
(ROOT/'docs/r1_24_cycle_checks.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in ['cases','note']},ensure_ascii=False))
