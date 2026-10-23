"""Stamp the current equipment loop; preserve the previously frozen route."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
base = json.loads((ROOT / 'source_art/r3/checkpoints/candidate_04/docs/r3_build_manifest.json').read_text())
paths = {item['path'] for item in base['artifacts']}
for pattern in ['assets/r3/equipment/ordinary_greatsword/**/*', 'source_art/r3/equipment_27304/**/*']:
    paths.update(p.relative_to(ROOT).as_posix() for p in ROOT.glob(pattern) if p.is_file())
paths.update(['scripts/equipment_appearance.gd', 'scripts/equipment_runtime.gd', 'scripts/source_walk_inbetweens.gd',
              'data/first_equipment.json', 'data/swordman_mswd0007_r0.json', 'data/swordman_mswd0007_r1.json',
              'data/swordman_mswd0007_walk_inbetweens.json', 'data/swordman_mswd0007_dash_inbetweens.json',
              'tools/r3/export_starter_weapon.py', 'tools/r3/bake_starter_weapon.gd',
              'tools/r3/weapon_asset_checks.gd', 'tools/r3/equipment_storage_checks.gd',
              'tools/r3/run_equipment_storage_checks.py', 'tools/r3/equipment_checks.gd',
              'docs/r3_starter_weapon_source_reference.json'])
artifacts = []
for name in sorted(paths):
    content = (ROOT / name).read_bytes()
    artifacts.append({'path': name, 'bytes': len(content), 'sha256': hashlib.sha256(content).hexdigest()})
report = {'stage': 'R3 equipment loop candidate 05', 'artifacts': artifacts,
          'R3_baseline': 'source_art/r3/checkpoints/candidate_04',
          'notes': ['First-route dialogue, coins, first-drop, weapon reward and plus4 damage are prototype adaptations.',
                    'Item27304 uses its canonical mswd0007 weapon layers; old lswd0000 default is called practice sword without claiming a unique official itemID.',
                    'Character masterclock and body/apparel are preserved. Different weapon ANI durations remain source evidence.',
                    'New32 native locomotion bakes have16 exact endpoints; F5 and raw R0 comparison use the selected weapon.',
                    'Schema1/2 migrate in memory to3; completed profiles own the weapon but retain their default appearance. Ownership, equipment and rewards commit atomically.',
                    'All QA writes isolated profiles; no formal player profile was created or changed. Future R4 files are excluded.']}
(ROOT / 'docs/r3_build_manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print('Stamped R3/05:', len(artifacts), 'source/runtime artifacts.')
