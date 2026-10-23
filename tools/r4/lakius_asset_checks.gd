extends RefCounted
## Readback QA only. Never play a scene or mutate actors, inputs or profiles.

const DATA: String = "res://data/lakius_animations.json"
const SOURCE: String = "res://docs/r4_lakius_source_reference.json"
const REPORT: String = "res://docs/r4_01_lakius_asset_checks.json"
const DURATIONS: Dictionary = {
	"stay": [80], "move": [80, 80, 50, 80, 80, 80, 80],
	"attack1": [80, 100, 150, 80], "damage1": [null], "damage2": [null],
	"down": [80, 80, 10000, 10000, 300],
	"moveback": [80, 80, 50, 80, 80, 80, 80], "sit": [100],
	"attacklong": [50, 80, 80, 80, 80, 120, 50], "attackheart": [850, 200, 50],
}
var _images: Dictionary = {}


func collect(folder: String) -> Array[String]:
	var paths: Array[String] = []
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".png"):
			paths.append(folder.path_join(file))
	for child: String in DirAccess.get_directories_at(folder):
		paths.append_array(collect(folder.path_join(child)))
	return paths


func _sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _point(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


func _texture(manifest: Dictionary) -> Dictionary:
	var path: String = manifest.texture
	var source := Image.new()
	var source_error: Error = source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	var texture: Texture2D = load(path) as Texture2D
	var imported: Image = texture.get_image() if texture != null else null
	var decompressed: bool = true
	if imported != null and imported.is_compressed():
		decompressed = imported.decompress() == OK
	var dimensions_match: bool = false
	var exact: bool = false
	var rgba_sha: String = ""
	if source_error == OK:
		source.convert(Image.FORMAT_RGBA8)
		_images[path] = source
		rgba_sha = _sha(source.get_data())
		dimensions_match = source.get_size() == _point(manifest.size)
		if imported != null and decompressed:
			imported.convert(Image.FORMAT_RGBA8)
			exact = source.get_size() == imported.get_size() and source.get_data() == imported.get_data()
	var config := ConfigFile.new()
	var settings: bool = config.load(path + ".import") == OK
	for pair: Array in [["compress/mode", 0], ["mipmaps/generate", false], ["process/fix_alpha_border", false], ["process/premult_alpha", false], ["detect_3d/compress_to", 0]]:
		settings = settings and config.get_value("params", pair[0], null) == pair[1]
	var png_match: bool = FileAccess.get_sha256(path) == manifest.sha256_png
	var rgba_match: bool = rgba_sha == manifest.sha256_rgba
	return {"path": path, "source_loaded": source_error == OK,
		"size": [source.get_width(), source.get_height()], "imported_resource": texture != null,
		"dimensions_match_manifest": dimensions_match, "exact_rgba": exact,
		"png_sha256_matches_source_manifest": png_match, "rgba_sha256_matches_source_manifest": rgba_match,
		"rgba_sha256": rgba_sha, "lossless_settings": settings,
		"passed": source_error == OK and texture != null and dimensions_match and exact and png_match and rgba_match and settings}


func _definition(data: Dictionary, source: Dictionary) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var canvas_ok: bool = _point(data.canvas_size) == Vector2i(362, 202) and _point(data.foot_anchor) == Vector2i(134, 153)
	records.append({"name": "fixed canvas362x202 and foot134153", "passed": canvas_ok})
	var keys: Array = data.animations.keys()
	keys.sort()
	var expected: Array = DURATIONS.keys()
	expected.sort()
	records.append({"name": "ten distinct canonical action keys without hero aliases", "passed": keys == expected})
	var scripts: Dictionary = {}
	for item: Dictionary in source.scripts:
		scripts[item.path] = item
	var total: int = 0
	for action: String in DURATIONS:
		var animation: Dictionary = data.animations.get(action, {})
		var original: Dictionary = scripts.get(animation.get("source_ani", ""), {})
		var decoded: Dictionary = {}
		var references: bool = not original.is_empty()
		if references:
			var bin_path: String = "res://" + str(original.original_reference)
			var json_path: String = "res://" + str(original.decoded_reference)
			references = FileAccess.file_exists(bin_path) and FileAccess.file_exists(json_path) and FileAccess.get_sha256(bin_path) == animation.source_sha256 and original.sha256_decoded_bytes == animation.source_sha256 and original.crc_matches
			if FileAccess.file_exists(json_path):
				var artifact: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json_path))
				decoded = artifact.get("decoded", {})
		var frames: Array = animation.get("frames", [])
		var expected_duration: Array = DURATIONS[action]
		var frame_ok: bool = frames.size() == expected_duration.size() and frames.size() == int(animation.get("source_frames_count", -1)) and frames.size() == int(decoded.get("frames_count", -1))
		var clock_ok: bool = frame_ok
		var source_ok: bool = frame_ok and references and _same(animation.get("source_globals"), decoded.get("globals")) and _same(animation.get("source_resources"), decoded.get("resources")) and animation.get("source_resources", []) == ["monster/draconian/draco_lakius.img"]
		var composition_ok: bool = frame_ok
		var duration_values: Array = []
		if frame_ok:
			for index: int in frames.size():
				var frame: Dictionary = frames[index]
				var source_frame: Dictionary = decoded.frames[index]
				var duration: Variant = null
				for property: Dictionary in source_frame.properties:
					if int(property.type) == 12:
						duration = property.value
				clock_ok = clock_ok and duration == expected_duration[index] and frame.source_duration_ms == duration and int(frame.duration_ms) == (10000 if duration == null else int(duration))
				duration_values.append(frame.source_duration_ms)
				source_ok = source_ok and int(frame.img_frame) == int(source_frame.image_frame) and _same(frame.source_properties, source_frame.properties) and _same(frame.source_boxes, source_frame.boxes) and _point(frame.ani_offset) == Vector2i(int(source_frame.x), int(source_frame.y)) and FileAccess.file_exists(frame.texture) and FileAccess.file_exists(frame.source_crop)
				var crop: Image = _images.get(frame.source_crop)
				var composite: Image = _images.get(frame.texture)
				var paste: Vector2i = _point(frame.composite_paste_offset)
				var logical: Vector2i = _point(frame.ani_offset) + Vector2i(int(frame.img_metadata.x), int(frame.img_metadata.y))
				composition_ok = composition_ok and crop != null and composite != null and logical == _point(frame.logical_crop_offset) and paste == _point(data.foot_anchor) + logical
				if crop != null and composite != null:
					var rebuilt: Image = Image.create(362, 202, false, Image.FORMAT_RGBA8)
					rebuilt.fill(Color(0, 0, 0, 0))
					rebuilt.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), paste)
					composition_ok = composition_ok and paste.x >= 0 and paste.y >= 0 and paste.x + crop.get_width() <= 362 and paste.y + crop.get_height() <= 202 and rebuilt.get_data() == composite.get_data() and _sha(crop.get_data()) == frame.source_crop_rgba_sha256
		total += frames.size()
		records.append({"name": "canonical source definition " + action, "frames": frames.size(),
			"source_duration_ms": duration_values, "source_references_and_original_bytes": references,
			"source_boxes_properties_indices_offsets": source_ok, "source_clock": clock_ok,
			"exact_transparent_canvas_composition": composition_ok,
			"passed": frame_ok and source_ok and clock_ok and composition_ok})
	records.append({"name": "37 master records, 32 raw crops and69 textures", "passed": total == 37 and int(source.counts.composite_frames) == 37 and int(source.counts.unique_source_crops) == 32 and int(source.counts.textures) == 69})
	records.append({"name": "runtime data matches exporter source manifest SHA", "passed": FileAccess.get_sha256(DATA) == source.runtime_data_sha256})
	return records


func _world_reuse() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/r4_depths_source_reference.json"))
	var prior: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/r2_01_asset_checks.json"))
	var verified: Dictionary = {}
	for item: Dictionary in prior.textures:
		verified[item.path] = item.exact_rgba
	for item: Dictionary in world.assets:
		var path: String = item.texture
		var hash_ok: bool = FileAccess.get_sha256(path) == item.sha256_png
		var native_prior: bool = verified.get(path, false) == true
		records.append({"path": path, "png_sha256_unchanged": hash_ok,
			"prior_native_import_exact_rgba": native_prior, "prior_report": "docs/r2_01_asset_checks.json",
			"passed": hash_ok and native_prior})
	return records


func run(_main: Node, candidate: String = "R4/01") -> Dictionary:
	_images.clear()
	var started: int = Time.get_ticks_usec()
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var master_frames: int = 0
	for animation: Dictionary in data.animations.values():
		master_frames += animation.get("frames", []).size()
	var records: Array[Dictionary] = []
	var expected_paths: Array[String] = []
	var pixels: int = 0
	for manifest: Dictionary in source.raw_crops + source.composites:
		expected_paths.append(manifest.texture)
		var record: Dictionary = _texture(manifest)
		pixels += int(record.size[0]) * int(record.size[1])
		records.append(record)
	var actual_paths: Array[String] = collect("res://assets/r4/lakius")
	expected_paths.sort()
	actual_paths.sort()
	var definitions: Array[Dictionary] = _definition(data, source)
	definitions.append({"name": "all and only69 Lakius PNG paths declared", "passed": expected_paths.size() == 69 and actual_paths == expected_paths})
	var reuse: Array[Dictionary] = _world_reuse()
	definitions.append({"name": "ten existing R2 world PNGs reused", "passed": reuse.size() == 10})
	var failed: Array[Dictionary] = []
	for record: Dictionary in records + definitions + reuse:
		if not record.passed:
			failed.append(record)
	var report: Dictionary = {"candidate": candidate, "textures": records.size(), "expected_textures": 69,
		"native_exact_rgba_pixels": pixels, "animations": data.animations.size(), "master_frames": master_frames,
		"reused_world_textures": reuse.size(), "all_passed": failed.is_empty(), "failed": failed,
		"records": records, "definition_checks": definitions, "world_reuse": reuse,
		"seconds": float(Time.get_ticks_usec() - started) / 1000000.0,
		"qa_source_sha256": get_script().source_code.sha256_text(), "data_sha256": FileAccess.get_sha256(DATA),
		"source_manifest_sha256": FileAccess.get_sha256(SOURCE),
		"note": "Actual imported Texture2D readback includes transparent RGB for all69 Lakius PNGs. Original timing/boxes/offsets and exact37 canvas compositions are compared to retained source ANI artifacts. Ten R2 PNGs retain hashes and prior native readback evidence. No gameplay, profile or input changes; not a performance benchmark."}
	var file: FileAccess = FileAccess.open(REPORT, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	_images.clear()
	return {"textures": records.size(), "pixels": pixels, "animations": data.animations.size(),
		"master_frames": master_frames, "world_reused": reuse.size(), "failed": failed.size(), "all_passed": report.all_passed}
