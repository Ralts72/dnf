"""Read-only independent check of the two normal HopSmash ANI/IMG tracks."""
from pathlib import Path
import hashlib
import json
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/dnf_client_analysis'))
from inspect_clients import PVF, binary_ani, npk_entries, decode_frame


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    client = Path('/Users/mac/Downloads/天堂95起源单机客户端')
    reference = json.loads((ROOT / 'docs/r1_effect_source_reference.json').read_text())
    runtime = json.loads((ROOT / 'data/swordman_effects.json').read_text())
    assert reference['runtime_data_sha256'] == sha((ROOT / 'data/swordman_effects.json').read_bytes())
    assert reference['canonical_npk'] == 'sprite_character_swordman_effect_hopsmash.NPK'
    pvf = PVF(client / 'Script.pvf')
    ani_checks = []
    for record in reference['source_animations']:
        raw, crc = pvf.read(record['path'], True)
        decoded = binary_ani(raw)
        assert sha(raw) == record['sha256'] and crc == record['crc']
        assert crc['expected'] == crc['actual_seed_file_number']
        assert decoded == record['decoded']
        ani_checks.append(record['path'])
    pack = client / 'ImagePacks2' / reference['canonical_npk']
    entries = {e['path']: e for e in npk_entries(pack)}
    images = {}
    crops = {}
    pixels = 0
    with pack.open('rb') as source:
        for crop in reference['source_crops']:
            info = crop['source']
            assert info['npk'] == reference['canonical_npk']
            entry = entries[info['img']]
            assert entry['offset'] == info['npk_entry_offset'] and entry['bytes'] == info['payload_bytes']
            if info['img'] not in images:
                source.seek(entry['offset'])
                payload = source.read(entry['bytes'])
                assert sha(payload) == info['sha256_img_payload']
                images[info['img']] = payload
            original, meta = decode_frame(images[info['img']], crop['img_frame'])
            raw_png = (ROOT / crop['texture'].removeprefix('res://')).read_bytes()
            assert sha(raw_png) == crop['sha256_png']
            current = Image.open(ROOT / crop['texture'].removeprefix('res://')).convert('RGBA')
            assert original.size == current.size and original.tobytes() == current.tobytes()
            assert meta == crop['img_metadata']
            pixels += current.width * current.height
            crops[(info['img'].removeprefix('sprite/'), crop['img_frame'])] = crop
    for track in runtime['actions']['hopsmash']:
        record = next(r for r in reference['source_animations'] if r['path'] == track['source_ani'])
        clock = 0
        assert len(track['frames']) == len(record['decoded']['frames'])
        for actual, frame in zip(track['frames'], record['decoded']['frames']):
            duration = next(p['value'] for p in frame['properties'] if p['type'] == 12)
            assert actual['start_ms'] == clock and actual['duration_ms'] == duration
            assert actual['source_properties'] == frame['properties']
            if frame['resource'] is None:
                assert actual['texture'] is None and actual['offset'] == [frame['x'], frame['y']]
            else:
                crop = crops[(frame['resource'], frame['image_frame'])]
                meta = crop['img_metadata']
                assert actual['texture'] == crop['texture']
                assert actual['offset'] == [frame['x'] + meta['x'], frame['y'] + meta['y']]
            clock += duration
        assert track['duration_ms'] == clock
    body = json.loads((ROOT / 'data/swordman_r0.json').read_text())['animations']['hopsmash']['frames']
    delays = [runtime['actions']['hopsmash'][i]['frames'][0]['duration_ms'] for i in range(2)]
    assert delays == [sum(f['duration_ms'] for f in body[:2]), sum(f['duration_ms'] for f in body[:3])] == [360, 420]
    report = {'candidate': 'R1/19', 'failed': 0, 'source_ani_crc_checked': len(ani_checks),
              'source_npk_images_checked': len(images), 'exact_source_rgba_crops': len(crops),
              'exact_source_rgba_pixels': pixels, 'source_delay_frames_ms': delays,
              'source_reference_sha256': sha((ROOT / 'docs/r1_effect_source_reference.json').read_bytes()),
              'qa_source_sha256': sha(Path(__file__).read_bytes()),
              'notes': reference['interpretation']}
    (ROOT / 'docs/r1_19_effect_source_checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
