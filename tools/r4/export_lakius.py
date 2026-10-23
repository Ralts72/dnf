"""Export ID71 Lakius/魯卡斯 source pictures, clocks and contact sounds only.

Writes new R4 assets/data/reference evidence. Client PVF/NPK/IMG are read as
data; no client code, Godot, Blender or original AI is executed. The ten source
actions stay distinct, including AttackLong and AttackHeart.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import shutil
import sys
import xml.etree.ElementTree as ET

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/dnf_client_analysis'))
from inspect_clients import PVF, npk_entries, img_frames, decode_frame, binary_ani
from pixel_imports import PROFILE
from export_audio import packets, normalize_comments
sys.path.insert(0, str(ROOT / 'tools/r3'))
from export_draconian_audio import page_audit, decoded_audio

PACK = 'sprite_monster_draconian.NPK'
IMG = 'sprite/monster/draconian/draco_lakius.img'
MOB = 'monster/draconian/lakius.mob'
SOURCE = ROOT / 'source_art/r4/lakius'
ASSETS = ROOT / 'assets/r4/lakius'
ACTIONS = {'stay': 'stay', 'move': 'movefoward', 'attack1': 'attack',
           'damage1': 'damage1', 'damage2': 'damage2', 'down': 'down',
           'moveback': 'moveback', 'sit': 'sit', 'attacklong': 'attacklong',
           'attackheart': 'attackheart'}
CONTACT_TAGS = {'attack1': 'KNIFE_HIT', 'attackheart': 'SLASH_HIT_03',
                'attacklong': 'SPEAR_HIT'}
CANVAS = [362, 202]
ANCHOR = [134, 153]
MARGIN = 8
INSPECTOR_HOLD_MS = 10000


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def file_sha(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def source_record(pvf, path, decoded):
    raw, crc = pvf.read(path, True)
    assert crc['expected'] == crc['actual_seed_file_number'], path
    target = SOURCE / 'pvf' / path
    target.parent.mkdir(parents=True, exist_ok=True)
    original = target.with_suffix(target.suffix + '.bin')
    original.write_bytes(raw)
    assert original.read_bytes() == raw
    reference = target.with_suffix(target.suffix + '.json')
    result = {'path': path, 'bytes': len(raw), 'sha256_decoded_bytes': sha(raw),
              'crc': crc, 'crc_matches': True,
              'original_reference': original.relative_to(ROOT).as_posix(),
              'decoded_reference': reference.relative_to(ROOT).as_posix()}
    write_json(reference, {**result, 'decoded': decoded})
    return result


def section(tokens, name):
    start = next(i for i, token in enumerate(tokens) if token.get('text', '').lower() == name)
    end = next((i for i in range(start + 1, len(tokens)) if tokens[i]['type'] == 5), len(tokens))
    return tokens[start:end]


def list_selection(pvf, path, predicate):
    tokens = pvf.tokens(path, 'big5')
    return [item for left, right in zip(tokens[::2], tokens[1::2])
            if predicate(left, right) for item in [left, right]]


def texture(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    with Image.open(path) as saved:
        assert saved.mode == 'RGBA' and saved.size == image.size
        assert saved.tobytes() == image.tobytes(), path
    # Configure only our69 new PNGs. Preserve native importer metadata on reruns.
    sidecar = path.with_suffix('.png.import')
    previous = sidecar.read_text() if sidecar.exists() else ''
    text = previous or ('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
                        '[deps]\n\nsource_file="res://' + path.relative_to(ROOT).as_posix()
                        + '"\n\n[params]\n')
    assert '[params]' in text
    for key, value in PROFILE.items():
        pattern = r'^' + re.escape(key) + r'=.*$'
        if re.search(pattern, text, re.MULTILINE):
            text = re.sub(pattern, key + '=' + value, text, flags=re.MULTILINE)
        else:
            text = text.rstrip() + '\n' + key + '=' + value + '\n'
    if text != previous:
        sidecar.write_text(text)
    return {'texture': 'res://' + path.relative_to(ROOT).as_posix(),
            'size': list(image.size), 'sha256_png': file_sha(path),
            'sha256_rgba': sha(image.tobytes()),
            'alpha_range': list(image.getchannel('A').getextrema()),
            'import_sidecar': sidecar.relative_to(ROOT).as_posix()}


def export_audio(client, pvf, scripts):
    ffmpeg, ffprobe = shutil.which('ffmpeg'), shutil.which('ffprobe')
    assert ffmpeg and ffprobe, 'Local ffmpeg/ffprobe required for PCM byte comparison'
    xml_raw = (client / 'audio.xml').read_bytes()
    tags = {node.attrib['ID']: node for node in ET.fromstring(xml_raw) if 'ID' in node.attrib}
    archive = SOURCE / 'audio'
    archive.mkdir(parents=True, exist_ok=True)
    (archive / 'audio.xml.bin').write_bytes(xml_raw)
    pack = 'sounds_effect.npk'
    pack_path = client / 'SoundPacks' / pack
    entries = {entry['path']: entry for entry in npk_entries(pack_path, False)}
    sounds = {}
    for action, tag in CONTACT_TAGS.items():
        source_action = ACTIONS[action]
        atk = 'monster/draconian/dlattackinfo/' + source_action + '.atk'
        tokens = pvf.tokens(atk, 'big5')
        hits = [tokens[i + 1]['text'] for i, token in enumerate(tokens[:-1])
                if token.get('text', '').lower() == '[hit wav]']
        assert hits == [tag], (atk, hits)
        attributes = dict(tags[tag].attrib)
        entry_path = attributes['FILE'].replace('\\', '/').lower()
        entry = entries[entry_path]
        with pack_path.open('rb') as stream:
            stream.seek(entry['offset'])
            raw = stream.read(entry['bytes'])
        assert raw.startswith(b'OggS')
        original = archive / (tag.lower() + '.ogg')
        original.write_bytes(raw)
        fixed, proof = normalize_comments(raw)
        if tag == 'SPEAR_HIT':
            runtime = ROOT / 'assets/r3/audio/spear_hit.ogg'
            assert runtime.read_bytes() == fixed, 'Existing spear asset must match canonical normalized bytes'
        else:
            runtime = ASSETS / 'audio' / (tag.lower() + '.ogg')
            runtime.parent.mkdir(parents=True, exist_ok=True)
            runtime.write_bytes(fixed)
        assert original.read_bytes() == raw
        before_pages, after_pages = page_audit(raw), page_audit(fixed)
        assert before_pages == after_pages
        before_packets, after_packets = packets(raw), packets(fixed)
        assert len(before_packets) == len(after_packets)
        assert all(left == right for i, (left, right) in enumerate(zip(before_packets, after_packets)) if i != 1)
        source_pcm, source_decoded = decoded_audio(original, ffmpeg, ffprobe)
        runtime_pcm, runtime_decoded = decoded_audio(runtime, ffmpeg, ffprobe)
        assert source_pcm == runtime_pcm
        sounds[tag] = {'path': 'res://' + runtime.relative_to(ROOT).as_posix(),
                       'reused_existing_runtime': tag == 'SPEAR_HIT',
                       'source_binding': {'action': action, 'atk': atk, 'hit_wav': tag,
                                          'atk_sha256': next(item['sha256_decoded_bytes'] for item in scripts if item['path'] == atk)},
                       'npk': pack, 'entry': entry_path, 'entry_offset': entry['offset'],
                       'source_bytes': len(raw), 'sha256_source_ogg': sha(raw),
                       'original_reference': original.relative_to(ROOT).as_posix(),
                       'runtime_bytes': len(fixed), 'sha256_runtime_ogg': sha(fixed),
                       'xml_attributes': attributes, 'metadata_fix': proof,
                       'ogg_pages': before_pages, 'all_page_crcs_valid': True,
                       'noncomment_packets_identical': True,
                       'granule_serial_sequence_flags_identical': True,
                       'source_pcm': source_decoded, 'runtime_pcm': runtime_decoded,
                       'decoded_pcm_byte_identical': True}
    notes = ['Only3 direct ATK contact tags are resolved. Play on a real successful contact; no original native-engine dispatch/timing is claimed.',
             'AttackLong/SPEAR_HIT is retained as a source reference; the first boss pattern uses Attack/AttackHeart only.',
             'Attack, hurt and death family voices remain unbound; no voice event is invented.',
             'One bare Vorbis comment is prefixed COMMENT= and its page CRC updated. Identification/setup/audio packets, timing headers and decoded float32 PCM are unchanged.',
             'Existing R3 SPEAR_HIT runtime bytes are verified and reused without rewriting that asset.']
    runtime_data = {'schema': 1, 'monster_id': 71,
                    'sounds': {tag: {'path': item['path']} for tag, item in sounds.items()},
                    'contact_tags': CONTACT_TAGS, 'normal_audio': 'KNIFE_HIT',
                    'heavy_audio': 'SLASH_HIT_03',
                    'source_roles': {'attack_voice': None, 'hurt_voice': None, 'death_voice': None},
                    'runtime_hooks_implemented': False,
                    'source_reference': 'docs/r4_lakius_source_reference.json', 'notes': notes}
    write_json(ROOT / 'data/lakius_audio.json', runtime_data)
    return {'audio_xml_sha256': sha(xml_raw),
            'audio_xml_original_reference': (archive / 'audio.xml.bin').relative_to(ROOT).as_posix(),
            'canonical_npk': {'path': str(pack_path), 'sha256': file_sha(pack_path)},
            'sounds': sounds, 'runtime_data': 'data/lakius_audio.json',
            'runtime_data_sha256': file_sha(ROOT / 'data/lakius_audio.json'),
            'reader_helpers': {'path': 'tools/r3/export_draconian_audio.py',
                               'sha256': file_sha(ROOT / 'tools/r3/export_draconian_audio.py')}, 'notes': notes}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path, default=Path('/Users/mac/Downloads/天堂95起源单机客户端'))
    args = parser.parse_args()
    client = args.client
    pvf = PVF(client / 'Script.pvf')
    assert pvf.header['tree_crc_actual'] == pvf.header['tree_crc_expected']
    assert not pvf.header['payload_bounds_errors'] and not pvf.header['parse_error']
    pack_path = client / 'ImagePacks2' / PACK
    entry = next(item for item in npk_entries(pack_path) if item['path'] == IMG)
    with pack_path.open('rb') as stream:
        stream.seek(entry['offset'])
        raw_img = stream.read(entry['bytes'])
    table, _palette = img_frames(raw_img)
    img_archive = SOURCE / 'img/draco_lakius.img.bin'
    img_archive.parent.mkdir(parents=True, exist_ok=True)
    img_archive.write_bytes(raw_img)
    assert img_archive.read_bytes() == raw_img
    image_source = {'client': '95', 'npk': PACK, 'npk_sha256': file_sha(pack_path),
                    'img': IMG, 'npk_entry_offset': entry['offset'], 'payload_bytes': len(raw_img),
                    'sha256_img_payload': sha(raw_img), 'img_version': entry['version'],
                    'img_total_frames': len(table),
                    'original_reference': img_archive.relative_to(ROOT).as_posix(),
                    'selection': 'Explicit canonical NPK; patch/overlay precedence not inferred.'}
    write_json(SOURCE / 'img/source_reference.json', image_source)
    scripts, crops, images, animations = [], {}, {}, {}
    bounds, composite_records = [], []
    missing_source_durations = []
    for key, source_action in ACTIONS.items():
        path = 'monster/draconian/dlani/' + source_action + '.ani'
        raw, crc = pvf.read(path, True)
        assert crc['expected'] == crc['actual_seed_file_number']
        ani = binary_ani(raw)
        assert ani['resources'] == [IMG.removeprefix('sprite/')]
        assert not any(prop['type'] == 16 for prop in ani['globals'] + sum([f['properties'] for f in ani['frames']], []))
        scripts.append(source_record(pvf, path, ani))
        animation = {'source_ani': path, 'source_action': source_action,
                     'source_sha256': sha(raw), 'source_globals': ani['globals'],
                     'source_resources': ani['resources'], 'source_frames_count': ani['frames_count'],
                     'frames': []}
        for i, source_frame in enumerate(ani['frames']):
            index = source_frame['image_frame']
            if index not in crops:
                image, metadata = decode_frame(raw_img, index)
                resolved, seen = index, set()
                while 'link' in table[resolved]:
                    assert resolved not in seen
                    seen.add(resolved)
                    resolved = table[resolved]['link']
                images[index] = image
                crops[index] = {**texture(image, ASSETS / 'source' / f'{index:03d}.png'),
                                'img_frame': index, 'resolved_img_frame': resolved,
                                'img_metadata': metadata,
                                'export': 'Exact decoded source RGBA crop including transparent RGB; no pixel edits, scaling or canvas reconstruction.'}
            image, crop = images[index], crops[index]
            metadata = crop['img_metadata']
            offset = [source_frame['x'] + metadata['x'], source_frame['y'] + metadata['y']]
            bounds.append([offset[0], offset[1], offset[0] + image.width, offset[1] + image.height])
            paste = [ANCHOR[0] + offset[0], ANCHOR[1] + offset[1]]
            assert paste[0] >= MARGIN and paste[1] >= MARGIN
            assert paste[0] + image.width <= CANVAS[0] - MARGIN
            assert paste[1] + image.height <= CANVAS[1] - MARGIN
            fixed = Image.new('RGBA', CANVAS, (0, 0, 0, 0))
            # Pillow expands a mutable two-value paste box in place; pass a
            # tuple so the recorded source offset remains exactly[x,y].
            fixed.paste(image, tuple(paste))  # Unmasked RGBA copy retains RGB under alpha0.
            rect = [paste[0], paste[1], paste[0] + image.width, paste[1] + image.height]
            assert fixed.crop(rect).tobytes() == image.tobytes()
            duration = next((prop['value'] for prop in source_frame['properties'] if prop['type'] == 12), None)
            if duration is None:
                missing_source_durations.append({'action': key, 'frame': i})
            result = {**texture(fixed, ASSETS / 'frames' / key / f'{i:03d}.png'),
                      'duration_ms': duration if duration is not None else INSPECTOR_HOLD_MS,
                      'source_duration_ms': duration,
                      'duration_origin': 'Original source ANI property12' if duration is not None else 'Static inspector hold only; source duration missing, not gameplay hitstun',
                      'img_frame': index, 'resolved_img_frame': crop['resolved_img_frame'],
                      'ani_offset': [source_frame['x'], source_frame['y']], 'img_metadata': metadata,
                      'logical_crop_offset': offset, 'composite_paste_offset': paste,
                      'source_crop': crop['texture'], 'source_crop_rgba_sha256': crop['sha256_rgba'],
                      'source_properties': source_frame['properties'], 'source_boxes': source_frame['boxes'],
                      'derived_artifact': True,
                      'composition': 'Exact unmasked source RGBA crop on fixed transparent canvas; no resampling or color edits.'}
            animation['frames'].append(result)
            composite_records.append({'action': key, 'frame': i, **result})
        animations[key] = animation
    logical_bounds = [min(b[0] for b in bounds), min(b[1] for b in bounds),
                      max(b[2] for b in bounds), max(b[3] for b in bounds)]
    assert [logical_bounds[2] - logical_bounds[0] + 2 * MARGIN,
            logical_bounds[3] - logical_bounds[1] + 2 * MARGIN] == CANVAS
    assert [-logical_bounds[0] + MARGIN, -logical_bounds[1] + MARGIN] == ANCHOR
    assert len(crops) == 32 and len(composite_records) == 37 and len(animations) == 10

    scripts.append(source_record(pvf, MOB, pvf.tokens(MOB, 'big5')))
    for action in ['attack', 'attackheart', 'attacklong']:
        path = 'monster/draconian/dlattackinfo/' + action + '.atk'
        scripts.append(source_record(pvf, path, pvf.tokens(path, 'big5')))
    selected_monster = list_selection(pvf, 'monster/monster.lst', lambda left, right: left.get('value') == 71)
    assert selected_monster[1]['text'].lower() == 'draconian/lakius.mob'
    scripts.append(source_record(pvf, 'monster/monster.lst', {'selection': 'ID71 only; complete bytes retained', 'tokens': selected_monster}))
    dictionary_pair = list_selection(pvf, 'n_string.lst', lambda left, right: left.get('value') == 7)
    assert dictionary_pair[1]['text'].lower() == 'monster/monster.kor.str'
    scripts.append(source_record(pvf, 'n_string.lst', {'selection': 'Dictionary7; complete bytes retained', 'tokens': dictionary_pair}))
    dictionary = pvf.read('monster/monster.kor.str').decode('big5', 'strict')
    assert 'name_525>魯卡斯' in dictionary.splitlines()
    scripts.append(source_record(pvf, 'monster/monster.kor.str', {'encoding': 'Big5', 'name_key': 'name_525', 'source_name': '魯卡斯'}))
    map_pairs = list_selection(pvf, 'map/map.lst', lambda left, right: right.get('text', '').lower() in ['draconiantower/(0,2)b1823.map', 'draconiantower/(3,2)b1823.map'])
    scripts.append(source_record(pvf, 'map/map.lst', {'selection': 'Two source boss-map references; complete bytes retained', 'tokens': map_pairs}))
    boss_rows = []
    for path in ['map/draconiantower/(0,2)b1823.map', 'map/draconiantower/(3,2)b1823.map']:
        tokens = section(pvf.tokens(path, 'big5'), '[monster]')[1:]
        values = [token.get('text', token.get('value')) for token in tokens]
        rows = [values[i:i + 10] for i in range(0, len(values), 10)]
        selected = [row for row in rows if row[0] == 71]
        assert len(selected) == 1 and selected[0][-1] == '[boss]'
        boss_rows.append({'path': path, 'source_monster_row': selected[0]})
        scripts.append(source_record(pvf, path, {'selection': 'ID71 row from [monster]; complete bytes retained', 'rows': selected}))
    audio = export_audio(client, pvf, scripts)
    notes = ['ID71 Lakius resolves Big5 name_525 to魯卡斯; simplified鲁卡斯 is a display conversion. Source maps explicitly mark ID71 [boss].',
             'ID55023 Tower_Lakius is a distinct death-tower variant and is not exported.',
             'All10 canonical source action names remain distinct. No hero dash/attack2/attack3 aliases or copied master records are added.',
             'Original ANI clocks, XYZ boxes, offsets, indices and property values are retained. Down includes original10000ms holds; no original death controller is claimed.',
             'Damage1/2 source duration is missing; duration_ms10000 is an inspector-only fallback and source_duration_ms stays null.',
             'Fixed canvas frames are derived transparent padding plus exact RGBA copies. Raw crops and original IMG payload remain available.',
             'No armor overlay, lightning, shield, cage, hallucination or unbound family voice is silently added. The source MOB lists more motions than this bounded whitelist.',
             'HP, damage, AI, reaction, guard/armor, state persistence and route layout are new runtime adaptations outside this asset exporter.',
             'No Godot, Blender, source client binary, ACT/SKL interpreter or internet service is run.']
    data = {'schema': 1, 'character': 'lakius', 'monster_id': 71, 'name': '鲁卡斯',
            'source_name_big5': '魯卡斯', 'canvas_size': CANVAS, 'foot_anchor': ANCHOR,
            'animations': animations, 'source_data': 'docs/r4_lakius_source_reference.json',
            'logical_source_bbox': logical_bounds, 'transparent_margin': MARGIN,
            'preview_missing_duration_hold_ms': INSPECTOR_HOLD_MS, 'notes': notes}
    write_json(ROOT / 'data/lakius_animations.json', data)
    report = {'schema': 1, 'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'producer': 'tools/r4/export_lakius.py', 'producer_sha256': file_sha(Path(__file__)),
              'client': '95', 'client_directory': str(client), 'source_pvf_sha256': file_sha(client / 'Script.pvf'),
              'pvf_header': pvf.header, 'monster': {'id': 71, 'mob': MOB, 'name_dictionary_id': 7,
                'name_dictionary': 'monster/monster.kor.str', 'name_key': 'name_525', 'name_big5': '魯卡斯',
                'boss_map_rows': boss_rows}, 'image': image_source,
              'canvas': {'size': CANVAS, 'foot_anchor': ANCHOR, 'logical_source_bbox': logical_bounds, 'margin': MARGIN},
              'counts': {'animations': len(animations), 'composite_frames': len(composite_records),
                'unique_source_crops': len(crops), 'textures': len(crops) + len(composite_records),
                'verified_pvf_crc': len(scripts), 'runtime_audio_new': 2, 'runtime_audio_reused': 1,
                'composite_pixels': len(composite_records) * CANVAS[0] * CANVAS[1],
                'raw_crop_pixels': sum(item.width * item.height for item in images.values())},
              'runtime_data': 'data/lakius_animations.json',
              'runtime_data_sha256': file_sha(ROOT / 'data/lakius_animations.json'),
              'raw_crops': list(crops.values()), 'composites': composite_records, 'scripts': scripts,
              'audio': audio, 'import_profile': PROFILE,
              'source_timing': {'missing_duration_frames': missing_source_durations,
                'attack1': {'source_ms': [80, 100, 150, 80], 'type15_box_frames': [2], 'active_ms': [180, 330]},
                'attackheart': {'source_ms': [850, 200, 50], 'type15_box_frames': [1], 'active_ms': [850, 1050]},
                'attacklong': {'source_ms': [50, 80, 80, 80, 80, 120, 50], 'type15_box_frames': [3], 'active_ms': [210, 290]}},
              'verification': {'all_pvf_crc_match': True, 'original_pvf_img_ogg_bytes_retained': True,
                'all69_png_rgba_roundtrips_exact': True, 'all37_composite_crop_rectangles_rgba_exact': True,
                'all_audio_page_crcs_valid': True, 'all_audio_noncomment_packets_identical': True,
                'all3_source_runtime_pcm_byte_identical': True, 'old_spear_runtime_not_rewritten': True},
              'adapted_gameplay_rules': None, 'notes': notes}
    write_json(ROOT / 'docs/r4_lakius_source_reference.json', report)
    write_json(SOURCE / 'reference.json', {'manifest': 'docs/r4_lakius_source_reference.json',
        'manifest_sha256': file_sha(ROOT / 'docs/r4_lakius_source_reference.json'),
        'animation_data': 'data/lakius_animations.json', 'audio_data': 'data/lakius_audio.json',
        'counts': report['counts'], 'verification': report['verification']})
    print(json.dumps({'monster_id': 71, **report['counts'], 'canvas': CANVAS,
                      'foot_anchor': ANCHOR, 'manifest': 'docs/r4_lakius_source_reference.json'}))


if __name__ == '__main__':
    main()
