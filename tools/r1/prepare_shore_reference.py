"""Retain explicit shoreline measurements and exact, prop-free source crops."""
from pathlib import Path
import hashlib
import json
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/dnf_client_analysis'))
from pixel_imports import configure


def main():
    source = ROOT / 'assets/r0/port/westile03/image/000.png'
    image = Image.open(source)
    crops = []
    for name, rect in [('quay_coping', (130, 101, 224, 119)),
                       ('pier_top', (4, 29, 104, 36)), ('pier_face', (4, 40, 104, 57))]:
        target = ROOT / f'assets/r1/{name}.png'
        image.crop(rect).save(target)
        crops.append({'name': name, 'source': source.relative_to(ROOT).as_posix(),
                      'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                      'rect': rect, 'output': target.relative_to(ROOT).as_posix(),
                      'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                      'operation': 'Exact rectangular RGBA crop; no resampling, recoloring or repair'})
    ref = {'candidate': 'R1/08', 'source_manifest': 'docs/r0_asset_manifest.json',
           'measurements': {'source02_origin': [449, 84], 'source03_origin': [673, 148],
               'near_shore_outer_pixels': [[449, 190], [673, 254], [958, 254]],
               'coping_width_source_pixels': 14,
               'far_piers': [{'name': 'Far', 'bounds': [510, 135, 958, 153]},
                             {'name': 'Middle', 'bounds': [510, 175, 958, 187]}],
               'lamps': [{'name': 'FarSmall0', 'foot': [495, 141], 'top_y': 99},
                         {'name': 'FarSmall1', 'foot': [564, 141], 'top_y': 99},
                         {'name': 'FarSmall2', 'foot': [592, 148], 'top_y': 110},
                         {'name': 'Middle0', 'foot': [509, 188], 'top_y': 99},
                         {'name': 'Middle1', 'foot': [546, 178], 'top_y': 100},
                         {'name': 'Near', 'foot': [636, 253], 'top_y': 117}]},
           'source_images': [{'path': f'assets/r0/port/{name}/image/000.png',
               'sha256': hashlib.sha256((ROOT / f'assets/r0/port/{name}/image/000.png').read_bytes()).hexdigest()}
               for name in ['westile02', 'westile03']], 'texture_crops': crops,
           'notes': ['Visible source contours are manually measured. Hidden pier extent, depths and lamp volumes are new geometry.',
                     'Far piers extend beneath the retained foreground ship; no new navigation area is opened.',
                     'Swatches exclude baked sacks, barrels and lamps; source props are not painted onto new slabs.']}
    (ROOT / 'source_art/r1/shore_reference.json').write_text(json.dumps(ref, ensure_ascii=False, indent=2) + '\n')
    configure(ROOT)
    print('Measured shore contours; retained three exact source texture crops.')


if __name__ == '__main__':
    main()
