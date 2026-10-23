"""Compare full native2x gallery RGB with independently decoded1x PNGs."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[4];BASE=Path(__file__).resolve().parent
cases=[]
for facing in [1,-1]:
    yy,xx=np.mgrid[:448,:640]
    sy=np.floor((yy+.5)/2).astype(int)
    sx=np.floor((xx+.5)/2 if facing==1 else (532-xx-.5)/2).astype(int)
    inside=(sx>=0)&(sx<320);cx=np.clip(sx,0,319)
    for frame in range(8):
        for sub in range(3):
            source=np.asarray(Image.open(BASE/f'baked/dash_{frame:02}_{sub}.png').convert('RGBA'))
            a=source[sy,cx];expected=np.full((448,640,3),[51,64,71],dtype=np.uint8);opaque=inside&(a[...,3]==255);expected[opaque]=a[opaque,:3]
            path=ROOT/f'work/r1_26_cycle/{"r" if facing==1 else "l"}_{frame:02}_{sub}.png'
            actual=np.asarray(Image.open(path).convert('RGB'));bad=np.any(actual!=expected,axis=-1)
            grid=bool(np.array_equal(actual[::2,::2],actual[1::2,::2]) and np.array_equal(actual[::2,::2],actual[::2,1::2]))
            cases.append({'frame':frame,'subframe':sub,'facing':facing,'full_RGB_pixels':int(bad.size),'mismatches':int(bad.sum()),'integer2x_grid':grid,'png_sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
result={'study':'R1/26 full native2x RGB readback','cases':cases,'failed':[c for c in cases if c['mismatches'] or not c['integer2x_grid']],
        'full_RGB_pixels':sum(c['full_RGB_pixels'] for c in cases),'analysis_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'note':'Both facings, all24 bakes, full viewport including known opaque background; exact source-color and2x logical-grid comparison.'}
(ROOT/'docs/r1_26_cycle_checks.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'cases':len(cases),'full_RGB_pixels':result['full_RGB_pixels'],'failed':result['failed']}))
