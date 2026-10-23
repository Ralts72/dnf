"""Run schema5 supply tests in a disposable project, guarding formal four files."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")
FORMAL = Path.home() / "Library/Application Support/Godot/app_userdata/dnf/adventure/first_route_v1.json"
FILES = ["scripts/adventure_progress.gd", "data/first_route_quest.json", "data/first_equipment.json", "tools/r4/supplies_storage_checks.gd"]
REPORT = "docs/r4_04_storage_checks.json"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def guard() -> dict:
    result = {}
    for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
        path = Path(str(FORMAL) + suffix)
        result[str(path)] = {"exists": path.exists(), "is_file": path.is_file(), "sha256": digest(path) if path.is_file() else None}
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=GODOT)
    arguments = parser.parse_args()
    before = guard()
    hashes = {relative: digest(ROOT / relative) for relative in FILES}
    with tempfile.TemporaryDirectory(prefix="dnf-supplies-storage-") as temporary:
        scratch = Path(temporary)
        (scratch / "project.godot").write_text('config_version=5\n[application]\nconfig/name="DNF isolated supplies QA"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="DNF isolated supplies QA"\n')
        (scratch / "docs").mkdir()
        for relative in FILES:
            target = scratch / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        result = subprocess.run([str(arguments.godot), "--headless", "--path", temporary, "--script", "res://tools/r4/supplies_storage_checks.gd"], text=True, capture_output=True, timeout=45)
        generated = scratch / REPORT
        report = json.loads(generated.read_text()) if generated.is_file() else {"count": 0, "checks": [], "failed": [{"name": "test generated report", "passed": False}], "all_passed": False}
        after = guard()
        source_unchanged = all(digest(ROOT / relative) == sha for relative, sha in hashes.items())
        report["isolation"] = {"scratch_project": temporary, "autoloads": False, "main_scene": False, "copied_sources": hashes, "sources_unchanged_after_test": source_unchanged,
                               "human_files_before": before, "human_files_after": after, "human_profile_bytes_unchanged": before == after}
        report["execution"] = {"returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
        report["all_passed"] = bool(report["all_passed"] and result.returncode == 0 and not result.stderr and before == after and source_unchanged)
        (ROOT / REPORT).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(result.stdout, end="")
    print(result.stderr, end="")
    print(f"Isolated supplies storage: {report['count']} checks; passed={report['all_passed']}; formal four files unchanged={before == after}.")
    if not report["all_passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
