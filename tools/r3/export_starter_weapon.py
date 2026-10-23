"""Prepare the isolated ID27304 appearance without replacing current assets.

Canonical mswd0007 crops are decoded as data. Seven existing body/apparel
layers and the character clock stay unchanged; fixed-canvas composites and
future native lower-apparel bakes are explicitly derived artifacts.
"""
from pathlib import Path
import argparse
import copy
import datetime
import hashlib
import json
import re
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/dnf_client_analysis'))
from inspect_clients import PVF, npk_entries, img_frames, decode_frame, binary_ani
from pixel_imports import PROFILE

ASSETS = 'assets/r3/equipment/ordinary_greatsword'
SOURCE = 'source_art/r3/equipment_27304'
PACK = 'sprite_character_swordman_equipment_weapon_mswd.NPK'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_sha(path):
    return sha(path.read_bytes())


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def texture(image, relative):
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    with Image.open(path) as saved:
        assert saved.mode == 'RGBA' and saved.tobytes() == image.tobytes()
    sidecar = path.with_suffix('.png.import')
    previous = sidecar.read_text() if sidecar.exists() else ''
    text = previous or ('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\n\nsource_file="res://' + relative + '"\n\n[params]\n')
    for key, value in PROFILE.items():
        pattern = '^' + re.escape(key) + '=.*$'
        text = re.sub(pattern, key + '=' + value, text, flags=re.MULTILINE) if re.search(pattern, text, re.MULTILINE) else text.rstrip() + '\n' + key + '=' + value + '\n'
    if text != previous:
        sidecar.write_text(text)
    return {'texture': 'res://' + relative, 'sha256_png': file_sha(path), 'sha256_rgba': sha(image.tobytes()),
            'size': list(image.size), 'import_sidecar': sidecar.relative_to(ROOT).as_posix()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path, default=Path('/Users/mac/Downloads/天堂95起源单机客户端'))
    args = parser.parse_args()
    client = args.client
    pvf = PVF(client / 'Script.pvf')
    assert pvf.header['tree_crc_actual'] == pvf.header['tree_crc_expected']
    assert not pvf.header['parse_error'] and not pvf.header['payload_bounds_errors']
    base = json.loads((ROOT / 'data/swordman_r0.json').read_text())
    source = copy.deepcopy(base)
    source['appearance'] = {'item_id': 27304, 'variation': [0, 7], 'layers': ['mswdb', 'mswdc']}
    composite = {'schema': 1, 'source_data': 'data/swordman_mswd0007_r0.json',
                 'canvas_size': [320, 224], 'foot_anchor': [133, 167], 'animations': {}}
    pack_cache, album_cache, crop_cache = {}, {}, {}
    raw_records, ani_records, pose_records, timing_differences = [], [], [], []
    unchanged = {}

    def album(pack, image_path):
        if pack not in pack_cache:
            path = client / 'ImagePacks2' / pack
            pack_cache[pack] = {'path': path, 'sha256': file_sha(path), 'entries': {e['path']: e for e in npk_entries(path)}}
        key = (pack, image_path)
        if key not in album_cache:
            entry = pack_cache[pack]['entries'][image_path]
            with pack_cache[pack]['path'].open('rb') as stream:
                stream.seek(entry['offset'])
                payload = stream.read(entry['bytes'])
            table, _palette = img_frames(payload)
            reference = ROOT / SOURCE / 'img' / (Path(image_path).name + '.bin')
            reference.parent.mkdir(parents=True, exist_ok=True)
            reference.write_bytes(payload)
            album_cache[key] = (payload, table, {'npk': pack, 'npk_sha256': pack_cache[pack]['sha256'],
                'img': image_path, 'entry': entry, 'sha256_img_payload': sha(payload),
                'raw_reference': reference.relative_to(ROOT).as_posix()})
        return album_cache[key]

    def frame(pack, image_path, image_index, relative):
        key = (pack, image_path, image_index)
        if key not in crop_cache:
            payload, table, provenance = album(pack, image_path)
            resolved = image_index
            seen = set()
            while 'link' in table[resolved]:
                assert resolved not in seen
                seen.add(resolved)
                resolved = table[resolved]['link']
            metadata = table[resolved]
            image = Image.new('RGBA', (1, 1)) if metadata['width'] == 0 or metadata['height'] == 0 else decode_frame(payload, image_index)[0]
            record = {**texture(image, relative), 'img_frame': image_index, 'resolved_img_frame': resolved,
                      'img_metadata': metadata, 'source': provenance, 'original_rgba_crop': True}
            crop_cache[key] = (image, record)
            raw_records.append(record)
        return crop_cache[key]

    def ani(path, role):
        data, crc = pvf.read(path, True)
        assert crc['expected'] == crc['actual_seed_file_number'], path
        decoded = binary_ani(data)
        destination = ROOT / SOURCE / 'pvf' / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.with_suffix('.ani.bin').write_bytes(data)
        record = {'path': path, 'role': role, 'sha256': sha(data), 'crc': crc, 'decoded': decoded}
        write_json(destination.with_suffix('.ani.json'), record)
        ani_records.append(record)
        return decoded

    for action, animation in source['animations'].items():
        character = ani('character/swordman/animation/' + action + '.ani', 'character master clock')
        weapons = {layer: ani(f'equipment/character/swordman/weapon/hsword/mswd{layer}/{action}.ani', 'weapon layer') for layer in ['b', 'c']}
        composite['animations'][action] = {'frames': []}
        animation['weapon_source_anis'] = {layer: f'equipment/character/swordman/weapon/hsword/mswd{layer}/{action}.ani' for layer in ['b', 'c']}
        for layer in ['b', 'c']:
            assert len(weapons[layer]['frames']) == len(character['frames'])
            assert weapons[layer]['resources'] == [f'character/swordman/equipment/weapon/mswd/mswd%02d%02d{layer}.img']
        for index, pose in enumerate(animation['frames']):
            char = character['frames'][index]
            layer_evidence = []
            for slot, layer in [(0, 'b'), (8, 'c')]:
                weapon = weapons[layer]['frames'][index]
                assert all(char[key] == weapon[key] for key in ['image_frame', 'x', 'y'])
                image_index = weapon['image_frame']
                image, record = frame(PACK, f'sprite/character/swordman/equipment/weapon/mswd/mswd0007{layer}.img',
                                      image_index, f'{ASSETS}/src/{layer}/{image_index:03d}.png')
                metadata = record['img_metadata']
                pose['layers'][slot] = {'name': pose['layers'][slot]['name'], 'texture': record['texture'],
                    'offset': [weapon['x'] + metadata['x'], weapon['y'] + metadata['y']]}
                delay = next((prop['value'] for prop in weapon['properties'] if prop['type'] == 12), None)
                if delay != pose['duration_ms']:
                    timing_differences.append({'action': action, 'frame': index, 'layer': layer,
                                               'character_ms': pose['duration_ms'], 'weapon_ms': delay})
                layer_evidence.append({'layer': layer, 'source_duration_ms': delay,
                    'source_properties': weapon['properties'], 'source_boxes': weapon['boxes'], 'source_globals': weapons[layer]['globals']})
            pose['weapon_source_evidence'] = layer_evidence
            canvas = Image.new('RGBA', (320, 224))
            for slot, layer in enumerate(pose['layers']):
                path = ROOT / layer['texture'].removeprefix('res://')
                image = Image.open(path).convert('RGBA')
                if slot not in [0, 8]:
                    assert layer == base['animations'][action]['frames'][index]['layers'][slot]
                    unchanged[layer['texture']] = file_sha(path)
                box = image.getbbox()
                if box:
                    left, top = layer['offset'][0] + 133, layer['offset'][1] + 167
                    assert left + box[0] >= 0 and top + box[1] >= 0 and left + box[2] <= 320 and top + box[3] <= 224
                canvas.alpha_composite(image, (layer['offset'][0] + 133, layer['offset'][1] + 167))
            result = texture(canvas, f'{ASSETS}/frames/{action}_{index:02d}.png')
            composite['animations'][action]['frames'].append({'texture': result['texture'], 'duration_ms': pose['duration_ms'],
                'img_frame': pose['img_frame'], 'source_properties': pose['source_properties'], 'source_boxes': pose['source_boxes']})
            pose_records.append({**result, 'action': action, 'frame': index, 'layer_textures': [x['texture'] for x in pose['layers']],
                'layer_offsets': [x['offset'] for x in pose['layers']], 'operation': 'Existing9-layer alpha composite; no resizing/repainting; fixed320x224 foot133,167.'})
    write_json(ROOT / 'data/swordman_mswd0007_r0.json', source)
    write_json(ROOT / 'data/swordman_mswd0007_r1.json', composite)
    _icon, icon = frame('sprite_item_weapon_swordman.NPK', 'sprite/item/weapon/swordman/lswd.img', 2, f'{ASSETS}/icon.png')
    _field, field = frame('sprite_item.NPK', 'sprite/item/fieldimage.img', 12, f'{ASSETS}/field.png')
    equ_path = 'equipment/character/swordman/weapon/hsword/lswd.equ'
    equ_bytes, equ_crc = pvf.read(equ_path, True)
    assert equ_crc['expected'] == equ_crc['actual_seed_file_number']
    equ_record = {'path': equ_path, 'sha256': sha(equ_bytes), 'crc': equ_crc, 'tokens': pvf.tokens(equ_path, 'big5')}
    equ_destination = ROOT / SOURCE / 'pvf' / equ_path
    equ_destination.parent.mkdir(parents=True, exist_ok=True)
    equ_destination.with_suffix('.equ.bin').write_bytes(equ_bytes)
    write_json(equ_destination.with_suffix('.equ.json'), equ_record)

    experiment_records = []
    for action, old_folder, shader_name, recipe_name in [('move', 'walk_cycle_24', 'walk_shear.gdshader', 'walk_recipe.json'),
                                                       ('dash', 'dash_cycle_26', 'dash_skin.gdshader', 'dash_recipe.json')]:
        folder = 'walk' if action == 'move' else 'dash'
        old = ROOT / 'source_art/r1/experiments' / old_folder
        target = ROOT / SOURCE / folder
        target.mkdir(parents=True, exist_ok=True)
        recipe = json.loads((old / recipe_name).read_text())
        recipe['source_data'] = 'res://data/swordman_mswd0007_r0.json'
        write_json(target / recipe_name, recipe)
        (target / shader_name).write_bytes((old / shader_name).read_bytes())
        actor = (old / 'actor.gd').read_text().replace('res://source_art/r1/experiments/' + old_folder + '/', 'res://' + SOURCE + '/' + folder + '/')
        (target / 'actor.gd').write_text(actor)
        experiment_records.append({'action': action, 'source_folder': old.relative_to(ROOT).as_posix(), 'new_folder': target.relative_to(ROOT).as_posix(),
            'source_actor_sha256': file_sha(old / 'actor.gd'), 'new_actor_sha256': file_sha(target / 'actor.gd'),
            'shader_sha256': file_sha(target / shader_name), 'shader_byte_identical': (target / shader_name).read_bytes() == (old / shader_name).read_bytes(),
            'source_recipe_sha256': file_sha(old / recipe_name), 'new_recipe_sha256': file_sha(target / recipe_name),
            'adaptation': 'Only resource directory and recipe.source_data changed; original recipe numeric fields and shaders unchanged.'})
        frames = []
        for index, pose in enumerate(composite['animations'][action]['frames']):
            frames.append({'source': pose['texture'], 'intermediates': [f'res://{ASSETS}/{folder}/{action}_{index:02d}_{sub}.png' for sub in [1, 2]]})
        write_json(ROOT / f'data/swordman_mswd0007_{folder}_inbetweens.json', {
            'schema': 1, 'action': action, 'source_frame_ms': 100, 'subframes': 3, 'cycle_ms': 800,
            'lower_body_sample_rate_hz': 30, 'upper_body_source_rate_hz': 10, 'canvas_size': [320, 224], 'foot_anchor': [133, 167],
            'frames': frames, 'bake_complete': False, 'notes': ['Output paths reserved; run newnativebaker before runtimeintegration.', 'Lower apparel adaptation; original character and weapon masterclock unchanged.']})
    equipment = {'schema': 1, 'default_appearance': {'id': 'practice_lswd0000', 'name': '练习长剑',
        'r0_data': 'res://data/swordman_r0.json', 'r1_data': 'res://data/swordman_r1.json',
        'walk_data': 'res://data/swordman_walk_inbetweens.json', 'dash_data': 'res://data/swordman_dash_inbetweens.json',
        'prototype_damage_bonus': 0, 'official_item_id': None,
        'note': 'Prototype default appearance name. Existing lswd0000 visual is not assigned a unique official item ID.'},
        'items': {'27304': {'item_id': 27304, 'name': '普通巨剑', 'source_name_big5': '普通巨劍', 'type': 'weapon',
            'icon_path': icon['texture'], 'field_path': field['texture'], 'appearance_id': 'mswd0007',
            'r0_data': 'res://data/swordman_mswd0007_r0.json', 'r1_data': 'res://data/swordman_mswd0007_r1.json',
            'walk_data': 'res://data/swordman_mswd0007_walk_inbetweens.json', 'dash_data': 'res://data/swordman_mswd0007_dash_inbetweens.json',
            'prototype_damage_bonus': 4, 'source_equipment_physical_attack': [72, 72],
            'source_stats_are_provenance_only': True, 'source_pvf': equ_path}},
        'quest_reward': {'quest_id': 'first_route_v1', 'item_id': 27304, 'quantity': 1,
            'receipt_id': 'first_route_weapon_v1', 'once_only': True, 'adapted_reward': True, 'runtime_hook_implemented': False},
        'notes': ['The +4 bonus and one-time quest grant are explicit prototype adaptations, not restored original item formulas/rewards.',
                  'Source physical attack72 is not direct HP damage. Existing default appearance and artifacts remain unchanged.',
                  'All variant F5 paths must have a successful native bake before equipping at runtime.']}
    write_json(ROOT / 'data/first_equipment.json', equipment)
    report = {'schema': 1, 'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'producer': 'tools/r3/export_starter_weapon.py', 'producer_sha256': file_sha(Path(__file__)),
        'source_pvf_sha256': file_sha(client / 'Script.pvf'), 'equipment': equ_record,
        'raw_crops': raw_records, 'composites': pose_records, 'source_anis': ani_records,
        'counts': {'weapon_layer_crops': 164, 'item_crops': 2, 'composite_frames': len(pose_records), 'ani_crc_verified': len(ani_records), 'textures': len(raw_records) + len(pose_records)},
        'source_r0_sha256': file_sha(ROOT / 'data/swordman_r0.json'), 'unchanged_body_apparel_pngs': unchanged,
        'runtime_r0_sha256': file_sha(ROOT / 'data/swordman_mswd0007_r0.json'), 'runtime_r1_sha256': file_sha(ROOT / 'data/swordman_mswd0007_r1.json'),
        'weapon_timing_differences': timing_differences, 'import_profile': PROFILE, 'native_experiments': experiment_records,
        'validation': {'all_raw_rgba_roundtrips_exact': True, 'all_composite_png_roundtrips_exact': True,
            'all_184_weapon_indices_and_offsets_match_character': True, 'all_7_other_layers_unchanged': True,
            'alpha_pixel_clipping_cases': 0, 'canvas_size': [320, 224], 'foot_anchor': [133, 167],
            'character_masterclock_preserved': True, 'native_bake_not_run_by_exporter': True},
        'notes': equipment['notes'] + ['Rawweapon/IMG bytes and42ANIs retained under source_art/r3/equipment_27304.',
            'WeaponANI jumpattack/down original durations differ; only original character clock drives composites. Weapon originals remain evidence.',
            'No Godot, Blender, gameplayhook, sourceclientcode, or paid/network service executed.']}
    assert len(ani_records) == 42 and len(pose_records) == 92 and len(raw_records) == 166
    write_json(ROOT / 'docs/r3_starter_weapon_source_reference.json', report)
    print(json.dumps({'counts': report['counts'], 'source': 'docs/r3_starter_weapon_source_reference.json', 'native_bake_ready_not_run': True}))


if __name__ == '__main__':
    main()
