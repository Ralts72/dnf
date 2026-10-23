"""Verify original palette pixels, serialized native uniforms and unchanged models."""
from pathlib import Path
import hashlib,json,re
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
reference=json.loads((ROOT/'source_art/r1/water_reference.json').read_text())
manifest=json.loads((ROOT/'docs/r0_asset_manifest.json').read_text())
scene=(ROOT/'scenes/west_coast_r1.tscn').read_text();records=[]
for sample in reference['palette']:
    source=ROOT/sample['source']
    frame=next(f for f in manifest['frames'] if f['texture']=='res://'+sample['source'])
    assert hashlib.sha256(source.read_bytes()).hexdigest()==sample['source_sha256']==frame['sha256_png']
    rgba=list(Image.open(source).convert('RGBA').getpixel(tuple(sample['point'])))
    assert rgba==sample['rgba'] and rgba[3]==255
    values=re.search(r'shader_parameter/'+sample['name']+r' = Color\(([^)]+)\)',scene).group(1)
    assert all(abs(float(a)-b/255)<1e-8 for a,b in zip(values.split(','),rgba))
    records.append({'name':sample['name'],'point':sample['point'],'rgba':rgba,'exact_source_pixel':True,'native_uniform_matches':True})
shore=json.loads((ROOT/'source_art/r1/shore_reference.json').read_text())['measurements']
assert reference['mapping']['near_shore_points']==shore['near_shore_outer_pixels']
assert reference['mapping']['far_pier_bounds']==shore['far_piers'][0]['bounds']
assert reference['mapping']['middle_pier_bounds']==shore['far_piers'][1]['bounds']
assert not re.search(r'\bTIME\b',(ROOT/'shaders/harbor_water.gdshader').read_text())
baseline=json.loads((ROOT/'source_art/r1/checkpoints/candidate_11/docs/r1_build_manifest.json').read_text())
models=[]
for path in ['source_art/r1/west_coast_port.blend','assets/r1/models/west_coast_port.glb']:
    expected=next(a for a in baseline['artifacts'] if a['path']==path)['sha256']
    actual=hashlib.sha256((ROOT/path).read_bytes()).hexdigest();assert actual==expected
    models.append({'path':path,'unchanged_since':'R1/11','sha256':actual})
report={'candidate':'R1/12','failed':[],'palette':records,'unchanged_models':models,
    'source_script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'shader_sha256':hashlib.sha256((ROOT/'shaders/harbor_water.gdshader').read_bytes()).hexdigest(),
    'note':'Palette pixels and geometry hashes are exact; water rendering and motion are new interpretation.'}
(ROOT/'docs/r1_12_water_source_checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('Nine source water colors and native uniforms exact; source .blend and GLB unchanged since candidate 11.')
