extends RefCounted
var capture_prefix: String="r1_20"
## Inspect source-track boundaries, real input, scene transfer and native pixels.

var checks: Array=[]
var render_cases: Array=[]
var raw_images: Dictionary={}
const TIMES: Array[float]=[390,450,510,630,690,750,810,870]


func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func key(code: Key,pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)


func place(p: Node,time_ms: float) -> void:
	p.preview("hopsmash")
	var remaining: float=time_ms
	for i: int in range(p._animations["hopsmash"]["frames"].size()):
		var duration: float=p._animations["hopsmash"]["frames"][i]["duration_ms"]
		if remaining<duration:
			p.frame_index=i
			p.elapsed_ms=remaining
			break
		remaining-=duration
	p._apply_frame()
	if p is Node3D:p._update_sprite_transform()
	else:p._update_visual()


func expected_frames(p: Node,time_ms: float) -> Array:
	var selected: Array=[]
	for track: Dictionary in p.action_effects.actions["hopsmash"]:
		for frame: Dictionary in track["frames"]:
			if frame["texture"]!=null and time_ms>=frame["start_ms"] and time_ms<frame["start_ms"]+frame["duration_ms"]:
				selected.append(frame)
	return selected


func texture_rgba(p: Node) -> void:
	for path: String in p.action_effects.textures:
		var source:=Image.new()
		source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		source.convert(Image.FORMAT_RGBA8)
		raw_images[path]=source
		var actual: Image=p.action_effects.textures[path].get_image()
		var compressed: bool=actual.is_compressed()
		if compressed:actual.decompress()
		actual.convert(Image.FORMAT_RGBA8)
		check_result("imported_fx_rgba_"+path.get_base_dir().get_file()+"_"+path.get_file(),not compressed
			and actual.get_size()==source.get_size() and actual.get_data()==source.get_data(),
			{"path":path,"size":source.get_size(),"rgba_pixels":source.get_width()*source.get_height()})


func functional(root: Node,kind: String) -> void:
	var p: Node=root.player
	root._set_paused(true)
	p.action_effects.enabled=true
	var boundary_rows: Array=[]
	for time_ms: float in [0,359.99,360,419.99,420,479.99,480,539.99,540,599.99,600,660,720,780,840,899.99]:
		place(p,time_ms)
		var expected: Array=expected_frames(p,time_ms).map(func(f: Dictionary):return f["texture"])
		var actual: Array=p.action_effects.active_frames.map(func(f: Dictionary):return f["texture"])
		boundary_rows.append({"ms":time_ms,"expected":expected,"actual":actual,"pass":expected==actual})
	check_result(kind+"_all_source_delay_and_frame_boundaries",boundary_rows.all(func(r: Dictionary):return r.pass),{"rows":boundary_rows})
	place(p,450)
	var held: Dictionary=p.capture_state()
	var fx: Array=p.action_effects.active_frames.duplicate(true)
	p._process(.4)
	check_result(kind+"_pause_freezes_pose_and_fx",held==p.capture_state() and fx==p.action_effects.active_frames)
	root.preview_controls.effects_toggle.button_pressed=false
	check_result(kind+"_checkbox_hides_fx_without_changing_pose",p.action_effects.active_frames.is_empty() and p.capture_state()==held)
	key(KEY_F10,true);key(KEY_F10,false)
	await root.get_tree().process_frame
	check_result(kind+"_F10_restores_same_effect_frame",p.action_effects.active_frames==fx and p.capture_state()==held
		and root.preview_controls.effects_toggle.button_pressed)
	p.step_frame()
	check_result(kind+"_single_step_uses_pose_time",p.frame_index==4 and is_equal_approx(p.action_effects.pose_time_ms(),600.0)
		and p.action_effects.active_frames.size()==1 and p.action_effects.active_frames[0]["start_ms"]==600)
	p.paused=false
	p.preview("hopsmash")
	p._process(.9)
	p.paused=true
	check_result(kind+"_loop_wrap_clears_previous_effects",p.frame_index==0 and p.action_effects.active_frames.is_empty())
	p.paused=false
	p.perform("hopsmash")
	p._process(.901)
	p.paused=true
	check_result(kind+"_one_shot_returns_to_idle_without_fx",p.animation_name=="stay" and not p._one_shot and p.action_effects.active_frames.is_empty())
	p.reset_position()
	root._set_paused(false)
	key(KEY_Q,true);key(KEY_Q,false)
	var until: int=Time.get_ticks_msec()+1800
	while p.action_effects.active_frames.size()!=2 and Time.get_ticks_msec()<until:
		await root.get_tree().process_frame
	root._set_paused(true)
	check_result(kind+"_real_Q_runs_source_tracks",p.animation_name=="hopsmash" and p._one_shot
		and p.action_effects.active_frames.size()==2,{"pose_ms":p.action_effects.pose_time_ms(),"active":p.action_effects.active_frames})
	p.preview("stay")
	check_result(kind+"_other_actions_hide_effects",p.action_effects.active_frames.is_empty())
	check_result(kind+"_toggle_inside_footer_without_help_overlap",root.get_node("Interface/EffectsToggle").get_global_rect().end.x<=928
		and root.get_node("Interface/EffectsToggle").get_global_rect().end.y<=540
		and root.get_node("Interface/Help").get_global_rect().end.x<root.get_node("Interface/EffectsToggle").get_global_rect().position.x)


func rendered(root: Node,kind: String,scale: int=1) -> void:
	var p: Node=root.player
	root._set_paused(true)
	if kind=="R1":
		root.set_render_scale(scale)
		p.position=p.source_to_world(Vector2(460,295))
	else:p.position=Vector2(460,295)
	for time_ms: float in TIMES:
		for facing: int in [1,-1]:
			p.facing=facing
			place(p,time_ms)
			var frames: Array=expected_frames(p,time_ms)
			p.action_effects.enabled=false
			p.action_effects.sync()
			for _i: int in 3:await RenderingServer.frame_post_draw
			var base: Image=(root.render_viewport if kind=="R1" else root.get_viewport()).get_texture().get_image()
			p.action_effects.enabled=true
			p.action_effects.sync()
			for _i: int in 3:await RenderingServer.frame_post_draw
			var actual: Image=(root.render_viewport if kind=="R1" else root.get_viewport()).get_texture().get_image()
			var foot: Vector2
			var transform:=Transform2D.IDENTITY
			if kind=="R1":
				foot=root.world.get_node("Camera").unproject_position(p.position)/float(scale)
				transform=Transform2D(Vector2(scale,0),Vector2(0,scale),Vector2.ZERO)
			else:
				foot=p.position+Vector2(32-root.framing.offset_x,105-root.framing.offset_y)
				transform=root.get_viewport().get_stretch_transform()
			var samples: int=0
			var matches: int=0
			var maximum: float=0
			var changed: int=0
			var bad: Array=[]
			for frame: Dictionary in frames:
				var source: Image=raw_images[frame["texture"]]
				var offset:=Vector2(frame["offset"][0],frame["offset"][1])
				for y: int in range(1,source.get_height()-1,3):
					for x: int in range(1,source.get_width()-1,3):
						var color: Color=source.get_pixel(x,y)
						if color.a<.05 or maxf(color.r,maxf(color.g,color.b))<.2:continue
						var local: Vector2=offset+Vector2(x+.5,y+.5)
						var pixel:=Vector2i(transform*(foot+Vector2(local.x*facing,local.y)))
						var before: Color=base.get_pixelv(pixel)
						var expected: Color=before.srgb_to_linear() if kind=="R1" else before
						for other: Dictionary in frames:
							var xy:=Vector2i((local-Vector2(other["offset"][0],other["offset"][1])).floor())
							var image: Image=raw_images[other["texture"]]
							if not Rect2i(Vector2i.ZERO,image.get_size()).has_point(xy):continue
							var c: Color=image.get_pixelv(xy)
							var value: Color=c.srgb_to_linear() if kind=="R1" else c
							expected.r+=value.r*c.a;expected.g+=value.g*c.a;expected.b+=value.b*c.a
						expected=expected.clamp()
						if kind=="R1":expected=expected.linear_to_srgb()
						var observed: Color=actual.get_pixelv(pixel)
						var difference: float=maxf(absf(observed.r-expected.r),maxf(absf(observed.g-expected.g),absf(observed.b-expected.b)))
						maximum=maxf(maximum,difference)
						samples+=1
						if difference<2.5/255.0:matches+=1
						elif bad.size()<12:bad.append({"local":local,"pixel":pixel,"expected":expected,"actual":observed,"source":color,"before":before})
						if Vector3(observed.r-before.r,observed.g-before.g,observed.b-before.b).length()>.01:changed+=1
			var row: Dictionary={"scene":kind,"scale":scale,"time_ms":time_ms,"facing":facing,"samples":samples,
				"matching":matches,"changed":changed,"max_rgb_distance":maximum,"bad":bad,"pass":samples>10 and matches==samples and changed>5}
			render_cases.append(row)
			if kind=="R1" and scale==2 and time_ms==450 and facing==1:
				actual.save_png("res://docs/previews/"+capture_prefix+"_effect_scene.png")
	check_result(kind+"_native_additive_pixels_"+str(scale),render_cases.filter(func(r: Dictionary):return r.scene==kind and r.scale==scale).all(func(r: Dictionary):return r.pass))


func foreground_depth(root: Node) -> void:
	var p: Node=root.player
	root.set_render_scale(2)
	p.position=p.source_to_world(Vector2(460,295))
	p.facing=1
	place(p,450)
	var blocker:=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	mesh.size=Vector3(.9,1.1,.08)
	blocker.mesh=mesh
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(.02,.6,.02)
	blocker.material_override=material
	root.world.add_child(blocker)
	blocker.position=p.position+Vector3(1.5,1.3,.4)
	p.action_effects.enabled=false;p.action_effects.sync()
	for _i: int in 3:await RenderingServer.frame_post_draw
	var base: Image=root.render_viewport.get_texture().get_image()
	p.action_effects.enabled=true;p.action_effects.sync()
	for _i: int in 3:await RenderingServer.frame_post_draw
	var actual: Image=root.render_viewport.get_texture().get_image()
	var center: Vector2=root.world.get_node("Camera").unproject_position(blocker.position)
	var mask: int=0
	var matching: int=0
	for y: int in range(int(center.y)-70,int(center.y)+70):
		for x: int in range(int(center.x)-60,int(center.x)+60):
			var before: Color=base.get_pixel(x,y)
			if before.g>.6 and before.r<.3 and before.b<.3:
				mask+=1
				var c: Color=actual.get_pixel(x,y)
				if Vector3(c.r-before.r,c.g-before.g,c.b-before.b).length()<.005:matching+=1
	var source_overlap: int=0
	var foot: Vector2=root.world.get_node("Camera").unproject_position(p.position)/2.0
	for frame: Dictionary in expected_frames(p,450):
		var image: Image=raw_images[frame["texture"]]
		for y: int in range(1,image.get_height()-1,3):
			for x: int in range(1,image.get_width()-1,3):
				var c: Color=image.get_pixel(x,y)
				if c.a<.5 or maxf(c.r,maxf(c.g,c.b))<.4:continue
				var pixel:=Vector2i((foot+Vector2(frame["offset"][0]+x+.5,frame["offset"][1]+y+.5))*2)
				var before: Color=base.get_pixelv(pixel)
				if before.g>.6 and before.r<.3 and before.b<.3:source_overlap+=1
	check_result("native_foreground_mesh_occludes_additive_fx",mask>1000 and matching==mask and source_overlap>30,
		{"opaque_green_pixels":mask,"unchanged_pixels":matching,"independent_source_effect_overlap_samples":source_overlap})
	blocker.queue_free()
	await root.get_tree().process_frame


func run(root: Node,candidate: String="R1/20") -> Dictionary:
	capture_prefix=candidate.to_lower().replace("/","_")
	var tree: SceneTree=root.get_tree()
	var original: Dictionary=root.player.capture_state()
	var original_scale: int=root.render_scale
	var original_enabled: bool=root.player.action_effects.enabled
	texture_rgba(root.player)
	await functional(root,"R1")
	await rendered(root,"R1",1)
	await rendered(root,"R1",2)
	await foreground_depth(root)
	place(root.player,450)
	var expected: Dictionary=root.player.capture_state()
	var expected_fx: Array=root.player.action_effects.active_frames.duplicate(true)
	root._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	check_result("F4_to_R0_retains_pose_and_effect_frames",root.player.capture_state()==expected and root.player.action_effects.active_frames==expected_fx)
	await functional(root,"R0")
	await rendered(root,"R0")
	place(root.player,510)
	root.preview_controls._select_effects(false)
	expected=root.player.capture_state()
	root._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	check_result("F4_back_retains_disabled_toggle_and_pose",root.player.capture_state()==expected and not root.player.action_effects.enabled
		and not root.preview_controls.effects_toggle.button_pressed and root.player.action_effects.active_frames.is_empty())
	root.preview_controls._select_effects(original_enabled)
	root.player.restore_state(original)
	root.set_render_scale(original_scale)
	root._set_paused(original["paused"])
	if tree.has_meta("port_compare_state"):tree.remove_meta("port_compare_state")
	var failed: Array=checks.filter(func(c: Dictionary):return not c.pass)
	var report: Dictionary={"candidate":candidate,"checks":checks,"failed":failed,"render_cases":render_cases,
		"qa_source_sha256":get_script().source_code.sha256_text(),"effect_data_sha256":FileAccess.get_sha256("res://data/swordman_effects.json"),
		"notes":["Nine imported RGBA textures are compared with unmodified source crops.",
			"Expected native additive pixels are computed from PNG bytes and a same-pose no-effect frame, including overlapping tracks.",
			"R1 uses native linear-light additive blending; R0 canvas uses native display-space addition. Original engine color space is unverified.",
			"Checks cover source delays, real Q/F10 input, pause/step/loop/finish and F4 transfer; no skill movement or damage semantics are added."]}
	var out:=FileAccess.open("res://docs/"+candidate.to_lower().replace("/","_")+"_effect_checks.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "));out.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases.size(),"failed_render_cases":render_cases.filter(func(r: Dictionary):return not r.pass)}
