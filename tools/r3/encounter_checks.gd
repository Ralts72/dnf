extends RefCounted
## Native behavior checks; run with a pose_check_job on SceneTree.root.
## Positions and one low-HP fixture are staged. Combat clocks are never advanced
## manually, and the final victory uses actual controls with the enemy AI enabled.

const HARBOR: String = "res://scenes/west_coast_r1.tscn"
const META_KEYS: Array[String] = ["first_encounter_state", "world_travel_state", "world_travel_spawn", "world_region", "port_framing_offset", "port_framing_offset_x", "port_compare_state"]
var checks: Array = []
var records: Array = []
var render_cases: Array = []
var started_usec: int = 0


func check_result(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check": label, "pass": passed, "details": details})
	render_cases.append({"check": label, "pass": passed})


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
	for code: Key in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SHIFT, KEY_SPACE, KEY_X, KEY_Q]:
		key(code, false)


func current(tree: SceneTree) -> Node:
	return tree.current_scene


func encounter(main: Node) -> Node:
	return main.get_node_or_null("FirstEncounter") if main != null else null


func point(main: Node) -> Vector2:
	return main.player.world_to_source(main.player.position)


func counter(state: Dictionary, name: String) -> int:
	return int(state.get("event_counters", {}).get(name, 0))


func observe(tree: SceneTree, label: String, phase_started: int) -> Dictionary:
	var main: Node = current(tree)
	if main == null or main.get_node_or_null("WorldTravel") == null:
		return {}
	var travel: Dictionary = main.get_node("WorldTravel").capture_state()
	var e: Node = encounter(main)
	var state: Dictionary = e.capture_state() if e != null else {}
	var now: int = Time.get_ticks_usec()
	records.append({"phase": label, "elapsed_seconds": float(now-started_usec)/1000000.0,
		"phase_seconds": float(now-phase_started)/1000000.0, "region": travel.get("region", ""),
		"travel_phase": travel.get("phase", ""), "player_position": point(main),
		"hero_action": main.player.animation_name, "hero_frame": main.player.frame_index,
		"hero_attack_instance": main.player.attack_instance, "jump_height": main.player.jump_motion.height_pixels,
		"paused": main.player.paused, "ui_input_blocked": main.player.ui_input_blocked,
		"encounter": state})
	return state


func wait_for(tree: SceneTree, label: String, seconds: float, until: Callable = Callable(), codes: Array = []) -> Dictionary:
	release_motion()
	for code: Key in codes:
		key(code, true)
	var start: int = Time.get_ticks_usec()
	var reached: bool = false
	var state: Dictionary = {}
	while float(Time.get_ticks_usec()-start)/1000000.0 < seconds:
		await RenderingServer.frame_post_draw
		state = observe(tree, label, start)
		var main: Node = current(tree)
		if main != null and until.is_valid() and until.call(main, state):
			reached = true
			break
	release_motion()
	return {"reached": reached, "state": state, "duration_seconds": float(Time.get_ticks_usec()-start)/1000000.0}


func ready_in(region: String) -> Callable:
	return func(main: Node, _state: Dictionary):
		var travel: Node = main.get_node_or_null("WorldTravel")
		return travel != null and travel.current_region() == region and travel.capture_state().get("phase", "") == "ready"


func enter_hall(tree: SceneTree) -> bool:
	var main: Node = current(tree)
	var region: String = main.get_node("WorldTravel").current_region()
	if region == "hall":
		return encounter(main) != null
	if region == "harbor":
		main.player.reset_position()
		var first: Dictionary = await wait_for(tree, "enter_approach", 4.5, ready_in("approach"), [KEY_A, KEY_SHIFT])
		if not first.reached:
			return false
	var aligned: Dictionary = await wait_for(tree, "align_tower_door", 3.5,
		func(m: Node, _state: Dictionary): return absf(point(m).x-430.0) < 8.0, [KEY_A, KEY_SHIFT])
	if not aligned.reached:
		return false
	var entered: Dictionary = await wait_for(tree, "enter_hall", 3.0, ready_in("hall"), [KEY_W, KEY_SHIFT])
	return entered.reached and encounter(current(tree)) != null


func fixture(main: Node, hero: Vector2 = Vector2(440, 315), enemy_point: Vector2 = Vector2(505, 315), facing: int = 1, freeze_ai: bool = true) -> Node:
	release_motion()
	var e: Node = encounter(main)
	e.reset_encounter()
	e.qa_freeze_enemy = freeze_ai
	main._set_paused(false)
	if main.player.markers_visible:
		main._toggle_markers()
	main.player.ui_input_blocked = false
	main.player.free_control()
	main.player.position = main.player.source_to_world(hero)
	main.player.facing = facing
	main.player.next_attack = "attack1"
	main.player.velocity = Vector3.ZERO
	main.player._update_sprite_transform()
	main.player.motion_smoothing.reset()
	e.enemy.position = e.enemy.source_to_world(enemy_point)
	e.enemy.facing = -facing
	e.enemy.hold_pose("stay", 0)
	e.enemy.reset_physics_interpolation()
	main.framing.advance(0.0, true)
	main.get_viewport().gui_release_focus()
	return e


func actual_retry(tree: SceneTree, label: String) -> bool:
	var e: Node = encounter(current(tree))
	var before: Dictionary = e.capture_state()
	tap(KEY_R)
	await wait_for(tree, label, .12)
	var main: Node = current(tree)
	e = encounter(main)
	var after: Dictionary = e.capture_state()
	return int(after.player_hp) == 100 and int(after.enemy_hp) == 90 and not after.cleared \
		and not main.player.ui_input_blocked and not main.player.paused and not main.player.jump_motion.is_active() \
		and point(main).distance_to(main.player.spawn_position) < .001 and counter(after, "resets") == counter(before, "resets")+1


func combat_cases(tree: SceneTree) -> void:
	var main: Node = current(tree)
	var attack_cases: Array = [{"action": "attack1", "key": KEY_X, "damage": 18, "pre": .10},
		{"action": "attack2", "key": KEY_X, "damage": 22, "pre": .10},
		{"action": "attack3", "key": KEY_X, "damage": 30, "pre": .06},
		{"action": "hopsmash", "key": KEY_Q, "damage": 36, "pre": .27}]
	for test: Dictionary in attack_cases:
		var e: Node = fixture(main)
		main.player.next_attack = test.action if test.action != "hopsmash" else "attack1"
		var before: Dictionary = e.capture_state()
		tap(test.key)
		await wait_for(tree, test.action+"_before_hit_window", test.pre)
		var early: Dictionary = e.capture_state()
		await wait_for(tree, test.action+"_whole_source_action", 1.0-float(test.pre))
		var after: Dictionary = e.capture_state()
		check_result(test.action+"_real_input_hits_once_in_its_action", int(early.enemy_hp) == 90
			and int(after.enemy_hp) == 90-int(test.damage) and counter(after, "hero_hits") == counter(before, "hero_hits")+1,
			{"before": before, "before_active_window": early, "after": after})
	var miss_cases: Array = [{"name": "outside_horizontal_reach", "hero": Vector2(350,315), "enemy": Vector2(550,315), "facing": 1},
		{"name": "outside_depth_lane", "hero": Vector2(440,270), "enemy": Vector2(505,335), "facing": 1},
		{"name": "behind_hero_facing", "hero": Vector2(500,315), "enemy": Vector2(435,315), "facing": 1}]
	for test: Dictionary in miss_cases:
		var e: Node = fixture(main, test.hero, test.enemy, test.facing)
		var before: Dictionary = e.capture_state()
		tap(KEY_X)
		await wait_for(tree, test.name, .72)
		var after: Dictionary = e.capture_state()
		check_result(test.name+"_does_not_damage_enemy", int(after.enemy_hp) == 90 and counter(after, "hero_hits") == counter(before, "hero_hits"), {"after": after})
	var e: Node = fixture(main)
	tap(KEY_F2)
	var paused_before: Dictionary = e.capture_state()
	tap(KEY_X)
	tap(KEY_Q)
	await wait_for(tree, "paused_combat_inputs", .5)
	var paused_after: Dictionary = e.capture_state()
	check_result("actual_pause_blocks_combat_input_and_damage", main.player.paused and int(paused_after.enemy_hp) == 90 and int(paused_after.player_hp) == 100
		and counter(paused_after, "hero_hits") == counter(paused_before, "hero_hits"))
	e = fixture(main, Vector2(440,315), Vector2(485,315), 1, false)
	var popup: PopupMenu = main.preview_controls.audio_menu.get_popup()
	popup.popup()
	var menu_before: Dictionary = e.capture_state()
	tap(KEY_X)
	tap(KEY_Q)
	await wait_for(tree, "menu_combat_lock", .65)
	var menu_after: Dictionary = e.capture_state()
	check_result("actual_open_menu_blocks_both_combat_sides", popup.visible and int(menu_after.player_hp) == 100 and int(menu_after.enemy_hp) == 90
		and counter(menu_after, "enemy_attacks") == counter(menu_before, "enemy_attacks"))
	popup.hide()
	e = fixture(main, Vector2(440,315), Vector2(485,315), 1, false)
	main.player.preview("attack1")
	var preview_before: Dictionary = e.capture_state()
	await wait_for(tree, "pose_preview_combat_lock", .7)
	var preview_after: Dictionary = e.capture_state()
	check_result("pose_inspection_neither_hits_nor_invites_enemy_attack", main.player.preview_mode and int(preview_after.enemy_hp) == 90 and int(preview_after.player_hp) == 100
		and counter(preview_after, "enemy_attacks") == counter(preview_before, "enemy_attacks"))
	e = fixture(main, Vector2(440,315), Vector2(490,315), 1, false)
	var strike_before: Dictionary = e.capture_state()
	var windup: Dictionary = await wait_for(tree, "enemy_begins_actual_attack", 2.0,
		func(_m: Node, state: Dictionary): return counter(state, "enemy_attacks") > counter(strike_before, "enemy_attacks"))
	var hit: Dictionary = await wait_for(tree, "enemy_real_strike", 1.0,
		func(_m: Node, state: Dictionary): return int(state.get("player_hp", 100)) < 100)
	var struck: Dictionary = e.capture_state()
	check_result("enemy_actual_source_attack_damages_noninvincible_player", windup.reached and hit.reached and int(struck.player_hp) == 88
		and counter(struck, "enemy_hits") == counter(strike_before, "enemy_hits")+1, {"before": strike_before, "after": struck})
	check_result("enemy_strike_follows_source_310ms_telegraph", hit.reached and float(struck.get("enemy_action_elapsed_ms", -1.0)) >= 310.0-.1
		and float(hit.duration_seconds)+float(windup.state.get("enemy_action_elapsed_ms", 0.0))/1000.0 >= .285,
		{"windup": windup, "hit": hit, "sampling_tolerance_seconds": .025})
	e = fixture(main, Vector2(440,315), Vector2(490,315), 1, false)
	var dodge_before: Dictionary = e.capture_state()
	tap(KEY_SPACE)
	await wait_for(tree, "jump_avoids_ground_strike", .9)
	var dodge_after: Dictionary = e.capture_state()
	var dodge_rows: Array = records.filter(func(r): return r.phase == "jump_avoids_ground_strike")
	check_result("actual_jump_clears_enemy_active_ground_strike", int(dodge_after.player_hp) == 100 and counter(dodge_after, "enemy_attacks") > counter(dodge_before, "enemy_attacks")
		and dodge_rows.any(func(r): return r.jump_height > 35.0 and float(r.encounter.get("enemy_action_elapsed_ms", -1.0)) >= 310.0), {"after": dodge_after})
	e = fixture(main)
	tap(KEY_SPACE)
	var descending: Dictionary = await wait_for(tree, "prepare_descending_air_attack", 1.2,
		func(m: Node, _state: Dictionary): return m.player.jump_motion.phase == "falling" and m.player.jump_motion.height_pixels <= 65.0 and m.player.jump_motion.height_pixels > 35.0)
	var air_before: Dictionary = e.capture_state()
	tap(KEY_X)
	await wait_for(tree, "actual_air_attack", .5)
	var air_after: Dictionary = e.capture_state()
	check_result("actual_descending_air_attack_hits_once", descending.reached and int(air_after.enemy_hp) == 72 and counter(air_after, "hero_hits") == counter(air_before, "hero_hits")+1, {"after": air_after})
	e = fixture(main, Vector2(440,315), Vector2(490,315), 1, false)
	var hurt_for_inspection: Dictionary = await wait_for(tree, "hurt_before_inspection_pause", 2.0,
		func(_m: Node, state: Dictionary): return float(state.get("hero_hurt_remaining", 0.0)) > .05)
	tap(KEY_F2)
	await wait_for(tree, "hurt_paused_for_inspection", .05)
	var paused_hurt: bool = main.player.paused and main.player.ui_input_blocked
	# Exercise the actual GUI button's connected signal, then close inspection
	# through the keyboard path that previously could be blocked by the hurt lock.
	main.get_node("Interface/Buttons/Markers").pressed.emit()
	var gui_opened_inspection: bool = main.player.markers_visible
	tap(KEY_F1)
	var keyboard_closed_inspection: bool = not main.player.markers_visible
	tap(KEY_F2)
	var resumed: Dictionary = await wait_for(tree, "hurt_inspection_resumes", .9,
		func(m: Node, state: Dictionary): return not m.player.paused and not m.player.ui_input_blocked and float(state.get("hero_hurt_remaining", 1.0)) == 0.0)
	var resume_point: Vector2 = point(main)
	await wait_for(tree, "actual_movement_after_hurt_inspection", .08, Callable(), [KEY_D])
	check_result("hurt_pause_GUI_inspection_can_close_by_F1_and_resume_control", hurt_for_inspection.reached and paused_hurt and gui_opened_inspection
		and keyboard_closed_inspection and resumed.reached and point(main).x > resume_point.x+3.0,
		{"paused_hurt": paused_hurt, "GUI_button_signal_opened": gui_opened_inspection, "keyboard_F1_closed": keyboard_closed_inspection, "resumed": resumed.reached})
	e = fixture(main)
	var combo_before: Dictionary = e.capture_state()
	var combo_instance: int = main.player.attack_instance
	tap(KEY_X)
	await wait_for(tree, "combo_first_attack_before_buffer_tap", .45)
	tap(KEY_X)
	var queue_observed: bool = main.player.queued_attack and main.player.attack_buffer_remaining > 0.0
	await wait_for(tree, "combo_buffered_second_attack", 1.0)
	var combo_after: Dictionary = e.capture_state()
	var two_instances: bool = main.player.attack_instance == combo_instance+2
	await wait_for(tree, "combo_idle_without_third_keypress", .35)
	check_result("two_actual_X_taps_buffer_exactly_two_hits_then_idle", main.player.combat_buffer_enabled and queue_observed and two_instances
		and int(combo_after.enemy_hp) == 50 and counter(combo_after, "hero_hits") == counter(combo_before, "hero_hits")+2
		and main.player.attack_instance == combo_instance+2 and not main.player._one_shot and not main.player.queued_attack
		and main.player.animation_name == "stay" and int(e.enemy_hp) == 50,
		{"queue_observed_at_450ms": queue_observed, "two_attack_instances": two_instances, "after": combo_after})
	e = fixture(main, Vector2(440,315), Vector2(490,315), 1, false)
	# Explicit low-health precondition bounds the defeat test to one real strike.
	# No health writes occur in the subsequent final-victory scenario.
	e.player_hp = 12
	var defeated: Dictionary = await wait_for(tree, "actual_enemy_causes_player_defeat", 2.0,
		func(_m: Node, state: Dictionary): return int(state.get("player_hp", 100)) <= 0)
	var defeated_point: Vector2 = point(main)
	var defeated_attack_instance: int = main.player.attack_instance
	tap(KEY_X)
	await wait_for(tree, "defeated_player_input_lock", .2, Callable(), [KEY_D])
	var defeat_state: Dictionary = e.capture_state()
	check_result("actual_enemy_strike_can_defeat_and_lock_player", defeated.reached and int(defeat_state.player_hp) == 0
		and main.player.ui_input_blocked and int(defeat_state.enemy_hp) == 90 and point(main).distance_to(defeated_point) < .001
		and main.player.attack_instance == defeated_attack_instance, {"after": defeat_state})
	check_result("actual_R_retries_after_player_defeat", await actual_retry(tree, "retry_after_defeat"))
	e = fixture(main)
	tap(KEY_X)
	await wait_for(tree, "alive_enemy_damage_before_retreat", .7)
	var alive_before: Dictionary = e.capture_state()
	e.qa_freeze_enemy = false
	var alive_retreat: Dictionary = await wait_for(tree, "alive_enemy_retreat", 3.0, ready_in("approach"), [KEY_S, KEY_SHIFT])
	var alive_return: Dictionary = await wait_for(tree, "alive_enemy_return", 3.0, ready_in("hall"), [KEY_W, KEY_SHIFT]) if alive_retreat.reached else {"reached": false}
	main = current(tree)
	var alive_after: Dictionary = encounter(main).capture_state() if encounter(main) != null else {}
	var arrival_clearance: float = point(main).distance_to(encounter(main).enemy.world_to_source(encounter(main).enemy.position)) if encounter(main) != null else 0.0
	check_result("alive_enemy_reentry_preserves_health_with_safe_arrival_clearance", alive_retreat.reached and alive_return.reached
		and int(alive_before.enemy_hp) == 72 and int(alive_after.get("enemy_hp", -1)) == 72
		and int(alive_after.get("player_hp", -1)) == int(alive_before.player_hp) and arrival_clearance > 120.0,
		{"before": alive_before, "returned": alive_after, "source_pixel_clearance": arrival_clearance})
	if encounter(main) == null:
		return
	e = fixture(main, Vector2(430,315), Vector2(540,315), 1, false)
	var victory_before: Dictionary = e.capture_state()
	var victory_inputs: Array = []
	for attempt: int in 5:
		if e.cleared or e.player_hp <= 0:
			break
		var recovered: Dictionary = await wait_for(tree, "victory_ready_"+str(attempt), 1.5,
			func(m: Node, state: Dictionary): return bool(state.get("cleared", false)) or (not m.player._one_shot and not m.player.ui_input_blocked and not m.player.jump_motion.is_active()))
		if not recovered.reached or e.cleared or e.player_hp <= 0:
			break
		var gap: float = e.enemy.world_to_source(e.enemy.position).x-point(main).x
		var toward: Key = KEY_D if gap >= 0.0 else KEY_A
		var away: Key = KEY_A if gap >= 0.0 else KEY_D
		# Retreat with actual run input before casting. A 110px separation leaves
		# time for the source360ms Q windup before a55px/s foe reaches its70px stab.
		if absf(gap) < 105.0:
			await wait_for(tree, "victory_real_retreat_"+str(attempt), .8,
				func(m: Node, _state: Dictionary): return absf(encounter(m).enemy.world_to_source(encounter(m).enemy.position).x-point(m).x) >= 112.0, [away, KEY_SHIFT])
		elif absf(gap) > 118.0:
			await wait_for(tree, "victory_real_approach_"+str(attempt), 1.0,
				func(m: Node, _state: Dictionary): return absf(encounter(m).enemy.world_to_source(encounter(m).enemy.position).x-point(m).x) <= 112.0, [toward])
		gap = e.enemy.world_to_source(e.enemy.position).x-point(main).x
		toward = KEY_D if gap >= 0.0 else KEY_A
		if main.player.facing != (1 if gap >= 0.0 else -1):
			await wait_for(tree, "victory_real_facing_"+str(attempt), .03, Callable(), [toward])
		var accepted_before: int = main.player.attack_instance
		var cast_gap: float = e.enemy.world_to_source(e.enemy.position).x-point(main).x
		tap(KEY_Q)
		var action: Dictionary = await wait_for(tree, "victory_real_Q_"+str(attempt), 1.2,
			func(m: Node, state: Dictionary): return bool(state.get("cleared", false)) or (not m.player._one_shot and not m.player.ui_input_blocked))
		victory_inputs.append({"attempt": attempt, "source_ground_gap_at_cast": cast_gap,
			"accepted_attack_instance": main.player.attack_instance > accepted_before, "action_finished": action.reached,
			"after": e.capture_state()})
	var victory: Dictionary = e.capture_state()
	check_result("actual_controls_defeat_enemy_without_final_health_writes", e.cleared and int(victory.enemy_hp) == 0 and int(victory.player_hp) > 0
		and counter(victory, "victories") == counter(victory_before, "victories")+1, {"before": victory_before, "after": victory,
		"enemy_AI_enabled": not e.qa_freeze_enemy, "actual_input_plan": victory_inputs})
	var persisted: bool = false
	var persisted_state: Dictionary = {}
	if e.cleared:
		# Evasive play may finish away from the door's x408..472 trigger lane.
		var return_direction: Key = KEY_D if point(main).x < 440.0 else KEY_A
		var aligned_return: Dictionary = await wait_for(tree, "victory_align_return_door", 3.0,
			func(m: Node, _state: Dictionary): return absf(point(m).x-440.0) < 8.0, [return_direction, KEY_SHIFT])
		var retreat: Dictionary = await wait_for(tree, "victory_retreat_to_approach", 3.0, ready_in("approach"), [KEY_S, KEY_SHIFT]) if aligned_return.reached else {"reached": false}
		if retreat.reached:
			var returned: Dictionary = await wait_for(tree, "return_to_cleared_hall", 3.0, ready_in("hall"), [KEY_W, KEY_SHIFT])
			if returned.reached:
				main = current(tree)
				e = encounter(main)
				persisted_state = e.capture_state()
				persisted = e.cleared and int(persisted_state.enemy_hp) == 0 and int(persisted_state.player_hp) == int(victory.player_hp)
	check_result("cleared_encounter_persists_after_actual_retreat_and_return", persisted, {"returned_state": persisted_state})
	if encounter(current(tree)) != null:
		check_result("actual_R_restarts_cleared_encounter", await actual_retry(tree, "retry_after_clear"))
	else:
		check_result("actual_R_restarts_cleared_encounter", false, {"reason": "Could not return to the hall"})


func run(main: Node, candidate: String = "R3/01") -> Dictionary:
	var tree: SceneTree = main.get_tree()
	started_usec = Time.get_ticks_usec()
	var original_scene: String = main.scene_file_path
	var original_actor: Dictionary = main.player.capture_state()
	var original_spawn: Vector2 = main.player.spawn_position
	var original_input_blocked: bool = main.player.ui_input_blocked
	var original_offset := Vector2(main.framing.offset_x, main.framing.offset_y)
	var preferences = preload("res://tools/r2/travel_checks.gd").new()
	var original_settings: Dictionary = preferences.settings(main)
	var original_interface: bool = main.get_node("Interface").visible
	var original_markers: bool = main.player.markers_visible
	var original_meta: Dictionary = {}
	for meta_key: String in META_KEYS:
		var present: bool = tree.has_meta(meta_key)
		var value: Variant = tree.get_meta(meta_key) if present else null
		if value is Dictionary:
			value = value.duplicate(true)
		original_meta[meta_key] = {"present": present, "value": value}
	main._set_paused(false)
	main.player.ui_input_blocked = false
	main.player.free_control()
	main.get_node("Interface").visible = true
	if main.player.markers_visible:
		main._toggle_markers()
	main.get_viewport().gui_release_focus()
	var entered: bool = await enter_hall(tree)
	check_result("hall_encounter_available_after_real_route_or_standalone_entry", entered)
	if entered:
		await combat_cases(tree)
	main = current(tree)
	var live_encounter: Node = encounter(main)
	if live_encounter != null:
		live_encounter.qa_freeze_enemy = false
	release_motion()
	for meta_key: String in META_KEYS:
		if original_meta[meta_key].present:
			tree.set_meta(meta_key, original_meta[meta_key].value)
		elif tree.has_meta(meta_key):
			tree.remove_meta(meta_key)
	tree.change_scene_to_file(HARBOR)
	await tree.scene_changed
	await wait_for(tree, "cleanup_harbor_ready", .6, ready_in("harbor"))
	main = current(tree)
	# FirstEncounter persists on _exit_tree; restore its save after the old hall
	# has actually exited, so that late persistence cannot overwrite this copy.
	if original_meta.first_encounter_state.present:
		tree.set_meta("first_encounter_state", original_meta.first_encounter_state.value)
	elif tree.has_meta("first_encounter_state"):
		tree.remove_meta("first_encounter_state")
	preferences.apply_settings(main, original_settings)
	main.get_node("Interface").visible = original_interface
	if main.player.markers_visible != original_markers:
		main._toggle_markers()
	if original_scene == HARBOR:
		main.player.restore_state(original_actor)
		main.player.spawn_position = original_spawn
		main.player.ui_input_blocked = original_input_blocked
		main._set_paused(original_actor.paused)
		main.framing.offset_x = original_offset.x
		main.framing.offset_y = original_offset.y
		main.framing.apply()
	else:
		main.player.reset_position()
		main._set_paused(false)
		main.player.ui_input_blocked = false
		main.framing.advance(0.0, true)
	var encounter_meta_restored: bool = tree.has_meta("first_encounter_state") == original_meta.first_encounter_state.present
	if encounter_meta_restored and original_meta.first_encounter_state.present:
		encounter_meta_restored = tree.get_meta("first_encounter_state") == original_meta.first_encounter_state.value
	check_result("original_combat_save_and_preferences_restored_on_clean_harbor", main.get_node("WorldTravel").current_region() == "harbor"
		and preferences.settings(main) == original_settings and encounter_meta_restored and encounter(main) == null
		and not tree.has_meta("world_travel_spawn") and tree.root.find_children("TravelFade", "CanvasLayer", true, false).size() == 1)
	var result: Dictionary = {"candidate": candidate, "checks": checks, "failed": checks.filter(func(c): return not c.pass),
		"duration_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0, "records": records,
		"qa_source_sha256": get_script().source_code.sha256_text(),
		"encounter_source_sha256": FileAccess.get_file_as_string("res://scripts/first_encounter.gd").sha256_text(),
		"enemy_source_sha256": FileAccess.get_file_as_string("res://scripts/draconian_enemy.gd").sha256_text(),
		"note": "Actual key inputs and unchanged source animation clocks. Controlled fixtures reset the encounter, stage positions and optionally freeze enemy AI; one playerHP12 fixture makes a real strike lethal. Final victory uses AI-enabled actual Q casts, running retreats and facing input at about110px separation, with no HP writes, followed by actual retreat/return and R. All three X attacks are independently checked above. No native pixel/color/performance claim. Original encounter save/preferences are restored before a fresh harbor reload."}
	var output := FileAccess.open("res://docs/r3_01_encounter_checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	return {"checks": checks.size(), "failed": result.failed, "render_cases": render_cases.size(), "recorded_rows": records.size()}
