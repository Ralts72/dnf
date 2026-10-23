"""Prepare four isolated Upper Slash aliases; write no image/runtime assets.

All15 parent action objects remain exact. The new upperslash action explicitly
copies Attack3's nine original records/550ms and adds only source/alias metadata.
This is a prototype reuse, not a recovered original skill-to-ANI dispatcher.
Reads nine bounded PVF sources and existing canonical images as data only.
"""
from __future__ import annotations

import argparse
import copy
import datetime
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/dnf_client_analysis"))
from inspect_clients import PVF, binary_ani, decode_frame, npk_entries
from export_r0 import LAYERS

SOURCE = ROOT / "source_art/r4/upper_slash"
REFERENCE = ROOT / "docs/r4_upper_slash_source_reference.json"
MASTER = "character/swordman/animation/attack3.ani"
SKILL = "skill/swordman/upperslash.skl"
CHR = "character/swordman/swordman.chr"
ATK = "character/swordman/attackinfo/upperslash.atk"
OUTPUTS = [ROOT / f"data/swordman_upper_{appearance}_{view}.json"
           for appearance in ("practice", "great") for view in ("r0", "r1")]


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def file_sha(path: Path) -> str:
    return sha(path.read_bytes())


def write(path: Path, raw: bytes) -> None:
    assert path.is_relative_to(SOURCE) or path in OUTPUTS or path == REFERENCE, path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(raw)


def write_json(path: Path, value: object) -> None:
    write(path, (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode())


def section(tokens: list, label: str) -> list:
    output, active = [], False
    for token in tokens:
        if token["type"] == 5:
            if active:
                break
            active = token["text"] == label
        elif active:
            output.append(token.get("text", token.get("value")))
    return output


def delays(animation: dict) -> list:
    return [next(p["value"] for p in frame["properties"] if p["type"] == 12) for frame in animation["frames"]]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", type=Path, default=Path("/Users/mac/Downloads/天堂95起源单机客户端"))
    args = parser.parse_args()
    pvf = PVF(args.client / "Script.pvf")
    assert pvf.header["tree_crc_expected"] == pvf.header["tree_crc_actual"]
    assert not pvf.header["parse_error"] and not pvf.header["payload_bounds_errors"]
    sources, decoded = [], {}

    def source(path: str):
        if path not in decoded:
            raw, crc = pvf.read(path, True)
            assert crc["expected"] == crc["actual_seed_file_number"], path
            value = binary_ani(raw) if path.endswith(".ani") else pvf.tokens(path, "big5")
            raw_path = SOURCE / "pvf" / (path + ".bin")
            json_path = SOURCE / "pvf" / (path + ".json")
            write(raw_path, raw)
            write_json(json_path, {"path": path, "crc": crc, "decoded": value})
            assert raw_path.read_bytes() == raw
            sources.append({"path": path, "crc": crc, "crc_matches": True, "bytes": len(raw), "sha256_decoded": sha(raw),
                            "raw_reference": raw_path.relative_to(ROOT).as_posix(), "decoded_reference": json_path.relative_to(ROOT).as_posix()})
            decoded[path] = value
        return decoded[path]

    skill_list = source("skill/swordmanskill.lst")
    index = next(i for i, token in enumerate(skill_list) if token.get("text", "").lower() == "swordman/upperslash.skl")
    assert skill_list[index - 1]["value"] == 46
    skill, character, attack, master = source(SKILL), source(CHR), source(ATK), source(MASTER)
    assert section(skill, "[name]") == ["上挑"] and section(skill, "[cool time]") == [2000, 2000]
    initial = section(character, "[skill]")
    initial_pairs = [initial[i:i + 2] for i in range(0, len(initial), 2)]
    assert [46, 1] in initial_pairs
    assert master["frames_count"] == 9 and delays(master) == [50] * 8 + [150]
    assert [frame["image_frame"] for frame in master["frames"]] == list(range(33, 42))
    assert all((frame["x"], frame["y"]) == (-232, -333) for frame in master["frames"])
    weapon_anis = {}
    weapon_proof = []
    for family in ("lswd", "mswd"):
        for suffix in ("b", "c"):
            path = f"equipment/character/swordman/weapon/hsword/{family}{suffix}/attack3.ani"
            ani = source(path)
            assert len(ani["frames"]) == 9 and delays(ani) == delays(master)
            assert all((a["image_frame"], a["x"], a["y"]) == (b["image_frame"], b["x"], b["y"]) for a, b in zip(master["frames"], ani["frames"]))
            weapon_anis[(family, suffix)] = ani
            weapon_proof.append({"source_ani": path, "source_resources": ani["resources"],
                                 "same_frame_order_offsets_and_durations_as_Attack3": True,
                                 "duration_ms": delays(ani), "source_globals": ani["globals"]})
    assert len(sources) == 9
    parents = {}
    guard = {}
    for appearance in ("practice", "great"):
        for view in ("r0", "r1"):
            path = ROOT / f"data/swordman_ghost_{appearance}_{view}.json"
            parent = json.loads(path.read_text())
            assert len(parent["animations"]) == 15 and sum(len(action["frames"]) for action in parent["animations"].values()) == 110
            parents[(appearance, view)] = parent
            guard[path.relative_to(ROOT).as_posix()] = file_sha(path)
            for action in parent["animations"].values():
                for frame in action["frames"]:
                    for layer in frame.get("layers", [frame]):
                        path = ROOT / layer["texture"].removeprefix("res://")
                        key = path.relative_to(ROOT).as_posix()
                        if key not in guard:
                            guard[key] = file_sha(path)
    old_album_report = json.loads((ROOT / "docs/r4_ghost_slash_source_reference.json").read_text())
    old_albums = {(entry["npk"], entry["img"]): entry for entry in old_album_report["source_albums"]}
    albums, raw_pixels, composites, outputs = {}, {}, [], {}

    def album(pack: str, img: str):
        key = (pack, img)
        if key not in albums:
            # Reuse a previously frozen exact payload reference; do not create
            # another IMG copy or any PNG. Still reread canonical NPK bytes.
            previous = old_albums[key]
            package = args.client / "ImagePacks2" / pack
            entry = next(item for item in npk_entries(package) if item["path"] == img)
            with package.open("rb") as stream:
                stream.seek(entry["offset"])
                raw = stream.read(entry["bytes"])
            assert sha(raw) == previous["sha256_img_payload"]
            assert (ROOT / previous["raw_reference"]).read_bytes() == raw
            albums[key] = (raw, {"npk": pack, "img": img, "entry": entry,
                                 "sha256_img_payload": sha(raw), "existing_raw_reference": previous["raw_reference"],
                                 "existing_raw_reference_exact": True, "new_IMG_exported": False})
        return albums[key]

    for appearance in ("practice", "great"):
        raw_parent, composed_parent = parents[(appearance, "r0")], parents[(appearance, "r1")]
        assert composed_parent["canvas_size"] == [320, 224] and composed_parent["foot_anchor"] == [133, 167]
        for index, source_frame in enumerate(master["frames"]):
            raw_frame = raw_parent["animations"]["attack3"]["frames"][index]
            derived_frame = composed_parent["animations"]["attack3"]["frames"][index]
            assert raw_frame["duration_ms"] == derived_frame["duration_ms"] == delays(master)[index]
            assert raw_frame["img_frame"] == derived_frame["img_frame"] == source_frame["image_frame"]
            assert raw_frame["source_properties"] == derived_frame["source_properties"] == source_frame["properties"]
            assert raw_frame["source_boxes"] == derived_frame["source_boxes"] == source_frame["boxes"]
            canvas = Image.new("RGBA", (320, 224), (0, 0, 0, 0))
            assert [layer["name"] for layer in raw_frame["layers"]] == [entry[0] for entry in LAYERS]
            for name, pack_suffix, image_path in LAYERS:
                if appearance == "great" and name in ("weapon_back", "weapon_front"):
                    suffix = "b" if name == "weapon_back" else "c"
                    pack_suffix, image_path = "weapon_mswd", f"weapon/mswd/mswd0007{suffix}.img"
                pack = "sprite_character_swordman_equipment_" + pack_suffix + ".NPK"
                img = "sprite/character/swordman/equipment/" + image_path
                raw, provenance = album(pack, img)
                image, metadata = decode_frame(raw, source_frame["image_frame"])
                layer = next(layer for layer in raw_frame["layers"] if layer["name"] == name)
                offset = [source_frame["x"] + metadata["x"], source_frame["y"] + metadata["y"]]
                assert layer["offset"] == offset
                path = ROOT / layer["texture"].removeprefix("res://")
                with Image.open(path) as original:
                    assert original.mode == "RGBA" and original.size == image.size and original.tobytes() == image.tobytes()
                raw_pixels[layer["texture"]] = {"texture": layer["texture"], "layer": name, "source": provenance,
                    "img_frame": source_frame["image_frame"], "img_metadata": metadata, "ani_offset": [source_frame["x"], source_frame["y"]],
                    "logical_crop_offset": offset, "size": list(image.size), "sha256_png": file_sha(path),
                    "sha256_rgba": sha(image.tobytes()), "source_RGBA_and_offset_exact": True, "new_export": False}
                canvas.alpha_composite(image, (133 + offset[0], 167 + offset[1]))
            path = ROOT / derived_frame["texture"].removeprefix("res://")
            with Image.open(path) as original:
                assert original.mode == "RGBA" and original.size == (320, 224) and original.tobytes() == canvas.tobytes()
            composites.append({"appearance": appearance, "frame": index, "texture": derived_frame["texture"], "img_frame": source_frame["image_frame"],
                               "size": [320, 224], "duration_ms": delays(master)[index], "sha256_png": file_sha(path), "sha256_rgba": sha(canvas.tobytes()),
                               "existing_composite_rebuilt_from_source_layers_exact": True, "new_export": False})
        for view in ("r0", "r1"):
            parent = parents[(appearance, view)]
            result = copy.deepcopy(parent)
            alias = copy.deepcopy(parent["animations"]["attack3"])
            alias.update({"source_ani": MASTER, "source_action_key": "attack3", "prototype_alias_of": "attack3",
                          "original_UpperSlash_dispatch_restored": False})
            for index, frame in enumerate(alias["frames"]):
                frame["source_ani"] = MASTER
                comparison = copy.deepcopy(frame)
                comparison.pop("source_ani")
                assert comparison == parent["animations"]["attack3"]["frames"][index]
            result["animations"]["upperslash"] = alias
            result["source_reference"] = "res://docs/r4_upper_slash_source_reference.json"
            result["runtime_hooks_implemented"] = False
            result["upper_slash_alias"] = {"source_skill_id": 46, "source_skill": SKILL, "source_animation": MASTER,
                "prototype_alias_of": "attack3", "new_PNGs": 0, "original_skill_to_animation_dispatch_proven": False,
                "MP_superarmor_After_FX_audio_implemented": False}
            if view == "r1":
                result["source_data"] = f"data/swordman_upper_{appearance}_r0.json"
            for key in parent["animations"]:
                assert result["animations"][key] == parent["animations"][key]
            assert len(result["animations"]) == 16 and sum(len(a["frames"]) for a in result["animations"].values()) == 119
            path = ROOT / f"data/swordman_upper_{appearance}_{view}.json"
            write_json(path, result)
            outputs[path.relative_to(ROOT).as_posix()] = {"sha256": file_sha(path), "parent": f"data/swordman_ghost_{appearance}_{view}.json",
                "existing15_action_objects_exact": True, "action_count": 16, "record_count": 119,
                "alias_records": 9, "alias_duration_ms": 550, "new_frame_metadata_only": ["source_ani"]}
    assert len(raw_pixels) == 99 and len(composites) == 18 and len(albums) == 11
    for relative, expected in guard.items():
        assert file_sha(ROOT / relative) == expected, relative
    write_json(SOURCE / "existing_artifact_guard.json", {"all_files_unchanged": True, "paths_sha256": guard})
    level = section(skill, "[level info]")
    notes = [
        "New upperslash is an explicit prototype alias of existing source Attack3, not an asserted recovered basic Upper Slash ANI dispatcher. All nine records,550ms, source frames33..41, ANI offsets−232,−333, properties, boxes, layer order and exact original pixels remain unchanged.",
        "Every new alias record carries source_ani character/swordman/animation/attack3.ani. Existing15 action objects are exact parent copies. The ordinary attack3 action is untouched, and no original SKL/ATK values become direct prototype HP/physics formulas.",
        "ID46→skill/swordman/upperslash.skl and initial CHR46lv1 are direct source evidence. The source text says launch and superarmor, original command Z, cooldown2000ms, physical weapon effect, MP6..40. Prototype V binding, finite launch, HP damage, runtime clock integration, MP and superarmor are not implemented by this preparation.",
        "UpperSlash.atk directly contains physic/down/hit lift up but no numeric lift velocity. SKL first dungeon row[120,350,100,30] and display multiplier0.285714 imply about100% displayed lift ratio;350 is not proven pixels/s or height. Original gravity/mass/air protection/force mapping and skill-to-ANI/FX/audio dispatcher remain unknown.",
        "Male CHR has no standalone Animation/UpperSlash.ani in this PVF; it declares Attack3 and UpperSlashAfter. The separate After/FX/MP/armor/cancel/voice behavior is not restored or included. Do not silently append After or grant source cancel semantics.",
        "Zero new PNGs, zero IMG copies/repaints, no import sidecars or existing files are written. Source layers are independently reread from eleven explicit canonical IMG entries and matched to99 existing crops and18 composed frames. Already frozen exact IMG payload archives are referenced rather than duplicated.",
        "Four new manifests retain fixed R1 canvas320×224/foot133,167 and all parent actions. Existing input/appearance selectors/runtime/scenes/profile/08 data are not changed. Hooks remain false; Godot/Blender/client/network are never invoked."
    ]
    report = {"schema": 1, "stage": "R4/09 isolated Upper Slash source/alias preparation",
        "created_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "producer": "tools/r4/prepare_upper_slash.py", "producer_sha256": file_sha(Path(__file__)),
        "client_root": str(args.client), "pvf_tree": pvf.header, "encoding": "Big5", "source_scripts": sources,
        "identity": {"skill_id": 46, "skill_path": SKILL, "skill_list": "skill/swordmanskill.lst", "source_name": section(skill, "[name]"),
                     "source_CHR": CHR, "initial_skill_pairs": initial_pairs, "initial_level": 1},
        "source_skill_fields": {key: section(skill, key) for key in ["[name]", "[name2]", "[explain]", "[basic explain]", "[command key explain]", "[required level]", "[cool time]", "[consume MP]", "[weapon effect type]", "[static data]", "[level property]"]},
        "first_dungeon_level_info": {"stride": level[0], "first10_raw_rows": [level[1 + i * 4:1 + (i + 1) * 4] for i in range(10)],
                                    "raw350_to_pixel_mapping_proven": False},
        "source_attack_info": {"path": ATK, "tokens": attack},
        "alias": {"runtime_action_key": "upperslash", "prototype_alias_of": "attack3", "source_action_key": "attack3", "source_ani": MASTER,
                  "records": 9, "total_ms": 550, "duration_ms": delays(master), "source_offsets": [[f["x"], f["y"]] for f in master["frames"]],
                  "source_image_frames": [f["image_frame"] for f in master["frames"]], "source_frames": master["frames"], "source_globals": master["globals"],
                  "original_skill_to_main_animation_dispatch_proven": False, "frame_copy_comparison_ignores_only_added_source_ani": True},
        "weapon_ANI": weapon_proof, "source_albums": [evidence for raw, evidence in albums.values()],
        "existing_source_crops": list(raw_pixels.values()), "existing_derived_composites": composites, "outputs": outputs,
        "existing_guard_reference": "source_art/r4/upper_slash/existing_artifact_guard.json", "existing_guarded_files": len(guard),
        "runtime_hooks_implemented": False, "verification": {"CRC_verified_payloads": 9, "parent_manifests_unchanged": 4,
             "parent15_action_objects_exact": 60, "alias_frame_copies_with_added_source_ani_only": 36,
             "canonical_IMG_archives_referenced_exact": 11, "existing_crop_RGBA_and_offsets_exact": 99,
             "existing_composites_rebuilt_complete_RGBA": 18, "all_existing_guarded_files_unchanged": True,
             "new_PNGs": 0, "new_IMG_payloads": 0, "native_Godot_import_or_play_tested": False}, "notes": notes}
    write_json(REFERENCE, report)
    print(json.dumps({"outputs": outputs, "source_CRC_payloads": 9, "new_PNGs": 0, "existing_RGBA_crops": 99,
                      "existing_RGBA_composites": 18, "guarded_old_files": len(guard), "reference": REFERENCE.relative_to(ROOT).as_posix()}, ensure_ascii=False))


if __name__ == "__main__":
    main()
