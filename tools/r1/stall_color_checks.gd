extends RefCounted
## Measure imported, actually rendered stall colors and its retained cast shadow.

var checks: Array=[]
var render_cases: Array=[]


func check_result(label: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":label,"pass":passed,"details":details})


func rgb_distance(a: Color,b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))


func sample(main: Node,meshes: Array,scale: int,source: Image) -> void:
	var tree: SceneTree=main.get_tree()
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(896,404)*scale
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	var world:=Node3D.new()
	viewport.add_child(world)
	for obj: MeshInstance3D in meshes:
		var copy: MeshInstance3D=obj.duplicate()
		world.add_child(copy)
		copy.global_transform=obj.global_transform
	var camera: Camera3D=main.world.get_node("Camera").duplicate()
	world.add_child(camera)
	camera.global_transform=main.world.get_node("Camera").global_transform
	camera.current=true
	var light:=DirectionalLight3D.new()
	light.light_color=Color(1,.05,.02)
	light.light_energy=8.0
	world.add_child(light)
	for _i: int in 3:await RenderingServer.frame_post_draw
	var image: Image=viewport.get_texture().get_image()
	var tested: int=0
	var matching: int=0
	var empty: int=0
	var transparent: int=0
	var maximum: float=0.0
	for y: int in range(2,source.get_height()-2,2):
		for x: int in range(2,source.get_width()-2,2):
			var expected: Color=source.get_pixel(x,y)
			var solid: bool=true
			var clear: bool=true
			for d: Vector2i in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				solid=solid and source.get_pixel(x+d.x,y+d.y).a>.999
				clear=clear and source.get_pixel(x+d.x,y+d.y).a<.001
			var point:=Vector2i(Vector2(172+x+.5,81+y+.5)*scale)
			var actual: Color=image.get_pixelv(point)
			for d: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				solid=solid and image.get_pixelv(point+d*scale).a>.999
			if solid and actual.a>.999:
				tested+=1
				var distance: float=rgb_distance(actual,expected)
				maximum=maxf(maximum,distance)
				if distance<.5/255.0:matching+=1
			if clear:
				empty+=1
				if actual.a<.001:transparent+=1
	var details: Dictionary={"scale":scale,"samples":tested,"matching":matching,"max_rgb_distance":maximum,
		"clear_source_samples":empty,"transparent":transparent,"light_energy":light.light_energy,"light_color":light.light_color}
	render_cases.append(details)
	check_result("original_stall_rgb_under_red_light_%dx"%scale,tested>4000 and matching==tested,details)
	check_result("source_transparent_pixels_remain_empty_%dx"%scale,empty>7000 and transparent==empty,details)
	# Independent, fixed source regions prevent missing surfaces from passing by omission.
	for region: Dictionary in [{"name":"red_drapery","rect":Rect2i(40,70,65,70)},
		{"name":"canopy","rect":Rect2i(175,25,25,20)},
		{"name":"blue_counter_cloth","rect":Rect2i(198,130,20,8)}]:
		var count: int=0
		var matches: int=0
		var rectangle: Rect2i=region.rect
		for y: int in range(rectangle.position.y,rectangle.end.y,2):
			for x: int in range(rectangle.position.x,rectangle.end.x,2):
				var p:=Vector2i(Vector2(172+x+.5,81+y+.5)*scale)
				count+=1
				if image.get_pixelv(p).a>.999 and rgb_distance(image.get_pixelv(p),source.get_pixel(x,y))<.5/255.0:matches+=1
		check_result("region_%s_%dx"%[region.name,scale],matches==count,{"samples":count,"matching":matches})
	image.save_png("res://docs/previews/r1_18_stall_isolated_%dx.png"%scale)
	viewport.queue_free()
	await tree.process_frame


func run(main: Node) -> Dictionary:
	var tree: SceneTree=main.get_tree()
	var original: Dictionary=main.player.capture_state()
	main._set_paused(true)
	var painted: Array=[]
	var architecture: Node=main.world.get_node("PortArchitecture")
	for obj: MeshInstance3D in architecture.find_children("Stall_*","MeshInstance3D",true,false):
		var mat: StandardMaterial3D=obj.mesh.surface_get_material(0)
		if mat.resource_name=="Source_Painted_Stall":painted.append(obj)
	check_result("thirteen_separate_painted_meshes",painted.size()==13)
	var unlit: bool=true
	var cutout: bool=true
	var nearest: bool=true
	var casts: bool=true
	for obj: MeshInstance3D in painted:
		var mat: StandardMaterial3D=obj.mesh.surface_get_material(0)
		unlit=unlit and mat.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED
		cutout=cutout and mat.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and is_equal_approx(mat.alpha_scissor_threshold,.25)
		nearest=nearest and mat.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST
		casts=casts and obj.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	check_result("painted_color_uses_unlit_material",unlit)
	check_result("painted_alpha_uses_cutout",cutout)
	check_result("painted_pixels_use_nearest_sampling",nearest)
	check_result("painted_geometry_retains_cast_shadow",casts)
	var mast: MeshInstance3D=architecture.find_child("Stall_Central_Parasol_Mast",true,false)
	check_result("native_wood_still_uses_scene_lighting",mast.mesh.surface_get_material(0).shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	var source:=Image.new()
	source.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/r0/port/westmobj00/image/000.png"))
	var imported: Image=painted[0].mesh.surface_get_material(0).albedo_texture.get_image()
	var compressed: bool=imported.is_compressed()
	if compressed:imported.decompress()
	imported.convert(Image.FORMAT_RGBA8)
	check_result("imported_texture_preserves_all_source_rgba",not compressed and imported.get_data()==source.get_data(),
		{"pixels":source.get_width()*source.get_height(),"vram_compressed":compressed})
	var original_update: int=main.render_viewport.render_target_update_mode
	main.render_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	await sample(main,painted,1,source)
	await sample(main,painted,2,source)
	main.render_viewport.render_target_update_mode=original_update as SubViewport.UpdateMode
	for _i: int in 3:await RenderingServer.frame_post_draw
	var with_shadow: Image=main.render_viewport.get_texture().get_image()
	var modes: Array=[]
	for obj: MeshInstance3D in painted:
		modes.append(obj.cast_shadow)
		obj.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for _i: int in 3:await RenderingServer.frame_post_draw
	var without_shadow: Image=main.render_viewport.get_texture().get_image()
	var changed: int=0
	var tested: int=0
	for y: int in range(160,182):
		for x: int in range(416,440):
			var point:=Vector2i(Vector2(x+.5,y+.5)*main.render_scale)
			if source.get_pixel(x-172,y-81).a>.001:continue
			tested+=1
			if rgb_distance(with_shadow.get_pixelv(point),without_shadow.get_pixelv(point))>.01:changed+=1
	check_result("unlit_stall_still_shadows_native_wall",changed>40,{"samples":tested,"changed_pixels":changed})
	with_shadow.save_png("res://docs/previews/r1_18_stall_shadow_on.png")
	without_shadow.save_png("res://docs/previews/r1_18_stall_shadow_off.png")
	for i: int in painted.size():painted[i].cast_shadow=modes[i]
	main.player.restore_state(original)
	main._set_paused(original.paused)
	await tree.process_frame
	var failed: Array=checks.filter(func(c: Dictionary):return not c.pass)
	var report: Dictionary={"candidate":"R1/18","checks":checks,"failed":failed,"render_cases":render_cases,
		"qa_source_sha256":get_script().source_code.sha256_text(),"glb_sha256":FileAccess.get_sha256("res://assets/r1/models/west_coast_port.glb"),
		"note":"Original source PNG RGB measured in isolated native 3D targets under red light. Actual wall shadow checked separately in the main scene."}
	var out:=FileAccess.open("res://docs/r1_18_stall_color_checks.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	out.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases}
