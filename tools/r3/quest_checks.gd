extends RefCounted
## A real input/scene/save quest loop in a unique QA profile. Run on a root job.

const ProgressScript = preload("res://scripts/adventure_progress.gd")
const HARBOR: String = "res://scenes/west_coast_r1.tscn"
const META_KEYS: Array[String] = ["route_hero_hp", "tower_boss_state", "first_encounter_state", "world_travel_state", "world_travel_spawn", "world_region", "port_framing_offset", "port_framing_offset_x", "port_compare_state"]
var checks: Array = []
var records: Array = []
var render_cases: Array = []
var screenshots: Dictionary = {}
var started_usec: int = 0
var qa_path: String = ""
var output_prefix: String = "r3_02"


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


func point(main: Node) -> Vector2:
	return main.player.world_to_source(main.player.position) if main.player is Node3D else main.player.position


func profile_guard() -> Dictionary:
	var result: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		var path: String = ProgressScript.DEFAULT_STORAGE+suffix
		var exists: bool = FileAccess.file_exists(path)
		result[path] = {"exists": exists, "sha256": FileAccess.get_sha256(path) if exists else ""}
	return result


func qa_bundle() -> Dictionary:
	if not FileAccess.file_exists(qa_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(qa_path))
	return parsed if parsed is Dictionary else {}


func observe(tree: SceneTree, progress: Node, label: String) -> Dictionary:
	var main: Node = tree.current_scene
	if main == null:
		return {}
	var travel: Node = main.get_node_or_null("WorldTravel")
	var fight: Node = main.get_node_or_null("FirstEncounter")
	var state: Dictionary = {"phase": label, "elapsed_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"scene": main.scene_file_path, "position": point(main), "action": main.player.animation_name,
		"paused": main.player.paused, "blocked": main.player.ui_input_blocked,
		"jump_height": main.player.jump_motion.height_pixels, "quest": progress.capture_state(),
		"travel": travel.capture_state() if travel != null else {}, "combat": fight.capture_state() if fight != null else {}}
	records.append(state)
	return state


func wait_for(tree: SceneTree, progress: Node, label: String, seconds: float, until: Callable = Callable(), codes: Array = []) -> Dictionary:
	release_motion()
	for code: Key in codes:
		key(code, true)
	var start: int = Time.get_ticks_usec()
	var reached: bool = false
	var last: Dictionary = {}
	while float(Time.get_ticks_usec()-start)/1000000.0 < seconds:
		await RenderingServer.frame_post_draw
		last = observe(tree, progress, label)
		if not last.is_empty() and until.is_valid() and until.call(tree.current_scene, last):
			reached = true
			break
	release_motion()
	return {"reached": reached, "last": last, "duration_seconds": float(Time.get_ticks_usec()-start)/1000000.0}


func ready_in(region: String) -> Callable:
	return func(_main: Node, state: Dictionary): return state.travel.get("region", "") == region and state.travel.get("phase", "") == "ready"


func screenshot(main: Node, name: String, progress: Node) -> void:
	var path: String = "res://docs/previews/" + output_prefix + "_"+name+".png"
	var error: Error = main.get_viewport().get_texture().get_image().save_png(path)
	screenshots[name] = {"path": path, "save_error": error, "quest": progress.capture_state(), "scene": main.scene_file_path}


func fight_with_actual_controls(tree: SceneTree, progress: Node) -> Dictionary:
	var main: Node = tree.current_scene
	var fight: Node = main.get_node("FirstEncounter")
	var before: Dictionary = fight.capture_state()
	var casts: Array = []
	for attempt: int in 6:
		if fight.cleared or fight.player_hp <= 0:
			break
		var ready: Dictionary = await wait_for(tree, progress, "fight_control_ready_"+str(attempt), 1.5,
			func(m: Node, s: Dictionary): return bool(s.combat.get("cleared", false)) or (not m.player._one_shot and not m.player.ui_input_blocked and not m.player.jump_motion.is_active()))
		if not ready.reached or fight.cleared or fight.player_hp <= 0:
			break
		var gap: float = fight.enemy.world_to_source(fight.enemy.position).x-point(main).x
		var toward: Key = KEY_D if gap >= 0.0 else KEY_A
		var away: Key = KEY_A if gap >= 0.0 else KEY_D
		if absf(gap) < 105.0:
			await wait_for(tree, progress, "fight_actual_run_retreat_"+str(attempt), 1.0,
				func(m: Node, _s: Dictionary): return absf(m.get_node("FirstEncounter").enemy.world_to_source(m.get_node("FirstEncounter").enemy.position).x-point(m).x) >= 112.0, [away, KEY_SHIFT])
		elif absf(gap) > 118.0:
			await wait_for(tree, progress, "fight_actual_approach_"+str(attempt), 2.0,
				func(m: Node, _s: Dictionary): return absf(m.get_node("FirstEncounter").enemy.world_to_source(m.get_node("FirstEncounter").enemy.position).x-point(m).x) <= 112.0, [toward])
		gap = fight.enemy.world_to_source(fight.enemy.position).x-point(main).x
		toward = KEY_D if gap >= 0.0 else KEY_A
		if main.player.facing != (1 if gap >= 0.0 else -1):
			await wait_for(tree, progress, "fight_actual_facing_"+str(attempt), .03, Callable(), [toward])
		var instance: int = main.player.attack_instance
		var cast_gap: float = fight.enemy.world_to_source(fight.enemy.position).x-point(main).x
		tap(KEY_Q)
		await wait_for(tree, progress, "fight_actual_Q_"+str(attempt), 1.2,
			func(m: Node, s: Dictionary): return bool(s.combat.get("cleared", false)) or (not m.player._one_shot and not m.player.ui_input_blocked))
		casts.append({"attempt": attempt, "gap_at_cast": cast_gap, "attack_accepted": main.player.attack_instance > instance, "after": fight.capture_state()})
	return {"before": before, "after": fight.capture_state(), "casts": casts, "AI_enabled": not fight.qa_freeze_enemy}


func quest_flow(tree: SceneTree, progress: Node) -> void:
	var main: Node = tree.current_scene
	tap(KEY_R)
	await wait_for(tree, progress, "default_harbor", .1)
	tap(KEY_E)
	await wait_for(tree, progress, "E_far_from_NPC", .06)
	check_result("E_far_from_Lorian_does_not_open_dialog", not progress.capture_state().dialog_open and not progress.can_interact())
	var approach_npc: Dictionary = await wait_for(tree, progress, "actual_walk_to_Lorian", 2.0,
		func(m: Node, _s: Dictionary): return absf(point(m).x-300.0) <= 8.0, [KEY_A, KEY_SHIFT])
	check_result("actual_walk_reaches_NPC_interaction_zone", approach_npc.reached and progress.can_interact(), {"position": point(main)})
	if not approach_npc.reached:
		return
	tap(KEY_F2)
	tap(KEY_E)
	await wait_for(tree, progress, "E_while_paused", .06)
	var pause_blocks: bool = main.player.paused and not progress.capture_state().dialog_open
	tap(KEY_F2)
	var popup: PopupMenu = main.preview_controls.audio_menu.get_popup()
	popup.popup()
	await wait_for(tree, progress, "menu_open", .04)
	tap(KEY_E)
	await wait_for(tree, progress, "E_while_menu_open", .06)
	var menu_blocks: bool = popup.visible and not progress.capture_state().dialog_open
	popup.hide()
	await wait_for(tree, progress, "menu_closed", .05)
	main.get_viewport().gui_release_focus()
	tap(KEY_SPACE)
	await wait_for(tree, progress, "prepare_airborne_interaction", .5,
		func(m: Node, _s: Dictionary): return m.player.jump_motion.height_pixels > 15.0)
	tap(KEY_E)
	await wait_for(tree, progress, "E_while_airborne", .05)
	var air_blocks: bool = main.player.jump_motion.is_active() and not progress.capture_state().dialog_open
	await wait_for(tree, progress, "land_before_dialog", 1.3,
		func(m: Node, _s: Dictionary): return not m.player.jump_motion.is_active())
	check_result("pause_menu_and_airborne_states_block_NPC_E", pause_blocks and menu_blocks and air_blocks,
		{"pause": pause_blocks, "menu": menu_blocks, "airborne": air_blocks})
	tap(KEY_E)
	await wait_for(tree, progress, "actual_E_opens_quest_dialog", .08)
	check_result("actual_E_opens_available_quest_dialog", progress.capture_state().dialog_open and progress.progress.quest_stage == "available")
	screenshot(main, "quest_dialog", progress)
	var dialog_point: Vector2 = point(main)
	var dialog_instance: int = main.player.attack_instance
	tap(KEY_X)
	tap(KEY_SPACE)
	await wait_for(tree, progress, "dialog_blocks_gameplay", .2, Callable(), [KEY_A, KEY_W, KEY_SHIFT])
	check_result("modal_dialog_blocks_movement_attack_and_jump_without_accepting", progress.capture_state().dialog_open and progress.progress.quest_stage == "available"
		and point(main).distance_to(dialog_point) < .001 and main.player.attack_instance == dialog_instance and not main.player.jump_motion.is_active())
	tap(KEY_ENTER)
	await wait_for(tree, progress, "actual_Enter_accepts_quest", .1)
	var accepted: Dictionary = progress.capture_state()
	var accepted_file: Dictionary = qa_bundle()
	check_result("actual_Enter_accepts_and_saves_active_quest_then_releases_controls", accepted.progress.quest_stage == "active" and accepted_file.get("quest_stage", "") == "active"
		and not accepted.progress.objective_cleared and int(accepted.progress.coins) == 0 and not accepted.dialog_open and not main.player.ui_input_blocked,
		{"state": accepted, "QA_saved_bundle": accepted_file})
	if accepted.progress.quest_stage != "active":
		return
	var outbound: Dictionary = await wait_for(tree, progress, "quest_harbor_to_approach", 3.0, ready_in("approach"), [KEY_A, KEY_SHIFT])
	if not outbound.reached:
		check_result("actual_route_reaches_hall_for_active_quest", false, outbound)
		return
	var door_x: Dictionary = await wait_for(tree, progress, "quest_align_tower_door", 3.5,
		func(m: Node, _s: Dictionary): return absf(point(m).x-430.0) < 8.0, [KEY_A, KEY_SHIFT])
	var hall: Dictionary = await wait_for(tree, progress, "quest_approach_to_hall", 3.0, ready_in("hall"), [KEY_W, KEY_SHIFT]) if door_x.reached else {"reached": false}
	main = tree.current_scene
	check_result("actual_route_reaches_hall_for_active_quest", hall.reached and progress.progress.quest_stage == "active")
	if not hall.reached:
		return
	var combat: Dictionary = await fight_with_actual_controls(tree, progress)
	check_result("actual_AI_enabled_fight_creates_objective_victory", combat.AI_enabled and int(combat.before.enemy_hp) == 90
		and combat.after.cleared and int(combat.after.enemy_hp) == 0 and int(combat.after.player_hp) > 0, combat)
	var receipt: Dictionary = await wait_for(tree, progress, "victory_auto_saves_return_receipt", 1.0,
		func(_m: Node, s: Dictionary): return s.quest.progress.quest_stage == "return" and s.quest.progress.objective_cleared)
	screenshot(main, "quest_victory", progress)
	var return_file: Dictionary = qa_bundle()
	check_result("observed_victory_automatically_saves_return_receipt", receipt.reached and return_file.get("quest_stage", "") == "return"
		and return_file.get("objective_cleared", false) and int(return_file.get("coins", -1)) == 0, {"QA_saved_bundle": return_file})
	if not receipt.reached:
		return
	var receipt_hash: String = FileAccess.get_sha256(qa_path)
	tap(KEY_R)
	await wait_for(tree, progress, "practice_retry_keeps_quest_receipt", .12)
	var practice: Dictionary = main.get_node("FirstEncounter").capture_state()
	check_result("actual_R_practice_reset_retains_saved_completion_receipt", not practice.cleared and int(practice.enemy_hp) == 90
		and progress.progress.quest_stage == "return" and progress.progress.objective_cleared and FileAccess.get_sha256(qa_path) == receipt_hash, {"combat": practice})
	var retreat: Dictionary = await wait_for(tree, progress, "quest_hall_to_approach", 3.0, ready_in("approach"), [KEY_S, KEY_SHIFT])
	var lane: Dictionary = await wait_for(tree, progress, "quest_approach_lower_lane", 1.5,
		func(m: Node, _s: Dictionary): return point(m).y >= 318.0, [KEY_S, KEY_SHIFT]) if retreat.reached else {"reached": false}
	var harbor: Dictionary = await wait_for(tree, progress, "quest_return_to_harbor", 4.5, ready_in("harbor"), [KEY_D, KEY_SHIFT]) if lane.reached else {"reached": false}
	check_result("actual_return_route_keeps_reward_receipt", harbor.reached and progress.progress.quest_stage == "return" and progress.progress.objective_cleared)
	if not harbor.reached:
		return
	main = tree.current_scene
	var returned_npc: Dictionary = await wait_for(tree, progress, "actual_return_walk_to_Lorian", 2.0,
		func(m: Node, _s: Dictionary): return absf(point(m).x-300.0) < 8.0, [KEY_D, KEY_SHIFT])
	if not returned_npc.reached:
		check_result("actual_E_Enter_claims_exactly40_once", false, returned_npc)
		return
	tap(KEY_E)
	await wait_for(tree, progress, "return_reward_dialog", .06)
	screenshot(main, "reward_dialog", progress)
	var reward_dialog: bool = progress.capture_state().dialog_open and progress.progress.quest_stage == "return"
	tap(KEY_ENTER)
	await wait_for(tree, progress, "actual_Enter_claims_reward", .1)
	var claimed: Dictionary = progress.capture_state()
	var claimed_file: Dictionary = qa_bundle()
	check_result("actual_E_Enter_claims_exactly40_once", reward_dialog and claimed.progress.quest_stage == "completed" and claimed.progress.reward_granted
		and int(claimed.progress.coins) == 40 and int(claimed_file.get("coins", -1)) == 40 and not claimed.dialog_open, {"state": claimed, "QA_saved_bundle": claimed_file})
	screenshot(main, "quest_completed", progress)
	var claimed_hash: String = FileAccess.get_sha256(qa_path)
	for _i: int in 2:
		tap(KEY_E)
		await wait_for(tree, progress, "repeat_completed_dialog", .04)
		tap(KEY_ENTER)
		await wait_for(tree, progress, "close_completed_dialog", .04)
	check_result("reopening_completed_dialog_cannot_grant_second_reward", int(progress.progress.coins) == 40 and progress.progress.reward_granted
		and progress.capture_state().save_attempts == claimed.save_attempts and FileAccess.get_sha256(qa_path) == claimed_hash and not progress.capture_state().dialog_open)
	var clone: Node = ProgressScript.new()
	clone.name = "QuestReloadProbe"
	tree.root.add_child(clone)
	clone.set_process(false)
	clone.set_physics_process(false)
	clone.set_process_input(false)
	var reloaded: bool = clone.configure_storage(qa_path, true)
	var clone_state: Dictionary = clone.capture_state()
	clone.queue_free()
	await wait_for(tree, progress, "reload_probe_freed", .04)
	check_result("independent_QA_profile_reload_retains_completed40", reloaded and clone_state.progress.quest_stage == "completed"
		and clone_state.progress.objective_cleared and clone_state.progress.reward_granted and int(clone_state.progress.coins) == 40, {"reload_state": clone_state})
	var hud: CanvasItem = main.get_node("PortClip/QuestObjective")
	tap(KEY_TAB)
	await wait_for(tree, progress, "Tab_hides_quest_HUD", .05)
	var hidden: bool = not hud.is_visible_in_tree()
	tap(KEY_TAB)
	await wait_for(tree, progress, "Tab_restores_quest_HUD", .05)
	check_result("actual_Tab_hides_and_restores_quest_objective", hidden and hud.is_visible_in_tree())
	tap(KEY_F2)
	var profile_before_F4: Dictionary = progress.progress.duplicate(true)
	tap(KEY_F4)
	await tree.scene_changed
	await wait_for(tree, progress, "R0_comparison_settled", .05)
	main = tree.current_scene
	tap(KEY_E)
	await wait_for(tree, progress, "R0_E_is_not_quest_interaction", .05)
	var R0_blocked: bool = main.scene_file_path.ends_with("west_coast_r0.tscn") and not progress.capture_state().dialog_open \
		and main.get_node_or_null("WorldTravel") == null and not progress.can_interact()
	tap(KEY_F4)
	await tree.scene_changed
	await wait_for(tree, progress, "R1_comparison_return_settled", .06)
	main = tree.current_scene
	tap(KEY_F2)
	check_result("F4_R0_has_no_quest_or_portal_and_return_retains_profile", R0_blocked and main.scene_file_path == HARBOR
		and progress.progress == profile_before_F4 and not progress.capture_state().dialog_open, {"R0_interaction_blocked": R0_blocked})
	var before_move: Vector2 = point(main)
	await wait_for(tree, progress, "free_movement_after_all_dialogs", .08, Callable(), [KEY_D])
	var controller_count: int = 0
	for node: Node in tree.root.get_children():
		if node.get_script() == ProgressScript:
			controller_count += 1
	check_result("one_persistent_controller_one_closed_dialog_and_free_controls", controller_count == 1
		and is_instance_valid(progress._layer) and progress._layer.get_parent() == progress
		and progress.get_children().filter(func(n): return n is CanvasLayer).size() == 1 and not progress.capture_state().dialog_open
		and not main.player.ui_input_blocked and point(main).x > before_move.x+3.0,
		{"controller_count": controller_count, "dialog_count": tree.root.find_children("QuestDialog", "CanvasLayer", true, false).size()})


func run(main: Node, candidate: String = "R3/02") -> Dictionary:
	output_prefix = candidate.to_lower().replace("/", "_")
	var tree: SceneTree = main.get_tree()
	started_usec = Time.get_ticks_usec()
	var formal_before: Dictionary = profile_guard()
	var progress: Node = tree.root.get_node_or_null("AdventureProgress")
	if progress == null:
		check_result("persistent_quest_controller_is_integrated", false)
		return {"checks": checks.size(), "failed": checks}
	qa_path = "user://qa/quest_live_"+str(Time.get_unix_time_from_system()).replace(".", "_")+"_"+str(Time.get_ticks_usec())+".json"
	# Switch before any E/Enter call, then touch only this unique QA profile.
	var configured: bool = progress.configure_storage(qa_path, false)
	var controller_id: int = progress.get_instance_id()
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
	check_result("QA_profile_is_isolated_available_and_initial_area_is_harbor", configured and progress.storage_path == qa_path
		and progress.progress.quest_stage == "available" and main.scene_file_path == HARBOR and not FileAccess.file_exists(qa_path), {"QA_storage_path": qa_path})
	if configured and main.scene_file_path == HARBOR:
		await quest_flow(tree, progress)
	release_motion()
	progress.close_dialog()
	for meta_key: String in META_KEYS:
		if original_meta[meta_key].present:
			tree.set_meta(meta_key, original_meta[meta_key].value)
		elif tree.has_meta(meta_key):
			tree.remove_meta(meta_key)
	tree.change_scene_to_file(HARBOR)
	await tree.scene_changed
	await wait_for(tree, progress, "cleanup_harbor_ready", .6, ready_in("harbor"))
	main = tree.current_scene
	# The old hall's _exit_tree may save late. Restore after it has gone.
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
	var formal_after: Dictionary = profile_guard()
	check_result("formal_profile_and_backup_bytes_unchanged", formal_before == formal_after, {"before": formal_before, "after": formal_after})
	check_result("default_storage_and_original_player_restored_on_clean_harbor", default_loaded and progress.storage_path == ProgressScript.DEFAULT_STORAGE
		and progress.get_instance_id() == controller_id and not progress.capture_state().dialog_open and main.scene_file_path == HARBOR
		and main.player.capture_state() == original_actor and preferences.settings(main) == original_preferences
		and main.player.ui_input_blocked == original_blocked and not tree.has_meta("world_travel_spawn"))
	check_result("dialog_victory_and_reward_screenshots_saved", screenshots.has("quest_dialog") and screenshots.has("quest_victory") and screenshots.has("reward_dialog") and screenshots.has("quest_completed")
		and screenshots.values().all(func(s): return s.save_error == OK), {"screenshots": screenshots})
	var result: Dictionary = {"candidate": candidate, "checks": checks, "failed": checks.filter(func(c): return not c.pass),
		"duration_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0, "QA_storage_path": qa_path,
		"QA_storage_absolute_path": ProjectSettings.globalize_path(qa_path), "formal_profile_before": formal_before, "formal_profile_after": formal_after,
		"records": records, "screenshots": screenshots, "qa_source_sha256": get_script().source_code.sha256_text(),
		"progress_source_sha256": FileAccess.get_file_as_string("res://scripts/adventure_progress.gd").sha256_text(),
		"note": "Actual E/Enter dialogue, directional route, AI-enabled spacing/Q victory, practice R, reward and comparison controls. No health/position writes, AI freeze or clock acceleration in the quest route. All quest writes target one unique user://qa profile; the formal profile is checked only for presence/hash by this QA, then normal default-profile loading is restored. Corrupt/backup schema cases belong to the separate storage suite."}
	var output := FileAccess.open("res://docs/" + output_prefix + "_quest_checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	return {"checks": checks.size(), "failed": result.failed, "render_cases": render_cases.size(), "recorded_rows": records.size()}
