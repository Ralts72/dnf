extends RefCounted
## Root-owned pose_check_job: bounded native checks, unique QA profile, no human save writes.

const ProgressScript = preload("res://scripts/adventure_progress.gd")
const InputChecks = preload("res://tools/r3/quest_checks.gd")
const Preferences = preload("res://tools/r2/travel_checks.gd")
const HARBOR: String = "res://scenes/west_coast_r1.tscn"
const META_KEYS: Array[String] = ["route_hero_hp", "tower_boss_state", "first_encounter_state", "world_travel_state", "world_travel_spawn", "world_region", "port_framing_offset", "port_framing_offset_x", "port_compare_state"]
const PROFILE_FIELDS: Array[String] = ["progress", "storage_path", "last_error", "loaded_from_backup", "_storage_ready", "_clear_seen", "_boss_clear_seen", "_save_attempts", "_pending_bundle"]
var checks: Array = []
var records: Array = []
var render_cases: Array = []
var screenshots: Dictionary = {}
var helper: RefCounted
var started_usec: int = 0
var qa_path: String = ""
var output_prefix: String = "r4_01"


func check_result(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check": label, "pass": passed, "details": details})
	render_cases.append({"check": label, "pass": passed})


func tap(code: Key) -> void:
	helper.tap(code)


func point(main: Node) -> Vector2:
	return helper.point(main)


func observe(tree: SceneTree, progress: Node, label: String) -> Dictionary:
	var main: Node = tree.current_scene
	if main == null or main.get_node_or_null("WorldTravel") == null:
		return {}
	var fight: Node = main.get_node_or_null("TowerBoss")
	var hall: Node = main.get_node_or_null("FirstEncounter")
	var row: Dictionary = {"phase": label, "elapsed_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"scene": main.scene_file_path, "position": point(main), "action": main.player.animation_name,
		"hero_frame": main.player.frame_index, "hero_elapsed_ms": main.player.elapsed_ms,
		"hero_attack_instance": main.player.attack_instance, "hero_one_shot": main.player._one_shot,
		"jump_height": main.player.jump_motion.height_pixels, "paused": main.player.paused,
		"markers": main.player.markers_visible, "blocked": main.player.ui_input_blocked,
		"travel": main.get_node("WorldTravel").capture_state(), "profile": progress.capture_state(),
		"boss": fight.capture_state() if fight != null else {}, "hall": hall.capture_state() if hall != null else {},
		"shared_hp": tree.get_meta("route_hero_hp", -1)}
	if fight != null:
		row["enemy_action"] = fight.enemy.animation_name
		row["enemy_frame"] = fight.enemy.frame_index
	records.append(row)
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
		and m.get_node_or_null("FirstLoot") != null and (region != "depths" or m.get_node_or_null("TowerBoss") != null)


func align_x(tree: SceneTree, progress: Node, target: float, label: String) -> bool:
	var code: Key = KEY_D if target > point(tree.current_scene).x else KEY_A
	var result: Dictionary = await wait_for(tree, progress, label, 5.0,
		func(m: Node, _s: Dictionary): return absf(point(m).x-target) < 7.0, [code, KEY_SHIFT])
	return result.reached


func screenshot(tree: SceneTree, name: String) -> void:
	var path: String = "res://docs/previews/"+output_prefix+"_boss_"+name+".png"
	var error: Error = tree.current_scene.get_viewport().get_texture().get_image().save_png(path)
	screenshots[name] = {"path": path, "save_error": error, "scene": tree.current_scene.scene_file_path}


func samples(label: String) -> Array:
	return records.filter(func(row): return row.phase == label)


func stage_actor(actor: Node, source: Vector2, facing: int) -> void:
	actor.jump_motion.reset()
	actor.free_control()
	actor.ui_input_blocked = false
	actor.velocity = Vector3.ZERO
	actor.position = actor.source_to_world(source)
	actor.facing = facing
	actor._update_sprite_transform()
	actor.reset_physics_interpolation()


func fixture(tree: SceneTree, progress: Node, label: String, gap: float = 80.0, freeze: bool = false) -> Node:
	# R establishes authored100/220HP. Only positions/AI gate below are staged.
	tap(KEY_R)
	await wait_for(tree, progress, label+"_actual_R", .05)
	var main: Node = tree.current_scene
	var fight: Node = main.get_node("TowerBoss")
	fight.qa_freeze_enemy = freeze
	stage_actor(main.player, Vector2(440, 315), 1)
	stage_actor(fight.enemy, Vector2(440+gap, 315), -1)
	fight.enemy.release_pose()
	fight.enemy.paused = false
	observe(tree, progress, label+"_staged_positions")
	return fight


func route_gate(tree: SceneTree, progress: Node) -> bool:
	var approach: Dictionary = await wait_for(tree, progress, "actual_harbor_to_approach", 4.5, ready_in("approach"), [KEY_A, KEY_SHIFT])
	if not approach.reached or not await align_x(tree, progress, 430, "actual_approach_align_door"):
		check_result("actual_route_reaches_uncleared_hall", false)
		return false
	var hall: Dictionary = await wait_for(tree, progress, "actual_approach_to_hall", 3.0, ready_in("hall"), [KEY_W, KEY_SHIFT])
	check_result("actual_route_reaches_uncleared_hall", hall.reached)
	if not hall.reached:
		return false
	var main: Node = tree.current_scene
	var first: Node = main.get_node("FirstEncounter")
	first.qa_freeze_enemy = true
	# Gate fixture: no combat or reward is claimed as an actual run here.
	stage_actor(main.player, Vector2(720, 320), 1)
	var locked: Dictionary = await wait_for(tree, progress, "fixture_actual_D_locked_gate", .65, Callable(), [KEY_D, KEY_SHIFT])
	check_result("actual_D_cannot_cross_gate_without_first_clear", tree.current_scene == main
		and not locked.last.travel.get("depths_unlocked", true) and point(main).x >= 769.0 and not first.cleared, locked)
	var next: Dictionary = progress._default_progress()
	next.quest_stage = "completed"
	next.objective_cleared = true
	next.reward_granted = true
	next.coins = 40
	next.inventory["3128"] = 1
	next.first_drop.state = "claimed"
	next.equipment.owned["27304"] = true
	next.equipment.equipped_key = "27304"
	var committed: bool = progress._commit(next)
	first.enemy_hp = 0
	first.cleared = true
	first.enemy.hide()
	first.enemy.collision_layer = 0
	first._persist()
	check_result("marked_completed_quest_and_weapon_fixture_is_valid_in_unique_current_schema_profile", committed
		and progress.storage_path == qa_path and progress.weapon_damage_bonus() == 4 and int(progress.progress.schema) == ProgressScript.PROFILE_SCHEMA,
		{"fixture": "Pre-existing completed Mirkius quest/claimed eye/equipped27304; not an actual quest/loot/equip claim in this boss QA.", "profile": progress.capture_state()})
	var entered: Dictionary = await wait_for(tree, progress, "fixture_unlocked_actual_D_enters_depths", 2.0, ready_in("depths"), [KEY_D])
	check_result("actual_D_enters_unlocked_depths_at_safe_spawn_with_equipment", committed and entered.reached
		and absf(point(tree.current_scene).x-176.0) < 6.0 and progress.equipped_weapon_key() == "27304", entered)
	return entered.reached


func combat_fixtures(tree: SceneTree, progress: Node) -> void:
	var fight: Node = await fixture(tree, progress, "normal_contact")
	var before: Dictionary = fight.capture_state()
	fight._start_attack("normal")
	await wait_for(tree, progress, "fixture_normal_before180", .4,
		func(_m: Node, s: Dictionary): return s.boss.attack_clock_ms >= 120.0)
	var windup: Dictionary = fight.capture_state()
	var contact: Dictionary = await wait_for(tree, progress, "fixture_normal_first_contact", .5,
		func(_m: Node, s: Dictionary): return s.boss.player_hp < before.player_hp)
	var ended: Dictionary = await wait_for(tree, progress, "fixture_normal_complete", .5,
		func(_m: Node, s: Dictionary): return s.boss.attack_kind == "")
	fight.qa_freeze_enemy = true
	var after: Dictionary = fight.capture_state()
	check_result("fixture_normal_source410ms_and_no_damage_before180ms", windup.player_hp == before.player_hp
		and windup.attack_kind == "normal" and ended.reached and float(after.attack_clock_ms) >= 410.0
		and float(after.attack_clock_ms) <= 435.0, {"before": before, "windup": windup, "after": after})
	check_result("fixture_normal_one14_damage_contact_inside180_330ms", contact.reached and int(after.player_hp) == 86
		and int(after.event_counters.enemy_hits)-int(before.event_counters.enemy_hits) == 1
		and float(contact.last.boss.attack_clock_ms) >= 180 and float(contact.last.boss.attack_clock_ms) < 350,
		{"first_contact": contact, "after": after})
	var normal_frames: Array = fight.enemy._animations["attack1"].frames
	var observed_frame: int = int(contact.last.get("enemy_frame", -1))
	var source_clock: float = float(contact.last.get("boss", {}).get("enemy_action_elapsed_ms", -1))
	var physics_clock: float = float(contact.last.get("boss", {}).get("attack_clock_ms", -1))
	var frame_start_ms: float = 0.0
	for index: int in maxi(0, observed_frame):
		frame_start_ms += float(normal_frames[index].duration_ms)
	var frame_valid: bool = observed_frame >= 0 and observed_frame < normal_frames.size()
	var frame_end_ms: float = frame_start_ms + float(normal_frames[observed_frame].duration_ms) if frame_valid else -1.0
	var tolerance_ms: float = 1000.0 / float(Engine.physics_ticks_per_second) + 0.5
	check_result("fixture_normal_uses_original_attack1_frame2_at_contact", contact.reached
		and contact.last.enemy_action == "attack1" and frame_valid and source_clock >= frame_start_ms and source_clock < frame_end_ms
		and physics_clock >= 180.0 and physics_clock < 330.0 and absf(source_clock-physics_clock) <= tolerance_ms,
		{"first_contact": contact.last, "source_clock_ms": source_clock, "source_frame_interval_ms": [frame_start_ms, frame_end_ms],
		"physics_clock_ms": physics_clock, "clock_difference_ms": absf(source_clock-physics_clock), "one_tick_tolerance_ms": tolerance_ms,
		"sampling_tolerance": "Source frame index must match its original ANI clock interval; actual contact is in physics active180..330ms, with render/physics clocks at most one physics tick apart (+0.5ms rounding)."})

	fight = await fixture(tree, progress, "heavy_armor")
	before = fight.capture_state()
	var anchored: Vector3 = fight.enemy.position
	fight._start_attack("heavy")
	tap(KEY_X)
	var armored: Dictionary = await wait_for(tree, progress, "fixture_actual_X_during_850ms_charge", .6,
		func(_m: Node, s: Dictionary): return s.boss.enemy_hp < before.enemy_hp)
	after = fight.capture_state()
	check_result("fixture_heavy_charge_takes22HP_without_hurt_or_push", armored.reached and int(after.enemy_hp) == 198
		and fight.enemy.position.distance_to(anchored) < .0001 and after.attack_kind == "heavy" and after.enemy_mode == "attack"
		and float(after.enemy_hurt_remaining) == 0.0 and after.telegraph_visible
		and int(after.event_counters.armored_hits)-int(before.event_counters.armored_hits) == 1,
		{"before": before, "after": after, "fixture": "Actual X1 source clock; only initial positions and direct heavy start are staged."})
	await wait_for(tree, progress, "fixture_heavy_before850", .8,
		func(_m: Node, s: Dictionary): return s.boss.attack_clock_ms >= 700.0)
	windup = observe(tree, progress, "fixture_heavy_windup_proof")
	screenshot(tree, "charge")
	contact = await wait_for(tree, progress, "fixture_heavy_first_contact", .5,
		func(_m: Node, s: Dictionary): return s.boss.player_hp < 100)
	ended = await wait_for(tree, progress, "fixture_heavy_complete", .5,
		func(_m: Node, s: Dictionary): return s.boss.attack_kind == "")
	after = fight.capture_state()
	check_result("fixture_heavy_preserves850ms_source_windup_frame0_without_damage", int(windup.boss.player_hp) == 100
		and windup.enemy_action == "attackheart" and int(windup.enemy_frame) == 0 and windup.boss.telegraph_visible, windup)
	check_result("fixture_heavy_one24_damage_contact_850_1050_and1100ms_end", contact.reached and ended.reached and int(after.player_hp) == 76
		and int(after.event_counters.enemy_hits)-int(before.event_counters.enemy_hits) == 1
		and float(contact.last.boss.attack_clock_ms) >= 850 and float(contact.last.boss.attack_clock_ms) < 1070
		and float(after.attack_clock_ms) >= 1100 and float(after.attack_clock_ms) <= 1125
		and contact.last.enemy_action == "attackheart" and int(contact.last.enemy_frame) == 1,
		{"first_contact": contact, "after": after})
	var attack_count: int = int(after.event_counters.enemy_attacks)
	var recovery_point: Vector3 = fight.enemy.position
	tap(KEY_Q)
	await wait_for(tree, progress, "fixture_heavy_recovery_no_pursuit", .22)
	var stationary: bool = fight.enemy.position.distance_to(recovery_point) < .0001 and fight.punish_remaining > .35
	var punished: Dictionary = await wait_for(tree, progress, "fixture_actual_Q_punishes_recovery", .65,
		func(_m: Node, s: Dictionary): return s.boss.enemy_hp < 198)
	after = fight.capture_state()
	check_result("fixture_heavy_has650ms_punish_window_and_actual_Q_can_stagger", stationary and punished.reached
		and int(after.enemy_hp) == 158 and float(after.enemy_hurt_remaining) > 0.0
		and int(after.event_counters.enemy_attacks) == attack_count, {"after": after, "Q_contact": punished})

	fight = await fixture(tree, progress, "jump_evades_heavy")
	var jump_before: Dictionary = fight.capture_state()
	fight._start_attack("heavy")
	await wait_for(tree, progress, "fixture_jump_wait420ms", .8,
		func(_m: Node, s: Dictionary): return s.boss.attack_clock_ms >= 420.0)
	tap(KEY_SPACE)
	ended = await wait_for(tree, progress, "fixture_actual_Space_covers_heavy_window", 1.0,
		func(_m: Node, s: Dictionary): return s.boss.attack_kind == "")
	fight.qa_freeze_enemy = true
	var active_rows: Array = samples("fixture_actual_Space_covers_heavy_window").filter(func(s): return float(s.boss.attack_clock_ms) >= 850.0 and float(s.boss.attack_clock_ms) < 1050.0)
	check_result("fixture_actual_Space_evades_entire_heavy_active_window", ended.reached and not active_rows.is_empty()
		and active_rows.all(func(s): return float(s.jump_height) >= 35.0) and fight.player_hp == 100
		and int(fight.event_counters.enemy_hits) == int(jump_before.event_counters.enemy_hits),
		{"active_samples": active_rows.size(), "minimum_jump_height": active_rows.map(func(s): return s.jump_height).min() if not active_rows.is_empty() else 0,
		"after": fight.capture_state()})

	fight = await fixture(tree, progress, "hero_single_hit", 80.0, true)
	before = fight.capture_state()
	tap(KEY_Q)
	await wait_for(tree, progress, "fixture_actual_Q_single_instance", 1.3,
		func(m: Node, s: Dictionary): return not m.player._one_shot and s.boss.enemy_hp < before.enemy_hp)
	after = fight.capture_state()
	check_result("fixture_one_Q_instance_hits_once_for_adapted40", int(before.enemy_hp)-int(after.enemy_hp) == 40
		and int(after.event_counters.hero_hits)-int(before.event_counters.hero_hits) == 1
		and int(after.hero_attack_instance) == int(before.hero_attack_instance)+1, {"before": before, "after": after})

	# Source clocks remain real time; only this setup uses close staged positions.
	fight = await fixture(tree, progress, "AI_pattern")
	var pattern_start: int = records.size()
	var heavy_baseline: int = int(fight.event_counters.heavy_attacks)
	var pattern_done: Dictionary = await wait_for(tree, progress, "fixture_AI_normal_normal_heavy", 4.2,
		func(_m: Node, s: Dictionary): return int(s.boss.event_counters.heavy_attacks) >= heavy_baseline+1)
	var pattern: Array = []
	var last_instance: int = -1
	for row: Dictionary in records.slice(pattern_start):
		if row.boss.attack_kind != "" and int(row.boss.enemy_attack_instance) != last_instance:
			last_instance = int(row.boss.enemy_attack_instance)
			pattern.append(row.boss.attack_kind)
			if pattern.size() == 3:
				break
	check_result("fixture_live_AI_selects_two_normal_then_heavy_without_manual_start", pattern == ["normal", "normal", "heavy"],
		{"sequence": pattern, "last": pattern_done.last, "fixture": "Only initial hero/enemy ground positions are staged; AI chooses all attacks."})


func modal_fixtures(tree: SceneTree, progress: Node) -> void:
	for gate: String in ["F2", "menu", "B", "F1"]:
		var fight: Node = await fixture(tree, progress, "freeze_"+gate, 180.0)
		fight._start_attack("heavy")
		await wait_for(tree, progress, "fixture_"+gate+"_charging", .4,
			func(_m: Node, s: Dictionary): return s.boss.attack_clock_ms >= 120.0)
		var main: Node = tree.current_scene
		var popup: PopupMenu = main.preview_controls.audio_menu.get_popup()
		if gate == "menu":
			popup.popup()
		else:
			tap({"F2": KEY_F2, "B": KEY_B, "F1": KEY_F1}[gate])
		await wait_for(tree, progress, "fixture_"+gate+"_settle", .035)
		var before: Dictionary = fight.capture_state()
		var source_clock: float = fight.enemy.action_elapsed_ms()
		tap(KEY_X)
		await wait_for(tree, progress, "fixture_"+gate+"_frozen", .22)
		var after: Dictionary = fight.capture_state()
		check_result("fixture_"+gate+"_freezes_AI_source_clock_armor_warning_and_damage", before.combat_blocked and after.combat_blocked
			and float(before.attack_clock_ms) == float(after.attack_clock_ms)
			and absf(source_clock-fight.enemy.action_elapsed_ms()) < .001
			and before.armor_remaining == after.armor_remaining and before.telegraph_visible == after.telegraph_visible
			and before.player_hp == after.player_hp and before.enemy_hp == after.enemy_hp
			and before.enemy_source_position == after.enemy_source_position, {"before": before, "after": after})
		if gate == "menu":
			popup.hide()
			main.get_viewport().gui_release_focus()
		elif gate == "B":
			tap(KEY_B)
		elif gate == "F1":
			tap(KEY_F1)
		else:
			tap(KEY_F2)
		var resumed: Dictionary = await wait_for(tree, progress, "fixture_"+gate+"_resumed", .35,
			func(_m: Node, s: Dictionary): return not s.boss.combat_blocked and float(s.boss.attack_clock_ms) > float(before.attack_clock_ms)+40.0)
		check_result("fixture_"+gate+"_close_resumes_without_input_softlock", resumed.reached, resumed)


func ko_and_shared_hp(tree: SceneTree, progress: Node) -> bool:
	var fight: Node = await fixture(tree, progress, "KO_retry")
	fight.player_hp = 14
	fight._persist()
	fight._start_attack("normal")
	var defeated: Dictionary = await wait_for(tree, progress, "fixture_14HP_actual_normal_KO", .65,
		func(_m: Node, s: Dictionary): return s.boss.player_hp == 0)
	var main: Node = tree.current_scene
	var source: Vector2 = point(main)
	var identity: int = main.player.attack_instance
	tap(KEY_X)
	tap(KEY_SPACE)
	await wait_for(tree, progress, "fixture_KO_blocks_controls", .25, Callable(), [KEY_D])
	check_result("fixture_real_contact_KO_holds_down_and_blocks_walk_attack_jump", defeated.reached and main.player.ui_input_blocked
		and main.player.animation_name == "down" and point(main).distance_to(source) < .1
		and main.player.attack_instance == identity and not main.player.jump_motion.is_active(),
		{"fixture": "Only initial player HP14 is staged; an actual normal hit produces KO.", "after": fight.capture_state()})
	tap(KEY_R)
	var reset: Dictionary = await wait_for(tree, progress, "actual_R_from_owned_KO_lock", .4,
		func(_m: Node, s: Dictionary): return s.boss.player_hp == 100 and s.boss.enemy_hp == 220 and not s.blocked)
	check_result("actual_R_from_KO_restores100_220_safe_entry_and_pattern", reset.reached and int(fight.pattern_index) == 0
		and point(main).distance_to(Vector2(176, 320)) < .1 and not fight._hero_lock and not fight._release_pending, reset)

	fight = await fixture(tree, progress, "shared_HP")
	fight._start_attack("normal")
	var hit: Dictionary = await wait_for(tree, progress, "fixture_sharedHP_actual14_damage", .65,
		func(_m: Node, s: Dictionary): return s.boss.player_hp == 86)
	fight.qa_freeze_enemy = true
	await wait_for(tree, progress, "fixture_sharedHP_hurt_unlock", .55,
		func(_m: Node, s: Dictionary): return not s.blocked)
	var hall: Dictionary = await wait_for(tree, progress, "actual_lowHP_depths_to_hall", 3.8, ready_in("hall"), [KEY_A, KEY_SHIFT])
	check_result("actual_retreat_keeps_shared86HP_in_first_hall", hit.reached and hall.reached and int(hall.last.hall.get("player_hp", -1)) == 86
		and int(tree.get_meta("route_hero_hp", -1)) == 86, hall)
	if not hall.reached:
		return false
	var back: Dictionary = await wait_for(tree, progress, "actual_lowHP_hall_to_depths", 2.0, ready_in("depths"), [KEY_D, KEY_SHIFT])
	check_result("actual_reentry_keeps_shared86HP_and_safe_boss_spawn", back.reached and int(back.last.boss.player_hp) == 86
		and int(back.last.boss.enemy_hp) == 220 and absf(float(back.last.boss.enemy_source_position.x)-640.0) < 3.0, back)
	return back.reached


func actual_boss_fight(tree: SceneTree, progress: Node) -> Dictionary:
	# Real attempt: no positions, HP, clocks, pattern or freeze writes after actual R.
	tap(KEY_R)
	await wait_for(tree, progress, "actual_AI_fresh_R", .06)
	var fight: Node = tree.current_scene.get_node("TowerBoss")
	fight.qa_freeze_enemy = false
	var before: Dictionary = fight.capture_state()
	var casts: Array = []
	for attempt: int in 9:
		if fight.cleared or fight.player_hp <= 0:
			break
		await wait_for(tree, progress, "actual_AI_wait_free_"+str(attempt), 2.0,
			func(m: Node, s: Dictionary): return s.boss.cleared or s.boss.player_hp == 0 or (not m.player._one_shot and not s.blocked and not m.player.jump_motion.is_active()))
		if fight.cleared or fight.player_hp <= 0:
			break
		var main: Node = tree.current_scene
		var difference: Vector2 = fight.enemy.world_to_source(fight.enemy.position)-point(main)
		if absf(difference.y) > 12.0:
			var vertical: Key = KEY_S if difference.y > 0 else KEY_W
			await wait_for(tree, progress, "actual_AI_align_depth_"+str(attempt), 1.5,
				func(m: Node, _s: Dictionary): return absf(fight.enemy.world_to_source(fight.enemy.position).y-point(m).y) < 10.0, [vertical])
		difference = fight.enemy.world_to_source(fight.enemy.position)-point(main)
		var toward: Key = KEY_D if difference.x >= 0 else KEY_A
		var away: Key = KEY_A if difference.x >= 0 else KEY_D
		if absf(difference.x) > 130.0:
			await wait_for(tree, progress, "actual_AI_approach_"+str(attempt), 4.0,
				func(m: Node, _s: Dictionary): return absf(fight.enemy.world_to_source(fight.enemy.position).x-point(m).x) <= 130.0, [toward, KEY_SHIFT])
		elif absf(difference.x) < 123.0:
			await wait_for(tree, progress, "actual_AI_retreat_"+str(attempt), 1.5,
				func(m: Node, _s: Dictionary): return absf(fight.enemy.world_to_source(fight.enemy.position).x-point(m).x) >= 128.0 \
					or point(m).x <= 40.0 or point(m).x >= 848.0, [away, KEY_SHIFT])
		difference = fight.enemy.world_to_source(fight.enemy.position)-point(main)
		toward = KEY_D if difference.x >= 0 else KEY_A
		await wait_for(tree, progress, "actual_AI_face_"+str(attempt), .025, Callable(), [toward])
		var identity: int = main.player.attack_instance
		var gap: Vector2 = fight.enemy.world_to_source(fight.enemy.position)-point(main)
		tap(KEY_Q)
		await wait_for(tree, progress, "actual_AI_Q_"+str(attempt), 1.6,
			func(m: Node, s: Dictionary): return s.boss.cleared or s.boss.player_hp == 0 or (not m.player._one_shot and not s.blocked))
		casts.append({"attempt": attempt, "gap_at_input": gap, "accepted": main.player.attack_instance > identity, "after": fight.capture_state()})
	return {"before": before, "after": fight.capture_state(), "casts": casts, "AI_enabled": not fight.qa_freeze_enemy,
		"fixture_policy": "Only the ordinary R reset starts this attempt. Every approach, retreat, facing change and Q is an actual input; no HP, position, clock, attack-start or AI-freeze mutation occurs during this attempt."}


func victory_and_return(tree: SceneTree, progress: Node) -> void:
	var real: Dictionary = await actual_boss_fight(tree, progress)
	check_result("real_AI_full220HP_boss_defeated_with_actual_controls", int(real.before.enemy_hp) == 220 and int(real.before.player_hp) == 100
		and real.AI_enabled and real.after.cleared and int(real.after.enemy_hp) == 0 and int(real.after.player_hp) > 0
		and int(real.after.event_counters.victories)-int(real.before.event_counters.victories) == 1, real)
	if not real.after.cleared:
		return
	var saved: Dictionary = await wait_for(tree, progress, "actual_victory_commits_chapter_flag", 1.3,
		func(m: Node, s: Dictionary): return bool(s.profile.progress.chapter_flags.lakius_cleared) and not s.profile.pending_save \
			and not m.player._one_shot and not s.boss.enemy_visible)
	var bundle: Dictionary = helper.qa_bundle()
	check_result("real_victory_persists_current_schema_flag_without_duplicate_quest_reward", saved.reached
		and bundle.get("chapter_flags", {}).get("lakius_cleared", false) and int(bundle.get("schema", 0)) == ProgressScript.PROFILE_SCHEMA
		and int(bundle.get("coins", -1)) == 40 and int(bundle.get("inventory", {}).get("3128", -1)) == 1
		and bundle.get("equipment", {}).get("equipped_key", "") == "27304", {"QA_saved_bundle": bundle})
	screenshot(tree, "victory")
	var hp: int = int(real.after.player_hp)
	var hall: Dictionary = await wait_for(tree, progress, "actual_victory_return_to_hall", 5.0, ready_in("hall"), [KEY_A, KEY_SHIFT])
	check_result("actual_victory_retreat_keeps_HP_and_chapter_receipt", hall.reached and int(hall.last.hall.get("player_hp", -1)) == hp
		and progress.progress.chapter_flags.lakius_cleared, hall)
	if not hall.reached:
		return
	var reentry: Dictionary = await wait_for(tree, progress, "actual_cleared_depths_reentry", 2.0, ready_in("depths"), [KEY_D, KEY_SHIFT])
	check_result("actual_reentry_retains_cleared_hidden_boss", reentry.reached and reentry.last.boss.cleared
		and int(reentry.last.boss.enemy_hp) == 0 and not reentry.last.boss.enemy_visible and int(reentry.last.boss.player_hp) == hp, reentry)
	if not reentry.reached:
		return
	var clone: Node = ProgressScript.new()
	clone.name = "BossProfileReadProbe"
	tree.root.add_child(clone)
	clone.set_process(false)
	clone.set_physics_process(false)
	clone.set_process_input(false)
	var loaded: bool = clone.configure_storage(qa_path, true)
	var loaded_state: Dictionary = clone.capture_state()
	clone.queue_free()
	check_result("independent_QA_reload_retains_boss_receipt_and_equipment", loaded
		and loaded_state.progress.chapter_flags.lakius_cleared and loaded_state.progress.equipment.equipped_key == "27304", loaded_state)
	tap(KEY_R)
	await wait_for(tree, progress, "actual_R_practice_after_historical_victory", .08)
	var reset_fight: Node = tree.current_scene.get_node("TowerBoss")
	check_result("actual_R_can_reset_practice_fight_without_revoking_saved_victory", reset_fight.enemy_hp == 220 and not reset_fight.cleared
		and progress.progress.chapter_flags.lakius_cleared and helper.qa_bundle().get("chapter_flags", {}).get("lakius_cleared", false))
	hall = await wait_for(tree, progress, "actual_postvictory_practice_retreat", 2.0, ready_in("hall"), [KEY_A, KEY_SHIFT])
	if not hall.reached or not await align_x(tree, progress, 440, "actual_return_align_hall_exit"):
		check_result("actual_postvictory_route_returns_to_harbor", false)
		return
	var approach: Dictionary = await wait_for(tree, progress, "actual_return_hall_to_approach", 3.0, ready_in("approach"), [KEY_S, KEY_SHIFT])
	if not approach.reached:
		check_result("actual_postvictory_route_returns_to_harbor", false)
		return
	await wait_for(tree, progress, "actual_return_lower_causeway", 1.5,
		func(m: Node, _s: Dictionary): return point(m).y >= 318.0, [KEY_S, KEY_SHIFT])
	var harbor: Dictionary = await wait_for(tree, progress, "actual_return_approach_to_harbor", 4.5, ready_in("harbor"), [KEY_D, KEY_SHIFT])
	check_result("actual_postvictory_route_returns_to_harbor", harbor.reached and progress.progress.chapter_flags.lakius_cleared, harbor)
	if harbor.reached:
		screenshot(tree, "return_harbor")


func snapshot_meta(tree: SceneTree) -> Dictionary:
	var values: Dictionary = {}
	for key: String in META_KEYS:
		var exists: bool = tree.has_meta(key)
		var value: Variant = tree.get_meta(key) if exists else null
		values[key] = {"present": exists, "value": value.duplicate(true) if value is Dictionary or value is Array else value}
	return values


func restore_meta(tree: SceneTree, values: Dictionary) -> void:
	for key: String in META_KEYS:
		if values[key].present:
			tree.set_meta(key, values[key].value)
		elif tree.has_meta(key):
			tree.remove_meta(key)


func run(root: Node, candidate: String = "R4/01") -> Dictionary:
	var tree: SceneTree = root.get_tree()
	started_usec = Time.get_ticks_usec()
	output_prefix = candidate.to_lower().replace("/", "_")
	helper = InputChecks.new()
	helper.started_usec = started_usec
	var main: Node = tree.current_scene
	var progress: Node = tree.root.get_node_or_null("AdventureProgress")
	if progress == null or main == null or main.scene_file_path != HARBOR:
		check_result("QA_starts_in_integrated_harbor", false)
		return {"checks": checks.size(), "failed": checks, "render_cases": render_cases.size()}
	var formal_before: Dictionary = helper.profile_guard()
	var original_meta: Dictionary = snapshot_meta(tree)
	var original_profile: Dictionary = {}
	for field: String in PROFILE_FIELDS:
		var value: Variant = progress.get(field)
		original_profile[field] = value.duplicate(true) if value is Dictionary else value
	var original_process: bool = progress.is_processing()
	var original_actor: Dictionary = main.player.capture_state()
	var original_spawn: Vector2 = main.player.spawn_position
	var original_blocked: bool = main.player.ui_input_blocked
	var original_offset: Vector2 = Vector2(main.framing.offset_x, main.framing.offset_y)
	var original_interface: bool = main.get_node("Interface").visible
	var original_markers: bool = main.player.markers_visible
	var preferences: RefCounted = Preferences.new()
	var original_preferences: Dictionary = preferences.settings(main)
	progress.set_process(false)
	qa_path = "user://qa/boss_live_"+str(Time.get_unix_time_from_system()).replace(".", "_")+"_"+str(Time.get_ticks_usec())+".json"
	helper.qa_path = qa_path
	for key: String in ["route_hero_hp", "tower_boss_state", "first_encounter_state"]:
		if tree.has_meta(key):
			tree.remove_meta(key)
	var configured: bool = progress.configure_storage(qa_path, false)
	progress.set_process(true)
	main._set_paused(false)
	main.player.ui_input_blocked = false
	main.player.free_control()
	main.get_node("Interface").visible = true
	if main.player.markers_visible:
		main._toggle_markers()
	main.get_viewport().gui_release_focus()
	tap(KEY_R)
	await wait_for(tree, progress, "isolated_boss_QA_profile", .1)
	check_result("unique_QA_current_schema_profile_preserves_formal_storage", configured and progress.storage_path == qa_path
		and int(progress.progress.schema) == ProgressScript.PROFILE_SCHEMA and not FileAccess.file_exists(qa_path) and helper.profile_guard() == formal_before,
		{"QA_path": qa_path, "formal_files": formal_before})
	if configured and await route_gate(tree, progress):
		await combat_fixtures(tree, progress)
		await modal_fixtures(tree, progress)
		if await ko_and_shared_hp(tree, progress):
			await victory_and_return(tree, progress)
	# Always bounded cleanup, including when a route or combat assertion failed.
	helper.release_motion()
	progress.set_process(false)
	progress.close_dialog()
	main = tree.current_scene
	if main != null:
		var loot: Node = main.get_node_or_null("FirstLoot")
		if loot != null:
			loot.close_bag()
		for popup: Node in tree.root.find_children("*", "PopupMenu", true, false):
			if popup.visible:
				popup.hide()
		for encounter_name: String in ["TowerBoss", "FirstEncounter"]:
			var encounter: Node = main.get_node_or_null(encounter_name)
			if encounter != null:
				encounter.qa_freeze_enemy = true
	var changed: Error = tree.change_scene_to_file(HARBOR)
	var cleanup: Dictionary = await wait_for(tree, progress, "cleanup_harbor_ready", 2.5, ready_in("harbor"))
	# Old encounter _exit_tree has now persisted its QA state. Restore afterward.
	for field: String in PROFILE_FIELDS:
		progress.set(field, original_profile[field])
	restore_meta(tree, original_meta)
	main = tree.current_scene
	if changed == OK and cleanup.reached:
		progress.progress_changed.emit()
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
	progress.set_process(original_process)
	var profile_restored: bool = PROFILE_FIELDS.all(func(field): return progress.get(field) == original_profile[field])
	check_result("original_profile_including_pending_transaction_and_all_session_meta_restored", cleanup.reached and profile_restored
		and snapshot_meta(tree) == original_meta, {"meta_before": original_meta, "meta_after": snapshot_meta(tree), "profile_fields_restored": profile_restored})
	check_result("original_harbor_actor_preferences_and_input_state_restored", cleanup.reached
		and main.player.capture_state() == original_actor and main.player.spawn_position == original_spawn
		and main.player.ui_input_blocked == original_blocked and preferences.settings(main) == original_preferences)
	var formal_after: Dictionary = helper.profile_guard()
	check_result("formal_profile_backup_temp_presence_and_hashes_unchanged", formal_before == formal_after, {"before": formal_before, "after": formal_after})
	var result: Dictionary = {"candidate": candidate, "checks": checks, "failed": checks.filter(func(c): return not c.pass),
		"duration_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0, "records": records, "screenshots": screenshots,
		"QA_storage_path": qa_path, "QA_storage_absolute_path": ProjectSettings.globalize_path(qa_path),
		"formal_profile_before": formal_before, "formal_profile_after": formal_after,
		"qa_source_sha256": get_script().source_code.sha256_text(),
		"boss_source_sha256": FileAccess.get_file_as_string("res://scripts/tower_boss.gd").sha256_text(),
		"rules_sha256": FileAccess.get_file_as_string("res://data/tower_boss_rules.json").sha256_text(),
		"note": "Marked fixtures stage gate/weapon history, ground positions, attack start, AI freeze or one KO HP14 precondition. Actual R/X/Q/Space and native source/physics clocks supply all measured damage. A separate fresh100/220HP attempt uses only real movement/facing/Q inputs with AI enabled; victory/route/profile receipt are reported separately. All waits are bounded. Unique QA storage is the only write destination for adventure progress, including cleanup; original in-memory pending transactions and listed SceneTree metadata are restored after combat scene exit."}
	var output: FileAccess = FileAccess.open("res://docs/"+output_prefix+"_boss_checks.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(result, "  "))
		output.close()
	return {"checks": checks.size(), "failed": result.failed, "render_cases": render_cases.size(), "recorded_rows": records.size(), "report": "res://docs/"+output_prefix+"_boss_checks.json"}
