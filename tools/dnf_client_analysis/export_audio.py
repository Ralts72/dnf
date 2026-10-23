"""Copy an explicit sound whitelist, byte for byte, from canonical source NPKs.

audio.xml supplies tag resolution and random weights. Action timing and the
square-sword choice below are sample mappings, not recovered engine behavior.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import xml.etree.ElementTree as ET

from inspect_clients import npk_entries

ROOT = Path(__file__).resolve().parents[2]
PACK_TAGS = {
    'sounds_char_swordman.npk': ['SM_ATK_01', 'SM_ATK_02', 'SM_ATK_03', 'SM_JUMP',
                                'SM_JUMP_ATK_01', 'SM_JUMP_ATK_02'],
    'sounds_effect.npk': ['JUMP_START', 'JUMP_END'],
    'sounds_char_swordman_weapon.npk': ['SQUARESWDA_01', 'SQUARESWDA_02',
                                       'SQUARESWDB', 'SQUARESWDC_01'],
}
GROUPS = ['R_SM_ATK', 'R_SM_JUMP_ATK', 'R_SQUARESWDA', 'R_SQUARESWDC']


def sha(data):
    return hashlib.sha256(data).hexdigest()


def ogg_crc(raw):
    value = 0
    for byte in raw:
        value ^= byte << 24
        for _ in range(8):
            value = ((value << 1) ^ (0x04C11DB7 if value & 0x80000000 else 0)) & 0xffffffff
    return value


def packets(raw):
    result, partial, pos = [], bytearray(), 0
    while pos < len(raw):
        assert raw[pos:pos + 4] == b'OggS'
        count = raw[pos + 26]
        segments = raw[pos + 27:pos + 27 + count]
        offset = pos + 27 + count
        for size in segments:
            partial.extend(raw[offset:offset + size])
            offset += size
            if size < 255:
                result.append(bytes(partial))
                partial.clear()
        pos = offset
    assert not partial
    return result


def normalize_comments(raw):
    """Fix only bare comments in the known, single-segment comment header.

    All identification/setup/audio packets and timing headers stay unchanged.
    The original source OGG is retained separately. No decode or re-encode.
    """
    result, pos, changed = bytearray(), 0, 0
    while pos < len(raw):
        count = raw[pos + 26]
        segments = bytearray(raw[pos + 27:pos + 27 + count])
        offset = pos + 27 + count
        payload = raw[offset:offset + sum(segments)]
        header = bytearray(raw[pos:pos + 27])
        if payload.startswith(b'\x03vorbis'):
            assert segments[0] < 255 and not header[5] & 1
            packet = payload[:segments[0]]
            vendor_len = struct.unpack_from('<I', packet, 7)[0]
            cursor = 11 + vendor_len
            comment_count = struct.unpack_from('<I', packet, cursor)[0]
            fixed = bytearray(packet[:cursor + 4])
            cursor += 4
            for _ in range(comment_count):
                size = struct.unpack_from('<I', packet, cursor)[0]
                comment = packet[cursor + 4:cursor + 4 + size]
                cursor += 4 + size
                if b'=' not in comment:
                    comment = b'COMMENT=' + comment
                    changed += 1
                fixed.extend(struct.pack('<I', len(comment)) + comment)
            fixed.extend(packet[cursor:])
            assert len(fixed) < 255
            payload = bytes(fixed) + payload[segments[0]:]
            segments[0] = len(fixed)
            header[22:26] = b'\0' * 4
            page = header + segments + payload
            struct.pack_into('<I', page, 22, ogg_crc(page))
            result.extend(page)
        else:
            result.extend(raw[pos:offset + sum(segments)])
        pos = offset + sum(raw[pos + 27:pos + 27 + count])
    source_packets, output_packets = packets(raw), packets(result)
    assert len(source_packets) == len(output_packets)
    assert all(a == b for i, (a, b) in enumerate(zip(source_packets, output_packets)) if i != 1)
    assert changed == 1
    return bytes(result), {'comments_fixed': changed, 'audio_packets': len(source_packets) - 3,
                           'audio_packet_sha256': sha(b''.join(source_packets[3:])),
                           'all_noncomment_packets_identical': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path, default=Path('/Users/mac/Downloads/天堂95起源单机客户端'))
    args = parser.parse_args()
    xml_path = args.client / 'audio.xml'
    xml_raw = xml_path.read_bytes()
    tree = ET.fromstring(xml_raw)
    tags = {x.attrib['ID']: x for x in tree if 'ID' in x.attrib}
    sounds, packs = {}, {}
    for pack, selected in PACK_TAGS.items():
        source = args.client / 'SoundPacks' / pack
        pack_raw = source.read_bytes()
        packs[pack] = {'sha256': sha(pack_raw), 'bytes': len(pack_raw)}
        entries = {e['path']: e for e in npk_entries(source, False)}
        for tag in selected:
            attributes = dict(tags[tag].attrib)
            path = attributes['FILE'].replace('\\', '/').lower()
            entry = entries[path]
            raw = pack_raw[entry['offset']:entry['offset'] + entry['bytes']]
            assert raw.startswith(b'OggS'), path
            original = ROOT / 'source_art/audio' / (tag.lower() + '.ogg')
            original.parent.mkdir(parents=True, exist_ok=True)
            original.write_bytes(raw)
            normalized, proof = normalize_comments(raw)
            target = ROOT / 'assets/r0/audio' / (tag.lower() + '.ogg')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(normalized)
            sounds[tag] = {'path': 'res://' + target.relative_to(ROOT).as_posix(),
                           'pack': pack, 'entry': path, 'offset': entry['offset'],
                           'bytes': len(raw), 'sha256': sha(raw), 'xml_attributes': attributes,
                           'retained_original': original.relative_to(ROOT).as_posix(),
                           'runtime_sha256': sha(normalized), 'metadata_fix': proof}
    groups = {tag: [{'tag': x.attrib['TAG'], 'weight': int(x.attrib['PROB'])}
                    for x in tags[tag]] for tag in GROUPS}
    assert all(item['tag'] in sounds for items in groups.values() for item in items)
    # Ground swing cues align with the chosen visible stroke, air swing with
    # the first source type-15 box. Neither is claimed as an original sound tag.
    actions = {
        'attack1': [{'at_ms': 0, 'tag': 'R_SM_ATK'}, {'at_ms': 150, 'tag': 'R_SQUARESWDA'}],
        'attack2': [{'at_ms': 0, 'tag': 'R_SM_ATK'}, {'at_ms': 150, 'tag': 'SQUARESWDB'}],
        'attack3': [{'at_ms': 0, 'tag': 'R_SM_ATK'}, {'at_ms': 100, 'tag': 'R_SQUARESWDC'}],
        'jumpattack': [{'at_ms': 0, 'tag': 'R_SM_JUMP_ATK'}, {'at_ms': 150, 'tag': 'R_SQUARESWDC'}],
    }
    notes = ['Original OGG payloads retained unchanged in source_art/audio; only explicit canonical NPKs are used.',
             'Runtime OGG files prefix one bare Vorbis comment with COMMENT= and update its page CRC; all noncomment packets are identical.',
             'Tag paths and random probabilities come from audio.xml.',
             'Action timing is inferred for this sample; source ANI has no type-16 sound properties.',
             'The square-sword family is selected for the lswd visual sample; original weapon-to-sound dispatch is not recovered.',
             'No hit, damage or hopsmash sound is assigned without corresponding gameplay.']
    runtime = {'schema': 1, 'sounds': {k: {'path': v['path']} for k, v in sounds.items()},
               'groups': groups, 'actions': actions,
               'jump': {'takeoff': ['JUMP_START', 'SM_JUMP'], 'landing': ['JUMP_END']},
               'default_volume': 0.6, 'source_reference': 'docs/r1_audio_source_reference.json', 'notes': notes}
    reference = {'client': str(args.client), 'audio_xml_sha256': sha(xml_raw), 'packs': packs,
                 'sounds': sounds, 'groups': groups, 'mapping': runtime, 'notes': notes}
    for path, data in [('data/swordman_audio.json', runtime), ('docs/r1_audio_source_reference.json', reference)]:
        (ROOT / path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'sounds': len(sounds), 'bytes': sum(s['bytes'] for s in sounds.values()),
                      'groups': len(groups), 'reference': 'docs/r1_audio_source_reference.json'}))


if __name__ == '__main__':
    main()
