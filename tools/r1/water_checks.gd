extends RefCounted
## GPU palette/grid checks plus real pause input, private clocks and F4 roundtrip.

var checks: Array=[]
var render_cases: Array=[]
var palette: Array[Color]=[]


func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func distance(a: Color,b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))


func key(code: Key,pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event)


func capture(root: Node) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.render_viewport.get_texture().get_image()


func palette_samples(image: Image,scale: int) -> Dictionary:
	var tested: int=0
	var matching: int=0
	var histogram: Array=[]
	histogram.resize(palette.size());histogram.fill(0)
	for sy: int in range(132,261,3):
		for x: int in range(450,851,4):
			var point:=Vector2i(Vector2(x+.5,sy+43+.5)*scale)
			var color: Color=image.get_pixelv(point)
			var best: float=10.0
			var index: int=-1
			for i: int in palette.size():
				var delta: float=distance(color,palette[i])
				if delta<best:best=delta;index=i
			tested+=1
			if best<.5/255.0 and color.a>.999:matching+=1;histogram[index]+=1
	return {"scale":scale,"samples":tested,"matching":matching,"palette_histogram":histogram}


func run(root: Node) -> Dictionary:
	var tree: SceneTree=root.get_tree()
	var original: Dictionary=root.player.capture_state()
	var original_water: Dictionary=root.water.capture_state()
	var original_scale: int=root.render_scale
	var had_meta: bool=tree.has_meta("port_water_state")
	var original_meta: Dictionary=tree.get_meta("port_water_state",{})
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://source_art/r1/water_reference.json"))
	var water: Node=root.water
	check_result("existing_native_water_plane_retained",water.mesh.size==Vector2(18,4.1)
		and water.position==Vector3(0,-.30,-.90) and water.cast_shadow==0)
	for sample: Dictionary in reference["palette"]:
		var rgba: Array=sample["rgba"]
		var color:=Color(rgba[0]/255.0,rgba[1]/255.0,rgba[2]/255.0,rgba[3]/255.0)
		palette.append(color)
		var actual: Color=water.water_material.get_shader_parameter(sample["name"])
		check_result("source_uniform_"+sample["name"],distance(actual,color)<.000001)
	check_result("main_material_is_private",water.material_override!=water.mesh.surface_get_material(0))
	root._set_paused(false)
	var start: float=water.seconds
	await tree.create_timer(.10).timeout
	check_result("live_water_clock_advances",water.seconds>start+.04)
	key(KEY_F2,true);key(KEY_F2,false)
	await tree.process_frame
	check_result("actual_f2_pauses_water_and_actors",water.paused and root.player.paused)
	var frozen: float=water.seconds
	await tree.create_timer(.12).timeout
	check_result("paused_clock_is_exactly_still",water.seconds==frozen)
	check_result("paused_shader_uniform_matches_clock",absf(float(water.water_material.get_shader_parameter("water_time"))-frozen)<.0001)
	key(KEY_F2,true);key(KEY_F2,false)
	await tree.create_timer(.10).timeout
	check_result("actual_f2_resumes_water_clock",not water.paused and not root.player.paused and water.seconds>frozen+.04)
	root._set_paused(true)
	var main_clock: float=water.seconds
	var fixture:=SubViewport.new()
	fixture.name="R1WaterFixture"
	fixture.size=Vector2i(960,540)
	fixture.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	tree.root.add_child(fixture)
	var clone: Node=load("res://scenes/west_coast_r1.tscn").instantiate()
	fixture.add_child(clone)
	clone._set_paused(true)
	for path: String in ["PortArchitecture","Actors","SourceProps"]:
		clone.world.get_node(path).visible=false
	check_result("capture_water_material_is_independent",clone.water.water_material!=water.water_material)
	clone.water.restore_state({"seconds":3.25,"paused":true})
	clone.set_render_scale(1)
	var low: Image=await capture(clone)
	var low_samples: Dictionary=palette_samples(low,1)
	render_cases.append(low_samples)
	check_result("native_1x_water_uses_source_palette",low_samples.samples>4000 and low_samples.matching==low_samples.samples,low_samples)
	low.save_png("res://docs/previews/r1_12_water_isolated_1x.png")
	clone.set_render_scale(2)
	var high: Image=await capture(clone)
	var high_samples: Dictionary=palette_samples(high,2)
	render_cases.append(high_samples)
	check_result("native_2x_water_uses_source_palette",high_samples.samples>4000 and high_samples.matching==high_samples.samples,high_samples)
	high.save_png("res://docs/previews/r1_12_water_isolated_2x.png")
	var compared: int=0
	var matching: int=0
	for sy: int in range(132,261,3):
		for x: int in range(450,851,4):
			var expected: Color=low.get_pixel(x,sy+43)
			for dy: int in [0,1]:
				for dx: int in [0,1]:
					compared+=1
					if distance(high.get_pixel(x*2+dx,(sy+43)*2+dy),expected)<.5/255.0:matching+=1
	check_result("source_pixel_grid_retained_at_2x",matching==compared,{"samples":compared,"matching":matching})
	clone.water.restore_state({"seconds":3.27,"paused":true})
	var same_step: Image=await capture(clone)
	check_result("same_quantized_time_has_identical_pixels",same_step.get_data()==high.get_data())
	clone.water.restore_state({"seconds":7.25,"paused":true})
	var moved: Image=await capture(clone)
	moved.save_png("res://docs/previews/r1_12_water_phase_7_25.png")
	var changed: int=0
	for sy: int in range(132,261,3):
		for x: int in range(450,851,4):
			var point:=Vector2i(Vector2(x+.5,sy+43+.5)*2)
			if distance(high.get_pixelv(point),moved.get_pixelv(point))>.5/255.0:changed+=1
	var fraction: float=float(changed)/high_samples.samples
	check_result("water_motion_is_local_without_global_flashing",fraction>.01 and fraction<.35,
		{"changed":changed,"samples":high_samples.samples,"fraction":fraction,"seconds":[3.25,7.25]})
	check_result("capture_clock_does_not_advance_main",water.seconds==main_clock)
	clone.set_render_scale(1)
	clone.water.restore_state({"seconds":3.25,"paused":true})
	var low_again: Image=await capture(clone)
	check_result("quality_roundtrip_retains_phase_and_pixels",low_again.get_data()==low.get_data() and clone.water.seconds==3.25)
	fixture.queue_free()
	await tree.process_frame
	# A source-white glint can be brighter than the lit pier. Prove depth with
	# separate pier-only / water-only controls at a glint inside the middle slab.
	var white_probe:=Vector2i(-1,-1)
	for sy: int in range(177,185):
		for x: int in range(560,626):
			if distance(high.get_pixel(x*2+1,(sy+43)*2+1),palette[8])<.5/255.0:
				white_probe=Vector2i(x,sy)
				break
		if white_probe.x>=0:break
	root.set_render_scale(2)
	root.water.restore_state({"seconds":3.25,"paused":true})
	var with_piers: Image=await capture(root)
	var hidden: Array=[]
	for node: MeshInstance3D in root.world.get_node("PortArchitecture").find_children("Pier_*","MeshInstance3D",true,false):
		if node.visible:hidden.append(node);node.visible=false
	var without_piers: Image=await capture(root)
	for node: MeshInstance3D in hidden:node.visible=true
	root.water.visible=false
	var without_water: Image=await capture(root)
	root.water.visible=true
	var target:=Vector2i(white_probe.x*2+1,(white_probe.y+43)*2+1)
	var full_color: Color=with_piers.get_pixelv(target)
	var water_color: Color=without_piers.get_pixelv(target)
	var pier_color: Color=without_water.get_pixelv(target)
	check_result("source_white_glint_is_occluded_by_native_pier",white_probe.x>=0
		and distance(water_color,palette[8])<.5/255.0 and distance(full_color,pier_color)<.025
		and pier_color.a>.999 and distance(full_color,water_color)>.02,
		{"source_point":white_probe,"full":full_color,"water_only":water_color,"pier_only":pier_color})
	root.water.restore_state({"seconds":12.5,"paused":true})
	root._switch_comparison()
	await tree.scene_changed
	var r0: Node=tree.current_scene
	r0._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	check_result("f4_roundtrip_retains_paused_water_phase",root.water.seconds==12.5 and root.water.paused and root.player.paused)
	root.set_render_scale(original_scale)
	root.player.restore_state(original)
	root.water.restore_state(original_water)
	root._set_paused(original["paused"])
	if had_meta:tree.set_meta("port_water_state",original_meta)
	else:tree.remove_meta("port_water_state")
	if tree.has_meta("port_compare_state"):tree.remove_meta("port_compare_state")
	var failed: Array=checks.filter(func(c: Dictionary):return not c["pass"])
	var report: Dictionary={"candidate":"R1/12","checks":checks,"failed":failed,"render_cases":render_cases,
		"qa_source_sha256":get_script().source_code.sha256_text(),
		"water_shader_sha256":FileAccess.get_sha256("res://shaders/harbor_water.gdshader"),
		"water_script_sha256":FileAccess.get_sha256("res://scripts/harbor_water.gd"),
		"note":"Native GPU samples from an isolated water surface; main-scene F2 input and a paused F4 roundtrip are checked separately."}
	var file=FileAccess.open("res://docs/r1_12_water_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases}
