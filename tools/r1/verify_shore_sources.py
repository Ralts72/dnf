"""Verify the new masonry crops against the retained original source PNGs."""
from pathlib import Path
import hashlib
import io
import json
import struct
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ref = json.loads((ROOT / 'source_art/r1/shore_reference.json').read_text())
original = json.loads((ROOT / 'docs/r0_asset_manifest.json').read_text())
frames = {f['texture'].removeprefix('res://'): f for f in original['frames']}
for source in ref['source_images']:
    raw = (ROOT / source['path']).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == source['sha256'] == frames[source['path']]['sha256_png']
records = []
for crop in ref['texture_crops']:
    source = ROOT / crop['source']
    assert hashlib.sha256(source.read_bytes()).hexdigest() == crop['source_sha256']
    dest = ROOT / crop['output']
    assert hashlib.sha256(dest.read_bytes()).hexdigest() == crop['sha256']
    expected = np.asarray(Image.open(source).convert('RGBA').crop(crop['rect']))
    actual = np.asarray(Image.open(dest).convert('RGBA'))
    assert np.array_equal(actual, expected)
    assert actual[:, :, 3].min() == 255
    records.append({'crop': crop['output'], 'exact_rgba': True, 'opaque': True, 'pixels': actual.shape[0] * actual.shape[1]})
inspection = json.loads((ROOT / 'docs/r1_blend_source_check.json').read_text())
assert inspection['source_blend_sha256'] == hashlib.sha256((ROOT / 'source_art/r1/west_coast_port.blend').read_bytes()).hexdigest()
assert not inspection['missing_images'] and all(i['packed'] for i in inspection['images'])
assert inspection['shore_uv_exists'] and inspection['near_shore_diagonal_caps'] >= 8
glb = (ROOT / 'assets/r1/models/west_coast_port.glb').read_bytes()
cursor, document, binary = 12, None, None
while cursor < len(glb):
    length, kind = struct.unpack_from('<II', glb, cursor)
    cursor += 8
    payload = glb[cursor:cursor + length]
    cursor += length
    if kind == 0x4e4f534a:
        document = json.loads(payload)
    elif kind == 0x004e4942:
        binary = payload
assert document is not None and binary is not None
assert all(s['magFilter'] == s['minFilter'] == 9728 for s in document['samplers'])
embedded = []
for name, source in [('Source_Quay_Coping', 'assets/r1/quay_coping.png'),
                     ('Source_Pier_Top', 'assets/r1/pier_top.png'),
                     ('Source_Pier_Face', 'assets/r1/pier_face.png'),
                     ('Source_Painted_Pier_Backwall', 'assets/r0/port/westile02/image/000.png')]:
    mat = next(m for m in document['materials'] if m['name'] == name)
    index = mat['pbrMetallicRoughness']['baseColorTexture']['index']
    image = document['images'][document['textures'][index]['source']]
    view = document['bufferViews'][image['bufferView']]
    offset = view.get('byteOffset', 0)
    raw = binary[offset:offset + view['byteLength']]
    actual = np.asarray(Image.open(io.BytesIO(raw)).convert('RGBA'))
    expected = np.asarray(Image.open(ROOT / source).convert('RGBA'))
    assert np.array_equal(actual, expected), name
    embedded.append({'material': name, 'exact_rgba': True, 'pixels': actual.shape[0] * actual.shape[1]})
report = {'candidate': 'R1/11', 'checks': records, 'failed': [],
          'raw_rgba_crops': len(records), 'packed_images': len(inspection['images']),
          'mesh_objects': inspection['mesh_objects'], 'manual_blender_scene_untouched': True,
          'source_script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          'source_blend_sha256': inspection['source_blend_sha256'],
          'glb_sha256': hashlib.sha256((ROOT / 'assets/r1/models/west_coast_port.glb').read_bytes()).hexdigest(),
          'embedded_glb_images': embedded, 'nearest_without_mipmaps_samplers': len(document['samplers']),
          'notes': ['Source PNG hashes match the original NPK export manifest.',
                    'Contour measurements and hidden new geometry are interpretations, not recovered game meshes.',
                    'Interactive Blender scene verified separately through read-only MCP; all builds use a new background process.']}
(ROOT / 'docs/r1_11_shore_source_checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k not in ['checks', 'notes']}))
