"""Export the isolated ID84 SwordmanStatue source actor, without runtime hooks.

Only eight original action keys/48 ANI records and their exact RGBA crops are
exported. Source wake-up lasts2400ms. Original AI/armor/magic damage formulas,
ANI events/rotations and HardAttack effect dispatch are not restored. Reads one
explicit canonical image NPK; never runs Godot, Blender, the client or network.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/dnf_client_analysis"))
from inspect_clients import PVF, binary_ani, decode_frame, img_frames, npk_entries
from pixel_imports import PROFILE

SOURCE = ROOT / "source_art/r4/swordman_statue"
ASSETS = ROOT / "assets/r4/swordman_statue"
DATA = ROOT / "data/swordman_statue_r1.json"
REFERENCE = ROOT / "docs/r4_swordman_statue_source_reference.json"
PACK = "sprite_monster_characterstatue.NPK"
IMG = "sprite/monster/characterstatue/swordmanstatue.img"
MOB = "monster/characterstatue/swordmanstatue.mob"
ATK = "monster/characterstatue/attackinfo/swordmanattack.atk"
MAP = "map/hallofdoll/(1,2)b1823.map"
ACTIONS = ("stay", "move", "attack", "damage1", "damage2", "down", "wakeup", "overturn")
CLOCKS = {"stay": (1, 120), "move": (8, 800), "attack": (18, 1200),
          "damage1": (1, 10000), "damage2": (1, 10000), "down": (6, 860),
          "wakeup": (12, 2400), "overturn": (1, 500)}
MARGIN = 8


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def file_sha(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for value in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(value)
    return result.hexdigest()


def write(path: Path, value: bytes) -> None:
    assert path.is_relative_to(SOURCE) or path.is_relative_to(ASSETS) or path in (DATA, REFERENCE), path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(value)


def write_json(path: Path, value: object) -> None:
    write(path, (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode())


def texture(image: Image.Image, path: Path) -> dict:
    assert path.is_relative_to(ASSETS) and image.mode == "RGBA"
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    with Image.open(path) as saved:
        assert saved.mode == "RGBA" and saved.size == image.size and saved.tobytes() == image.tobytes()
    sidecar = path.with_suffix(".png.import")
    previous = sidecar.read_text() if sidecar.exists() else ""
    text = previous or ('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
                        '[deps]\n\nsource_file="res://' + path.relative_to(ROOT).as_posix() + '"\n\n[params]\n')
    for key, value in PROFILE.items():
        pattern = r"^" + re.escape(key) + r"=.*$"
        text = re.sub(pattern, key + "=" + value, text, flags=re.MULTILINE) if re.search(pattern, text, re.MULTILINE) else text.rstrip() + "\n" + key + "=" + value + "\n"
    write(sidecar, text.encode())
    return {"texture": "res://" + path.relative_to(ROOT).as_posix(), "size": list(image.size),
            "sha256_png": file_sha(path), "sha256_rgba": sha(image.tobytes()),
            "import_sidecar": sidecar.relative_to(ROOT).as_posix()}


def source_record(pvf: PVF, path: str, binary_animation: bool = False, text: bool = False) -> tuple:
    raw, crc = pvf.read(path, True)
    assert crc["expected"] == crc["actual_seed_file_number"], path
    decoded = binary_ani(raw) if binary_animation else (raw.decode("big5", "replace") if text else pvf.tokens(path, "big5"))
    raw_path = SOURCE / "pvf" / (path + ".bin")
    json_path = SOURCE / "pvf" / (path + ".json")
    write(raw_path, raw)
    write_json(json_path, {"path": path, "crc": crc, "decoded": decoded})
    assert raw_path.read_bytes() == raw
    return decoded, {"pvf_path": path, "sha256_decoded": sha(raw), "bytes": len(raw), "crc": crc,
                     "crc_matches": True, "raw_reference": raw_path.relative_to(ROOT).as_posix(),
                     "decoded_reference": json_path.relative_to(ROOT).as_posix()}


def album(client: Path) -> tuple:
    package = client / "ImagePacks2" / PACK
    entry = next(e for e in npk_entries(package) if e["path"] == IMG)
    with package.open("rb") as stream:
        stream.seek(entry["offset"])
        raw = stream.read(entry["bytes"])
    destination = SOURCE / "img" / PACK / (IMG + ".bin")
    write(destination, raw)
    assert destination.read_bytes() == raw
    frames, _ = img_frames(raw)
    return raw, frames, {"npk": PACK, "sha256_npk": file_sha(package), "img": IMG,
                         "entry": entry, "sha256_img_payload": sha(raw), "declared_IMG_frames": len(frames),
                         "raw_reference": destination.relative_to(ROOT).as_posix()}


def section(tokens: list, name: str) -> list:
    output, active = [], False
    for token in tokens:
        if token["type"] == 5:
            if active:
                break
            active = token["text"].lower() == name.lower()
        elif active:
            output.append(token.get("text", token.get("value")))
    return output


def source_audio_binding(client: Path, attack: list, attack_source: dict) -> dict:
    assert section(attack, "[hit wav]") == ["R_SM_GUE"]
    raw = (client / "audio.xml").read_bytes()
    tree = ET.fromstring(raw)
    root = next(node for node in tree if node.attrib.get("ID") == "R_SM_GUE")
    assert root.tag == "RANDOM"
    children = [dict(child.attrib) for child in root]
    assert children == [{"TAG": "SM_GUE_ATK_01", "PROB": "50"}, {"TAG": "SM_GUE_ATK_02", "PROB": "50"}]
    effects = []
    snippets = []
    root_match = re.search(rb'<RANDOM\s+ID="R_SM_GUE"\s*>.*?</RANDOM>', raw, re.S)
    assert root_match
    snippets.append(root_match.group())
    for child in children:
        effect = next(node for node in tree if node.attrib.get("ID") == child["TAG"])
        assert effect.tag == "EFFECT"
        effects.append(dict(effect.attrib))
        tag = re.escape(child["TAG"].encode())
        match = re.search(rb'<EFFECT\s+ID="' + tag + rb'"\s+FILE="[^"\r\n]+"\s*/>', raw)
        assert match
        snippets.append(match.group())
    excerpt = SOURCE / "audio/audio_xml_exact_bindings.xml"
    write(excerpt, b"\n".join(snippets) + b"\n")
    evidence = {"source_atk": attack_source, "field": "[hit wav]", "source_tag": "R_SM_GUE",
                "audio_xml_sha256": sha(raw), "xml_type": "RANDOM", "random_children": children,
                "resolved_xml_effects": effects, "exact_source_excerpt": excerpt.relative_to(ROOT).as_posix(),
                "excerpt_sha256": file_sha(excerpt), "audio_exported": False,
                "runtime_hooks_implemented": False,
                "reason": "Source tag selects two50% files. No single branch is chosen or relabeled as a restored contact/voice; no SoundPack is opened in this bounded export."}
    write_json(SOURCE / "audio/source_binding.json", evidence)
    return evidence


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", type=Path, default=Path("/Users/mac/Downloads/天堂95起源单机客户端"))
    arguments = parser.parse_args()
    pvf = PVF(arguments.client / "Script.pvf")
    assert pvf.header["tree_crc_expected"] == pvf.header["tree_crc_actual"] and not pvf.header["parse_error"] and not pvf.header["payload_bounds_errors"]
    raw, table, image_source = album(arguments.client)
    animations, sources, source_frames, crop_images, crops = {}, [], {}, {}, {}
    logical_rectangles = []
    for key in ACTIONS:
        path = f"monster/characterstatue/swordmananimation/{key}.ani"
        ani, provenance = source_record(pvf, path, True)
        sources.append(provenance)
        assert ani["resources"] == [IMG.removeprefix("sprite/")]
        source_frames[key] = ani["frames"]
        assert len(ani["frames"]) == CLOCKS[key][0]
        assert sum(next(p["value"] for p in frame["properties"] if p["type"] == 12) for frame in ani["frames"]) == CLOCKS[key][1]
        animations[key] = {"source_action_key": key, "source_ani": path, "source_sha256": provenance["sha256_decoded"],
                           "source_globals": ani["globals"], "source_resources": ani["resources"], "frames": []}
        for frame in ani["frames"]:
            index = frame["image_frame"]
            if index not in crops:
                image, metadata = decode_frame(raw, index)
                resolved, seen = index, set()
                while "link" in table[resolved]:
                    assert resolved not in seen
                    seen.add(resolved)
                    resolved = table[resolved]["link"]
                crop_images[index] = image
                crops[index] = {**texture(image, ASSETS / "src" / f"{index:03d}.png"),
                                "img_frame": index, "resolved_img_frame": resolved, "img_metadata": metadata,
                                "source": image_source, "operation": "Exact complete source RGBA crop; no resize/repaint/alpha edits"}
            image, meta = crop_images[index], crops[index]["img_metadata"]
            x, y = frame["x"] + meta["x"], frame["y"] + meta["y"]
            logical_rectangles.append([x, y, x + image.width, y + image.height])
    assert sum(len(frames) for frames in source_frames.values()) == 48 and len(crops) == 35
    bounds = [min(b[0] for b in logical_rectangles), min(b[1] for b in logical_rectangles),
              max(b[2] for b in logical_rectangles), max(b[3] for b in logical_rectangles)]
    canvas = (bounds[2] - bounds[0] + MARGIN * 2, bounds[3] - bounds[1] + MARGIN * 2)
    anchor = (MARGIN - bounds[0], MARGIN - bounds[1])
    assert bounds == [-89, -115, 112, 20] and canvas == (217, 151) and anchor == (97, 123)
    records = []
    for key in ACTIONS:
        for index, original in enumerate(source_frames[key]):
            crop, image = crops[original["image_frame"]], crop_images[original["image_frame"]]
            meta = crop["img_metadata"]
            offset = [original["x"] + meta["x"], original["y"] + meta["y"]]
            paste = [anchor[0] + offset[0], anchor[1] + offset[1]]
            assert paste[0] >= MARGIN and paste[1] >= MARGIN
            assert paste[0] + image.width <= canvas[0] - MARGIN and paste[1] + image.height <= canvas[1] - MARGIN
            composed = Image.new("RGBA", canvas, (0, 0, 0, 0))
            composed.paste(image, tuple(paste))  # Complete unmasked RGBA copy, transparent RGB included.
            assert composed.crop((paste[0], paste[1], paste[0] + image.width, paste[1] + image.height)).tobytes() == image.tobytes()
            duration = next(p["value"] for p in original["properties"] if p["type"] == 12)
            frame = {**texture(composed, ASSETS / "frames" / key / f"{index:03d}.png"),
                     "duration_ms": duration, "source_duration_ms": duration, "img_frame": original["image_frame"],
                     "resolved_img_frame": crop["resolved_img_frame"], "ani_offset": [original["x"], original["y"]],
                     "img_metadata": meta, "logical_crop_offset": offset, "composite_paste_offset": paste,
                     "source_crop": crop["texture"], "source_crop_rgba_sha256": crop["sha256_rgba"],
                     "source_properties": original["properties"], "source_boxes": original["boxes"],
                     "derived_artifact": True, "operation": "Unmasked source RGBA copy on shared transparent canvas; ANI properties retained as metadata"}
            animations[key]["frames"].append(frame)
            records.append({"action": key, "frame": index, **frame})
    decoded = {}
    paths = [MOB, ATK, "monster/monster.lst", "monster/monster.kor.str", "n_string.lst",
             "map/map.lst", MAP, "dungeon/act2/hallofdoll.dgn", "dungeon/dungeon.kor.str"]
    for path in paths:
        value, proof = source_record(pvf, path, text=path.endswith(".str"))
        decoded[path] = value
        sources.append(proof)
    monster_list = decoded["monster/monster.lst"]
    identity_index = next(i for i, token in enumerate(monster_list) if token.get("text", "").lower() == "characterstatue/swordmanstatue.mob")
    assert monster_list[identity_index - 1]["value"] == 84
    name = next(line.split(">", 1)[1] for line in decoded["monster/monster.kor.str"].splitlines() if line.startswith("name_2004>"))
    monster_records = section(decoded[MAP], "[monster]")
    assert len(monster_records) % 10 == 0
    direct_records = [monster_records[i:i + 10] for i in range(0, len(monster_records), 10) if monster_records[i] == 84]
    assert direct_records and any(row[3:5] == [1061, 275] for row in direct_records)
    attack_tags = [token.get("text") for token in decoded[ATK] if token["type"] == 5]
    assert "[magic]" in attack_tags and "[dark element]" in attack_tags and "[physic]" not in attack_tags
    assert {"type": 16, "value": "atk_darklightning"} in source_frames["attack"][0]["properties"]
    assert all(frame["duration_ms"] == 200 for frame in animations["wakeup"]["frames"])
    audio = source_audio_binding(arguments.client, decoded[ATK], next(s for s in sources if s["pvf_path"] == ATK))
    notes = [
        "Eight original source action keys stay/move/attack/damage1/damage2/down/wakeup/overturn retain48 records. No attack1 alias, HardAttack effect action or invented frame is added.",
        "WakeUp is12×200ms=2400ms, alternating original ANI X offsets−233/−235 and Y−331. Shared IMG0 is copied at every original offset: no static replacement, speedup or shake removal.",
        "Canvas217×151/foot97,123 is the minimum axis-aligned union of complete selected RGBA crop rectangles plus exactly8px padding on each side. Source logical-foot anchor is retained; visible crop pixels may extend20px below it. No resize/repaint/resampling or transparent-RGB edit.",
        "Source SwordmanAttack.atk is MAGIC with DARK element, not physical. Damage reaction/down, source push/lift values and fort-armor category remain evidence, not implemented formulas, armor or runtime damage rules.",
        "Attack frame0 source property16 atk_darklightning is retained without executing or guessing its dispatcher/FX. Overturn property8 π is retained without applying an unproved original engine rotation; exported pictures remain unrotated source RGBA composites.",
        "MOB directly references WakeUp/HardAttack1/2 etc motions, but original passive/wake/AI/armor/event behavior is not restored. HardAttack effect ANI/IMG assets are outside this export.",
        "Source hit-wav R_SM_GUE resolves to a two-file50/50 RANDOM in audio.xml. Exact bindings are retained; no arbitrary fixed branch, voice assignment, SoundPack extract or runtime audio is created.",
        "ID84, Big5 name_2004 鬼劍士雕像, direct MOB motion/attack references and HallOfDoll map entry at1061,275 are independently retained with CRC-verified PVF payloads. This is source provenance, not a restored original map or AI claim.",
        "Only isolated new prefixes are written. No existing runtime/source/scene/manifest, client file, profile, Godot/Blender process or network is modified or invoked. Runtime hooks remain false."
    ]
    data = {"schema": 1, "monster_id": 84, "source_name": name, "canvas_size": list(canvas), "foot_anchor": list(anchor),
            "source_action_keys": list(ACTIONS), "animations": animations, "texture_sampling": "nearest",
            "audio": {"sounds": {}, "source_hit_wav_tag": "R_SM_GUE", "source_xml_binding": audio,
                      "attack_voice": None, "hurt_voice": None, "death_voice": None, "actions": {}, "runtime_hooks_implemented": False},
            "source_reference": "res://docs/r4_swordman_statue_source_reference.json", "runtime_hooks_implemented": False, "notes": notes}
    write_json(DATA, data)
    report = {"schema": 1, "stage": "R4/08 isolated source actor asset preparation",
              "created_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "producer": "tools/r4/export_swordman_statue.py", "producer_sha256": file_sha(Path(__file__)), "client_root": str(arguments.client),
              "pvf_tree": pvf.header, "encoding": "Big5", "identity": {"monster_id": 84, "source_name": name, "name_key": "name_2004", "source_mob": MOB,
              "source_category": section(decoded[MOB], "[category]"), "direct_map": MAP, "original_map_monster_records": direct_records,
              "map_record_position_indices": [3, 4], "direct_map_source_positions": [row[3:5] for row in direct_records],
              "source_attack_info": ATK, "source_attack_type": "magic", "source_element": "dark"},
              "source_scripts": sources, "actor_image_source": image_source, "source_crops": list(crops.values()), "derived_composites": records,
              "canvas_size": list(canvas), "foot_anchor": list(anchor), "full_RGBA_crop_union_relative_to_source_foot": bounds,
              "source_action_keys": list(ACTIONS), "runtime_action_keys": list(animations),
              "action_clocks": {key: {"records": len(a["frames"]), "duration_ms": [f["duration_ms"] for f in a["frames"]], "total_ms": sum(f["duration_ms"] for f in a["frames"])} for key, a in animations.items()},
              "unimplemented_source_events": [{"action": "attack", "frame": 0, "property": {"type": 16, "value": "atk_darklightning"}},
                                               {"action": "overturn", "frame": 0, "property": next(p for p in source_frames["overturn"][0]["properties"] if p["type"] == 8)}],
              "audio": audio, "runtime_output": {"path": DATA.relative_to(ROOT).as_posix(), "sha256": file_sha(DATA)},
              "import_policy": {"PNG": PROFILE, "sampling": "Nearest in source actor runtime", "scoped_only": True},
              "verification": {"CRC_verified_source_payloads": len(sources), "source_IMG_archives": 1, "source_crops": len(crops), "composite_records": len(records),
              "total_PNGs": len(crops) + len(records), "all_source_crop_RGBA_exact": True, "all_composites_reverse_crop_RGBA_exact": True,
              "all_PNG_roundtrips_exact": True, "all_full_crops_minimum8px_canvas_margin": True, "long_holds_preserved": True,
              "wakeup_12_by200ms_offsets_preserved": True, "audio_exported": False, "Godot_native_import_or_playback_tested": False},
              "runtime_hooks_implemented": False, "notes": notes}
    write_json(REFERENCE, report)
    print(json.dumps({"source_keys": list(ACTIONS), "records": len(records), "unique_crops": len(crops), "PNG_count": len(crops) + len(records),
                      "canvas": list(canvas), "anchor": list(anchor), "CRC_payloads": len(sources), "audio_exported": False,
                      "reference": REFERENCE.relative_to(ROOT).as_posix()}, ensure_ascii=False))


if __name__ == "__main__":
    main()
