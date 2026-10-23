"""Compare every active imported model PNG with its GLB image and source asset."""
from pathlib import Path
import hashlib
import io
import json
import struct
import argparse
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--candidate',default='R1/20')
parser.add_argument('--unchanged-model-baseline',default=None)
args=parser.parse_args()
def sha(path):return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()
def pixels(path):return np.asarray(Image.open(ROOT/path).convert('RGBA'))

raw=(ROOT/'assets/r1/models/west_coast_port.glb').read_bytes()
cursor=12
while cursor<len(raw):
    size,kind=struct.unpack_from('<II',raw,cursor);cursor+=8
    data=raw[cursor:cursor+size];cursor+=size
    if kind==0x4e4f534a:document=json.loads(data)
    elif kind==0x004e4942:binary=data
manifest=json.loads((ROOT/'docs/r1_model_texture_manifest.json').read_text())
assert manifest['texture_count']==len(manifest['textures'])==27
assert manifest['glb_sha256']==sha('assets/r1/models/west_coast_port.glb')
assert manifest['collector_sha256']==sha('tools/r1/collect_model_imports.gd')
profile=json.loads((ROOT/'docs/pixel_import_manifest.json').read_text())
assert profile['active_model_textures']==27 and profile['texture_count']==len(profile['textures'])
sources={'Source_Painted_Facade':'assets/r0/port/westile00/image/000.png',
         'Source_Painted_Pier_Backwall':'assets/r0/port/westile02/image/000.png',
         'Source_Painted_Stall':'assets/r0/port/westmobj00/image/000.png'}
for group,names in [('Dock',['Wood','Metal','Stone','Rope']),('Grove',['Plaster','Path','Grass','Canopy','Bark']),
                    ('Lamp',['Collar','Glass','Blue','Shaft'])]:
    sources.update({'Source_'+group+'_'+name:'assets/r1/'+group.lower()+'_'+name.lower()+'.png' for name in names})
sources.update({'Source_Quay_Coping':'assets/r1/quay_coping.png','Source_Pier_Top':'assets/r1/pier_top.png','Source_Pier_Face':'assets/r1/pier_face.png'})
sources.update({'Paving_Clay_'+str(i):'assets/r1/paving_tile_'+str(i)+'.png' for i in range(8)})
materials={m['name']:m for m in document['materials']}
records=[];used_images=set()
for entry in manifest['textures']:
    path=entry['path'].removeprefix('res://')
    actual=pixels(path)
    assert sha(path)==entry['png_sha256']
    assert hashlib.sha256(actual.tobytes()).hexdigest()==entry['rgba_sha256']
    assert list(actual.shape[1::-1])==entry['size']
    assert path in profile['textures']
    sidecar=(ROOT/(path+'.import')).read_text()
    for key,value in profile['profile'].items():assert key+'='+value+'\n' in sidecar
    for name in entry['materials']:
        material=materials[name]
        texture=document['textures'][material['pbrMetallicRoughness']['baseColorTexture']['index']]
        image=document['images'][texture['source']];used_images.add(texture['source'])
        view=document['bufferViews'][image['bufferView']];offset=view.get('byteOffset',0)
        embedded=np.asarray(Image.open(io.BytesIO(binary[offset:offset+view['byteLength']])).convert('RGBA'))
        original=pixels(sources[name])
        assert np.array_equal(actual,embedded) and np.array_equal(actual,original),name
        sampler=document['samplers'][texture['sampler']]
        assert sampler['minFilter']==sampler['magFilter']==9728
    records.append({'path':path,'materials':entry['materials'],'source_assets':[sources[n] for n in entry['materials']],
                    'pixels':actual.shape[0]*actual.shape[1],'source_dimensions':entry['size'],
                    'exact_source_and_glb_rgba':True,'import_profile_sha256':sha(path+'.import')})
assert len(sources)==27 and len(used_images)==len(document['images'])==27
if args.unchanged_model_baseline:
    baseline=json.loads((ROOT/'source_art/r1/checkpoints'/args.unchanged_model_baseline/'docs/r1_build_manifest.json').read_text())
    for path in ['assets/r1/models/west_coast_port.glb','source_art/r1/west_coast_port.blend','source_art/r1/model_manifest.json']:
        expected=next(x['sha256'] for x in baseline['artifacts'] if x['path']==path)
        assert sha(path)==expected
report={'candidate':args.candidate,'failed':[],'textures':records,'texture_count':len(records),
        'total_exact_rgba_pixels':sum(x['pixels'] for x in records),'glb_images_covered':len(used_images),
        'unchanged_model_baseline':args.unchanged_model_baseline,'glb_sha256':sha('assets/r1/models/west_coast_port.glb'),
        'collector_sha256':manifest['collector_sha256'],'qa_source_sha256':sha('tools/r1/verify_model_imports.py'),
        'note':'Every actual model base-color PNG is compared with its GLB image and owned source asset. Geometry and UV changes have separate checks.'}
prefix=args.candidate.lower().replace('/','_')
(ROOT/('docs/'+prefix+'_model_texture_source_checks.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='textures'},ensure_ascii=False))
