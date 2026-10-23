"""Stamp accepted R4/03 Sharan source/runtime hashes without checkpointing.

Root completes native QA and owns the unified backup. Every frozen R4/02
artifact path stays in the list and current common files are rehashed.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from stamp_build import ROOT, cache_or_temporary, local_file, sha256

BASELINE = "source_art/r4/checkpoints/candidate_02"
BASE_MANIFEST = BASELINE + "/docs/r4_build_manifest.json"
OUTPUT = "docs/r4_build_manifest.json"
NEW_GLOBS = ["assets/r4/sharan/**/*", "source_art/r4/sharan/**/*"]
NEW_FILES = [
    "scripts/sharan_interaction.gd",
    "data/sharan_dialogue.json",
    "docs/r4_sharan_source_reference.json",
    "tools/r4/sharan_checks.gd",
    "tools/r4/stamp_sharan_build.py",
]


def build_manifest(root: Path = ROOT) -> dict:
    original = local_file(root, BASE_MANIFEST).read_bytes()
    baseline = json.loads(original)
    inherited = {item["path"] for item in baseline["artifacts"]}
    paths = set(inherited)
    for pattern in NEW_GLOBS:
        matches = [path for path in root.glob(pattern)
                   if path.is_file() and not cache_or_temporary(path.relative_to(root))]
        if not matches:
            raise FileNotFoundError(f"Required R4/03 artifact group is empty: {pattern}")
        paths.update(path.relative_to(root).as_posix() for path in matches)
    paths.update(NEW_FILES)
    for relative in NEW_FILES:
        if Path(relative).suffix in {".gd", ".gdshader"}:
            uid = relative + ".uid"
            if (root / uid).is_file():
                paths.add(uid)
    artifacts = []
    for relative in sorted(paths):
        content = local_file(root, relative).read_bytes()
        artifacts.append({"path": relative, "bytes": len(content), "sha256": sha256(content)})
    assert inherited.issubset({item["path"] for item in artifacts})
    assert not any(item["path"].startswith("work/") for item in artifacts)
    return {
        "schema": 1,
        "stage": "R4 Sharan harbor rest interaction candidate 03",
        "candidate": "R4/03",
        "R4_baseline": BASELINE,
        "R3_baseline": baseline.get("R3_baseline"),
        "baseline_manifest": {"path": BASE_MANIFEST, "sha256": sha256(original),
                              "inherited_artifact_paths": len(inherited)},
        "artifact_count": len(artifacts),
        "new_artifact_paths": len(paths - inherited),
        "artifacts": artifacts,
        "scope": {
            "accepted_candidate_only": "Integrated R4/03; root accepts completed native QA before stamping",
            "interaction": "Harbor R1 Sharan conversation and free transient route-health restoration",
            "source_art": "Canonical Sharan portrait crops and retained NPC/ANI/IMG provenance",
            "existing_common_files": "All R4/02 artifact paths remain and current common integration edits are rehashed",
            "future_content": "All work/ research and unlisted future runtime or source content are excluded",
        },
        "exclusions": [
            "Generated .godot caches, including .godot/imported; .import configuration sidecars remain included",
            "Temporary files, Python bytecode, Git metadata and .DS_Store",
            "Recursive historical checkpoint discovery; only explicit inherited source references remain",
            "Human user:// profiles and isolated QA scratch profiles",
            "Unlisted later gameplay experiments and work/ previews or feasibility reports",
        ],
        "notes": [
            "Every frozen R4/02 artifact path is retained, including previous source binaries, import settings and explicitly listed historical references. Current hashes capture common harbor integration changes.",
            "Sharan interaction is restricted to harbor R1. E opens the nearby dialogue, E/Esc closes, and Enter restores route HP to100 or continues the journey when already full.",
            "The native64x130 portrait comes from a verified canonical NPC reference and remains unscaled with nearest sampling. Other exported Sharan face crops and original source payloads remain provenance rather than guessed substitutes.",
            "Dialogue and free restoration are prototype adaptations. Committed first-drop/chapter history and strictly observed current clear events determine the conversation without restoring or claiming original NPC quest semantics.",
            "Restoration changes only route_hero_hp and player_hp in already existing dictionary encounter metadata. It does not create absent fights, change enemy HP/clear flags/counters/positions, write a profile, charge coins, grant rewards or change schema.",
            "Modal input, grounded eligibility, camera-follow prompt, Interface visibility and skill cooldown freezing are part of the accepted interaction checks. The original R3 route, R4 boss, Ghost Slash and equipment remain in the inherited build.",
            "Root completes the focused native interaction checks before freezing. This stamper writes only docs/r4_build_manifest.json and does not run QA, create a checkpoint or access any player profile.",
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true", help="Validate paths and hashes without writing the manifest")
    arguments = parser.parse_args()
    report = build_manifest()
    if not arguments.check_only:
        (ROOT / OUTPUT).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    verb = "Checked" if arguments.check_only else "Stamped"
    print(f"{verb} R4/03: {report['artifact_count']} source/runtime artifacts; "
          f"{report['baseline_manifest']['inherited_artifact_paths']} inherited, "
          f"{report['new_artifact_paths']} new. No checkpoint or player profile touched.")


if __name__ == "__main__":
    main()
