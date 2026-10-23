"""Run profile tests in a disposable Godot project without the game's autoloads."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GODOT = Path('/Applications/Godot.app/Contents/MacOS/Godot')
FORMAL = Path.home() / 'Library/Application Support/Godot/app_userdata/dnf/adventure/first_route_v1.json'
FILES = ['scripts/adventure_progress.gd', 'data/first_route_quest.json',
         'data/first_equipment.json', 'tools/r3/equipment_storage_checks.gd']


def guard():
    return {str(FORMAL) + suffix: {'exists': Path(str(FORMAL) + suffix).exists(),
            'sha256': hashlib.sha256(Path(str(FORMAL) + suffix).read_bytes()).hexdigest()
            if Path(str(FORMAL) + suffix).is_file() else None}
            for suffix in ['', '.bak', '.tmp', '.bak.tmp']}


def main():
    before = guard()
    with tempfile.TemporaryDirectory(prefix='dnf-equipment-storage-') as temporary:
        scratch = Path(temporary)
        (scratch / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="DNF isolated equipment QA"\n')
        (scratch / 'docs').mkdir()
        for name in FILES:
            target = scratch / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        result = subprocess.run([str(GODOT), '--headless', '--path', temporary,
                                 '--script', 'res://tools/r3/equipment_storage_checks.gd'],
                                text=True, capture_output=True)
        (ROOT / 'work/r3_05_storage_checks.log').write_text(result.stdout + result.stderr)
        report = json.loads((scratch / 'docs/r3_05_storage_checks.json').read_text())
        after = guard()
        report['isolation'] = {'scratch_project': temporary, 'autoloads': False,
                               'main_scene': False, 'human_files_before': before,
                               'human_files_after': after, 'human_profile_bytes_unchanged': before == after}
        (ROOT / 'docs/r3_05_storage_checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        assert result.returncode == 0 and report['all_passed'] and before == after
        assert not result.stderr, result.stderr
        print(f"Isolated storage: {report['count']} passed; formal files unchanged.")


if __name__ == '__main__':
    main()
