"""Stage ordinary Ghost Slash in new assets/manifests; never execute client code.

This tool is deliberately separate from runtime integration. It only writes
assets/r4/ghost_slash/, source_art/r4/ghost_slash/, four new complete actor JSONs,
data/ghost_slash_effects.json and docs/r4_ghost_slash_source_reference.json.
Existing actor/equipment/effect data, scenes and source PNGs are never rewritten.
Run only after the parent authorizes export following the R4/01 freeze.
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
from export_r0 import LAYERS
from pixel_imports import PROFILE

ASSETS = 'assets/r4/ghost_slash'
SOURCE = ROOT / 'source_art/r4/ghost_slash'
CANVAS = (320, 224)
ANCHOR = (133, 167)
MASTER = 'character/swordman/animation/hardattack.ani'
ACTOR_INPUTS = {
    'practice': ('data/swordman_r0.json', 'data/swordman_r1.json'),
    'great': ('data/swordman_mswd0007_r0.json', 'data/swordman_mswd0007_r1.json'),
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def file_sha(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')


def duration(frame):
    return next(prop['value'] for prop in frame['properties'] if prop['type'] == 12)


def alpha_union(boxes):
    boxes = [box for box in boxes if box is not None]
    if not boxes:
        return None
    return [min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes)]


def texture(image, relative):
    assert relative.startswith(ASSETS+'/') and image.mode == 'RGBA'
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    with Image.open(path) as saved:
        assert saved.mode == 'RGBA' and saved.size == image.size and saved.tobytes() == image.tobytes(), relative
    sidecar = path.with_suffix('.png.import')
    previous = sidecar.read_text() if sidecar.exists() else ''
    text = previous or ('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\n\nsource_file="res://'+relative+'"\n\n[params]\n')
    assert '[params]' in text
    for key, value in PROFILE.items():
        pattern = '^'+re.escape(key)+'=.*$'
        text = re.sub(pattern, key+'='+value, text, flags=re.MULTILINE) if re.search(pattern, text, re.MULTILINE) else text.rstrip()+'\n'+key+'='+value+'\n'
    if text != previous:
        sidecar.write_text(text)
    bounds = image.getchannel('A').getbbox()
    return {'texture': 'res://'+relative, 'size': list(image.size), 'sha256_png': file_sha(path),
        'sha256_rgba': sha(image.tobytes()), 'alpha_bounds': list(bounds) if bounds else None,
        'import_sidecar': str(sidecar.relative_to(ROOT))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path, default=Path('/Users/mac/Downloads/天堂95起源单机客户端'))
    args = parser.parse_args()
    client = args.client
    pvf = PVF(client / 'Script.pvf')
    assert pvf.header['tree_crc_actual'] == pvf.header['tree_crc_expected']
    assert not pvf.header['parse_error'] and not pvf.header['payload_bounds_errors']
    source_pvf_sha = file_sha(client / 'Script.pvf')
    assert source_pvf_sha == json.loads((ROOT / 'docs/r0_asset_manifest.json').read_text())['source_pvf_sha256']
    packs, albums, crops, scripts = {}, {}, {}, {}
    raw_records, composite_records, retained_inputs, outputs = [], [], {}, {}

    def script(path, animation=False):
        if path not in scripts:
            raw, crc = pvf.read(path, True)
            assert crc['expected'] == crc['actual_seed_file_number'], path
            target = SOURCE / 'pvf' / path
            target.parent.mkdir(parents=True, exist_ok=True)
            raw_path = target.with_suffix(target.suffix+'.bin')
            raw_path.write_bytes(raw)
            assert raw_path.read_bytes() == raw
            decoded = binary_ani(raw) if animation else pvf.tokens(path, 'big5')
            scripts[path] = {'path': path, 'sha256_decoded_bytes': sha(raw), 'bytes': len(raw), 'crc': crc,
                'crc_matches': True, 'decoded': decoded, 'raw_reference': str(raw_path.relative_to(ROOT))}
            write_json(target.with_suffix(target.suffix+'.json'), scripts[path])
        return scripts[path]['decoded']

    def album(pack, image):
        if pack not in packs:
            path = client / 'ImagePacks2' / pack
            packs[pack] = {'path': path, 'sha256': file_sha(path), 'entries': {e['path']: e for e in npk_entries(path)}}
        key = (pack, image)
        if key not in albums:
            entry = packs[pack]['entries'][image]
            with packs[pack]['path'].open('rb') as stream:
                stream.seek(entry['offset'])
                raw = stream.read(entry['bytes'])
            table, _ = img_frames(raw)
            retained = SOURCE / 'img' / pack / (image+'.bin')
            retained.parent.mkdir(parents=True, exist_ok=True)
            retained.write_bytes(raw)
            assert retained.read_bytes() == raw
            albums[key] = (raw, table, {'npk': pack, 'npk_sha256': packs[pack]['sha256'], 'img': image,
                'entry': entry, 'sha256_img_payload': sha(raw), 'raw_reference': str(retained.relative_to(ROOT))})
        return albums[key]

    def crop(pack, image_path, index, relative):
        key = (pack, image_path, index)
        if key not in crops:
            raw, table, provenance = album(pack, image_path)
            resolved, seen = index, set()
            while 'link' in table[resolved]:
                assert resolved not in seen
                seen.add(resolved)
                resolved = table[resolved]['link']
            meta = table[resolved]
            empty = meta['width'] == 0 or meta['height'] == 0
            image = Image.new('RGBA', (1, 1)) if empty else decode_frame(raw, index)[0]
            record = {**texture(image, relative), 'img_frame': index, 'resolved_img_frame': resolved,
                'img_metadata': meta, 'source': provenance,
                'operation': 'Empty0x0 source represented by1x1 transparent sentinel' if empty else 'Exact decoded RGBA crop; no resize, repaint, recolor or retouch'}
            crops[key] = (image, record)
            raw_records.append(record)
        return crops[key]

    old_inputs, existing_png_paths = {}, set()
    for appearance, inputs in ACTOR_INPUTS.items():
        old_inputs[appearance] = [json.loads((ROOT / relative).read_text()) for relative in inputs]
        retained_inputs.update({relative: file_sha(ROOT / relative) for relative in inputs})
        for animation in old_inputs[appearance][0]['animations'].values():
            for pose in animation['frames']:
                existing_png_paths.update(layer['texture'].removeprefix('res://') for layer in pose['layers'])
        for animation in old_inputs[appearance][1]['animations'].values():
            existing_png_paths.update(pose['texture'].removeprefix('res://') for pose in animation['frames'])
    existing_png_hashes = {path: file_sha(ROOT / path) for path in sorted(existing_png_paths)}
    master = script(MASTER, True)
    assert len(master['frames']) == 18 and sum(duration(f) for f in master['frames']) == 950
    assert [f['image_frame'] for f in master['frames']] == list(range(139, 157))
    script('character/swordman/swordman.chr')
    script('skill/swordman/hardattack.skl')
    script('character/swordman/attackinfo/hardattack.atk')
    weapon_evidence, appearance_bounds = [], {}
    for appearance, (r0_input, r1_input) in ACTOR_INPUTS.items():
        old_raw, old_derived = old_inputs[appearance]
        assert set(old_raw['animations']) == set(old_derived['animations']) and len(old_raw['animations']) == 14
        assert tuple(old_derived['canvas_size']) == CANVAS and tuple(old_derived['foot_anchor']) == ANCHOR
        raw, derived = copy.deepcopy(old_raw), copy.deepcopy(old_derived)
        family = 'lswd' if appearance == 'practice' else 'mswd'
        weapons = {suffix: script(f'equipment/character/swordman/weapon/hsword/{family}{suffix}/hardattack.ani', True) for suffix in ['b', 'c']}
        for suffix, weapon in weapons.items():
            assert len(weapon['frames']) == len(master['frames'])
            assert all((f['image_frame'], f['x'], f['y']) == (w['image_frame'], w['x'], w['y']) for f, w in zip(master['frames'], weapon['frames']))
            weapon_evidence.append({'appearance': appearance, 'layer': suffix,
                'source_ani': f'equipment/character/swordman/weapon/hsword/{family}{suffix}/hardattack.ani',
                'master_delays_ms': [duration(f) for f in master['frames']], 'weapon_delays_ms': [duration(f) for f in weapon['frames']],
                'runtime_clock': 'Unmodified character master; equipment-layer delays retained only as source evidence'})
        added_raw = {'source_ani': MASTER, 'source_globals': master['globals'],
            'weapon_source_anis': {suffix: f'equipment/character/swordman/weapon/hsword/{family}{suffix}/hardattack.ani' for suffix in ['b', 'c']}, 'frames': []}
        added_derived = {'source_ani': MASTER, 'source_globals': master['globals'], 'frames': []}
        bounds_for_appearance = []
        for frame_index, frame in enumerate(master['frames']):
            layers, bounds = [], []
            for name, pack_suffix, image_path in LAYERS:
                pack = 'sprite_character_swordman_equipment_'+pack_suffix+'.NPK'
                folder = 'shared' if name not in ['weapon_back', 'weapon_front'] else appearance
                if appearance == 'great' and name in ['weapon_back', 'weapon_front']:
                    suffix = 'b' if name == 'weapon_back' else 'c'
                    pack = 'sprite_character_swordman_equipment_weapon_mswd.NPK'
                    image_path = f'weapon/mswd/mswd0007{suffix}.img'
                image, evidence = crop(pack, 'sprite/character/swordman/equipment/'+image_path, frame['image_frame'],
                    f'{ASSETS}/{folder}/src/{name}/{frame["image_frame"]:03d}.png')
                meta = evidence['img_metadata']
                offset = [frame['x']+meta['x'], frame['y']+meta['y']]
                layers.append({'name': name, 'texture': evidence['texture'], 'offset': offset})
                box = image.getchannel('A').getbbox()
                if box:
                    bounds.append([offset[0]+box[0], offset[1]+box[1], offset[0]+box[2], offset[1]+box[3]])
            used = alpha_union(bounds)
            assert used and used[0] >= -ANCHOR[0] and used[1] >= -ANCHOR[1] and used[2] <= CANVAS[0]-ANCHOR[0] and used[3] <= CANVAS[1]-ANCHOR[1], (appearance, frame_index, used)
            bounds_for_appearance.append(used)
            pose = {'duration_ms': duration(frame), 'img_frame': frame['image_frame'], 'ani_offset': [frame['x'], frame['y']],
                'layers': layers, 'source_boxes': frame['boxes'], 'source_properties': frame['properties'],
                'weapon_source_evidence': [{'layer': suffix, 'source_duration_ms': duration(weapons[suffix]['frames'][frame_index]),
                    'source_properties': weapons[suffix]['frames'][frame_index]['properties'],
                    'source_boxes': weapons[suffix]['frames'][frame_index]['boxes'], 'source_globals': weapons[suffix]['globals']} for suffix in ['b', 'c']]}
            added_raw['frames'].append(pose)
            canvas = Image.new('RGBA', CANVAS)
            for layer in layers:
                image = Image.open(ROOT / layer['texture'].removeprefix('res://')).convert('RGBA')
                canvas.alpha_composite(image, (layer['offset'][0]+ANCHOR[0], layer['offset'][1]+ANCHOR[1]))
            result = texture(canvas, f'{ASSETS}/{appearance}/frames/hardattack_{frame_index:02d}.png')
            added_derived['frames'].append({'texture': result['texture'], 'duration_ms': duration(frame), 'img_frame': frame['image_frame'],
                'source_properties': frame['properties'], 'source_boxes': frame['boxes']})
            composite_records.append({**result, 'appearance': appearance, 'action': 'hardattack', 'frame': frame_index,
                'alpha_bounds_relative_to_foot': used, 'layer_textures': [layer['texture'] for layer in layers],
                'layer_offsets': [layer['offset'] for layer in layers], 'operation': 'Nine-layer alpha composite on320x224 foot133,167; no resampling/cropping/retouch'})
        raw['animations']['hardattack'] = added_raw
        derived['animations']['hardattack'] = added_derived
        derived['source_data'] = f'data/swordman_ghost_{appearance}_r0.json'
        for key in old_raw['animations']:
            assert raw['animations'][key] == old_raw['animations'][key]
            assert derived['animations'][key] == old_derived['animations'][key]
        for version, value in [('r0', raw), ('r1', derived)]:
            relative = f'data/swordman_ghost_{appearance}_{version}.json'
            write_json(ROOT / relative, value)
            outputs[relative] = {'sha256': file_sha(ROOT / relative), 'existing14_actions_semantically_exact': True,
                'new_action': 'hardattack', 'actions': len(value['animations'])}
        appearance_bounds[appearance] = alpha_union(bounds_for_appearance)

    tracks = []
    for name, blend in [('hardattack1', 'normal'), ('hardattack2', 'add')]:
        source_ani = 'character/swordman/effect/animation/'+name+'.ani'
        ani = script(source_ani, True)
        clock, frames = 0, []
        for frame in ani['frames']:
            props = [p['value'] for p in frame['properties'] if p['type'] == 11]
            assert props == ([] if blend == 'normal' else [{'effect': 2}])
            item = {'start_ms': clock, 'duration_ms': duration(frame), 'texture': None,
                'offset': [frame['x'], frame['y']], 'source_properties': frame['properties']}
            if frame['resource'] is not None:
                image, evidence = crop('sprite_character_swordman_effect.NPK', 'sprite/'+frame['resource'], frame['image_frame'],
                    f'{ASSETS}/effects/{Path(frame["resource"]).stem}/{frame["image_frame"]:03d}.png')
                meta = evidence['img_metadata']
                item.update(texture=evidence['texture'], offset=[frame['x']+meta['x'], frame['y']+meta['y']], image_frame=frame['image_frame'])
            else:
                assert frame['image_frame'] == -1
            frames.append(item)
            clock += duration(frame)
        assert clock == 550 and [f['start_ms'] for f in frames if f['texture'] is not None] == [150, 200, 250, 300, 350, 400]
        tracks.append({'name': name, 'blend': blend, 'source_ani': source_ani, 'source_globals': ani['globals'], 'duration_ms': clock, 'frames': frames})
    effect_data = {'schema': 1, 'actions': {'hardattack': tracks}, 'audio_actions': {},
        'attachment': 'prototype_pose_time_zero', 'runtime_hooks_implemented': False,
        'notes': ['Original18-frame950ms character master and both550ms effect tracks are unmodified.',
            'An eventual pose-time-zero attachment and normal/add blend selection are explicit prototype interpretations; original ACT dispatch is not recovered.',
            'hardattack1 has no additive type11; hardattack2 retains type11 effect2. Renderer integration must honor per-track blend, retaining existing HopSmash defaults.',
            'Audio remains deliberately unbound: candidate XML/OGG resources exist, but direct base-skill dispatch/timing was not proven.',
            'No damage, cooldown, magic/dark formula, launch movement, cancel or charged branch is implemented by this export.']}
    write_json(ROOT / 'data/ghost_slash_effects.json', effect_data)
    for relative in retained_inputs:
        assert file_sha(ROOT / relative) == retained_inputs[relative], relative
    assert all(file_sha(ROOT / path) == digest for path, digest in existing_png_hashes.items()), 'An existing actor PNG changed during export'
    report = {'schema': 1, 'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'producer': 'tools/r4/export_ghost_slash.py', 'producer_sha256': file_sha(Path(__file__)), 'client': '95',
        'source_pvf_sha256': source_pvf_sha, 'pvf_tree': pvf.header, 'string_encoding': 'Big5',
        'source_scripts': list(scripts.values()), 'source_albums': [value[2] for value in albums.values()],
        'source_crops': raw_records, 'derived_composites': composite_records, 'weapon_timing_evidence': weapon_evidence,
        'actor_outputs': outputs, 'effect_output': {'path': 'data/ghost_slash_effects.json', 'sha256': file_sha(ROOT / 'data/ghost_slash_effects.json')},
        'existing_input_manifests_unchanged': retained_inputs, 'existing_pngs_retained_by_path_and_sha256': existing_png_hashes,
        'alpha_bounds_relative_to_foot': appearance_bounds, 'canvas_size': list(CANVAS), 'foot_anchor': list(ANCHOR),
        'import_profile': PROFILE, 'native_import_checked': False, 'runtime_hooks_implemented': False,
        'counts': {'new_raw_crops': len(raw_records), 'new_composite_frames': len(composite_records),
            'new_pngs': len(raw_records)+len(composite_records), 'pvf_scripts_crc_verified': len(scripts), 'full_actor_manifests': len(outputs)},
        'notes': ['Only new Ghost Slash paths are written. No existing actor JSON, first_equipment, old PNG, scene or runtime script is changed.',
            'Both complete actor variants append only canonical hardattack; all14 existing action objects/texture paths and masterframe metadata compare equal to their inputs.',
            'Skin/apparel0000 and practice weaponlswd0000 remain documented prototype appearance choices; item27304 uses canonicalmswd0007 b/c.',
            'Equipment-layer image indices/offsets match the master; their different50/500ms source delays are preserved, never substituted for the character clock.',
            'Blank source crops use a documented1x1 transparent sentinel; every nonempty crop is exact decoded RGBA and composites have no clipping.',
            'The two independent VFX tracks keep original crop offsets,150ms empty lead, visible150–450ms and550ms total duration.',
            'Requires later authorized native import/render proof, per-track blend integration and a separately labeled adapted gameplay rule. No client engine behavior is executed or claimed.']}
    write_json(ROOT / 'docs/r4_ghost_slash_source_reference.json', report)
    print(json.dumps({'outputs': list(outputs), 'counts': report['counts'], 'alpha_bounds': appearance_bounds,
        'source_reference': 'docs/r4_ghost_slash_source_reference.json', 'native_import_checked': False, 'runtime_hooks_implemented': False}, ensure_ascii=False))


if __name__ == '__main__':
    main()
