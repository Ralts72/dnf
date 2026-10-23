"""Stamp accepted R4/04 supplies artifacts without touching profiles or checkpoints."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from stamp_build import ROOT, cache_or_temporary, local_file, sha256

BASELINE = "source_art/r4/checkpoints/candidate_03"
BASE_MANIFEST = BASELINE + "/docs/r4_build_manifest.json"
OUTPUT = "docs/r4_build_manifest.json"
NEW_GLOBS = ["assets/r4/supplies/**/*", "source_art/r4/supplies/**/*"]
NEW_FILES = [
    "scripts/port_supply_shop.gd", "scripts/hp_potion_runtime.gd",
    "data/first_supplies.json", "docs/r4_hp_potion_source_reference.json",
    "tools/r4/supplies_checks.gd", "tools/r4/supplies_storage_checks.gd",
    "tools/r4/run_supplies_storage_checks.py", "tools/r4/inspect_hp_consumable.py",
    "tools/r4/stamp_supplies_build.py",
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
            raise FileNotFoundError(f"Empty R4/04 artifact group: {pattern}")
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
        "schema": 1, "stage": "R4 Lorian supplies and HP potion candidate 04", "candidate": "R4/04",
        "R4_baseline": BASELINE, "R3_baseline": baseline.get("R3_baseline"),
        "baseline_manifest": {"path": BASE_MANIFEST, "sha256": sha256(original), "inherited_artifact_paths": len(inherited)},
        "artifact_count": len(artifacts), "new_artifact_paths": len(paths-inherited), "artifacts": artifacts,
        "scope": {
            "interaction": "Harbor Lorian shop, third bag slot, H potion use across the existing route",
            "storage": "Profile5 strict legacy migration, atomic purchase, failed use without a deferred debit",
            "source_art": "Canonical item1106 icon/field PNG and direct Lorian shop evidence",
            "inherited": "All R4/03 artifact paths retained and current common integration files rehashed",
        },
        "exclusions": [
            "Generated .godot caches, Python bytecode and temporary files; import configuration sidecars are included",
            "Recursive discovery of historical checkpoints or future work/ research",
            "Player profiles and isolated QA scratch profiles",
        ],
        "notes": [
            "Run only after root accepts focused native checks and isolated storage checks; stamping does not perform QA.",
            "Price10/heal35 and the four-purchase reward budget are prototype adaptations. Source price100 and HP tuple remain provenance.",
            "Profile constants/accessors are the price and capacity authority; JSON metadata must agree with them.",
            "Potion cooldown10 seconds persists across areas and F4, freezes in R0 or modal views, and R clears cooldown without refunding inventory.",
            "A successful normal-return inventory commit is followed synchronously by transient HP application; cross-process crash atomicity is not asserted.",
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true")
    arguments = parser.parse_args()
    report = build_manifest()
    if not arguments.check_only:
        (ROOT / OUTPUT).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"{'Checked' if arguments.check_only else 'Stamped'} R4/04: {report['artifact_count']} artifacts, "
          f"{report['new_artifact_paths']} new; no checkpoint or player profile touched.")


if __name__ == "__main__":
    main()
