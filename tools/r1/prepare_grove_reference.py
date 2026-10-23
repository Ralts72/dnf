"""Extract the grove's source pixels and record the new geometry mapping.

The canopy mask selects existing pixels; retained RGB and alpha are untouched.
Hidden foliage, trunks and wall depth are interpretations for the fixed camera.
"""
from pathlib import Path
import hashlib
import json
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/dnf_client_analysis'))
from pixel_imports import configure


def main():
    source = ROOT / 'assets/r0/port/westile01/image/000.png'
    image = Image.open(source).convert('RGBA')
    crops = []
    for name, rect in [('grove_bark', (90, 149, 103, 197)),
                       ('grove_plaster', (108, 149, 134, 194)),
                       ('grove_path', (184, 185, 224, 211)),
                       ('grove_grass', (109, 201, 133, 209))]:
        output = ROOT / f'assets/r1/{name}.png'
        image.crop(rect).save(output)
        crops.append({'name': name, 'rect': rect, 'output': output.relative_to(ROOT).as_posix(),
                      'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
                      'operation': 'Exact rectangular RGBA crop; no resampling or color changes'})
    rect = (0, 0, 224, 140)
    raw = np.asarray(image.crop(rect)).copy()
    r, g, b = (raw[:, :, i].astype(np.float32) for i in range(3))
    yy, xx = np.indices(raw.shape[:2])
    green = (g > r * 1.12) & (g > b * .88) & (g > 35)
    dark_foliage = (r < 125) & (g < 125) & (b < 125) & (b > r * 1.05)
    keep = (yy < 90) | green | dark_foliage
    keep &= raw[:, :, 3] > 0
    output = raw.copy()
    output[~keep, 3] = 0
    target = ROOT / 'assets/r1/grove_canopy.png'
    Image.fromarray(output).save(target)
    reference = {'candidate': 'R1/09', 'source': source.relative_to(ROOT).as_posix(),
        'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'source_origin': [225, -42], 'source_manifest': 'docs/r0_asset_manifest.json',
        'crops': crops, 'canopy': {'rect': rect, 'output': target.relative_to(ROOT).as_posix(),
            'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
            'retained_pixels': int(keep.sum()), 'removed_opaque_pixels': int(((raw[:, :, 3] > 0) & ~keep).sum()),
            'mask_rule': 'y<90, otherwise green or blue-shadow foliage; preserve selected RGBA, set only removed alpha to zero',
            'green_rule': 'g>1.12*r and g>0.88*b and g>35',
            'shadow_rule': 'r,g,b<125 and b>1.05*r'},
        'geometry': {'root_height': .11, 'root_source_y': 167,
            'trees': [{'name': 'Left', 'foot': [247, 167], 'radius': .10, 'top_y': 43},
                      {'name': 'Middle', 'foot': [320, 167], 'radius': .125, 'top_y': 72},
                      {'name': 'Right', 'foot': [373, 167], 'radius': .11, 'top_y': 85}],
            'bed_source_bounds': [290, 155, 402, 171],
            'connection_source_bounds': [410, 130, 449, 190],
            'wall_front_source_bounds': [270, 84, 411, 158],
            'wall_return_source_points': [[411, 158], [449, 130]]},
        'notes': ['RGB is never synthesized or repainted; the canopy cutout mask is an explicit inferred selection.',
                  'Canopy stays source art on a native 3D surface. Trunks, branches, bed, wall and connecting path are new meshes.',
                  'The canopy depth, hidden wall profile and tree volumes are new interpretation; no new navigation is opened.']}
    (ROOT / 'source_art/r1/grove_reference.json').write_text(json.dumps(reference, ensure_ascii=False, indent=2) + '\n')
    configure(ROOT)
    print(json.dumps({'crops': len(crops), 'canopy_retained_pixels': int(keep.sum()), 'source_size': image.size}))


if __name__ == '__main__':
    main()
