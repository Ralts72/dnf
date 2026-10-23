"""Verify the stall color policy and compare actual GLB geometry to candidate 14."""
from pathlib import Path
import hashlib
import io
import json
import struct
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
BASELINE = ROOT / 'source_art/r1/checkpoints/candidate_14'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def glb(path):
    raw = path.read_bytes()
    cursor, document, binary = 12, None, None
    while cursor < len(raw):
        length, kind = struct.unpack_from('<II', raw, cursor)
        cursor += 8
        payload = raw[cursor:cursor + length]
        cursor += length
        if kind == 0x4e4f534a:
            document = json.loads(payload)
        elif kind == 0x004e4942:
            binary = payload
    assert document and binary
    return document, binary


def accessor(document, binary, index):
    item = document['accessors'][index]
    view = document['bufferViews'][item['bufferView']]
    dtype = {5120: 'i1', 5121: 'u1', 5122: '<i2', 5123: '<u2',
             5125: '<u4', 5126: '<f4'}[item['componentType']]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[item['type']]
    size = np.dtype(dtype).itemsize
    return np.ndarray((item['count'], width), dtype=dtype, buffer=binary,
                      offset=view.get('byteOffset', 0) + item.get('byteOffset', 0),
                      strides=(view.get('byteStride', width * size), size)).copy()


def embedded(document, binary, texture_index):
    texture = document['textures'][texture_index]
    image = document['images'][texture['source']]
    view = document['bufferViews'][image['bufferView']]
    start = view.get('byteOffset', 0)
    pixels = np.asarray(Image.open(io.BytesIO(binary[start:start + view['byteLength']])).convert('RGBA'))
    return pixels, document['samplers'][texture['sampler']]


def material_value(document, binary, value):
    if isinstance(value, dict):
        result = {}
        for key, child in value.items():
            if key.endswith('Texture') and isinstance(child, dict) and 'index' in child:
                pixels, sampler = embedded(document, binary, child['index'])
                result[key] = dict(child, index={'rgba_sha256': hashlib.sha256(pixels.tobytes()).hexdigest(),
                                                'size': list(pixels.shape), 'sampler': sampler})
            else:
                result[key] = material_value(document, binary, child)
        return result
    return value


source = ROOT / 'assets/r0/port/westmobj00/image/000.png'
source_manifest = json.loads((ROOT / 'docs/r0_asset_manifest.json').read_text())
frame = next(f for f in source_manifest['frames'] if f['texture'] == 'res://' + source.relative_to(ROOT).as_posix())
assert sha(source) == frame['sha256_png']
old, old_bin = glb(BASELINE / 'assets/r1/models/west_coast_port.glb')
current_path = ROOT / 'assets/r1/models/west_coast_port.glb'
current, current_bin = glb(current_path)
paint = next(m for m in current['materials'] if m['name'] == 'Source_Painted_Stall')
assert paint['alphaMode'] == 'MASK' and paint['alphaCutoff'] == .25
assert 'KHR_materials_unlit' in paint.get('extensions', {})
actual, sampler = embedded(current, current_bin, paint['pbrMetallicRoughness']['baseColorTexture']['index'])
expected = np.asarray(Image.open(source).convert('RGBA'))
assert np.array_equal(actual, expected)
assert sampler['minFilter'] == sampler['magFilter'] == 9728
old_meshes = {m['name']: m for m in old['meshes']}
new_meshes = {m['name']: m for m in current['meshes']}
barrel_node = next(n for n in old['nodes'] if n['name'] == 'Stall_Left_Barrel')
barrel_mesh = old['meshes'][barrel_node['mesh']]['name']
assert old_meshes.keys() == new_meshes.keys()
positions, uv_pairs, triangles = 0, 0, 0
omitted_attributes = []
for name, mesh in new_meshes.items():
    before = old_meshes[name]
    assert len(before['primitives']) == len(mesh['primitives'])
    for a, b in zip(before['primitives'], mesh['primitives']):
        assert a.get('mode', 4) == b.get('mode', 4) == 4
        old_mat = old['materials'][a['material']]['name']
        new_mat = current['materials'][b['material']]['name']
        assert old_mat == new_mat
        ai = accessor(old, old_bin, a['indices'])
        bi = accessor(current, current_bin, b['indices'])
        assert np.array_equal(ai, bi), (name, 'indices')
        triangles += len(bi) // 3
        for attr, index in a['attributes'].items():
            if name == barrel_mesh and attr == 'TEXCOORD_0':
                index = a['attributes']['TEXCOORD_1']
            if attr not in b['attributes']:
                assert new_mat == 'Source_Painted_Stall' and attr in ['NORMAL', 'TANGENT']
                omitted_attributes.append({'mesh': name, 'attribute': attr})
                continue
            before_array = accessor(old, old_bin, index)
            after_array = accessor(current, current_bin, b['attributes'][attr])
            assert np.array_equal(before_array, after_array), (name, attr)
            if attr == 'POSITION': positions += len(after_array)
            if attr == 'TEXCOORD_0': uv_pairs += len(after_array)
        assert not (b['attributes'].keys() - a['attributes'].keys())
# Object transforms, hierarchy and mesh bindings must stay identical too.
assert old['nodes'] == current['nodes'] and old['scenes'] == current['scenes']
assert old_bin == current_bin
old_mats = {m['name']: material_value(old, old_bin, m) for m in old['materials']}
new_mats = {m['name']: material_value(current, current_bin, m) for m in current['materials']}
assert old_mats.keys() == new_mats.keys()
changed = [name for name in old_mats if old_mats[name] != new_mats[name]]
assert changed == ['Source_Painted_Stall'], changed
report = {'candidate': 'R1/15', 'baseline': 'R1/14', 'failed': [],
          'source_png_sha256': sha(source), 'source_frame': frame,
          'embedded_rgba_pixels': actual.shape[0] * actual.shape[1], 'exact_source_rgba': True,
          'alpha_cutoff': .25, 'unlit': True, 'nearest_without_mipmaps': True,
          'meshes': len(new_meshes), 'positions_compared': positions, 'uv_pairs_compared': uv_pairs,
          'triangles_compared': triangles, 'node_transforms_and_hierarchy_unchanged': True,
          'materials_changed': changed, 'unused_attributes_omitted_by_exporter': omitted_attributes,
          'barrel_uv0_uses_existing_projected_uv1': True,
          'complete_binary_chunk_identical': True,
          'glb_sha256': sha(current_path), 'source_script_sha256': sha(Path(__file__)),
          'lossless_import_sidecar': 'assets/r1/models/west_coast_port_000_18.png.import',
          'lossless_import_sha256': sha(ROOT / 'assets/r1/models/west_coast_port_000_18.png.import'),
          'note': 'Positions, indices, transforms and source colors stay exact. Stall shading and the barrel UV binding are corrected; projected UV values stay exact.'}
(ROOT / 'docs/r1_15_stall_source_checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k != 'source_frame'}, ensure_ascii=False))
