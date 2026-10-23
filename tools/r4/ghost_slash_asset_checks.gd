extends RefCounted
## Read imported textures and immutable source records. No scene, actor pose,
## input, profile, effect toggle or gameplay timer is modified by this check.

const SOURCE: String = "res://docs/r4_ghost_slash_source_reference.json"
const EFFECTS: String = "res://data/ghost_slash_effects.json"
const OUTPUT: String = "res://docs/r4_02_ghost_asset_checks.json"
const MANIFESTS: Array = [
	["practice", "r0", "data/swordman_ghost_practice_r0.json", "data/swordman_r0.json"],
	["practice", "r1", "data/swordman_ghost_practice_r1.json", "data/swordman_r1.json"],
	["great", "r0", "data/swordman_ghost_great_r0.json", "data/swordman_mswd0007_r0.json"],
	["great", "r1", "data/swordman_ghost_great_r1.json", "data/swordman_mswd0007_r1.json"],
]
var _checks: Array[Dictionary] = []


func _check(name: String, passed: bool, detail: Variant = null) -> void:
	_checks.append({"name": name, "passed": passed, "detail": detail})


func _same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _point(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


func _sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func collect(folder: String) -> Array[String]:
	var result: Array[String] = []
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".png"):
			result.append(folder.path_join(file))
	for child: String in DirAccess.get_directories_at(folder):
		result.append_array(collect(folder.path_join(child)))
	return result


func _texture(item: Dictionary) -> Dictionary:
	var path: String = item.texture
	var image := Image.new()
	var loaded: bool = image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK
	var texture: Texture2D = load(path) as Texture2D
	var imported: Image = texture.get_image() if texture != null else null
	var usable: bool = imported != null
	if imported != null and imported.is_compressed():
		usable = imported.decompress() == OK
	var exact: bool = false
	var rgba_sha: String = ""
	if loaded:
		image.convert(Image.FORMAT_RGBA8)
		rgba_sha = _sha(image.get_data())
		if usable:
			imported.convert(Image.FORMAT_RGBA8)
			exact = image.get_size() == imported.get_size() and image.get_data() == imported.get_data()
	var config := ConfigFile.new()
	var lossless: bool = config.load(path + ".import") == OK
	for pair: Array in [["compress/mode", 0], ["mipmaps/generate", false], ["process/fix_alpha_border", false], ["process/premult_alpha", false], ["detect_3d/compress_to", 0]]:
		lossless = lossless and config.get_value("params", pair[0], null) == pair[1]
	var png_sha: bool = FileAccess.get_sha256(path) == item.sha256_png
	var rgba_match: bool = rgba_sha == item.sha256_rgba
	var dimensions: bool = image.get_size() == _point(item.size)
	return {"path": path, "size": [image.get_width(), image.get_height()], "source_loaded": loaded,
		"native_exact_rgba": exact, "png_sha_matches_source": png_sha, "rgba_sha_matches_source": rgba_match,
		"rgba_sha256": rgba_sha, "lossless_settings": lossless,
		"passed": loaded and usable and exact and png_sha and rgba_match and dimensions and lossless}


func _definitions(source: Dictionary) -> void:
	var master: Dictionary = {}
	for script: Dictionary in source.source_scripts:
		if script.path == "character/swordman/animation/hardattack.ani":
			master = script.decoded
	var source_ms: Array = []
	for frame: Dictionary in master.frames:
		for property: Dictionary in frame.properties:
			if int(property.type) == 12:
				source_ms.append(property.value)
	_check("source master retains18 records and950ms", source_ms.size() == 18 and source_ms.reduce(func(total, value): return total + value, 0.0) == 950.0)
	for descriptor: Array in MANIFESTS:
		var path: String = descriptor[2]
		var data: Dictionary = _json("res://" + path)
		var baseline: Dictionary = _json("res://" + str(descriptor[3]))
		var unchanged: bool = baseline.animations.size() == 14
		for action: String in baseline.animations:
			unchanged = unchanged and data.animations.has(action) and _same(data.animations[action], baseline.animations[action])
		var count: int = 0
		var resources: bool = true
		for animation: Dictionary in data.animations.values():
			count += animation.frames.size()
			for frame: Dictionary in animation.frames:
				var layers: Array = frame.layers if descriptor[1] == "r0" else [frame]
				for layer: Dictionary in layers:
					resources = resources and ResourceLoader.exists(layer.texture, "Texture2D")
		_check("15 actions110 records and unchanged old14: " + path, unchanged and data.animations.size() == 15 and count == 110 and resources and FileAccess.get_sha256("res://" + path) == source.actor_outputs[path].sha256)
		var frames: Array = data.animations.hardattack.frames
		var timing: bool = frames.size() == 18
		var evidence: bool = timing
		if timing:
			for index: int in frames.size():
				timing = timing and frames[index].duration_ms == source_ms[index]
				evidence = evidence and int(frames[index].img_frame) == int(master.frames[index].image_frame) and _same(frames[index].source_properties, master.frames[index].properties) and _same(frames[index].source_boxes, master.frames[index].boxes)
		_check("new action preserves original950ms indices properties boxes: " + path, timing and evidence)
		if descriptor[1] == "r1":
			_check("fixed320x224 foot133167: " + path, _point(data.canvas_size) == Vector2i(320, 224) and _point(data.foot_anchor) == Vector2i(133, 167))
	# Derived records must correspond exactly to the two sets of nine raw layers.
	var compositions: bool = source.derived_composites.size() == 36
	for item: Dictionary in source.derived_composites:
		var raw: Dictionary = _json("res://data/swordman_ghost_" + str(item.appearance) + "_r0.json")
		var rendered: Dictionary = _json("res://data/swordman_ghost_" + str(item.appearance) + "_r1.json")
		var pose: Dictionary = raw.animations.hardattack.frames[int(item.frame)]
		var texture_paths: Array = []
		var offsets: Array = []
		for layer: Dictionary in pose.layers:
			texture_paths.append(layer.texture)
			offsets.append(layer.offset)
		compositions = compositions and pose.layers.size() == 9 and _point(item.size) == Vector2i(320, 224) and _same(texture_paths, item.layer_textures) and _same(offsets, item.layer_offsets) and rendered.animations.hardattack.frames[int(item.frame)].texture == item.texture
	_check("36 composite records reference exact nine source layers and offsets", compositions)
	var old_jsons: bool = source.existing_input_manifests_unchanged.size() == 4
	for path: String in source.existing_input_manifests_unchanged:
		old_jsons = old_jsons and FileAccess.get_sha256("res://" + path) == source.existing_input_manifests_unchanged[path]
	var old_pngs: bool = true
	for path: String in source.existing_pngs_retained_by_path_and_sha256:
		old_pngs = old_pngs and FileAccess.get_sha256("res://" + path) == source.existing_pngs_retained_by_path_and_sha256[path]
	_check("four legacy manifests and all1086 retained PNG bytes untouched", old_jsons and old_pngs and source.existing_pngs_retained_by_path_and_sha256.size() == 1086)
	var original_bytes: bool = source.source_scripts.size() == 10 and source.source_albums.size() == 13
	for script: Dictionary in source.source_scripts:
		original_bytes = original_bytes and script.crc_matches and FileAccess.get_sha256("res://" + str(script.raw_reference)) == script.sha256_decoded_bytes
	for album: Dictionary in source.source_albums:
		original_bytes = original_bytes and FileAccess.get_sha256("res://" + str(album.raw_reference)) == album.sha256_img_payload
	_check("retained10 PVF and13 canonical IMG payload source SHA", original_bytes)


func _effects(source: Dictionary) -> void:
	var effects: Dictionary = _json(EFFECTS)
	var tracks: Array = effects.actions.hardattack
	var track_ok: bool = tracks.size() == 2 and effects.actions.size() == 1
	var scripts: Dictionary = {}
	for script: Dictionary in source.source_scripts:
		scripts[script.path] = script
	var crops: Dictionary = {}
	for crop: Dictionary in source.source_crops:
		crops[crop.texture] = crop
	for index: int in tracks.size():
		var track: Dictionary = tracks[index]
		var frames: Array = track.frames
		var original: Dictionary = scripts.get(track.source_ani, {}).get("decoded", {})
		var source_frames: Array = original.get("frames", [])
		var visible: int = 0
		var sequence: bool = frames.size() == 8 and source_frames.size() == 8 and int(track.duration_ms) == 550 and track.name == "hardattack" + str(index + 1) and track.blend == ("normal" if index == 0 else "add") and _same(track.source_globals, original.get("globals"))
		var cursor: int = 0
		for frame_index: int in frames.size():
			var frame: Dictionary = frames[frame_index]
			sequence = sequence and int(frame.start_ms) == cursor
			cursor += int(frame.duration_ms)
			if source_frames.size() == frames.size():
				var original_frame: Dictionary = source_frames[frame_index]
				var source_duration: int = -1
				var additive: bool = false
				for property: Dictionary in original_frame.properties:
					if int(property.type) == 12:
						source_duration = int(property.value)
					if int(property.type) == 11 and property.value.get("effect") == 2:
						additive = true
				sequence = sequence and source_duration == int(frame.duration_ms) and _same(frame.source_properties, original_frame.properties) and track.blend == ("add" if additive else "normal")
				var offset: Vector2i = Vector2i(int(original_frame.x), int(original_frame.y))
				if original_frame.resource == null:
					sequence = sequence and frame.texture == null and _point(frame.offset) == offset
				else:
					var crop: Dictionary = crops.get(frame.texture, {})
					sequence = sequence and not crop.is_empty()
					if not crop.is_empty():
						offset += Vector2i(int(crop.img_metadata.x), int(crop.img_metadata.y))
						sequence = sequence and crop.source.img == "sprite/" + str(original_frame.resource) and int(crop.img_frame) == int(original_frame.image_frame) and int(frame.image_frame) == int(original_frame.image_frame) and _point(frame.offset) == offset
			if frame.texture != null:
				visible += 1
				sequence = sequence and int(frame.start_ms) >= 150 and int(frame.start_ms) <= 400 and int(frame.duration_ms) == 50 and ResourceLoader.exists(frame.texture, "Texture2D")
		track_ok = track_ok and sequence and visible == 6 and cursor == 550 and frames[0].texture == null and int(frames[0].duration_ms) == 150 and frames[7].texture == null and int(frames[7].duration_ms) == 100
	_check("normal/add tracks retain source ANI properties offsets and150ms/550ms clocks", track_ok)
	# Integration may change only delivery metadata such as hooks/notes. The
	# historical export SHA remains evidence; actual tracks are checked above
	# against immutable ANI and IMG records instead of the whole JSON byte hash.
	_check("pose-zero attachment and unbound audio retained", effects.audio_actions.is_empty() and effects.attachment == "prototype_pose_time_zero")
	var helper: RefCounted = load("res://scripts/source_actor_effects.gd").new()
	var combined: Dictionary = helper._load_actions()
	var baseline: Dictionary = _json("res://data/swordman_effects.json").actions
	var merge_ok: bool = combined.size() == baseline.size() + 1 and _same(combined.hardattack, tracks)
	for action: String in baseline:
		merge_ok = merge_ok and _same(combined[action], baseline[action])
	_check("helper merges only hardattack and keeps old HopSmash objects", merge_ok)
	helper.spatial = false
	var normal2: CanvasItemMaterial = helper._material_for(0, "normal") as CanvasItemMaterial
	var add2: CanvasItemMaterial = helper._material_for(1, "add") as CanvasItemMaterial
	_check("2D track materials use MIX and ADD separately", normal2.blend_mode == CanvasItemMaterial.BLEND_MODE_MIX and add2.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD and normal2 != add2)
	helper.spatial = true
	var normal3: ShaderMaterial = helper._material_for(0, "normal") as ShaderMaterial
	var add3: ShaderMaterial = helper._material_for(1, "add") as ShaderMaterial
	var defaults: bool = true
	for index: int in baseline.hopsmash.size():
		var blend: String = str(baseline.hopsmash[index].get("blend", "add"))
		var material: ShaderMaterial = helper._material_for(index, blend) as ShaderMaterial
		defaults = defaults and blend == "add" and material.shader.resource_path == "res://shaders/source_effect.gdshader"
	_check("3D separate blend_mix/add shaders retain nearest alpha and old default", normal3.shader.resource_path == "res://shaders/source_effect_normal.gdshader" and add3.shader.resource_path == "res://shaders/source_effect.gdshader" and normal3.shader.code.contains("blend_mix") and add3.shader.code.contains("blend_add") and normal3.shader.code.contains("filter_nearest") and normal3.shader.code.contains("ALPHA = color.a") and normal3.render_priority == 1 and add3.render_priority == 2 and defaults)


func run(_main: Node, candidate: String = "R4/02") -> Dictionary:
	_checks.clear()
	var started: int = Time.get_ticks_usec()
	var source: Dictionary = _json(SOURCE)
	var records: Array[Dictionary] = []
	var expected_paths: Array[String] = []
	var pixels: int = 0
	for item: Dictionary in source.source_crops + source.derived_composites:
		var record: Dictionary = _texture(item)
		records.append(record)
		expected_paths.append(item.texture)
		pixels += int(record.size[0]) * int(record.size[1])
	var actual_paths: Array[String] = collect("res://assets/r4/ghost_slash")
	actual_paths.sort()
	expected_paths.sort()
	_check("all and only246 new PNG paths", records.size() == 246 and actual_paths == expected_paths)
	_definitions(source)
	_effects(source)
	var failed: Array[Dictionary] = []
	for record: Dictionary in records + _checks:
		if not record.passed:
			failed.append(record)
	var report: Dictionary = {"candidate": candidate, "textures": records.size(), "native_exact_rgba_pixels": pixels,
		"all_passed": failed.is_empty(), "failed": failed, "records": records, "checks": _checks,
		"source_manifest_sha256": FileAccess.get_sha256(SOURCE),
		"export_effect_output_sha256": source.effect_output.sha256,
		"current_effect_data_sha256": FileAccess.get_sha256(EFFECTS),
		"qa_source_sha256": get_script().source_code.sha256_text(),
		"effect_helper_sha256": FileAccess.get_sha256("res://scripts/source_actor_effects.gd"),
		"normal_shader_sha256": FileAccess.get_sha256("res://shaders/source_effect_normal.gdshader"),
		"unchanged_add_shader_sha256": FileAccess.get_sha256("res://shaders/source_effect.gdshader"),
		"seconds": float(Time.get_ticks_usec() - started) / 1000000.0,
		"note": "Actual imported Texture2D RGBA readback includes transparent RGB. Four15-action/110-frame manifests, old14 objects,950ms master,36 fixed canvases, source hashes, and normal/add material construction are checked without playing or mutating a scene. Nine-layer PNG composition is independently verified by the source exporter; blend rendering/actual skill timing belongs to live QA."}
	var file: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	return {"textures": records.size(), "pixels": pixels, "checks": _checks.size(), "failed": failed.size(), "all_passed": report.all_passed}
