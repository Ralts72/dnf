"""Export a small, explicit legacy Mirkius/龙人 animation whitelist.

Only new R3 asset/reference files and a work/ contact sheet are written. Source
PVF, NPK and IMG are read as data; no client program or gameplay script runs.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/dnf_client_analysis'))
from inspect_clients import PVF, npk_entries, img_frames, decode_frame, binary_ani
from pixel_imports import PROFILE

PACK = 'sprite_monster_draconian.NPK'
IMG = 'sprite/monster/draconian/draco_mirkius.img'
MOB = 'monster/draconian/mirkius.mob'
ACTIONS = {
    'stay': 'stay',
    'move': 'movefoward',
    'attack1': 'attack',
    'damage1': 'damage1',
    'damage2': 'damage2',
    'down': 'down',
    'moveback': 'moveback',
    'sit': 'sit',
    'attacklong': 'attacklong',
}
PREVIEW_HOLD_MS = 10000
CANVAS_MARGIN = 8


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def texture(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    with Image.open(path) as saved:
        assert saved.mode == 'RGBA' and saved.size == image.size
        assert saved.tobytes() == image.tobytes(), path
    sidecar = path.with_suffix('.png.import')
    previous = sidecar.read_text() if sidecar.exists() else ''
    text = previous or ('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
                        '[deps]\n\nsource_file="res://' + path.relative_to(ROOT).as_posix() + '"\n\n[params]\n')
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
            'size': list(image.size), 'sha256_png': file_digest(path),
            'sha256_rgba': digest(image.tobytes()),
            'alpha_range': list(image.getchannel('A').getextrema()),
            'import_sidecar': sidecar.relative_to(ROOT).as_posix()}


def source_record(pvf, path, decoded):
    raw, crc = pvf.read(path, True)
    assert crc['expected'] == crc['actual_seed_file_number'], path
    destination = ROOT / 'source_art/r3/pvf' / path
    destination.parent.mkdir(parents=True, exist_ok=True)
    raw_file = destination.with_suffix(destination.suffix + '.bin')
    raw_file.write_bytes(raw)
    result = {'path': path, 'sha256': digest(raw), 'bytes': len(raw), 'crc': crc,
              'raw_reference': raw_file.relative_to(ROOT).as_posix(), 'decoded': decoded}
    json_file = destination.with_suffix(destination.suffix + '.json')
    write_json(json_file, result)
    return {**result, 'decoded_reference': json_file.relative_to(ROOT).as_posix()}


def selected_section(tokens, label, end_label):
    start = next(index for index, item in enumerate(tokens) if item.get('text', '').lower() == label)
    end = next(index for index in range(start + 1, len(tokens)) if tokens[index].get('text', '').lower() == end_label)
    return tokens[start:end + 1]


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
    frame_table, _palette = img_frames(raw_img)
    img_version = int(entry['version'])
    img_archive = ROOT / 'source_art/r3/img/draco_mirkius.img.bin'
    img_archive.parent.mkdir(parents=True, exist_ok=True)
    img_archive.write_bytes(raw_img)
    image_source = {
        'client': '95', 'npk': PACK, 'npk_sha256': file_digest(pack_path), 'img': IMG,
        'npk_entry_offset': entry['offset'], 'payload_bytes': entry['bytes'],
        'sha256_img_payload': digest(raw_img), 'img_version': img_version,
        'img_total_frames': len(frame_table), 'raw_reference': img_archive.relative_to(ROOT).as_posix(),
        'selection': 'Explicit canonical NPK only; no patch/mod precedence inferred.',
    }
    animations = {}
    scripts = []
    crop_images = {}
    crops = {}
    bounds = []
    for key, source_action in ACTIONS.items():
        path = 'monster/draconian/dmani/' + source_action + '.ani'
        raw, crc = pvf.read(path, True)
        assert crc['expected'] == crc['actual_seed_file_number'], path
        ani = binary_ani(raw)
        assert ani['resources'] == [IMG.removeprefix('sprite/')]
        scripts.append(source_record(pvf, path, ani))
        animations[key] = {'source_ani': path, 'source_action': source_action,
                           'source_sha256': digest(raw), 'source_globals': ani['globals'],
                           'source_resources': ani['resources'], 'source_frames_count': ani['frames_count'],
                           'source_decoded': ani, 'frames': []}
        for frame in ani['frames']:
            index = frame['image_frame']
            if index not in crops:
                image, metadata = decode_frame(raw_img, index)
                resolved = index
                seen = set()
                while 'link' in frame_table[resolved]:
                    assert resolved not in seen
                    seen.add(resolved)
                    resolved = frame_table[resolved]['link']
                record = texture(image, ROOT / 'assets/r3/draconian/src' / f'{index:03d}.png')
                crops[index] = {**record, 'img_frame': index, 'resolved_img_frame': resolved,
                                'img_metadata': metadata, 'source': image_source,
                                'export': 'Exact decoded RGBA crop, including transparent RGB; no resize, retouch or alpha edits.'}
                crop_images[index] = image
            meta = crops[index]['img_metadata']
            x, y = frame['x'] + meta['x'], frame['y'] + meta['y']
            bounds.append((x, y, x + meta['width'], y + meta['height']))
    logical_bounds = [min(box[0] for box in bounds), min(box[1] for box in bounds),
                      max(box[2] for box in bounds), max(box[3] for box in bounds)]
    canvas_size = [logical_bounds[2] - logical_bounds[0] + 2 * CANVAS_MARGIN,
                   logical_bounds[3] - logical_bounds[1] + 2 * CANVAS_MARGIN]
    anchor = [-logical_bounds[0] + CANVAS_MARGIN, -logical_bounds[1] + CANVAS_MARGIN]
    composite_records = []
    composite_images = {}
    copied_rgba_pixels = 0
    for key, animation in animations.items():
        composite_images[key] = []
        for index, source_frame in enumerate(animation['source_decoded']['frames']):
            image_index = source_frame['image_frame']
            raw_crop = crop_images[image_index]
            crop = crops[image_index]
            meta = crop['img_metadata']
            offset = [source_frame['x'] + meta['x'], source_frame['y'] + meta['y']]
            paste = [anchor[0] + offset[0], anchor[1] + offset[1]]
            assert paste[0] >= CANVAS_MARGIN and paste[1] >= CANVAS_MARGIN
            assert paste[0] + raw_crop.width <= canvas_size[0] - CANVAS_MARGIN
            assert paste[1] + raw_crop.height <= canvas_size[1] - CANVAS_MARGIN
            composed = Image.new('RGBA', canvas_size, (0, 0, 0, 0))
            # No mask/alpha compositing: copy all four bytes, including RGB
            # beneath alpha0, so raw crop bytes survive a reverse extraction.
            composed.paste(raw_crop, paste)
            region = (paste[0], paste[1], paste[0] + raw_crop.width, paste[1] + raw_crop.height)
            assert composed.crop(region).tobytes() == raw_crop.tobytes()
            copied_rgba_pixels += raw_crop.width * raw_crop.height
            result = texture(composed, ROOT / 'assets/r3/draconian/frames' / key / f'{index:03d}.png')
            original_duration = next((prop['value'] for prop in source_frame['properties'] if prop['type'] == 12), None)
            frame = {**result, 'duration_ms': original_duration if original_duration is not None else PREVIEW_HOLD_MS,
                     'source_duration_ms': original_duration,
                     'duration_origin': 'Original ANI property12' if original_duration is not None else 'Inspector-only static pose hold fallback; not original timing or combat hitstun',
                     'img_frame': image_index, 'resolved_img_frame': crop['resolved_img_frame'],
                     'ani_offset': [source_frame['x'], source_frame['y']], 'img_metadata': meta,
                     'source_crop': crop['texture'], 'source_crop_rgba_sha256': crop['sha256_rgba'],
                     'logical_crop_offset': offset, 'composite_paste_offset': paste,
                     'source_properties': source_frame['properties'], 'source_boxes': source_frame['boxes'],
                     'derived_artifact': True,
                     'composition': 'Exact unmasked RGBA crop copy on shared transparent canvas; no resampling or pixel edits.'}
            animation['frames'].append(frame)
            composite_records.append({'action': key, 'frame': index, **frame})
            composite_images[key].append(composed)
        del animation['source_decoded']

    references = [MOB, 'monster/draconian/dmattackinfo/attack.atk',
                  'monster/draconian/dmattackinfo/attacklong.atk',
                  'monster/draconian/dlattackinfo/attackheart.atk']
    for path in references:
        scripts.append(source_record(pvf, path, pvf.tokens(path, 'big5')))
    monster_tokens = pvf.tokens('monster/monster.lst', 'big5')
    monster_pairs = []
    for index in range(0, len(monster_tokens) - 1, 2):
        left, right = monster_tokens[index:index + 2]
        if right.get('text', '').lower().startswith('draconian/'):
            monster_pairs.extend([left, right])
    assert any(a.get('value') == 70 and b.get('text', '').lower() == 'draconian/mirkius.mob'
               for a, b in zip(monster_pairs[::2], monster_pairs[1::2]))
    scripts.append(source_record(pvf, 'monster/monster.lst', {'selection': 'Only Draconian ID/path pairs; complete bytes retained in .bin', 'tokens': monster_pairs}))
    n_string_tokens = pvf.tokens('n_string.lst', 'big5')
    name_dictionary_pair = next([a, b] for a, b in zip(n_string_tokens[::2], n_string_tokens[1::2]) if a.get('value') == 7)
    assert name_dictionary_pair[1]['text'].lower() == 'monster/monster.kor.str'
    scripts.append(source_record(pvf, 'n_string.lst', {'selection': 'DictionaryID7; complete bytes retained in .bin', 'tokens': name_dictionary_pair}))
    dictionary = pvf.read('monster/monster.kor.str').decode('big5', 'strict')
    name_lines = [line for line in dictionary.splitlines() if any(line.startswith(key + '>') for key in ['name_530', 'name_2005', 'name_525', 'name_515'])]
    assert 'name_530>龍人' in name_lines
    scripts.append(source_record(pvf, 'monster/monster.kor.str', {'encoding': 'Big5', 'selection': 'Mirkius and adjacent variant names; complete bytes retained in .bin', 'lines': name_lines}))
    map_path = 'map/draconiantower/(2,0)s1601.map'
    map_monsters = selected_section(pvf.tokens(map_path, 'big5'), '[monster]', '[/monster]')
    scripts.append(source_record(pvf, map_path, {'selection': '[monster] section only; complete bytes retained in .bin', 'tokens': map_monsters}))
    legacy_act_paths = sorted(path for path in pvf.entries if path.startswith('monster/draconian/') and path.endswith('.act'))
    legacy_ai_paths = sorted(path for path in pvf.entries if path.startswith('monster/draconian/') and path.endswith('.ai'))

    notes = [
        'Legacy monsterID70 Mirkius resolves dictionaryID7/name_530 to 龍人. Simplified 龙人 is a display adaptation.',
        'Minius/藍龍人, Lakius/魯卡斯, Sius/雷環休斯 and newer Magneus are separate variants; no AI/ACT assets are borrowed from them.',
        'No gameplay implementation: HP, damage, AI, collision, hit timing, stun and death state machine are not supplied by this export.',
        'Original ANI properties, XYZ boxes, frame indices, offsets and explicit durations are retained verbatim as decoded data.',
        'damage1/2 contain no duration property: source_duration_ms=null; duration_ms=10000 is solely a safe static-pose inspector fallback, not original timing or a combat rule.',
        'Down retains both original10000ms source holds. There is no standalone deathANI in the legacy tree; do not label this export as original death behavior.',
        'Raw src PNGs contain exact source RGBA. Fixed-canvas frames are derived artifacts with exact unmasked crop copies and transparent padding.',
        'A contact sheet adds labels and a checkerboard only in work/; exported textures are not changed.',
        'No client EXE, DLL, game server, ACT interpreter, paid API or internet service was run.',
    ]
    animation_data = {'schema': 1, 'character': 'mirkius', 'monster_id': 70, 'canvas_size': canvas_size,
                      'foot_anchor': anchor, 'animations': animations, 'source_data': 'docs/r3_draconian_source_reference.json',
                      'logical_source_bbox': logical_bounds, 'transparent_margin': CANVAS_MARGIN,
                      'preview_missing_duration_hold_ms': PREVIEW_HOLD_MS, 'notes': notes}
    write_json(ROOT / 'data/draconian_animations.json', animation_data)

    label_width = 190
    cell_width, cell_height = canvas_size[0] + 8, canvas_size[1] + 30
    columns = max(len(items) for items in composite_images.values())
    sheet = Image.new('RGBA', (label_width + columns * cell_width, 56 + len(animations) * cell_height), (18, 25, 34, 255))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=14)
    draw.text((12, 12), 'ID70 Mirkius / canonical source frames at1:1 (checkerboard and labels are preview only)', font=font, fill=(235, 225, 198))
    draw.text((12, 32), 'damage timing absent in source; down retains10000ms holds. Runtime canvas: %sx%s / foot:%s' % (*canvas_size, anchor), font=font, fill=(185, 195, 205))
    for row, (key, items) in enumerate(composite_images.items()):
        y = 56 + row * cell_height
        draw.text((10, y + 8), key, font=font, fill=(230, 220, 195))
        draw.text((10, y + 28), ACTIONS[key] + '.ani', font=font, fill=(170, 185, 200))
        for column, image in enumerate(items):
            x = label_width + column * cell_width
            for cy in range(0, canvas_size[1], 12):
                for cx in range(0, canvas_size[0], 12):
                    color = (43, 51, 59, 255) if (cx // 12 + cy // 12) % 2 else (34, 42, 50, 255)
                    draw.rectangle((x + cx, y + cy, x + min(cx + 11, canvas_size[0] - 1), y + min(cy + 11, canvas_size[1] - 1)), fill=color)
            sheet.alpha_composite(image, (x, y))
            frame = animations[key]['frames'][column]
            duration_label = str(frame['source_duration_ms']) + 'ms' if frame['source_duration_ms'] is not None else 'no source duration'
            draw.text((x + 4, y + canvas_size[1] + 5), '#%d IMG%02d %s' % (column, frame['img_frame'], duration_label), font=font, fill=(205, 213, 220))
    preview_path = ROOT / 'work/r3_draconian_sheet.png'
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert('RGB').save(preview_path)

    report = {
        'schema': 1, 'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'producer': 'tools/r3/export_draconian.py', 'producer_sha256': file_digest(Path(__file__)),
        'client': '95', 'client_directory': str(client), 'source_pvf_sha256': file_digest(client / 'Script.pvf'),
        'pvf_header': pvf.header, 'monster': {'id': 70, 'mob': MOB, 'name_dictionary_id': 7,
            'name_dictionary': 'monster/monster.kor.str', 'name_key': 'name_530', 'name_big5': '龍人',
            'nearby_names': name_lines}, 'image': image_source,
        'counts': {'animations': len(animations), 'composite_frames': len(composite_records), 'unique_source_crops': len(crops),
                   'textures': len(crops) + len(composite_records), 'verified_pvf_crc': len(scripts), 'copied_rgba_pixels': copied_rgba_pixels},
        'canvas': {'size': canvas_size, 'foot_anchor': anchor, 'logical_source_bbox': logical_bounds,
                   'margin': CANVAS_MARGIN, 'derivation': 'Union of all selected ANIoffset+IMGcropbounds, padded8pixels per side.'},
        'runtime_data': 'data/draconian_animations.json', 'runtime_data_sha256': file_digest(ROOT / 'data/draconian_animations.json'),
        'raw_crops': list(crops.values()), 'composites': composite_records, 'scripts': scripts, 'import_profile': PROFILE,
        'action_ai_evidence': {'searched_pvf_prefix': 'monster/draconian/', 'act_paths': legacy_act_paths, 'ai_paths': legacy_ai_paths,
            'interpretation': 'This legacy mob directly lists motion and attackinfo records; no dedicated ACT or AI files in this prefix. Shared engine behavior was not reconstructed.',
            'source_attack1': {'ani': 'monster/draconian/dmani/attack.ani', 'attack_info': 'monster/draconian/dmattackinfo/attack.atk',
                'active_box_frame_index': 2, 'preceding_original_duration_ms': 310,
                'box': {'type': 15, 'xyz_size': [-22, -10, 35, 173, 20, 50]},
                'limitation': 'Source evidence only. These XYZ dimensions are not mapped to a playable Godot attack collider here.'},
            'death_evidence': {'standalone_death_ani': False, 'mob_die_effect_values': [0, 4, 0],
                'down_source_durations_ms': [80, 80, 10000, 10000, 300],
                'limitation': 'No original death-state or effect playback reconstructed; a later down/fade response must be labeled adapted.'}},
        'adapted_gameplay_rules': None,
        'validation': {'all_source_ani_crc_match': True, 'all_reference_crc_match': True,
            'all_raw_crop_rgba_roundtrips_exact': True, 'all_composite_crop_rectangles_rgba_exact': True,
            'all_png_rgba_roundtrips_exact': True, 'minimum_transparent_margin_px': CANVAS_MARGIN,
            'all_source_explicit_durations_preserved': True,
            'missing_duration_fallback_is_preview_only': True, 'source_assets_resized_or_repainted': False},
        'preview': {'path': preview_path.relative_to(ROOT).as_posix(), 'sha256': file_digest(preview_path),
            'native_pixel_scale': 1, 'not_runtime_texture': True}, 'notes': notes,
    }
    write_json(ROOT / 'docs/r3_draconian_source_reference.json', report)
    write_json(ROOT / 'source_art/r3/draconian_reference.json', {
        'manifest': 'docs/r3_draconian_source_reference.json',
        'manifest_sha256': file_digest(ROOT / 'docs/r3_draconian_source_reference.json'),
        'runtime_data': 'data/draconian_animations.json', 'counts': report['counts'], 'notes': notes})
    print(json.dumps({'canvas': report['canvas'], 'counts': report['counts'],
                      'manifest': 'docs/r3_draconian_source_reference.json', 'preview': str(preview_path)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
