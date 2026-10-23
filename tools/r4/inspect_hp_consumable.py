"""Read-only, narrowly scoped95client potion/shop feasibility; writes only its work JSON."""
from pathlib import Path
import datetime
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/dnf_client_analysis'))
from inspect_clients import PVF, npk_entries, img_frames, decode_frame

CLIENT = Path('/Users/mac/Downloads/天堂95起源单机客户端')
ITEM_ID = 1106
ITEM_SCRIPT = 'stackable/ptn_hplowest.stk'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(data)
    return h.hexdigest()


def sections(tokens):
    assert isinstance(tokens, list)
    result = []
    for token in tokens:
        if token['type'] == 5:
            result.append({'tag': token['text'], 'values': []})
        elif result:
            result[-1]['values'].append(token.get('text', token.get('value')))
    return result


def section(blocks, tag):
    return next((row['values'] for row in blocks if row['tag'] == tag), None)


def pairs(tokens):
    return list(zip(tokens[::2], tokens[1::2]))


def main():
    pvf = PVF(CLIENT / 'Script.pvf')
    assert pvf.header['tree_crc_actual'] == pvf.header['tree_crc_expected']
    assert not pvf.header['parse_error'] and not pvf.header['payload_bounds_errors']
    evidence = {}

    def source(path):
        if path not in evidence:
            raw, crc = pvf.read(path, True)
            assert crc['expected'] == crc['actual_seed_file_number'], path
            evidence[path] = {'path': path, 'bytes': len(raw), 'sha256_decoded': sha(raw),
                              'crc': crc, 'crc_matches': True}
        return evidence[path]

    def tokens(path):
        source(path)
        return pvf.tokens(path, 'big5')

    stack_pairs = pairs(tokens('stackable/stackable.lst'))
    stack_map = {a['value']: 'stackable/' + b['text'].lower() for a, b in stack_pairs}
    selected_pair = next([a, b] for a, b in stack_pairs if a['value'] == ITEM_ID)
    assert stack_map[ITEM_ID] == ITEM_SCRIPT
    item = sections(tokens(ITEM_SCRIPT))
    string_pair = next([a, b] for a, b in pairs(tokens('n_string.lst')) if a['value'] == 13)
    dictionary_path = string_pair[1]['text'].lower()
    source(dictionary_path)
    text = pvf.read(dictionary_path).decode('big5', 'replace')
    strings = {line.split('>', 1)[0]: line.split('>', 1)[1] for line in text.splitlines()
               if '>' in line and not line.startswith('//')}
    assert strings['name_1106'] == '諾頓的新手HP藥劑'
    assert section(item, '[name]') == [13, 'name_1106']
    assert section(item, '[hp recovery]') == ['+', 70, 1000, 'myself']
    assert section(item, '[price]') == [100]
    assert section(item, '[cool time]') == [10000]

    shop_pairs = pairs(tokens('itemshop/itemshop.lst'))
    shops = {a['value']: 'itemshop/' + b['text'].lower() for a, b in shop_pairs}

    def direct_shop(npc):
        path = 'npc/' + npc + '.npc'
        role = section(sections(tokens(path)), '[role]')
        shop_id = role[role.index('[item shop]') + 1]
        shop_path = shops[shop_id]
        blocks = sections(tokens(shop_path))
        raw = section(blocks, '[sell item]')
        return {'npc_path': path, 'role_values': role, 'itemshop_id': shop_id,
                'shop_path': shop_path, 'shop_npc': section(blocks, '[NPC]'),
                'shop_type': section(blocks, '[type]'), 'raw_sell_item': raw,
                'has_selected_item': ITEM_ID in raw}

    sharan = direct_shop('sharan')
    lorian = direct_shop('lorian')
    assert sharan['itemshop_id'] == 16 and sharan['shop_path'] == 'itemshop/magic2.shp'
    assert sharan['shop_npc'] == [12] and not sharan['has_selected_item']
    assert lorian['itemshop_id'] == 6 and lorian['shop_path'] == 'itemshop/magic1.shp'
    assert lorian['shop_npc'] == [10] and lorian['has_selected_item']
    direct_rows = []
    for item_id in dict.fromkeys(value for value in sharan['raw_sell_item'] if value >= 0):
        path = stack_map[item_id]
        blocks = sections(tokens(path))
        direct_rows.append({'item_id': item_id, 'pvf': path,
                            'stackable_type': section(blocks, '[stackable type]'),
                            'hp_recovery': section(blocks, '[hp recovery]')})
    assert len(direct_rows) == 72
    assert all(row['stackable_type'] == ['[recipe]', 0] and row['hp_recovery'] is None
               for row in direct_rows)
    sharan.update({'direct_items_checked': direct_rows, 'direct_item_count': len(direct_rows),
                   'HP_recovery_item_count': 0, 'conclusion': 'This direct95shop sells recipes only, not the selected potion or another direct HP-recovery consumable.'})

    images = {}
    for role, pack, img, index in [
        ('icon', 'sprite_item_stackable.NPK', 'sprite/item/stackable/consumption.img', 148),
        ('field', 'sprite_item.NPK', 'sprite/item/field_consumption.img', 7),
    ]:
        pack_path = CLIENT / 'ImagePacks2' / pack
        entry = next(row for row in npk_entries(pack_path) if row['path'] == img)
        with pack_path.open('rb') as stream:
            stream.seek(entry['offset'])
            raw = stream.read(entry['bytes'])
        frames, _ = img_frames(raw)
        resolved, seen = index, set()
        while 'link' in frames[resolved]:
            assert resolved not in seen
            seen.add(resolved)
            resolved = frames[resolved]['link']
        image, metadata = decode_frame(raw, index)
        images[role] = {'npk': pack, 'npk_sha256': file_sha(pack_path), 'img': img,
                        'img_index': index, 'resolved_img_index': resolved,
                        'size': list(image.size), 'metadata': metadata,
                        'entry': entry, 'sha256_img_payload': sha(raw),
                        'sha256_decoded_RGBA': sha(image.tobytes()),
                        'alpha_range': list(image.getchannel('A').getextrema()),
                        'exported': False,
                        'policy': 'Exact source crop located/decoded only. No PNG/runtime asset created.'}
    assert section(item, '[icon]') == ['Item/stackable/consumption.img', 148]
    assert section(item, '[field image]') == ['Item/field_consumption.img', 7]

    report = {
        'schema': 1, 'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'scope': 'Read-only95client feasibility; one lowest-tier candidate plus72 direct Sharan recipe references and one direct Lorian shop. No all-item catalog survey, client execution, Internet, production/runtime/profile edits or image export.',
        'source_client': str(CLIENT), 'pvf_header': pvf.header,
        'selected_item': {'item_id': ITEM_ID, 'pvf': ITEM_SCRIPT, 'list_pair': selected_pair,
                          'name_big5': strings['name_1106'], 'name_simplified': '诺顿的新手HP药剂',
                          'name2_source': strings['name2_1106'],
                          'name_dictionary': {'id': 13, 'path': dictionary_path,
                                              'keys': {key: strings[key] for key in ['name_1106', 'name2_1106', 'explain_1106', 'flavor_text_1106']}},
                          'all_source_sections': item, 'images': images},
        'source_value_boundary': {
            'minimum_level_raw': [1], 'grade_raw': [3], 'stack_limit_raw': [1000],
            'price_raw': [100], 'cool_time_raw': [10000], 'cooltime_group_raw': [0],
            'hp_recovery_raw': ['+', 70, 1000, 'myself'],
            'what_is_known': 'The source names an HP potion and literally supplies additive-mode+, value70, another parameter1000, targetmyself. price100 and cool time10000 are direct STK values.',
            'not_claimed': 'No recovered original item-use engine, exact timing interpretation of the1000parameter, source character maxHP/scaling, NPC final-price multiplier, potion-group sharing rules or source use/FX/sound dispatch is implemented or asserted. POTION_TOUCH is [move wav], not proof of a drinking sound.',
            'source_move_wav': section(item, '[move wav]')},
        'shop_boundary': {'sharan': sharan, 'verified_lorian_supplier': lorian,
                          'source_explain_boundary': 'explain_1106 listsNorton/Seria/Linus/Lorian. This report relies on current direct Lorian NPC→shop6→magic1.shp membership, not on assuming every textual vendor hint remains accurate in this modified95pack.',
                          'recommended_vendor': 'Existing harbor Lorian is source-backed for this potion. Sharan keeps free session rest; adding potion sales to her would be a new prototype vendor adaptation, not the direct source shop.'},
        'bounded_prototype_proposal': {
            'status': 'Proposal only; no gameplay/save schema changes in this task.',
            'item_identity_and_pixels': 'Use only source item1106 and exact consumption.img148; future exporter can separately preserve field_consumption.img7. Do not relabel the recipe shop as an original potion shop.',
            'adapted_tuning': {'buy_cost_coins': 10, 'heal_HP': None, 'use_cooldown_seconds': 10,
                               'carried_count_cap': 3, 'automatic_rest_reset': False,
                               'label': 'Root favors10prototype coins; healing remains explicitly TBD by root. Cooldown10seconds/carrycap3 remain proposals for the100HP route/one40coin reward, not original effect/cap. The10second cooldown would be an adaptation despite numerically matching10000if read as milliseconds.'},
            'purchase_flow': 'Keep Lorian E quest conversation; when it is completed expose one compact补给option/button: source-name potion ×1 for10prototype coins. Disable while poor/cap reached/pending save. Coins decrease and count increases in one successful profile transaction; failed save leaves both unchanged.',
            'use_flow': 'One deliberate hotkey in hall/depths when grounded/free, alive, injured, count>0 and useCDready. Do not interrupt/source-play a fabricated drinking animation. Atomically commit count-1 before healing min(100,hp+adapted_heal_HP), with adapted_heal_HP still TBD by root; only a successful transaction heals/starts sessionCD. Menus/dialogs/bag/fade/pause/inspection/preview/KO block use; actual movement/combat gates should be explicitly tuned later.',
            'health_sync': 'When inside an encounter, change that live controller.player_hp plus its_persist() to update route_hero_hp and its snapshot; setting route_hero_hp alone is insufficient because the current controller owns and will repersist liveHP. Preserve enemyHP/cleared/counters and historical quest/chapter receipts.',
            'existing_profile_constraint': {'file': 'scripts/adventure_progress.gd', 'line': 482,
                                            'finding': 'Schema4 _valid_quest currently requires coins exactly40after reward (0before); spending cannot be bolted onto the present validator. A later explicitly authorized schema/migration must represent spendable balance and potion count while retaining exactly-once reward and old backups. No schema is changed here.'},
            'R_and_rest': 'Practice R and Sharan free rest must never refund consumed potion inventory or spent coins. Sharan remains a free port HP option; potions are for limited field recovery. Session cooldown/reset policy should be defined explicitly before implementation.',
            'not_in_scope': ['Additional consumable types or merchants', 'Original shop economy/discount engine', 'New quests/rewards or money farming', 'Reviving afterKO', 'Unproven potion-use voices/FX']},
        'source_checks': list(evidence.values()),
        'all_source_CRC_match': True, 'analyzer': 'work/inspect_hp_consumable.py',
        'analyzer_sha256': file_sha(Path(__file__)),
    }
    output = ROOT / 'work/r4_hp_consumable_feasibility.json'
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'report': str(output), 'item_id': ITEM_ID,
                      'name_big5': strings['name_1106'], 'source_CRC_checks': len(evidence),
                      'Sharan_direct_items': 72, 'Sharan_HP_items': 0,
                      'Lorian_direct_shop_has1106': True, 'icon_size': images['icon']['size']},
                     ensure_ascii=False))


if __name__ == '__main__':
    main()
