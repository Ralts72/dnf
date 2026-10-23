extends RefCounted
## Finite real-key camera exercise; render cadence here is not a performance test.

var checks: Array = []
var records: Array = []
var bounds: Dictionary = {}


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tap(code: Key) -> void:
	key(code, true)
	key(code, false)


func check_result(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check": label, "pass": passed, "details": details})


func sample(main: Node, phase: String, elapsed: float) -> void:
	var p: Node = main.player
	var is_3d: bool = main.name == "WestCoastR1"
	var ground: Vector2 = p.world_to_source(p.position) if is_3d else p.position
	var foot: Vector2
	var path: String
	if is_3d:
		foot = main.world.get_node("Camera").unproject_position(p.sprite.get_global_transform_interpolated().origin) / float(main.render_scale)
		path = p.sprite.texture.resource_path
	else:
		foot = p.position + Vector2(-main.framing.offset_x, 43.0 - main.framing.offset_y - p.jump_motion.height_pixels)
		path = "R0:" + p.animation_name + ":" + str(p.frame_index)
	if not bounds.has(path):
		if not is_3d:
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_r1.json"))
			path = data.animations[p.animation_name].frames[p.frame_index].texture
		var image := Image.new()
		assert(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK)
		bounds[("R0:" + p.animation_name + ":" + str(p.frame_index)) if not is_3d else path] = image.get_used_rect()
	var rect: Rect2i = bounds[("R0:" + p.animation_name + ":" + str(p.frame_index)) if not is_3d else path]
	records.append({"phase": phase, "elapsed_s": elapsed, "scene": "R1" if is_3d else "R0", "ground": ground,
		"offset_y": main.framing.offset_y, "target_y": main.framing.target(), "jump_height": p.jump_motion.height_pixels,
		"paused": p.paused, "top_y": foot.y + rect.position.y - 167.0,
		"bottom_y": foot.y + rect.end.y - 167.0, "physics_interpolation": p.is_physics_interpolated_and_enabled()})


func run(main: Node, candidate: String = "R1/28") -> Dictionary:
	var tree: SceneTree = main.get_tree()
	var original: Dictionary = main.player.capture_state()
	var original_scale: int = main.render_scale
	main.player.reset_position()
	main.player.position = main.player.source_to_world(Vector2(440, 345))
	main.player.motion_smoothing.reset()
	main._set_paused(false)
	main.framing.advance(0.0, true)
	var phases: Array = [
		{"name": "walk_up", "seconds": 1.3, "keys": [KEY_W]},
		{"name": "walk_down", "seconds": 1.5, "keys": [KEY_S]},
		{"name": "pause", "seconds": .25, "tap": KEY_F2},
		{"name": "step", "seconds": .2, "tap": KEY_F3},
		{"name": "resume", "seconds": .15, "tap": KEY_F2},
		{"name": "jump_at_bottom", "seconds": 1.3, "tap": KEY_SPACE},
		{"name": "run_up", "seconds": .9, "keys": [KEY_W, KEY_SHIFT]},
		{"name": "run_down", "seconds": 1.1, "keys": [KEY_S, KEY_SHIFT]},
		{"name": "settle", "seconds": .35},
		{"name": "R0_walk_up", "seconds": 1.2, "keys": [KEY_W], "switch": true},
		{"name": "R0_walk_down", "seconds": 1.4, "keys": [KEY_S]},
		{"name": "R1_return", "seconds": .2, "switch": true},
		{"name": "reset", "seconds": .3, "tap": KEY_R}]
	var started: int = Time.get_ticks_usec()
	for phase: Dictionary in phases:
		for code: Key in [KEY_W, KEY_S, KEY_SHIFT]:
			key(code, false)
		if phase.get("switch", false):
			main._switch_comparison()
			await tree.scene_changed
			main = tree.current_scene
		if phase.has("tap"):
			tap(phase.tap)
		for code: Key in phase.get("keys", []):
			key(code, true)
		var until: int = Time.get_ticks_usec() + int(float(phase.seconds) * 1000000.0)
		while Time.get_ticks_usec() < until:
			await RenderingServer.frame_post_draw
			sample(main, phase.name, float(Time.get_ticks_usec() - started) / 1000000.0)
	var duration: float = float(Time.get_ticks_usec() - started) / 1000000.0
	for code: Key in [KEY_W, KEY_S, KEY_SHIFT]:
		key(code, false)
	check_result("real_keys_cover_both_renderers", records.any(func(r): return r.scene == "R0") and records.any(func(r): return r.scene == "R1"))
	check_result("rendered_pose_extents_remain_inside_vertical_view", records.all(func(r): return r.top_y >= 0.0 and r.bottom_y <= 404.0))
	check_result("camera_reaches_both_ends_of_existing_overscan", records.any(func(r): return r.offset_y > 36.9) and records.any(func(r): return r.offset_y < .1))
	var frozen: Array = records.filter(func(r): return r.phase in ["pause", "step"])
	check_result("F2_F3_freeze_ground_and_snap_camera", not frozen.is_empty() and frozen.all(func(r): return r.paused and r.ground.distance_to(frozen[0].ground) < .001 and absf(r.offset_y-r.target_y)<.001))
	var airborne: Array = records.filter(func(r): return r.phase == "jump_at_bottom" and r.jump_height > 5.0)
	check_result("jump_height_does_not_pull_ground_camera", airborne.size() > 50 and airborne.all(func(r): return absf(r.offset_y - 37.0) < .1))
	var steady: Array = records.filter(func(r): return r.phase not in ["pause", "step"])
	check_result("movement_preserves_native_actor_interpolation", steady.all(func(r): return r.physics_interpolation))
	var maximum_step: float = 0.0
	var too_fast: int = 0
	for i: int in range(1, records.size()):
		var a: Dictionary = records[i-1]
		var b: Dictionary = records[i]
		if a.phase != b.phase or b.phase in ["pause", "step", "reset"]:
			continue
		var distance: float = absf(b.offset_y-a.offset_y)
		maximum_step = maxf(maximum_step, distance)
		# R0 samples a 60 Hz logical ground point; allow one normal physics
		# step even when two render callbacks arrive unusually close together.
		if distance > maxf(110.2 / 60.0 + .2, 110.2 * (b.elapsed_s-a.elapsed_s) + .2):
			too_fast += 1
	check_result("moving_camera_has_no_large_jumps", too_fast == 0, {"violations": too_fast, "maximum_step_source_pixels": maximum_step})
	var last: Dictionary = records[-1]
	check_result("actual_R_resets_ground_and_camera", last.ground.distance_to(Vector2(440, 320)) < .001 and absf(last.offset_y-12.0) < .001)
	main.player.restore_state(original)
	main.set_render_scale(original_scale)
	main._set_paused(original.paused)
	main.framing.advance(0.0, true)
	var result: Dictionary = {"candidate": candidate, "checks": checks, "failed": checks.filter(func(c): return not c.pass),
		"duration_seconds": duration, "rendered_rows": records.size(), "records": records,
		"qa_source_sha256": get_script().source_code.sha256_text(),
		"note": "Actual W/S/Shift/Space/F2/F3/F4/R workflow. R1 extents use the native interpolated sprite transform; R0 bounds use logical position with the camera offset. Pixel preservation and R0 native interpolation are checked separately."}
	var output := FileAccess.open("res://docs/r1_28_framing_motion_checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	return {"checks": checks.size(), "failed": result.failed, "rendered_rows": records.size(), "elapsed_seconds": duration}
