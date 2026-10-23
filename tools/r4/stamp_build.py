"""Stamp accepted R4/01 source/runtime hashes; do not create a checkpoint.

Root runs this only after accepting R4/01 QA, then performs the unified backup.
The frozen R3/05 artifact paths are retained verbatim and rehashed in place.
No broad R4/work/checkpoint-directory scan can capture later research.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE = "source_art/r3/checkpoints/candidate_05"
BASE_MANIFEST = BASELINE + "/docs/r3_build_manifest.json"
OUTPUT = "docs/r4_build_manifest.json"
NEW_GLOBS = [
    "assets/r4/lakius/**/*",
    "source_art/r4/lakius/**/*",
    "data/lakius_*",
    "scenes/tower_depths*.tscn",
]
NEW_FILES = [
    "data/tower_boss_rules.json",
    "scenes/tower_depths.tscn",
    "scenes/tower_depths_world.tscn",
    "scenes/tower_depths_collisions.tscn",
    "scripts/tower_boss.gd",
    "source_art/r4/depths_layout_reference.json",
    "tools/r4/export_lakius.py",
    "tools/r4/build_depths_world.py",
    "tools/r4/boss_storage_checks.gd",
    "tools/r4/run_boss_storage_checks.py",
    "tools/r4/lakius_asset_checks.gd",
    "tools/r4/boss_checks.gd",
    "tools/r4/stamp_build.py",
    "docs/r4_lakius_source_reference.json",
    "docs/r4_depths_source_reference.json",
]


def sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def cache_or_temporary(path: Path) -> bool:
    # *.png.import / *.ogg.import are lossless import *configuration*, so they
    # must remain. Only generated cache directories and temporary files go out.
    return (any(part in {".godot", "__pycache__", ".git"} for part in path.parts)
            or path.name == ".DS_Store"
            or path.suffix in {".pyc", ".tmp"})


def local_file(root: Path, relative: str) -> Path:
    path = Path(relative)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"Artifact is not project-relative: {relative}")
    if cache_or_temporary(path):
        raise ValueError(f"Artifact references a generated cache: {relative}")
    absolute = root / path
    if not absolute.is_file():
        raise FileNotFoundError(f"Required R4/01 artifact is missing: {relative}")
    return absolute


def build_manifest(root: Path = ROOT) -> dict:
    base_bytes = local_file(root, BASE_MANIFEST).read_bytes()
    base = json.loads(base_bytes)
    inherited = {item["path"] for item in base["artifacts"]}
    paths = set(inherited)
    # Never recurse through the whole source_art tree or its historical builds.
    # Two historical source GLB/BLEND paths explicitly frozen by R3 remain in
    # `inherited`; they are not an invitation to scan either checkpoint folder.
    for pattern in NEW_GLOBS:
        matches = [path for path in root.glob(pattern)
                   if path.is_file() and not cache_or_temporary(path.relative_to(root))]
        if not matches:
            raise FileNotFoundError(f"Required R4/01 artifact group is empty: {pattern}")
        paths.update(path.relative_to(root).as_posix() for path in matches)
    paths.update(NEW_FILES)
    # Preserve optional native script UID references for the new authored files.
    # Existing baseline UIDs are already retained by the original path set.
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
        "stage": "R4 Lakius connected wide hall candidate 01",
        "candidate": "R4/01",
        "R3_baseline": BASELINE,
        "baseline_manifest": {"path": BASE_MANIFEST, "sha256": sha256(base_bytes),
                              "inherited_artifact_paths": len(inherited)},
        "artifact_count": len(artifacts),
        "new_artifact_paths": len(paths - inherited),
        "artifacts": artifacts,
        "scope": {
            "accepted_candidate_only": "R4/01; root accepts validation before stamping and backing up",
            "new_region": "depths",
            "source_monster": "ID71 Lakius / 魯卡斯; bounded canonical ANI/IMG/audio package",
            "profile_schema": 4,
            "existing_common_files": "All baseline artifact paths are rehashed to capture current integrated edits",
            "future_content": "Future 鬼斩 research and every work/ file are excluded",
        },
        "exclusions": [
            ".godot/imported and all .godot generated cache directories",
            "Temporary files, Python bytecode, .DS_Store and Git metadata",
            "Unlisted future R4/R5 runtime or source research",
            "Recursive historical checkpoint discovery; only explicit inherited source references remain",
            "Human user:// profiles and isolated QA scratch profiles",
        ],
        "notes": [
            "All 1405 frozen R3/05 artifact paths are retained; existing import configurations and explicit historical source GLB/BLEND references are not dropped.",
            "New PNG/OGG .import sidecars preserve the lossless import policy; they are configuration, not .godot/imported binary caches. New native script .uid files are included when present.",
            "One continuous native 3D wide hall extends the first hall to the right and returns left. It reuses ten R2 PNGs without new crops, while the R3 quest, first eye, equipment and harbor comparison remain in scope.",
            "Lakius uses ten distinct source actions,37 master records,32 raw crops and37 exact padded composites. Original ANI binaries, decoded references, original IMG and original OGG sources are retained.",
            "Boss AI, HP, damage, armor, warning plane and route adjacency are explicit prototype adaptations; no full original client combat or original 3D geometry is claimed.",
            "Schema1/2/3 migrate in memory to4. The historical lakius_cleared chapter flag commits with the prerequisite first encounter receipt and survives practice R; no additional boss coins, item drop or damage bonus are introduced.",
            "Storage QA uses isolated profiles and guards formal primary,backup,temporary and backup-temporary files. Stamping itself does not load or write any player profile.",
            "This tool writes only docs/r4_build_manifest.json. It does not run QA, change runtime files, create a checkpoint, copy a client, or include future 鬼斩 pre-research.",
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true", help="Validate paths/hash current files without writing the manifest")
    arguments = parser.parse_args()
    report = build_manifest()
    if not arguments.check_only:
        (ROOT / OUTPUT).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    verb = "Checked" if arguments.check_only else "Stamped"
    print(f"{verb} R4/01: {report['artifact_count']} source/runtime artifacts; "
          f"{report['baseline_manifest']['inherited_artifact_paths']} inherited, "
          f"{report['new_artifact_paths']} new. No checkpoint or player profile touched.")


if __name__ == "__main__":
    main()
