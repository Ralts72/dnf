extends RefCounted
## Small live input proof for the four authored ground colliders, on a persistent root job.

const ProgressScript = preload("res://scripts/adventure_progress.gd")
const QuestChecks = preload("res://tools/r3/quest_checks.gd")
const HARBOR: String = "res://scenes/west_coast_r1.tscn"
const META_KEYS: Array[String] = ["route_hero_hp", "tower_boss_state", "first_encounter_state", "world_travel_state", "world_travel_spawn", "world_region", "port_framing_offset", "port_framing_offset_x", "port_compare_state"]
const FOOT_RADIUS: float = .18
var helper: RefCounted
var checks: Array = []
var records: Array = []
var render_cases: Array = []
var penetration_rows: Array = []
var started_usec: int = 0
var qa_path: String = ""
var output_prefix: String = "r3_04"


func check_result(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check": label, "pass": passed, "details": details})
	render_cases.append({"check": label, "pass": passed})


func tap(code: Key) -> void:
	helper.tap(code)


func point(main: Node) -> Vector2:
	return helper.point(main)


func collider_root(main: Node) -> Node:
	if main.scene_file_path.ends_with("tower_approach.tscn"):
		return main.world.get_node_or_null("TowerApproachCollisions")
	if main.scene_file_path.ends_with("tower_hall.tscn"):
		return main.world.get_node_or_null("TowerHallCollisions")
	return null


func native_foot_clearance(main: Node, source_point: Vector2) -> Dictionary:
	var root: Node = collider_root(main)
	if root == null:
		return {"clear": main.scene_file_path == HARBOR, "native_count": 0, "minimum_clearance_m": 0.0, "shapes": []}
	var ground: Vector3 = main.player.source_to_world(source_point)
	var foot := Vector2(ground.x, ground.z)
	var minimum: float = INF
	var shapes: Array = []
	for shape: CollisionShape3D in root.find_children("*", "CollisionShape3D", true, false):
		var center3: Vector3 = main.world.to_local(shape.global_position)
		var difference: Vector2 = foot-Vector2(center3.x, center3.z)
		var clearance: float = -INF
		if shape.shape is CylinderShape3D:
			clearance = difference.length()-(shape.shape as CylinderShape3D).radius-FOOT_RADIUS
		elif shape.shape is BoxShape3D:
			var size: Vector3 = (shape.shape as BoxShape3D).size
			var outside: Vector2 = difference.abs()-Vector2(size.x, size.z)*.5-Vector2.ONE*FOOT_RADIUS
			# Independent overlap predicate from the native shape; the gate policy uses conservative rectangle corners.
			clearance = outside.max(Vector2.ZERO).length()+minf(maxf(outside.x, outside.y), 0.0)
		minimum = minf(minimum, clearance)
		shapes.append({"name": shape.get_parent().name, "clearance_m": clearance, "disabled": shape.disabled})
	return {"clear": minimum >= -.0005, "native_count": shapes.size(), "minimum_clearance_m": minimum, "shapes": shapes}


func observe(tree: SceneTree, progress: Node, label: String) -> Dictionary:
	var row: Dictionary = helper.observe(tree, progress, label)
	if row.is_empty():
		return row
	var main: Node = tree.current_scene
	row["native_foot"] = native_foot_clearance(main, point(main))
	row["inspection"] = main.player.markers_visible
	if row.native_foot.native_count > 0 and not row.native_foot.clear:
		penetration_rows.append({"phase": label, "position": point(main), "native_foot": row.native_foot})
	return row


func wait_for(tree: SceneTree, progress: Node, label: String, seconds: float, until: Callable = Callable(), codes: Array = []) -> Dictionary:
	helper.release_motion()
	for code: Key in codes:
		helper.key(code, true)
	var start: int = Time.get_ticks_usec()
	var reached: bool = false
	var last: Dictionary = {}
	while float(Time.get_ticks_usec()-start)/1000000.0 < seconds:
		await RenderingServer.frame_post_draw
		last = observe(tree, progress, label)
		if not last.is_empty() and until.is_valid() and until.call(tree.current_scene, last):
			reached = true
			break
	helper.release_motion()
	return {"reached": reached, "last": last, "duration_seconds": float(Time.get_ticks_usec()-start)/1000000.0}


func ready_in(region: String) -> Callable:
	return func(_m: Node, state: Dictionary): return state.travel.get("region", "") == region and state.travel.get("phase", "") == "ready"


func align_x(tree: SceneTree, progress: Node, target: float, label: String) -> Dictionary:
	var toward: Key = KEY_D if target > point(tree.current_scene).x else KEY_A
	return await wait_for(tree, progress, label, 4.5,
		func(m: Node, _s: Dictionary): return absf(point(m).x-target) <= 4.0, [toward, KEY_SHIFT])


func native_proof(main: Node, region: String) -> Dictionary:
	var root: Node = collider_root(main)
	var nodes: Array = []
	var valid: bool = root != null
	if root != null:
		for shape: CollisionShape3D in root.find_children("*", "CollisionShape3D", true, false):
			var body: StaticBody3D = shape.get_parent() as StaticBody3D
			var appropriate_shape: bool = shape.shape is CylinderShape3D if region == "hall" else shape.shape is BoxShape3D
			var center: Vector3 = main.world.to_local(shape.global_position)
			valid = valid and body != null and body.collision_layer == 1 and body.collision_mask == 1 and not shape.disabled and appropriate_shape
			nodes.append({"path": str(main.get_path_to(shape)), "body": body.name, "shape": shape.shape.get_class(), "center_world": center,
				"layer": body.collision_layer, "mask": body.collision_mask})
	var policy: Variant = main.get("route_obstacles")
	var captured: Dictionary = policy.capture_state() if policy != null else {}
	return {"valid": valid and nodes.size() == 2 and captured.get("region", "") == region and int(captured.get("obstacle_count", 0)) == 2,
		"native": nodes, "policy": captured}


func obstacle_flow(tree: SceneTree, progress: Node) -> void:
	tap(KEY_R)
	await wait_for(tree, progress, "harbor_start", .08)
	var approach: Dictionary = await wait_for(tree, progress, "actual_route_to_approach", 4.5, ready_in("approach"), [KEY_A, KEY_SHIFT])
	check_result("actual_route_reaches_approach_with_two_native_gate_colliders", approach.reached and native_proof(tree.current_scene, "approach").valid,
		native_proof(tree.current_scene, "approach") if approach.reached else approach)
	if not approach.reached:
		return
	var main: Node = tree.current_scene
	var right_x: Dictionary = await align_x(tree, progress, 488.0, "actual_walk_to_right_gate_base")
	await wait_for(tree, progress, "actual_W_against_right_gate_base", 1.65, Callable(), [KEY_W, KEY_SHIFT])
	var right_stop: Vector2 = point(main)
	check_result("right_gate_base_stops_actual_W_before_walk_limit", right_x.reached and absf(right_stop.x-488.0) <= 5.0
		and right_stop.y >= 244.3 and right_stop.y <= 245.2 and native_foot_clearance(main, right_stop).clear, {"position": right_stop})
	tap(KEY_R)
	await wait_for(tree, progress, "R_from_gate_contact_restores_safe_arrival", .08)
	check_result("R_from_gate_contact_restores_clear_approach_spawn", point(main).distance_to(Vector2(816, 320)) < .01
		and native_foot_clearance(main, point(main)).clear and not main.player.jump_motion.is_active())
	var left_x: Dictionary = await align_x(tree, progress, 372.0, "actual_walk_to_left_gate_base")
	await wait_for(tree, progress, "actual_W_against_left_gate_base", 1.65, Callable(), [KEY_W, KEY_SHIFT])
	var left_stop: Vector2 = point(main)
	check_result("left_gate_base_stops_actual_W_before_walk_limit", left_x.reached and absf(left_stop.x-372.0) <= 5.0
		and left_stop.y >= 244.3 and left_stop.y <= 245.2 and native_foot_clearance(main, left_stop).clear, {"position": left_stop})
	var hall: Dictionary = await wait_for(tree, progress, "actual_diagonal_slide_around_gate_into_center_door", 2.5, ready_in("hall"), [KEY_D, KEY_W, KEY_SHIFT])
	check_result("actual_diagonal_gate_slide_reaches_central_door_and_hall", hall.reached and native_proof(tree.current_scene, "hall").valid,
		native_proof(tree.current_scene, "hall") if hall.reached else hall)
	if not hall.reached:
		return
	main = tree.current_scene
	# Inspection deliberately gates enemy AI while the real directional movement probes geometry.
	# No HP, actor position, animation clock or qa_freeze_enemy is written by this QA.
	tap(KEY_F1)
	await wait_for(tree, progress, "inspection_isolates_ground_geometry_from_combat", .06)
	var inspection_ready: bool = main.player.markers_visible and main.get_node("FirstEncounter").capture_state().combat_blocked
	var hall_left_x: Dictionary = await align_x(tree, progress, 140.0, "actual_walk_to_left_column")
	await wait_for(tree, progress, "actual_W_against_left_column", 1.0, Callable(), [KEY_W, KEY_SHIFT])
	var hall_left: Vector2 = point(main)
	check_result("left_column_foot_stops_actual_W_without_penetration", inspection_ready and hall_left_x.reached
		and absf(hall_left.x-140.0) <= 5.0 and hall_left.y > 260.0 and hall_left.y < 264.0
		and native_foot_clearance(main, hall_left).clear, {"position": hall_left, "native": native_foot_clearance(main, hall_left)})
	tap(KEY_F2)
	var paused_point: Vector2 = point(main)
	await wait_for(tree, progress, "paused_W_cannot_slide_at_column", .2, Callable(), [KEY_W, KEY_D, KEY_SHIFT])
	var pause_holds: bool = main.player.paused and point(main).distance_to(paused_point) < .001
	tap(KEY_F2)
	var around_left: Dictionary = await wait_for(tree, progress, "actual_diagonal_slide_around_left_column", 1.5,
		func(m: Node, _s: Dictionary): return point(m).x >= 205.0 and point(m).y <= 247.0, [KEY_D, KEY_W, KEY_SHIFT])
	check_result("pause_holds_contact_then_diagonal_slide_rounds_left_column", pause_holds and around_left.reached
		and native_foot_clearance(main, point(main)).clear, {"position": point(main), "pause_holds": pause_holds})
	var lower_lane: Dictionary = await wait_for(tree, progress, "actual_column_bypass_to_lower_lane", 1.2,
		func(m: Node, _s: Dictionary): return point(m).y >= 325.0, [KEY_S, KEY_SHIFT])
	var hall_right_x: Dictionary = await align_x(tree, progress, 760.0, "actual_walk_to_right_column")
	await wait_for(tree, progress, "actual_W_against_right_column", 1.0, Callable(), [KEY_W, KEY_SHIFT])
	var hall_right: Vector2 = point(main)
	check_result("right_column_foot_stops_actual_W_without_penetration", lower_lane.reached and hall_right_x.reached
		and absf(hall_right.x-760.0) <= 5.0 and hall_right.y > 260.0 and hall_right.y < 264.0
		and native_foot_clearance(main, hall_right).clear, {"position": hall_right})
	tap(KEY_SPACE)
	var airborne: Dictionary = await wait_for(tree, progress, "actual_jump_W_at_column", .5,
		func(m: Node, _s: Dictionary): return m.player.jump_motion.height_pixels > 15.0, [KEY_W])
	var landed: Dictionary = await wait_for(tree, progress, "actual_jump_lands_outside_column", 1.3,
		func(m: Node, _s: Dictionary): return not m.player.jump_motion.is_active(), [KEY_W])
	check_result("actual_Space_W_cannot_land_inside_column_foot", airborne.reached and landed.reached and point(main).y > 260.0
		and native_foot_clearance(main, point(main)).clear, {"airborne": airborne.last, "landed": landed.last})
	var around_right: Dictionary = await wait_for(tree, progress, "actual_diagonal_slide_around_right_column", 1.5,
		func(m: Node, _s: Dictionary): return point(m).x <= 695.0 and point(m).y <= 247.0, [KEY_A, KEY_W, KEY_SHIFT])
	check_result("actual_opposite_diagonal_slide_rounds_right_column", around_right.reached and native_foot_clearance(main, point(main)).clear,
		{"position": point(main)})
	# A direct constraint call is explicitly a push-path fixture, not a claimed enemy strike.
	var pushed: Vector2 = main._constrain_ground(Vector2(140, 280), Vector2(140, 245))
	check_result("marked_push_path_fixture_uses_shared_ground_constraint", pushed.y > 260.0 and pushed.y < 264.0
		and native_foot_clearance(main, pushed).clear, {"fixture": "Direct _constrain_ground call at a column; no actor mutation or enemy strike is claimed.",
			"previous": Vector2(140, 280), "requested": Vector2(140, 245), "result": pushed})
	tap(KEY_R)
	await wait_for(tree, progress, "R_after_column_jump_restores_safe_hall_spawn", .1)
	check_result("R_after_column_probes_restores_clear_hall_spawn", point(main).distance_to(Vector2(440, 315)) < .01
		and native_foot_clearance(main, point(main)).clear and not main.player.jump_motion.is_active() and not main.player._one_shot)
	if main.player.markers_visible:
		tap(KEY_F1)
	var retreat: Dictionary = await wait_for(tree, progress, "actual_center_door_return_to_approach", 2.0, ready_in("approach"), [KEY_S, KEY_SHIFT])
	check_result("actual_central_door_return_is_clear_and_has_no_bounce", retreat.reached
		and point(tree.current_scene).distance_to(Vector2(430, 263)) < .1 and native_foot_clearance(tree.current_scene, point(tree.current_scene)).clear)
	await wait_for(tree, progress, "return_door_idle_no_bounce", .35)
	check_result("all_live_geometry_rows_remain_clear_with_stable_return", penetration_rows.is_empty()
		and tree.current_scene.scene_file_path.ends_with("tower_approach.tscn"), {"penetrations": penetration_rows, "recorded_rows": records.size()})


func run(main: Node, candidate: String = "R3/04") -> Dictionary:
	var tree: SceneTree = main.get_tree()
	started_usec = Time.get_ticks_usec()
	output_prefix = candidate.to_lower().replace("/", "_")
	helper = QuestChecks.new()
	helper.started_usec = started_usec
	records = helper.records
	var formal_before: Dictionary = helper.profile_guard()
	var progress: Node = tree.root.get_node_or_null("AdventureProgress")
	if progress == null:
		check_result("persistent_progress_is_integrated", false)
		return {"checks": checks.size(), "failed": checks}
	qa_path = "user://qa/obstacle_live_"+str(Time.get_unix_time_from_system()).replace(".", "_")+"_"+str(Time.get_ticks_usec())+".json"
	var configured: bool = progress.configure_storage(qa_path, false)
	var original_actor: Dictionary = main.player.capture_state()
	var original_spawn: Vector2 = main.player.spawn_position
	var original_blocked: bool = main.player.ui_input_blocked
	var original_offset := Vector2(main.framing.offset_x, main.framing.offset_y)
	var original_interface: bool = main.get_node("Interface").visible
	var original_markers: bool = main.player.markers_visible
	var preferences = preload("res://tools/r2/travel_checks.gd").new()
	var original_preferences: Dictionary = preferences.settings(main)
	var original_meta: Dictionary = {}
	for meta_key: String in META_KEYS:
		var exists: bool = tree.has_meta(meta_key)
		var value: Variant = tree.get_meta(meta_key) if exists else null
		if value is Dictionary:
			value = value.duplicate(true)
		original_meta[meta_key] = {"present": exists, "value": value}
	for combat_meta: String in ["first_encounter_state", "tower_boss_state", "route_hero_hp"]:
		if tree.has_meta(combat_meta):
			tree.remove_meta(combat_meta)
	main._set_paused(false)
	main.player.ui_input_blocked = false
	main.player.free_control()
	main.get_node("Interface").visible = true
	if main.player.markers_visible:
		main._toggle_markers()
	main.get_viewport().gui_release_focus()
	check_result("geometry_QA_is_isolated_on_initial_harbor", configured and main.scene_file_path == HARBOR
		and progress.storage_path == qa_path and progress.progress.first_drop.state == "unearned" and not FileAccess.file_exists(qa_path), {"QA_storage_path": qa_path})
	if configured and main.scene_file_path == HARBOR:
		await obstacle_flow(tree, progress)
	helper.release_motion()
	main = tree.current_scene
	var loot: Node = main.get_node_or_null("FirstLoot")
	if loot != null:
		loot.close_bag()
	progress.close_dialog()
	for meta_key: String in META_KEYS:
		if original_meta[meta_key].present:
			tree.set_meta(meta_key, original_meta[meta_key].value)
		elif tree.has_meta(meta_key):
			tree.remove_meta(meta_key)
	tree.change_scene_to_file(HARBOR)
	await tree.scene_changed
	await wait_for(tree, progress, "obstacle_cleanup_harbor_ready", .6, ready_in("harbor"))
	main = tree.current_scene
	for combat_meta: String in ["first_encounter_state", "tower_boss_state", "route_hero_hp"]:
		if original_meta[combat_meta].present:
			tree.set_meta(combat_meta, original_meta[combat_meta].value)
		elif tree.has_meta(combat_meta):
			tree.remove_meta(combat_meta)
	var default_loaded: bool = progress.configure_storage(ProgressScript.DEFAULT_STORAGE, true)
	preferences.apply_settings(main, original_preferences)
	main.player.restore_state(original_actor)
	main.player.spawn_position = original_spawn
	main.player.ui_input_blocked = original_blocked
	main._set_paused(original_actor.paused)
	main.framing.offset_x = original_offset.x
	main.framing.offset_y = original_offset.y
	main.framing.apply()
	main.get_node("Interface").visible = original_interface
	if main.player.markers_visible != original_markers:
		main._toggle_markers()
	var formal_after: Dictionary = helper.profile_guard()
	check_result("formal_profile_and_backup_bytes_unchanged", formal_before == formal_after, {"before": formal_before, "after": formal_after})
	check_result("default_profile_original_player_preferences_and_harbor_restored", default_loaded and progress.storage_path == ProgressScript.DEFAULT_STORAGE
		and main.scene_file_path == HARBOR and main.player.capture_state() == original_actor and main.player.spawn_position == original_spawn
		and main.player.ui_input_blocked == original_blocked and preferences.settings(main) == original_preferences
		and not progress.capture_state().dialog_open and not tree.has_meta("world_travel_spawn"))
	var result: Dictionary = {"candidate": candidate, "checks": checks, "failed": checks.filter(func(c): return not c.pass),
		"duration_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0, "records": records, "penetrations": penetration_rows,
		"QA_storage_path": qa_path, "QA_storage_absolute_path": ProjectSettings.globalize_path(qa_path),
		"formal_profile_before": formal_before, "formal_profile_after": formal_after,
		"qa_source_sha256": get_script().source_code.sha256_text(),
		"obstacle_source_sha256": FileAccess.get_file_as_string("res://scripts/route_ground_obstacles.gd").sha256_text(),
		"stage_source_sha256": FileAccess.get_file_as_string("res://scripts/exploration_stage.gd").sha256_text(),
		"note": "Actual inputs and native CollisionShape3D readback prove four foot blockers, diagonal slides, jump/landing, pause/reset and central door round trip. F1 inspection deliberately pauses enemy combat only during hall geometry probes; no HP, actor position, source clock or qa_freeze_enemy writes. One labeled direct shared-constraint call covers the push route without claiming a real enemy strike. Sweep/recovery edge matrices belong to the separate headless geometry suite. Human files are only presence/hash checked by QA; normal default loading is restored."}
	var output := FileAccess.open("res://docs/"+output_prefix+"_obstacle_checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	return {"checks": checks.size(), "failed": result.failed, "render_cases": render_cases.size(), "recorded_rows": records.size()}
