"""Prove the GLB delta is restricted to the intended UV fields and facade alpha."""
from pathlib import Path
import copy,hashlib,json,struct
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'source_art/r1/checkpoints/candidate_16'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def load(path):
    raw=path.read_bytes();cursor=12
    while cursor<len(raw):
        size,kind=struct.unpack_from('<II',raw,cursor);cursor+=8
        data=raw[cursor:cursor+size];cursor+=size
        if kind==0x4e4f534a:document=json.loads(data)
        elif kind==0x004e4942:binary=data
    return document,binary
before,old=load(BASE/'assets/r1/models/west_coast_port.glb')
after,new=load(ROOT/'assets/r1/models/west_coast_port.glb')
assert len(old)==len(new)
allowed=set();facade=[];dock=[]
for node in before['nodes']:
    if 'mesh' not in node:continue
    for primitive in before['meshes'][node['mesh']]['primitives']:
        material=before['materials'][primitive['material']]['name']
        if material=='Source_Painted_Facade':allowed.add(primitive['attributes']['TEXCOORD_0']);facade.append(node['name'])
        elif node['name'] in ['Dock_Mooring_Core','Dock_Mooring_Limestone_Cap']:
            allowed.update(primitive['attributes'][k] for k in ['TEXCOORD_0','TEXCOORD_1']);dock.append(node['name'])
assert len(facade)==76 and len(dock)==2 and len(allowed)==80
mask=np.zeros(len(old),dtype=np.bool_)
for index in allowed:
    accessor=before['accessors'][index];assert accessor['componentType']==5126 and accessor['type']=='VEC2'
    view=before['bufferViews'][accessor['bufferView']];offset=view.get('byteOffset',0)+accessor.get('byteOffset',0)
    stride=view.get('byteStride',8)
    for i in range(accessor['count']):mask[offset+i*stride:offset+i*stride+8]=True
old_bytes=np.frombuffer(old,dtype=np.uint8);new_bytes=np.frombuffer(new,dtype=np.uint8)
assert np.array_equal(old_bytes[~mask],new_bytes[~mask])
normalized=copy.deepcopy(after)
for index in allowed:
    for field in ['min','max']:
        if field in before['accessors'][index]:normalized['accessors'][index][field]=before['accessors'][index][field]
material=next(m for m in normalized['materials'] if m['name']=='Source_Painted_Facade')
prior=next(m for m in before['materials'] if m['name']=='Source_Painted_Facade')
assert material['alphaMode']=='MASK' and material['alphaCutoff']==.25
for field in ['alphaMode','alphaCutoff']:
    if field in prior:material[field]=prior[field]
    else:material.pop(field,None)
assert normalized==before
report={'candidate':'R1/17','baseline':'R1/16','failed':[],'facade_meshes':len(facade),'dock_meshes':dock,
        'allowed_uv_accessors':len(allowed),'changed_uv_bytes':int(np.sum(old_bytes!=new_bytes)),
        'unchanged_non_uv_binary_bytes':int(np.sum(~mask)),
        'all_positions_normals_indices_images_and_transforms_unchanged':True,
        'only_material_change':'Source_Painted_Facade alphaMode MASK / cutoff 0.25; PBR retained',
        'glb_sha256':sha(ROOT/'assets/r1/models/west_coast_port.glb'),
        'qa_source_sha256':sha(Path(__file__)),
        'note':'Strict byte whitelist covers only 80 UV accessors. All other binary bytes and JSON properties are equal to candidate 16.'}
(ROOT/'docs/r1_17_uv_source_checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
