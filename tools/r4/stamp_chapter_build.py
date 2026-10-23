"""Hash accepted R4/10 chapter receipts; --check-only never writes."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from stamp_build import ROOT, local_file, sha256

BASELINE = "source_art/r4/checkpoints/candidate_09"
BASE_MANIFEST = BASELINE + "/docs/r4_build_manifest.json"
OUTPUT = "docs/r4_build_manifest.json"
NEW_FILES = [
    "tools/r4/chapter_checks.gd",
    "tools/r4/chapter_storage_checks.gd",
    "tools/r4/run_chapter_storage_checks.py",
    "tools/r4/stamp_chapter_build.py",
]


def build_manifest(root: Path = ROOT) -> dict:
    original = local_file(root, BASE_MANIFEST).read_bytes()
    baseline = json.loads(original)
    inherited = {item["path"] for item in baseline["artifacts"]}
    if baseline.get("candidate") != "R4/09" or len(inherited) != 2709 or len(baseline["artifacts"]) != 2709:
        raise ValueError("Expected frozen R4/09 baseline with 2709 unique explicit paths")
    paths = inherited | set(NEW_FILES)
    for relative in NEW_FILES:
        if Path(relative).suffix == ".gd" and (root / (relative + ".uid")).is_file():
            paths.add(relative + ".uid")
    artifacts = []
    for relative in sorted(paths):
        content = local_file(root, relative).read_bytes()
        artifacts.append({"path": relative, "bytes": len(content), "sha256": sha256(content)})
    assert inherited.issubset(paths)
    assert not any(path.startswith("work/") for path in paths)
    return {
        "schema": 1, "stage": "R4 Persistent later chapter receipts and Sharan feedback candidate 10", "candidate": "R4/10",
        "R4_baseline": BASELINE, "R3_baseline": baseline.get("R3_baseline"),
        "baseline_manifest": {"path": BASE_MANIFEST, "sha256": sha256(original), "inherited_artifact_paths": len(inherited)},
        "artifact_count": len(artifacts), "new_artifact_paths": len(paths - inherited), "artifacts": artifacts,
        "scope": {
            "progress": "Schema6 exact three strict boolean chapter flags; independently persisted StoneMaster/statue victories with no new reward, inventory or currency",
            "migration": "Validate each schema1–5 before memory-only migration; preserve original economy, entitlement and Lakius/first-drop constraints",
            "failed_save": "Verified live win receipts survive R within session while an older exact pending transaction remains unchanged; manual retry settles old transaction, then a separate single attempt settles remaining receipts",
            "travel": "Committed StoneMaster receipt keeps the statue passage open after R; pending-only candidates do not unlock a historical gate",
            "feedback": "Sharan statue then StoneMaster branches read strict current clears or committed history; original free rest and modal behavior retained",
            "source_assets": "Zero new imagery, audio or original-source claims; inherited source evidence retained",
            "inherited": "All2709 R4/09 artifact paths retained and current common integration files rehashed",
        },
        "exclusions": [
            "Generated .godot caches, bytecode, temporary files and Git metadata; authored .import and present .uid files remain",
            "Broad discovery of future R4 content, work research, player/QA profiles, unrelated experiments and historical checkpoints",
            "Unlisted screenshots/reports, paid APIs and original client executables",
        ],
        "notes": [
            "Run only after root accepts native checks. This stamp neither performs QA nor creates a checkpoint.",
            "Receipt retention during a failed save is session RAM, not a claim of crash persistence. Restart durability begins with successful profile commit.",
            "Historical clear seeding fills only absent session metadata; it never overwrites an explicit live practice reset. Statue seed includes awakened=true.",
            "Missing baseline paths or required files fail before writing output. No asset or future-path discovery is performed.",
            "--check-only hashes only; normal invocation writes only docs/r4_build_manifest.json.",
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true")
    arguments = parser.parse_args()
    report = build_manifest()
    if not arguments.check_only:
        (ROOT / OUTPUT).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"{'Checked' if arguments.check_only else 'Stamped'} R4/10: {report['artifact_count']} artifacts, {report['new_artifact_paths']} new")


if __name__ == "__main__":
    main()
