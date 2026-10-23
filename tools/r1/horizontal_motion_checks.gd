extends RefCounted
## Finite real-key framing route; callback cadence is not a hardware benchmark.

var checks: Array = []
var records: Array = []
var render_cases: Array = []
var bounds: Dictionary = {}
var data: Dictionary = {}


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


func offset(main: Node) -> Vector2:
	return Vector2(main.framing.offset_x, main.framing.offset_y)


func sample(main: Node, phase: String, elapsed: float, phase_elapsed: float) -> void:
	var p: Node = main.player
	var is_3d: bool = main.name == "WestCoastR1"
	var ground: Vector2 = p.world_to_source(p.position) if is_3d else p.position
	var foot: Vector2
	var path: String
	if is_3d:
		foot = main.world.get_node("Camera").unproject_position(p.sprite.get_global_transform_interpolated().origin) / float(main.render_scale)
		path = p.sprite.texture.resource_path
	else:
		# This R0 extent is explicitly logical, not a claim about its native
		# interpolated sprite. Static framebuffer checks cover its original pixels.
		foot = p.position + Vector2(-main.framing.offset_x, 43.0-main.framing.offset_y-p.jump_motion.height_pixels)
		path = data.animations[p.animation_name].frames[p.frame_index].texture
	if not bounds.has(path):
		var image := Image.new()
		assert(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK)
		bounds[path] = image.get_used_rect()
	var rect: Rect2i = bounds[path]
	var left: float = float(rect.position.x)-133.0 if p.facing == 1 else 133.0-float(rect.end.x)
	var right: float = float(rect.end.x)-133.0 if p.facing == 1 else 133.0-float(rect.position.x)
	records.append({"phase": phase, "elapsed_s": elapsed, "phase_elapsed_s": phase_elapsed,
		"scene": "R1" if is_3d else "R0", "ground": ground, "camera_x": main.framing.offset_x,
		"camera_y": main.framing.offset_y, "target_x": main.framing.target_x(), "target_y": main.framing.target(),
		"foot": foot, "extent_basis": "native_interpolated_sprite_projection" if is_3d else "logical_R0_position",
		"left_x": foot.x+left, "right_x": foot.x+right,
		"top_y": foot.y+float(rect.position.y)-167.0, "bottom_y": foot.y+float(rect.end.y)-167.0,
		"action": p.animation_name, "frame": p.frame_index, "facing": p.facing,
		"paused": p.paused, "jump_height": p.jump_motion.height_pixels,
		"physics_interpolation": p.is_physics_interpolated_and_enabled()})


func run(main: Node, candidate: String = "R1/29") -> Dictionary:
	var tree: SceneTree = main.get_tree()
	var original: Dictionary = main.player.capture_state()
	var original_scale: int = main.render_scale
	var original_offset: Vector2 = offset(main)
	var original_effects: bool = main.player.action_effects.enabled
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_r1.json"))
	main.preview_controls._select_effects(false)
	main.player.reset_position()
	main.player.position = main.player.source_to_world(Vector2(220, 345))
	main.player.motion_smoothing.reset()
	main._set_paused(false)
	main.framing.advance(0.0, true)
	var phases: Array = [
		{"name": "walk_left_threshold", "seconds": .8, "keys": [KEY_A]},
		{"name": "jump_left_threshold", "seconds": 1.2, "tap": KEY_SPACE},
		{"name": "run_left_edge", "seconds": 1.0, "keys": [KEY_A, KEY_SHIFT]},
		{"name": "left_settle", "seconds": .2},
		{"name": "pause", "seconds": .2, "tap": KEY_F2},
		{"name": "step", "seconds": .15, "tap": KEY_F3},
		{"name": "resume", "seconds": .1, "tap": KEY_F2},
		{"name": "R0_run_from_left", "seconds": 1.4, "keys": [KEY_D, KEY_SHIFT], "switch": true},
		{"name": "R1_run_to_right", "seconds": 3.0, "keys": [KEY_D, KEY_SHIFT], "switch": true},
		{"name": "jump_right_edge", "seconds": 1.2, "tap": KEY_SPACE},
		{"name": "run_toward_center", "seconds": 2.1, "keys": [KEY_A, KEY_SHIFT]},
		{"name": "reset", "seconds": .3, "tap": KEY_R}]
	var started: int = Time.get_ticks_usec()
	for phase: Dictionary in phases:
		for code: Key in [KEY_A, KEY_D, KEY_SHIFT]:
			key(code, false)
		if phase.get("switch", false):
			var state_before: Dictionary = main.player.capture_state()
			var offset_before: Vector2 = offset(main)
			tap(KEY_F4)
			await tree.scene_changed
			main = tree.current_scene
			# Capture synchronously at scene_changed, before motion sampling resumes.
			render_cases.append({"phase": phase.name, "actor_state_retained": main.player.capture_state() == state_before,
				"offset_before": offset_before, "offset_after": offset(main),
				"scene": str(main.name)})
		if phase.has("tap"):
			tap(phase.tap)
		for code: Key in phase.get("keys", []):
			key(code, true)
		var phase_started: int = Time.get_ticks_usec()
		var until: int = phase_started+int(float(phase.seconds)*1000000.0)
		while Time.get_ticks_usec() < until:
			await RenderingServer.frame_post_draw
			var now: int = Time.get_ticks_usec()
			sample(main, phase.name, float(now-started)/1000000.0, float(now-phase_started)/1000000.0)
	var duration: float = float(Time.get_ticks_usec()-started)/1000000.0
	for code: Key in [KEY_A, KEY_D, KEY_SHIFT]:
		key(code, false)
	check_result("actual_route_covers_both_renderers_inside_retained_street", records.any(func(r): return r.scene == "R0")
		and records.any(func(r): return r.scene == "R1") and records.all(func(r): return r.phase == "reset" or (r.ground.x >= 35.99 and r.ground.x <= 852.01 and absf(r.ground.y-345.0) < .001)))
	check_result("source_pose_extents_fit_both_axes_through_route", records.all(func(r): return r.left_x >= 0.0 and r.right_x <= 896.0 and r.top_y >= 0.0 and r.bottom_y <= 404.0),
		{"R1_basis": "Native interpolated sprite projection", "R0_basis": "Logical position; original-pixel native readback is checked separately"})
	check_result("camera_reaches_both_horizontal_limits_at_lower_edge", records.any(func(r): return r.camera_x < -147.9)
		and records.any(func(r): return r.camera_x > 139.9) and records.filter(func(r): return r.phase != "reset").all(func(r): return absf(r.camera_y-37.0) < .001))
	check_result("actual_F4_transfers_actor_and_both_camera_offsets", render_cases.size() == 2 and render_cases.all(func(c): return c.actor_state_retained and c.offset_before.distance_to(c.offset_after) < .001), {"transfers": render_cases})
	var freeze_ok: bool = true
	for phase: String in ["pause", "step"]:
		var rows: Array = records.filter(func(r): return r.phase == phase)
		freeze_ok = freeze_ok and not rows.is_empty()
		if not rows.is_empty():
			for row: Dictionary in rows:
				freeze_ok = freeze_ok and row.paused and row.ground.distance_to(rows[0].ground) < .001 \
					and row.action == rows[0].action and row.frame == rows[0].frame \
					and absf(row.camera_x-row.target_x) < .001 and absf(row.camera_y-row.target_y) < .001
	check_result("F2_F3_hold_ground_and_pose_and_snap_both_camera_axes", freeze_ok)
	var jump_ok: bool = true
	var airborne_samples: Dictionary = {}
	for phase: String in ["jump_left_threshold", "jump_right_edge"]:
		var rows: Array = records.filter(func(r): return r.phase == phase)
		var airborne: Array = rows.filter(func(r): return r.jump_height > 5.0 and r.phase_elapsed_s > .25)
		airborne_samples[phase] = airborne.size()
		jump_ok = jump_ok and airborne.size() > 30 and rows.all(func(r): return r.ground.distance_to(rows[0].ground) < .001)
		jump_ok = jump_ok and airborne.all(func(r): return absf(r.camera_x-r.target_x) < .2 and absf(r.camera_y-37.0) < .001)
	check_result("airborne_height_does_not_change_fixed_ground_camera_target", jump_ok,
		{"airborne_samples_after_settle": airborne_samples, "settle_window_seconds": .25})
	var maximum_step: float = 0.0
	var violations: int = 0
	for i: int in range(1, records.size()):
		var a: Dictionary = records[i-1]
		var b: Dictionary = records[i]
		if a.phase != b.phase or b.phase in ["pause", "step", "reset"]:
			continue
		var distance: float = absf(b.camera_x-a.camera_x)
		maximum_step = maxf(maximum_step, distance)
		if distance > maxf(190.0/60.0+.3, 190.0*(b.elapsed_s-a.elapsed_s)+.3):
			violations += 1
	check_result("moving_horizontal_camera_has_no_large_jumps", violations == 0,
		{"violations": violations, "maximum_step_source_pixels": maximum_step,
		"bound": "max(190/60+0.3,190*render_interval+0.3) source pixels; scene changes, pause/step and R snaps excluded"})
	var last: Dictionary = records[-1]
	check_result("actual_R_resets_ground_and_both_camera_axes", last.ground.distance_to(Vector2(440, 320)) < .001
		and absf(last.camera_x) < .001 and absf(last.camera_y-12.0) < .001)
	main.player.restore_state(original)
	main.set_render_scale(original_scale)
	main._set_paused(original.paused)
	main.preview_controls._select_effects(original_effects)
	main.framing.offset_x = original_offset.x
	main.framing.offset_y = original_offset.y
	main.framing.apply()
	check_result("production_actor_quality_effects_and_offsets_restored_on_R1", main.name == "WestCoastR1" and main.player.capture_state() == original
		and main.render_scale == original_scale and main.player.action_effects.enabled == original_effects and offset(main).distance_to(original_offset) < .001)
	var result: Dictionary = {"candidate": candidate, "checks": checks, "failed": checks.filter(func(c): return not c.pass),
		"duration_seconds": duration, "rendered_rows": records.size(), "records": records, "F4_transfers": render_cases,
		"qa_source_sha256": get_script().source_code.sha256_text(),
		"framing_source_sha256": FileAccess.get_file_as_string("res://scripts/source_framing.gd").sha256_text(),
		"note": "Actual A/D/Shift/Space/F2/F3/F4/R events across both renderers. R1 pose bounds use native interpolated sprite projection and actual selected PNG alpha extents, mirrored for facing. R0 bounds are explicitly logical, not GPU readback. Jump checks allow an initial .25s for existing camera lag to settle. This finite behavior route is not a performance benchmark."}
	var output := FileAccess.open("res://docs/r1_29_horizontal_motion_checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	return {"checks": checks.size(), "failed": result.failed, "rendered_rows": records.size(), "elapsed_seconds": duration}
