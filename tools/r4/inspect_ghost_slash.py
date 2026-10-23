"""Bounded, read-only Ghost Slash feasibility research against working client95.

Only the requested work/ JSON is written. PVF/NPK/IMG/audio are parsed as data;
no client, gameplay script, Godot, Blender, network or paid service is run.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/dnf_client_analysis'))
from inspect_clients import PVF, npk_entries, img_frames, decode_frame, binary_ani
from export_r0 import LAYERS
from export_audio import packets


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def file_sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def section(tokens, name):
    start = next(i for i, token in enumerate(tokens) if token.get('text', '').lower() == name)
    end = next((i for i in range(start + 1, len(tokens)) if tokens[i]['type'] == 5), len(tokens))
    return tokens[start:end]


def frame_delays(ani):
    return [next((p['value'] for p in frame['properties'] if p['type'] == 12), None) for frame in ani['frames']]


def union(boxes):
    boxes = [b for b in boxes if b is not None]
    return [min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes)] if boxes else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path, default=Path('/Users/mac/Downloads/天堂95起源单机客户端'))
    parser.add_argument('--output', type=Path, default=ROOT / 'work/r4_ghost_slash_feasibility.json')
    args = parser.parse_args()
    assert args.output.resolve().is_relative_to((ROOT / 'work').resolve()), 'Research output must stay under work/'
    pvf = PVF(args.client / 'Script.pvf')
    assert pvf.header['tree_crc_actual'] == pvf.header['tree_crc_expected']
    assert not pvf.header['parse_error'] and not pvf.header['payload_bounds_errors']
    sources, albums, packs, crops = {}, {}, {}, {}

    def source(path, animation=False):
        if path not in sources:
            raw, crc = pvf.read(path, True)
            assert crc['expected'] == crc['actual_seed_file_number'], path
            sources[path] = {'path': path, 'bytes': len(raw), 'sha256_decoded_bytes': sha(raw), 'crc': crc, 'crc_matches': True}
            if animation:
                decoded = binary_ani(raw)
                clock = 0
                for frame in decoded['frames']:
                    frame['start_ms'] = clock
                    delay = next((p['value'] for p in frame['properties'] if p['type'] == 12), 0)
                    clock += delay
                sources[path]['decoded'] = decoded
                sources[path]['total_ms'] = clock
            else:
                sources[path]['tokens'] = pvf.tokens(path, 'big5')
        return sources[path]

    def album(pack, image):
        if pack not in packs:
            path = args.client / 'ImagePacks2' / pack
            packs[pack] = {'path': str(path), 'sha256_npk': file_sha(path), 'entries': {e['path']: e for e in npk_entries(path)}}
        key = (pack, image)
        if key not in albums:
            entry = packs[pack]['entries'][image]
            with Path(packs[pack]['path']).open('rb') as stream:
                stream.seek(entry['offset'])
                raw = stream.read(entry['bytes'])
            table, _ = img_frames(raw)
            albums[key] = (raw, table, {'npk': pack, 'npk_sha256': packs[pack]['sha256_npk'], 'img': image,
                'entry': entry, 'sha256_img_payload': sha(raw), 'declared_frames': len(table)})
        return albums[key]

    def crop(pack, image, index):
        key = (pack, image, index)
        if key not in crops:
            raw, table, provenance = album(pack, image)
            resolved, seen = index, set()
            while 'link' in table[resolved]:
                assert resolved not in seen
                seen.add(resolved)
                resolved = table[resolved]['link']
            meta = table[resolved]
            if meta['width'] and meta['height']:
                image_data, _ = decode_frame(raw, index)
                bounds = image_data.getchannel('A').getbbox()
                pixel_sha = sha(image_data.tobytes())
            else:
                bounds, pixel_sha = None, None
            crops[key] = {'npk': pack, 'img': image, 'img_frame': index, 'resolved_img_frame': resolved,
                'img_metadata': meta, 'sha256_rgba': pixel_sha, 'alpha_bounds_in_crop': list(bounds) if bounds else None,
                'album_sha256': provenance['sha256_img_payload']}
        return crops[key]

    chr_path = 'character/swordman/swordman.chr'
    chr_tokens = source(chr_path)['tokens']
    name_path = 'skill/swordman/hardattack.skl'
    skl_tokens = source(name_path)['tokens']
    source('skill/swordman/cancelhardattack.skl')
    source('skill/swordman/hardattackcharge.skl')
    base_path = 'character/swordman/animation/hardattack.ani'
    master = source(base_path, True)['decoded']
    source('character/swordman/attackinfo/hardattack.atk')
    after = source('character/swordman/animation/hardattackchargeafter.ani', True)['decoded']
    old_attack2 = source('character/swordman/animation/attack2.ani', True)['decoded']
    body_delays = frame_delays(master)
    old = json.loads((ROOT / 'data/swordman_r0.json').read_text())['animations']
    new_indices = {frame['image_frame'] for frame in master['frames']}
    existing_intersections = {key: sorted(new_indices & {f['img_frame'] for f in action['frames']}) for key, action in old.items()}
    effects = []
    for key in ['hardattack1', 'hardattack2']:
        path = 'character/swordman/effect/animation/' + key + '.ani'
        effect = source(path, True)['decoded']
        visible = []
        for frame in effect['frames']:
            if frame['resource'] is None:
                continue
            item = crop('sprite_character_swordman_effect.NPK', 'sprite/' + frame['resource'], frame['image_frame'])
            bounds = item['alpha_bounds_in_crop']
            meta = item['img_metadata']
            if bounds:
                visible.append([frame['x'] + meta['x'] + bounds[0], frame['y'] + meta['y'] + bounds[1],
                    frame['x'] + meta['x'] + bounds[2], frame['y'] + meta['y'] + bounds[3]])
        effects.append({'source_ani': path, 'canonical_npk': 'sprite_character_swordman_effect.NPK',
            'total_ms': sources[path]['total_ms'], 'first_visible_ms': min(f['start_ms'] for f in effect['frames'] if f['resource'] is not None),
            'visible_end_ms': max(f['start_ms'] + next(p['value'] for p in f['properties'] if p['type'] == 12) for f in effect['frames'] if f['resource'] is not None),
            'alpha_bounds_relative_to_hero_foot': union(visible), 'globals': effect['globals'],
            'blend_evidence': sorted({json.dumps(p['value'], sort_keys=True) for f in effect['frames'] for p in f['properties'] if p['type'] == 11})})

    pose_bounds, weapon_evidence = [], []
    for appearance in ['practice_lswd0000', '27304']:
        weapon_anis = {}
        for suffix in ['b', 'c']:
            family = 'lswd' if appearance == 'practice_lswd0000' else 'mswd'
            path = f'equipment/character/swordman/weapon/hsword/{family}{suffix}/hardattack.ani'
            weapon = source(path, True)['decoded']
            assert len(weapon['frames']) == len(master['frames'])
            assert all((f['image_frame'], f['x'], f['y']) == (w['image_frame'], w['x'], w['y']) for f, w in zip(master['frames'], weapon['frames']))
            weapon_anis[suffix] = weapon
            weapon_evidence.append({'appearance': appearance, 'layer': suffix, 'source_ani': path,
                'same_master_indices_offsets': True, 'master_delays_ms': body_delays, 'weapon_delays_ms': frame_delays(weapon),
                'timing_matches_master': frame_delays(weapon) == body_delays})
        for index, frame in enumerate(master['frames']):
            bounds = []
            for name, pack_suffix, image_path in LAYERS:
                pack = 'sprite_character_swordman_equipment_' + pack_suffix + '.NPK'
                if appearance == '27304' and name in ['weapon_back', 'weapon_front']:
                    suffix = 'b' if name == 'weapon_back' else 'c'
                    pack = 'sprite_character_swordman_equipment_weapon_mswd.NPK'
                    image_path = f'weapon/mswd/mswd0007{suffix}.img'
                item = crop(pack, 'sprite/character/swordman/equipment/' + image_path, frame['image_frame'])
                box = item['alpha_bounds_in_crop']
                meta = item['img_metadata']
                if box:
                    bounds.append([frame['x']+meta['x']+box[0], frame['y']+meta['y']+box[1],
                        frame['x']+meta['x']+box[2], frame['y']+meta['y']+box[3]])
            used = union(bounds)
            pose_bounds.append({'appearance': appearance, 'frame': index, 'img_frame': frame['image_frame'],
                'alpha_bounds_relative_to_foot': used, 'fits_current320x224_foot133_167': used[0] >= -133 and used[1] >= -167 and used[2] <= 187 and used[3] <= 57})

    xml_path = args.client / 'audio.xml'
    tags = {node.attrib['ID']: node for node in ET.fromstring(xml_path.read_bytes()) if 'ID' in node.attrib}
    sound_candidates = []
    for tag, pack in [('SM_GUE_ATK_01', 'sounds_char_swordman.npk'), ('SM_GUE_ATK_02', 'sounds_char_swordman.npk'),
                      ('SM_GUE_CHARGE', 'sounds_char_swordman.npk'), ('GHOSTSLASH_CRY', 'sounds_effect.npk'), ('GHOSTSLASH_CHARGE_END', 'sounds_effect.npk')]:
        attributes = dict(tags[tag].attrib)
        path = args.client / 'SoundPacks' / pack
        entries = {e['path']: e for e in npk_entries(path, False)}
        entry_path = attributes['FILE'].replace('\\', '/').lower()
        entry = entries[entry_path]
        with path.open('rb') as stream:
            stream.seek(entry['offset'])
            raw = stream.read(entry['bytes'])
        assert raw.startswith(b'OggS')
        ogg_packets = packets(raw)
        sound_candidates.append({'tag': tag, 'canonical_npk': pack, 'xml_attributes': attributes, 'entry': entry,
            'sha256_ogg_source': sha(raw), 'sha256_vorbis_audio_packets': sha(b''.join(ogg_packets[3:])), 'ogg_packets': len(ogg_packets),
            'direct_base_skill_dispatch_proven': False})
    # Bounded dispatch search: selected base files and names containing hardattack/ghostslash only.
    audio_names = ['SM_GUE_ATK_01', 'SM_GUE_ATK_02', 'R_SM_GUE', 'SM_GUE_CHARGE', 'GHOSTSLASH_CRY', 'GHOSTSLASH_CHARGE_END']
    search_paths = sorted(path for path in pvf.entries if ('hardattack' in path or 'ghostslash' in path)
        and path.endswith(('.act', '.nut', '.skl', '.atk')) and ('swordman' in path or 'wooden_doll' in path))
    direct_refs, dispatch_proofs = [], []
    for path in search_paths:
        raw, crc = pvf.read(path, True)
        assert crc['expected'] == crc['actual_seed_file_number'], path
        dispatch_proofs.append({'path': path, 'sha256_decoded_bytes': sha(raw), 'crc': crc, 'crc_matches': True})
        decoded = pvf.tokens(path, 'big5')
        texts = [t.get('text', '') for t in decoded] if isinstance(decoded, list) else raw.decode('utf8', 'replace').splitlines()
        direct_refs.extend({'path': path, 'text': text} for text in texts if any(tag in text.upper() for tag in audio_names))
    chr_refs = [{'token_index': i, 'token': token} for i, token in enumerate(chr_tokens) if 'hardattack' in token.get('text', '').lower()]
    report = {'format': 'dnf-r4-ghost-slash-feasibility-v1', 'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'scope': __doc__.strip(), 'producer': str(Path(__file__).relative_to(ROOT)), 'producer_sha256': file_sha(Path(__file__)),
        'reproduce': 'python3 tools/r4/inspect_ghost_slash.py', 'client': '95', 'client_root': str(args.client), 'translation_encoding': 'Big5',
        'source_pvf_sha256': file_sha(args.client / 'Script.pvf'), 'pvf_tree': pvf.header,
        'identification': {'name': section(skl_tokens, '[name]'), 'explain': section(skl_tokens, '[explain]'),
            'source_command': section(skl_tokens, '[command]'), 'source_command_hint': section(skl_tokens, '[command key explain]'),
            'dungeon_cool_time': section(skl_tokens, '[cool time]'), 'chr_direct_references': chr_refs,
            'excluded_similar_name': 'ghostsidewind is鬼影鞭, not鬼斬; new2018 hardattack_0/hardattack_hell and charged soul branches are outside this first skill.'},
        'existing14_action_reuse': {'current_actions': list(old), 'hardattack_img_intersections': existing_intersections,
            'ordinary_hardattack_reuses_existing_master': False,
            'chargeafter_vs_attack2': {'img_indices_equal': [f['image_frame'] for f in after['frames']] == [f['image_frame'] for f in old_attack2['frames']],
                'delays_equal': frame_delays(after) == frame_delays(old_attack2), 'offsets_equal': [(f['x'], f['y']) for f in after['frames']] == [(f['x'], f['y']) for f in old_attack2['frames']],
                'complete_decoded_equal': after == old_attack2,
                'note': 'The charged follow-up uses existing attack2 pictures and clock, but is a distinct source ANI with properties/boxes retained. It is not the ordinary Ghost Slash master.'}},
        'ordinary_master': {'source_ani': base_path, 'frames': len(master['frames']), 'total_ms': sources[base_path]['total_ms'],
            'img_indices': sorted(new_indices), 'source_boxes_types': sorted({b['type'] for f in master['frames'] for b in f['boxes']}),
            'property23': [{'frame': i, 'start_ms': f['start_ms'], 'raw': p['value']} for i, f in enumerate(master['frames']) for p in f['properties'] if p['type'] == 23],
            'attack_window_status': 'No type15 attack box occurs in this body ANI. Type23=65534 is preserved as an uninterpreted source marker, not claimed as a hit event.'},
        'weapon_alignment': weapon_evidence, 'pose_bounds': pose_bounds,
        'all36_pose_variants_fit_current_actor_canvas': all(p['fits_current320x224_foot133_167'] for p in pose_bounds),
        'appearance_alpha_union_bounds': {key: union([p['alpha_bounds_relative_to_foot'] for p in pose_bounds if p['appearance'] == key]) for key in ['practice_lswd0000', '27304']},
        'camera_scope': {'grounded_skill_only': True, 'effect_union_bounds': union([e['alpha_bounds_relative_to_hero_foot'] for e in effects]),
            'both_facings_max_horizontal_extent': max(abs(n) for e in effects for n in (e['alpha_bounds_relative_to_hero_foot'][0], e['alpha_bounds_relative_to_hero_foot'][2])),
            'current_horizontal_safety_extent_px': 184, 'requires_larger_canvas_or_horizontal_deadzone': False,
            'reason': 'All body alpha fits the existing canvas, and both independently attached effects fit within159px of the foot in either facing, leaving25px against the184px edge framing budget. No airborne Ghost Slash is proposed.'},
        'effects': effects, 'source_albums': [value[2] for value in albums.values()], 'crop_proofs': list(crops.values()),
        'audio': {'audio_xml_sha256': file_sha(xml_path), 'candidates': sound_candidates,
            'xml_random_group_R_SM_GUE': [dict(child.attrib) for child in tags['R_SM_GUE']], 'bounded_dispatch_search_paths': search_paths,
            'bounded_dispatch_search_crc_proofs': dispatch_proofs,
            'bounded_dispatch_references': direct_refs, 'binding_status': 'The tags/files and50:50 voice group exist, but selected base CHR/ANI/SKL/ATK do not bind them. No base male Swordman .act exists. Do not label a chosen start/swing/contact cue as restored native timing.'},
        'sources': list(sources.values()),
        'recommendation': {'feasible': True, 'skill_key': 'ghost_slash', 'input': 'Z (currently unused prototype key; original source command is heldUp+Z)',
            'first_version': 'Grounded single directional slash with one attack_instance and cooldown; keep all18 original pose frames950ms and both original550ms effect tracks. Exclude charge, soul after-images, launch physics, native magic/dark formulas and cancel trees initially.',
            'adapted_active_ms': [150, 450], 'window_basis': 'With an explicitly adapted pose-time-zero attachment, both visual tracks first render150ms and their last visible image ends450ms. This is a proposed adapted damage window, not recovered ACT dispatch.',
            'cooldown_ms': 6000, 'cooldown_basis': 'Source dungeon SKL [cool time]6000/6000; the prototype has no MP system, so MP/level costs stay provenance.',
            'damage_range_depth': 'Choose and label separate prototype tuning after visual/reach review; do not directly use source percentage magic/dark damage or push/lift300 as HP/pixels.',
            'engineering_scope': ['New18 master poses for seven shared body/apparel layers and two weapon appearances;18x9 current layers +36 alternative weapon crops before link dedup.',
                'Two weapon-specific ANI clocks differ from master if shown in weapon_alignment; retain character master clock as existing appearance pipeline does.',
                'Append action consistently to bothR0/R1 appearance definitions; current EquipmentAppearance enforces matching action sets/frame counts/boxes, so adding only default appearance would reject swapping.',
                'Add twelve normal/additive VFX crops from one canonical pack; preserve offsets and empty delay frames. Normal blend for hardattack1, type11 effect2 retained for hardattack2 with an explicitly adapted additive interpretation.',
                'New skill input/action/cooldown, both combat controllers shared-hit tuning, pause/menu/bag/inspection/reset gates, camera/alpha bounds and focused native proof. F5 locomotion clips need no new inbetweens for this action.'],
            'audio_policy': 'Candidate source OGGs are available. Bind only after a declared prototype timing choice or stronger direct source event evidence; do not invent a native voice mapping.',
            'risks': ['No base characterACT dispatcher is exposed; bodyANI has hurt boxes only, so exact damage start/cancel/hit semantics remain adapted.',
                'Check pose_bounds and effect relative-foot bounds before claiming existing fixed canvas/camera margins fit. Do not clip or rescale original art to force a fit.',
                'Type23 markers and optional charged/2018 rework branches remain outside scope.']} }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({'output': str(args.output), 'master_frames': len(master['frames']), 'master_ms': sources[base_path]['total_ms'],
        'pvf_crc_files': len(sources), 'source_crops_decoded': len(crops), 'fits_current_canvas': report['all36_pose_variants_fit_current_actor_canvas'],
        'appearance_bounds': {key: union([p['alpha_bounds_relative_to_foot'] for p in pose_bounds if p['appearance'] == key]) for key in ['practice_lswd0000', '27304']},
        'effect_bounds': effects, 'chargeafter_reuse': report['existing14_action_reuse']['chargeafter_vs_attack2'], 'direct_audio_refs': direct_refs}, ensure_ascii=False))


if __name__ == '__main__':
    main()
