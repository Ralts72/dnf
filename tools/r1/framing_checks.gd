extends RefCounted
## Read back both renderers at the legal lower street edge, including raw poses.

var checks: Array = []
var render_cases: Array = []
var images: Dictionary = {}
var sampler = preload("res://tools/r1/pose_checks.gd").new()


func check_result(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check": label, "pass": passed, "details": details})


func render_case(main: Node, action: String, frame: int, sub: int, facing: int, scale: int) -> void:
	var p: Node = main.player
	p.preview(action)
	p.frame_index = frame
	p.elapsed_ms = float(sub) * 100.0 / 3.0
	p.facing = facing
	p._apply_frame()
	var is_3d: bool = main.name == "WestCoastR1"
	if is_3d:
		p._update_sprite_transform()
	else:
		p._update_visual()
	p.motion_smoothing.reset()
	main.framing.advance(0.0, true)
	var path: String
	if is_3d:
		path = p.sprite.texture.resource_path
	else:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_r1.json"))
		path = data.animations[action].frames[frame].texture
	if not images.has(path):
		var source := Image.new()
		assert(source.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK)
		images[path] = source
	var source: Image = images[path]
	for _i: int in 2:
		await RenderingServer.frame_post_draw
	var actual: Image = main.render_viewport.get_texture().get_image()
	var foot: Vector2 = main.world.get_node("Camera").unproject_position(p.position) / float(scale) if is_3d else p.position + Vector2(-main.framing.offset_x, 43.0 - main.framing.offset_y)
	var clipped: int = 0
	var samples: int = 0
	var mismatches: int = 0
	for y: int in source.get_height():
		for x: int in source.get_width():
			if source.get_pixel(x, y).a < .999:
				continue
			var offset := Vector2((float(x) + .5 - 133.0) * facing, float(y) + .5 - 167.0)
			var pixel := Vector2i((foot + offset) * float(scale))
			if not Rect2i(Vector2i.ZERO, actual.get_size()).has_point(pixel):
				clipped += 1
				continue
			if x % 4 != 1 or y % 4 != 1 or x < 1 or y < 1 or x >= 319 or y >= 223 or not sampler.opaque_interior(source, Vector2i(x, y)):
				continue
			samples += 1
			if sampler.color_distance(source.get_pixel(x, y), actual.get_pixelv(pixel)) > .025:
				mismatches += 1
	render_cases.append({"scene": "R1" if is_3d else "R0", "action": action, "frame": frame, "subframe": sub,
		"facing": facing, "scale": scale, "offset_y": main.framing.offset_y,
		"clipped_source_pixels": clipped, "interior_samples": samples, "RGB_mismatches": mismatches})
	if action == "hopsmash" and frame == 4 and facing == 1 and scale == (2 if is_3d else 1):
		main.get_viewport().get_texture().get_image().save_png("res://docs/previews/r1_28_bottom_" + ("R1" if is_3d else "R0") + ".png")


func run(main: Node, candidate: String = "R1/28") -> Dictionary:
	var tree: SceneTree = main.get_tree()
	var original: Dictionary = main.player.capture_state()
	var original_scale: int = main.render_scale
	var original_offset: float = main.framing.offset_y
	var original_effects: bool = main.player.action_effects.enabled
	main.preview_controls._select_effects(false)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_r1.json"))
	var base_basis: Basis = main.world.get_node("Camera").basis
	var base_size: float = main.world.get_node("Camera").size
	main._set_paused(true)
	main.player.position = main.player.source_to_world(Vector2(440, 345))
	main.player.motion_smoothing.reset()
	for scale: int in [1, 2]:
		main.set_render_scale(scale)
		for action: String in data.animations:
			for frame: int in data.animations[action].frames.size():
				for facing: int in [1, -1]:
					await render_case(main, action, frame, 0, facing, scale)
		for action: String in ["move", "dash"]:
			for frame: int in 8:
				for sub: int in [1, 2]:
					for facing: int in [1, -1]:
						await render_case(main, action, frame, sub, facing, scale)
	check_result("R1_camera_angle_and_scale_retained", main.world.get_node("Camera").basis == base_basis and is_equal_approx(main.world.get_node("Camera").size, base_size))
	var before_switch: Dictionary = main.player.capture_state()
	var framing_before: float = main.framing.offset_y
	main._switch_comparison()
	await tree.scene_changed
	main = tree.current_scene
	check_result("F4_retains_actor_state_and_camera_offset", main.player.capture_state() == before_switch and is_equal_approx(main.framing.offset_y, framing_before))
	for action: String in data.animations:
		for frame: int in data.animations[action].frames.size():
			for facing: int in [1, -1]:
				await render_case(main, action, frame, 0, facing, 1)
	check_result("R0_canvas_moves_without_actor_parent_transform_changes", main.player.get_parent().get_parent().position == Vector2(0, 43) and main.render_viewport.canvas_transform.origin == Vector2(0, -37))
	check_result("R0_keeps_original_layers_and_no_derived_selection", not main.player.walk_inbetweens.spatial and not main.player.walk_inbetweens.active)
	before_switch = main.player.capture_state()
	main._switch_comparison()
	await tree.scene_changed
	main = tree.current_scene
	check_result("F4_return_retains_actor_and_framing", main.player.capture_state() == before_switch and is_equal_approx(main.framing.offset_y, 37.0))
	var r1: Array = render_cases.filter(func(c): return c.scene == "R1")
	var r0: Array = render_cases.filter(func(c): return c.scene == "R0")
	check_result("R1_all496_raw_and_derived_cases", r1.size() == 496)
	check_result("R0_all184_original_layer_cases", r0.size() == 184)
	check_result("both_renderers_have_no_bottom_pose_clipping", render_cases.all(func(c): return c.clipped_source_pixels == 0))
	check_result("both_renderers_preserve_source_RGB_interiors", render_cases.all(func(c): return c.interior_samples > 30 and c.RGB_mismatches == 0))
	main.player.restore_state(original)
	main.set_render_scale(original_scale)
	main._set_paused(original.paused)
	main.preview_controls._select_effects(original_effects)
	main.framing.offset_y = original_offset
	main.framing.apply()
	check_result("production_actor_and_quality_restored", main.player.capture_state() == original and main.render_scale == original_scale)
	var result: Dictionary = {"candidate": candidate, "checks": checks, "failed": checks.filter(func(c): return not c.pass),
		"render_cases": render_cases, "qa_source_sha256": get_script().source_code.sha256_text(),
		"framing_source_sha256": FileAccess.get_file_as_string("res://scripts/source_framing.gd").sha256_text(),
		"note": "Actual native R1 and R0 framebuffer readback at legal source ground point(440,345). Horizontal world-edge framing is outside this check."}
	var output := FileAccess.open("res://docs/r1_28_native_framing_checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	return {"checks": checks.size(), "failed": result.failed, "render_cases": render_cases.size()}
