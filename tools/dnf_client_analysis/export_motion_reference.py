"""Read the source jump references and create an explicit, adjustable mapping.

No client code is executed. Existing runtime tuning is preserved unless
--write-defaults is supplied; source evidence is always refreshed.
"""
from pathlib import Path
import argparse
import hashlib
import json

from inspect_clients import PVF, binary_ani

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path, default=Path('/Users/mac/Downloads/天堂95起源单机客户端'))
    parser.add_argument('--write-defaults', action='store_true')
    args = parser.parse_args()
    pvf = PVF(args.client / 'Script.pvf')
    digest = hashlib.sha256()
    with (args.client / 'Script.pvf').open('rb') as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            digest.update(chunk)
    pvf_sha = digest.hexdigest()
    assert pvf_sha == json.loads((ROOT / 'docs/r0_asset_manifest.json').read_text())['source_pvf_sha256']
    assert pvf.header['tree_crc_expected'] == pvf.header['tree_crc_actual']
    assert not pvf.header['parse_error'] and not pvf.header['payload_bounds_errors']
    sources = {}
    paths = ['character/swordman/swordman.chr', 'character/swordman/animation/jump.ani',
             'character/swordman/animation/jumpattack.ani']
    for path in paths:
        raw, crc = pvf.read(path, True)
        assert crc['expected'] == crc['actual_seed_file_number'], path
        sources[path] = {'sha256': hashlib.sha256(raw).hexdigest(), 'crc': crc}
        if path.endswith('.ani'):
            sources[path]['decoded'] = binary_ani(raw)
    tokens = pvf.tokens(paths[0], 'big5')
    fields = {}
    for label in ['[jump power]', '[jump speed]', '[weight]']:
        index = next(i for i, token in enumerate(tokens) if token.get('text', '').lower() == label)
        fields[label] = tokens[index + 1]['value']
    jump = sources[paths[1]]['decoded']['frames']
    holds = [i for i, frame in enumerate(jump)
             if next(p['value'] for p in frame['properties'] if p['type'] == 12) >= 10000]
    assert holds == [7, 14] and len(jump) == 16
    durations = [next(p['value'] for p in f['properties'] if p['type'] == 12) for f in jump]
    ascent_seconds = sum(durations[1:7]) / 1000.0
    descent_seconds = sum(durations[8:14]) / 1000.0
    assert ascent_seconds == descent_seconds == .5
    mapping = {'takeoff_speed_px_s': fields['[jump power]'],
               'gravity_px_s2': fields['[jump power]'] / ascent_seconds,
               'air_move_speed_px_s': fields['[jump speed]'], 'run_jump_multiplier': 1.9,
               'takeoff_frame': 0, 'rising_frames': [1, 7], 'falling_frames': [8, 14], 'landing_frame': 15}
    notes = ['CHR values and ANI bytes are source evidence; their original engine unit conversion is not recovered.',
             'This sample maps jump power to vertical screen pixels/second and jump speed to air travel pixels/second.',
             'Gravity is chosen so the apex follows the 500ms finite ascent; prep/landing keep source frame durations.',
             'The phase partition is inferred from the pose sequence and its two hold frames.',
             'Ground navigation and height remain independent, matching the sample\'s fixed-view 2.5D model.']
    reference = {'source_pvf': str(args.client / 'Script.pvf'), 'source_pvf_sha256': pvf_sha,'source_fields': fields,
                 'sources': sources, 'hold_frames': holds, 'ascent_seconds': ascent_seconds,
                 'descent_seconds': descent_seconds, 'default_mapping': mapping, 'notes': notes}
    (ROOT / 'docs/r1_jump_source_reference.json').write_text(json.dumps(reference, ensure_ascii=False, indent=2) + '\n')
    runtime = ROOT / 'data/swordman_motion.json'
    if not runtime.exists() or args.write_defaults:
        runtime.write_text(json.dumps({'schema': 1, 'mapping': mapping,
                                       'source_reference': 'docs/r1_jump_source_reference.json',
                                       'notes': notes}, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'source_fields': fields, 'ascent_seconds': ascent_seconds,
                      'default_mapping': mapping, 'runtime_tuning': str(runtime)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
