"""Verify the lossless APNG against every native comparison capture."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[4];BASE=Path(__file__).resolve().parent
path=ROOT/'docs/previews/r1_26_dash_comparison.png';animation=Image.open(path)
sources=[np.asarray(Image.open(BASE/f'comparison/pair_{i:02}.png').convert('RGBA')) for i in range(24)]
cases=[]
for i in range(animation.n_frames):
    animation.seek(i);actual=np.asarray(animation.convert('RGBA'));source=sources[i%24]
    cases.append({'frame':i,'duration_ms':animation.info.get('duration',0),'rgba_mismatches':int(np.any(actual!=source,axis=-1).sum())})
cycles=[sum(c['duration_ms'] for c in cases[i:i+24]) for i in range(0,len(cases),24)]
checks=[{'check':'all144_native_frames_exact','pass':len(cases)==144 and all(c['rgba_mismatches']==0 for c in cases)},
        {'check':'all6_cycles_remain800ms','pass':len(cycles)==6 and all(abs(t-800)<.01 for t in cycles)}]
result={'checks':checks,'failed':[c for c in checks if not c['pass']],'frame_count':len(cases),'native_size':animation.size,'frames':cases,
        'cycle_durations_ms':cycles,'total_duration_ms':sum(cycles),'apng_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'qa_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'note':'APNG is the lossless comparison; optional H264 MP4 is a lossy convenience preview.'}
(ROOT/'docs/r1_26_preview_checks.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['frames','note']}))
