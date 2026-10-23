"""Prepare isolated source visuals for an explicitly adapted StoneMaster ranged move.

The six accepted close-punch animation objects remain byte-semantically intact.
Only Cast, gem pictures and a directly referenced contact sound are prepared.
Original projectile creation, timing, flight, lifetime and collision dispatch
remain unresolved. No runtime script/scene, Godot, client or network is run.
"""
from __future__ import annotations

import argparse
import copy
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

SOURCE = ROOT / "source_art/r4/stonemaster_ranged"
ASSETS = ROOT / "assets/r4/stonemaster_ranged"
DATA = ROOT / "data/stonemaster_ranged_r1.json"
GEM = ROOT / "data/stonemaster_gem.json"
REFERENCE = ROOT / "docs/r4_stonemaster_ranged_source_reference.json"
PARENT = ROOT / "data/stonemaster_r1.json"
PARENT_SHA256 = "57f64ed37b8930ee23f985927ef641bd24a51c6a6aa5e1ba69a18e35cafb98f8"
PACK = "sprite_monster_dollmaster.NPK"
CAST_ANI = "monster/dollmaster/stoneanimation/cast.ani"
GEM_ANI = "equipment/monster/dollmaster/animation/gem.ani"
GEM_ATK = "monster/dollmaster/attackinfo/stoneattackgem.atk"
MOB = "monster/dollmaster/stonemaster.mob"
EQU = "equipment/monster/dollmaster/dollmaster.equ"
CANVAS = (88, 111)
ANCHOR = (49, 89)
SIX_KEYS = ("stay", "move", "attack", "damage1", "damage2", "down")


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def file_sha(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for value in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(value)
    return result.hexdigest()


def object_sha(value: object) -> str:
    return sha(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode())


def write(path: Path, value: bytes) -> None:
    assert path.is_relative_to(SOURCE) or path.is_relative_to(ASSETS) or path in (DATA, GEM, REFERENCE), path
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
    text = sidecar.read_text() if sidecar.exists() else ('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
            '[deps]\n\nsource_file="res://' + path.relative_to(ROOT).as_posix() + '"\n\n[params]\n')
    for key, value in PROFILE.items():
        pattern = r"^" + re.escape(key) + r"=.*$"
        text = re.sub(pattern, key + "=" + value, text, flags=re.MULTILINE) if re.search(pattern, text, re.MULTILINE) else text.rstrip() + "\n" + key + "=" + value + "\n"
    write(sidecar, text.encode())
    return {"texture": "res://" + path.relative_to(ROOT).as_posix(), "size": list(image.size),
            "sha256_png": file_sha(path), "sha256_rgba": sha(image.tobytes()), "import_sidecar": sidecar.relative_to(ROOT).as_posix()}


def source_record(pvf: PVF, path: str, animation: bool = False) -> tuple:
    raw, crc = pvf.read(path, True)
    assert crc["expected"] == crc["actual_seed_file_number"], path
    decoded = binary_ani(raw) if animation else pvf.tokens(path, "big5")
    raw_path, json_path = SOURCE / "pvf" / (path + ".bin"), SOURCE / "pvf" / (path + ".json")
    write(raw_path, raw)
    write_json(json_path, {"path": path, "crc": crc, "decoded": decoded})
    assert raw_path.read_bytes() == raw
    return decoded, {"pvf_path": path, "bytes": len(raw), "sha256_decoded": sha(raw), "crc": crc,
                     "crc_matches": True, "raw_reference": raw_path.relative_to(ROOT).as_posix(),
                     "decoded_reference": json_path.relative_to(ROOT).as_posix()}


def album(client: Path, image_path: str) -> tuple:
    assert image_path in ("sprite/monster/dollmaster/stonemaster.img", "sprite/monster/dollmaster/dollmastergem.img")
    package = client / "ImagePacks2" / PACK
    entry = next(e for e in npk_entries(package) if e["path"] == image_path)
    with package.open("rb") as stream:
        stream.seek(entry["offset"])
        raw = stream.read(entry["bytes"])
    target = SOURCE / "img" / PACK / (image_path + ".bin")
    write(target, raw)
    assert target.read_bytes() == raw
    table, _ = img_frames(raw)
    return raw, table, {"npk": PACK, "sha256_npk": file_sha(package), "img": image_path, "entry": entry,
                        "sha256_img_payload": sha(raw), "declared_IMG_frames": len(table), "raw_reference": target.relative_to(ROOT).as_posix()}


def section(tokens: list, label: str) -> list:
    output, active = [], False
    for token in tokens:
        if token["type"] == 5:
            if active:
                break
            active = token["text"].lower() == label.lower()
        elif active:
            output.append(token.get("text", token.get("value")))
    return output


def contact_audio(client: Path, atk: list, provenance: dict) -> dict:
    assert section(atk, "[hit wav]") == ["JEWEL_HIT"] and any(t.get("text") == "[physic]" for t in atk)
    xml_raw = (client / "audio.xml").read_bytes()
    attributes = dict(next(n for n in ET.fromstring(xml_raw) if n.attrib.get("ID") == "JEWEL_HIT").attrib)
    entry_path = attributes["FILE"].replace("\\", "/").lower()
    package = client / "SoundPacks/sounds_effect.npk"
    entry = next(e for e in npk_entries(package, False) if e["path"] == entry_path)
    assert entry["bytes"] <= 512 * 1024
    with package.open("rb") as stream:
        stream.seek(entry["offset"])
        original_bytes = stream.read(entry["bytes"])
    assert original_bytes.startswith(b"OggS")
    original, runtime = SOURCE / "audio/jewel_hit.ogg", ASSETS / "audio/jewel_hit.ogg"
    write(original, original_bytes)
    source_packets = packets(original_bytes)
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
        safe, fix = normalize_comments(original_bytes)
    else:
        safe, fix = original_bytes, {"comments_fixed": 0, "all_noncomment_packets_identical": True}
    write(runtime, safe)
    runtime_packets = packets(safe)
    assert len(source_packets) == len(runtime_packets)
    assert all(left == right for i, (left, right) in enumerate(zip(source_packets, runtime_packets)) if i != 1)
    assert page_audit(original_bytes) == page_audit(safe)
    ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
    assert ffmpeg and ffprobe
    pcm_a, before = decoded_audio(original, ffmpeg, ffprobe)
    pcm_b, after = decoded_audio(runtime, ffmpeg, ffprobe)
    assert pcm_a == pcm_b
    sidecar = runtime.with_suffix(".ogg.import")
    if not sidecar.exists():
        write(sidecar, ('[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n\n[deps]\n\nsource_file="res://'
                        + runtime.relative_to(ROOT).as_posix() + '"\n\n[params]\n\nloop=false\nloop_offset=0.0\nbpm=0.0\nbeat_count=0\nbar_beats=4\n').encode())
    result = {"tag": "JEWEL_HIT", "path": "res://" + runtime.relative_to(ROOT).as_posix(), "canonical_npk": "sounds_effect.npk",
              "sha256_npk": file_sha(package), "entry": entry, "audio_xml_sha256": sha(xml_raw), "xml_attributes": attributes,
              "retained_original": original.relative_to(ROOT).as_posix(), "sha256_source_ogg": sha(original_bytes), "sha256_runtime_ogg": sha(safe),
              "metadata_fix": fix, "source_PCM": before, "runtime_PCM": after, "PCM_byte_identical": True,
              "all_noncomment_packets_identical": True, "ogg_timing_headers_identical": True,
              "source_binding": {"pvf_path": GEM_ATK, "sha256_decoded": provenance["sha256_decoded"], "field": "[hit wav]", "tag": "JEWEL_HIT"},
              "runtime_hooks_implemented": False, "limit": "Direct physical contact-tag reference does not prove projectile spawn or sound scheduling."}
    write_json(SOURCE / "audio/source_binding.json", result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", type=Path, default=Path("/Users/mac/Downloads/天堂95起源单机客户端"))
    arguments = parser.parse_args()
    parent_bytes = PARENT.read_bytes()
    assert sha(parent_bytes) == PARENT_SHA256, "Use the accepted R4/06 six-action parent, never silently select a different variant"
    parent = json.loads(parent_bytes)
    assert tuple(parent["animations"]) == SIX_KEYS and parent["canvas_size"] == list(CANVAS) and parent["foot_anchor"] == list(ANCHOR)
    old_animations = copy.deepcopy(parent["animations"])
    assert sum(len(a["frames"]) for a in old_animations.values()) == 32
    protected = [PARENT, ROOT / "docs/r4_stonemaster_source_reference.json"]
    for pattern in ("assets/r4/stonemaster/**/*", "assets/r4/doll_gallery/**/*", "source_art/r4/stonemaster/**/*"):
        protected.extend(p for p in ROOT.glob(pattern) if p.is_file())
    original_hashes = {p.relative_to(ROOT).as_posix(): file_sha(p) for p in protected}
    pvf = PVF(arguments.client / "Script.pvf")
    assert pvf.header["tree_crc_expected"] == pvf.header["tree_crc_actual"] and not pvf.header["parse_error"] and not pvf.header["payload_bounds_errors"]
    sources, values = [], {}
    for path in (CAST_ANI, GEM_ANI, GEM_ATK, MOB, EQU):
        value, proof = source_record(pvf, path, path.endswith(".ani"))
        values[path] = value
        sources.append(proof)
    cast, gem = values[CAST_ANI], values[GEM_ANI]
    assert cast["frames_count"] == 11 and gem["frames_count"] == 13
    body_raw, body_table, body_source = album(arguments.client, "sprite/monster/dollmaster/stonemaster.img")
    new_crops = []
    for index in (4, 5):
        image, metadata = decode_frame(body_raw, index)
        new_crops.append({**texture(image, ASSETS / "src" / f"{index:03d}.png"), "img_frame": index,
                          "img_metadata": metadata, "source": body_source, "operation": "Exact complete source RGBA crop"})
    inherited_crops = {f["img_frame"]: f["source_crop"] for a in old_animations.values() for f in a["frames"]}
    crop_paths = {c["img_frame"]: c["texture"] for c in new_crops}
    crop_paths.update(inherited_crops)
    cast_action = {"source_action_key": "cast", "source_ani": CAST_ANI, "source_globals": cast["globals"], "source_resources": cast["resources"],
                   "source_sha256": next(p["sha256_decoded"] for p in sources if p["pvf_path"] == CAST_ANI), "frames": []}
    derived, clock = [], 0
    for index, source_frame in enumerate(cast["frames"]):
        image, metadata = decode_frame(body_raw, source_frame["image_frame"])
        offset = [source_frame["x"] + metadata["x"], source_frame["y"] + metadata["y"]]
        paste = [ANCHOR[0] + offset[0], ANCHOR[1] + offset[1]]
        assert min(paste) >= 8 and paste[0] + image.width <= CANVAS[0] - 8 and paste[1] + image.height <= CANVAS[1] - 8
        composed = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        composed.paste(image, tuple(paste))
        assert composed.crop((paste[0], paste[1], paste[0] + image.width, paste[1] + image.height)).tobytes() == image.tobytes()
        duration = next(p["value"] for p in source_frame["properties"] if p["type"] == 12)
        frame = {**texture(composed, ASSETS / "frames/cast" / f"{index:03d}.png"), "duration_ms": duration, "source_duration_ms": duration,
                 "source_start_ms": clock, "img_frame": source_frame["image_frame"], "ani_offset": [source_frame["x"], source_frame["y"]],
                 "img_metadata": metadata, "logical_crop_offset": offset, "composite_paste_offset": paste,
                 "source_crop": crop_paths[source_frame["image_frame"]], "source_crop_rgba_sha256": sha(image.tobytes()),
                 "source_properties": source_frame["properties"], "source_boxes": source_frame["boxes"], "derived_artifact": True,
                 "operation": "Unmasked source RGBA copy on unchanged88x111 canvas/foot49,89; all source crop channels retained"}
        cast_action["frames"].append(frame)
        derived.append({"action": "cast", "frame": index, **frame})
        clock += duration
    assert clock == 1000
    gem_raw, gem_table, gem_source = album(arguments.client, "sprite/monster/dollmaster/dollmastergem.img")
    gem_frames, clock = [], 0
    for index, source_frame in enumerate(gem["frames"]):
        image, metadata = decode_frame(gem_raw, source_frame["image_frame"])
        assert image.size == (15, 16)
        duration = next(p["value"] for p in source_frame["properties"] if p["type"] == 12)
        gem_frames.append({**texture(image, ASSETS / "gem" / f"{index:03d}.png"), "start_ms": clock, "duration_ms": duration,
                           "source_duration_ms": duration, "img_frame": source_frame["image_frame"], "ani_offset": [source_frame["x"], source_frame["y"]],
                           "img_metadata": metadata, "logical_crop_offset": [source_frame["x"] + metadata["x"], source_frame["y"] + metadata["y"]],
                           "source_properties": source_frame["properties"], "source_boxes": source_frame["boxes"], "derived_artifact": False,
                           "operation": "Exact15x16 source RGBA crop; source equipment offsets retained separately, no flight/path transformation"})
        clock += duration
    assert clock == 615
    boundary = {"original_independent_projectile_dispatch_proven": False, "MOB_equipment_attachment_proven": False,
                "direct_MOB_attack_info": section(values[MOB], "[attack info]"), "direct_EQU_attack_motions": section(values[EQU], "[attack motion]"),
                "direct_physical_ATK": GEM_ATK, "direct_Gem_ANI": GEM_ANI, "direct_Gem_IMG": gem_source["img"],
                "limit": "The second attack-info and equipment-animation slots are parallel references, not a recovered ID37 equipment attachment or projectile-create instruction. Canonical directories contain no ACT/AI/NUT. Cast ANI has no projectile-create event.",
                "original_release_time_or_flight_speed_lifetime_collision_proven": False,
                "future_prototype_policy": "Any emit after1000ms, independent flight speed/lifetime/collision/hit-once/guard direction is a new explicit prototype adaptation, not restored original behavior.",
                "excluded": "SunkenRock passiveobject is magical; CastAct1/2/Stoner effects are not exported or substituted as physical-gem dispatch."}
    write_json(SOURCE / "dispatch_boundary.json", boundary)
    audio = contact_audio(arguments.client, values[GEM_ATK], next(p for p in sources if p["pvf_path"] == GEM_ATK))
    notes = ["Preparation only for an explicitly source-picture-based adapted ranged move; original independent projectile dispatch is unresolved.",
             "The six accepted R4/06 animation objects and their existing picture paths are copied exactly. Cast is an additional original11-record1000ms action, with no edits to those32 records.",
             "Only2 new Cast source crops (IMG4/5),11 fixed-canvas Cast composites and13 original15x16 Gem crops are exported. No CastAct1/2/Stoner effects.",
             "Gem retains13 original equipment ANI records/615ms, every property/box/offset, and exact RGBA. The source equipment attachment clock and original release event are not recovered.",
             "JEWEL_HIT has a direct StoneAttackGem ATK reference plus exact audio.xml/canonical NPK resolution. No attack/hurt/death voice or schedule is invented.",
             "Runtime scripts, scenes, manifests, parent assets/data/source reference and the original six-action JSON are not modified. No Godot/client execution or paid service."]
    animations = copy.deepcopy(old_animations)
    animations["cast"] = cast_action
    audio_data = copy.deepcopy(parent["audio"])
    audio_data["sounds"]["JEWEL_HIT"] = {"path": audio["path"]}
    audio_data["explicit_gem_contact_tag"] = "JEWEL_HIT"
    audio_data["runtime_hooks_implemented"] = False
    parent_link = {"path": "res://data/stonemaster_r1.json", "sha256": PARENT_SHA256, "inherited_action_keys": list(SIX_KEYS),
                   "inherited_action_objects_SHA256": {k: object_sha(old_animations[k]) for k in SIX_KEYS}, "exact_inherited_records": 32}
    data = {"schema": 1, "monster_id": 37, "source_name": parent["source_name"], "canvas_size": list(CANVAS), "foot_anchor": list(ANCHOR),
            "source_action_keys": list(SIX_KEYS) + ["cast"], "animations": animations, "audio": audio_data, "texture_sampling": "nearest",
            "parent_manifest": parent_link, "dispatch_boundary": boundary, "source_reference": "res://docs/r4_stonemaster_ranged_source_reference.json",
            "runtime_hooks_implemented": False, "notes": notes}
    gem_data = {"schema": 1, "source_ani": GEM_ANI, "source_globals": gem["globals"], "source_resources": gem["resources"],
                "source_role": "Equipment Gem animation, not a proved independent projectile object", "duration_ms": 615, "frames": gem_frames,
                "source": gem_source, "audio": {"sounds": {"JEWEL_HIT": {"path": audio["path"]}}, "actions": {}, "runtime_hooks_implemented": False},
                "dispatch_boundary": boundary, "source_reference": "res://docs/r4_stonemaster_ranged_source_reference.json", "runtime_hooks_implemented": False, "notes": notes}
    assert all(data["animations"][k] == parent["animations"][k] for k in SIX_KEYS)
    write_json(DATA, data)
    write_json(GEM, gem_data)
    assert all(file_sha(ROOT / p) == expected for p, expected in original_hashes.items())
    report = {"schema": 1, "stage": "R4/07 isolated ranged source preparation", "created_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "producer": "tools/r4/export_stonemaster_ranged.py", "producer_sha256": file_sha(Path(__file__)), "client_root": str(arguments.client), "pvf_tree": pvf.header,
              "parent_manifest": parent_link, "source_scripts": sources, "source_albums": [body_source, gem_source], "source_crops": new_crops,
              "derived_composites": derived, "gem_frames": gem_frames, "audio": audio, "dispatch_boundary": boundary,
              "outputs": {"caster_manifest": {"path": DATA.relative_to(ROOT).as_posix(), "sha256": file_sha(DATA)}, "gem_manifest": {"path": GEM.relative_to(ROOT).as_posix(), "sha256": file_sha(GEM)}},
              "import_policy": {"PNG": PROFILE, "sampling": "nearest in the source actor shader / future explicit projectile material", "scoped_only": True},
              "verification": {"PVF_CRC_verified": 5, "new_Cast_source_crops": 2, "Cast_composites": 11, "Gem_original_crops": 13, "total_new_PNGs": 26,
                               "original_six_animation_objects_exact": True, "original32records_unchanged": True, "new_Cast_clock_ms": 1000, "Gem_clock_ms": 615,
                               "all_PNG_roundtrips_RGBA_exact": True, "all_Cast_reverse_crops_RGBA_exact": True, "Cast_complete_RGBA_crop_minimum8px_margin": True,
                               "all_noncomment_OGG_packets_and_timing_identical": True, "decoded_PCM_byte_identical": True, "all_protected_R4_06_files_unchanged": True,
                               "Godot_native_import_or_playback_tested": False}, "protected_R4_06_files_SHA256": original_hashes, "notes": notes}
    write_json(REFERENCE, report)
    print(json.dumps({"inherited_records": 32, "Cast_records": 11, "Gem_records": 13, "new_PNGs": 26, "source_CRC": 5,
                      "parent_unchanged": True, "ranged_dispatch_original_proven": False, "audio_PCM_exact": True, "reference": REFERENCE.relative_to(ROOT).as_posix()}))


if __name__ == "__main__":
    main()
