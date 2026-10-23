"""Hash the accepted R4/08 statue corridor adaptation; --check-only never writes."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from stamp_build import ROOT, cache_or_temporary, local_file, sha256

BASELINE = "source_art/r4/checkpoints/candidate_07"
BASE_MANIFEST = BASELINE + "/docs/r4_build_manifest.json"
OUTPUT = "docs/r4_build_manifest.json"
NEW_GLOBS = ["assets/r4/swordman_statue/**/*", "source_art/r4/swordman_statue/**/*"]
NEW_FILES = [
    "data/swordman_statue_r1.json", "data/statue_encounter_rules.json",
    "scripts/statue_encounter.gd", "scenes/tower_statue_gallery.tscn",
    "scenes/tower_statue_gallery_world.tscn", "scenes/tower_statue_gallery_collisions.tscn",
    "docs/r4_swordman_statue_source_reference.json", "docs/r4_statue_gallery_layout_reference.json",
    "tools/r4/export_swordman_statue.py", "tools/r4/build_statue_gallery_world.py",
    "tools/r4/statue_checks.gd", "tools/r4/stamp_statue_build.py",
]


def build_manifest(root: Path = ROOT) -> dict:
    original = local_file(root, BASE_MANIFEST).read_bytes()
    baseline = json.loads(original)
    inherited = {item["path"] for item in baseline["artifacts"]}
    if baseline.get("candidate") != "R4/07" or len(inherited) != 2454 or len(baseline["artifacts"]) != 2454:
        raise ValueError("Expected frozen R4/07 baseline with 2454 unique explicit paths")
    paths = set(inherited)
    for pattern in NEW_GLOBS:
        matches = [p for p in root.glob(pattern) if p.is_file() and not cache_or_temporary(p.relative_to(root))]
        if not matches:
            raise FileNotFoundError(f"Empty R4/08 artifact group: {pattern}")
        paths.update(p.relative_to(root).as_posix() for p in matches)
    paths.update(NEW_FILES)
    for relative in NEW_FILES:
        if Path(relative).suffix == ".gd" and (root / (relative + ".uid")).is_file():
            paths.add(relative + ".uid")
    for relative in sorted(paths - inherited):
        if relative.startswith("assets/") and Path(relative).suffix in {".png", ".ogg"}:
            sidecar = relative + ".import"
            local_file(root, sidecar)
            if sidecar not in paths:
                raise ValueError(f"Missing scoped media import configuration: {sidecar}")
    artifacts = []
    for relative in sorted(paths):
        content = local_file(root, relative).read_bytes()
        artifacts.append({"path": relative, "bytes": len(content), "sha256": sha256(content)})
    assert inherited.issubset(paths)
    assert not any(path.startswith("work/") for path in paths)
    return {
        "schema": 1, "stage": "R4 continuous statue corridor candidate 08", "candidate": "R4/08",
        "R4_baseline": BASELINE, "R3_baseline": baseline.get("R3_baseline"),
        "baseline_manifest": {"path": BASE_MANIFEST, "sha256": sha256(original), "inherited_artifact_paths": len(inherited)},
        "artifact_count": len(artifacts), "new_artifact_paths": len(paths - inherited), "artifacts": artifacts,
        "scope": {
            "new_region": "One1280px continuous statue corridor with region-specific camera pan; original896x404 viewport/actor scale retained",
            "combat": "Source SwordmanStatue ID84: adapted2400ms wake and magic18 contact; source level1 magic15% guard absorption yields16, oldphysical40% unchanged",
            "source_assets": "83new PNGs:35unchanged crops+48exactly padded records; no new audio or unknown dark-lightning event execution",
            "source_actions": "Eight canonical actions/48records, wake12x200ms and down6records860ms retained",
            "geometry": "Editable native columns/windows/walls, full existing source-size vistas and audited expanded AABBs outside walk bounds",
            "progress": "Transient statue_gallery_state/awakened only; no profile schema,reward,quest,inventory or entitlement change",
            "inherited": "All2454 R4/07 artifact paths retained; common integration files rehashed",
        },
        "exclusions": [
            "Generated .godot caches, bytecode, temporary files and Git metadata; authored .import and present .uid files remain",
            "Broad discovery of other R4 content, work research, player/QA profiles, unrelated experiments and historical checkpoints",
            "Unlisted screenshots/reports, future content, paid APIs and original client executables",
        ],
        "notes": [
            "Run only after root accepts native checks. This stamp neither performs QA nor accepts a build or creates a checkpoint.",
            "Source imagery, ANI frame durations and retained CRC payloads are evidence; adapted wake/AI/magic guard/geometry do not claim original passive,armor or event dispatcher reconstruction.",
            "Missing baseline paths, required files, source groups or media import configurations fail before writing output.",
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
    print(f"{'Checked' if arguments.check_only else 'Stamped'} R4/08: {report['artifact_count']} artifacts, {report['new_artifact_paths']} new")


if __name__ == "__main__":
    main()
