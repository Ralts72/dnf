extends RefCounted
## Run on a pose_check_job attached to SceneTree.root. Every save uses a unique QA profile.

const ProgressScript = preload("res://scripts/adventure_progress.gd")
const QuestChecks = preload("res://tools/r3/quest_checks.gd")
const HARBOR: String = "res://scenes/west_coast_r1.tscn"
const META_KEYS: Array[String] = ["route_hero_hp", "tower_boss_state", "first_encounter_state", "world_travel_state", "world_travel_spawn", "world_region", "port_framing_offset", "port_framing_offset_x", "port_compare_state"]
var checks: Array = []
var records: Array = []
var render_cases: Array = []
var screenshots: Dictionary = {}
var started_usec: int = 0
var qa_path: String = ""
var output_prefix: String = "r3_03"
var helper: RefCounted


func check_result(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check": label, "pass": passed, "details": details})
	render_cases.append({"check": label, "pass": passed})


func key(code: Key, pressed: bool) -> void:
	helper.key(code, pressed)


func tap(code: Key) -> void:
	helper.tap(code)


func point(main: Node) -> Vector2:
	return helper.point(main)


func loot_state(main: Node) -> Dictionary:
	var loot: Node = main.get_node_or_null("FirstLoot")
	return loot.capture_state() if loot != null else {}


func observe(tree: SceneTree, progress: Node, label: String) -> Dictionary:
	var row: Dictionary = helper.observe(tree, progress, label)
	if not row.is_empty():
		row["loot"] = loot_state(tree.current_scene)
	return row


func wait_for(tree: SceneTree, progress: Node, label: String, seconds: float, until: Callable = Callable(), codes: Array = []) -> Dictionary:
	helper.release_motion()
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
	helper.release_motion()
	return {"reached": reached, "last": last, "duration_seconds": float(Time.get_ticks_usec()-start)/1000000.0}


func ready_in(region: String) -> Callable:
	return func(_main: Node, state: Dictionary): return state.travel.get("region", "") == region and state.travel.get("phase", "") == "ready" and not state.loot.is_empty()


func screenshot(main: Node, name: String, progress: Node) -> void:
	var path: String = "res://docs/previews/" + output_prefix + "_" + name + ".png"
	var error: Error = main.get_viewport().get_texture().get_image().save_png(path)
	screenshots[name] = {"path": path, "save_error": error, "scene": main.scene_file_path,
		"viewport_size": main.get_viewport_rect().size, "loot": loot_state(main), "profile": progress.capture_state()}


func saved_bundle() -> Dictionary:
	return helper.qa_bundle()


func drop_point(progress: Node) -> Vector2:
	var position: Array = progress.progress.first_drop.position
	return Vector2(position[0], position[1])


func align_x(tree: SceneTree, progress: Node, target: float, label: String) -> Dictionary:
	var toward: Key = KEY_D if target > point(tree.current_scene).x else KEY_A
	return await wait_for(tree, progress, label, 4.0,
		func(m: Node, _s: Dictionary): return absf(point(m).x-target) <= 7.0, [toward, KEY_SHIFT])


func enter_hall_from_harbor(tree: SceneTree, progress: Node, label: String) -> bool:
	var approach: Dictionary = await wait_for(tree, progress, label+"_harbor_to_approach", 4.5, ready_in("approach"), [KEY_A, KEY_SHIFT])
	if not approach.reached:
		return false
	var aligned: Dictionary = await align_x(tree, progress, 430.0, label+"_align_door")
	if not aligned.reached:
		return false
	var hall: Dictionary = await wait_for(tree, progress, label+"_approach_to_hall", 3.0, ready_in("hall"), [KEY_W, KEY_SHIFT])
	return hall.reached


func exit_hall(tree: SceneTree, progress: Node, label: String) -> bool:
	var aligned: Dictionary = await align_x(tree, progress, 440.0, label+"_align_hall_exit")
	if not aligned.reached:
		return false
	var approach: Dictionary = await wait_for(tree, progress, label+"_hall_to_approach", 3.0, ready_in("approach"), [KEY_S, KEY_SHIFT])
	return approach.reached


func return_harbor(tree: SceneTree, progress: Node, label: String) -> bool:
	if not await exit_hall(tree, progress, label):
		return false
	var lane: Dictionary = await wait_for(tree, progress, label+"_lower_lane", 1.5,
		func(m: Node, _s: Dictionary): return point(m).y >= 318.0, [KEY_S, KEY_SHIFT])
	if not lane.reached:
		return false
	var harbor: Dictionary = await wait_for(tree, progress, label+"_approach_to_harbor", 4.5, ready_in("harbor"), [KEY_D, KEY_SHIFT])
	return harbor.reached


func bag_gate_checks(tree: SceneTree, progress: Node) -> void:
	var main: Node = tree.current_scene
	tap(KEY_F2)
	tap(KEY_B)
	await wait_for(tree, progress, "B_while_paused", .05)
	var pause_blocks: bool = main.player.paused and not loot_state(main).bag_open
	tap(KEY_F2)
	var popup: PopupMenu = main.preview_controls.audio_menu.get_popup()
	popup.popup()
	await wait_for(tree, progress, "bag_gate_menu_open", .04)
	tap(KEY_B)
	await wait_for(tree, progress, "B_while_menu_open", .05)
	var menu_blocks: bool = popup.visible and not loot_state(main).bag_open
	popup.hide()
	await wait_for(tree, progress, "bag_gate_menu_closed", .04)
	main.get_viewport().gui_release_focus()
	tap(KEY_SPACE)
	await wait_for(tree, progress, "bag_gate_airborne", .5,
		func(m: Node, _s: Dictionary): return m.player.jump_motion.height_pixels > 15.0)
	tap(KEY_B)
	await wait_for(tree, progress, "B_while_airborne", .05)
	var air_blocks: bool = main.player.jump_motion.is_active() and not loot_state(main).bag_open
	await wait_for(tree, progress, "bag_gate_landed", 1.3,
		func(m: Node, _s: Dictionary): return not m.player.jump_motion.is_active())
	tap(KEY_X)
	tap(KEY_B)
	await wait_for(tree, progress, "B_while_attacking", .05)
	var action_blocks: bool = main.player._one_shot and not loot_state(main).bag_open
	await wait_for(tree, progress, "bag_gate_attack_finished", 1.0,
		func(m: Node, _s: Dictionary): return not m.player._one_shot)
	check_result("pause_menu_air_and_attack_block_actual_B", pause_blocks and menu_blocks and air_blocks and action_blocks,
		{"paused": pause_blocks, "menu": menu_blocks, "airborne": air_blocks, "attack": action_blocks})
	tap(KEY_B)
	await wait_for(tree, progress, "harbor_empty_bag_open", .05)
	var empty: Dictionary = loot_state(main)
	tap(KEY_ESCAPE)
	await wait_for(tree, progress, "harbor_empty_bag_Esc_close", .04)
	check_result("harbor_B_opens_empty_bag_and_Esc_releases_controls", empty.bag_open and int(empty.inventory_count) == 0 and not empty.drop_visible
		and not loot_state(main).bag_open and not main.player.ui_input_blocked)


func hall_modal_checks(tree: SceneTree, progress: Node) -> void:
	var main: Node = tree.current_scene
	# Stop immediately on entering the actual exit rectangle, before its 150 ms hold qualifies.
	var at_exit: Dictionary = await wait_for(tree, progress, "walk_into_hall_exit_before_hold_qualifies", .8,
		func(m: Node, _s: Dictionary): return point(m).y >= 338.0, [KEY_S, KEY_SHIFT])
	tap(KEY_B)
	await wait_for(tree, progress, "hall_bag_modal_settled", .06)
	var before: Dictionary = observe(tree, progress, "hall_bag_guard_before")
	tap(KEY_X)
	tap(KEY_Q)
	tap(KEY_SPACE)
	tap(KEY_F2)
	await wait_for(tree, progress, "bag_blocks_actual_portal_and_combat_inputs", .35, Callable(), [KEY_S, KEY_SHIFT])
	var after: Dictionary = observe(tree, progress, "hall_bag_guard_after")
	var modal: bool = at_exit.reached and before.loot.bag_open and after.loot.bag_open and after.scene == before.scene
	check_result("hall_bag_blocks_actual_exit_movement_attacks_jump_and_pause", modal and after.position.distance_to(before.position) < .001
		and after.combat.hero_attack_instance == before.combat.hero_attack_instance and after.jump_height == 0.0
		and not before.paused and not after.paused and after.travel.transition_count == before.travel.transition_count,
		{"before": before, "after": after})
	check_result("bag_modal_freezes_enemy_AI_clocks_and_damage", modal and after.combat.combat_blocked
		and after.combat.enemy_source_position.distance_to(before.combat.enemy_source_position) < .001
		and after.combat.enemy_action_elapsed_ms == before.combat.enemy_action_elapsed_ms
		and after.combat.enemy_cooldown == before.combat.enemy_cooldown
		and after.combat.event_counters == before.combat.event_counters
		and after.combat.player_hp == before.combat.player_hp and after.combat.enemy_hp == before.combat.enemy_hp)
	tap(KEY_B)
	await wait_for(tree, progress, "hall_B_closes_bag", .05)
	var closed: bool = not loot_state(main).bag_open and not main.player.ui_input_blocked
	var lane: Dictionary = await wait_for(tree, progress, "return_from_exit_to_combat_lane", .8,
		func(m: Node, _s: Dictionary): return point(m).y <= 315.0, [KEY_W, KEY_SHIFT])
	check_result("B_closes_hall_bag_and_actual_movement_resumes", closed and lane.reached)


func loot_flow(tree: SceneTree, progress: Node) -> void:
	var main: Node = tree.current_scene
	tap(KEY_R)
	await wait_for(tree, progress, "initial_harbor_free", .08)
	await bag_gate_checks(tree, progress)
	var entered: bool = await enter_hall_from_harbor(tree, progress, "first_loot_route")
	check_result("actual_directional_route_reaches_live_hall", entered and progress.progress.quest_stage == "available"
		and int(progress.progress.inventory["3128"]) == 0 and progress.progress.first_drop.state == "unearned")
	if not entered:
		return
	await hall_modal_checks(tree, progress)
	main = tree.current_scene
	var combat: Dictionary = await helper.fight_with_actual_controls(tree, progress)
	check_result("real_AI_enabled_full90HP_fight_creates_first_clear", combat.AI_enabled and int(combat.before.enemy_hp) == 90
		and combat.after.cleared and int(combat.after.enemy_hp) == 0 and int(combat.after.player_hp) > 0, combat)
	if not combat.after.cleared:
		return
	var pending: Dictionary = await wait_for(tree, progress, "first_clear_saved_pending_drop", 1.2,
		func(m: Node, s: Dictionary): return s.quest.progress.first_drop.state == "pending" and s.loot.drop_visible and not m.player._one_shot)
	var pending_file: Dictionary = saved_bundle()
	var original_drop: Vector2 = drop_point(progress)
	check_result("first_clear_saves_one_ground_drop_independently_of_quest", pending.reached and progress.progress.quest_stage == "available"
		and pending_file.get("schema", 0) == ProgressScript.PROFILE_SCHEMA and pending_file.get("first_drop", {}).get("state", "") == "pending"
		and int(pending_file.get("inventory", {}).get("3128", -1)) == 0 and not progress.capture_state().pending_save,
		{"drop_position": original_drop, "QA_saved_bundle": pending_file})
	if not pending.reached:
		return
	screenshot(main, "ground_drop", progress)
	if main.get_node("FirstLoot").can_pickup():
		var away: Key = KEY_A if point(main).x <= original_drop.x else KEY_D
		await wait_for(tree, progress, "walk_outside_pickup_radius", 1.0,
			func(m: Node, _s: Dictionary): return not m.get_node("FirstLoot").can_pickup(), [away])
	var far_before: Dictionary = loot_state(main)
	var pending_hash: String = FileAccess.get_sha256(qa_path)
	tap(KEY_E)
	await wait_for(tree, progress, "actual_E_outside_drop_radius", .06)
	check_result("grounded_free_E_outside_pickup_radius_does_not_claim", not far_before.can_pickup and not main.player._one_shot
		and not main.player.jump_motion.is_active() and not main.player.ui_input_blocked and loot_state(main).drop_visible
		and progress.progress.first_drop.state == "pending" and int(progress.progress.inventory["3128"]) == 0
		and FileAccess.get_sha256(qa_path) == pending_hash, {"before": far_before, "position": point(main)})
	var retreated: bool = await exit_hall(tree, progress, "pending_drop_retreat")
	check_result("pending_drop_remains_hall_only_after_actual_retreat", retreated and not loot_state(tree.current_scene).get("drop_visible", true)
		and progress.progress.first_drop.state == "pending" and int(progress.progress.inventory["3128"]) == 0)
	if not retreated:
		return
	var reloaded: bool = progress.configure_storage(qa_path, true)
	var reentered: Dictionary = await wait_for(tree, progress, "pending_drop_actual_reentry_after_disk_reload", 2.0, ready_in("hall"), [KEY_W, KEY_SHIFT])
	main = tree.current_scene
	var restored: Dictionary = loot_state(main)
	check_result("QA_disk_reload_and_actual_reentry_restore_pending_drop_position", reloaded and reentered.reached
		and restored.get("drop_visible", false) and restored.get("position", Vector2.INF).distance_to(original_drop) < .001
		and progress.progress.first_drop.state == "pending" and int(restored.get("inventory_count", -1)) == 0,
		{"original_position": original_drop, "restored": restored, "loaded_state": progress.capture_state()})
	if not reentered.reached:
		return
	var drop: Vector2 = drop_point(progress)
	if absf(point(main).y-drop.y) > 20.0:
		var vertical: Key = KEY_S if drop.y > point(main).y else KEY_W
		await wait_for(tree, progress, "walk_to_drop_depth", 1.5,
			func(m: Node, _s: Dictionary): return absf(point(m).y-drop.y) <= 20.0, [vertical])
	var toward: Key = KEY_D if drop.x > point(main).x else KEY_A
	var near_drop: Dictionary = await wait_for(tree, progress, "actual_walk_into_pickup_radius", 3.0,
		func(m: Node, _s: Dictionary): return m.get_node("FirstLoot").can_pickup(), [toward])
	tap(KEY_E)
	await wait_for(tree, progress, "actual_E_pickup_saves_before_disappearing", .08)
	var claimed_file: Dictionary = saved_bundle()
	var claimed: Dictionary = loot_state(main)
	check_result("actual_near_E_saves_claimed_item_then_removes_ground_drop", near_drop.reached and not claimed.drop_visible
		and int(claimed.inventory_count) == 1 and progress.progress.first_drop.state == "claimed"
		and claimed_file.get("first_drop", {}).get("state", "") == "claimed" and int(claimed_file.get("inventory", {}).get("3128", -1)) == 1
		and not progress.capture_state().pending_save, {"loot": claimed, "QA_saved_bundle": claimed_file})
	if int(claimed.inventory_count) != 1:
		return
	tap(KEY_B)
	await wait_for(tree, progress, "actual_B_shows_claimed_item", .06)
	screenshot(main, "bag_with_item", progress)
	check_result("actual_B_bag_displays_one_item_and_pickup_feedback", loot_state(main).bag_open and int(loot_state(main).inventory_count) == 1
		and main.get_node("FirstLoot")._icon.visible and main.get_node("FirstLoot")._count.text == "1"
		and str(claimed.toast).contains("获得"), {"loot": loot_state(main), "pickup_toast": claimed.toast})
	tap(KEY_B)
	await wait_for(tree, progress, "claimed_bag_closed", .04)
	var harbor: bool = await return_harbor(tree, progress, "claimed_item_return")
	check_result("claimed_item_survives_actual_return_to_harbor_without_ground_drop", harbor
		and int(loot_state(tree.current_scene).get("inventory_count", -1)) == 1 and not loot_state(tree.current_scene).get("drop_visible", true))
	if not harbor:
		return
	main = tree.current_scene
	tap(KEY_B)
	await wait_for(tree, progress, "harbor_claimed_bag_open", .05)
	var harbor_bag: bool = loot_state(main).bag_open and int(loot_state(main).inventory_count) == 1
	tap(KEY_ESCAPE)
	await wait_for(tree, progress, "harbor_claimed_bag_Esc_close", .04)
	check_result("harbor_bag_keeps_item_and_Esc_releases_input", harbor_bag and not loot_state(main).bag_open and not main.player.ui_input_blocked)
	var saved_profile: Dictionary = progress.progress.duplicate(true)
	tap(KEY_F2)
	tap(KEY_F4)
	await tree.scene_changed
	await wait_for(tree, progress, "R0_has_no_loot_controller", .05)
	main = tree.current_scene
	tap(KEY_B)
	tap(KEY_E)
	await wait_for(tree, progress, "R0_B_E_do_not_change_profile", .05)
	var no_R0_loot: bool = (main.scene_file_path.ends_with("west_coast_r0.tscn") and main.get_node_or_null("FirstLoot") == null
		and progress.progress == saved_profile)
	tap(KEY_F4)
	await tree.scene_changed
	await wait_for(tree, progress, "R1_loot_restored_after_F4", .08, ready_in("harbor"))
	main = tree.current_scene
	tap(KEY_F2)
	check_result("R0_has_no_bag_or_pickup_and_F4_retains_inventory", no_R0_loot and int(loot_state(main).get("inventory_count", -1)) == 1
		and not loot_state(main).get("bag_open", true) and progress.progress == saved_profile)
	var claimed_reload: bool = progress.configure_storage(qa_path, true)
	var claimed_reentry: bool = await enter_hall_from_harbor(tree, progress, "claimed_drop_reentry")
	main = tree.current_scene
	check_result("claimed_QA_reload_and_actual_reentry_do_not_regenerate_drop", claimed_reload and claimed_reentry
		and main.get_node("FirstEncounter").cleared and not loot_state(main).get("drop_visible", true)
		and int(progress.progress.inventory["3128"]) == 1 and progress.progress.first_drop.state == "claimed")
	if not claimed_reentry:
		return
	var before_repeat_hash: String = FileAccess.get_sha256(qa_path)
	var before_repeat_saves: int = progress.capture_state().save_attempts
	tap(KEY_R)
	await wait_for(tree, progress, "actual_R_practice_preserves_claimed_drop", .08)
	var retry: Dictionary = main.get_node("FirstEncounter").capture_state()
	check_result("actual_R_restarts_practice_without_revoking_claimed_item", not retry.cleared and int(retry.enemy_hp) == 90
		and int(progress.progress.inventory["3128"]) == 1 and not loot_state(main).drop_visible)
	# Bounded duplicate-reward fixture only: the separate first victory above used all 90 HP.
	main.get_node("FirstEncounter").enemy_hp = 36
	var repeat_combat: Dictionary = await helper.fight_with_actual_controls(tree, progress)
	await wait_for(tree, progress, "practice_victory_cannot_repeat_first_drop", .08)
	check_result("marked36HP_practice_fixture_actual_Q_cannot_award_second_item", repeat_combat.AI_enabled and repeat_combat.after.cleared
		and int(progress.progress.inventory["3128"]) == 1 and progress.progress.first_drop.state == "claimed" and not loot_state(main).drop_visible
		and progress.capture_state().save_attempts == before_repeat_saves and FileAccess.get_sha256(qa_path) == before_repeat_hash,
		{"fixture": "Only this duplicate-reward probe sets enemy_hp=36 after actual R; no position, AI freeze or clock writes. Primary full90HP fight above has no combat fixture.", "combat": repeat_combat})


func run(main: Node, candidate: String = "R3/03") -> Dictionary:
	output_prefix = candidate.to_lower().replace("/", "_")
	var tree: SceneTree = main.get_tree()
	started_usec = Time.get_ticks_usec()
	helper = QuestChecks.new()
	helper.started_usec = started_usec
	records = helper.records
	var formal_before: Dictionary = helper.profile_guard()
	var progress: Node = tree.root.get_node_or_null("AdventureProgress")
	if progress == null:
		check_result("persistent_progress_and_loot_are_integrated", false)
		return {"checks": checks.size(), "failed": checks}
	qa_path = "user://qa/loot_live_" + str(Time.get_unix_time_from_system()).replace(".", "_") + "_" + str(Time.get_ticks_usec()) + ".json"
	helper.qa_path = qa_path
	# Isolate before any B/E, quest action, route transition or encounter interaction.
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
	await wait_for(tree, progress, "loot_controller_settled", .1)
	check_result("QA_storage_is_isolated_current_schema_empty_harbor", configured and main.scene_file_path == HARBOR
		and main.get_node_or_null("FirstLoot") != null and progress.storage_path == qa_path and int(progress.progress.schema) == ProgressScript.PROFILE_SCHEMA
		and int(progress.progress.inventory["3128"]) == 0 and progress.progress.first_drop.state == "unearned" and not FileAccess.file_exists(qa_path),
		{"QA_storage_path": qa_path})
	if configured and main.scene_file_path == HARBOR and main.get_node_or_null("FirstLoot") != null:
		await loot_flow(tree, progress)
	helper.release_motion()
	main = tree.current_scene
	var current_loot: Node = main.get_node_or_null("FirstLoot")
	if current_loot != null:
		current_loot.close_bag()
	var encounter: Node = main.get_node_or_null("FirstEncounter")
	if encounter != null:
		encounter.qa_freeze_enemy = false
	progress.close_dialog()
	for meta_key: String in META_KEYS:
		if original_meta[meta_key].present:
			tree.set_meta(meta_key, original_meta[meta_key].value)
		elif tree.has_meta(meta_key):
			tree.remove_meta(meta_key)
	tree.change_scene_to_file(HARBOR)
	await tree.scene_changed
	await wait_for(tree, progress, "loot_cleanup_harbor_ready", .6, ready_in("harbor"))
	main = tree.current_scene
	# The departing hall persists in _exit_tree, after the first metadata restore.
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
	check_result("formal_profile_and_backup_presence_and_hashes_unchanged", formal_before == formal_after, {"before": formal_before, "after": formal_after})
	check_result("default_storage_original_player_and_closed_bag_restored", default_loaded and progress.storage_path == ProgressScript.DEFAULT_STORAGE
		and progress.get_instance_id() == controller_id and main.scene_file_path == HARBOR and main.player.capture_state() == original_actor
		and main.player.spawn_position == original_spawn and main.player.ui_input_blocked == original_blocked
		and preferences.settings(main) == original_preferences and not progress.capture_state().dialog_open
		and not loot_state(main).get("bag_open", true) and not tree.has_meta("world_travel_spawn"))
	check_result("ground_drop_and_item_bag_current_viewport_screenshots_saved", screenshots.has("ground_drop") and screenshots.has("bag_with_item")
		and screenshots.values().all(func(s): return s.save_error == OK and s.scene.ends_with("tower_hall.tscn")), {"screenshots": screenshots})
	var result: Dictionary = {"candidate": candidate, "checks": checks, "failed": checks.filter(func(c): return not c.pass),
		"duration_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0, "QA_storage_path": qa_path,
		"QA_storage_absolute_path": ProjectSettings.globalize_path(qa_path), "formal_profile_before": formal_before, "formal_profile_after": formal_after,
		"records": records, "screenshots": screenshots, "qa_source_sha256": get_script().source_code.sha256_text(),
		"progress_source_sha256": FileAccess.get_file_as_string("res://scripts/adventure_progress.gd").sha256_text(),
		"loot_source_sha256": FileAccess.get_file_as_string("res://scripts/first_loot.gd").sha256_text(),
		"note": "Actual directional routes, full90HP AI-enabled Q spacing victory, far/near E, B/Esc bag and modal guard, pending/claimed QA disk reloads, R0 absence and R practice. No HP/position writes, AI freeze or source-clock acceleration in the primary first-clear flow. Only the separately marked repeat-reward fixture reduces practice enemy HP to36, then still uses actual Q. Storage failure/migration transactions have a separate isolated suite. This QA only hashes human files, restores normal default loading and leaves its unique QA profile as evidence."}
	var output := FileAccess.open("res://docs/" + output_prefix + "_loot_checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	return {"checks": checks.size(), "failed": result.failed, "render_cases": render_cases.size(), "recorded_rows": records.size()}
