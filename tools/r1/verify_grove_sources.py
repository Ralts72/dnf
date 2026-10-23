"""Check source extraction, the explicit canopy mask and embedded GLB images."""
from pathlib import Path
import hashlib
import io
import json
import struct
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ref = json.loads((ROOT / 'source_art/r1/grove_reference.json').read_text())
manifest = json.loads((ROOT / 'docs/r0_asset_manifest.json').read_text())
source = ROOT / ref['source']
frame = next(f for f in manifest['frames'] if f['texture'] == 'res://' + ref['source'])
assert hashlib.sha256(source.read_bytes()).hexdigest() == ref['source_sha256'] == frame['sha256_png']
original = Image.open(source).convert('RGBA')
records = []
for item in ref['crops']:
    path = ROOT / item['output']
    actual = np.asarray(Image.open(path).convert('RGBA'))
    expected = np.asarray(original.crop(item['rect']))
    assert hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256']
    assert np.array_equal(actual, expected) and actual[:, :, 3].min() == 255
    records.append({'image': item['output'], 'exact_rgba': True, 'pixels': actual.shape[0] * actual.shape[1]})
canopy_path = ROOT / ref['canopy']['output']
masked = np.asarray(Image.open(canopy_path).convert('RGBA'))
raw = np.asarray(original.crop(ref['canopy']['rect']))
assert hashlib.sha256(canopy_path.read_bytes()).hexdigest() == ref['canopy']['sha256']
assert np.array_equal(masked[:, :, :3], raw[:, :, :3])
selected = masked[:, :, 3] > 0
assert np.array_equal(masked[selected], raw[selected])
assert selected.sum() == ref['canopy']['retained_pixels']
# Semantic probes chosen from the source image, independent of classifier math.
for x, y in [(90, 20), (150, 50), (150, 110)]:
    assert masked[y, x, 3] > 0, ('missing foliage probe', x, y)
for x, y in [(10, 110), (115, 130), (210, 130)]:
    assert masked[y, x, 3] == 0, ('baked wall probe retained', x, y)
glb = (ROOT / 'assets/r1/models/west_coast_port.glb').read_bytes()
cursor, document, binary = 12, None, None
while cursor < len(glb):
    length, kind = struct.unpack_from('<II', glb, cursor); cursor += 8
    payload = glb[cursor:cursor + length]; cursor += length
    if kind == 0x4e4f534a: document = json.loads(payload)
    elif kind == 0x004e4942: binary = payload
assert document and binary
embedded = []
for name in ['Bark', 'Plaster', 'Path', 'Grass', 'Canopy']:
    material = next(m for m in document['materials'] if m['name'] == 'Source_Grove_' + name)
    texture = document['textures'][material['pbrMetallicRoughness']['baseColorTexture']['index']]
    image = document['images'][texture['source']]
    view = document['bufferViews'][image['bufferView']]
    start = view.get('byteOffset', 0)
    actual = np.asarray(Image.open(io.BytesIO(binary[start:start + view['byteLength']])).convert('RGBA'))
    expected = np.asarray(Image.open(ROOT / f'assets/r1/grove_{name.lower()}.png').convert('RGBA'))
    assert np.array_equal(actual, expected), name
    sampler = document['samplers'][texture['sampler']]
    assert sampler['magFilter'] == sampler['minFilter'] == 9728
    if name == 'Canopy':
        assert material['alphaMode'] == 'MASK' and material['alphaCutoff'] == .25
        assert 'KHR_materials_unlit' in material['extensions']
    embedded.append({'material': material['name'], 'exact_rgba': True, 'pixels': actual.shape[0] * actual.shape[1]})
inspection = json.loads((ROOT / 'docs/r1_blend_source_check.json').read_text())
assert inspection['source_blend_sha256'] == hashlib.sha256((ROOT / 'source_art/r1/west_coast_port.blend').read_bytes()).hexdigest()
assert inspection['grove_canopy_uv_exists'] and inspection['grove_trunk_meshes'] == 9
assert not inspection['missing_images'] and all(i['packed'] for i in inspection['images'])
report = {'candidate': 'R1/11', 'failed': [], 'raw_crops': records, 'embedded_images': embedded,
          'canopy_retained_rgba_pixels': int(selected.sum()), 'canopy_all_rgb_unchanged': True,
          'canopy_selected_alpha_unchanged': True, 'semantic_mask_probes': 6,
          'mesh_objects': inspection['mesh_objects'], 'packed_images': len(inspection['images']),
          'source_blend_sha256': inspection['source_blend_sha256'],
          'glb_sha256': hashlib.sha256(glb).hexdigest(),
          'source_script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          'note': 'Mask selection and new geometry are interpreted; no source colors are repainted.'}
(ROOT / 'docs/r1_11_grove_source_checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k not in ['raw_crops', 'embedded_images']}))
