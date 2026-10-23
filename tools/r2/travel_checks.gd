extends RefCounted
## Run through a pose_check_job attached to SceneTree.root, not the current scene.
## All four passages use actual key events. Only gate preconditions are staged.

const HARBOR: String = "res://scenes/west_coast_r1.tscn"
const META_KEYS: Array[String] = ["world_travel_state", "world_travel_spawn", "world_region", "port_framing_offset", "port_framing_offset_x", "first_encounter_state"]
var checks: Array = []
var records: Array = []
var render_cases: Array = []
var drives: Array = []
var arrivals: Array = []
var gate_states: Array = []
var screenshots: Dictionary = {}
var fade_input_probes: Array = []
var expected_settings: Dictionary = {}
var started_usec: int = 0
var output_prefix: String = "r2_01"


func check_result(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check": label, "pass": passed, "details": details})


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


func release_motion() -> void:
	for code: Key in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SHIFT, KEY_SPACE]:
		key(code, false)


func main_node(tree: SceneTree) -> Node:
	var main: Node = tree.current_scene
	return main if main != null and main.get_node_or_null("WorldTravel") != null else null


func point(main: Node) -> Vector2:
	return main.player.world_to_source(main.player.position)


func settings(main: Node) -> Dictionary:
	var tree: SceneTree = main.get_tree()
	var music: Node = tree.root.get_node("PortMusic")
	return {"walk": main.player.walk_inbetweens.enabled, "motion": main.player.motion_smoothing.enabled,
		"effects": main.player.action_effects.enabled, "quality": main.render_scale,
		"audio_volume": float(tree.get_meta("port_audio_volume", .6)), "audio_muted": tree.get_meta("port_audio_muted", false),
		"music_volume": music.volume, "music_muted": music.muted}


func apply_settings(main: Node, values: Dictionary) -> void:
	main.preview_controls._select_walk_inbetweens(values.walk)
	main.preview_controls._select_motion_smoothing(values.motion)
	main.preview_controls._select_effects(values.effects)
	main.set_render_scale(values.quality)
	var tree: SceneTree = main.get_tree()
	tree.set_meta("port_audio_volume", values.audio_volume)
	tree.set_meta("port_audio_muted", values.audio_muted)
	main.player.action_audio.apply_preferences()
	var music: Node = tree.root.get_node("PortMusic")
	music.select_volume(values.music_volume)
	music.muted = values.music_muted
	main.preview_controls.sync()


func observe(main: Node, label: String) -> Dictionary:
	var state: Dictionary = main.get_node("WorldTravel").capture_state()
	var veil: Control = main.get_node("WorldTravel/TravelFade/Veil")
	var row: Dictionary = {"phase": label, "elapsed_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"region": state.get("current_region", state.get("region", "")), "travel_phase": state.get("phase", ""),
		"transition_count": state.get("transition_count", -1), "fade_alpha": state.get("fade_alpha", -1.0),
		"source_position": point(main), "spawn_position": main.player.spawn_position,
		"jump_height": main.player.jump_motion.height_pixels, "jump_active": main.player.jump_motion.is_active(),
		"paused": main.player.paused, "ui_input_blocked": main.player.ui_input_blocked,
		"fade_covers_viewport": veil.size.distance_to(main.get_viewport_rect().size) < .1}
	records.append(row)
	return state


func drive(tree: SceneTree, label: String, codes: Array, maximum_seconds: float, until: Callable = Callable()) -> Dictionary:
	release_motion()
	for code: Key in codes:
		key(code, true)
	var start: int = Time.get_ticks_usec()
	var reached: bool = false
	var last: Dictionary = {}
	while float(Time.get_ticks_usec()-start)/1000000.0 < maximum_seconds:
		await RenderingServer.frame_post_draw
		var main: Node = main_node(tree)
		if main == null:
			continue
		last = observe(main, label)
		if last.get("phase", "") == "fade_out" and fade_input_probes.is_empty():
			var pause_button: Control = main.get_node("Interface/Buttons/Pause")
			if pause_button.is_visible_in_tree():
				var original_focus_mode: int = pause_button.focus_mode
				var previous_focus: Control = main.get_viewport().gui_get_focus_owner()
				pause_button.focus_mode = Control.FOCUS_ALL
				pause_button.grab_focus()
				var owned_focus: bool = main.get_viewport().gui_get_focus_owner() == pause_button
				tap(KEY_SPACE)
				pause_button.focus_mode = original_focus_mode
				if is_instance_valid(previous_focus) and previous_focus != pause_button and previous_focus.focus_mode != Control.FOCUS_NONE:
					previous_focus.grab_focus()
				fade_input_probes.append({"phase": label, "travel_phase": last.phase,
					"focused_control": str(pause_button.get_path()), "Space_did_not_pause_actor": not main.player.paused,
					"button_was_focus_owner_before_Space": owned_focus, "focus_mode_restored": pause_button.focus_mode == original_focus_mode,
					"Space_did_not_start_jump": not main.player.jump_motion.is_active()})
		if until.is_valid() and until.call(main, last):
			reached = true
			break
	release_motion()
	var result: Dictionary = {"phase": label, "keys": codes, "duration_seconds": float(Time.get_ticks_usec()-start)/1000000.0,
		"maximum_seconds": maximum_seconds, "has_destination": until.is_valid(), "destination_reached": reached, "last_travel_state": last}
	drives.append(result)
	return result


func ready_in(region: String) -> Callable:
	return func(_main: Node, state: Dictionary): return state.get("current_region", state.get("region", "")) == region and state.get("phase", "") == "ready"


func passage(tree: SceneTree, label: String, keys: Array, destination: String, timeout: float) -> bool:
	var before: Dictionary = main_node(tree).get_node("WorldTravel").capture_state()
	var result: Dictionary = await drive(tree, label, keys, timeout, ready_in(destination))
	if not result.destination_reached:
		return false
	var main: Node = main_node(tree)
	var state: Dictionary = main.get_node("WorldTravel").capture_state()
	var arrival: Dictionary = {"passage": label, "region": destination, "state": state,
		"settings": settings(main), "source_position": point(main), "spawn_position": main.player.spawn_position,
		"grounded": not main.player.jump_motion.is_active() and absf(main.player.jump_motion.height_pixels) < .001,
		"free_control": not main.player.paused and not main.player.preview_mode and not main.player._one_shot,
		"one_transition": int(state.get("transition_count", -1)) == int(before.get("transition_count", -1))+1}
	if not screenshots.has(destination):
		var screenshot_path: String = "res://docs/previews/"+output_prefix+"_"+destination+".png"
		var save_error: Error = main.get_viewport().get_texture().get_image().save_png(screenshot_path)
		screenshots[destination] = {"path": screenshot_path, "save_error": save_error,
			"region": destination, "phase": state.get("phase", ""), "fade_alpha": state.get("fade_alpha", -1.0)}
	# Continue the arrival direction briefly: it must lead inward, not bounce back.
	await drive(tree, label+"_arrival_direction", keys, .18)
	main = main_node(tree)
	var after: Dictionary = main.get_node("WorldTravel").capture_state()
	arrival["no_bounce"] = after.get("current_region", after.get("region", "")) == destination and after.get("transition_count", -1) == state.get("transition_count", -2)
	arrivals.append(arrival)
	render_cases.append({"passage": label, "region": destination, "transition_count": state.get("transition_count", -1)})
	return true


func local_reset(tree: SceneTree, label: String) -> bool:
	var main: Node = main_node(tree)
	var spawn: Vector2 = main.player.spawn_position
	tap(KEY_R)
	await drive(tree, label, [], .12)
	main = main_node(tree)
	return point(main).distance_to(spawn) < .001 and not main.player.jump_motion.is_active() and not main.player.paused \
		and not main.player.preview_mode and not main.player._one_shot \
		and Vector2(main.framing.offset_x, main.framing.offset_y).distance_to(Vector2(main.framing.target_x(false), main.framing.target(false))) < .01


func run(main: Node, candidate: String = "R2/01") -> Dictionary:
	var tree: SceneTree = main.get_tree()
	started_usec = Time.get_ticks_usec()
	output_prefix = candidate.to_lower().replace("/", "_")
	var original_actor: Dictionary = main.player.capture_state()
	var original_settings: Dictionary = settings(main)
	var original_offset := Vector2(main.framing.offset_x, main.framing.offset_y)
	var original_spawn: Vector2 = main.player.spawn_position
	var original_input_blocked: bool = main.player.ui_input_blocked
	var original_interface_visible: bool = main.get_node("Interface").visible
	var original_markers: bool = main.player.markers_visible
	var original_meta: Dictionary = {}
	for meta_key: String in META_KEYS:
		var present: bool = tree.has_meta(meta_key)
		original_meta[meta_key] = {"present": present, "value": tree.get_meta(meta_key) if present else null}
		if original_meta[meta_key].value is Dictionary:
			original_meta[meta_key].value = original_meta[meta_key].value.duplicate(true)
	var travel: Node = main.get_node("WorldTravel")
	var initial_region: String = travel.current_region()
	check_result("QA_starts_in_harbor", initial_region == "harbor")
	# Nondefault sentinels make preference persistence distinguishable from a
	# new scene merely returning to its default settings.
	expected_settings = original_settings.duplicate(true)
	expected_settings.walk = not original_settings.walk
	expected_settings.motion = not original_settings.motion
	expected_settings.effects = not original_settings.effects
	expected_settings.quality = 1 if original_settings.quality == 2 else 2
	expected_settings.audio_volume = .3 if original_settings.audio_volume != .3 else .6
	expected_settings.audio_muted = false
	expected_settings.music_volume = .1 if original_settings.music_volume != .1 else .2
	expected_settings.music_muted = false
	apply_settings(main, expected_settings)
	main.get_node("Interface").visible = true
	main.player.reset_position()
	main.player.position = main.player.source_to_world(Vector2(40, 320))
	main.player.motion_smoothing.reset()
	main.framing.advance(0.0, true)
	main._set_paused(false)
	await drive(tree, "gate_setup", [], .12)
	var music_before: Dictionary = tree.root.get_node("PortMusic").capture_state()
	tap(KEY_F2)
	await drive(tree, "paused_exit_hold", [KEY_A], .25)
	main = main_node(tree)
	var paused_state: Dictionary = main.get_node("WorldTravel").capture_state()
	gate_states.append({"gate": "paused", "state": paused_state})
	check_result("paused_actor_cannot_leave_even_at_exit_with_direction_held", main.player.paused and main.get_node("WorldTravel").current_region() == "harbor" and paused_state.phase == "ready")
	tap(KEY_F2)
	var popup: PopupMenu = main.preview_controls.audio_menu.get_popup()
	popup.popup()
	await drive(tree, "popup_exit_hold", [KEY_A], .25)
	main = main_node(tree)
	var popup_state: Dictionary = main.get_node("WorldTravel").capture_state()
	gate_states.append({"gate": "popup", "state": popup_state})
	check_result("open_actual_menu_blocks_exit_hold", is_instance_valid(popup) and popup.visible and main.get_node("WorldTravel").current_region() == "harbor" and popup_state.phase == "ready")
	if is_instance_valid(popup):
		popup.hide()
	await drive(tree, "popup_closed", [], .08)
	main = main_node(tree)
	main.get_viewport().gui_release_focus()
	tap(KEY_SPACE)
	await drive(tree, "airborne_exit_hold", [KEY_A], .45)
	main = main_node(tree)
	var airborne_state: Dictionary = main.get_node("WorldTravel").capture_state()
	gate_states.append({"gate": "airborne", "state": airborne_state})
	check_result("airborne_actor_cannot_trigger_scene_replacement", main.player.jump_motion.is_active() and main.player.jump_motion.height_pixels > 5.0
		and main.get_node("WorldTravel").current_region() == "harbor" and airborne_state.phase == "ready")
	await drive(tree, "land_without_exit_direction", [], 1.1)
	var route_ok: bool = initial_region == "harbor" and main_node(tree).get_node("WorldTravel").current_region() == "harbor"
	var local_resets: Array = []
	var quality_cases: Array = []
	if route_ok:
		route_ok = await passage(tree, "harbor_to_approach", [KEY_A], "approach", 3.0)
	if route_ok:
		main = main_node(tree)
		for _i: int in 2:
			var old_point: Vector2 = point(main)
			tap(KEY_F6)
			await drive(tree, "approach_quality_toggle", [], .08)
			main = main_node(tree)
			quality_cases.append({"scale": main.render_scale, "dimensions": main.render_viewport.size,
				"unchanged_ground": point(main).distance_to(old_point) < .001,
				"native_dimensions_match": main.render_viewport.size == Vector2i(896,404)*int(main.render_scale)})
		local_resets.append({"region": "approach", "pass": await local_reset(tree, "approach_local_reset")})
		var toward_door: Dictionary = await drive(tree, "approach_walk_to_door_x", [KEY_A, KEY_SHIFT], 3.5,
			func(m: Node, _state: Dictionary): return absf(point(m).x-430.0) <= 8.0)
		route_ok = toward_door.destination_reached
	if route_ok:
		route_ok = await passage(tree, "approach_to_hall", [KEY_W, KEY_SHIFT], "hall", 3.0)
	if route_ok:
		local_resets.append({"region": "hall", "pass": await local_reset(tree, "hall_local_reset")})
		route_ok = await passage(tree, "hall_to_approach", [KEY_S, KEY_SHIFT], "approach", 3.0)
	if route_ok:
		var lower_lane: Dictionary = await drive(tree, "approach_return_to_lower_lane", [KEY_S, KEY_SHIFT], 1.5,
			func(m: Node, _state: Dictionary): return point(m).y >= 318.0)
		route_ok = lower_lane.destination_reached
	if route_ok:
		route_ok = await passage(tree, "approach_to_harbor", [KEY_D, KEY_SHIFT], "harbor", 4.5)
	var comparison_ok: bool = false
	var comparison_details: Dictionary = {}
	if route_ok:
		main = main_node(tree)
		tap(KEY_F2)
		await drive(tree, "pause_for_harbor_comparison", [], .08)
		var before_comparison: Dictionary = main.player.capture_state()
		var comparison_anchor: Vector2 = main.player.spawn_position
		tap(KEY_F4)
		await tree.scene_changed
		main = tree.current_scene
		var original_pose_retained: bool = main.scene_file_path.ends_with("west_coast_r0.tscn") and main.player.capture_state() == before_comparison
		tap(KEY_F4)
		await tree.scene_changed
		main = tree.current_scene
		var return_pose_retained: bool = main.player.capture_state() == before_comparison
		var anchor_retained: bool = main.player.spawn_position.distance_to(comparison_anchor) < .001
		var return_reset_ok: bool = await local_reset(tree, "harbor_reset_after_comparison")
		comparison_ok = original_pose_retained and return_pose_retained and anchor_retained and return_reset_ok
		comparison_details = {"R0_original_pose_retained": original_pose_retained, "R1_pose_retained": return_pose_retained,
			"reset_anchor_before_F4": comparison_anchor, "reset_anchor_after_F4": main.player.spawn_position,
			"anchor_retained": anchor_retained, "actual_R_returns_to_anchor": return_reset_ok}
	check_result("actual_keys_complete_all_four_passages", route_ok and arrivals.size() == 4, {"drives": drives})
	check_result("safe_grounded_arrivals_are_free_and_do_not_bounce", arrivals.size() == 4 and arrivals.all(func(a): return a.grounded and a.free_control and a.one_transition and a.no_bounce and a.source_position.distance_to(a.spawn_position) <= 4.0), {"arrivals": arrivals})
	check_result("nondefault_controls_audio_and_quality_persist_across_regions", arrivals.size() == 4 and arrivals.all(func(a): return a.settings == expected_settings))
	check_result("R_resets_to_each_regions_local_spawn", local_resets.size() == 2 and local_resets.all(func(c): return c.pass), {"cases": local_resets})
	check_result("harbor_F4_preserves_original_pose_and_return_reset_anchor", comparison_ok, comparison_details)
	check_result("both_F6_qualities_work_in_route_without_moving_actor", quality_cases.size() == 2 and quality_cases.any(func(c): return c.scale == 1)
		and quality_cases.any(func(c): return c.scale == 2) and quality_cases.all(func(c): return c.unchanged_ground and c.native_dimensions_match), {"cases": quality_cases})
	var ready_rows: Array = records.filter(func(r): return r.travel_phase == "ready")
	var fading_rows: Array = records.filter(func(r): return r.travel_phase in ["fade_out", "fade_in"])
	var music_after: Dictionary = tree.root.get_node("PortMusic").capture_state()
	check_result("transition_fades_finish_and_persistent_music_does_not_restart", route_ok and records.any(func(r): return r.travel_phase == "fade_out")
		and records.any(func(r): return r.travel_phase == "fade_in") and ready_rows.all(func(r): return r.fade_alpha < .001)
		and music_before.player_id == music_after.player_id and music_before.play_starts == music_after.play_starts,
		{"music_before": music_before, "music_after": music_after})
	check_result("fade_blocks_controls_and_covers_viewport", not fading_rows.is_empty() and fading_rows.all(func(r): return r.ui_input_blocked and not r.paused and r.fade_covers_viewport)
		and fade_input_probes.size() == 1 and fade_input_probes[0].button_was_focus_owner_before_Space and fade_input_probes[0].focus_mode_restored
		and fade_input_probes[0].Space_did_not_pause_actor and fade_input_probes[0].Space_did_not_start_jump,
		{"focused_button_Space_probe": fade_input_probes})
	check_result("all_three_region_screenshots_saved_after_clear_fade", screenshots.size() == 3 and screenshots.values().all(func(s): return s.save_error == OK and s.phase == "ready" and s.fade_alpha < .001), {"screenshots": screenshots})
	# Restore the original route metadata before a clean harbor reload. The QA's
	# four transitions and visited flags must not become player progress.
	release_motion()
	for meta_key: String in META_KEYS:
		if original_meta[meta_key].present:
			tree.set_meta(meta_key, original_meta[meta_key].value)
		elif tree.has_meta(meta_key):
			tree.remove_meta(meta_key)
	tree.change_scene_to_file(HARBOR)
	await tree.scene_changed
	main = tree.current_scene
	await drive(tree, "cleanup_harbor_ready", [], .6, ready_in("harbor"))
	main = main_node(tree)
	# A hall encounter persists on _exit_tree. Restore after that scene has
	# actually exited, so its late save cannot turn QA combat state into progress.
	if original_meta.first_encounter_state.present:
		tree.set_meta("first_encounter_state", original_meta.first_encounter_state.value)
	elif tree.has_meta("first_encounter_state"):
		tree.remove_meta("first_encounter_state")
	var combat_save_restored: bool = tree.has_meta("first_encounter_state") == original_meta.first_encounter_state.present
	if combat_save_restored and original_meta.first_encounter_state.present:
		combat_save_restored = tree.get_meta("first_encounter_state") == original_meta.first_encounter_state.value
	apply_settings(main, original_settings)
	main.player.restore_state(original_actor)
	main.player.spawn_position = original_spawn
	main.player.ui_input_blocked = original_input_blocked
	main._set_paused(original_actor.paused)
	main.get_node("Interface").visible = original_interface_visible
	if main.player.markers_visible != original_markers:
		main._toggle_markers()
	main.framing.offset_x = original_offset.x
	main.framing.offset_y = original_offset.y
	main.framing.apply()
	check_result("original_harbor_actor_preferences_and_framing_restored", main.get_node("WorldTravel").current_region() == "harbor"
		and main.player.capture_state() == original_actor and settings(main) == original_settings
		and main.player.spawn_position.distance_to(original_spawn) < .001
		and main.player.ui_input_blocked == original_input_blocked
		and combat_save_restored
		and tree.get_meta("world_region", "") == "harbor" and not tree.has_meta("world_travel_spawn")
		and tree.root.find_children("TravelFade", "CanvasLayer", true, false).size() == 1
		and not main.get_node("WorldTravel/TravelFade/Veil").visible
		and Vector2(main.framing.offset_x, main.framing.offset_y).distance_to(original_offset) < .001)
	var result: Dictionary = {"candidate": candidate, "output_prefix": output_prefix, "checks": checks, "failed": checks.filter(func(c): return not c.pass),
		"duration_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0, "records": records, "drives": drives,
		"gate_states": gate_states, "arrivals": arrivals, "render_cases": render_cases, "screenshots": screenshots, "fade_input_probes": fade_input_probes,
		"qa_source_sha256": get_script().source_code.sha256_text(),
		"travel_source_sha256": FileAccess.get_file_as_string("res://scripts/world_travel.gd").sha256_text(),
		"note": "Actual directional/Shift/Space/F2/F6/R key events and a real audio PopupMenu. Only the initial harbor x40,y320 gate precondition is positioned directly; all four passages and route alignment use input. Arrivals are expected grounded by design. Native framebuffer appearance and performance are outside this behavioral suite. Original actor/preferences/framing and travel metadata are restored via a final harbor reload."}
	var output := FileAccess.open("res://docs/"+output_prefix+"_travel_checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	return {"checks": checks.size(), "failed": result.failed, "render_cases": render_cases.size(), "recorded_rows": records.size()}
