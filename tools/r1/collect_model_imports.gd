extends SceneTree
## Discover the real PNG paths selected by Godot's GLB importer, without guessing
## the suffix used for repeated image names. Run after the first import pass.


func _initialize() -> void:
	call_deferred("collect")


func digest(bytes: PackedByteArray) -> String:
	var context:=HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func collect() -> void:
	var model_path: String="res://assets/r1/models/west_coast_port.glb"
	var model: Node=load(model_path).instantiate()
	var textures: Dictionary={}
	for obj: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for i: int in obj.mesh.get_surface_count():
			var material: StandardMaterial3D=obj.mesh.surface_get_material(i)
			if material==null or material.albedo_texture==null:continue
			var path: String=material.albedo_texture.resource_path
			assert(path.begins_with("res://assets/r1/models/") and FileAccess.file_exists(path))
			if not textures.has(path):
				var original:=Image.new()
				var error: int=original.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
				assert(error==OK)
				original.convert(Image.FORMAT_RGBA8)
				textures[path]={"path":path,"png_sha256":FileAccess.get_sha256(path),
					"rgba_sha256":digest(original.get_data()),"size":[original.get_width(),original.get_height()],"materials":[]}
			if not str(material.resource_name) in textures[path].materials:
				textures[path].materials.append(str(material.resource_name))
	var paths: Array=textures.keys()
	paths.sort()
	var records: Array=[]
	for path: String in paths:
		textures[path].materials.sort()
		records.append(textures[path])
	var report: Dictionary={"model":model_path,"glb_sha256":FileAccess.get_sha256(model_path),
		"texture_count":records.size(),"textures":records,
		"collector_sha256":get_script().source_code.sha256_text(),
		"note":"Actual imported model material paths. Sizes and RGBA hashes are read from the extracted PNG files, not compressed runtime images."}
	var out:=FileAccess.open("res://docs/r1_model_texture_manifest.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	out.close()
	model.free()
	print("Model texture discovery: ",records.size()," active PNGs.")
	quit()
