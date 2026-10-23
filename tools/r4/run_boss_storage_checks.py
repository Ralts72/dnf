"""Run receipt QA in a disposable Godot project, guarding all formal sidecars.

Reusable run_isolated() copies only the profile, its two data files and the
requested SceneTree test.  It never loads the game's project or autoloads.
"""
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
DEPENDENCIES = ["scripts/adventure_progress.gd", "data/first_route_quest.json", "data/first_equipment.json"]


def guard() -> dict:
    result = {}
    for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
        path = Path(str(FORMAL) + suffix)
        result[str(path)] = {"exists": path.exists(), "is_file": path.is_file(),
                             "sha256": hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None}
    return result


def run_isolated(script: str, report_path: str, godot: Path = GODOT, timeout: int = 45) -> dict:
    assert script.startswith("tools/") and report_path.startswith("docs/")
    assert ".." not in Path(script).parts and ".." not in Path(report_path).parts
    before = guard()
    source_hashes = {}
    with tempfile.TemporaryDirectory(prefix="dnf-boss-storage-") as temporary:
        scratch = Path(temporary)
        (scratch / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="DNF isolated boss storage QA"\n'
            'config/use_custom_user_dir=true\nconfig/custom_user_dir_name="DNF isolated boss storage QA"\n')
        (scratch / Path(report_path).parent).mkdir(parents=True)
        for relative in DEPENDENCIES + [script]:
            source = ROOT / relative
            target = scratch / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            source_hashes[relative] = hashlib.sha256(source.read_bytes()).hexdigest()
        try:
            process = subprocess.run([str(godot), "--headless", "--path", temporary,
                                      "--script", "res://" + script],
                                     text=True, capture_output=True, timeout=timeout)
            execution = {"returncode": process.returncode, "stdout": process.stdout, "stderr": process.stderr,
                         "timeout": False}
        except subprocess.TimeoutExpired as error:
            execution = {"returncode": None, "stdout": str(error.stdout or ""),
                         "stderr": str(error.stderr or ""), "timeout": True}
        generated = scratch / report_path
        report = json.loads(generated.read_text()) if generated.is_file() else {
            "schema": 1, "count": 0, "checks": [], "failed": [{"name": "SceneTree generated a report", "passed": False}],
            "all_passed": False}
        after = guard()
        source_unchanged = all(hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == digest
                               for relative, digest in source_hashes.items())
        report["isolation"] = {"scratch_project": temporary, "autoloads": False, "main_scene": False,
                               "copied_sources": source_hashes, "sources_unchanged_after_test": source_unchanged,
                               "human_files_before": before, "human_files_after": after,
                               "human_profile_bytes_unchanged": before == after}
        report["execution"] = execution
        passed = (report["all_passed"] and execution["returncode"] == 0 and not execution["stderr"]
                  and before == after and source_unchanged)
        report["all_passed"] = passed
        (ROOT / report_path).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(execution["stdout"], end="")
    if execution["stderr"]:
        print(execution["stderr"], end="")
    print(f"Isolated boss storage: {report['count']} checks; passed={passed}; formal four files unchanged={before == after}.")
    if not passed:
        raise SystemExit(1)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=GODOT)
    parser.add_argument("--timeout", type=int, default=45)
    arguments = parser.parse_args()
    run_isolated("tools/r4/boss_storage_checks.gd", "docs/r4_01_storage_checks.json",
                 arguments.godot, arguments.timeout)


if __name__ == "__main__":
    main()
