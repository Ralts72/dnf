"""Export only the source-backed StoneMaster close-punch asset subset.

Writes isolated new R4/06 actor/scenery assets and source evidence. Six original
action keys and all32 source records remain intact. No runtime hook, Godot,
client executable, original AI, Blender or network operation is performed.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/dnf_client_analysis"))
from inspect_clients import PVF, binary_ani, decode_frame, img_frames, npk_entries
from pixel_imports import PROFILE
from export_audio import packets, normalize_comments
sys.path.insert(0, str(ROOT / "tools/r3"))
from export_draconian_audio import decoded_audio, page_audit

SOURCE = ROOT / "source_art/r4/stonemaster"
ASSETS = ROOT / "assets/r4/stonemaster"
SCENERY = ROOT / "assets/r4/doll_gallery"
DATA = ROOT / "data/stonemaster_r1.json"
REFERENCE = ROOT / "docs/r4_stonemaster_source_reference.json"
PACK = "sprite_monster_dollmaster.NPK"
IMG = "sprite/monster/dollmaster/stonemaster.img"
ACTIONS = ("stay", "move", "attack", "damage1", "damage2", "down")
CANVAS = (88, 111)
ANCHOR = (49, 89)
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
    assert any(path.is_relative_to(base) for base in (SOURCE, ASSETS, SCENERY)) or path in (DATA, REFERENCE), path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(value)


def write_json(path: Path, value: object) -> None:
    write(path, (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode())


def texture(image: Image.Image, path: Path) -> dict:
    assert path.is_relative_to(ASSETS) or path.is_relative_to(SCENERY)
    path.parent.mkdir(parents=True, exist_ok=True)
    assert image.mode == "RGBA"
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


def album(client: Path, pack: str, image_path: str) -> tuple:
    assert pack in (PACK, "sprite_map_act2_amon.NPK")
    package = client / "ImagePacks2" / pack
    entry = next(e for e in npk_entries(package) if e["path"] == image_path)
    with package.open("rb") as stream:
        stream.seek(entry["offset"])
        raw = stream.read(entry["bytes"])
    destination = SOURCE / "img" / pack / (image_path + ".bin")
    write(destination, raw)
    assert destination.read_bytes() == raw
    frames, _ = img_frames(raw)
    return raw, frames, {"npk": pack, "sha256_npk": file_sha(package), "img": image_path,
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


def contact_audio(client: Path, punch: list, source_atk: dict) -> dict:
    assert section(punch, "[hit wav]") == ["STONE_DMG"]
    xml_raw = (client / "audio.xml").read_bytes()
    node = next(n for n in ET.fromstring(xml_raw) if n.attrib.get("ID") == "STONE_DMG")
    attributes = dict(node.attrib)
    entry_path = attributes["FILE"].replace("\\", "/").lower()
    assert entry_path == "sounds/effect/stone_dmg.ogg"
    package = client / "SoundPacks/sounds_effect.npk"
    entry = next(e for e in npk_entries(package, False) if e["path"] == entry_path)
    assert entry["bytes"] <= 512 * 1024
    with package.open("rb") as stream:
        stream.seek(entry["offset"])
        raw = stream.read(entry["bytes"])
    assert raw.startswith(b"OggS")
    original = SOURCE / "audio/stone_dmg.ogg"
    runtime = ASSETS / "audio/stone_dmg.ogg"
    write(original, raw)
    source_packets = packets(raw)
    comment = source_packets[1]
    assert comment.startswith(b"\x03vorbis")
    cursor = 11 + struct.unpack_from("<I", comment, 7)[0]
    count = struct.unpack_from("<I", comment, cursor)[0]
    cursor += 4
    bare = 0
    for _ in range(count):
        size = struct.unpack_from("<I", comment, cursor)[0]
        bare += b"=" not in comment[cursor + 4:cursor + 4 + size]
        cursor += 4 + size
    if bare:
        assert bare == 1
        safe, fix = normalize_comments(raw)
    else:
        safe, fix = raw, {"comments_fixed": 0, "all_noncomment_packets_identical": True}
    write(runtime, safe)
    runtime_packets = packets(safe)
    assert len(source_packets) == len(runtime_packets)
    assert all(a == b for i, (a, b) in enumerate(zip(source_packets, runtime_packets)) if i != 1)
    assert page_audit(raw) == page_audit(safe)
    ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
    assert ffmpeg and ffprobe, "Local ffmpeg/ffprobe required for exact PCM verification"
    pcm_a, proof_a = decoded_audio(original, ffmpeg, ffprobe)
    pcm_b, proof_b = decoded_audio(runtime, ffmpeg, ffprobe)
    assert pcm_a == pcm_b
    sidecar = runtime.with_suffix(".ogg.import")
    if not sidecar.exists():
        write(sidecar, ('[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n\n[deps]\n\nsource_file="res://'
                        + runtime.relative_to(ROOT).as_posix() + '"\n\n[params]\n\nloop=false\nloop_offset=0.0\nbpm=0.0\nbeat_count=0\nbar_beats=4\n').encode())
    evidence = {"tag": "STONE_DMG", "path": "res://" + runtime.relative_to(ROOT).as_posix(),
                "canonical_npk": "sounds_effect.npk", "sha256_npk": file_sha(package), "entry": entry,
                "audio_xml_sha256": sha(xml_raw), "xml_attributes": attributes,
                "retained_original": original.relative_to(ROOT).as_posix(), "sha256_source_ogg": sha(raw),
                "sha256_runtime_ogg": sha(safe), "metadata_fix": fix,
                "all_noncomment_packets_identical": True, "ogg_timing_headers_identical": True,
                "source_PCM": proof_a, "runtime_PCM": proof_b, "PCM_byte_identical": True,
                "source_binding": {"pvf_path": source_atk["pvf_path"], "sha256_decoded": source_atk["sha256_decoded"],
                                   "field": "[hit wav]", "tag": "STONE_DMG"},
                "runtime_hooks_implemented": False, "role": "Explicit physical punch contact, not attack/hurt/death voice"}
    write_json(SOURCE / "audio/source_binding.json", evidence)
    return evidence


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", type=Path, default=Path("/Users/mac/Downloads/天堂95起源单机客户端"))
    arguments = parser.parse_args()
    pvf = PVF(arguments.client / "Script.pvf")
    assert pvf.header["tree_crc_expected"] == pvf.header["tree_crc_actual"] and not pvf.header["parse_error"] and not pvf.header["payload_bounds_errors"]
    raw, table, image_source = album(arguments.client, PACK, IMG)
    animations, sources, source_frames, crop_images, crops = {}, [], {}, {}, {}
    for key in ACTIONS:
        path = f"monster/dollmaster/stoneanimation/{key}.ani"
        ani, provenance = source_record(pvf, path, True)
        sources.append(provenance)
        assert ani["resources"] == [IMG.removeprefix("sprite/")]
        source_frames[key] = ani["frames"]
        animations[key] = {"source_action_key": key, "source_ani": path, "source_sha256": provenance["sha256_decoded"],
                           "source_globals": ani["globals"], "source_resources": ani["resources"], "frames": []}
        for frame in ani["frames"]:
            index = frame["image_frame"]
            if index in crops:
                continue
            image, metadata = decode_frame(raw, index)
            resolved, seen = index, set()
            while "link" in table[resolved]:
                assert resolved not in seen
                seen.add(resolved)
                resolved = table[resolved]["link"]
            crop_images[index] = image
            crops[index] = {**texture(image, ASSETS / "src" / f"{index:03d}.png"),
                            "img_frame": index, "resolved_img_frame": resolved, "img_metadata": metadata,
                            "source": image_source, "operation": "Exact complete source RGBA crop; no resampling/alpha edits"}
    assert sum(len(f) for f in source_frames.values()) == 32 and len(crops) == 11
    records, used_bounds = [], []
    for key in ACTIONS:
        for index, original in enumerate(source_frames[key]):
            crop = crops[original["image_frame"]]
            image = crop_images[original["image_frame"]]
            meta = crop["img_metadata"]
            offset = [original["x"] + meta["x"], original["y"] + meta["y"]]
            paste = [ANCHOR[0] + offset[0], ANCHOR[1] + offset[1]]
            assert paste[0] >= MARGIN and paste[1] >= MARGIN
            assert paste[0] + image.width <= CANVAS[0] - MARGIN and paste[1] + image.height <= CANVAS[1] - MARGIN
            composed = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
            # Pillow may expand a mutable two-item box in place; preserve our
            # two-component offset metadata by passing an immutable tuple.
            composed.paste(image, tuple(paste))  # Unmasked RGBA copy, including transparent RGB.
            assert composed.crop((paste[0], paste[1], paste[0] + image.width, paste[1] + image.height)).tobytes() == image.tobytes()
            duration = next(p["value"] for p in original["properties"] if p["type"] == 12)
            frame = {**texture(composed, ASSETS / "frames" / key / f"{index:03d}.png"),
                     "duration_ms": duration, "source_duration_ms": duration, "img_frame": original["image_frame"],
                     "resolved_img_frame": crop["resolved_img_frame"], "ani_offset": [original["x"], original["y"]],
                     "img_metadata": meta, "logical_crop_offset": offset, "composite_paste_offset": paste,
                     "source_crop": crop["texture"], "source_crop_rgba_sha256": crop["sha256_rgba"],
                     "source_properties": original["properties"], "source_boxes": original["boxes"],
                     "derived_artifact": True, "operation": "Unmasked source RGBA copy on shared transparent canvas"}
            animations[key]["frames"].append(frame)
            records.append({"action": key, "frame": index, **frame})
            used_bounds.append([offset[0], offset[1], offset[0] + image.width, offset[1] + image.height])
    logical_bounds = [min(b[0] for b in used_bounds), min(b[1] for b in used_bounds), max(b[2] for b in used_bounds), max(b[3] for b in used_bounds)]
    assert logical_bounds == [-41, -81, 31, 14]
    decoded = {}
    reference_paths = ["monster/dollmaster/stonemaster.mob", "monster/dollmaster/attackinfo/stoneattackpunch.atk",
                       "monster/dollmaster/attackinfo/stoneattackgem.atk", "monster/monster.lst", "monster/monster.kor.str",
                       "n_string.lst", "map/map.lst", "map/hallofdoll/(1,1)n1818.map", "dungeon/act2/hallofdoll.dgn", "dungeon/dungeon.kor.str"]
    for path in reference_paths:
        value, proof = source_record(pvf, path, text=path.endswith(".str"))
        decoded[path] = value
        sources.append(proof)
    monster_list = decoded["monster/monster.lst"]
    i = next(i for i, t in enumerate(monster_list) if t.get("text", "").lower() == "dollmaster/stonemaster.mob")
    assert monster_list[i - 1]["value"] == 37
    name = next(line.split(">", 1)[1] for line in decoded["monster/monster.kor.str"].splitlines() if line.startswith("name_510>"))
    environment = []
    for key, img in (("statue", "200obj03"), ("far", "far")):
        path = "map/hallofdoll/animation/" + ("statue0" if key == "statue" else "far1") + ".ani"
        ani, proof = source_record(pvf, path, True)
        sources.append(proof)
        img_path = f"sprite/map/act2/amon/{img}.img"
        img_raw, _, img_source = album(arguments.client, "sprite_map_act2_amon.NPK", img_path)
        image, metadata = decode_frame(img_raw, 0)
        assert image.size == ((99, 205) if key == "statue" else (640, 410))
        environment.append({"key": key, **texture(image, SCENERY / f"{key}.png"), "source_ani": path,
                            "source": img_source, "img_frame": 0, "img_metadata": metadata,
                            "ani_offset": [ani["frames"][0]["x"], ani["frames"][0]["y"]],
                            "source_globals": ani["globals"], "source_properties": ani["frames"][0]["properties"],
                            "source_boxes": ani["frames"][0]["boxes"], "operation": "Exact unmodified source RGBA crop"})
    punch_path = "monster/dollmaster/attackinfo/stoneattackpunch.atk"
    audio = contact_audio(arguments.client, decoded[punch_path], next(s for s in sources if s["pvf_path"] == punch_path))
    notes = ["Six original source keys stay/move/attack/damage1/damage2/down remain unchanged; attack is not renamed attack1 and no duplicate alias record is generated.",
             "All32 original ANI records, durations, properties, boxes and IMG crop offsets are retained.10000ms damage/down holds are source pose records, not implemented hitstun/death timers.",
             "The source MOB is a range-combat caster. Only the selected physical close-punch assets are prepared. Spell/projectile/summon/control AI is not restored or implemented.",
             "Canvas88x111/foot49,89 contains complete RGBA crop rectangles with at least8pixels on every side, not only nontransparent bounds. No resize, repaint or transparent-RGB edits.",
             "STONE_DMG is directly referenced by source punch ATK and resolved by audio.xml into canonical sounds_effect.npk. Runtime contact timing and engine damage formulas are not restored.",
             "The two scenery frames are separate source outputs. Layout, any new physical geometry/HP/AI/window/damage rules and route connection are future explicit adaptations.",
             "No runtime hook, scene/manifest/previous-asset modification or Godot/client execution is performed."]
    data = {"schema": 1, "monster_id": 37, "source_name": name, "canvas_size": list(CANVAS), "foot_anchor": list(ANCHOR),
            "source_action_keys": list(ACTIONS), "animations": animations, "audio": {"sounds": {"STONE_DMG": {"path": audio["path"]}},
            "explicit_contact_tag": "STONE_DMG", "attack_voice": None, "hurt_voice": None, "death_voice": None,
            "actions": {}, "runtime_hooks_implemented": False}, "texture_sampling": "nearest", "source_reference": "res://docs/r4_stonemaster_source_reference.json",
            "runtime_hooks_implemented": False, "notes": notes}
    write_json(DATA, data)
    report = {"schema": 1, "stage": "R4/06 isolated asset preparation", "created_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "producer": "tools/r4/export_stonemaster.py", "producer_sha256": file_sha(Path(__file__)), "client_root": str(arguments.client),
              "pvf_tree": pvf.header, "encoding": "Big5", "identity": {"monster_id": 37, "source_name": name, "source_mob": "monster/dollmaster/stonemaster.mob",
              "source_category": section(decoded["monster/dollmaster/stonemaster.mob"], "[category]"), "direct_map": "map/hallofdoll/(1,1)n1818.map",
              "original_map_monster_records": [section(decoded["map/hallofdoll/(1,1)n1818.map"], "[monster]")[i:i + 10] for i in range(0, len(section(decoded["map/hallofdoll/(1,1)n1818.map"], "[monster]")), 10) if section(decoded["map/hallofdoll/(1,1)n1818.map"], "[monster]")[i] == 37]},
              "source_scripts": sources, "actor_image_source": image_source, "source_crops": list(crops.values()), "derived_composites": records,
              "canvas_size": list(CANVAS), "foot_anchor": list(ANCHOR), "full_RGBA_crop_union_relative_to_source_foot": logical_bounds,
              "source_action_keys": list(ACTIONS), "runtime_action_keys": list(animations),
              "action_clocks": {key: {"records": len(a["frames"]), "duration_ms": [f["duration_ms"] for f in a["frames"]], "total_ms": sum(f["duration_ms"] for f in a["frames"])} for key, a in animations.items()},
              "environment_outputs": environment, "audio": audio, "runtime_output": {"path": DATA.relative_to(ROOT).as_posix(), "sha256": file_sha(DATA)},
              "import_policy": {"PNG": PROFILE, "sampling": "Nearest in existing source actor shader/native world material", "scoped_only": True},
              "verification": {"CRC_verified_source_payloads": len(sources), "source_IMG_archives": 3, "source_crops": len(crops), "composite_records": len(records),
              "total_PNGs": len(crops) + len(records) + len(environment), "all_source_crop_RGBA_exact": True, "all_composites_reverse_crop_RGBA_exact": True,
              "all_PNG_roundtrips_exact": True, "all_full_crops_minimum8px_canvas_margin": True, "long_holds_preserved": True,
              "all_noncomment_OGG_packets_identical": True, "decoded_PCM_byte_identical": True, "Godot_native_import_or_playback_tested": False}, "notes": notes}
    write_json(REFERENCE, report)
    print(json.dumps({"source_keys": list(ACTIONS), "records": len(records), "unique_crops": len(crops), "PNG_count": report["verification"]["total_PNGs"],
                      "canvas": list(CANVAS), "anchor": list(ANCHOR), "audio_PCM_exact": True, "reference": REFERENCE.relative_to(ROOT).as_posix()}, ensure_ascii=False))


if __name__ == "__main__":
    main()
