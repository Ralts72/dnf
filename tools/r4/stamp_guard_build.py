"""Stamp accepted R4/05 manual Guard artifacts; --check-only performs no writes."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

# Read-only checking must not create Python import bytecode beside this tool.
sys.dont_write_bytecode = True
from stamp_build import ROOT, cache_or_temporary, local_file, sha256

BASELINE = "source_art/r4/checkpoints/candidate_04"
BASE_MANIFEST = BASELINE + "/docs/r4_build_manifest.json"
OUTPUT = "docs/r4_build_manifest.json"
NEW_GLOBS = ["source_art/r4/guard/**/*"]
NEW_FILES = [
    "scripts/guard_runtime.gd", "data/guard_rules.json",
    "docs/r4_guard_source_reference.json", "tools/r4/inspect_guard.py",
    "tools/r4/guard_checks.gd", "tools/r4/stamp_guard_build.py",
]


def build_manifest(root: Path = ROOT) -> dict:
    original = local_file(root, BASE_MANIFEST).read_bytes()
    baseline = json.loads(original)
    inherited = {item["path"] for item in baseline["artifacts"]}
    assert len(inherited) == 2197, "Expected the frozen R4/04 baseline's2197 explicit paths"
    paths = set(inherited)
    for pattern in NEW_GLOBS:
        matches = [path for path in root.glob(pattern)
                   if path.is_file() and not cache_or_temporary(path.relative_to(root))]
        if not matches:
            raise FileNotFoundError(f"Empty R4/05 artifact group: {pattern}")
        paths.update(path.relative_to(root).as_posix() for path in matches)
    paths.update(NEW_FILES)
    for relative in NEW_FILES:
        uid = relative + ".uid"
        if Path(relative).suffix == ".gd" and (root / uid).is_file():
            paths.add(uid)
    artifacts = []
    for relative in sorted(paths):
        content = local_file(root, relative).read_bytes()
        artifacts.append({"path": relative, "bytes": len(content), "sha256": sha256(content)})
    assert inherited.issubset(paths)
    assert not any(path.startswith("work/") for path in paths)
    return {
        "schema": 1, "stage": "R4 manual Swordman Guard candidate 05", "candidate": "R4/05",
        "R4_baseline": BASELINE, "R3_baseline": baseline.get("R3_baseline"),
        "baseline_manifest": {"path": BASE_MANIFEST, "sha256": sha256(original), "inherited_artifact_paths": len(inherited)},
        "artifact_count": len(artifacts), "new_artifact_paths": len(paths-inherited), "artifacts": artifacts,
        "scope": {
            "gameplay": "Held C manual front guard in existing3D route; bag C remains equipment switch",
            "combat": "Valid enemy contact resolves one reduced hit, short guard reaction/recoil, and original KO flow",
            "source_art": "Eleven exact CRC-verified PVF payloads plus decoded references; existing guard PNGs reused",
            "inherited": "All2197 R4/04 artifact paths retained and current common integration files rehashed",
        },
        "exclusions": [
            "Generated .godot caches, Python bytecode and temporary files; inherited import configurations and present script UIDs are retained",
            "Broad discovery of assets/r4, historical checkpoints or future work/ research",
            "Player profiles, isolated QA scratch profiles and unaccepted future runtime content",
        ],
        "notes": [
            "Run only after root accepts focused native checks and regressions; this script does not perform QA or freeze a checkpoint.",
            "Source Guard explicitly absorbs front attacks while the key is held. Level1 physical40%,200ms reaction and2s cooldown inform the prototype.",
            "C binding, damage max1 ceil60%, frame0/1 contact mapping,6px recoil and noMP handling are explicit gameplay adaptations.",
            "No new character PNG, FX or audio is introduced. The existing fifteen-action, two-appearance manifests already contain IMG123/124 with10000ms source pose holds.",
            "Independent guard state does not use UI input blocking. Menus/scene changes cancel safely; pause/inspection freeze clocks; guarded chip can still defeat the hero.",
            "R0 remains a raw comparison and never restores active defense. Unknown optional actor properties require explicit type or equality guards.",
            "--check-only only reads and hashes artifacts; neither manifest, checkpoints nor any player profile is written.",
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true")
    arguments = parser.parse_args()
    report = build_manifest()
    if not arguments.check_only:
        (ROOT / OUTPUT).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"{'Checked' if arguments.check_only else 'Stamped'} R4/05: {report['artifact_count']} artifacts, "
          f"{report['new_artifact_paths']} new; no checkpoint or player profile touched.")


if __name__ == "__main__":
    main()
