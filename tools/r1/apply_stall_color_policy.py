"""Apply a material-only GLB edit without retessellating existing geometry."""
from pathlib import Path
import json
import struct


def apply(path, barrel_projected_uv=None):
    raw = path.read_bytes()
    chunks, cursor = [], 12
    while cursor < len(raw):
        size, kind = struct.unpack_from('<II', raw, cursor)
        cursor += 8
        payload = raw[cursor:cursor + size]
        cursor += size
        if kind == 0x4e4f534a:
            document = json.loads(payload)
            if barrel_projected_uv is not None:
                barrel = next(n for n in document['nodes'] if n['name'] == 'Stall_Left_Barrel')
                for primitive in document['meshes'][barrel['mesh']]['primitives']:
                    # Candidate 14 uses its second UV set for the projection.
                    # Choose explicitly; a fresh Blender export may put it first.
                    primitive['attributes']['TEXCOORD_0'] = primitive['attributes']['TEXCOORD_' + str(barrel_projected_uv)]
            material = next(m for m in document['materials'] if m['name'] == 'Source_Painted_Stall')
            material.setdefault('extensions', {})['KHR_materials_unlit'] = {}
            material['extensions'].pop('KHR_materials_emissive_strength', None)
            material.pop('emissiveFactor', None)
            material.pop('emissiveTexture', None)
            if 'KHR_materials_unlit' not in document.setdefault('extensionsUsed', []):
                document['extensionsUsed'].append('KHR_materials_unlit')
            payload = json.dumps(document, separators=(',', ':')).encode()
            payload += b' ' * (-len(payload) % 4)
        chunks.append(struct.pack('<II', len(payload), kind) + payload)
    data = b''.join(chunks)
    path.write_bytes(struct.pack('<III', 0x46546c67, 2, len(data) + 12) + data)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    parser.add_argument('--barrel-projected-uv', type=int)
    args = parser.parse_args()
    apply(args.path, args.barrel_projected_uv)
