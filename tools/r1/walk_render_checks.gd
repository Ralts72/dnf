extends RefCounted
## Check production-selected walk RGBA poses in the real R1 material.

var render_cases: Array=[]
var checks: Array=[]
var images: Dictionary={}
var selection_cases: Array=[]
var sampler: RefCounted


func set_pose(root: Node,frame: int,sub: int,facing: int) -> Image:
	var p: Node=root.player
	p.frame_index=frame;p.elapsed_ms=float(sub)*100.0/3.0;p.facing=facing
	p._apply_frame()
	var key: String="%d_%d"%[frame,sub]
	p._update_sprite_transform()
	var expected_path: String=p.current_frame().texture if sub==0 else "res://assets/r1/actors/swordman_walk/move_%02d_%d.png"%[frame,sub]
	selection_cases.append({"frame":frame,"subframe":sub,"path":p.sprite.texture.resource_path,
		"pass":p.sprite.texture.resource_path==expected_path and p.walk_inbetweens.subframe==sub
		and p.source_material.get_shader_parameter("source_texture")==p.sprite.texture})
	return images[key]


func target(root: Node,pixel: Vector2i,scale: int) -> Vector2i:
	var foot: Vector2=root.world.get_node("Camera").unproject_position(root.player.position)/float(scale)
	var offset: Vector2=Vector2(pixel)+Vector2(.5,.5)-Vector2(133,167)
	offset.x*=root.player.facing
	return Vector2i((foot+offset)*float(scale))


func render_case(root: Node,frame: int,sub: int,facing: int,scale: int) -> void:
	var source: Image=set_pose(root,frame,sub,facing)
	for _i: int in 2:await RenderingServer.frame_post_draw
	var actual: Image=root.render_viewport.get_texture().get_image()
	var samples: int=0;var mismatches: int=0;var clipped: int=0;var maximum: float=0
	for y: int in range(1,223,4):
		for x: int in range(1,319,4):
			var pixel:=Vector2i(x,y)
			if not sampler.opaque_interior(source,pixel):continue
			var point: Vector2i=target(root,pixel,scale)
			if not Rect2i(Vector2i.ZERO,actual.get_size()).has_point(point):clipped+=1;continue
			var difference: float=sampler.color_distance(source.get_pixelv(pixel),actual.get_pixelv(point))
			samples+=1;maximum=maxf(maximum,difference)
			if difference>.025:mismatches+=1
	var result: Dictionary={"frame":frame,"subframe":sub,"facing":facing,"scale":scale,"samples":samples,"mismatches":mismatches,"clipped":clipped,
		"max_rgb_distance":maximum,"pass":samples>30 and mismatches==0 and clipped==0}
	render_cases.append(result)
	if frame==6 and sub==2 and facing==1 and scale==2:
		root.get_viewport().get_texture().get_image().save_png("res://docs/previews/r1_25_r1_pose.png")
	if not result.pass:actual.save_png("res://work/r1_25_r1_fail_%d_%d_%d_%d.png"%[frame,sub,facing,scale])


func occlusion(root: Node) -> void:
	root.set_render_scale(2)
	var source: Image=set_pose(root,6,2,1)
	var box:=MeshInstance3D.new();box.name="ExperimentalWalkOcclusion"
	var mesh:=BoxMesh.new();mesh.size=Vector3(.65,.7,.25)
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(.08,.72,.55);mesh.material=material;box.mesh=mesh
	box.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.world.add_child(box)
	for front: bool in [true,false]:
		box.position=root.player.position+Vector3(0,.35,.35 if front else -.35)
		root.player.sprite.visible=false
		for _i: int in 2:await RenderingServer.frame_post_draw
		var background: Image=root.render_viewport.get_texture().get_image()
		var center: Vector2=root.world.get_node("Camera").unproject_position(box.position)
		var cube_color: Color=background.get_pixelv(Vector2i(center))
		root.player.sprite.visible=true
		for _i: int in 2:await RenderingServer.frame_post_draw
		var actual: Image=root.render_viewport.get_texture().get_image()
		var overlap: int=0;var matches: int=0;var maximum: float=0
		for y: int in range(1,223,2):
			for x: int in range(1,319,2):
				var pixel:=Vector2i(x,y)
				if not sampler.opaque_interior(source,pixel):continue
				var point: Vector2i=target(root,pixel,2)
				if sampler.color_distance(background.get_pixelv(point),cube_color)>.001:continue
				overlap+=1
				var expected: Color=background.get_pixelv(point) if front else source.get_pixelv(pixel)
				var difference: float=sampler.color_distance(actual.get_pixelv(point),expected)
				maximum=maxf(maximum,difference)
				if difference<.025:matches+=1
		checks.append({"check":"real_3d_box_in_front_preserves_cube" if front else "real_3d_box_behind_preserves_actor",
			"pass":overlap>15 and matches==overlap,"samples":overlap,"matching":matches,"max_rgb_distance":maximum})
		actual.save_png("res://docs/previews/r1_25_occlusion_%s.png"%("front" if front else "back"))
	box.queue_free()
	await root.get_tree().process_frame


func run(root: Node) -> Dictionary:
	var original: Dictionary=root.player.capture_state();var scale_before: int=root.render_scale
	var fx_before: bool=root.player.action_effects.enabled
	var walk_before: bool=root.player.walk_inbetweens.enabled
	root.preview_controls._select_walk_inbetweens(true)
	root._set_paused(true);root.player.action_effects.enabled=false
	root.player.position=root.player.source_to_world(Vector2(460,295));root.player.motion_smoothing.reset()
	root.player.preview("move")
	sampler=load("res://tools/r1/pose_checks.gd").new()
	for frame: int in 8:
		for sub: int in 3:
			var key: String="%d_%d"%[frame,sub]
			var path: String="res://source_art/r1/experiments/walk_cycle_24/baked/move_%02d_%d.png"%[frame,sub]
			var image:=Image.new();assert(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK)
			images[key]=image
	for scale: int in [1,2]:
		root.set_render_scale(scale)
		for frame: int in 8:
			for sub: int in 3:
				for facing: int in [1,-1]:await render_case(root,frame,sub,facing,scale)
	await occlusion(root)
	var failed_cases: Array=render_cases.filter(func(c):return not c.pass)
	checks.append({"check":"all_96_real_R1_pose_cases_match","pass":render_cases.size()==96 and failed_cases.is_empty(),"cases":render_cases.size(),"failed_cases":failed_cases.size()})
	checks.append({"check":"runtime_imports_selected_without_QA_texture_substitution","pass":selection_cases.all(func(c):return c.pass),"cases":selection_cases.size()})
	root.player.action_effects.enabled=fx_before
	root.set_render_scale(scale_before);root.player.restore_state(original);root._set_paused(original.paused);root.preview_controls._select_walk_inbetweens(walk_before)
	var failed: Array=checks.filter(func(c):return not c.pass)
	var report: Dictionary={"study":"R1/25 original and derived walk poses on production R1 material","production_candidate":"R1/25","checks":checks,"failed":failed,
		"render_cases":render_cases,"failed_render_cases":failed_cases,"selection_cases":selection_cases,
		"qa_source_sha256":get_script().source_code.sha256_text(),"billboard_shader_sha256":root.player.source_material.shader.code.sha256_text(),
		"notes":["Production walk sampler selects imported textures automatically. Expected pixels come from the independent native-bake reference.",
			"Both source facings, both render qualities, all24 samples; opaque interior source points compared to actual R1 pixels.",
			"Foreground/back box checks cover one representative derived pose, not every scene obstacle."]}
	var output:=FileAccess.open("res://docs/r1_25_r1_checks.json",FileAccess.WRITE);output.store_string(JSON.stringify(report,"  "));output.close()
	return {"cases":render_cases.size(),"failed_cases":failed_cases.size(),"checks":checks.size(),"failed":failed}
