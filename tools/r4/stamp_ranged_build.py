"""Hash the accepted R4/07 ranged adaptation; --check-only never writes."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from stamp_build import ROOT, cache_or_temporary, local_file, sha256

BASELINE = "source_art/r4/checkpoints/candidate_06"
BASE_MANIFEST = BASELINE + "/docs/r4_build_manifest.json"
OUTPUT = "docs/r4_build_manifest.json"
NEW_GLOBS = ["assets/r4/stonemaster_ranged/**/*", "source_art/r4/stonemaster_ranged/**/*"]
NEW_FILES = [
    "data/stonemaster_ranged_r1.json", "data/stonemaster_gem.json",
    "scripts/stone_gem_projectiles.gd", "docs/r4_stonemaster_ranged_source_reference.json",
    "tools/r4/export_stonemaster_ranged.py", "tools/r4/ranged_checks.gd",
    "tools/r4/stamp_ranged_build.py",
]


def build_manifest(root: Path = ROOT) -> dict:
    original = local_file(root, BASE_MANIFEST).read_bytes()
    baseline = json.loads(original)
    inherited = {item["path"] for item in baseline["artifacts"]}
    if baseline.get("candidate") != "R4/06" or len(inherited) != 2374 or len(baseline["artifacts"]) != 2374:
        raise ValueError("Expected frozen R4/06 baseline with 2374 unique explicit paths")
    paths = set(inherited)
    for pattern in NEW_GLOBS:
        matches = [p for p in root.glob(pattern) if p.is_file() and not cache_or_temporary(p.relative_to(root))]
        if not matches:
            raise FileNotFoundError(f"Empty R4/07 artifact group: {pattern}")
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
        "schema": 1, "stage": "R4 StoneMaster ranged adaptation candidate 07", "candidate": "R4/07",
        "R4_baseline": BASELINE, "R3_baseline": baseline.get("R3_baseline"),
        "baseline_manifest": {"path": BASE_MANIFEST, "sha256": sha256(original), "inherited_artifact_paths": len(inherited)},
        "artifact_count": len(artifacts), "new_artifact_paths": len(paths - inherited), "artifacts": artifacts,
        "scope": {
            "combat": "Explicitly adapted StoneMaster cast and single straight physical gem; current close punch/retreat retained",
            "source_assets": "26 new PNGs: two source crops, eleven padded Cast frames, thirteen unchanged15x16 Gem crops; one source-linked JEWEL_HIT sound",
            "source_actions": "Old six action objects and32records unchanged; source Cast11records/1000ms and equipment Gem13records/615ms retained",
            "source_boundary": "No recovered MOB-to-equipment/projectile creation dispatcher; movement, emission, centered crop placement, collision and AI are prototype adaptations",
            "progress": "Transient fight only; no new region, profile schema, reward, quest, inventory or entitlement",
            "inherited": "All2374 R4/06 artifact paths retained; common integration files rehashed",
        },
        "exclusions": [
            "Generated .godot caches, bytecode, temporary files and Git metadata; authored .import and present .uid files remain",
            "Broad discovery of other R4 content, work research, player/QA profiles, unrelated experiments and historical checkpoints",
            "Unlisted screenshots/reports, future content, paid APIs and original client executables",
        ],
        "notes": [
            "Run only after root accepts native checks. This stamp neither performs QA nor accepts a build or creates a checkpoint.",
            "Source imagery, ANI frame durations and retained CRC payloads are evidence; the adapted independent projectile does not claim source dispatch or movement reconstruction.",
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
    print(f"{'Checked' if arguments.check_only else 'Stamped'} R4/07: {report['artifact_count']} artifacts, {report['new_artifact_paths']} new")


if __name__ == "__main__":
    main()
