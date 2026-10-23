"""Stamp the accepted R4/02 Ghost Slash build after root finishes QA.

Preserve every frozen R4/01 path and rehash current common files. This only
writes the manifest; root owns acceptance, delivery evidence and checkpointing.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from stamp_build import ROOT, cache_or_temporary, local_file, sha256

BASELINE = "source_art/r4/checkpoints/candidate_01"
BASE_MANIFEST = BASELINE + "/docs/r4_build_manifest.json"
OUTPUT = "docs/r4_build_manifest.json"
NEW_GLOBS = [
    "assets/r4/ghost_slash/**/*",
    "source_art/r4/ghost_slash/**/*",
    "data/swordman_ghost_*",
]
NEW_FILES = [
    "data/ghost_slash_effects.json",
    "scripts/source_skill_runtime.gd",
    "shaders/source_effect_normal.gdshader",
    "tools/r4/export_ghost_slash.py",
    "tools/r4/inspect_ghost_slash.py",
    "tools/r4/ghost_slash_asset_checks.gd",
    "tools/r4/ghost_slash_checks.gd",
    "tools/r4/stamp_ghost_slash_build.py",
    "docs/r4_ghost_slash_source_reference.json",
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
            raise FileNotFoundError(f"Required R4/02 artifact group is empty: {pattern}")
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
        "stage": "R4 Ghost Slash integrated skill candidate 02",
        "candidate": "R4/02",
        "R4_baseline": BASELINE,
        "R3_baseline": baseline.get("R3_baseline"),
        "baseline_manifest": {"path": BASE_MANIFEST, "sha256": sha256(original),
                              "inherited_artifact_paths": len(inherited)},
        "artifact_count": len(artifacts),
        "new_artifact_paths": len(paths - inherited),
        "artifacts": artifacts,
        "scope": {
            "accepted_candidate_only": "Integrated R4/02; root accepts completed QA before stamping",
            "new_action": "hardattack / 鬼斩, ground-only Z skill",
            "new_actor_manifests": "Four complete manifests: practice/greatsword, raw R0/composite R1",
            "existing_common_files": "Every R4/01 artifact path is rehashed, including integrated input/actor/equipment/effect/skill-rule edits",
            "future_content": "All work/ research and unlisted later content are excluded",
        },
        "exclusions": [
            "Generated .godot caches, including .godot/imported; .import lossless settings remain included",
            "Temporary files, Python bytecode, Git metadata and .DS_Store",
            "Recursive historical checkpoint discovery; only explicit inherited source references remain",
            "Human user:// profiles and isolated QA scratch profiles",
            "Unlisted future runtime/source experiments and work/ previews or feasibility reports",
        ],
        "notes": [
            "All frozen R4/01 artifact paths remain, including original source references and import configurations. Existing common edits are captured by current byte hashes rather than by changing the baseline list.",
            "Ghost Slash adds210 exact source crops including12 FX PNGs and36 fixed-canvas composites,246 new PNGs total. Original source ANI/IMG bytes and source properties/boxes/offsets remain evidence.",
            "Four manifests preserve the previous14 action objects and add18 source HardAttack frames, making15 actions and110 master records. The character950ms clock and320x224 canvas/foot133,167 are retained.",
            "Two550ms source FX tracks retain their150ms delay and six50ms visible frames. Track1 uses normal alpha mixing, track2 uses additive mixing; original HopSmash additive shader behavior is preserved.",
            "Ground-only Z activation, cooldown handling and the150–450ms hit window are explicit prototype adaptations. Source hit dispatch, magic/dark formulas and full original skill semantics are not claimed.",
            "Ghost Slash audio remains unbound where direct source dispatch/timing is unproven. Equipment still contributes only the existing adapted bonus0/4, not original item attack72.",
            "The exporter source report retains its historical effect-output SHA and export-time hook status. Integrated effects JSON may update only delivery status/notes; final QA separately records the current integrated SHA and directly checks source track semantics.",
            "Root validates native246-texture RGBA, actual skill/FX clocks, F4 across both weapons/renderers, cooldown and existing equipment/route regressions before freezing. This stamper records artifacts and does not execute those checks.",
            "Only docs/r4_build_manifest.json is written. No runtime asset, player profile, source client or checkpoint is modified by stamping.",
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
    print(f"{verb} R4/02: {report['artifact_count']} source/runtime artifacts; "
          f"{report['baseline_manifest']['inherited_artifact_paths']} inherited, "
          f"{report['new_artifact_paths']} new. No checkpoint or player profile touched.")


if __name__ == "__main__":
    main()
