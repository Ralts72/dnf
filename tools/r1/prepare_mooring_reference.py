"""Retain exact mooring texture crops and explicit placement/depth choices."""
from pathlib import Path
import hashlib
import json
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/dnf_client_analysis'))
from pixel_imports import configure


def main():
    source = ROOT / 'assets/r0/port/westile04/image/000.png'
    image = Image.open(source).convert('RGBA')
    crops = []
    for name, rect in [('dock_wood', (65, 39, 78, 48)), ('dock_metal', (63, 50, 78, 54)),
                       ('dock_rope', (127, 77, 150, 81)), ('dock_stone', (130, 58, 158, 65))]:
        output = ROOT / f'assets/r1/{name}.png'
        image.crop(rect).save(output)
        crops.append({'name': name, 'rect': rect, 'output': output.relative_to(ROOT).as_posix(),
                      'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
                      'operation': 'Exact RGBA crop; no resampling or recoloring'})
    reference = {'candidate': 'R1/10', 'source': source.relative_to(ROOT).as_posix(),
        'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'source_origin': [592, 175],
        'source_manifest': 'docs/r0_asset_manifest.json', 'crops': crops,
        'interior_palette': {'source_pixel': [70, 34], 'rgba': list(image.getpixel((70, 34)))},
        'barrels': [{'name': 'Left', 'ground_center': [653, 270], 'base_y': .025, 'height': .55, 'radius_x': .24, 'radius_z': .16},
                    {'name': 'Right', 'ground_center': [678, 270], 'base_y': .025, 'height': .52, 'radius_x': .205, 'radius_z': .14},
                    {'name': 'Upper', 'ground_center': [663, 267], 'base_y': .575, 'height': .62, 'radius_x': .21, 'radius_z': .12}],
        'mooring': {'ground_center': [734, 259], 'stone_bottom_y': .35, 'stone_height': .18,
                    'stone_radius_x': .35, 'stone_radius_z': .135,
                    'rope_tail_source': [[714, 256], [710, 253], [704, 252], [698, 254], [697, 258], [699, 260], [707, 257]]},
        'near_ship_view_depth_offset': -.95,
        'notes': ['Visible placement follows westile04. Hidden volume, flattened depth and supporting geometry are new interpretation.',
                  'Near ship moves only along the camera ray; its projected source anchor and ANI offsets/timing stay unchanged.',
                  'Native props keep physical ground contact. The image-only ship is placed behind the quay foreground.']}
    (ROOT / 'source_art/r1/mooring_reference.json').write_text(json.dumps(reference, ensure_ascii=False, indent=2) + '\n')
    configure(ROOT)
    print(json.dumps({'crops': len(crops), 'source_size': image.size, 'ship_view_depth_offset': -.95}))


if __name__ == '__main__':
    main()
