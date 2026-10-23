extends RefCounted
## Focused native readback at the unchanged legal left and right street edges.

const POSES: Array = [
	{"action": "stay", "frame": 0},
	{"action": "move", "frame": 2},
	{"action": "dash", "frame": 0},
	{"action": "dash", "frame": 5},
	{"action": "attack2", "frame": 2},
	{"action": "attack2", "frame": 4},
	{"action": "hopsmash", "frame": 4},
	{"action": "attack3", "frame": 4}]
const EDGES: Array = [{"name": "left", "x": 36.0, "offset_x": -148.0},
	{"name": "right", "x": 852.0, "offset_x": 140.0}]

var checks: Array = []
var render_cases: Array = []
var floor_cases: Array = []
var images: Dictionary = {}
var data: Dictionary = {}
var sampler = preload("res://tools/r1/pose_checks.gd").new()


func check_result(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check": label, "pass": passed, "details": details})


func offset(main: Node) -> Vector2:
	return Vector2(main.framing.offset_x, main.framing.offset_y)


func tap(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func place(main: Node, edge: Dictionary) -> void:
	var point := Vector2(float(edge.x), 345.0)
	main.player.position = main.player.source_to_world(point) if main.name == "WestCoastR1" else point
	main.player.motion_smoothing.reset()
	main.framing.advance(0.0, true)


func render_case(main: Node, edge: Dictionary, pose: Dictionary, facing: int, scale: int) -> void:
	var p: Node = main.player
	p.preview(pose.action)
	p.frame_index = int(pose.frame)
	p.elapsed_ms = 0.0
	p.facing = facing
	p._apply_frame()
	var is_3d: bool = main.name == "WestCoastR1"
	if is_3d:
		p._update_sprite_transform()
	else:
		p._update_visual()
	p.motion_smoothing.reset()
	main.framing.advance(0.0, true)
	var path: String = p.sprite.texture.resource_path if is_3d else data.animations[pose.action].frames[int(pose.frame)].texture
	if not images.has(path):
		var image := Image.new()
		assert(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK)
		images[path] = image
	var source: Image = images[path]
	for _i: int in 2:
		await RenderingServer.frame_post_draw
	var actual: Image = main.render_viewport.get_texture().get_image()
	var foot: Vector2 = main.world.get_node("Camera").unproject_position(p.position) / float(scale) if is_3d else p.position + Vector2(-main.framing.offset_x, 43.0 - main.framing.offset_y)
	var clipped: int = 0
	var opaque: int = 0
	var samples: int = 0
	var matching: int = 0
	var largest_delta: float = 0.0
	var bounds := Rect2i(Vector2i.ZERO, actual.get_size())
	for y: int in source.get_height():
		for x: int in source.get_width():
			if source.get_pixel(x, y).a < .999:
				continue
			opaque += 1
			var relative := Vector2((float(x) + .5 - 133.0) * facing, float(y) + .5 - 167.0)
			var physical: Vector2 = (foot + relative) * float(scale)
			var pixel := Vector2i(floori(physical.x), floori(physical.y))
			if not bounds.has_point(pixel):
				clipped += 1
				continue
			if x % 4 != 1 or y % 4 != 1 or x < 1 or y < 1 or x >= source.get_width()-1 or y >= source.get_height()-1 or not sampler.opaque_interior(source, Vector2i(x, y)):
				continue
			samples += 1
			var delta: float = sampler.color_distance(source.get_pixel(x, y), actual.get_pixelv(pixel))
			largest_delta = maxf(largest_delta, delta)
			if delta < .025:
				matching += 1
	render_cases.append({"scene": "R1" if is_3d else "R0", "edge": edge.name,
		"action": pose.action, "frame": pose.frame, "facing": facing, "scale": scale,
		"offset": offset(main), "projected_foot": foot, "opaque_source_pixels": opaque,
		"clipped_source_pixels": clipped, "interior_samples": samples,
		"visible_RGB_matches": matching, "unclassified_nonmatches": samples-matching,
		"maximum_sample_RGB_delta": largest_delta})
	if is_3d and scale == 2 and pose.action == "hopsmash" and facing == (-1 if edge.name == "left" else 1):
		main.get_viewport().get_texture().get_image().save_png("res://docs/previews/r1_29_edge_" + str(edge.name) + ".png")


func floor_case(main: Node, edge: Dictionary, scale: int) -> void:
	# The lower ground band must not reveal the transparent viewport underneath.
	# Sky and water are intentionally excluded from this coverage assertion.
	for _i: int in 2:
		await RenderingServer.frame_post_draw
	var image: Image = main.render_viewport.get_texture().get_image()
	var tested: int = 0
	var transparent: int = 0
	for x_start: int in [0, 864]:
		for x: int in range(x_start, x_start+32, 2):
			for y: int in range(392, 404, 2):
				tested += 1
				if image.get_pixel(x*scale, y*scale).a < .999:
					transparent += 1
	floor_cases.append({"scene": str(main.name), "edge": edge.name, "scale": scale,
		"offset": offset(main), "samples": tested, "transparent_ground_samples": transparent})


func run(main: Node, candidate: String = "R1/29") -> Dictionary:
	var tree: SceneTree = main.get_tree()
	var original: Dictionary = main.player.capture_state()
	var original_scale: int = main.render_scale
	var original_offset: Vector2 = offset(main)
	var original_effects: bool = main.player.action_effects.enabled
	var camera: Camera3D = main.world.get_node("Camera")
	var original_basis: Basis = camera.basis
	var original_size: float = camera.size
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_r1.json"))
	main.preview_controls._select_effects(false)
	main._set_paused(true)
	for scale: int in [1, 2]:
		main.set_render_scale(scale)
		for edge: Dictionary in EDGES:
			place(main, edge)
			check_result("R1_" + str(edge.name) + "_target_" + str(scale), offset(main).distance_to(Vector2(float(edge.offset_x), 37.0)) < .001)
			for pose: Dictionary in POSES:
				for facing: int in [1, -1]:
					await render_case(main, edge, pose, facing, scale)
			await floor_case(main, edge, scale)
	check_result("horizontal_framing_keeps_camera_angle_and_zoom", camera.basis == original_basis and is_equal_approx(camera.size, original_size))
	var before: Dictionary = main.player.capture_state()
	var transferred: Vector2 = offset(main)
	main._switch_comparison()
	await tree.scene_changed
	main = tree.current_scene
	check_result("F4_to_R0_retains_actor_and_both_offsets", main.player.capture_state() == before and offset(main).distance_to(transferred) < .001)
	for edge: Dictionary in EDGES:
		place(main, edge)
		for pose: Dictionary in POSES:
			for facing: int in [1, -1]:
				await render_case(main, edge, pose, facing, 1)
		await floor_case(main, edge, 1)
		check_result("R0_" + str(edge.name) + "_canvas_only", main.player.get_parent().get_parent().position == Vector2(0, 43)
			and main.render_viewport.canvas_transform.origin.distance_to(-offset(main)) < .001)
	before = main.player.capture_state()
	transferred = offset(main)
	main._switch_comparison()
	await tree.scene_changed
	main = tree.current_scene
	check_result("F4_to_R1_retains_actor_and_both_offsets", main.player.capture_state() == before and offset(main).distance_to(transferred) < .001)
	tap(KEY_R)
	for _i: int in 2:
		await tree.process_frame
	check_result("actual_R_restores_default_ground_and_both_offsets", main.player.world_to_source(main.player.position).distance_to(Vector2(440, 320)) < .001
		and offset(main).distance_to(Vector2(0, 12)) < .001)
	check_result("all96_representative_edge_cases_read_back", render_cases.size() == 96)
	check_result("all_edge_pose_opaque_pixels_fit_native_viewport", render_cases.all(func(c): return c.opaque_source_pixels > 0 and c.clipped_source_pixels == 0))
	check_result("each_edge_pose_has_visible_source_RGB_interiors", render_cases.all(func(c): return c.interior_samples >= 30 and c.visible_RGB_matches >= 30),
		{"note": "Nonmatching samples remain unclassified because actual scene geometry may occlude the actor. This check asserts visible original-color pixels, not absence of all possible color errors."})
	check_result("both_renderers_have_covered_lower_side_ground_at_max_pan", floor_cases.size() == 6 and floor_cases.all(func(c): return c.samples == 192 and c.transparent_ground_samples == 0), {"cases": floor_cases})
	main.player.restore_state(original)
	main.set_render_scale(original_scale)
	main._set_paused(original.paused)
	main.preview_controls._select_effects(original_effects)
	main.framing.offset_x = original_offset.x
	main.framing.offset_y = original_offset.y
	main.framing.apply()
	check_result("production_actor_quality_effects_and_framing_restored", main.name == "WestCoastR1" and main.player.capture_state() == original
		and main.render_scale == original_scale and main.player.action_effects.enabled == original_effects and offset(main).distance_to(original_offset) < .001)
	var result: Dictionary = {"candidate": candidate, "checks": checks, "failed": checks.filter(func(c): return not c.pass),
		"render_cases": render_cases, "floor_cases": floor_cases, "qa_source_sha256": get_script().source_code.sha256_text(),
		"framing_source_sha256": FileAccess.get_file_as_string("res://scripts/source_framing.gd").sha256_text(),
		"note": "Actual R1/R0 native framebuffers at unchanged legal source x36/852,y345; R1 scales1/2. Clipping counts all fully opaque source pixels. Scene-occluded RGB nonmatches are reported without attributing their cause. Lower-band alpha checks sample both sides, not intentionally transparent sky/water. This focused suite does not repeat the full animation/effect regression."}
	var output := FileAccess.open("res://docs/r1_29_horizontal_checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	return {"checks": checks.size(), "failed": result.failed, "render_cases": render_cases.size()}
