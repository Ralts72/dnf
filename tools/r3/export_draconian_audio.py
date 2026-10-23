"""Prepare only the source-bound Mirkius spear-contact sound.

Mirkius attack/hurt/death voice dispatch is unresolved. Dragonman-family XML
tags are retained as candidates, without exporting or assigning their voices.
No runtime hook or client/Godot execution is performed by this tool.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/dnf_client_analysis'))
from inspect_clients import PVF, npk_entries, binary_ani
from export_audio import packets, normalize_comments, ogg_crc

PACK_TAGS = {'sounds_effect.npk': ['SPEAR_HIT']}
FAMILY_CANDIDATES = ['DRAGONMAN_ATK_SHORT', 'DRAGONMAN_ATK_LONG', 'DRAGONMAN_ATK',
                     'DRAGONMAN_DMG', 'DRAGONMAN_DIE', 'R_DRAGONMAN_DMG']
MAX_SOURCE_SOUNDS = 6
MAX_SOURCE_BYTES_PER_SOUND = 512 * 1024


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_sha(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def page_audit(raw):
    position = 0
    pages = []
    while position < len(raw):
        assert raw[position:position + 4] == b'OggS'
        count = raw[position + 26]
        header_end = position + 27 + count
        end = header_end + sum(raw[position + 27:header_end])
        assert end <= len(raw)
        page = bytearray(raw[position:end])
        expected = struct.unpack_from('<I', page, 22)[0]
        page[22:26] = b'\0' * 4
        assert expected == ogg_crc(page)
        pages.append({'sequence': struct.unpack_from('<I', page, 18)[0],
                      'serial': struct.unpack_from('<I', page, 14)[0],
                      'granule_position': struct.unpack_from('<Q', page, 6)[0],
                      'flags': page[5], 'crc_valid': True})
        position = end
    assert position == len(raw)
    return pages


def decoded_audio(path, ffmpeg, ffprobe):
    probe = subprocess.run([ffprobe, '-v', 'error', '-show_entries',
                            'stream=codec_name,sample_rate,channels:format=duration',
                            '-of', 'json', str(path)], capture_output=True, check=True, timeout=30)
    metadata = json.loads(probe.stdout)
    assert len(metadata['streams']) == 1
    stream = metadata['streams'][0]
    assert stream['codec_name'] == 'vorbis'
    assert float(metadata['format']['duration']) <= 10.0
    pcm = subprocess.run([ffmpeg, '-v', 'error', '-i', str(path), '-map', '0:a:0',
                          '-f', 'f32le', '-acodec', 'pcm_f32le', 'pipe:1'],
                         capture_output=True, check=True, timeout=30).stdout
    assert 0 < len(pcm) < 10 * 192000 * 8 * 4
    channels = int(stream['channels'])
    assert len(pcm) % (channels * 4) == 0
    return pcm, {'decoder': 'ffmpeg', 'format': 'interleaved float32 little-endian',
                 'sample_rate': int(stream['sample_rate']), 'channels': channels,
                 'frames': len(pcm) // (channels * 4), 'bytes': len(pcm),
                 'sha256': sha(pcm), 'container_duration_seconds': float(metadata['format']['duration'])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path, default=Path('/Users/mac/Downloads/天堂95起源单机客户端'))
    args = parser.parse_args()
    ffmpeg = shutil.which('ffmpeg')
    ffprobe = shutil.which('ffprobe')
    assert ffmpeg and ffprobe, 'Local ffmpeg/ffprobe required for byte-identical PCM verification'
    client = args.client
    xml_raw = (client / 'audio.xml').read_bytes()
    xml = ET.fromstring(xml_raw)
    tags = {node.attrib['ID']: node for node in xml if 'ID' in node.attrib}
    pvf = PVF(client / 'Script.pvf')
    assert pvf.header['tree_crc_actual'] == pvf.header['tree_crc_expected']
    assert not pvf.header['payload_bounds_errors'] and not pvf.header['parse_error']
    atk_path = 'monster/draconian/dmattackinfo/attack.atk'
    raw_atk, atk_crc = pvf.read(atk_path, True)
    assert atk_crc['expected'] == atk_crc['actual_seed_file_number']
    atk_tokens = pvf.tokens(atk_path, 'big5')
    hit_fields = []
    for index, token in enumerate(atk_tokens[:-1]):
        if token.get('text', '').lower() == '[hit wav]':
            hit_fields.append({'token_index': index, 'tag': atk_tokens[index + 1].get('text')})
    assert any(field['tag'] == 'SPEAR_HIT' for field in hit_fields)
    voice_scan = []
    for action in ['stay', 'movefoward', 'attack', 'damage1', 'damage2', 'down', 'moveback', 'sit', 'attacklong']:
        path = 'monster/draconian/dmani/' + action + '.ani'
        raw, crc = pvf.read(path, True)
        assert crc['expected'] == crc['actual_seed_file_number']
        ani = binary_ani(raw)
        sound_properties = [prop for prop in ani['globals'] if prop['type'] == 16]
        sound_properties += [prop for frame in ani['frames'] for prop in frame['properties'] if prop['type'] == 16]
        voice_scan.append({'path': path, 'sha256': sha(raw), 'sound_properties_type16': sound_properties})
    assert not any(item['sound_properties_type16'] for item in voice_scan)
    mob_tokens = pvf.tokens('monster/draconian/mirkius.mob', 'big5')
    mob_sound_tokens = [token for token in mob_tokens if any(word in token.get('text', '').lower()
                        for word in ['dragonman_', '.ogg', '[sound', '[damage sound', '[die sound'])]
    assert not mob_sound_tokens
    assert sum(len(items) for items in PACK_TAGS.values()) <= MAX_SOURCE_SOUNDS
    sounds = {}
    packs = {}
    for pack, selected in PACK_TAGS.items():
        pack_path = client / 'SoundPacks' / pack
        entries = {entry['path']: entry for entry in npk_entries(pack_path, False)}
        packs[pack] = {'sha256': file_sha(pack_path), 'bytes': pack_path.stat().st_size,
                       'selection': 'Explicit canonical package; no overlay/patch precedence inferred'}
        for tag in selected:
            attributes = dict(tags[tag].attrib)
            entry_path = attributes['FILE'].replace('\\', '/').lower()
            entry = entries[entry_path]
            assert entry['bytes'] <= MAX_SOURCE_BYTES_PER_SOUND
            with pack_path.open('rb') as stream:
                stream.seek(entry['offset'])
                raw = stream.read(entry['bytes'])
            assert raw.startswith(b'OggS')
            original_path = ROOT / 'source_art/r3/audio' / (tag.lower() + '.ogg')
            original_path.parent.mkdir(parents=True, exist_ok=True)
            original_path.write_bytes(raw)
            fixed, proof = normalize_comments(raw)
            runtime_path = ROOT / 'assets/r3/audio' / (tag.lower() + '.ogg')
            runtime_path.parent.mkdir(parents=True, exist_ok=True)
            runtime_path.write_bytes(fixed)
            assert original_path.read_bytes() == raw
            before_pages, after_pages = page_audit(raw), page_audit(fixed)
            assert before_pages == after_pages
            before_packets, after_packets = packets(raw), packets(fixed)
            assert all(left == right for index, (left, right) in enumerate(zip(before_packets, after_packets)) if index != 1)
            source_pcm, source_decoded = decoded_audio(original_path, ffmpeg, ffprobe)
            runtime_pcm, runtime_decoded = decoded_audio(runtime_path, ffmpeg, ffprobe)
            assert source_pcm == runtime_pcm
            sounds[tag] = {'path': 'res://' + runtime_path.relative_to(ROOT).as_posix(),
                'pack': pack, 'entry': entry_path, 'offset': entry['offset'], 'bytes': len(raw),
                'sha256': sha(raw), 'xml_attributes': attributes,
                'retained_original': original_path.relative_to(ROOT).as_posix(),
                'runtime_bytes': len(fixed), 'runtime_sha256': sha(fixed),
                'metadata_fix': proof, 'ogg_pages': before_pages,
                'source_decoded_pcm': source_decoded, 'runtime_decoded_pcm': runtime_decoded,
                'decoded_pcm_byte_identical': True, 'identification_setup_and_audio_packets_identical': True,
                'granule_serial_sequence_and_flags_identical': True,
                'source_binding': {'pvf': atk_path, 'pvf_sha256': sha(raw_atk), 'fields': hit_fields,
                    'limitation': 'SPEAR_HIT is explicitly referenced. Repeated FOX_ATK_HIT/[hit wav] precedence and original engine dispatch were not executed.'}}
    candidates = {tag: {'xml_attributes': dict(tags[tag].attrib),
                        'xml_children': [dict(child.attrib) for child in tags[tag]],
                        'exported': False, 'bound_to_mirkius': False,
                        'reason': 'Dragonman-family tag exists, but this Mirkius MOB/ANI does not supply an exact voice binding.'}
                  for tag in FAMILY_CANDIDATES}
    notes = [
        'Only SPEAR_HIT is exported: exact audio.xml tag-to-file resolution and a direct Mirkius attackinfo reference are verified.',
        'Attack, hurt and death voices remain unassigned. DRAGONMAN family names alone do not prove Mirkius voice dispatch.',
        'Mirkius ATK repeats [hit wav] with FOX_ATK_HIT then SPEAR_HIT; precedence/full original contact dispatch is unresolved.',
        'Runtime OGG fixes one bare Vorbis comment and its page CRC only. Original source bytes are retained unchanged.',
        'All identification/setup/audio packets and OGG timing headers are unchanged; local ffmpeg float32 PCM is byte-identical.',
        'No gameplay event timing, runtime audio hook, hero voice replacement, Godot/client execution, or paid/network service is included.',
    ]
    runtime = {'schema': 1, 'monster_id': 70, 'sounds': {tag: {'path': item['path']} for tag, item in sounds.items()},
               'source_roles': {'attack_voice': None, 'hurt_voice': None, 'death_voice': None,
                                'explicit_atk_spear_hit_tag': 'SPEAR_HIT'},
               'actions': {}, 'runtime_hooks_implemented': False,
               'source_reference': 'docs/r3_draconian_audio_source_reference.json', 'notes': notes}
    write_json(ROOT / 'data/draconian_audio.json', runtime)
    evidence = {'audio_xml_sha256': sha(xml_raw), 'selected_sound_tags': {tag: dict(tags[tag].attrib) for tag in sounds},
                'family_candidates_unbound': candidates, 'mirkius_ani_voice_scan': voice_scan,
                'mirkius_mob_sound_tokens': mob_sound_tokens,
                'atk': {'path': atk_path, 'sha256': sha(raw_atk), 'crc': atk_crc, 'tokens': atk_tokens}}
    write_json(ROOT / 'source_art/r3/audio/source_tag_evidence.json', evidence)
    report = {'schema': 1, 'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'producer': 'tools/r3/export_draconian_audio.py', 'producer_sha256': file_sha(Path(__file__)),
        'client': str(client), 'audio_xml_sha256': sha(xml_raw), 'packs': packs, 'sounds': sounds,
        'source_evidence': evidence, 'runtime_mapping': runtime,
        'verification': {'sound_count': len(sounds), 'source_bytes': sum(item['bytes'] for item in sounds.values()),
            'all_source_ogg_bytes_preserved': True, 'all_noncomment_packets_identical': True,
            'all_ogg_page_crcs_valid': True, 'all_timing_headers_identical': True,
            'all_decoded_pcm_byte_identical': True, 'voice_dispatch_resolved': False,
            'godot_import_or_playback_tested': False}, 'notes': notes}
    write_json(ROOT / 'docs/r3_draconian_audio_source_reference.json', report)
    write_json(ROOT / 'source_art/r3/audio/draconian_audio_reference.json', {
        'manifest': 'docs/r3_draconian_audio_source_reference.json',
        'manifest_sha256': file_sha(ROOT / 'docs/r3_draconian_audio_source_reference.json'),
        'runtime_data': 'data/draconian_audio.json', 'verification': report['verification']})
    print(json.dumps({'sounds': len(sounds), 'source_bytes': report['verification']['source_bytes'],
        'pcm_byte_identical': True, 'voice_dispatch_resolved': False,
        'manifest': 'docs/r3_draconian_audio_source_reference.json'}))


if __name__ == '__main__':
    main()
