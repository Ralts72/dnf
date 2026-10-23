extends RefCounted
## Compare every source pose and facing with real R0/R1 rendered pixels.

var checks: Array=[]
var render_cases: Array=[]
var diagnostics_saved: int=0


func check_result(label: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":label,"pass":passed,"details":details})


func color_distance(a: Color,b: Color) -> float:
	return Vector3(a.r,a.g,a.b).distance_to(Vector3(b.r,b.g,b.b))


func opaque_interior(image: Image,point: Vector2i) -> bool:
	if image.is_compressed():
		return false
	for yy in range(-1,2):
		for xx in range(-1,2):
			if image.get_pixelv(point+Vector2i(xx,yy)).a<.999:
				return false
	return true


func render_all(root: Node,kind: String,native_scale: int=1) -> void:
	var p: Node=root.player
	var previous_effects: bool=p.action_effects.enabled
	p.action_effects.enabled=false
	var r1: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_r1.json"))
	var anchor:=Vector2(r1["foot_anchor"][0],r1["foot_anchor"][1])
	var world_position:=Vector2(460,295)
	root._set_paused(true)
	if kind=="R1":
		root.set_render_scale(native_scale)
		p.position=p.source_to_world(world_position)
	else:
		p.position=world_position
	for action: String in r1["animations"]:
		p.preview(action)
		var frames: Array=r1["animations"][action]["frames"]
		for frame_index: int in range(frames.size()):
			p.frame_index=frame_index
			p.elapsed_ms=0.0
			p._apply_frame()
			# Compare to the original PNG bytes, never a possibly lossy imported
			# texture: that would let the import's own color errors pass unnoticed.
			var source:=Image.new()
			var decode_error: int=source.load_png_from_buffer(FileAccess.get_file_as_bytes(frames[frame_index]["texture"]))
			if decode_error!=OK:
				check_result("source_png_decodes",false,{"texture":frames[frame_index]["texture"],"error":decode_error})
				return
			for facing: int in [1,-1]:
				p.facing=facing
				if kind=="R1":
					p._update_sprite_transform()
				else:
					p._update_visual()
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var actual: Image
				var foot: Vector2
				var screen_transform:=Transform2D.IDENTITY
				if kind=="R1":
					actual=root.render_viewport.get_texture().get_image()
					foot=root.world.get_node("Camera").unproject_position(p.position)/float(native_scale)
					screen_transform=Transform2D(Vector2(native_scale,0),Vector2(0,native_scale),Vector2.ZERO)
				else:
					actual=root.get_viewport().get_texture().get_image()
					foot=world_position+Vector2(32-root.framing.offset_x,105-root.framing.offset_y)
					# Window's final transform also includes its embedded-screen offset.
					# The captured viewport image contains only its render stretch.
					screen_transform=root.get_viewport().get_stretch_transform()
				var samples:=0
				var matching:=0
				var clipped:=0
				var max_delta:=0.0
				for y in range(1,source.get_height()-1,4):
					for x in range(1,source.get_width()-1,4):
						var pixel:=Vector2i(x,y)
						if not opaque_interior(source,pixel):
							continue
						var offset: Vector2=Vector2(x+.5,y+.5)-anchor
						offset.x*=facing
						var physical: Vector2=screen_transform*(foot+offset)
						var target:=Vector2i(floori(physical.x),floori(physical.y))
						if not Rect2i(Vector2i.ZERO,actual.get_size()).has_point(target):
							clipped+=1
							continue
						var delta:=color_distance(source.get_pixelv(pixel),actual.get_pixelv(target))
						samples+=1
						max_delta=maxf(max_delta,delta)
						if delta<.025:
							matching+=1
				var passed: bool=samples>30 and matching>=samples*.99 and clipped==0
				var result: Dictionary={"scene":kind,"render_scale":native_scale if kind=="R1" else 0,"action":action,"frame":frame_index,
					"img_frame":frames[frame_index]["img_frame"],"facing":facing,"samples":samples,
					"matching":matching,"clipped":clipped,"max_rgb_distance":max_delta,"pass":passed}
				render_cases.append(result)
				if not passed and diagnostics_saved<8:
					actual.save_png("res://work/pose_failure_%s_%dx_%s_%d_%d.png"%[kind,native_scale,action,frame_index,facing])
					diagnostics_saved+=1

	p.action_effects.enabled=previous_effects
	p.action_effects.sync()


func functional_checks(root: Node,kind: String) -> void:
	var p: Node=root.player
	p.reset_position()
	var sequence: Array=[]
	for _i in range(4):
		p.attack()
		sequence.append(p.animation_name)
		var duration:=0.0
		for frame: Dictionary in p._animations[p.animation_name]["frames"]:
			duration+=frame["duration_ms"]
		p._process((duration+.001)/1000.0)
	check_result(kind+"_three_attack_sequence",sequence==["attack1","attack2","attack3","attack1"],{"sequence":sequence})
	p.free_control()
	p.ui_input_blocked=true
	p.next_attack="attack1"
	p.attack()
	check_result(kind+"_ui_focus_blocks_attack_without_advancing_queue",p.animation_name=="stay" and not p._one_shot and p.next_attack=="attack1")
	p.ui_input_blocked=false
	p.perform("missing_action")
	check_result(kind+"_unknown_action_does_not_lock_control",not p._one_shot and p.animation_name=="stay")
	p.paused=false
	p.preview("jump")
	p.frame_index=14
	p.elapsed_ms=0.0
	p._apply_frame()
	p._process(9.999)
	var holds: bool=p.frame_index==14
	p._process(.002)
	check_result(kind+"_long_source_hold_preserved",holds and p.frame_index==15,
		{"hold_ms":p._animations["jump"]["frames"][14]["duration_ms"]})
	root._set_paused(false)
	p.preview("jump")
	p.frame_index=14
	root.preview_controls.sync()
	root.preview_controls._select_action(1)
	check_result(kind+"_clip_selection_does_not_pause_on_slider_clamp",not p.paused and p.animation_name=="attack3" and p.frame_index==0)
	root.preview_controls._select_action(2)
	root.preview_controls._scrub(7)
	check_result(kind+"_scrub_pauses_and_locates_long_frame",p.paused and p.frame_index==7
		and is_zero_approx(p.elapsed_ms) and p.current_frame()["duration_ms"]==10000)
	var before: Dictionary=p.capture_state()
	root.preview_controls.turn_around()
	var after: Dictionary=p.capture_state()
	check_result(kind+"_turn_retains_pose",after["facing"]==-before["facing"]
		and after["frame"]==before["frame"] and after["elapsed_ms"]==before["elapsed_ms"] and after["paused"])


func run(root: Node,candidate: String="R1/20") -> Dictionary:
	var prefix: String=candidate.to_lower().replace("/","_")
	var tree: SceneTree=root.get_tree()
	var original: Dictionary=root.player.capture_state()
	var original_scale: int=root.render_scale
	functional_checks(root,"R1")
	await render_all(root,"R1",1)
	await render_all(root,"R1",2)
	var p: Node=root.player
	p.reset_position()
	p.next_attack="attack3"
	p.attack()
	p._process(.11)
	root._set_paused(true)
	var expected: Dictionary=p.capture_state()
	root._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	check_result("r1_to_r0_preserves_attack_queue_and_one_shot",root.player.capture_state()==expected)
	functional_checks(root,"R0")
	await render_all(root,"R0")
	root.player.next_attack="attack2"
	root._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	check_result("r0_to_r1_preserves_next_attack",root.player.next_attack=="attack2")
	root.set_render_scale(original_scale)
	root.player.restore_state(original)
	root._set_paused(original["paused"])
	if tree.has_meta("port_compare_state"):
		tree.remove_meta("port_compare_state")
	var failed_cases: Array=render_cases.filter(func(item: Dictionary) -> bool:return not item["pass"])
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_r1.json"))
	var expected_cases: int=0
	for clip: Dictionary in data["animations"].values():
		expected_cases+=clip["frames"].size()*6
	check_result("all_source_frames_and_facings_match_rendered_pixels",failed_cases.is_empty() and render_cases.size()==expected_cases,
		{"cases":render_cases.size(),"expected_cases":expected_cases,"failed_cases":failed_cases.size()})
	var failed:=0
	for item: Dictionary in checks:
		if not item["pass"]:
			failed+=1
	var report: Dictionary={"candidate":candidate,"platform":"macOS","checks":checks,"failed":failed,
		"render_cases":render_cases,"failed_render_cases":failed_cases.size(),
		"qa_source_sha256":get_script().source_code.sha256_text(),
		"source_data_sha256":FileAccess.get_sha256("res://data/swordman_r0.json"),
		"derived_data_sha256":FileAccess.get_sha256("res://data/swordman_r1.json"),
		"notes":["All 14 raw clips, all 92 frames and both facings are compared with optional visual effects disabled in R0 and both R1 render qualities.",
			"Opaque source-art interior samples are compared against actual rendered pixels at the foot-anchored location.",
			"Jump, guard, damage and down remain raw source-pose previews; source holds are not a movement state machine.",
			"UI signal-path checks here supplement the separately recorded actual keyboard and pointer input."]}
	var out:=FileAccess.open("res://docs/"+prefix+"_pose_checks.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	out.close()
	return {"failed":failed,"checks":checks,"render_case_count":render_cases.size(),
		"failed_render_cases":failed_cases.size(),"first_failures":failed_cases.slice(0,8)}
