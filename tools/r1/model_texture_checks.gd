extends RefCounted
## Test actual imported material textures and native 3D nearest sampling.

var checks: Array=[]
var render_cases: Array=[]


func check_result(label: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":label,"pass":passed,"details":details})


func rgb_distance(a: Color,b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))


func actual_textures(main: Node) -> Dictionary:
	var textures: Dictionary={}
	for obj: MeshInstance3D in main.world.get_node("PortArchitecture").find_children("*","MeshInstance3D",true,false):
		for i: int in obj.mesh.get_surface_count():
			var material: StandardMaterial3D=obj.mesh.surface_get_material(i)
			if material!=null and material.albedo_texture!=null:textures[material.albedo_texture.resource_path]=material.albedo_texture
	return textures


func sample(main: Node,texture: Texture2D,source: Image,scale: int) -> void:
	var tree: SceneTree=main.get_tree()
	var viewport:=SubViewport.new()
	viewport.size=source.get_size()*scale
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.size=source.get_height()*.01
	camera.position=Vector3(0,0,1)
	viewport.add_child(camera)
	camera.current=true
	var quad:=QuadMesh.new()
	quad.size=Vector2(source.get_size())*.01
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture=texture
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold=.25
	quad.material=material
	var panel:=MeshInstance3D.new()
	panel.mesh=quad
	viewport.add_child(panel)
	for _i: int in 3:await RenderingServer.frame_post_draw
	var image: Image=viewport.get_texture().get_image()
	var samples: int=0
	var matching: int=0
	var maximum: float=0.0
	for y: int in range(1,source.get_height()-1,2):
		for x: int in range(1,source.get_width()-1,2):
			var expected: Color=source.get_pixel(x,y)
			if expected.a<.999:continue
			var point:=Vector2i(Vector2(x+.5,y+.5)*scale)
			var actual: Color=image.get_pixelv(point)
			samples+=1
			var distance: float=rgb_distance(expected,actual)
			maximum=maxf(maximum,distance)
			if distance<.5/255.0 and actual.a>.999:matching+=1
	var record: Dictionary={"path":texture.resource_path,"scale":scale,"samples":samples,"matching":matching,"max_rgb_distance":maximum,
		"source_size":source.get_size(),"render_target":image.get_size()}
	render_cases.append(record)
	check_result("native_3d_source_rgb_%dx_%s"%[scale,texture.resource_path.get_file()],samples>1 and matching==samples,record)
	if scale==2 and texture.resource_path.get_file() in ["west_coast_port_000.png","west_coast_port_paving_tile_0.png","west_coast_port_pier_face.png"]:
		image.save_png("res://docs/previews/r1_18_gpu_"+texture.resource_path.get_file())
	viewport.queue_free()
	await tree.process_frame


func run(main: Node) -> Dictionary:
	var tree: SceneTree=main.get_tree()
	var original: Dictionary=main.player.capture_state()
	var original_scale: int=main.render_scale
	var original_update: int=main.render_viewport.render_target_update_mode
	main._set_paused(true)
	var textures: Dictionary=actual_textures(main)
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/r1_model_texture_manifest.json"))
	check_result("all_twenty_seven_actual_model_textures_discovered",textures.size()==27)
	var paths: Array=textures.keys()
	paths.sort()
	var expected_paths: Array=[]
	for item: Dictionary in manifest.textures:expected_paths.append(item.path)
	expected_paths.sort()
	check_result("actual_material_paths_match_discovered_manifest",paths==expected_paths)
	main.render_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	for path: String in paths:
		var texture: Texture2D=textures[path]
		var source:=Image.new()
		source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		source.convert(Image.FORMAT_RGBA8)
		var actual: Image=texture.get_image()
		var compressed: bool=actual.is_compressed()
		if compressed:actual.decompress()
		actual.convert(Image.FORMAT_RGBA8)
		check_result("imported_full_rgba_%s"%path.get_file(),not compressed and actual.get_size()==source.get_size() and actual.get_data()==source.get_data(),
			{"path":path,"runtime_size":actual.get_size(),"source_size":source.get_size(),"compressed":compressed,"rgba_pixels":source.get_width()*source.get_height()})
		await sample(main,texture,source,1)
		await sample(main,texture,source,2)
	main.render_viewport.render_target_update_mode=original_update as SubViewport.UpdateMode
	# F6 changes only target size; the imported texture objects must stay intact.
	var ids: Dictionary={}
	for path: String in paths:ids[path]=textures[path].get_instance_id()
	var retained: bool=true
	for scale: int in [1,2]:
		main.set_render_scale(scale)
		await RenderingServer.frame_post_draw
		var current: Dictionary=actual_textures(main)
		retained=retained and current.size()==ids.size()
		for path: String in paths:retained=retained and current.has(path) and current[path].get_instance_id()==ids[path]
	check_result("quality_switch_retains_texture_resources",retained,{"actual_material_textures_checked":ids.size(),"scales":[1,2]})
	main.set_render_scale(original_scale)
	main.player.restore_state(original)
	main._set_paused(original.paused)
	var failed: Array=checks.filter(func(c: Dictionary):return not c.pass)
	var report: Dictionary={"candidate":"R1/18","checks":checks,"failed":failed,"render_cases":render_cases,
		"qa_source_sha256":get_script().source_code.sha256_text(),"glb_sha256":FileAccess.get_sha256("res://assets/r1/models/west_coast_port.glb"),
		"note":"Imported full RGBA is compared to extracted PNGs. GPU texture sampling is isolated on unlit native 3D panels; actual scene PBR lighting remains enabled."}
	var out:=FileAccess.open("res://docs/r1_18_model_texture_checks.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	out.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases}
