"""Measure the original facade silhouette and retain a raw foliage crop.

No generative repaint: measurements and a lossless rectangular crop only.
"""
from pathlib import Path
import json,hashlib
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
source=ROOT/'assets/r0/port/westile00/image/000.png'
image=Image.open(source).convert('RGBA')
profile=[]
for x in range(image.width):
    def plaster(y):
        r,g,b,a=image.getpixel((x,y))
        return a>240 and r>170 and g>160 and b>100 and r>=g-4
    candidates=[y for y in range(30,115) if all(plaster(y+k) for k in range(3))]
    profile.append(min(candidates) if candidates else 90)
smoothed=[sum(profile[max(0,i-5):min(len(profile),i+6)])/len(profile[max(0,i-5):min(len(profile),i+6)]) for i in range(len(profile))]
foliage_path=ROOT/'assets/r1/foliage_top.png'
image.crop((85,0,224,85)).save(foliage_path)
floor_quads=[]
for i,(dx,dy) in enumerate([(0,0),(21,11),(42,22),(63,33),(84,44),(105,55),(0,62),(42,62)]):
    quad=[62+dx,274+dy,38+dx,283+dy,62+dx,293+dy,85+dx,283+dy]
    tile=image.transform((64,64),Image.Transform.QUAD,quad,Image.Resampling.NEAREST)
    path=ROOT/f'assets/r1/paving_tile_{i}.png'
    tile.save(path)
    floor_quads.append({'output':path.relative_to(ROOT).as_posix(),'quad_ul_ll_lr_ur':quad,
                        'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                        'operation':'Nearest-neighbor quad rectification of a painted source tile, no repaint'})
out={'source_texture':'assets/r0/port/westile00/image/000.png',
     'sha256_source_png':hashlib.sha256(source.read_bytes()).hexdigest(),
     'source_manifest':'docs/r0_asset_manifest.json','profile_top_pixels':profile,
     'profile_smoothed_pixels':smoothed,
     'source_dimensions':image.size,
     'mapping':{'x_pixel_per_meter':60,'x_pixel_origin':447,'y_pixel_ground':227.59,
                'y_pixel_per_meter':47.2806452164},
     'foliage_crop':{'rect':[85,0,224,85],'output':'assets/r1/foliage_top.png',
                     'sha256':hashlib.sha256(foliage_path.read_bytes()).hexdigest()},
     'paving_rectification':floor_quads,
     'note':'Profile is an image-color measurement, not recovered original 3D geometry. Interior walls, depth and back faces are new construction.'}
(ROOT/'source_art/r1/facade_reference.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print('Measured facade profile; exported lossless foliage crop.')
