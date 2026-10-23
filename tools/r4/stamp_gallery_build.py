"""Stamp accepted R4/06 doll-gallery artifacts; --check-only never writes.

Root accepts native QA before invoking this tool. It does not run QA, freeze a
checkpoint, or discover unrelated future content outside the explicit groups.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from stamp_build import ROOT, cache_or_temporary, local_file, sha256

BASELINE = "source_art/r4/checkpoints/candidate_05"
BASE_MANIFEST = BASELINE + "/docs/r4_build_manifest.json"
OUTPUT = "docs/r4_build_manifest.json"
NEW_GLOBS = [
    "assets/r4/stonemaster/**/*",
    "assets/r4/doll_gallery/**/*",
    "source_art/r4/stonemaster/**/*",
]
NEW_FILES = [
    "data/stonemaster_r1.json",
    "data/gallery_encounter_rules.json",
    "scripts/gallery_encounter.gd",
    "scenes/tower_doll_gallery.tscn",
    "scenes/tower_doll_gallery_world.tscn",
    "scenes/tower_doll_gallery_collisions.tscn",
    "docs/r4_stonemaster_source_reference.json",
    "docs/r4_doll_gallery_layout_reference.json",
    "tools/r4/export_stonemaster.py",
    "tools/r4/build_doll_gallery_world.py",
    "tools/r4/gallery_checks.gd",
    "tools/r4/stamp_gallery_build.py",
]


def build_manifest(root: Path = ROOT) -> dict:
    original = local_file(root, BASE_MANIFEST).read_bytes()
    baseline = json.loads(original)
    inherited = {item["path"] for item in baseline["artifacts"]}
    if baseline.get("candidate") != "R4/05" or len(inherited) != 2226 or len(baseline["artifacts"]) != 2226:
        raise ValueError("Expected the frozen R4/05 baseline's 2226 unique explicit paths")
    paths = set(inherited)
    for pattern in NEW_GLOBS:
        matches = [path for path in root.glob(pattern)
                   if path.is_file() and not cache_or_temporary(path.relative_to(root))]
        if not matches:
            raise FileNotFoundError(f"Empty R4/06 artifact group: {pattern}")
        paths.update(path.relative_to(root).as_posix() for path in matches)
    paths.update(NEW_FILES)
    for relative in NEW_FILES:
        if Path(relative).suffix == ".gd" and (root / (relative + ".uid")).is_file():
            paths.add(relative + ".uid")
    # PNG/OGG import sidecars are authored configuration, not generated caches.
    # An incomplete scoped export/import must fail rather than stamp less data.
    for relative in sorted(paths - inherited):
        if relative.startswith("assets/") and Path(relative).suffix in {".png", ".ogg"}:
            sidecar = relative + ".import"
            local_file(root, sidecar)
            if sidecar not in paths:
                raise ValueError(f"Required import configuration escaped the explicit scope: {sidecar}")
    artifacts = []
    for relative in sorted(paths):
        content = local_file(root, relative).read_bytes()
        artifacts.append({"path": relative, "bytes": len(content), "sha256": sha256(content)})
    assert inherited.issubset(paths)
    assert not any(path.startswith("work/") for path in paths)
    return {
        "schema": 1, "stage": "R4 Hall of Doll antechamber candidate 06", "candidate": "R4/06",
        "R4_baseline": BASELINE, "R3_baseline": baseline.get("R3_baseline"),
        "baseline_manifest": {"path": BASE_MANIFEST, "sha256": sha256(original),
                              "inherited_artifact_paths": len(inherited)},
        "artifact_count": len(artifacts), "new_artifact_paths": len(paths - inherited), "artifacts": artifacts,
        "scope": {
            "new_region": "doll_gallery; a single connected native 3D antechamber beyond the Lakius gate",
            "source_monster": "ID37 StoneMaster / 岩石人偶師; six original ANI action keys, 32 records and 11 unique source crops",
            "source_assets": "45 unchanged or exactly padded PNGs, two original environmental images included; one source-linked STONE_DMG contact sound",
            "geometry": "27 editable native meshes and three source-size cards; expanded decorative AABBs outside walking bounds, intentionally empty collision root",
            "combat": "One adapted close punch and bounded retreat; inherited hero attacks, guard, potions and shared route HP",
            "progress": "Transient doll_gallery_state only; no new profile schema, reward, quest, inventory or equipment entitlement",
            "inherited": "All 2226 R4/05 artifact paths retained; current common integration files rehashed",
        },
        "exclusions": [
            "Generated .godot caches, Python bytecode, temporary files and Git metadata; .import configurations and present script .uid files remain",
            "Broad discovery of assets/r4, other source_art/r4 content, historical checkpoints or future runtime files",
            "Every work/ research file, player profile and isolated QA profile",
            "Unlisted screenshots, visual reports and later content; this stamp covers only inherited paths and the explicit R4/06 groups/files",
        ],
        "notes": [
            "Run only after root accepts native source/behavior checks. This script does not perform QA, accept a build or create a checkpoint.",
            "The forward gate accepts only a strict boolean current Lakius clear or committed chapter receipt; retreat remains possible before the new encounter is cleared.",
            "The source action is attack, not attack1. Its original 13-record 645ms ANI is retained; hit timing, HP, cooldown, hurt/death durations and 50px backstep are explicit prototype adaptations.",
            "The source vista remains 640x410 and the two statues 99x205 at 1:1 logical pixels. New geometry uses existing source textures with recorded native material response; no original 3D map reconstruction is claimed.",
            "Only actual unblocked punch contact dispatches the source-linked sound. No ranged spell, projectile, control AI, source monster formula, extra reward or new media is implied.",
            "The three exact new globs include all exported source evidence, lossless import configurations and scoped audio. Optional native script UIDs are retained when present.",
            "Missing baseline paths, new required files, empty source groups or missing PNG/OGG import configurations raise an error before any output write.",
            "--check-only reads and hashes only. The normal command writes only docs/r4_build_manifest.json, with no checkpoint or profile operation.",
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true", help="Validate and hash without writing the build manifest")
    arguments = parser.parse_args()
    report = build_manifest()
    if not arguments.check_only:
        (ROOT / OUTPUT).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"{'Checked' if arguments.check_only else 'Stamped'} R4/06: {report['artifact_count']} artifacts, "
          f"{report['new_artifact_paths']} new; no checkpoint or player profile touched.")


if __name__ == "__main__":
    main()
