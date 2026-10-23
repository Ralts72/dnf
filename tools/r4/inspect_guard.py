"""Archive the bounded male Swordman Guard source evidence, without runtime edits.

Only source_art/r4/guard and docs/r4_guard_source_reference.json are written.
Eleven whitelisted PVF payloads are decoded as data and CRC checked; existing
character pictures are referenced and hashed, never exported or modified.
No client code, Godot, Blender, network, NPK extraction or audio guessing.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/dnf_client_analysis"))
from inspect_clients import PVF, binary_ani

SOURCE = ROOT / "source_art/r4/guard"
REPORT = ROOT / "docs/r4_guard_source_reference.json"
MASTER = "character/swordman/animation/guard.ani"
GUARD = "skill/swordman/guard.skl"
PATHS = [GUARD, "skill/swordman/cancelguard.skl", "skill/swordmanskill.lst",
         "character/swordman/swordman.chr", MASTER,
         "character/swordman/effect/animation/guard/dust.ani",
         "character/swordman/effect/animation/guard/spark.ani"] + [
    f"equipment/character/swordman/weapon/hsword/{family}{layer}/guard.ani"
    for family in ("lswd", "mswd") for layer in ("b", "c")]
MANIFESTS = [f"data/swordman_ghost_{appearance}_{view}.json"
             for appearance in ("practice", "great") for view in ("r0", "r1")]


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def section(tokens: list[dict], label: str) -> list:
    values, active = [], False
    for token in tokens:
        if token["type"] == 5:
            if active:
                break
            active = token["text"] == label
        elif active:
            values.append(token.get("text", token.get("value")))
    return values


def delays(animation: dict) -> list[int]:
    return [next(p["value"] for p in f["properties"] if p["type"] == 12)
            for f in animation["frames"]]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", type=Path, default=Path("/Users/mac/Downloads/天堂95起源单机客户端"))
    arguments = parser.parse_args()
    pvf = PVF(arguments.client / "Script.pvf")
    assert pvf.header["tree_crc_expected"] == pvf.header["tree_crc_actual"]
    assert not pvf.header["parse_error"] and not pvf.header["payload_bounds_errors"]
    assert len(PATHS) == 11 and len(set(PATHS)) == 11
    sources, decoded = [], {}
    for path in PATHS:
        raw, crc = pvf.read(path, True)
        assert crc["expected"] == crc["actual_seed_file_number"], path
        value = binary_ani(raw) if path.endswith(".ani") else pvf.tokens(path, "big5")
        decoded[path] = value
        destination = SOURCE / "pvf" / (path + ".bin")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(raw)
        assert destination.read_bytes() == raw
        readable = destination.with_suffix(".json")
        write_json(readable, {"pvf_path": path, "crc": crc, "decoded": value})
        sources.append({"pvf_path": path, "bytes": len(raw), "sha256_decoded": sha(raw),
                        "crc": crc, "crc_matches": True,
                        "raw_reference": str(destination.relative_to(ROOT)),
                        "readable_reference": str(readable.relative_to(ROOT))})

    master = decoded[MASTER]
    assert master["frames_count"] == 2 and delays(master) == [10000, 10000]
    identity = [(f["image_frame"], f["x"], f["y"]) for f in master["frames"]]
    assert identity == [(123, -232, -333), (124, -232, -333)]
    weapon = []
    for path in PATHS:
        if not path.startswith("equipment/"):
            continue
        value = decoded[path]
        assert [(f["image_frame"], f["x"], f["y"]) for f in value["frames"]] == identity
        assert delays(value) == delays(master)
        weapon.append({"source_ani": path, "same_master_frame_order_offsets_and_duration": True,
                       "image_frames": [123, 124], "duration_ms": delays(value)})
    tokens = decoded[GUARD]
    level_info = section(tokens, "[level info]")
    assert level_info[0] == 5
    levels = []
    for i in range(5):
        row = level_info[1 + i * 5:1 + (i + 1) * 5]
        levels.append({"level": i + 1, "raw_row": row, "physical_absorb_percent": row[2],
                       "magical_absorb_percent": row[3], "knockback_time_ms": row[1]})
    assert levels[0]["physical_absorb_percent"] == 40 and levels[0]["knockback_time_ms"] == 200
    assert section(tokens, "[cool time]") == [2000, 2000]
    skill_list = decoded["skill/swordmanskill.lst"]
    guard_index = next(i for i, t in enumerate(skill_list) if t.get("text", "").lower() == "swordman/guard.skl")
    assert skill_list[guard_index - 1]["value"] == 1

    manifests, pixels = [], {}
    for relative in MANIFESTS:
        path = ROOT / relative
        content = json.loads(path.read_text())
        assert len(content["animations"]) == 15
        frames = content["animations"]["guard"]["frames"]
        assert [f["img_frame"] for f in frames] == [123, 124]
        assert [f["duration_ms"] for f in frames] == [10000, 10000]
        if relative.endswith("_r1.json"):
            assert content["canvas_size"] == [320, 224] and content["foot_anchor"] == [133, 167]
        refs = []
        for i, frame in enumerate(frames):
            layers = frame.get("layers", [frame])
            if relative.endswith("_r0.json"):
                assert len(layers) == 9
            textures = []
            for layer in layers:
                texture = layer["texture"]
                local = ROOT / texture.removeprefix("res://")
                assert texture.startswith("res://") and local.is_file(), texture
                pixels[texture] = {"path": texture, "bytes": local.stat().st_size, "sha256_png": sha(local.read_bytes())}
                textures.append(texture)
            refs.append({"frame": i, "image_frame": frame["img_frame"], "duration_ms": frame["duration_ms"], "textures": textures})
        manifests.append({"path": relative, "sha256": sha(path.read_bytes()), "action_count": 15,
                          "guard_frames": refs, "changed": False})

    optional_fx = []
    for name in ("dust", "spark"):
        path = f"character/swordman/effect/animation/guard/{name}.ani"
        value = decoded[path]
        optional_fx.append({"source_ani": path, "frames": value["frames_count"],
                            "duration_ms": delays(value), "total_ms": sum(delays(value)),
                            "resources": value["resources"], "direct_guard_contact_dispatch_proven": False,
                            "exported": False, "runtime_hooked": False})
    report = {"schema": 1, "stage": "R4/05 source preparation only", "created_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "producer": "tools/r4/inspect_guard.py", "producer_sha256": sha(Path(__file__).read_bytes()),
              "reproduce": "/Users/mac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tools/r4/inspect_guard.py",
              "scope": __doc__.strip(), "client_root": str(arguments.client), "pvf_tree": pvf.header,
              "encoding": "Big5", "source_scripts": sources, "source_count": len(sources),
              "identity": {"skill_id": 1, "skill_list": "skill/swordmanskill.lst", "skill_path": GUARD,
                           "name": section(tokens, "[name]"), "name2": section(tokens, "[name2]"),
                           "explain": section(tokens, "[explain]"), "command": section(tokens, "[command key explain]"),
                           "cooldown_ms": section(tokens, "[cool time]"), "consume_MP_range": section(tokens, "[consume MP]"),
                           "first5_levels": levels, "level_property_index_evidence": section(tokens, "[level property]"),
                           "unassigned_static_data": section(tokens, "[static data]")},
              "source_animation": {"path": MASTER, "frames": 2, "image_frames": [123, 124],
                                   "source_offsets": [[-232, -333], [-232, -333]], "source_duration_ms": [10000, 10000],
                                   "source_boxes_and_properties": master["frames"], "weapon_ani_matches": weapon,
                                   "timing_limit": "These are long source pose holds. They do not prove a20s skill duration/startup, nor the original frame-to-contact dispatcher."},
              "existing_visuals": {"new_PNGs_required": 0, "exported_PNGs": 0, "manifests": manifests,
                                   "existing_unique_PNG_count": len(pixels), "existing_PNGs": list(pixels.values()),
                                   "facing": "The existing runtime uses facing1 for unflipped right-facing, facing-1 for horizontal flip. Front-only blocking is explicit skill text; no numeric facing convention is declared by Guard ANI."},
              "adaptation_boundary": {"planned_runtime_hooks_implemented_by_this_tool": False,
                  "source_proven": ["Front-only absorption", "Hold skill key to sustain the pose", "MP paid only once at start", "2s source cooldown", "Level1 physical40%, magical15%, knockback time200ms"],
                  "prototype_plan": {"key": "C in free3D gameplay; bag C remains equipment switch", "physical_absorb_percent": 40,
                                     "incoming_damage_mapping": {"12": 8, "14": 9, "24": 15}, "formula": "max1 ceil(original_damage *0.6)",
                                     "begin_cooldown_ms": 2000, "contact_reaction_ms": 200, "knockback_source_px": 6,
                                     "hold_frame": 0, "contact_frame": 1, "MP_implemented": False},
                  "explicitly_adapted": ["C binding and eligibility/cancellation", "Damage formula/rounding over existing prototype HP rules", "All current melee treated as physical", "Frame0 hold/frame1 impact mapping and reaction clock", "6px push distance", "NoMP pool and no skill levels", "Single contact guard branch with existing enemy hit latch"],
                  "separate_skills": {"cancelguard": "Separate required-level15 passive; explicit normal attack interruption. Not implicitly granted.", "autoguard_and_reflectguard": "Separate skill list IDs3 and2, not manual Guard."}},
              "FX_and_audio_limit": {"optional_source_FX": optional_fx,
                                     "sound_properties_in_master": [p for f in master["frames"] for p in f["properties"] if p["type"] not in [12]],
                                     "direct_contact_FX_or_audio_dispatch_proven": False,
                                     "policy": "No new pictures/audio exported or guessed; optional named FX alone do not establish original contact dispatch. Existing effect sampler keyed by source pose clock is insufficient for a held guard contact event."},
              "verification": {"all11_file_CRC_match": True, "raw_payload_roundtrip_exact": True,
                               "four_weapon_ANI_master_clock_and_offsets_match": True,
                               "four15action_manifests_already_have_guard": True, "all_referenced_PNGs_exist_and_hashed": True,
                               "source_ANI_and_existing_PNGs_unchanged": True, "Godot_or_client_executed": False}}
    write_json(REPORT, report)
    print(json.dumps({"report": str(REPORT.relative_to(ROOT)), "CRC_verified_sources": len(sources),
                      "existing_guard_PNGs": len(pixels), "new_PNGs": 0}, ensure_ascii=False))


if __name__ == "__main__":
    main()
