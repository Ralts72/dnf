"""Keep owned pixel-art imports lossless, including Sprite3D's initial textures.

Godot may auto-switch a scene-referenced 3D texture to VRAM compression and
mipmaps. These source crops and fixed-camera billboards use nearest sampling;
record an explicit profile before importing instead of relying on that default.
"""
from pathlib import Path
import json
import re

PROFILE = {
    'compress/mode': '0',
    'mipmaps/generate': 'false',
    'process/fix_alpha_border': 'false',
    'process/premult_alpha': 'false',
    'detect_3d/compress_to': '0',
}


def configure(root):
    root = Path(root)
    model_manifest = root / 'docs/r1_model_texture_manifest.json'
    model_textures = set()
    if model_manifest.exists():
        model_textures = {root / item['path'].removeprefix('res://')
                          for item in json.loads(model_manifest.read_text())['textures']}
    files = sorted(set((root / 'assets/r0').rglob('*.png')) |
                   set((root / 'assets/r1/actors').rglob('*.png')) |
                   {root / 'assets/r1/foliage_top.png'} |
                   model_textures |
                   {root / ('assets/r1/' + name + '.png') for name in
                    ['quay_coping','pier_top','pier_face','grove_bark','grove_plaster','grove_path','grove_grass','grove_canopy',
                     'dock_wood','dock_metal','dock_rope','dock_stone',
                     'lamp_blue','lamp_glass','lamp_shaft','lamp_collar']})
    changed = 0
    paths = []
    for image in files:
        if not image.exists():
            continue
        relative = image.relative_to(root).as_posix()
        sidecar = image.with_suffix(image.suffix + '.import')
        previous = sidecar.read_text() if sidecar.exists() else ''
        text = previous or ('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
                            '[deps]\n\nsource_file="res://' + relative + '"\n\n[params]\n')
        assert '[params]' in text, sidecar
        for key, value in PROFILE.items():
            pattern = r'^' + re.escape(key) + r'=.*$'
            if re.search(pattern, text, re.MULTILINE):
                text = re.sub(pattern, key + '=' + value, text, flags=re.MULTILINE)
            else:
                text = text.rstrip() + '\n' + key + '=' + value + '\n'
        if text != previous:
            sidecar.write_text(text)
            changed += 1
        paths.append(relative)
    report = {'profile': PROFILE, 'textures': paths, 'texture_count': len(paths),
              'model_texture_manifest': 'docs/r1_model_texture_manifest.json' if model_textures else None,
              'active_model_textures': len(model_textures),
              'notes': ['PNG source bytes are unchanged.',
                        'Explicit lossless imports; automatic 3D compression and mipmaps disabled.',
                        'Nearest sampling does not need transparent-border color dilation.']}
    (root / 'docs/pixel_import_manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f'Pixel import profile: {len(paths)} textures, {changed} sidecars updated.')
    return report


if __name__ == '__main__':
    configure(Path(__file__).resolve().parents[2])
