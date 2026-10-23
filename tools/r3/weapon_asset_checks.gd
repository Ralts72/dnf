extends RefCounted
## Read actual Godot imports and compare all equipment PNG channels, including transparent RGB.

func collect(folder: String) -> Array[String]:
	var paths: Array[String] = []
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".png"):
			paths.append(folder.path_join(file))
	for child: String in DirAccess.get_directories_at(folder):
		paths.append_array(collect(folder.path_join(child)))
	return paths


func run(_main: Node, candidate: String = "R3/05") -> Dictionary:
	var records: Array[Dictionary] = []
	var pixels: int = 0
	var started: int = Time.get_ticks_usec()
	var paths: Array[String] = collect("res://assets/r3/equipment/ordinary_greatsword")
	paths.sort()
	for path: String in paths:
		var source := Image.new()
		var source_error: Error = source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		var texture: Texture2D = load(path)
		var imported: Image = texture.get_image()
		if imported.is_compressed():
			imported.decompress()
		source.convert(Image.FORMAT_RGBA8)
		imported.convert(Image.FORMAT_RGBA8)
		var config := ConfigFile.new()
		var settings: bool = config.load(path + ".import") == OK
		for pair: Array in [["compress/mode", 0], ["mipmaps/generate", false], ["process/fix_alpha_border", false], ["process/premult_alpha", false], ["detect_3d/compress_to", 0]]:
			settings = settings and config.get_value("params", pair[0], null) == pair[1]
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(source.get_data())
		pixels += source.get_width() * source.get_height()
		records.append({"path": path, "source_loaded": source_error == OK,
			"size": [source.get_width(), source.get_height()], "exact_rgba": source.get_data() == imported.get_data(),
			"lossless_settings": settings, "rgba_sha256": context.finish().hex_encode()})
	var failed: Array = records.filter(func(r): return not r.source_loaded or not r.exact_rgba or not r.lossless_settings)
	var report: Dictionary = {"candidate": candidate, "textures": records.size(), "expected_textures": 290,
		"native_exact_rgba_pixels": pixels, "all_passed": records.size() == 290 and failed.is_empty(),
		"failed": failed, "records": records, "seconds": float(Time.get_ticks_usec()-started)/1000000.0,
		"qa_source_sha256": get_script().source_code.sha256_text(),
		"note": "Import readback verification only. Source PVF/IMG and native derived-pose provenance live in separate source and bake reports. Not a performance benchmark."}
	var file := FileAccess.open("res://docs/r3_05_weapon_asset_checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	return {"textures": records.size(), "pixels": pixels, "failed": failed.size(), "all_passed": report.all_passed}
