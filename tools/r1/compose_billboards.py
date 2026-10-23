"""Derive single-surface 3D billboards from the retained, editable R0 layers.

No resize or repaint. Pillow alpha-composites crops with their source offsets;
the derived canvas and foot anchor are recorded for reproducibility.
"""
from pathlib import Path
import json
import math
import hashlib
import sys
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
manifest={'source_manifest':'docs/r0_asset_manifest.json','derivatives':[]}
for actor in ['swordman','npc_lo','npc_sr']:
    source_path=ROOT/f'data/{actor}_r0.json'
    source=json.loads(source_path.read_text())
    cache={}
    bounds=[]
    for animation in source['animations'].values():
        for frame in animation['frames']:
            for layer in frame['layers']:
                path=layer['texture']
                if path not in cache:
                    cache[path]=Image.open(ROOT/path.removeprefix('res://')).convert('RGBA')
                box=cache[path].getbbox()
                if box:
                    x,y=layer['offset']
                    bounds.append((x+box[0],y+box[1],x+box[2],y+box[3]))
    left=min(b[0] for b in bounds)-4
    top=min(b[1] for b in bounds)-4
    right=max(b[2] for b in bounds)+4
    bottom=max(b[3] for b in bounds)+4
    size=(math.ceil((right-left)/16)*16,math.ceil((bottom-top)/16)*16)
    data={'schema':1,'source_data':f'data/{actor}_r0.json','canvas_size':size,
          'foot_anchor':[-left,-top],'animations':{}}
    directory=ROOT/f'assets/r1/actors/{actor}'
    directory.mkdir(parents=True,exist_ok=True)
    for action,animation in source['animations'].items():
        frames=[]
        for i,frame in enumerate(animation['frames']):
            canvas=Image.new('RGBA',size)
            for layer in frame['layers']:
                image=cache[layer['texture']]
                if not image.getbbox():continue
                canvas.alpha_composite(image,(layer['offset'][0]-left,layer['offset'][1]-top))
            path=directory/f'{action}_{i:02d}.png'
            canvas.save(path)
            texture='res://'+path.relative_to(ROOT).as_posix()
            frames.append({'texture':texture,'duration_ms':frame['duration_ms'],'img_frame':frame['img_frame'],
                           'source_properties':frame['source_properties'],'source_boxes':frame['source_boxes']})
            manifest['derivatives'].append({'texture':texture,'source_animation':animation['source_ani'],
                'source_frame':i,'source_layer_textures':[l['texture'] for l in frame['layers']],
                'source_layer_offsets':[l['offset'] for l in frame['layers']],
                'foot_anchor':[-left,-top],'canvas_size':size,
                'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                'operation':'Source alpha composite in retained layer order; no scaling or repaint'})
        data['animations'][action]={'frames':frames}
    (ROOT/f'data/{actor}_r1.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print(actor,size,data['foot_anchor'])
(ROOT/'docs/r1_derivative_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
sys.path.insert(0,str(ROOT/'tools/dnf_client_analysis'))
from pixel_imports import configure
configure(ROOT)
