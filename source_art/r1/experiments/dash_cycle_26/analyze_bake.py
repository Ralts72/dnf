"""Read native dash bakes. No original or generated image pixels are edited."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[4]
BASE=Path(__file__).resolve().parent
read=lambda p:json.loads(p.read_text())
rgba=lambda p:np.asarray(Image.open(p).convert('RGBA'))
raw=read(ROOT/'data/swordman_r0.json')['animations']['dash']['frames']
source=read(ROOT/'data/swordman_r1.json')['animations']['dash']['frames']
recipe=read(BASE/'dash_recipe.json')
palette=set()
for frame in raw:
    for layer in frame['layers']:
        a=rgba(ROOT/layer['texture'].removeprefix('res://'))
        palette.update(map(tuple,a[a[...,3]==255,:3]))
cases=[]
for frame in range(8):
    original=rgba(ROOT/source[frame]['texture'].removeprefix('res://'))
    owner=np.full((224,320),-1)
    for slot,layer in enumerate(raw[frame]['layers']):
        a=rgba(ROOT/layer['texture'].removeprefix('res://'));h,w=a.shape[:2];x,y=np.array(layer['offset'])+[133,167]
        l,t=max(0,x),max(0,y);r,b=min(320,x+w),min(224,y+h)
        if r>l and b>t:owner[t:b,l:r][a[t-y:b-y,l-x:r-x,3]==255]=slot
    protected=(original[...,3]==255)&((np.arange(224)[:,None]<recipe['hip_y'])|np.isin(owner,[0,1,6,7,8]))
    for sub in range(3):
        path=BASE/f'baked/dash_{frame:02}_{sub}.png';actual=rgba(path)
        check=original[...,3]==255 if sub==0 else protected
        mismatch=check&np.any(actual!=original,axis=-1)
        colors=set(map(tuple,actual[actual[...,3]==255,:3]))
        record={'frame':frame,'subframe':sub,'opaque_pixels':int((actual[...,3]==255).sum()),'alpha_levels':np.unique(actual[...,3]).tolist(),
                'new_RGB_colors':len(colors-palette),'protected_samples':int(check.sum()),'protected_mismatches':int(mismatch.sum()),
                'mismatch_examples':np.argwhere(mismatch)[:8,::-1].tolist(),'png_sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
        if sub:
            template=frame if sub==1 else (frame+1)%8;leg=recipe['front_leg'][template];boot=recipe['boots'][template][leg]
            layer=raw[template]['layers'][boot['slot']];a=rgba(ROOT/layer['texture'].removeprefix('res://'));ox,oy=np.array(layer['offset'])+[133,167]
            phase=sub/3;target=np.array(recipe['boots'][frame][leg]['center'])*(1-phase)+np.array(recipe['boots'][(frame+1)%8][leg]['center'])*phase
            shift=target-np.array(boot['center']);yy,xx=np.mgrid[:224,:320];p=np.stack([xx+.5,yy+.5],axis=-1)-shift
            xy=np.floor(p-[ox,oy]).astype(int);sx,sy=xy[...,0],xy[...,1]
            inside=(sx>=0)&(sy>=0)&(sx<a.shape[1])&(sy<a.shape[0]);cx=np.clip(sx,0,a.shape[1]-1);cy=np.clip(sy,0,a.shape[0]-1)
            bx,by,br,bb=boot['bbox'];inside&=(p[...,0]>=bx)&(p[...,0]<br)&(p[...,1]>=by)&(p[...,1]<bb)&(a[cy,cx,3]==255)
            foreground=np.isin(owner,[6,7,8]);visible=inside&~foreground
            bad=visible&np.any(actual!=a[cy,cx],axis=-1)
            record.update(front_boot_samples=int(visible.sum()),front_boot_mismatches=int(bad.sum()),front_boot_bad=np.argwhere(bad)[:8,::-1].tolist())
        cases.append(record)
failed=[c for c in cases if c['protected_mismatches'] or c['new_RGB_colors'] or c['alpha_levels']!=[0,255] or c.get('front_boot_mismatches',0)]
result={'study':'R1/26 native1x dash source-palette and protected-source check','cases':cases,'failed':failed,'unique_poses':len({c['png_sha256'] for c in cases}),
        'source_RGB_colors':len(palette),'opaque_pixels':sum(c['opaque_pixels'] for c in cases),'protected_samples':sum(c['protected_samples'] for c in cases),
        'front_boot_samples':sum(c.get('front_boot_samples',0) for c in cases),'analysis_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'note':'Palette, alpha, visible body/clothes/weapon and front-boot samples; does not by itself prove whole-pose aesthetics or all hidden leg geometry.'}
(ROOT/'docs/r1_26_palette_checks.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['cases','failed','note']}|{'failed_cases':len(failed)}))
