extends RefCounted
## Native grove geometry, source-pixel foliage and path-over-water checks.

var checks: Array=[]
var render_cases: Array=[]


func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func rgb_distance(a: Color,b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))


func canopy_sample(main: Node,crown: MeshInstance3D,scale: int) -> void:
	var tree: SceneTree=main.get_tree()
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(896,404)*scale
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	var world:=Node3D.new()
	viewport.add_child(world)
	var copy: MeshInstance3D=crown.duplicate()
	world.add_child(copy)
	copy.global_transform=crown.global_transform
	var camera: Camera3D=main.world.get_node("Camera").duplicate()
	world.add_child(camera)
	camera.global_transform=main.world.get_node("Camera").global_transform
	camera.current=true
	for i: int in 3:
		await RenderingServer.frame_post_draw
	var image: Image=viewport.get_texture().get_image()
	var source:=Image.new()
	source.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/r1/grove_canopy.png"))
	var tested: int=0
	var matched: int=0
	var maximum: float=0.0
	for y: int in range(1,source.get_height()-1,3):
		for x: int in range(1,source.get_width()-1,3):
			var opaque: bool=true
			for d: Vector2i in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				opaque=opaque and source.get_pixel(x+d.x,y+d.y).a>.999
			if not opaque:
				continue
			var point:=Vector2i((Vector2(225+x+.5,1+y+.5))*scale)
			var actual: Color=image.get_pixelv(point)
			var expected: Color=source.get_pixel(x,y)
			var distance: float=rgb_distance(actual,expected)
			tested+=1
			maximum=maxf(maximum,distance)
			if distance<.5/255.0 and actual.a>.999:
				matched+=1
	var case: Dictionary={"scale":scale,"samples":tested,"matching":matched,"max_rgb_distance":maximum}
	render_cases.append(case)
	check_result("canopy_source_pixels_%dx"%scale,tested>1200 and matched==tested,case)
	var empty: int=0
	for p: Vector2i in [Vector2i(10,110),Vector2i(115,130),Vector2i(210,130)]:
		var point:=Vector2i(Vector2(225+p.x+.5,1+p.y+.5)*scale)
		if image.get_pixelv(point).a<.001:
			empty+=1
	check_result("no_baked_plaster_in_canopy_%dx"%scale,empty==3,{"transparent_probes":empty})
	image.save_png("res://docs/previews/r1_11_canopy_%dx.png"%scale)
	viewport.queue_free()
	await tree.process_frame


func run(root: Node) -> Dictionary:
	var tree: SceneTree=root.get_tree()
	var original: Dictionary=root.player.capture_state()
	var update: int=root.render_viewport.render_target_update_mode
	root._set_paused(true)
	var architecture: Node=root.world.get_node("PortArchitecture")
	var crown: MeshInstance3D=architecture.find_child("Grove_Source_Canopy",true,false)
	var path: MeshInstance3D=architecture.find_child("Grove_Connecting_Stone_Path",true,false)
	var trunks: Array=architecture.find_children("Grove_Tree_*_Trunk_*","MeshInstance3D",true,false)
	var branches: Array=architecture.find_children("Grove_Tree_*_Branch_*","MeshInstance3D",true,false)
	check_result("native_grove_meshes_present",architecture.find_children("Grove_*","MeshInstance3D",true,false).size()==27)
	check_result("three_segmented_native_trunks",trunks.size()==9 and branches.size()==12,{"trunks":trunks.size(),"branches":branches.size()})
	var volume: bool=true
	for trunk: MeshInstance3D in trunks:
		var box: AABB=trunk.global_transform*trunk.get_aabb()
		volume=volume and box.size.x>.1 and box.size.z>.1 and box.size.y>.4
	check_result("trunks_have_real_native_volume",volume)
	check_result("connecting_path_extends_below_water",path.get_aabb().size.y>.6)
	check_result("garden_wall_has_receding_return",architecture.find_child("Grove_Boundary_Wall_Front",true,false)!=null
		and architecture.find_child("Grove_Boundary_Wall_Return",true,false).get_aabb().size.z>.8)
	check_result("planting_bed_and_grass_are_separate",architecture.find_child("Grove_Planting_Bed_Base",true,false)!=null
		and architecture.find_child("Grove_Planting_Bed_Grass",true,false)!=null)
	var mat: StandardMaterial3D=crown.mesh.surface_get_material(0)
	check_result("canopy_uses_alpha_cutout",mat.transparency==2 and is_equal_approx(mat.alpha_scissor_threshold,.25))
	check_result("canopy_preserves_unlit_source_colors",mat.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED)
	check_result("canopy_has_nearest_sampling",mat.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST)
	root.render_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	await canopy_sample(root,crown,1)
	await canopy_sample(root,crown,2)
	root.render_viewport.render_target_update_mode=update as SubViewport.UpdateMode
	for i: int in 3:
		await RenderingServer.frame_post_draw
	var with_path: Image=root.render_viewport.get_texture().get_image()
	with_path.save_png("res://docs/previews/r1_11_grove_visible.png")
	path.visible=false
	await RenderingServer.frame_post_draw
	var without_path: Image=root.render_viewport.get_texture().get_image()
	without_path.save_png("res://docs/previews/r1_11_path_hidden.png")
	path.visible=true
	var point:=Vector2i(Vector2(440.5,176.5+43)*root.render_scale)
	var a: Color=with_path.get_pixelv(point)
	var b: Color=without_path.get_pixelv(point)
	check_result("stone_path_covers_previous_water_gap",rgb_distance(a,b)>.2 and b.b>b.r,
		{"source_point":Vector2(440.5,176.5),"path":a,"without_path":b})
	# Only the crown is removed; source props and the rest of the geometry stay put.
	crown.visible=false
	await RenderingServer.frame_post_draw
	var without_crown: Image=root.render_viewport.get_texture().get_image()
	crown.visible=true
	var changed: int=0
	for y: int in range(2,140,3):
		for x: int in range(226,449,3):
			var p:=Vector2i(Vector2(x,y)*root.render_scale)
			if rgb_distance(with_path.get_pixelv(p),without_crown.get_pixelv(p))>.05:
				changed+=1
	check_result("source_crown_visible_in_full_scene",changed>500,{"changed_samples":changed})
	# The new far foliage must not paint over a player jumping in the near lane.
	var p: Node=root.player
	p.reset_position()
	p.position=p.source_to_world(Vector2(320,285))
	p.start_jump()
	p._tick_jump(.6,false)
	p.paused=true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var air_image: Image=root.render_viewport.get_texture().get_image()
	air_image.save_png("res://docs/previews/r1_11_jump_in_front_of_grove.png")
	var source:=Image.new()
	source.load_png_from_buffer(FileAccess.get_file_as_bytes(p.current_frame()["texture"]))
	var camera: Camera3D=root.world.get_node("Camera")
	var foot: Vector2=camera.unproject_position(p.position+Vector3.UP*p.height_above_ground)
	var tested: int=0
	var matching: int=0
	for y: int in range(1,source.get_height()-1,3):
		for x: int in range(1,source.get_width()-1,3):
			var opaque: bool=true
			for d: Vector2i in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				opaque=opaque and source.get_pixel(x+d.x,y+d.y).a>.999
			if not opaque:
				continue
			var target:=Vector2i(foot+(Vector2(x+.5,y+.5)-p._foot_anchor)*root.render_scale)
			tested+=1
			if rgb_distance(air_image.get_pixelv(target),source.get_pixel(x,y))<.5/255.0:
				matching+=1
	check_result("air_player_stays_in_front_of_far_grove",tested>300 and matching==tested,
		{"samples":tested,"matching":matching,"height_pixels":p.jump_motion.height_pixels,"foot":foot})
	root.player.restore_state(original)
	root._set_paused(original["paused"])
	var failed: Array=checks.filter(func(c: Dictionary):return not c["pass"])
	var report: Dictionary={"candidate":"R1/11","checks":checks,"failed":failed,"render_cases":render_cases,
		"glb_sha256":FileAccess.get_sha256("res://assets/r1/models/west_coast_port.glb"),
		"source_script_sha256":get_script().source_code.sha256_text(),
		"note":"Source foliage RGB tested in isolated native 3D targets at 1x and 2x; path tested in actual scene. New geometry and mask selection are interpretations."}
	var file:=FileAccess.open("res://docs/r1_11_grove_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases}
