"""Verify exact source crops and the final GLB's four embedded lamp textures."""
from pathlib import Path
import hashlib,io,json,struct
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
ref=json.loads((ROOT/'source_art/r1/lamp_reference.json').read_text())
source=ROOT/ref['source'];manifest=json.loads((ROOT/'docs/r0_asset_manifest.json').read_text())
frame=next(f for f in manifest['frames'] if f['texture']=='res://'+ref['source'])
assert hashlib.sha256(source.read_bytes()).hexdigest()==frame['sha256_png']==ref['source_sha256']
original=Image.open(source).convert('RGBA');records=[]
for crop in ref['crops']:
    path=ROOT/crop['output'];actual=np.asarray(Image.open(path).convert('RGBA'))
    assert np.array_equal(actual,np.asarray(original.crop(crop['rect'])))
    assert actual[:,:,3].min()==255
    assert hashlib.sha256(path.read_bytes()).hexdigest()==crop['sha256']
    records.append({'crop':crop['output'],'exact_rgba':True,'pixels':actual.shape[0]*actual.shape[1]})
glb=(ROOT/'assets/r1/models/west_coast_port.glb').read_bytes();cursor=12
document,binary=None,None
while cursor<len(glb):
    length,kind=struct.unpack_from('<II',glb,cursor);cursor+=8
    payload=glb[cursor:cursor+length];cursor+=length
    if kind==0x4e4f534a:document=json.loads(payload)
    elif kind==0x004e4942:binary=payload
embedded=[]
for name in ['Blue','Glass','Shaft','Collar']:
    mat=next(m for m in document['materials'] if m['name']=='Source_Lamp_'+name)
    texture=document['textures'][mat['pbrMetallicRoughness']['baseColorTexture']['index']]
    view=document['bufferViews'][document['images'][texture['source']]['bufferView']]
    start=view.get('byteOffset',0)
    actual=np.asarray(Image.open(io.BytesIO(binary[start:start+view['byteLength']])).convert('RGBA'))
    assert np.array_equal(actual,np.asarray(Image.open(ROOT/f'assets/r1/lamp_{name.lower()}.png').convert('RGBA')))
    sampler=document['samplers'][texture['sampler']];assert sampler['minFilter']==sampler['magFilter']==9728
    embedded.append({'material':mat['name'],'exact_rgba':True,'pixels':actual.shape[0]*actual.shape[1]})
inspection=json.loads((ROOT/'docs/r1_blend_source_check.json').read_text())
assert inspection['source_blend_sha256']==hashlib.sha256((ROOT/'source_art/r1/west_coast_port.blend').read_bytes()).hexdigest()
assert inspection['lamp_meshes']==42 and inspection['lamp_uv_exists'] and inspection['lamp_positive_signed_volumes']==42
assert not inspection['missing_images']
report={'candidate':'R1/11','failed':[],'raw_crops':records,'embedded_images':embedded,
        'source_blend_sha256':inspection['source_blend_sha256'],'glb_sha256':hashlib.sha256(glb).hexdigest(),
        'source_script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'mesh_objects':inspection['mesh_objects'],'packed_images':len(inspection['images']),
        'note':'Pixels retain exact source RGBA; profiles, depth and cylindrical mapping are adapted, and native lamp lighting changes rendered RGB.'}
(ROOT/'docs/r1_11_lamp_source_checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'failed':[],'crops':len(records),'rgba_pixels':sum(r['pixels'] for r in records),'mesh_objects':inspection['mesh_objects'],'packed_images':len(inspection['images'])}))
