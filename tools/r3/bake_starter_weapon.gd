extends RefCounted
## Run only after importing the isolated variant textures. Creates its own
## transparent2D viewport; never modifies the game actor or R1 experiments.

const SOURCE_ROOT: String = "res://source_art/r3/equipment_27304"
const ASSET_ROOT: String = "res://assets/r3/equipment/ordinary_greatsword"


func _rgba_sha(image: Image) -> String:
	var context: HashingContext = HashingContext.new()
	assert(context.start(HashingContext.HASH_SHA256) == OK)
	assert(context.update(image.get_data()) == OK)
	return context.finish().hex_encode()


func _lossless(path: String) -> void:
	var config: ConfigFile = ConfigFile.new()
	var sidecar: String = path + ".import"
	if FileAccess.file_exists(sidecar):
		assert(config.load(sidecar) == OK)
	else:
		config.set_value("remap", "importer", "texture")
		config.set_value("remap", "type", "CompressedTexture2D")
		config.set_value("deps", "source_file", path)
	config.set_value("params", "compress/mode", 0)
	config.set_value("params", "mipmaps/generate", false)
	config.set_value("params", "process/fix_alpha_border", false)
	config.set_value("params", "process/premult_alpha", false)
	config.set_value("params", "detect_3d/compress_to", 0)
	assert(config.save(sidecar) == OK)


func run(main: Node, candidate: String = "R3/05") -> Dictionary:
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_mswd0007_r1.json"))
	assert(Vector2(original.canvas_size[0], original.canvas_size[1]) == Vector2(320, 224)
		and Vector2(original.foot_anchor[0], original.foot_anchor[1]) == Vector2(133, 167))
	var records: Array[Dictionary] = []
	var provenance: Array[Dictionary] = []
	var all_endpoints: bool = true
	var all_roundtrips: bool = true
	var all_runtime_copies: bool = true
	var runtime_count: int = 0
	for action: String in ["move", "dash"]:
		var folder: String = "walk" if action == "move" else "dash"
		var base: String = SOURCE_ROOT + "/" + folder
		var recipe_name: String = "walk_recipe.json" if action == "move" else "dash_recipe.json"
		var shader_name: String = "walk_shear.gdshader" if action == "move" else "dash_skin.gdshader"
		var script: GDScript = GDScript.new()
		script.source_code = FileAccess.get_file_as_string(base + "/actor.gd")
		assert(script.reload() == OK)
		var viewport: SubViewport = SubViewport.new()
		viewport.size = Vector2i(320, 224)
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.world_2d = World2D.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		main.get_tree().root.add_child(viewport)
		var actor: Node2D = script.new()
		viewport.add_child(actor)
		var source_frames: Array = original.animations[action].frames
		assert(source_frames.size() == 8)
		var baked_directory: String = base + "/baked"
		var runtime_directory: String = ASSET_ROOT + "/" + folder
		assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(baked_directory)) == OK)
		assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(runtime_directory)) == OK)
		for frame: int in 8:
			assert(int(source_frames[frame].duration_ms) == 100)
			for subframe: int in 3:
				actor.update_pose(frame, subframe)
				for _settle: int in 3:
					await RenderingServer.frame_post_draw
				var rendered: Image = viewport.get_texture().get_image()
				rendered.convert(Image.FORMAT_RGBA8)
				assert(rendered.get_size() == Vector2i(320, 224))
				var name: String = "%s_%02d_%d.png" % [action, frame, subframe]
				var output_path: String = baked_directory + "/" + name
				assert(rendered.save_png(output_path) == OK)
				_lossless(output_path)
				var reloaded: Image = Image.new()
				assert(reloaded.load_png_from_buffer(FileAccess.get_file_as_bytes(output_path)) == OK)
				reloaded.convert(Image.FORMAT_RGBA8)
				var roundtrip: bool = reloaded.get_data() == rendered.get_data()
				all_roundtrips = all_roundtrips and roundtrip
				var endpoint: Variant = null
				var runtime_path: String = ""
				var runtime_copy: Variant = null
				if subframe == 0:
					var expected: Image = Image.new()
					assert(expected.load_png_from_buffer(FileAccess.get_file_as_bytes(source_frames[frame].texture)) == OK)
					expected.convert(Image.FORMAT_RGBA8)
					endpoint = rendered.get_data() == expected.get_data()
					all_endpoints = all_endpoints and bool(endpoint)
				else:
					runtime_path = runtime_directory + "/" + name
					var output: FileAccess = FileAccess.open(runtime_path, FileAccess.WRITE)
					assert(output != null)
					output.store_buffer(FileAccess.get_file_as_bytes(output_path))
					output.close()
					_lossless(runtime_path)
					runtime_copy = FileAccess.get_file_as_bytes(runtime_path) == FileAccess.get_file_as_bytes(output_path)
					all_runtime_copies = all_runtime_copies and bool(runtime_copy)
					runtime_count += 1
				records.append({"action": action, "frame": frame, "subframe": subframe,
					"path": output_path, "runtime_path": runtime_path, "png_sha256": FileAccess.get_sha256(output_path),
					"rgba_sha256": _rgba_sha(rendered),
					"size": [320, 224], "png_roundtrip_exact": roundtrip,
					"variant_endpoint_rgba_exact": endpoint, "runtime_png_copy_exact": runtime_copy})
		viewport.queue_free()
		await main.get_tree().process_frame
		provenance.append({"action": action, "actor_source_sha256": script.source_code.sha256_text(),
			"recipe_sha256": FileAccess.get_sha256(base + "/" + recipe_name),
			"shader_sha256": FileAccess.get_sha256(base + "/" + shader_name)})
	var success: bool = all_endpoints and all_roundtrips and all_runtime_copies and records.size() == 48 and runtime_count == 32
	# Existing reserved paths become publishable only after successful native QA.
	for folder: String in ["walk", "dash"]:
		var path: String = "res://data/swordman_mswd0007_" + folder + "_inbetweens.json"
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		data.bake_complete = success
		data.bake_source_reference = "docs/r3_05_weapon_bake_checks.json"
		var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		output.store_string(JSON.stringify(data, "\t") + "\n")
		output.close()
	var report: Dictionary = {"schema": 1, "candidate": candidate, "equipment_id": 27304,
		"created_at": Time.get_datetime_string_from_system(true), "godot": Engine.get_version_info().string,
		"qa_source_sha256": get_script().source_code.sha256_text(),
		"raw_layer_data_sha256": FileAccess.get_sha256("res://data/swordman_mswd0007_r0.json"),
		"composite_data_sha256": FileAccess.get_sha256("res://data/swordman_mswd0007_r1.json"),
		"native_sources": provenance, "records": records, "sample_count": records.size(),
		"runtime_inbetween_textures": runtime_count, "variant_endpoints_checked": 16,
		"endpoint_full_rgba_exact": all_endpoints, "all_png_roundtrips_exact": all_roundtrips,
		"all_runtime_png_copies_exact": all_runtime_copies, "all_passed": success,
		"notes": ["New isolated variant data and experiment paths only; originalR1 experiments and runtime assets untouched.",
			"Upper body and equippedweapon use original character100ms frame clock; lower apparel uses authored30Hz samples.",
			"No attackclock, movement speed, combat damage, gameplay actor or scene transform changed by the baker."]}
	var file: FileAccess = FileAccess.open("res://docs/r3_05_weapon_bake_checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	return {"samples": records.size(), "runtime_textures": runtime_count, "all_passed": success,
		"endpoint_full_rgba_exact": all_endpoints, "report": "docs/r3_05_weapon_bake_checks.json"}
