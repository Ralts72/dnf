"""Hash the accepted R4/09 upper slash adaptation; --check-only never writes."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from stamp_build import ROOT, cache_or_temporary, local_file, sha256

BASELINE = "source_art/r4/checkpoints/candidate_08"
BASE_MANIFEST = BASELINE + "/docs/r4_build_manifest.json"
OUTPUT = "docs/r4_build_manifest.json"
NEW_GLOBS = ["source_art/r4/upper_slash/**/*"]
NEW_FILES = [
    "data/swordman_upper_practice_r0.json", "data/swordman_upper_practice_r1.json",
    "data/swordman_upper_great_r0.json", "data/swordman_upper_great_r1.json",
    "data/upper_slash_rules.json", "scripts/upper_slash_runtime.gd", "scripts/enemy_launch_motion.gd",
    "docs/r4_upper_slash_source_reference.json", "tools/r4/prepare_upper_slash.py",
    "tools/r4/upper_checks.gd", "tools/r4/stamp_upper_build.py",
]


def build_manifest(root: Path = ROOT) -> dict:
    original = local_file(root, BASE_MANIFEST).read_bytes()
    baseline = json.loads(original)
    inherited = {item["path"] for item in baseline["artifacts"]}
    if baseline.get("candidate") != "R4/08" or len(inherited) != 2672 or len(baseline["artifacts"]) != 2672:
        raise ValueError("Expected frozen R4/08 baseline with 2672 unique explicit paths")
    paths = set(inherited)
    for pattern in NEW_GLOBS:
        matches = [p for p in root.glob(pattern) if p.is_file() and not cache_or_temporary(p.relative_to(root))]
        if not matches:
            raise FileNotFoundError(f"Empty R4/09 artifact group: {pattern}")
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
        "schema": 1, "stage": "R4 Upper Slash and finite ordinary-enemy lift candidate 09", "candidate": "R4/09",
        "R4_baseline": BASELINE, "R3_baseline": baseline.get("R3_baseline"),
        "baseline_manifest": {"path": BASE_MANIFEST, "sha256": sha256(original), "inherited_artifact_paths": len(inherited)},
        "artifact_count": len(artifacts), "new_artifact_paths": len(paths - inherited), "artifacts": artifacts,
        "scope": {
            "ability": "V ground-only Upper Slash prototype alias of existing Attack3; source nineframes550ms and2s cooldown retained",
            "combat": "Adapted24physical damage,+4equipped bonus; finite800ms/48px ordinary enemy lift,minimum120ms landing recovery,no repeated air extension; boss receives damage only",
            "source_assets": "Zero new PNG/IMG/audio; existing Attack3 pose/images and0/100ms swing cues explicitly reused, no original skill dispatcher or force-unit reconstruction claimed",
            "source_actions": "Four16action119record manifests; all60 inherited action objects and36 copied alias records retained exactly except explicit source_ani metadata",
            "progress": "Session-only cooldown/lift; no new region,profile schema,reward,quest,inventory or entitlement",
            "inherited": "All2672 R4/08 artifact paths retained; current common integration files rehashed",
        },
        "exclusions": [
            "Generated .godot caches, bytecode, temporary files and Git metadata; authored .import and present .uid files remain",
            "Broad discovery of other R4 content, work research, player/QA profiles, unrelated experiments and historical checkpoints",
            "Unlisted screenshots/reports, future content, paid APIs and original client executables",
        ],
        "notes": [
            "Run only after root accepts native checks. This stamp neither performs QA nor accepts a build or creates a checkpoint.",
            "Source imagery, ANI durations and nine retained CRC payloads are evidence; alias,lift,damage,key and reused swing cues do not claim original skill dispatcher,force-unit mapping,MP or armor reconstruction.",
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
    print(f"{'Checked' if arguments.check_only else 'Stamped'} R4/09: {report['artifact_count']} artifacts, {report['new_artifact_paths']} new")


if __name__ == "__main__":
    main()
