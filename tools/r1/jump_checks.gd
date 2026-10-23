extends RefCounted
## Native jump integration, source-pixel render and real keyboard input checks.

var checks: Array=[]
var render_cases: Array=[]
var input_samples: Dictionary={}
var capture_prefix: String="r1_20"


func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func key(code: Key,pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)


func functional(root: Node,kind: String) -> void:
	var p: Node=root.player
	p.reset_position()
	root._set_paused(true)
	p.paused=false
	var began: bool=p.start_jump()
	p.paused=true
	var ground: Variant=p.position
	check_result(kind+"_jump_starts",began and p.jump_motion.phase=="takeoff" and p.frame_index==0)
	p._tick_jump(.099,false)
	check_result(kind+"_source_takeoff_delay",is_zero_approx(p.jump_motion.height_pixels) and p.frame_index==0)
	p._tick_jump(.001,false)
	p._tick_jump(.25,false)
	check_result(kind+"_ascending_pose_and_height",p.jump_motion.phase=="rising" and absf(p.jump_motion.height_pixels-80.625)<.001 and p.animation_name=="jump")
	var held: Dictionary=p.capture_state()
	p._process(.4)
	p._physics_process(.4)
	check_result(kind+"_pause_holds_height_and_pose",p.capture_state()==held)
	p.step_frame()
	check_result(kind+"_step_advances_jump_one_physics_tick",absf(p.jump_motion.elapsed-held["jump"]["elapsed"]-1.0/60.0)<.000001 and p.paused)
	p.restore_state(held)
	p._tick_jump(.25,false)
	check_result(kind+"_apex_and_ground_point",absf(p.jump_motion.height_pixels-107.5)<.001 and p.position.distance_to(ground)<.0001)
	if kind=="R1":
		var camera: Camera3D=root.world.get_node("Camera")
		var projected: float=(camera.unproject_position(p.position).y-camera.unproject_position(p.position+Vector3.UP*p.height_above_ground).y)/root.render_scale
		var shadow: Node3D=p.get_node("ContactShadow")
		check_result("R1_projected_lift_matches_r0_pixels",absf(projected-107.5)<.001,
			{"projected_pixels":projected,"world_up_metres":p.height_above_ground})
		check_result("R1_shadow_stays_on_ground_and_fades",absf(shadow.global_position.y-.015)<.001
			and absf(shadow.scale.x-.7)<.001 and is_equal_approx(shadow.get_instance_shader_parameter("height_ratio"),1.0))
	else:
		check_result("R0_visual_lifts_above_ground_point",absf(p.visual.position.y+107.5)<.001)
	p.next_attack="attack2"
	p.paused=false
	p.attack()
	p.paused=true
	check_result(kind+"_air_attack_uses_source_clip",p.animation_name=="jumpattack" and p.frame_index==0 and p.next_attack=="attack2")
	var started: float=p.jump_motion.air_attack_started
	p._tick_jump(.15,false)
	p.paused=false
	p.attack()
	p.paused=true
	check_result(kind+"_one_air_attack_does_not_restart_or_advance_ground_queue",p.jump_motion.air_attack_started==started and p.next_attack=="attack2")
	p._tick_jump(.3,false)
	check_result(kind+"_air_attack_returns_to_fall_without_landing",p.animation_name=="jump" and p.jump_motion.phase=="falling" and p.jump_motion.height_pixels>0.0)
	p.free_control()
	check_result(kind+"_escape_keeps_flight",p.jump_motion.is_active() and p.jump_motion.height_pixels>0.0)
	p._tick_jump(.05,false)
	check_result(kind+"_landing_uses_source_final_pose",p.jump_motion.phase=="landing" and p.frame_index==15 and is_zero_approx(p.jump_motion.height_pixels))
	p._tick_jump(.05,false)
	check_result(kind+"_lands_without_source_hold_delay",not p.jump_motion.is_active() and p.animation_name=="stay")
	p.paused=false
	p.start_jump()
	p._tick_jump(.35,false)
	root.preview_controls._popup_opened()
	var before: Variant=p.position
	var time_before: float=p.jump_motion.elapsed
	Input.action_press("move_right")
	p._physics_process(1.0/60.0)
	Input.action_release("move_right")
	check_result(kind+"_menu_blocks_ground_input_but_flight_continues",p.position.distance_to(before)<.0001
		and p.jump_motion.elapsed>time_before and p.animation_name=="jump")
	root.preview_controls._popup_closed()
	p.paused=true
	p.preview("jump")
	check_result(kind+"_raw_preview_keeps_source_hold_and_resets_height",not p.jump_motion.is_active()
		and p._animations["jump"]["frames"][7]["duration_ms"]==10000)
	p.paused=false
	Input.action_press("run")
	p.start_jump()
	Input.action_release("run")
	p.paused=true
	check_result(kind+"_run_jump_captures_launch_speed",absf(p.jump_motion.travel_speed-180.5)<.001)
	p.preview("jump")


func rendered_lift(root: Node,kind: String,scale: int=1) -> void:
	var p: Node=root.player
	p.reset_position()
	if kind=="R1":
		root.set_render_scale(scale)
		p.position=p.source_to_world(Vector2(460,295))
	else:
		p.position=Vector2(460,295)
	p.start_jump()
	root._set_paused(true)
	p._tick_jump(.35,false)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var actual: Image
	var foot: Vector2
	var transform:=Transform2D.IDENTITY
	if kind=="R1":
		actual=root.render_viewport.get_texture().get_image()
		foot=root.world.get_node("Camera").unproject_position(p.position+Vector3.UP*p.height_above_ground)/float(scale)
		transform=Transform2D(Vector2(scale,0),Vector2(0,scale),Vector2.ZERO)
	else:
		# Read the raw 2D viewport before the window's nearest-neighbor upscale,
		# matching the R1 native-viewport comparison above.
		actual=root.render_viewport.get_texture().get_image()
		foot=p.position+Vector2(-root.framing.offset_x,43-root.framing.offset_y-p.jump_motion.height_pixels)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_r1.json"))
	var frame: Dictionary=data["animations"][p.animation_name]["frames"][p.frame_index]
	var source:=Image.new()
	source.load_png_from_buffer(FileAccess.get_file_as_bytes(frame["texture"]))
	var anchor:=Vector2(data["foot_anchor"][0],data["foot_anchor"][1])
	var samples:=0
	var matches:=0
	var max_delta:=0.0
	for y in range(1,source.get_height()-1,3):
		for x in range(1,source.get_width()-1,3):
			var opaque:=true
			for yy in range(-1,2):
				for xx in range(-1,2):
					if source.get_pixel(x+xx,y+yy).a<.999:
						opaque=false
			if not opaque:
				continue
			var point:=Vector2i(transform*(foot+Vector2(x+.5,y+.5)-anchor))
			var a:=actual.get_pixelv(point)
			var b:=source.get_pixel(x,y)
			var delta:=Vector3(a.r,a.g,a.b).distance_to(Vector3(b.r,b.g,b.b))
			samples+=1
			max_delta=maxf(max_delta,delta)
			if delta<.025:
				matches+=1
	var result: Dictionary={"scene":kind,"render_scale":scale,"samples":samples,"matching":matches,
		"height_pixels":p.jump_motion.height_pixels,"max_rgb_distance":max_delta}
	render_cases.append(result)
	check_result(kind+"_rendered_airborne_source_pixels_%dx"%scale,samples>100 and matches>=samples*.99,result)
	actual.save_png("res://docs/previews/"+capture_prefix+"_lift_%s_%dx.png"%[kind,scale])


func actual_input(root: Node,kind: String) -> void:
	var tree: SceneTree=root.get_tree()
	var p: Node=root.player
	p.reset_position()
	root._set_paused(false)
	var rows: Array=[]
	key(KEY_RIGHT,true)
	key(KEY_SPACE,true)
	for index: int in range(95):
		await tree.physics_frame
		if index==18:
			key(KEY_X,true)
		if index==19:
			key(KEY_X,false)
		if index==45:
			key(KEY_RIGHT,false)
		rows.append({"physics_frame":index,"phase":p.jump_motion.phase,"height":p.jump_motion.height_pixels,
			"action":p.animation_name,"next_attack":p.next_attack})
	key(KEY_SPACE,false)
	key(KEY_RIGHT,false)
	key(KEY_X,false)
	var air_seen: bool=rows.any(func(row: Dictionary) -> bool:return row["action"]=="jumpattack")
	var land_seen: bool=rows.any(func(row: Dictionary) -> bool:return row["phase"]=="landing")
	var starts:=0
	var last: String="grounded"
	var peak:=0.0
	for row: Dictionary in rows:
		if row["phase"]=="takeoff" and last=="grounded":
			starts+=1
		last=row["phase"]
		peak=maxf(peak,row["height"])
	check_result(kind+"_actual_space_x_and_release_land",air_seen and land_seen and peak>100
		and not p.jump_motion.is_active() and p.animation_name=="stay",{"peak_height":peak,"jump_starts":starts})
	check_result(kind+"_holding_space_does_not_auto_jump",starts==1)
	check_result(kind+"_actual_air_attack_does_not_advance_ground_chain",p.next_attack=="attack1")
	var point: Vector2=p.world_to_source(p.position) if kind=="R1" else p.position
	check_result(kind+"_actual_air_control_moves_ground_point",point.x>480 and point.x<540 and absf(point.y-320)<.01,{"source_position":point})
	input_samples[kind]=rows
	key(KEY_RIGHT,true)
	for _index: int in range(12):
		await tree.physics_frame
	key(KEY_RIGHT,false)
	var after_walk: Vector2=p.world_to_source(p.position) if kind=="R1" else p.position
	check_result(kind+"_ground_movement_uses_fixed_physics_step",after_walk.x-point.x>17 and after_walk.x-point.x<23,
		{"twelve_tick_distance":after_walk.x-point.x})
	root._set_paused(true)


func run(root: Node,candidate: String="R1/20") -> Dictionary:
	capture_prefix=candidate.to_lower().replace("/","_")
	var tree: SceneTree=root.get_tree()
	var original: Dictionary=root.player.capture_state()
	var original_scale: int=root.render_scale
	functional(root,"R1")
	await rendered_lift(root,"R1",1)
	await rendered_lift(root,"R1",2)
	await actual_input(root,"R1")
	root.player.reset_position()
	root.player.start_jump()
	root._set_paused(true)
	root.player._tick_jump(.35,false)
	root.player.paused=false
	root.player.attack()
	root.player.paused=true
	root.player._tick_jump(.13,false)
	var expected: Dictionary=root.player.capture_state()
	var expected_height: float=root.player.jump_motion.height_pixels
	root._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	check_result("r1_to_r0_preserves_air_attack_and_height",root.player.capture_state()==expected
		and absf(root.player.jump_motion.height_pixels-expected_height)<.001)
	functional(root,"R0")
	await rendered_lift(root,"R0")
	await actual_input(root,"R0")
	root.player.reset_position()
	root.player.start_jump()
	root._set_paused(true)
	root.player._tick_jump(.42,false)
	expected=root.player.capture_state()
	expected_height=root.player.jump_motion.height_pixels
	root._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	check_result("r0_to_r1_preserves_air_phase_and_height",root.player.capture_state()==expected
		and absf(root.player.jump_motion.height_pixels-expected_height)<.001)
	root.set_render_scale(original_scale)
	root.player.restore_state(original)
	root._set_paused(original["paused"])
	if tree.has_meta("port_compare_state"):
		tree.remove_meta("port_compare_state")
	var failed:=0
	for item: Dictionary in checks:
		if not item["pass"]:
			failed+=1
	var report: Dictionary={"candidate":candidate,"checks":checks,"failed":failed,
		"render_cases":render_cases,"actual_keyboard_samples":input_samples,
		"qa_source_sha256":get_script().source_code.sha256_text(),
		"jump_source_sha256":FileAccess.get_sha256("res://scripts/source_jump.gd"),
		"motion_data_sha256":FileAccess.get_sha256("res://data/swordman_motion.json"),
		"notes":["Motion is a documented mapping from source values and pose timing, not a recovered engine physics implementation.",
			"CharacterBody3D represents ground navigation. Visual height and ground shadow are independent.",
			"Actual keyboard events are injected through Godot Input.parse_input_event and observed for 95 physics frames in each scene."]}
	var out:=FileAccess.open("res://docs/"+capture_prefix+"_jump_checks.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	out.close()
	return {"failed":failed,"checks":checks,"render_case_count":render_cases.size(),
		"failed_render_cases":checks.filter(func(item: Dictionary) -> bool:return not item["pass"])}
