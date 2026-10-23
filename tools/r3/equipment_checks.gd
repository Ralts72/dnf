extends RefCounted
## A real quest/equip route and explicitly staged damage probes, on a persistent root job.

const ProgressScript = preload("res://scripts/adventure_progress.gd")
const QuestChecks = preload("res://tools/r3/quest_checks.gd")
const HARBOR: String = "res://scenes/west_coast_r1.tscn"
const GREAT: String = "27304"
const PRACTICE: String = "practice_lswd0000"
const META_KEYS: Array[String] = ["route_hero_hp", "tower_boss_state", "first_encounter_state", "world_travel_state", "world_travel_spawn", "world_region", "port_framing_offset", "port_framing_offset_x", "port_compare_state"]
var helper: RefCounted
var definitions: Dictionary = {}
var data_cache: Dictionary = {}
var checks: Array = []
var records: Array = []
var render_cases: Array = []
var screenshots: Dictionary = {}
var started_usec: int = 0
var qa_path: String = ""
var output_prefix: String = "r3_05"


func check_result(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check": label, "pass": passed, "details": details})
	render_cases.append({"check": label, "pass": passed})


func tap(code: Key) -> void:
	helper.tap(code)


func point(main: Node) -> Vector2:
	return helper.point(main)


func runtime_state(progress: Node) -> Dictionary:
	var runtime: Node = progress.get_node_or_null("EquipmentRuntime")
	return runtime.capture_state() if runtime != null else {}


func source_data(path: String) -> Dictionary:
	if not data_cache.has(path):
		data_cache[path] = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data_cache[path]


func appearance_proof(main: Node, progress: Node) -> Dictionary:
	var actor: Node = main.player
	var key: String = progress.equipped_weapon_key()
	var definition: Dictionary = definitions.default_appearance if key == PRACTICE else definitions.items[key]
	var spatial: bool = actor is Node3D
	var source_path: String = definition.r1_data if spatial else definition.r0_data
	var source: Dictionary = source_data(source_path)
	var expected: Dictionary = source.animations[actor.animation_name].frames[actor.frame_index]
	var result: Dictionary = {"key": key, "spatial": spatial, "source_data": source_path, "action": actor.animation_name,
		"frame": actor.frame_index, "elapsed_ms": actor.elapsed_ms, "F5_enabled": actor.walk_inbetweens.enabled,
		"F5_active": actor.walk_inbetweens.active, "subframe": actor.walk_inbetweens.subframe, "matches": false}
	if spatial:
		var expected_texture: String = expected.texture
		if actor.walk_inbetweens.active and actor.walk_inbetweens.subframe > 0:
			var clip_path: String = definition.walk_data if actor.animation_name == "move" else definition.dash_data
			var clip: Dictionary = source_data(clip_path)
			expected_texture = clip.frames[actor.frame_index].intermediates[actor.walk_inbetweens.subframe-1]
		var actual_texture: String = actor.sprite.texture.resource_path
		var shader_texture: Texture2D = actor.source_material.get_shader_parameter("source_texture")
		result["raw_texture"] = str(actor.current_frame().texture)
		result["current_texture"] = actual_texture
		result["expected_texture"] = expected_texture
		result["shader_texture"] = shader_texture.resource_path if shader_texture != null else ""
		result.matches = str(actor.current_frame().texture) == str(expected.texture) and actual_texture == expected_texture and result.shader_texture == actual_texture
	else:
		var weapons: Array = []
		for index: int in expected.layers.size():
			var layer: Dictionary = expected.layers[index]
			if str(layer.name).begins_with("weapon_"):
				var actual: String = actor._layers[index].texture.resource_path
				weapons.append({"name": layer.name, "expected_texture": layer.texture, "current_texture": actual,
					"matches": actual == str(layer.texture) and str(actor.current_frame().layers[index].texture) == str(layer.texture)})
		result["weapon_layers"] = weapons
		result.matches = weapons.size() == 2 and weapons.all(func(layer): return layer.matches)
	return result


func observe(tree: SceneTree, progress: Node, label: String) -> Dictionary:
	var row: Dictionary = helper.observe(tree, progress, label)
	if not row.is_empty():
		row["appearance"] = appearance_proof(tree.current_scene, progress)
		row["equipment_runtime"] = runtime_state(progress)
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
	return func(m: Node, s: Dictionary): return s.travel.get("region", "") == region and s.travel.get("phase", "") == "ready" \
		and m.get_node_or_null("FirstLoot") != null and s.appearance.matches and s.equipment_runtime.get("applied_actor_id", -1) == m.player.get_instance_id()


func align_x(tree: SceneTree, progress: Node, target: float, label: String) -> Dictionary:
	var toward: Key = KEY_D if target > point(tree.current_scene).x else KEY_A
	return await wait_for(tree, progress, label, 4.5,
		func(m: Node, _s: Dictionary): return absf(point(m).x-target) < 7.0, [toward, KEY_SHIFT])


func enter_hall(tree: SceneTree, progress: Node, label: String) -> bool:
	var approach: Dictionary = await wait_for(tree, progress, label+"_harbor_to_approach", 4.5, ready_in("approach"), [KEY_A, KEY_SHIFT])
	if not approach.reached:
		return false
	var aligned: Dictionary = await align_x(tree, progress, 430.0, label+"_align_door")
	if not aligned.reached:
		return false
	var hall: Dictionary = await wait_for(tree, progress, label+"_approach_to_hall", 3.0, ready_in("hall"), [KEY_W, KEY_SHIFT])
	return hall.reached


func return_harbor(tree: SceneTree, progress: Node) -> bool:
	var aligned: Dictionary = await align_x(tree, progress, 440.0, "reward_align_hall_exit")
	if not aligned.reached:
		return false
	var retreat: Dictionary = await wait_for(tree, progress, "reward_hall_to_approach", 3.0, ready_in("approach"), [KEY_S, KEY_SHIFT])
	if not retreat.reached:
		return false
	var lane: Dictionary = await wait_for(tree, progress, "reward_approach_lower_lane", 1.5,
		func(m: Node, _s: Dictionary): return point(m).y >= 318.0, [KEY_S, KEY_SHIFT])
	if not lane.reached:
		return false
	var harbor: Dictionary = await wait_for(tree, progress, "reward_approach_to_harbor", 4.5, ready_in("harbor"), [KEY_D, KEY_SHIFT])
	return harbor.reached


func screenshot(main: Node, progress: Node, name: String) -> void:
	var path: String = "res://docs/previews/"+output_prefix+"_"+name+".png"
	var error: Error = main.get_viewport().get_texture().get_image().save_png(path)
	screenshots[name] = {"path": path, "save_error": error, "scene": main.scene_file_path,
		"profile": progress.capture_state(), "appearance": appearance_proof(main, progress)}


func clock_fields(main: Node) -> Dictionary:
	var p: Node = main.player
	return {"action": p.animation_name, "frame": p.frame_index, "elapsed_ms": p.elapsed_ms,
		"paused": p.paused, "preview": p.preview_mode, "one_shot": p._one_shot,
		"facing": p.facing, "jump": p.jump_motion.capture_state(), "F5_enabled": p.walk_inbetweens.enabled}


func switch_in_bag(tree: SceneTree, progress: Node, expected_key: String, label: String) -> Dictionary:
	var main: Node = tree.current_scene
	tap(KEY_B)
	await wait_for(tree, progress, label+"_bag_open", .06)
	var before: Dictionary = clock_fields(main)
	var was_open: bool = main.get_node("FirstLoot").capture_state().bag_open
	tap(KEY_C)
	var immediate: Dictionary = clock_fields(main)
	await wait_for(tree, progress, label+"_C_commit_and_render", .08)
	var state: Dictionary = {"bag_open": was_open, "before_clock": before, "immediate_clock": immediate,
		"clock_preserved": before == immediate, "key": progress.equipped_weapon_key(), "bonus": progress.weapon_damage_bonus(),
		"button_text": main.get_node("FirstLoot")._equip_button.text, "appearance": appearance_proof(main, progress),
		"runtime": runtime_state(progress), "expected_key": expected_key}
	return state


func close_bag(tree: SceneTree, progress: Node, label: String) -> void:
	tap(KEY_B)
	await wait_for(tree, progress, label, .04)


func damage_fixture(tree: SceneTree, progress: Node, action_key: Key, label: String) -> Dictionary:
	var main: Node = tree.current_scene
	var fight: Node = main.get_node("FirstEncounter")
	tap(KEY_R)
	await wait_for(tree, progress, label+"_R_reset", .05)
	fight.qa_freeze_enemy = true
	main.player.free_control()
	main.player.position = main.player.source_to_world(Vector2(440, 315))
	main.player.facing = 1
	main.player.reset_physics_interpolation()
	fight.enemy.position = fight.enemy.source_to_world(Vector2(520, 315))
	fight.enemy.facing = -1
	fight.enemy.release_pose()
	fight.enemy.reset_physics_interpolation()
	var before: Dictionary = fight.capture_state()
	tap(action_key)
	var hit: Dictionary = await wait_for(tree, progress, label+"_actual_input_hit", 1.1,
		func(_m: Node, s: Dictionary): return int(s.combat.enemy_hp) < int(before.enemy_hp))
	await wait_for(tree, progress, label+"_actual_action_finished", 1.2,
		func(m: Node, _s: Dictionary): return not m.player._one_shot and not m.player.ui_input_blocked)
	var after: Dictionary = fight.capture_state()
	return {"fixture": "Actual R restores authored90HP; only this damage probe stages hero440,315/enemy520,315 and qa_freeze_enemy=true. Actual X/Q clocks and HP damage run normally.",
		"key": progress.equipped_weapon_key(), "bonus": progress.weapon_damage_bonus(), "input": "X" if action_key == KEY_X else "Q",
		"hit": hit.reached, "damage": int(before.enemy_hp)-int(after.enemy_hp), "before": before, "after": after,
		"appearance": appearance_proof(main, progress)}


func equipment_flow(tree: SceneTree, progress: Node) -> void:
	var main: Node = tree.current_scene
	tap(KEY_R)
	await wait_for(tree, progress, "equipment_default_harbor", .08)
	var npc: Dictionary = await align_x(tree, progress, 300.0, "actual_walk_to_quest_NPC")
	tap(KEY_E)
	await wait_for(tree, progress, "actual_E_available_dialog", .05)
	tap(KEY_ENTER)
	await wait_for(tree, progress, "actual_Enter_accepts_equipment_quest", .06)
	check_result("actual_E_Enter_accepts_quest_with_unowned_practice_weapon", npc.reached and progress.progress.quest_stage == "active"
		and not progress.owns_weapon(GREAT) and progress.equipped_weapon_key() == PRACTICE and progress.weapon_damage_bonus() == 0)
	if progress.progress.quest_stage != "active":
		return
	var entered: bool = await enter_hall(tree, progress, "real_equipment_quest")
	check_result("actual_route_reaches_hall_with_practice_appearance", entered and appearance_proof(tree.current_scene, progress).matches)
	if not entered:
		return
	var combat: Dictionary = await helper.fight_with_actual_controls(tree, progress)
	check_result("real_full90HP_AI_fight_earns_weapon_quest_receipt", combat.AI_enabled and int(combat.before.enemy_hp) == 90 and combat.after.cleared
		and int(combat.after.enemy_hp) == 0 and int(combat.after.player_hp) > 0 and progress.weapon_damage_bonus() == 0, combat)
	var receipt: Dictionary = await wait_for(tree, progress, "real_victory_saves_return_receipt", 1.2,
		func(_m: Node, s: Dictionary): return s.quest.progress.quest_stage == "return" and not _m.player._one_shot)
	if not receipt.reached:
		return
	var returned: bool = await return_harbor(tree, progress)
	if not returned:
		check_result("actual_return_to_NPC_grants40_and_owned_weapon_without_auto_equip", false)
		return
	main = tree.current_scene
	var reward_npc: Dictionary = await align_x(tree, progress, 300.0, "actual_return_to_reward_NPC")
	tap(KEY_E)
	await wait_for(tree, progress, "actual_E_reward_dialog", .05)
	screenshot(main, progress, "weapon_reward")
	tap(KEY_ENTER)
	await wait_for(tree, progress, "actual_Enter_claims_weapon_reward", .08)
	var reward: Dictionary = progress.capture_state()
	var reward_file: Dictionary = helper.qa_bundle()
	check_result("actual_return_to_NPC_grants40_and_owned_weapon_without_auto_equip", reward_npc.reached and reward.progress.quest_stage == "completed"
		and reward.progress.reward_granted and int(reward.progress.coins) == 40 and progress.owns_weapon(GREAT)
		and progress.equipped_weapon_key() == PRACTICE and progress.weapon_damage_bonus() == 0
		and reward_file.get("equipment", {}).get("owned", {}).get(GREAT, false), {"state": reward, "QA_saved_bundle": reward_file})
	if not progress.owns_weapon(GREAT):
		return
	var reward_hash: String = FileAccess.get_sha256(qa_path)
	var reward_saves: int = reward.save_attempts
	tap(KEY_E)
	await wait_for(tree, progress, "completed_quest_reopened", .04)
	tap(KEY_ENTER)
	await wait_for(tree, progress, "completed_quest_closed", .04)
	check_result("completed_dialog_cannot_duplicate_weapon_or40coins", int(progress.progress.coins) == 40 and progress.owns_weapon(GREAT)
		and progress.capture_state().save_attempts == reward_saves and FileAccess.get_sha256(qa_path) == reward_hash)
	var equipped: Dictionary = await switch_in_bag(tree, progress, GREAT, "actual_B_C_equip_greatsword")
	screenshot(main, progress, "equipped_bag")
	check_result("actual_B_C_equips_owned_greatsword_and_updates_button", equipped.bag_open and equipped.key == GREAT and int(equipped.bonus) == 4
		and equipped.appearance.matches and str(equipped.button_text).contains("练习长剑") and equipped.runtime.get("last_error", "") == "", equipped)
	check_result("synchronous_equip_preserves_source_clock_and_F5_setting", equipped.clock_preserved, equipped)
	await close_bag(tree, progress, "equipped_bag_closed")
	# Exercise the real toggle and finish with F5 enabled regardless of its initial setting.
	tap(KEY_F5)
	await wait_for(tree, progress, "actual_F5_toggle", .03)
	if not main.player.walk_inbetweens.enabled:
		tap(KEY_F5)
		await wait_for(tree, progress, "actual_F5_enabled", .03)
	await wait_for(tree, progress, "equipped_actual_F5_walk", .5, Callable(), [KEY_D])
	screenshot(main, progress, "equipped_walk")
	await wait_for(tree, progress, "equipped_actual_F5_dash", .5, Callable(), [KEY_D, KEY_SHIFT])
	for label: String in ["equipped_actual_F5_walk", "equipped_actual_F5_dash"]:
		var samples: Array = records.filter(func(s): return s.phase == label)
		check_result(label+"_uses_new_raw_and_baked_visible_textures", not samples.is_empty() and samples.all(func(s): return (s.appearance.matches
			and str(s.appearance.current_texture).begins_with("res://assets/r3/equipment/ordinary_greatsword/")))
			and samples.any(func(s): return s.appearance.F5_active and int(s.appearance.subframe) > 0), {"samples": samples.size(), "first": samples[0] if not samples.is_empty() else {}})
	tap(KEY_F2)
	var before_F4: Dictionary = progress.progress.duplicate(true)
	tap(KEY_F4)
	await tree.scene_changed
	await wait_for(tree, progress, "equipped_R0_comparison_ready", .2)
	main = tree.current_scene
	var R0: Dictionary = appearance_proof(main, progress)
	check_result("F4_R0_displays_both_new_source_weapon_layers", main.scene_file_path.ends_with("west_coast_r0.tscn") and R0.matches
		and not R0.spatial and progress.progress == before_F4 and R0.weapon_layers.all(func(layer): return str(layer.current_texture).contains("ordinary_greatsword/src/")), R0)
	tap(KEY_F4)
	await tree.scene_changed
	await wait_for(tree, progress, "equipped_R1_comparison_return", .3, ready_in("harbor"))
	main = tree.current_scene
	tap(KEY_F2)
	tap(KEY_R)
	await wait_for(tree, progress, "actual_R_retains_committed_equipment", .08)
	check_result("F4_return_and_R_keep_equipment_and_new_R1_texture", progress.progress == before_F4 and progress.equipped_weapon_key() == GREAT
		and appearance_proof(main, progress).matches and main.player.walk_inbetweens.enabled)
	var armed_hall: bool = await enter_hall(tree, progress, "equipped_hall_route")
	check_result("actual_region_changes_reapply_committed_greatsword", armed_hall and progress.equipped_weapon_key() == GREAT
		and appearance_proof(tree.current_scene, progress).matches and runtime_state(progress).get("applied_key", "") == GREAT)
	if not armed_hall:
		return
	main = tree.current_scene
	var sword_X: Dictionary = await damage_fixture(tree, progress, KEY_X, "greatsword_X1_fixture")
	var sword_Q: Dictionary = await damage_fixture(tree, progress, KEY_Q, "greatsword_Q_fixture")
	check_result("marked_hit_fixtures_greatsword_X1_22_and_Q40", sword_X.hit and sword_Q.hit and int(sword_X.damage) == 22 and int(sword_Q.damage) == 40,
		{"X1": sword_X, "Q": sword_Q})
	var practice: Dictionary = await switch_in_bag(tree, progress, PRACTICE, "actual_B_C_restore_practice")
	check_result("actual_B_C_restores_practice_visual_and_zero_bonus", practice.bag_open and practice.key == PRACTICE and int(practice.bonus) == 0
		and practice.appearance.matches and practice.clock_preserved and str(practice.button_text).contains("攻击 +4"), practice)
	await close_bag(tree, progress, "practice_bag_closed")
	var practice_X: Dictionary = await damage_fixture(tree, progress, KEY_X, "practice_X1_fixture")
	var practice_Q: Dictionary = await damage_fixture(tree, progress, KEY_Q, "practice_Q_fixture")
	check_result("marked_hit_fixtures_practice_X1_18_and_Q36_and_exact_bonus4", practice_X.hit and practice_Q.hit and int(practice_X.damage) == 18
		and int(practice_Q.damage) == 36 and int(sword_X.damage)-int(practice_X.damage) == 4 and int(sword_Q.damage)-int(practice_Q.damage) == 4,
		{"X1": practice_X, "Q": practice_Q})
	var final_equip: Dictionary = await switch_in_bag(tree, progress, GREAT, "actual_B_C_final_greatsword")
	await close_bag(tree, progress, "final_equipped_bag_closed")
	var clone: Node = ProgressScript.new()
	clone.name = "EquipmentReloadProbe"
	tree.root.add_child(clone)
	clone.set_process(false)
	clone.set_physics_process(false)
	clone.set_process_input(false)
	var reloaded: bool = clone.configure_storage(qa_path, true)
	var reload_state: Dictionary = clone.capture_state()
	var reload_bonus: int = clone.weapon_damage_bonus()
	var reload_key: String = clone.equipped_weapon_key()
	clone.queue_free()
	await wait_for(tree, progress, "independent_equipment_reload_probe_freed", .04)
	check_result("independent_QA_reload_retains_owned_equipped_weapon_and_bonus", final_equip.key == GREAT and reloaded and reload_key == GREAT and reload_bonus == 4
		and reload_state.progress.equipment.owned[GREAT] and int(reload_state.progress.coins) == 40 and int(reload_state.progress.schema) == ProgressScript.PROFILE_SCHEMA,
		{"loaded_state": reload_state, "bonus": reload_bonus})
	main.get_node("FirstEncounter").qa_freeze_enemy = false


func run(main: Node, candidate: String = "R3/05") -> Dictionary:
	var tree: SceneTree = main.get_tree()
	started_usec = Time.get_ticks_usec()
	output_prefix = candidate.to_lower().replace("/", "_")
	definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/first_equipment.json"))
	helper = QuestChecks.new()
	helper.started_usec = started_usec
	records = helper.records
	var formal_before: Dictionary = helper.profile_guard()
	var progress: Node = tree.root.get_node_or_null("AdventureProgress")
	if progress == null:
		check_result("persistent_progress_is_integrated", false)
		return {"checks": checks.size(), "failed": checks}
	qa_path = "user://qa/equipment_live_"+str(Time.get_unix_time_from_system()).replace(".", "_")+"_"+str(Time.get_ticks_usec())+".json"
	helper.qa_path = qa_path
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
	await wait_for(tree, progress, "equipment_controller_settled", .1)
	check_result("isolated_current_schema_initial_profile_has_unowned_practice_equipment", configured and main.scene_file_path == HARBOR
		and progress.storage_path == qa_path and int(progress.progress.schema) == ProgressScript.PROFILE_SCHEMA and not progress.owns_weapon(GREAT)
		and progress.equipped_weapon_key() == PRACTICE and appearance_proof(main, progress).matches and not FileAccess.file_exists(qa_path), {"QA_storage_path": qa_path})
	if configured and main.scene_file_path == HARBOR:
		await equipment_flow(tree, progress)
	helper.release_motion()
	main = tree.current_scene
	var loot: Node = main.get_node_or_null("FirstLoot")
	if loot != null:
		loot.close_bag()
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
	await wait_for(tree, progress, "equipment_cleanup_harbor_ready", .6, ready_in("harbor"))
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
	check_result("formal_profile_and_backup_presence_and_hashes_unchanged", formal_before == formal_after, {"before": formal_before, "after": formal_after})
	check_result("default_profile_original_player_preferences_and_appearance_restored", default_loaded and progress.storage_path == ProgressScript.DEFAULT_STORAGE
		and main.scene_file_path == HARBOR and main.player.capture_state() == original_actor and main.player.spawn_position == original_spawn
		and main.player.ui_input_blocked == original_blocked and preferences.settings(main) == original_preferences and appearance_proof(main, progress).matches
		and not progress.capture_state().dialog_open and not main.get_node("FirstLoot").capture_state().bag_open and not tree.has_meta("world_travel_spawn"))
	check_result("weapon_reward_bag_and_walk_current_viewport_screenshots_saved", screenshots.has("weapon_reward") and screenshots.has("equipped_bag")
		and screenshots.has("equipped_walk") and screenshots.values().all(func(s): return s.save_error == OK), {"screenshots": screenshots})
	var result: Dictionary = {"candidate": candidate, "checks": checks, "failed": checks.filter(func(c): return not c.pass),
		"duration_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0, "records": records, "screenshots": screenshots,
		"QA_storage_path": qa_path, "QA_storage_absolute_path": ProjectSettings.globalize_path(qa_path),
		"formal_profile_before": formal_before, "formal_profile_after": formal_after,
		"qa_source_sha256": get_script().source_code.sha256_text(),
		"progress_source_sha256": FileAccess.get_file_as_string("res://scripts/adventure_progress.gd").sha256_text(),
		"appearance_source_sha256": FileAccess.get_file_as_string("res://scripts/equipment_appearance.gd").sha256_text(),
		"runtime_source_sha256": FileAccess.get_file_as_string("res://scripts/equipment_runtime.gd").sha256_text(),
		"note": "Actual E/Enter quest, full90HP AI-enabled initial fight and route, B/C equipment commits, live F5 raw+baked Sprite3D/shader textures, F4 native weapon layers, region/R persistence and independent QA save reload. Primary quest has no HP/position writes, AI freeze or clock acceleration. Only explicitly marked X1/Q damage fixtures stage safe positions and freeze AI; actual input and native source clocks produce22/40 versus18/36, the adapted +4 rather than source72. Human files are only presence/hash checked by QA; normal default loading and original controls/appearance are restored. Transaction failures/migrations belong to separate storage tests."}
	var output := FileAccess.open("res://docs/"+output_prefix+"_equipment_checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	return {"checks": checks.size(), "failed": result.failed, "render_cases": render_cases.size(), "recorded_rows": records.size()}
