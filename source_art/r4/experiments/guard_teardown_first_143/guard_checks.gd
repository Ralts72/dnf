extends RefCounted
## Focused native defense checks; only the persistent root job executes this suite.

const Inputs = preload("res://tools/r3/quest_checks.gd")
const StateChecks = preload("res://tools/r4/sharan_checks.gd")
const SuppliesChecks = preload("res://tools/r4/supplies_checks.gd")
const Preferences = preload("res://tools/r2/travel_checks.gd")
const HARBOR: String = "res://scenes/west_coast_r1.tscn"
const RAW: String = "res://scenes/west_coast_r0.tscn"
const HALL: String = "res://scenes/tower_hall.tscn"
const DEPTHS: String = "res://scenes/tower_depths.tscn"
const GUARD_FIELDS: Array[String] = ["cooldown_remaining", "reaction_remaining", "accepted_begins", "rejected_begins", "blocked_hits", "uncovered_hits", "end_count", "reset_count", "last_reject_reason", "last_end_reason", "last_hit", "_active", "_release_pending", "_needs_release", "_locked_facing"]
var checks: Array = []
var render_cases: Array = []
var records: Array = []
var screenshots: Dictionary = {}
var helper: RefCounted
var states: RefCounted
var guard: Node
var skill: Node
var potion: Node
var started_usec: int
var qa_path: String
var output_prefix: String = "r4_05"


func check_result(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check": label, "pass": passed, "details": details})
	render_cases.append({"check": label, "pass": passed})


func point(main: Node) -> Vector2:
	return helper.point(main)


func fight_at(main: Node) -> Node:
	var boss: Node = main.get_node_or_null("TowerBoss")
	return boss if boss != null else main.get_node_or_null("FirstEncounter")


func observe(tree: SceneTree, label: String) -> Dictionary:
	var main: Node = tree.current_scene
	if main == null or main.get("player") == null:
		return {}
	var fight: Node = fight_at(main)
	var travel: Node = main.get_node_or_null("WorldTravel")
	var row: Dictionary = {"phase": label, "elapsed_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"scene": main.scene_file_path, "position": point(main), "action": main.player.animation_name,
		"frame": main.player.frame_index, "frame_elapsed_ms": main.player.elapsed_ms, "facing": main.player.facing,
		"one_shot": main.player._one_shot, "paused": main.player.paused, "blocked": main.player.ui_input_blocked,
		"jump_height": main.player.jump_motion.height_pixels, "guard": guard.capture_state(),
		"skill": skill.capture_state(), "potion": potion.capture_state(),
		"fight": fight.capture_state() if fight != null else {}, "travel": travel.capture_state() if travel != null else {}}
	records.append(row)
	return row


func wait_for(tree: SceneTree, label: String, seconds: float, until: Callable = Callable(), keys: Array = []) -> Dictionary:
	helper.release_motion() # Deliberately does not release C; each hold has an explicit release.
	for code: Key in keys:
		helper.key(code, true)
	var start: int = Time.get_ticks_usec()
	var reached: bool = false
	var last: Dictionary = {}
	while float(Time.get_ticks_usec()-start)/1000000.0 < seconds:
		await RenderingServer.frame_post_draw
		last = observe(tree, label)
		if not last.is_empty() and until.is_valid() and until.call(tree.current_scene, last):
			reached = true
			break
	helper.release_motion()
	return {"reached": reached, "last": last, "duration_seconds": float(Time.get_ticks_usec()-start)/1000000.0}


func ready_scene(path: String) -> Callable:
	return func(main: Node, row: Dictionary): return main.scene_file_path == path and guard.main == main and skill.main == main and potion.main == main \
		and (path == RAW or row.travel.get("phase", "") == "ready") \
		and (path != HARBOR or main.get_node_or_null("PortSupplyShop") != null) \
		and (path != HALL or main.get_node_or_null("FirstEncounter") != null) \
		and (path != DEPTHS or main.get_node_or_null("TowerBoss") != null)


func screenshot(tree: SceneTree, name: String) -> void:
	var path: String = "res://docs/previews/"+output_prefix+"_guard_"+name+".png"
	screenshots[name] = {"path": path, "save_error": tree.current_scene.get_viewport().get_texture().get_image().save_png(path), "scene": tree.current_scene.scene_file_path}


func echo_C() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_C
	event.physical_keycode = KEY_C
	event.pressed = true
	event.echo = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func actual_reset(tree: SceneTree, label: String) -> void:
	helper.key(KEY_C, false)
	helper.tap(KEY_R)
	await wait_for(tree, label+"_actual_R", .04)


func stage_actor(actor: Node, source: Vector2, facing: int) -> void:
	actor.jump_motion.reset()
	actor.free_control()
	actor.ui_input_blocked = false
	actor.paused = false
	actor.velocity = Vector3.ZERO
	actor.position = actor.source_to_world(source)
	actor.facing = facing
	actor._update_sprite_transform()
	actor.reset_physics_interpolation()


func asset_checks() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/r4_guard_source_reference.json"))
	var passed: bool = source.source_scripts.size() == 11 and source.existing_visuals.existing_PNGs.size() == 26
	var sources: Array = []
	for entry: Dictionary in source.source_scripts:
		var exact: bool = entry.crc_matches and FileAccess.get_sha256("res://"+entry.raw_reference) == entry.sha256_decoded
		passed = passed and exact
		sources.append({"path": entry.pvf_path, "CRC_verified_retained_bytes_exact": exact})
	var images: Array = []
	for entry: Dictionary in source.existing_visuals.existing_PNGs:
		var texture: Texture2D = load(entry.path)
		var imported: Image = texture.get_image() if texture != null else null
		var raw := Image.new()
		var loaded: Error = raw.load_png_from_buffer(FileAccess.get_file_as_bytes(entry.path))
		var exact: bool = loaded == OK and imported != null and FileAccess.get_sha256(entry.path) == entry.sha256_png
		if exact and imported.is_compressed():
			exact = imported.decompress() == OK
		if exact:
			raw.convert(Image.FORMAT_RGBA8)
			imported.convert(Image.FORMAT_RGBA8)
			exact = raw.get_size() == imported.get_size() and raw.get_data() == imported.get_data()
		passed = passed and exact
		images.append({"path": entry.path, "native_RGBA_exact": exact})
	for entry: Dictionary in source.existing_visuals.manifests:
		passed = passed and FileAccess.get_sha256("res://"+entry.path) == entry.sha256
	var source_clock: Array = source.source_animation.source_duration_ms
	check_result("eleven_CRC_sources_and26_native_existing_PNGs_preserve_guard123_124", passed
		and source_clock.size() == 2 and float(source_clock[0]) == 10000.0 and float(source_clock[1]) == 10000.0
		and float(guard.rules.cooldown_seconds) == 2.0 and float(guard.rules.reaction_seconds) == .2,
		{"sources": sources, "native_images": images, "new_media": 0})


func hold_and_cooldown(tree: SceneTree, progress: Node) -> void:
	await actual_reset(tree, "first_hold")
	var main: Node = tree.current_scene
	var serial: int = guard.accepted_begins
	var before: Vector2 = point(main)
	var facing: int = main.player.facing
	var start: int = Time.get_ticks_usec()
	helper.key(KEY_C, true)
	var begin: Dictionary = guard.capture_state()
	helper.tap(KEY_F7)
	await wait_for(tree, "actual_C_hold_locks_ground_and_facing", .15, Callable(), [KEY_A, KEY_W, KEY_SHIFT])
	check_result("actual_C_hold_locks_movement_F7_facing_and_uses_source_idle_pose", begin.active and begin.cooldown_remaining == 2.0
		and guard.accepted_begins == serial+1 and guard.capture_state().active and main.player.guard_active
		and point(main).distance_to(before) < .01 and main.player.facing == facing and main.player.animation_name == "guard"
		and main.player.frame_index == 0 and not main.player.ui_input_blocked,
		{"begin": begin, "held": guard.capture_state()})
	var casts: int = skill.accepted_casts
	var uses: int = potion.accepted_uses
	var next: String = main.player.next_attack
	var stock: int = progress.hp_potion_count()
	for key: Key in [KEY_X, KEY_Q, KEY_SPACE, KEY_Z, KEY_H]:
		helper.tap(key)
	await wait_for(tree, "guard_blocks_actual_attack_jump_Z_H", .06)
	check_result("held_guard_rejects_X_Q_Space_Z_H_without_advancing_X_order_or_consuming", guard.capture_state().active
		and main.player.animation_name == "guard" and not main.player._one_shot and not main.player.jump_motion.is_active()
		and main.player.next_attack == next and skill.accepted_casts == casts and potion.accepted_uses == uses
		and progress.hp_potion_count() == stock and skill.cooldown_remaining == 0 and potion.cooldown_remaining == 0)
	helper.key(KEY_C, false)
	await wait_for(tree, "release_leaves_begin_CD_running", .04)
	var ended: bool = not guard.capture_state().active and guard.cooldown_remaining > 1.4
	helper.tap(KEY_C)
	var rejected: bool = guard.accepted_begins == serial+1 and not guard.capture_state().active
	var ready: Dictionary = await wait_for(tree, "actual_two_second_begin_CD_expires", 2.4,
		func(_m: Node, row: Dictionary): return row.guard.cooldown_remaining == 0 and row.guard.can_begin)
	var elapsed: float = float(Time.get_ticks_usec()-start)/1000000.0
	helper.key(KEY_C, true)
	echo_C()
	echo_C()
	check_result("real_two_second_CD_starts_at_begin_release_keeps_it_and_echo_does_not_reopen", ended and rejected and ready.reached
		and elapsed >= 1.85 and elapsed <= 2.3 and guard.capture_state().active and guard.accepted_begins == serial+2,
		{"elapsed_from_begin_seconds": elapsed, "ready": ready, "after_fresh_press_and_echo": guard.capture_state()})
	helper.key(KEY_C, false)
	await wait_for(tree, "second_hold_released", .03)


func frozen_hold(tree: SceneTree, key: Key, reason: String) -> void:
	await actual_reset(tree, reason+"_fixture")
	helper.key(KEY_C, true)
	await wait_for(tree, reason+"_guard_starts", .03)
	helper.tap(key)
	await wait_for(tree, reason+"_freeze_settles", .03)
	var before: Dictionary = guard.capture_state()
	helper.key(KEY_C, false)
	await wait_for(tree, reason+"_release_while_frozen", .14)
	var frozen: Dictionary = guard.capture_state()
	helper.tap(key)
	var resumed: Dictionary = await wait_for(tree, reason+"_resume_ends_released_guard", .3,
		func(_m: Node, row: Dictionary): return not row.guard.active)
	check_result(reason+"_freezes_guard_CD_then_release_ends_on_resume", before.active and before.frozen and before.freeze_reason == reason
		and frozen.active and frozen.cooldown_remaining == before.cooldown_remaining and frozen.reaction_remaining == before.reaction_remaining
		and resumed.reached and not tree.current_scene.player.guard_active,
		{"before": before, "frozen_after_release": frozen, "resume": resumed})


func modal_checks(tree: SceneTree, progress: Node) -> void:
	await actual_reset(tree, "bag_priority")
	var main: Node = tree.current_scene
	helper.key(KEY_C, true)
	var serial: int = guard.accepted_begins
	helper.tap(KEY_B)
	await wait_for(tree, "B_cancels_guard_and_opens_bag", .04)
	var bag_open: bool = main.get_node("FirstLoot").capture_state().bag_open and not guard.capture_state().active
	var previous: String = progress.equipped_weapon_key()
	helper.key(KEY_C, true) # Still held on closing; bag receives its ordinary equip command.
	await wait_for(tree, "bag_C_equips_not_guard", .04)
	var equipped: bool = progress.equipped_weapon_key() != previous and guard.accepted_begins == serial
	screenshot(tree, "bag_priority")
	helper.tap(KEY_B)
	var ready: Dictionary = await wait_for(tree, "held_C_after_bag_does_not_auto_begin_even_when_CD_expires", 2.3,
		func(_m: Node, row: Dictionary): return row.guard.cooldown_remaining == 0)
	var no_carry: bool = not guard.capture_state().active and guard.accepted_begins == serial
	helper.key(KEY_C, false)
	await wait_for(tree, "release_C_clears_bag_carry_latch", .03)
	helper.key(KEY_C, true)
	check_result("bag_C_changes_weapon_and_closing_requires_a_fresh_C_press", bag_open and equipped and ready.reached and no_carry
		and guard.capture_state().active and guard.accepted_begins == serial+1,
		{"bag_cancelled": bag_open, "weapon_changed": equipped, "no_auto_begin": no_carry, "fresh": guard.capture_state()})
	await actual_reset(tree, "menu_cancel")
	helper.key(KEY_C, true)
	var menu: PopupMenu = main.get_node("Interface/AudioMenu").get_popup()
	menu.popup(Rect2i(180,120,180,160))
	await wait_for(tree, "native_menu_cancels_guard", .05)
	var menu_cancelled: bool = menu.visible and not guard.capture_state().active and not main.player.guard_active
	menu.hide()
	helper.key(KEY_C, false)
	await wait_for(tree, "menu_closes_before_preview", .03)
	await actual_reset(tree, "preview_cancel")
	helper.key(KEY_C, true)
	main.player.preview("guard")
	await wait_for(tree, "source_preview_cancels_actual_defense", .04)
	check_result("native_menu_and_source_preview_cancel_actual_guard", menu_cancelled and main.player.preview_mode
		and main.player.animation_name == "guard" and not main.player.guard_active and not guard.capture_state().active)
	helper.key(KEY_C, false)
	main.player.free_control()
	await actual_reset(tree, "dialog_cancel")
	stage_actor(main.player, Vector2(320,310), 1) # Near-NPC starting-position fixture.
	helper.key(KEY_C, true)
	helper.tap(KEY_E)
	await wait_for(tree, "actual_E_opens_Lorian_and_cancels_guard", .04)
	check_result("actual_E_dialog_cancels_guard_without_dangling_defense", progress.capture_state().dialog_open
		and main.player.ui_input_blocked and not guard.capture_state().active and not main.player.guard_active)
	helper.key(KEY_C, false)
	helper.tap(KEY_ESCAPE)
	await wait_for(tree, "dialog_Esc_closes", .03)
	await actual_reset(tree, "active_R_cancel")
	helper.key(KEY_C, true)
	var resets: int = guard.reset_count
	helper.tap(KEY_R)
	await wait_for(tree, "actual_R_clears_active_guard", .04)
	check_result("one_actual_R_clears_active_guard_and_its_CD", not guard.capture_state().active and not main.player.guard_active
		and guard.cooldown_remaining == 0 and guard.reset_count == resets+1 and main.player.animation_name != "guard")
	helper.key(KEY_C, false)


func comparison_and_gates(tree: SceneTree) -> void:
	await actual_reset(tree, "F4_cancel")
	helper.key(KEY_C, true)
	var serial: int = guard.accepted_begins
	var cd: float = guard.cooldown_remaining
	helper.tap(KEY_F4)
	var raw: Dictionary = await wait_for(tree, "actual_F4_guard_cancel_before_R0_capture", 2.5, ready_scene(RAW))
	var raw_state: Dictionary = observe(tree, "R0_skill_and_potion_API_are_valid")
	var raw_ok: bool = raw.reached and not raw_state.guard.active and raw_state.action != "guard" \
		and raw_state.guard.freeze_reason == "comparison" and raw_state.skill.can_cast \
		and raw_state.potion.freeze_reason == "comparison" and not raw_state.potion.can_use
	helper.key(KEY_C, true)
	await wait_for(tree, "R0_C_cannot_start_guard", .08)
	var raw_stable: bool = guard.accepted_begins == serial and guard.cooldown_remaining == cd
	helper.key(KEY_C, false)
	helper.tap(KEY_F4)
	var back: Dictionary = await wait_for(tree, "actual_F4_R1_has_no_guard_pose_carry", 2.5, ready_scene(HARBOR))
	check_result("F4_cancels_before_capture_R0_APIs_work_and_R1_has_no_guard_carry", raw_ok and raw_stable and back.reached
		and not guard.capture_state().active and not tree.current_scene.player.guard_active and tree.current_scene.player.animation_name != "guard",
		{"R0": raw_state, "R0_clock_stable": raw_stable, "return": back})
	await actual_reset(tree, "guard_entry_gates")
	var main: Node = tree.current_scene
	serial = guard.accepted_begins
	helper.tap(KEY_SPACE)
	var air: Dictionary = await wait_for(tree, "real_air_before_C", .4,
		func(m: Node, _row: Dictionary): return m.player.jump_motion.height_pixels > 10.0)
	helper.key(KEY_C, true)
	var air_rejected: bool = air.reached and guard.accepted_begins == serial and not guard.capture_state().active
	helper.key(KEY_C, false)
	await wait_for(tree, "real_jump_lands_before_attack_C", 1.3,
		func(m: Node, _row: Dictionary): return not m.player.jump_motion.is_active())
	helper.tap(KEY_X)
	helper.key(KEY_C, true)
	var action_rejected: bool = main.player._one_shot and guard.accepted_begins == serial and not guard.capture_state().active
	helper.key(KEY_C, false)
	await wait_for(tree, "real_attack_finishes_before_preview_C", .9,
		func(m: Node, _row: Dictionary): return not m.player._one_shot)
	main.player.preview("guard")
	helper.key(KEY_C, true)
	check_result("fresh_C_rejected_in_real_air_attack_and_source_preview", air_rejected and action_rejected
		and guard.accepted_begins == serial and not guard.capture_state().active,
		{"air_wait": air, "air_rejected": air_rejected, "attack_rejected": action_rejected})
	helper.key(KEY_C, false)
	main.player.free_control()


func boss_fixture(tree: SceneTree, label: String, back: bool = false, initial_hp: int = 100) -> Node:
	await actual_reset(tree, label)
	var main: Node = tree.current_scene
	var boss: Node = main.get_node("TowerBoss")
	boss.qa_freeze_enemy = true
	stage_actor(main.player, Vector2(440,315), 1)
	stage_actor(boss.enemy, Vector2(370 if back else 510,315), 1 if back else -1)
	if initial_hp != 100:
		boss.player_hp = initial_hp # Explicit chip-KO precondition, not measured damage.
		boss._persist()
	return boss


func boss_checks(tree: SceneTree) -> bool:
	tree.change_scene_to_file(DEPTHS) # Direct arena setup is a fixture, not route completion.
	var ready: Dictionary = await wait_for(tree, "fixture_depths_ready", 2.5, ready_scene(DEPTHS))
	if not ready.reached:
		check_result("boss_fixture_loads", false, ready)
		return false
	var boss: Node = await boss_fixture(tree, "front_normal")
	var hits: int = guard.blocked_hits
	var enemy_hits: int = boss.event_counters.enemy_hits
	helper.key(KEY_C, true)
	boss.qa_freeze_enemy = false
	boss._start_attack("normal")
	var contact: Dictionary = await wait_for(tree, "actual_boss_normal_front_contact", .65,
		func(_m: Node, row: Dictionary): return row.guard.blocked_hits > hits)
	check_result("real_front_boss_normal14_becomes9_without_hurt_or_enemy_freeze", contact.reached and boss.player_hp == 91
		and guard.blocked_hits == hits+1 and boss.event_counters.enemy_hits == enemy_hits+1 and boss.attack_clock >= 180.0
		and boss.hero_hurt_remaining == 0 and not tree.current_scene.player.ui_input_blocked and guard.capture_state().active
		and tree.current_scene.player.frame_index == 1 and absf(point(tree.current_scene).x-434.0) < .03 and boss.enemy_hp == 220,
		{"contact": contact, "fixture": "Real normal clock/contact from staged70px facing gap; enemy AI enabled."})
	screenshot(tree, "normal_contact")
	# Keep the enemy running through the rest of its active window: freezing
	# here would make the one-contact latch assertion vacuous.
	var idle: Dictionary = await wait_for(tree, "hold_returns_to_source_guard_idle_after_response", .45,
		func(m: Node, row: Dictionary): return row.guard.reaction_remaining == 0 and m.player.frame_index == 0)
	check_result("held_C_response_returns_to_frame0_and_same_enemy_swing_hits_once", idle.reached and guard.capture_state().active
		and guard.blocked_hits == hits+1 and boss.event_counters.enemy_hits == enemy_hits+1 and boss.player_hp == 91)
	boss.qa_freeze_enemy = true
	boss = await boss_fixture(tree, "front_heavy")
	hits = guard.blocked_hits
	helper.key(KEY_C, true)
	boss.qa_freeze_enemy = false
	boss._start_attack("heavy")
	var heavy: Dictionary = await wait_for(tree, "actual_boss_heavy_front_contact", 1.35,
		func(_m: Node, row: Dictionary): return row.guard.blocked_hits > hits)
	check_result("real_front_heavy24_becomes15_and_remains_guarded", heavy.reached and boss.player_hp == 85
		and boss.attack_clock >= 850.0 and guard.last_hit.raw_damage == 24 and guard.last_hit.damage == 15
		and boss.hero_hurt_remaining == 0 and guard.capture_state().active and not tree.current_scene.player.ui_input_blocked,
		{"contact": heavy})
	var released_at: int = Time.get_ticks_usec()
	helper.key(KEY_C, false)
	await wait_for(tree, "released_C_still_has_200ms_impact_pose", .04)
	var held_response: bool = guard.capture_state().active and tree.current_scene.player.frame_index == 1
	var ended: Dictionary = await wait_for(tree, "released_C_ends_after_impact_clock", .4,
		func(_m: Node, row: Dictionary): return not row.guard.active)
	var response_seconds: float = float(Time.get_ticks_usec()-released_at)/1000000.0
	check_result("release_during_contact_waits_real_200ms_response_without_resetting_begin_CD", held_response and ended.reached
		and response_seconds >= .12 and response_seconds <= .31 and guard.cooldown_remaining > .6 and guard.cooldown_remaining < 1.3
		and not tree.current_scene.player.guard_active and boss.player_hp == 85,
		{"seconds_from_release": response_seconds, "end": ended})
	boss.qa_freeze_enemy = true
	boss = await boss_fixture(tree, "rear_normal", true)
	var uncovered: int = guard.uncovered_hits
	hits = guard.blocked_hits
	enemy_hits = boss.event_counters.enemy_hits
	helper.key(KEY_C, true)
	boss.qa_freeze_enemy = false
	boss._start_attack("normal")
	var rear: Dictionary = await wait_for(tree, "actual_rear_normal_is_not_blocked", .65,
		func(_m: Node, row: Dictionary): return row.fight.event_counters.enemy_hits > enemy_hits)
	check_result("real_rear_normal_keeps14_damage_hurt_and_cancels_guard", rear.reached and boss.player_hp == 86
		and guard.uncovered_hits == uncovered+1 and guard.blocked_hits == hits and not guard.capture_state().active
		and not tree.current_scene.player.guard_active and boss.hero_hurt_remaining > 0 and tree.current_scene.player.ui_input_blocked,
		{"rear_contact": rear})
	boss.qa_freeze_enemy = true
	boss = await boss_fixture(tree, "front_chip_KO", false, 5)
	helper.key(KEY_C, true)
	boss.qa_freeze_enemy = false
	boss._start_attack("normal")
	var ko: Dictionary = await wait_for(tree, "real_guard_chip_can_KO", .65,
		func(_m: Node, row: Dictionary): return row.fight.player_hp == 0)
	var ended_on_ko: bool = ko.reached and not guard.capture_state().active and not tree.current_scene.player.guard_active \
		and tree.current_scene.player.ui_input_blocked
	await actual_reset(tree, "chip_KO_retry")
	check_result("guard_chip_is_not_invulnerability_and_KO_R_releases_input", ended_on_ko and boss.player_hp == 100
		and not tree.current_scene.player.ui_input_blocked and guard.cooldown_remaining == 0,
		{"chip_KO": ko, "fixture": "Only initial5HP is staged; real front normal chip9 causes KO."})
	boss.qa_freeze_enemy = true
	return true


func hall_and_travel_checks(tree: SceneTree) -> void:
	tree.change_scene_to_file(HALL)
	var hall: Dictionary = await wait_for(tree, "fixture_hall_guard_ready", 2.5, ready_scene(HALL))
	if not hall.reached:
		check_result("hall_fixture_loads", false, hall)
		return
	await actual_reset(tree, "Mirkius_front_guard")
	var first: Node = tree.current_scene.get_node("FirstEncounter")
	stage_actor(tree.current_scene.player, Vector2(440,315), 1)
	stage_actor(first.enemy, Vector2(505,315), -1)
	var hits: int = guard.blocked_hits
	helper.key(KEY_C, true)
	first.qa_freeze_enemy = false
	var contact: Dictionary = await wait_for(tree, "actual_Mirkius_AI_front_contact", 1.8,
		func(_m: Node, row: Dictionary): return row.guard.blocked_hits > hits)
	check_result("real_Mirkius_AI12_becomes8_without_hurt", contact.reached and first.player_hp == 92
		and guard.last_hit.raw_damage == 12 and guard.last_hit.damage == 8 and first.hero_hurt_remaining == 0
		and guard.capture_state().active and first.event_counters.enemy_attacks >= 1,
		{"contact": contact, "fixture": "Only initial65px positions are staged; normal AI chooses and runs its own attack."})
	first.qa_freeze_enemy = true
	helper.key(KEY_C, false)
	tree.change_scene_to_file(DEPTHS)
	var depths: Dictionary = await wait_for(tree, "fixture_portal_guard_depths", 2.5, ready_scene(DEPTHS))
	if not depths.reached:
		check_result("portal_fixture_loads", false, depths)
		return
	await actual_reset(tree, "portal_gate")
	tree.current_scene.get_node("TowerBoss").qa_freeze_enemy = true
	stage_actor(tree.current_scene.player, Vector2(38,320), -1)
	helper.key(KEY_C, true)
	var serial: int = guard.accepted_begins
	await wait_for(tree, "actual_A_held_guard_cannot_use_exit", .28, Callable(), [KEY_A])
	var refused: bool = tree.current_scene.scene_file_path == DEPTHS and guard.capture_state().active
	helper.key(KEY_C, false)
	var crossed: Dictionary = await wait_for(tree, "release_guard_then_actual_A_travels", 2.5, ready_scene(HALL), [KEY_A])
	if crossed.reached:
		tree.current_scene.get_node("FirstEncounter").qa_freeze_enemy = true
	check_result("guarded_exit_is_refused_release_allows_actual_travel_with_CD_and_no_pose_carry", refused and crossed.reached
		and not guard.capture_state().active and not tree.current_scene.player.guard_active
		and guard.accepted_begins == serial and guard.cooldown_remaining > .7 and guard.cooldown_remaining < 1.9,
		{"refused_while_guarded": refused, "travel": crossed})
	await actual_reset(tree, "forced_scene_change")
	helper.key(KEY_C, true)
	serial = guard.accepted_begins
	tree.change_scene_to_file(DEPTHS) # Explicit external scene-change fixture.
	var forced: Dictionary = await wait_for(tree, "forced_scene_change_cancels_held_C", 2.5, ready_scene(DEPTHS))
	if forced.reached:
		tree.current_scene.get_node("TowerBoss").qa_freeze_enemy = true
	check_result("forced_scene_change_cancels_active_guard_without_held_key_carry", forced.reached and not guard.capture_state().active
		and not tree.current_scene.player.guard_active and guard.accepted_begins == serial,
		{"fixture_scene_change": forced})
	helper.key(KEY_C, false)


func run(root: Node, candidate: String = "R4/05") -> Dictionary:
	var tree: SceneTree = root.get_tree()
	started_usec = Time.get_ticks_usec()
	output_prefix = candidate.to_lower().replace("/", "_")
	helper = Inputs.new()
	helper.started_usec = started_usec
	states = StateChecks.new()
	var main: Node = tree.current_scene
	var progress: Node = tree.root.get_node_or_null("AdventureProgress")
	guard = tree.root.get_node_or_null("GuardRuntime")
	skill = tree.root.get_node_or_null("SourceSkillRuntime")
	potion = tree.root.get_node_or_null("HpPotionRuntime")
	if main == null or main.scene_file_path != HARBOR or progress == null or guard == null or skill == null or potion == null or guard.capture_state().active:
		check_result("fresh_integrated_harbor_with_inactive_guard_available", false)
		return {"checks": checks.size(), "failed": checks, "render_cases": render_cases.size()}
	var formal_before: Dictionary = helper.profile_guard()
	var original_meta: Dictionary = states.snapshot_meta(tree)
	var original_profile: Dictionary = states.snapshot_fields(progress, StateChecks.PROFILE_FIELDS)
	var original_guard: Dictionary = states.snapshot_fields(guard, GUARD_FIELDS)
	var original_skill: Dictionary = states.snapshot_fields(skill, StateChecks.SKILL_FIELDS)
	var original_potion: Dictionary = states.snapshot_fields(potion, SuppliesChecks.POTION_FIELDS)
	var process_before: Array[bool] = [progress.is_processing(), guard.is_processing(), guard.is_physics_processing(), skill.is_processing(), potion.is_processing()]
	var original_actor: Dictionary = main.player.capture_state()
	var original_spawn: Vector2 = main.player.spawn_position
	var original_blocked: bool = main.player.ui_input_blocked
	var original_offset: Vector2 = Vector2(main.framing.offset_x, main.framing.offset_y)
	var original_interface: bool = main.get_node("Interface").visible
	var original_markers: bool = main.player.markers_visible
	var original_restore_count: int = main.get_node("SharanInteraction").restore_count
	var preferences: RefCounted = Preferences.new()
	var original_preferences: Dictionary = preferences.settings(main)
	progress.set_process(false)
	qa_path = "user://qa/guard_live_"+str(Time.get_ticks_usec())+"_"+str(Time.get_unix_time_from_system()).replace(".", "_")+".json"
	var configured: bool = progress.configure_storage(qa_path, false)
	# Completed reward/one purchased potion is explicit history, not a quest proof.
	var fixture: Dictionary = progress._default_progress()
	fixture.quest_stage = "completed"
	fixture.objective_cleared = true
	fixture.reward_granted = true
	fixture.coins = 30
	fixture.first_drop.state = "claimed"
	fixture.inventory["3128"] = 1
	fixture.inventory["1106"] = 1
	fixture.equipment.owned["27304"] = true
	var committed: bool = progress._commit(fixture)
	for key: String in ["first_encounter_state", "tower_boss_state"]:
		if tree.has_meta(key):
			tree.remove_meta(key)
	tree.set_meta("route_hero_hp", 50) # H is genuinely eligible except for held guard.
	progress.set_process(true)
	guard.set_process(true)
	guard.set_physics_process(true)
	skill.set_process(true)
	potion.set_process(true)
	main._set_paused(false)
	main.player.ui_input_blocked = false
	main.player.free_control()
	main.get_node("Interface").visible = true
	if main.player.markers_visible:
		main._toggle_markers()
	main.get_viewport().gui_release_focus()
	helper.key(KEY_C, false)
	check_result("unique_QA_profile_legitimate_potion_owned_fixture_preserves_formal_four_files", configured and committed
		and progress.storage_path == qa_path and progress.hp_potion_count() == 1 and potion.capture_state().player_hp == 50
		and helper.profile_guard() == formal_before,
		{"QA_path": qa_path, "fixture": "Completed reward,30gold/one purchased potion, ownership and50 initialHP only."})
	if configured and committed:
		asset_checks()
		await hold_and_cooldown(tree, progress)
		await frozen_hold(tree, KEY_F2, "paused")
		await frozen_hold(tree, KEY_F1, "inspection")
		await modal_checks(tree, progress)
		await comparison_and_gates(tree)
		if await boss_checks(tree):
			await hall_and_travel_checks(tree)
	# Close the QA encounter first; its exit writes must precede original-meta restore.
	helper.release_motion()
	helper.key(KEY_C, false)
	guard.end_guard("qa_cleanup")
	progress.set_process(false)
	guard.set_process(false)
	guard.set_physics_process(false)
	skill.set_process(false)
	potion.set_process(false)
	main = tree.current_scene
	if main != null:
		for pair: Array in [["PortSupplyShop", "close_shop"], ["SharanInteraction", "close_dialog"], ["FirstLoot", "close_bag"]]:
			var controller: Node = main.get_node_or_null(pair[0])
			if controller != null:
				controller.call(pair[1])
		var fight: Node = fight_at(main)
		if fight != null:
			fight.qa_freeze_enemy = true
	progress.close_dialog()
	for popup: Node in tree.root.find_children("*", "PopupMenu", true, false):
		if popup.visible:
			popup.hide()
	var changed: Error = tree.change_scene_to_file(HARBOR)
	var cleanup: Dictionary = await wait_for(tree, "cleanup_fresh_harbor", 2.5, ready_scene(HARBOR))
	states.restore_fields(progress, original_profile)
	states.restore_meta(tree, original_meta)
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
		main.get_node("SharanInteraction").restore_count = original_restore_count
		guard.attach_area(main)
		skill.attach_area(main)
		potion.attach_area(main)
	states.restore_fields(guard, original_guard)
	states.restore_fields(skill, original_skill)
	states.restore_fields(potion, original_potion)
	guard._refresh_hud()
	skill._refresh_hud()
	potion._refresh_hud()
	progress.set_process(process_before[0])
	guard.set_process(process_before[1])
	guard.set_physics_process(process_before[2])
	skill.set_process(process_before[3])
	potion.set_process(process_before[4])
	check_result("cleanup_restores_profile_pending_meta_actor_preferences_and_all_runtime_state", cleanup.reached
		and states.snapshot_fields(progress, StateChecks.PROFILE_FIELDS) == original_profile and states.snapshot_meta(tree) == original_meta
		and states.snapshot_fields(guard, GUARD_FIELDS) == original_guard and states.snapshot_fields(skill, StateChecks.SKILL_FIELDS) == original_skill
		and states.snapshot_fields(potion, SuppliesChecks.POTION_FIELDS) == original_potion and main.player.capture_state() == original_actor
		and main.player.spawn_position == original_spawn and main.player.ui_input_blocked == original_blocked
		and preferences.settings(main) == original_preferences and guard.main == main and not main.player.guard_active,
		{"cleanup": cleanup})
	var formal_after: Dictionary = helper.profile_guard()
	check_result("formal_primary_backup_and_both_temporary_files_are_byte_unchanged", formal_before == formal_after,
		{"before": formal_before, "after": formal_after})
	var failed: Array = checks.filter(func(c): return not c.pass)
	var report: Dictionary = {"candidate": candidate, "checks": checks, "failed": failed, "records": records, "screenshots": screenshots,
		"duration_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0, "QA_storage_path": qa_path,
		"formal_profile_before": formal_before, "formal_profile_after": formal_after, "qa_source_sha256": get_script().source_code.sha256_text(),
		"guard_source_sha256": FileAccess.get_file_as_string("res://scripts/guard_runtime.gd").sha256_text(),
		"guard_rules_sha256": FileAccess.get_file_as_string("res://data/guard_rules.json").sha256_text(),
		"note": "Focused guard proof, not a fixture-free victory. Reward/potion history, source positions, direct arena entry, boss attack starts and initial5HP chip-KO are explicit fixtures. Actual C/hold/release/echo and X/Q/Space/Z/H/F1/F2/F4/F7/B/E/R inputs supply gates; enemy attack clocks and contact damage are native and unmodified. Mirkius chooses its own attack. Original pending profile, metadata, actor/preferences and all three runtime clocks/counters restore after combat exit. PNGs read through buffers; no JSON int/float deep-equality assumptions. All waits bounded."}
	var path: String = "res://docs/"+output_prefix+"_guard_checks.json"
	var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "  "))
		output.close()
	return {"checks": checks.size(), "failed": failed, "render_cases": render_cases.size(), "recorded_rows": records.size(), "report": path}
