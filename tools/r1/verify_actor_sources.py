"""Verify the actor source chain and lossless import profile without a client run."""
from pathlib import Path
import argparse
import hashlib
import json
import re

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return json.loads((ROOT / path).read_text())


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', default='R1/20')
    args = parser.parse_args()
    prefix = args.candidate.lower().replace('/', '_')
    assert re.fullmatch(r'r\d+_\d+', prefix), args.candidate
    manifest = read('docs/r0_asset_manifest.json')
    assert manifest['source_pvf_sha256'] == 'dc0e1acbc98b03b160e9ddb0643efdc7752cdf9c8969937507720a4ca2705c7b'
    assert all(a['crc']['expected'] == a['crc']['actual_seed_file_number'] for a in manifest['animations'])
    assert all(sha(f['texture'].removeprefix('res://')) == f['sha256_png'] for f in manifest['frames'])
    previous = read('source_art/r1/checkpoints/candidate_04/docs/r0_asset_manifest.json')
    current = {f['texture']: f['sha256_png'] for f in manifest['frames']}
    assert all(current[f['texture']] == f['sha256_png'] for f in previous['frames'])
    comparisons = 0
    for actor in ['swordman', 'npc_lo', 'npc_sr']:
        raw = read(f'data/{actor}_r0.json')
        derived = read(f'data/{actor}_r1.json')
        assert set(raw['animations']) == set(derived['animations'])
        anchor = derived['foot_anchor']
        for action, clip in raw['animations'].items():
            assert len(clip['frames']) == len(derived['animations'][action]['frames'])
            for index, frame in enumerate(clip['frames']):
                rebuilt = Image.new('RGBA', tuple(derived['canvas_size']))
                for layer in frame['layers']:
                    image = Image.open(ROOT / layer['texture'].removeprefix('res://')).convert('RGBA')
                    rebuilt.alpha_composite(image, (layer['offset'][0] + anchor[0], layer['offset'][1] + anchor[1]))
                derived_frame = derived['animations'][action]['frames'][index]
                reference = Image.open(ROOT / derived_frame['texture'].removeprefix('res://')).convert('RGBA')
                assert rebuilt.tobytes() == reference.tobytes(), (actor, action, index)
                assert frame['duration_ms'] == derived_frame['duration_ms']
                assert frame['source_properties'] == derived_frame['source_properties']
                assert frame['source_boxes'] == derived_frame['source_boxes']
                comparisons += 1
    profile = read('docs/pixel_import_manifest.json')
    for name in profile['textures']:
        sidecar = (ROOT / (name + '.import')).read_text()
        for key, expected in profile['profile'].items():
            value = re.search(r'^' + re.escape(key) + r'=(.*)$', sidecar, re.MULTILINE)
            assert value and value[1] == expected, (name, key)
    clips = {}
    for name, clip in read('data/swordman_r0.json')['animations'].items():
        frames = clip['frames']
        clips[name] = {'frames': len(frames), 'duration_ms': sum(f['duration_ms'] for f in frames),
                       'long_hold_frames': [i for i, f in enumerate(frames) if f['duration_ms'] >= 10000]}
    report = {'candidate': args.candidate, 'source_pvf_sha256': manifest['source_pvf_sha256'],
              'source_crops_checked': len(manifest['frames']), 'source_ani_crc_checked': len(manifest['animations']),
              'previous_crops_unchanged': len(previous['frames']), 'exact_rgba_composites': comparisons,
              'lossless_import_profiles_checked': profile['texture_count'], 'clips': clips, 'failed': 0,
              'qa_source_sha256': sha('tools/r1/verify_actor_sources.py'),
              'notes': ['Every derivative is reconstructed from R0 layer offsets; exact RGBA bytes are compared.',
                        'Durations, raw properties and boxes are retained without interpreting them as gameplay rules.',
                        'This verifies local files and import settings; native render checks are recorded separately.']}
    (ROOT / ('docs/' + prefix + '_source_checks.json')).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k not in ['clips', 'notes']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
