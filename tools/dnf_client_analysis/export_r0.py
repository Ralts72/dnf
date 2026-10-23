"""Export a small, explicit whitelist from the 95 client. Never execute client code.

Run with a Python environment containing numpy and Pillow, from any directory.
The original three inspection scripts remain unchanged from the handover.
"""
from pathlib import Path
import argparse
import hashlib
import json
import posixpath

from PIL import Image
from inspect_clients import PVF, npk_entries, img_frames, decode_frame
from pixel_imports import configure as configure_pixel_imports

PROJECT = Path(__file__).resolve().parents[2]
LAYERS = [
    ('weapon_back', 'weapon_lswd', 'weapon/lswd/lswd0000b.img'),
    ('body', 'avatar_skin', 'avatar/skin/sm_body0000.img'),
    ('pants_back', 'avatar_pants', 'avatar/pants/sm_pants0000b.img'),
    ('shoes_back', 'avatar_shoes', 'avatar/shoes/sm_shoes0000b.img'),
    ('pants', 'avatar_pants', 'avatar/pants/sm_pants0000a.img'),
    ('shoes', 'avatar_shoes', 'avatar/shoes/sm_shoes0000a.img'),
    ('coat', 'avatar_coat', 'avatar/coat/sm_coat0000a.img'),
    ('hair', 'avatar_hair', 'avatar/hair/sm_hair0000a.img'),
    ('weapon_front', 'weapon_lswd', 'weapon/lswd/lswd0000c.img'),
]
ACTIONS = ['stay', 'move', 'dash', 'attack1', 'attack2', 'hopsmash',
           'attack3', 'jump', 'jumpattack', 'sit', 'damage1', 'damage2', 'down', 'guard']


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


class Exporter:
    def __init__(self, client):
        self.client = client
        self.pvf = PVF(client / 'Script.pvf')
        h = self.pvf.header
        assert h['tree_crc_actual'] == h['tree_crc_expected']
        assert not h['payload_bounds_errors'] and not h['parse_error']
        self.packs, self.albums, self.frames, self.scripts = {}, {}, {}, {}

    def album(self, pack, path):
        key = (pack, path)
        if key not in self.albums:
            packfile = self.client / 'ImagePacks2' / pack
            if pack not in self.packs:
                self.packs[pack] = {e['path']: e for e in npk_entries(packfile)}
            e = self.packs[pack][path]
            with packfile.open('rb') as f:
                f.seek(e['offset'])
                data = f.read(e['bytes'])
            self.albums[key] = (data, {
                'client': '95', 'npk': pack, 'img': path,
                'npk_entry_offset': e['offset'], 'payload_bytes': e['bytes'],
                'sha256_img_payload': digest(data),
                'selection': 'Explicit canonical NPK, no mod overlay inference',
            })
        return self.albums[key]

    def frame(self, pack, path, index, alias):
        key = (pack, path, index)
        if key not in self.frames:
            data, source = self.album(pack, path)
            fs, _ = img_frames(data)
            resolved, seen = index, set()
            while 'link' in fs[resolved]:
                assert resolved not in seen
                seen.add(resolved)
                resolved = fs[resolved]['link']
            meta = fs[resolved]
            if meta['width'] == 0 or meta['height'] == 0:
                im = Image.new('RGBA', (1, 1))
            else:
                im, meta = decode_frame(data, index)
            relative = f'assets/r0/{alias}/{index:03d}.png'
            dest = PROJECT / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            im.save(dest)
            self.frames[key] = {
                'texture': 'res://' + relative,
                'img_frame': index, 'resolved_img_frame': resolved,
                'source': source, 'img_metadata': meta,
                'sha256_png': digest(dest.read_bytes()),
                'export': 'Raw RGBA crop; no resampling, retouching or palette edits',
            }
        return self.frames[key]

    def ani(self, path):
        if path not in self.scripts:
            data, crc = self.pvf.read(path, True)
            assert crc['expected'] == crc['actual_seed_file_number'], path
            self.scripts[path] = {
                'path': path, 'sha256': digest(data), 'crc': crc,
                'decoded': __import__('inspect_clients').binary_ani(data),
            }
        return self.scripts[path]['decoded']

    def sequence(self, path, alias, character=False):
        ani = self.ani(path)
        frames = []
        for f in ani['frames']:
            layers = []
            if character:
                specs = [(name, f'sprite_character_swordman_equipment_{pack}.NPK',
                          'sprite/character/swordman/equipment/' + image)
                         for name, pack, image in LAYERS]
            else:
                resource = f['resource']
                assert resource is not None, path
                specs = [('image', 'sprite_map_npc.NPK' if resource.startswith('map/npc/')
                          else 'sprite_map_hendonmyre.NPK', 'sprite/' + resource)]
            for name, pack, image in specs:
                item = self.frame(pack, image, f['image_frame'], alias + '/' + name)
                meta = item['img_metadata']
                layers.append({'name': name, 'texture': item['texture'],
                               'offset': [f['x'] + meta['x'], f['y'] + meta['y']]})
            delay = next(prop['value'] for prop in f['properties'] if prop['type'] == 12)
            frames.append({'duration_ms': delay, 'img_frame': f['image_frame'],
                           'ani_offset': [f['x'], f['y']], 'layers': layers,
                           'source_boxes': f['boxes'], 'source_properties': f['properties']})
        return {'source_ani': path, 'source_globals': ani['globals'], 'frames': frames}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path,
                        default=Path('/Users/mac/Downloads/天堂95起源单机客户端'))
    args = parser.parse_args()
    e = Exporter(args.client)
    swordman = {'schema': 1, 'animations': {}, 'layer_order': [x[0] for x in LAYERS],
                'notes': ['Avatar 0000 selected appearance, not a global path substitution.',
                          'Layer order is a documented R0 composition; full engine layer variations pending.',
                          'Only image offsets and durations are played. Properties/boxes retained as evidence, not combat rules.',
                          'Jump, guard, damage and down retain long source hold frames; these are raw pose previews, not movement/response state machines.',
                          'Overturn is excluded because its rotation property is not yet interpreted.']}
    for action in ACTIONS:
        swordman['animations'][action] = e.sequence(
            f'character/swordman/animation/{action}.ani', 'swordman', True)
    write_json(PROJECT / 'data/swordman_r0.json', swordman)
    for npc in ['lo', 'sr']:
        write_json(PROJECT / f'data/npc_{npc}_r0.json', {
            'schema': 1, 'animations': {'stay': e.sequence(f'npc/animation/npc_{npc}.ani', f'npc_{npc}')},
            'layer_order': ['image'],
        })

    # A historical port variant is a better layout reference than the modified (f) street.
    map_path = 'map/hendonmyre/sky_westcoast2.map'
    raw_map, crc = e.pvf.read(map_path, True)
    assert crc['expected'] == crc['actual_seed_file_number']
    tokens = e.pvf.tokens(map_path, 'big5')
    write_json(PROJECT / 'docs/source_port_map.json', {
        'source_pvf': map_path, 'sha256': digest(raw_map), 'crc': crc, 'tokens': tokens,
    })
    world = {'reference_map': map_path, 'objects': [], 'floor': [], 'background': []}
    pack = 'sprite_map_hendonmyre.NPK'
    # Explicit older far image: the current ANI points at a newer port_far asset.
    far = e.frame(pack, 'sprite/map/hendonmyre/westfar00.img', 0, 'port/far')
    world['background'].append({'texture': far['texture'], 'position': [0, -80]})
    # Tile canvas origin chosen by matching the lower edge to westile00..03 (y=361).
    # Preserve this explicit inference rather than pretending the tile engine was reconstructed.
    for index in range(1, 5):
        item = e.frame(pack, 'sprite/map/hendonmyre/skywayv2.img', index, 'port/floor')
        m = item['img_metadata']
        world['floor'].append({'texture': item['texture'],
                               'position': [(index-1)*224 + m['x'], -99 + m['y']]})
    start = next(i for i,t in enumerate(tokens) if t.get('text') == '[animation]') + 1
    end = next(i for i,t in enumerate(tokens) if t.get('text') == '[/animation]')
    entries = tokens[start:end]
    for i in range(0, len(entries), 5):
        path = posixpath.normpath(posixpath.join('map/hendonmyre', entries[i]['text'].lower()))
        # The signpost asset is outside this small whitelist; record omission below.
        if path.endswith('/brpost00.ani'):
            continue
        anchor = [entries[i+2]['value'], entries[i+3]['value'] - entries[i+4]['value']]
        seq = e.sequence(path, 'port/' + Path(path).stem)
        world['objects'].append({'name': Path(path).stem, 'anchor': anchor,
                                 'source_layer': entries[i+1]['text'], 'sequence': seq})
    world['notes'] = ['Original ANI placement coordinates retained for the port variant.',
                      'Older westfar00 IMG selected instead of current far ANI replacement.',
                      'Floor image canvas origin y=-99 is inferred by matching visible seams.',
                      'NPCs are a new comparison arrangement, not original port NPC positions.',
                      'brpost00 sign omitted; original layer meanings/scroll rates not fully emulated.']
    write_json(PROJECT / 'data/port_r0.json', world)
    write_json(PROJECT / 'docs/r0_asset_manifest.json', {
        'schema': 1, 'client': '95', 'client_directory': str(args.client),
        'source_pvf_sha256': digest((args.client / 'Script.pvf').read_bytes()),
        'pvf_header': e.pvf.header, 'frames': list(e.frames.values()),
        'animations': list(e.scripts.values()),
        'limitations': swordman['notes'] + world['notes'],
    })
    configure_pixel_imports(PROJECT)
    print(json.dumps({'exported_crops': len(e.frames), 'decoded_ani': len(e.scripts),
                      'character_actions': ACTIONS, 'manifest': 'docs/r0_asset_manifest.json'}))


if __name__ == '__main__':
    main()
