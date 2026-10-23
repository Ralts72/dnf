"""Export only the source-backed Eye of Dragonman item for the first loot loop.

The client is opened as read-only PVF/NPK data. Only two new PNGs, their lossless
import sidecars, data/first_loot_items.json and docs/r3_loot_source_reference.json
are written. This tool neither imports assets in Godot nor changes runtime code.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/dnf_client_analysis'))
from inspect_clients import PVF, npk_entries, img_frames, decode_frame
from pixel_imports import PROFILE

ITEM_ID = 3128
ITEM_SCRIPT = 'stackable/material/eye_dragonman.stk'
MONSTER_SCRIPT = 'monster/draconian/mirkius.mob'
TEXTURES = {
    'icon': ('dragon_eye_icon.png', 'sprite_item_stackable.NPK',
             'sprite/item/stackable/material.img', 32),
    'field': ('dragon_eye_field.png', 'sprite_item.NPK',
              'sprite/item/fieldimage.img', 23),
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def sections(tokens):
    result = []
    for token in tokens:
        if token['type'] == 5:
            result.append({'tag': token['text'], 'values': []})
        elif result:
            result[-1]['values'].append(token.get('text', token.get('value')))
    return result


def section(blocks, tag):
    return next(block['values'] for block in blocks if block['tag'] == tag)


def pair(tokens, value):
    return next([left, right] for left, right in zip(tokens[::2], tokens[1::2])
                if left.get('value') == value)


def source_script(pvf, path, selected):
    raw, crc = pvf.read(path, True)
    assert crc['expected'] == crc['actual_seed_file_number'], path
    return {'path': path, 'bytes': len(raw), 'sha256_decoded_bytes': digest(raw),
            'crc': crc, 'crc_matches': True, 'selected_source_data': selected}


def write_texture(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    with Image.open(path) as saved:
        assert saved.mode == 'RGBA' and saved.size == image.size
        assert saved.tobytes() == image.tobytes(), path
    # Touch only the new item sidecars. Preserve Godot-generated remap metadata
    # on later reruns; never scan or rewrite other asset import settings.
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
    return {'path': 'res://' + path.relative_to(ROOT).as_posix(),
            'size': list(image.size), 'sha256_png': file_digest(path),
            'sha256_rgba': digest(image.tobytes()),
            'alpha_range': list(image.getchannel('A').getextrema()),
            'png_rgba_roundtrip_equal': True,
            'import_sidecar': sidecar.relative_to(ROOT).as_posix()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path,
                        default=Path('/Users/mac/Downloads/天堂95起源单机客户端'))
    args = parser.parse_args()
    client = args.client
    pvf = PVF(client / 'Script.pvf')
    assert pvf.header['tree_crc_actual'] == pvf.header['tree_crc_expected']
    assert not pvf.header['payload_bounds_errors'] and not pvf.header['parse_error']

    item_pair = pair(pvf.tokens('stackable/stackable.lst', 'big5'), ITEM_ID)
    assert item_pair[1]['text'].lower() == ITEM_SCRIPT.removeprefix('stackable/')
    item_tokens = pvf.tokens(ITEM_SCRIPT, 'big5')
    item_sections = sections(item_tokens)
    assert section(item_sections, '[icon]') == ['Item/stackable/material.img', 32]
    assert section(item_sections, '[field image]') == ['Item/FieldImage.img', 23]
    assert section(item_sections, '[stackable type]') == ['[material]', 3]
    name_start = next(i for i, token in enumerate(item_tokens)
                      if token.get('text') == '[name]')
    dictionary_id, name_key = item_tokens[name_start + 1:name_start + 3]
    assert dictionary_id == {'type': 9, 'value': 13}
    assert name_key.get('text') == 'name_3128' and name_key['type'] == 10
    dictionary_pair = pair(pvf.tokens('n_string.lst', 'big5'), 13)
    dictionary_path = dictionary_pair[1]['text'].lower()
    dictionary_text = pvf.read(dictionary_path).decode('big5', 'replace')
    dictionary = {line.split('>', 1)[0]: line.split('>', 1)[1]
                  for line in dictionary_text.splitlines()
                  if '>' in line and not line.startswith('//')}
    assert dictionary['name_3128'] == '龍人之眼'
    assert dictionary['name2_3128'] == 'Eye of Dragonman'

    monster_pair = pair(pvf.tokens('monster/monster.lst', 'big5'), 70)
    assert monster_pair[1]['text'].lower() == 'draconian/mirkius.mob'
    monster_items = section(sections(pvf.tokens(MONSTER_SCRIPT, 'big5')), '[item]')
    source_drop = next(monster_items[i:i + 2] for i in range(0, len(monster_items), 2)
                       if monster_items[i] == ITEM_ID)
    assert source_drop == [3128, 500]

    scripts = [
        source_script(pvf, 'stackable/stackable.lst', item_pair),
        source_script(pvf, ITEM_SCRIPT, item_sections),
        source_script(pvf, 'n_string.lst', dictionary_pair),
        source_script(pvf, dictionary_path,
                      {key: dictionary[key] for key in ['name_3128', 'name2_3128']}),
        source_script(pvf, 'monster/monster.lst', monster_pair),
        source_script(pvf, MONSTER_SCRIPT, {'[item]': monster_items}),
    ]
    images = {}
    for role, (filename, pack, img, index) in TEXTURES.items():
        pack_path = client / 'ImagePacks2' / pack
        entry = next(entry for entry in npk_entries(pack_path) if entry['path'] == img)
        with pack_path.open('rb') as stream:
            stream.seek(entry['offset'])
            raw_img = stream.read(entry['bytes'])
        image, metadata = decode_frame(raw_img, index)
        table, _palette = img_frames(raw_img)
        resolved, seen = index, set()
        while 'link' in table[resolved]:
            assert resolved not in seen
            seen.add(resolved)
            resolved = table[resolved]['link']
        assert image.size == ((28, 28) if role == 'icon' else (33, 23))
        images[role] = {
            **write_texture(image, ROOT / 'assets/r3/items' / filename),
            'img_frame_index': index, 'resolved_img_frame_index': resolved,
            'img_metadata': metadata, 'original_img_crop': True,
            'source': {'client': '95', 'npk': pack, 'npk_sha256': file_digest(pack_path),
                       'img': img, 'npk_entry_offset': entry['offset'],
                       'payload_bytes': entry['bytes'], 'sha256_img_payload': digest(raw_img),
                       'img_total_frames': len(table)},
            'export': 'Exact decoded RGBA crop, including transparent RGB; no resize, redraw, alpha edit or canvas reconstruction.',
        }

    source_refs = {'pvf': ITEM_SCRIPT, 'item_list': 'stackable/stackable.lst',
                   'icon': {'npk': TEXTURES['icon'][1], 'img': TEXTURES['icon'][2], 'index': 32},
                   'field': {'npk': TEXTURES['field'][1], 'img': TEXTURES['field'][2], 'index': 23},
                   'monster': MONSTER_SCRIPT, 'monster_item_pair_raw': source_drop,
                   'reference': 'res://docs/r3_loot_source_reference.json'}
    adapted_rule = {'encounter': 'first_mirkius', 'trigger': 'first_encounter_clear',
                    'item_id': ITEM_ID, 'count': 1, 'once_per_profile': True,
                    'rule_origin': 'prototype_adaptation',
                    'note': '本原型首次清怪一次必掉1个；原Mirkius表3128,500原样记录，未解释为原版掉率。'}
    data = {'schema': 1, 'items': {str(ITEM_ID): {
        'item_id': ITEM_ID, 'name': '龙人之眼', 'source_name': dictionary['name_3128'],
        'kind': 'material', 'icon_path': images['icon']['path'],
        'field_path': images['field']['path'], 'source_refs': source_refs,
    }}, 'adapted_drop_rule': adapted_rule}
    write_json(ROOT / 'data/first_loot_items.json', data)
    reference = {
        'schema': 1, 'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'item_id': ITEM_ID, 'name': '龙人之眼', 'source_name': dictionary['name_3128'],
        'source_english_name': dictionary['name2_3128'], 'translation_encoding': 'Big5',
        'client': '95', 'client_directory': str(client),
        'source_pvf_sha256': file_digest(client / 'Script.pvf'),
        'pvf_header': pvf.header, 'scripts': scripts, 'images': images,
        'source_drop_reference': {'monster_id': 70, 'monster_pvf': MONSTER_SCRIPT,
                                  'tag': '[item]', 'pair_raw': source_drop,
                                  'probability': None,
                                  'interpretation': 'The raw pair establishes a source item reference only. Weighting, denominator and original runtime drop selection were not reproduced.'},
        'adapted_drop_rule': adapted_rule, 'import_profile': PROFILE,
        'verification': {'pvf_crc_passed': len(scripts), 'png_rgba_roundtrips_passed': len(images),
                         'source_decoded_pixels_preserved': sum(v['size'][0] * v['size'][1] for v in images.values())},
        'notes': [
            'Explicit canonical NPK selection; patch NPK precedence is not inferred.',
            'The original inventory picture is blue; the original field image is a shared brown bone-remains picture. Their source association is preserved without inventing a matching blue ground icon.',
            'Names, images, item IDs and the raw Mirkius item pair are source-backed. One guaranteed drop on the first adapted encounter clear is a new prototype rule.',
            'This export adds no runtime, quest, pickup or persistence hook and does not execute Godot, client binaries, ACT or SKL.',
            'Only the two item PNGs, their lossless import sidecars, the item data and this source reference are written.',
        ],
    }
    write_json(ROOT / 'docs/r3_loot_source_reference.json', reference)
    print(json.dumps({'item_id': ITEM_ID, 'textures': {k: v['path'] for k, v in images.items()},
                      **reference['verification']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
