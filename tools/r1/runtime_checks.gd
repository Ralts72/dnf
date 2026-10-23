extends RefCounted
## Run in the actual graphical game via the Godot game-eval bridge:
## return await load("res://tools/r1/runtime_checks.gd").new().run(get_tree().current_scene)

var checks: Array = []


func check_result(name: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check":name, "pass":passed, "details":details})


func blue_pixels(image: Image, point: Vector2, scale: float) -> int:
	var count := 0
	for y in range(int(point.y-13*scale),int(point.y+12*scale)):
		for x in range(int(point.x-24*scale),int(point.x+24*scale)):
			var c := image.get_pixel(x,y)
			if c.b > c.r * 1.12 and c.b > c.g * 0.92:
				count += 1
	return count


func run(root: Node,candidate: String="R1/20") -> Dictionary:
	var tree: SceneTree = root.get_tree()
	var p: Node = root.player
	var render_scale: float=float(root.render_scale)
	var architecture: Node = root.world.get_node("PortArchitecture")
	check_result("latest_glb_loaded", architecture.find_children("*Hinge*","",true,false).is_empty()
		and architecture.find_child("Worn_Curved_Coping",true,false).mesh.surface_get_material(0).resource_name == "Plaster_Highlight")
	root._set_paused(true)
	var durations := {"stay":720.0,"move":800.0,"dash":800.0,"attack1":600.0,"attack2":650.0,"hopsmash":900.0}
	for action: String in durations:
		p.preview(action)
		p.paused = false
		var before: int = p.frame_transitions
		p._process((durations[action]+0.001)/1000.0)
		check_result("source_timing_"+action, p.frame_index==0 and p.frame_transitions-before==p._animations[action]["frames"].size(),
			{"duration_ms":durations[action]})
		p.paused = true
	p.preview("attack1")
	p._process(0.5)
	check_result("pause_holds_frame",p.frame_index==0)
	p.step_frame()
	check_result("single_step",p.frame_index==1)
	p.free_control()
	p.paused=false
	p.perform("attack1")
	p._process(0.601)
	check_result("attack_returns_to_idle",p.animation_name=="stay")
	p.paused=true
	p.preview("hopsmash")
	p.step_frame()
	p.step_frame()
	p.facing=-1
	p.position=p.source_to_world(Vector2(525,315))
	p.motion_smoothing.reset()
	p._update_sprite_transform()
	root.framing.advance(0.0,true)
	var projected_native: Vector2=root.world.get_node("Camera").unproject_position(p.position)
	var projected: Vector2=projected_native/render_scale
	var expected_foot:=Vector2(525-root.framing.offset_x,358-root.framing.offset_y)
	check_result("camera_foot_matches_r0",projected.distance_to(expected_foot)<0.02,
		{"projected_logical":projected,"projected_native":projected_native,"expected_logical":expected_foot,"render_scale":render_scale})
	var expected: Dictionary=p.capture_state()
	root._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	var state_2d: Dictionary=root.player.capture_state()
	check_result("r1_to_r0_retains_pose",root.scene_file_path.ends_with("west_coast_r0.tscn")
		and state_2d["position"].distance_to(expected["position"])<0.001
		and state_2d["facing"]==expected["facing"] and state_2d["frame"]==expected["frame"]
		and state_2d["action"]==expected["action"] and state_2d["paused"]==expected["paused"])
	root._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	p=root.player
	var state_3d: Dictionary=p.capture_state()
	check_result("r0_to_r1_retains_pose",root.scene_file_path.ends_with("west_coast_r1.tscn")
		and state_3d["position"].distance_to(expected["position"])<0.001
		and state_3d["facing"]==expected["facing"] and state_3d["frame"]==expected["frame"]
		and state_3d["action"]==expected["action"] and state_3d["paused"]==expected["paused"])

	# Exercise native CharacterBody3D collision, not an emulated movement helper.
	root._set_probe_visible(true)
	p.reset_position()
	root._set_paused(false)
	p.position=Vector3(1.2,0.025,2.45)
	p.motion_smoothing.reset()
	await tree.physics_frame
	await tree.physics_frame
	Input.action_press("move_right")
	await tree.create_timer(1.45).timeout
	Input.action_release("move_right")
	check_result("native_collision_blocks_walkthrough",p.position.x>2.15 and p.position.x<2.32,
		{"position":p.position,"slide_collisions":p.get_slide_collision_count()})
	p.position=Vector3(1.2,0.025,1.87)
	p.motion_smoothing.reset()
	Input.action_press("move_right")
	await tree.create_timer(1.45).timeout
	Input.action_release("move_right")
	check_result("walk_behind_probe_without_collision",p.position.x>3.2,{"position":p.position})
	root._set_paused(true)
	p.preview("stay")
	p.facing=1
	p.position=Vector3(2.99,0.025,2.05)
	p.motion_smoothing.reset()
	p.markers_visible=false
	p._update_sprite_transform()
	var viewport: SubViewport=root.get_node("PortClip/ViewportContainer/Viewport")
	var camera: Camera3D=root.world.get_node("Camera")
	root.framing.advance(0.0,true)
	var foot: Vector2=camera.unproject_position(p.position)
	await RenderingServer.frame_post_draw
	var with_probe: Image=viewport.get_texture().get_image()
	with_probe.save_png("res://docs/previews/r1_occlusion_behind.png")
	var probes: Array=root.world.get_node("PortArchitecture").find_children("Occlusion_Stone*","MeshInstance3D",true,false)
	for probe in probes:
		probe.visible=false
	await RenderingServer.frame_post_draw
	var without_probe: Image=viewport.get_texture().get_image()
	without_probe.save_png("res://docs/previews/r1_occlusion_without_probe.png")
	var count_with:=blue_pixels(with_probe,foot,render_scale)
	var count_without:=blue_pixels(without_probe,foot,render_scale)
	check_result("rendered_probe_occludes_actor_feet",count_without>20 and count_with<count_without*0.6,
		{"blue_pixels_with_probe":count_with,"blue_pixels_without_probe":count_without,"foot":foot})
	for probe in probes:
		probe.visible=true
	p.position.z=3.12
	p._update_sprite_transform()
	p.motion_smoothing.reset()
	root.framing.advance(0.0,true)
	foot=camera.unproject_position(p.position)
	await RenderingServer.frame_post_draw
	var in_front: Image=viewport.get_texture().get_image()
	in_front.save_png("res://docs/previews/r1_occlusion_front.png")
	var front_blue:=blue_pixels(in_front,foot,render_scale)
	check_result("rendered_actor_in_front_remains_visible",front_blue>20,{"blue_pixels":front_blue})

	root._set_probe_visible(false)
	p.reset_position()
	root._set_paused(false)
	tree.remove_meta("port_compare_state")
	var samples: Array=[]
	var start_ms:=Time.get_ticks_msec()
	for i in range(120):
		await tree.process_frame
		if i%15==0:
			samples.append(Engine.get_frames_per_second())
	var duration_ms:=Time.get_ticks_msec()-start_ms
	await RenderingServer.frame_post_draw
	var capture:=root.get_viewport().get_texture().get_image()
	capture.save_png("res://docs/previews/r1_port.png")
	var failed:=0
	for item: Dictionary in checks:
		if not item["pass"]:
			failed+=1
	var report: Dictionary={"candidate":candidate,"platform":"macOS", "godot":Engine.get_version_info()["string"],
		"checks":checks,"failed":failed,"screenshot_size":capture.get_size(),
		"render_viewport":viewport.size,"logical_ui":Vector2i(960,540),"render_scale":render_scale,
		"qa_source_sha256":get_script().source_code.sha256_text(),
		"performance_observation":{"process_frames":120,"elapsed_ms":duration_ms,"fps_samples":samples,
			"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"note":"Short observation in the current editor game window, not a hardware benchmark or Windows validation"}}
	var out:=FileAccess.open("res://docs/r1_runtime_checks.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	out.close()
	var versioned:=FileAccess.open("res://docs/"+candidate.to_lower().replace("/","_")+"_runtime_checks.json",FileAccess.WRITE)
	versioned.store_string(JSON.stringify(report,"  "))
	versioned.close()
	return report
