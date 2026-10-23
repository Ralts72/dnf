extends RefCounted
## Independent camera-space checks of the painted facade's 3D projection.

var checks: Array=[]
var render_cases: Array=[]


func check_result(label: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":label,"pass":passed,"details":details})


func distance(a: Color,b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))


func sample(main: Node,meshes: Array,source: Image,scale: int,phase: String) -> void:
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
		var material: StandardMaterial3D=obj.mesh.surface_get_material(0).duplicate()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled=false
		copy.material_override=material
		world.add_child(copy)
		copy.global_transform=obj.global_transform
	var camera: Camera3D=main.world.get_node("Camera").duplicate()
	world.add_child(camera)
	camera.global_transform=main.world.get_node("Camera").global_transform
	camera.current=true
	# Calibrate from the actual camera and the retained facade reference plane.
	var origin: Vector2=camera.unproject_position(Vector3(0,0,-.42))/scale-Vector2(447,227.59)
	for _i: int in 3:await RenderingServer.frame_post_draw
	var image: Image=viewport.get_texture().get_image()
	var samples: int=0
	var matching: int=0
	var clear: int=0
	var transparent: int=0
	var maximum: float=0.0
	for y: int in range(2,source.get_height()-2,2):
		for x: int in range(2,source.get_width()-2,2):
			var point:=Vector2i((Vector2(x+.5,y+.5)+origin)*scale)
			if point.y>=image.get_height()-scale:continue
			var actual: Color=image.get_pixelv(point)
			var solid: bool=true
			var empty: bool=true
			for d: Vector2i in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				solid=solid and source.get_pixel(x+d.x,y+d.y).a>.999 and image.get_pixelv(point+d*scale).a>.999
				empty=empty and source.get_pixel(x+d.x,y+d.y).a<.001
			if solid and actual.a>.999:
				samples+=1
				var error: float=distance(actual,source.get_pixel(x,y))
				maximum=maxf(maximum,error)
				if error<.5/255.0:matching+=1
			if empty:
				clear+=1
				if actual.a<.001:transparent+=1
	var record: Dictionary={"scale":scale,"samples":samples,"matching":matching,"max_rgb_distance":maximum,
		"clear_samples":clear,"transparent":transparent,"source_origin":origin}
	render_cases.append(record)
	check_result("camera_aligned_facade_rgb_%dx"%scale,samples>5000 and matching==samples,record)
	check_result("original_facade_gaps_remain_transparent_%dx"%scale,clear>1000 and transparent==clear,record)
	image.save_png("res://docs/previews/r1_17_facade_"+phase+"_%dx.png"%scale)
	viewport.queue_free()
	await tree.process_frame


func run(main: Node) -> Dictionary:
	var tree: SceneTree=main.get_tree()
	var phase: String=tree.get_meta("facade_qa_phase","after")
	var original: Dictionary=main.player.capture_state()
	var update: int=main.render_viewport.render_target_update_mode
	main._set_paused(true)
	var meshes: Array=[]
	for obj: MeshInstance3D in main.world.get_node("PortArchitecture").find_children("*","MeshInstance3D",true,false):
		if obj.mesh.surface_get_material(0).resource_name=="Source_Painted_Facade":meshes.append(obj)
	check_result("all_seventy_six_facade_parts_present",meshes.size()==76)
	var material: StandardMaterial3D=meshes[0].mesh.surface_get_material(0)
	check_result("facade_pbr_lighting_retained",material.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	check_result("facade_source_alpha_uses_cutout",material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and is_equal_approx(material.alpha_scissor_threshold,.25))
	var source:=Image.new()
	source.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/r0/port/westile00/image/000.png"))
	main.render_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	await sample(main,meshes,source,1,phase)
	await sample(main,meshes,source,2,phase)
	main.render_viewport.render_target_update_mode=update as SubViewport.UpdateMode
	main.player.restore_state(original)
	main._set_paused(original.paused)
	var failed: Array=checks.filter(func(c: Dictionary):return not c.pass)
	var report: Dictionary={"candidate":"R1/17","phase":phase,"checks":checks,"failed":failed,"render_cases":render_cases,
		"qa_source_sha256":get_script().source_code.sha256_text(),"glb_sha256":FileAccess.get_sha256("res://assets/r1/models/west_coast_port.glb"),
		"note":"Projection and alpha tested with actual meshes and UVs in isolated unlit 3D targets. Main scene facade retains PBR lighting."}
	var out:=FileAccess.open("res://docs/r1_17_facade_"+phase+"_checks.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	out.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases}
