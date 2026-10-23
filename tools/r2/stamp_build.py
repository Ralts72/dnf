"""Freeze the connected-route candidate without rewriting the R1 baseline."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
baseline = json.loads((ROOT / 'source_art/r1/checkpoints/candidate_29/docs/r1_build_manifest.json').read_text())
paths = {item['path'] for item in baseline['artifacts']}
for pattern in ['tools/r2/*.py', 'tools/r2/*.gd', 'assets/r2/**/*.png', 'assets/r2/**/*.png.import',
                'source_art/r2/*.json', 'source_art/r2/pvf/**/*']:
    paths.update(path.relative_to(ROOT).as_posix() for path in ROOT.glob(pattern) if path.is_file())
paths.update(['scripts/world_travel.gd', 'scripts/exploration_stage.gd', 'data/world_route.json',
              'scenes/tower_approach.tscn', 'scenes/tower_hall.tscn',
              'scenes/tower_approach_world.tscn', 'scenes/tower_hall_world.tscn',
              'docs/r2_asset_manifest.json'])
artifacts = []
for name in sorted(paths):
    data = (ROOT / name).read_bytes()
    artifacts.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
report = {'stage': 'R2 connected route candidate 01', 'artifacts': artifacts,
          'R1_baseline': 'source_art/r1/checkpoints/candidate_29',
          'route': 'data/world_route.json', 'asset_sources': 'docs/r2_asset_manifest.json',
          'layout': 'source_art/r2/layout_reference.json',
          'notes': ['The harbor model and character PNGs retain R1/29 bytes.',
                    'Three areas connect through held directional input at physical exits.',
                    'All new layout, navigation and3Ddepth are adaptations, not recovered source maps.',
                    'Progress is transient SceneTree metadata; no save, combat, quest or reward yet.',
                    'R0 remains the harbor-only reference. R1/29 evidence is historical, not counted as a fresh R2 regression.']}
(ROOT / 'docs/r2_build_manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print('Stamped R2/01:', len(artifacts), 'runtime/source artifacts.')
