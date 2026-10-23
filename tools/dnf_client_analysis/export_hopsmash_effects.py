"""Export only the two normal male Swordman HopSmash visual tracks.

Read source data only. Neither skill scripts nor client programs are executed.
The sample aligns the tracks with the pose clip; engine dispatch is not recovered.
"""
from pathlib import Path
import hashlib
import json

from export_r0 import Exporter, PROJECT, write_json
from pixel_imports import configure


def main():
    client = Path('/Users/mac/Downloads/天堂95起源单机客户端')
    exporter = Exporter(client)
    pack = 'sprite_character_swordman_effect_hopsmash.NPK'
    tracks = []
    for name in ['sword', 'smash']:
        path = f'character/swordman/effect/animation/hopsmash/{name}.ani'
        ani = exporter.ani(path)
        frames = []
        clock = 0
        for frame in ani['frames']:
            duration = next(p['value'] for p in frame['properties'] if p['type'] == 12)
            assert [p['value'] for p in frame['properties'] if p['type'] == 11] == [{'effect': 2}]
            item = {'start_ms': clock, 'duration_ms': duration, 'texture': None,
                    'offset': [frame['x'], frame['y']], 'source_properties': frame['properties']}
            if frame['resource'] is not None:
                image = frame['resource']
                crop = exporter.frame(pack, 'sprite/' + image, frame['image_frame'],
                                      'effects/hopsmash/' + Path(image).stem)
                meta = crop['img_metadata']
                item.update({'texture': crop['texture'],
                             'offset': [frame['x'] + meta['x'], frame['y'] + meta['y']],
                             'image_frame': frame['image_frame']})
            else:
                assert frame['image_frame'] == -1
            frames.append(item)
            clock += duration
        tracks.append({'name': name, 'source_ani': path, 'duration_ms': clock, 'frames': frames})
    data = {'schema': 1, 'actions': {'hopsmash': tracks},
            'blend': 'sample_additive',
            'notes': ['Track offsets, empty delay frames and durations come directly from source ANI.',
                      'The sample starts both tracks at pose time zero. Original engine attachment/dispatch is not recovered.',
                      'Source type 11 effect value 2 is retained. Godot additive rendering is the sample interpretation.',
                      'No berserker shockwave, damage, movement or sound dispatch is added.']}
    write_json(PROJECT / 'data/swordman_effects.json', data)
    reference = {'client': '95', 'canonical_npk': pack,
                 'source_pvf_sha256': json.loads((PROJECT / 'docs/r0_asset_manifest.json').read_text())['source_pvf_sha256'],
                 'source_animations': list(exporter.scripts.values()),
                 'source_crops': list(exporter.frames.values()),
                 'runtime_data_sha256': hashlib.sha256((PROJECT / 'data/swordman_effects.json').read_bytes()).hexdigest(),
                 'interpretation': data['notes']}
    write_json(PROJECT / 'docs/r1_effect_source_reference.json', reference)
    configure(PROJECT)
    print('Exported', len(tracks), 'tracks and', len(exporter.frames), 'unaltered source crops.')


if __name__ == '__main__':
    main()
