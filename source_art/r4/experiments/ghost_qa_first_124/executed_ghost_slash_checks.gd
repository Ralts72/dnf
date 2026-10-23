extends RefCounted
## Focused native checks. Root pose_check_job owns execution across scene changes.

const Inputs = preload("res://tools/r3/quest_checks.gd")
const Preferences = preload("res://tools/r2/travel_checks.gd")
const HARBOR: String = "res://scenes/west_coast_r1.tscn"
const RAW: String = "res://scenes/west_coast_r0.tscn"
const HALL: String = "res://scenes/tower_hall.tscn"
const DEPTHS: String = "res://scenes/tower_depths.tscn"
const META_KEYS: Array[String] = ["route_hero_hp", "tower_boss_state", "first_encounter_state", "world_travel_state", "world_travel_spawn", "world_region", "port_framing_offset", "port_framing_offset_x", "port_compare_state"]
const PROFILE_FIELDS: Array[String] = ["progress", "storage_path", "last_error", "loaded_from_backup", "_storage_ready", "_clear_seen", "_boss_clear_seen", "_save_attempts", "_pending_bundle"]
const SKILL_FIELDS: Array[String] = ["cooldown_remaining", "accepted_casts", "rejected_casts", "reset_count", "last_reject_reason"]
var checks: Array = []
var render_cases: Array = []
var records: Array = []
var screenshots: Dictionary = {}
var helper: RefCounted
var skill: Node
var started_usec: int
var qa_path: String
var output_prefix: String = "r4_02"


func check_result(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check": label, "pass": passed, "details": details})
	render_cases.append({"check": label, "pass": passed})


func point(main: Node) -> Vector2:
	return helper.point(main)


func fight_at(main: Node) -> Node:
	var boss: Node = main.get_node_or_null("TowerBoss")
	return boss if boss != null else main.get_node_or_null("FirstEncounter")


func fx_state(actor: Node) -> Dictionary:
	var fx: RefCounted = actor.action_effects
	var surfaces: Array = []
	for surface: Node in fx.surfaces:
		var material: Material = surface.material_override if surface is Sprite3D else surface.material
		surfaces.append({"visible": surface.visible, "blend": surface.get_meta("source_effect_blend", ""),
			"texture": surface.texture.resource_path if surface.texture != null else "",
			"shader": material.shader.resource_path if material is ShaderMaterial else "",
			"blend_mode": material.blend_mode if material is CanvasItemMaterial else -1,
			"priority": material.render_priority if material is ShaderMaterial else -1})
	return {"clock_ms": fx.pose_time_ms(), "active": fx.active_frames.duplicate(true), "surfaces": surfaces}


func observe(tree: SceneTree, label: String) -> Dictionary:
	var main: Node = tree.current_scene
	if main == null or main.get("player") == null:
		return {}
	var actor: Node = main.player
	var fight: Node = fight_at(main)
	var travel: Node = main.get_node_or_null("WorldTravel")
	var row: Dictionary = {"phase": label, "elapsed_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"scene": main.scene_file_path, "position": point(main), "action": actor.animation_name,
		"frame": actor.frame_index, "frame_elapsed_ms": actor.elapsed_ms, "one_shot": actor._one_shot,
		"next_attack": actor.next_attack, "paused": actor.paused, "blocked": actor.ui_input_blocked,
		"jump_height": actor.jump_motion.height_pixels, "skill": skill.capture_state(), "fx": fx_state(actor),
		"fight": fight.capture_state() if fight != null else {}, "travel": travel.capture_state() if travel != null else {}}
	records.append(row)
	return row


func wait_for(tree: SceneTree, label: String, seconds: float, until: Callable = Callable(), keys: Array = []) -> Dictionary:
	helper.release_motion()
	for code: Key in keys:
		helper.key(code, true)
	var start: int = Time.get_ticks_usec()
	var reached: bool = false
	var last: Dictionary = {}
	while float(Time.get_ticks_usec()-start)/1000000.0 < seconds:
		await RenderingServer.frame_post_draw
		last = observe(tree, label)
		if label == "actual_Z_source_timeline" and not screenshots.has("source_fx") and not last.is_empty() \
			and last.fx.clock_ms >= 200 and last.fx.clock_ms < 400 and last.fx.active.size() == 2:
			screenshot(tree, "source_fx")
		if not last.is_empty() and until.is_valid() and until.call(tree.current_scene, last):
			reached = true
			break
	helper.release_motion()
	return {"reached": reached, "last": last, "duration_seconds": float(Time.get_ticks_usec()-start)/1000000.0}


func ready_scene(path: String) -> Callable:
	return func(main: Node, row: Dictionary): return main.scene_file_path == path and skill.main == main \
		and (path == RAW or row.travel.get("phase", "") == "ready") \
		and (path != HALL or main.get_node_or_null("FirstEncounter") != null) \
		and (path != DEPTHS or main.get_node_or_null("TowerBoss") != null)


func screenshot(tree: SceneTree, name: String) -> void:
	var path: String = "res://docs/previews/"+output_prefix+"_ghost_"+name+".png"
	screenshots[name] = {"path": path, "error": tree.current_scene.get_viewport().get_texture().get_image().save_png(path),
		"scene": tree.current_scene.scene_file_path}


func native_blends(fx: Dictionary, spatial: bool) -> bool:
	if fx.surfaces.size() != 2:
		return false
	for i: int in range(2):
		var surface: Dictionary = fx.surfaces[i]
		if surface.blend != ("normal" if i == 0 else "add"):
			return false
		if spatial:
			var expected: String = "res://shaders/source_effect_normal.gdshader" if i == 0 else "res://shaders/source_effect.gdshader"
			if surface.shader != expected or surface.priority != i+1:
				return false
		elif surface.blend_mode != (CanvasItemMaterial.BLEND_MODE_MIX if i == 0 else CanvasItemMaterial.BLEND_MODE_ADD):
			return false
	return true


func basic_cast(tree: SceneTree) -> void:
	var main: Node = tree.current_scene
	helper.tap(KEY_R)
	await wait_for(tree, "actual_R_before_first_Z", .05)
	var serial: int = skill.accepted_casts
	var rejected: int = skill.rejected_casts
	var next: String = main.player.next_attack
	var started: int = Time.get_ticks_usec()
	helper.tap(KEY_Z)
	var accepted: Dictionary = observe(tree, "actual_first_Z")
	helper.tap(KEY_Z)
	var finished: Dictionary = await wait_for(tree, "actual_Z_source_timeline", 1.3,
		func(_m: Node, row: Dictionary): return not row.one_shot)
	var cast_seconds: float = float(Time.get_ticks_usec()-started)/1000000.0
	var idle_serial: int = skill.accepted_casts
	helper.tap(KEY_Z)
	check_result("actual_Z_is_one_950ms_cast_with_6s_CD_repeat_rejected_X_order_unchanged", accepted.action == "hardattack"
		and accepted.one_shot and absf(float(accepted.skill.cooldown_remaining)-6.0) < .04
		and finished.reached and cast_seconds >= .83 and cast_seconds <= 1.18
		and skill.accepted_casts == serial+1 and idle_serial == skill.accepted_casts
		and skill.rejected_casts >= rejected+2
		and skill.cooldown_remaining > 4.7 and main.player.next_attack == next,
		{"accepted": accepted, "finished": finished, "cast_seconds": cast_seconds, "skill_after_repeat": skill.capture_state()})
	var rows: Array = records.filter(func(row): return row.phase == "actual_Z_source_timeline" and row.action == "hardattack")
	var visible: Array = rows.filter(func(row): return row.fx.clock_ms >= 175 and row.fx.clock_ms < 425)
	check_result("actual_source_clock_displays_both_normal_and_additive_native_tracks", not visible.is_empty()
		and visible.all(func(row): return row.fx.active.size() == 2 and native_blends(row.fx, true) and row.fx.surfaces.all(func(surface): return surface.visible and not surface.texture.is_empty())),
		{"visible_samples": visible.size(), "first": visible[0] if not visible.is_empty() else {}})
	var blank: Array = rows.filter(func(row): return row.fx.clock_ms < 150 or row.fx.clock_ms >= 450)
	check_result("source_effects_are_hidden_before150_and_from450_through_recovery", blank.size() >= 2
		and blank.any(func(row): return row.fx.clock_ms >= 450)
		and blank.all(func(row): return row.fx.active.is_empty() and row.fx.surfaces.all(func(surface): return not surface.visible)),
		{"blank_samples": blank.size()})
	var before: float = skill.cooldown_remaining
	var ground: Vector2 = point(main)
	await wait_for(tree, "actual_walk_during_CD", .18, Callable(), [KEY_D])
	check_result("cooldown_counts_down_during_source_recovery_and_actual_movement", float(accepted.skill.cooldown_remaining)-float(finished.last.skill.cooldown_remaining) > .75
		and before-skill.cooldown_remaining >= .10 and point(main).x-ground.x >= 8.0,
		{"CD_before_move": before, "CD_after_move": skill.cooldown_remaining, "ground_delta": point(main)-ground})
	var expired: Dictionary = await wait_for(tree, "real_six_second_CD_expires", 5.6,
		func(_main: Node, row: Dictionary): return row.skill.ready)
	var expiry_seconds: float = float(Time.get_ticks_usec()-started)/1000000.0
	helper.tap(KEY_Z)
	check_result("actual_CD_reaches_ready_after_six_seconds_and_next_Z_casts", expired.reached and expiry_seconds >= 5.85 and expiry_seconds <= 6.25
		and skill.accepted_casts == serial+2 and main.player.animation_name == "hardattack" and main.player._one_shot,
		{"elapsed_from_first_Z_seconds": expiry_seconds, "ready": expired, "second_cast": skill.capture_state()})
	await wait_for(tree, "second_real_Z_recovers_before_modal_checks", 1.3,
		func(_main: Node, row: Dictionary): return not row.one_shot)


func freeze_gate(tree: SceneTree, kind: String, key: Key, reason: String) -> void:
	var main: Node = tree.current_scene
	skill.cooldown_remaining = 4.0 # Explicit clock precondition, not a cast proof.
	var popup: PopupMenu
	if reason == "menu":
		popup = main.get_node("Interface/AudioMenu").get_popup()
		popup.popup(Rect2i(180, 120, 180, 160))
	else:
		helper.tap(key)
	await wait_for(tree, kind+"_gate_settle", .045)
	var before: Dictionary = skill.capture_state()
	var accepted: int = skill.accepted_casts
	helper.tap(KEY_Z)
	await wait_for(tree, kind+"_gate_frozen", .14)
	var frozen: Dictionary = skill.capture_state()
	if reason == "menu":
		popup.hide()
	else:
		helper.tap(key)
	await wait_for(tree, kind+"_gate_resumed", .08)
	check_result("actual_"+kind+"_freezes_CD_blocks_Z_and_resumes", before.frozen and before.freeze_reason == reason
		and frozen.frozen and frozen.cooldown_remaining == before.cooldown_remaining
		and skill.accepted_casts == accepted and not skill.capture_state().frozen
		and skill.cooldown_remaining < float(frozen.cooldown_remaining)-.025,
		{"before": before, "frozen": frozen, "resumed": skill.capture_state()})


func rejection_and_reset(tree: SceneTree) -> void:
	var main: Node = tree.current_scene
	helper.tap(KEY_R)
	await wait_for(tree, "reject_fixture_R", .04)
	var serial: int = skill.accepted_casts
	helper.tap(KEY_SPACE)
	await wait_for(tree, "real_jump_before_rejected_Z", .09)
	var height: float = main.player.jump_motion.height_pixels
	helper.tap(KEY_Z)
	var air_reject: bool = height > 0 and skill.accepted_casts == serial and skill.cooldown_remaining == 0
	await wait_for(tree, "real_jump_lands", 1.3, func(m: Node, _s: Dictionary): return not m.player.jump_motion.is_active())
	main.player.ui_input_blocked = true # Explicit external-UI gate fixture.
	helper.tap(KEY_Z)
	var ui_reject: bool = skill.accepted_casts == serial and skill.cooldown_remaining == 0
	main.player.ui_input_blocked = false
	main.player.preview("hardattack") # Source preview fixture must not count as casting.
	helper.tap(KEY_Z)
	await wait_for(tree, "preview_rejects_Z", .06)
	check_result("actual_Z_rejected_in_real_air_external_UI_and_source_preview", air_reject and ui_reject
		and skill.accepted_casts == serial and skill.cooldown_remaining == 0 and main.player.preview_mode,
		{"air_height": height, "air_rejected": air_reject, "UI_rejected": ui_reject, "preview_skill": skill.capture_state()})
	main.player.free_control()
	skill.cooldown_remaining = 3.0
	var resets: int = skill.reset_count
	helper.tap(KEY_R)
	await wait_for(tree, "actual_R_clears_CD", .06)
	check_result("one_actual_R_clears_CD_once_and_restores_free_ground_control", skill.cooldown_remaining == 0 and skill.reset_count == resets+1
		and not main.player._one_shot and not main.player.preview_mode and not main.player.ui_input_blocked)


func late_pose(actor: Node) -> void:
	actor.preview("hardattack")
	actor.preview_mode = false
	actor._one_shot = true
	actor.paused = true
	actor.frame_index = 17
	actor.elapsed_ms = 75.0
	actor._apply_frame()
	actor._update_sprite_transform()


func late_frame_and_F4(tree: SceneTree, progress: Node) -> void:
	var equipment: Node = progress.get_node("EquipmentRuntime")
	for weapon: String in ["27304", "practice_lswd0000"]:
		var main: Node = tree.current_scene
		late_pose(main.player)
		var before: Dictionary = main.player.capture_state()
		var swapped: bool = progress.equip_weapon(weapon)
		var stable: bool = main.player.capture_state() == before
		skill.cooldown_remaining = 3.5
		var accepted: int = skill.accepted_casts
		helper.tap(KEY_F4)
		var raw: Dictionary = await wait_for(tree, "late17_"+weapon+"_R0", 2.5, ready_scene(RAW))
		main = tree.current_scene
		var raw_state: Dictionary = main.player.capture_state()
		var raw_fx: Dictionary = fx_state(main.player)
		var layer_count: int = main.player.current_frame().get("layers", []).size()
		check_result("fixture_"+weapon+"_R0_frame17_F4_and_adapter_preserve_clock_and_CD", swapped and stable and raw.reached
			and raw_state.action == "hardattack" and raw_state.frame == 17 and raw_state.elapsed_ms == 75.0 and raw_state.paused
			and layer_count == 9 and equipment.appearance.current_key(main.player) == weapon
			and raw_fx.active.is_empty() and native_blends(raw_fx, false)
			and skill.cooldown_remaining == 3.5 and skill.accepted_casts == accepted,
			{"actor": raw_state, "fx": raw_fx, "appearance": equipment.appearance.capture_state(main.player), "adapter_clock_unchanged": stable})
		helper.tap(KEY_F4)
		var back: Dictionary = await wait_for(tree, "late17_"+weapon+"_R1", 2.5, ready_scene(HARBOR))
		main = tree.current_scene
		var state: Dictionary = main.player.capture_state()
		var fx: Dictionary = fx_state(main.player)
		var texture: String = str(main.player.current_frame().get("texture", ""))
		check_result("fixture_"+weapon+"_R1_frame17_roundtrip_has_valid_texture_and_CD", back.reached and state.action == "hardattack"
			and state.frame == 17 and state.elapsed_ms == 75.0 and state.paused and not texture.is_empty()
			and equipment.appearance.current_key(main.player) == weapon and native_blends(fx, true) and fx.active.is_empty()
			and skill.cooldown_remaining == 3.5 and skill.accepted_casts == accepted,
			{"actor": state, "texture": texture, "appearance": equipment.appearance.capture_state(main.player), "skill": skill.capture_state()})
		if weapon == "27304":
			screenshot(tree, "great_frame17")
		main._set_paused(false)
		main.player.free_control()
	helper.tap(KEY_R)
	await wait_for(tree, "after_F4_actual_R", .04)


func stage_actor(actor: Node, source: Vector2, facing: int) -> void:
	actor.jump_motion.reset()
	actor.free_control()
	actor.paused = false
	actor.ui_input_blocked = false
	actor.velocity = Vector3.ZERO
	actor.position = actor.source_to_world(source)
	actor.facing = facing
	actor._update_sprite_transform()
	actor.reset_physics_interpolation()


func combat_fixture(tree: SceneTree, label: String) -> Node:
	helper.tap(KEY_R) # Real retry supplies authored full HP, not a health write.
	await wait_for(tree, label+"_actual_R", .05)
	var main: Node = tree.current_scene
	var fight: Node = fight_at(main)
	fight.qa_freeze_enemy = true
	stage_actor(main.player, Vector2(440, 315), 1)
	stage_actor(fight.enemy, Vector2(550, 315), -1)
	fight.enemy.release_pose()
	return fight


func hit_case(tree: SceneTree, progress: Node, region: String, weapon: String, damage: int) -> void:
	var equipped: bool = progress.equip_weapon(weapon)
	var fight: Node = await combat_fixture(tree, region+"_"+weapon)
	var hp: int = fight.enemy_hp
	var hits: int = fight.event_counters.hero_hits
	var accepted: int = skill.accepted_casts
	helper.tap(KEY_Z)
	var waited: Dictionary = await wait_for(tree, region+"_"+weapon+"_actual_Z", 1.3,
		func(m: Node, _row: Dictionary): return not m.player._one_shot)
	check_result(region+"_fixture_"+weapon+"_actual_Z_hits_once_for_"+str(damage), equipped and waited.reached
		and hp-fight.enemy_hp == damage and fight.event_counters.hero_hits == hits+1 and skill.accepted_casts == accepted+1,
		{"fixture": "Actual R full HP, staged110px facing gap, enemy AI frozen; actual Z with unmodified source/physics clocks.",
		"before_HP": hp, "after": fight.capture_state(), "skill": skill.capture_state()})


func preview_no_damage(tree: SceneTree, label: String) -> bool:
	var fight: Node = await combat_fixture(tree, label+"_preview")
	var hp: int = fight.enemy_hp
	var hits: int = fight.event_counters.hero_hits
	tree.current_scene.player.preview("hardattack")
	await wait_for(tree, label+"_source_preview_only", .53)
	var passed: bool = fight.enemy_hp == hp and fight.event_counters.hero_hits == hits and skill.cooldown_remaining == 0
	tree.current_scene.player.free_control()
	return passed


func combat_checks(tree: SceneTree, progress: Node) -> void:
	# Scene setup is a fixture; only the hall->depths portal below is a route assertion.
	tree.change_scene_to_file(HALL)
	var hall: Dictionary = await wait_for(tree, "fixture_load_hall", 2.5, ready_scene(HALL))
	if not hall.reached:
		check_result("hall_fixture_initializes", false, hall)
		return
	await hit_case(tree, progress, "hall", "practice_lswd0000", 44)
	await hit_case(tree, progress, "hall", "27304", 48)
	var hall_preview: bool = await preview_no_damage(tree, "hall")
	var first: Node = fight_at(tree.current_scene)
	first.qa_freeze_enemy = true
	stage_actor(tree.current_scene.player, Vector2(760, 325), 1)
	skill.cooldown_remaining = 4.0 # Clock/portal starting-position fixture.
	var accepted: int = skill.accepted_casts
	var crossed: Dictionary = await wait_for(tree, "actual_D_portal_keeps_CD", 2.5, ready_scene(DEPTHS), [KEY_D])
	var transfer_rows: Array = records.filter(func(row): return row.phase == "actual_D_portal_keeps_CD" and row.skill.freeze_reason == "travel")
	var no_reset: bool = skill.cooldown_remaining > 3.0 and skill.cooldown_remaining <= 4.0 and skill.accepted_casts == accepted
	var fade_stable: bool = true
	for i: int in range(1, transfer_rows.size()):
		fade_stable = fade_stable and absf(float(transfer_rows[i].skill.cooldown_remaining)-float(transfer_rows[i-1].skill.cooldown_remaining)) < .001
	check_result("actual_hall_to_depths_portal_preserves_CD_and_freezes_during_fades", crossed.reached and no_reset
		and transfer_rows.size() >= 2 and fade_stable,
		{"transfer": crossed, "travel_frozen_samples": transfer_rows.size(), "fade_stable": fade_stable})
	if not crossed.reached:
		return
	await hit_case(tree, progress, "boss", "practice_lswd0000", 44)
	await hit_case(tree, progress, "boss", "27304", 48)
	var boss_preview: bool = await preview_no_damage(tree, "boss")
	check_result("hall_and_boss_source_preview_has_no_damage_hit_receipt_or_cooldown", hall_preview and boss_preview,
		{"hall": hall_preview, "boss": boss_preview})
	var boss: Node = await combat_fixture(tree, "hurt_CD")
	# One real normal strike from a staged start, without AI freeze during contact.
	stage_actor(boss.enemy, Vector2(510, 315), -1)
	boss.qa_freeze_enemy = false
	boss._start_attack("normal")
	skill.cooldown_remaining = 4.0
	var hurt: Dictionary = await wait_for(tree, "real_enemy_contact_during_CD", .55,
		func(m: Node, _row: Dictionary): return m.get_node("TowerBoss").hero_hurt_remaining > 0)
	var hurt_before: float = skill.cooldown_remaining
	var hurt_rows_start: int = records.size()
	await wait_for(tree, "own_hurt_keeps_CD_ticking", .10)
	var hurt_rows: Array = records.slice(hurt_rows_start).filter(func(row): return row.fight.get("hero_hurt_remaining", 0.0) > 0)
	check_result("real_enemy_contact_hurt_lock_keeps_CD_ticking", hurt.reached and boss.player_hp == 86
		and not hurt_rows.is_empty() and hurt_rows.all(func(row): return not row.skill.frozen)
		and hurt_before-skill.cooldown_remaining >= .045,
		{"contact": hurt, "hurt_samples": hurt_rows.size(), "CD_before": hurt_before, "CD_after": skill.cooldown_remaining})
	boss.qa_freeze_enemy = true


func snapshot_meta(tree: SceneTree) -> Dictionary:
	var result: Dictionary = {}
	for key: String in META_KEYS:
		var present: bool = tree.has_meta(key)
		var value: Variant = tree.get_meta(key) if present else null
		result[key] = {"present": present, "value": value.duplicate(true) if value is Dictionary else value}
	return result


func restore_meta(tree: SceneTree, values: Dictionary) -> void:
	for key: String in META_KEYS:
		if values[key].present:
			tree.set_meta(key, values[key].value)
		elif tree.has_meta(key):
			tree.remove_meta(key)


func run(root: Node, candidate: String = "R4/02") -> Dictionary:
	var tree: SceneTree = root.get_tree()
	started_usec = Time.get_ticks_usec()
	output_prefix = candidate.to_lower().replace("/", "_")
	helper = Inputs.new()
	helper.started_usec = started_usec
	var main: Node = tree.current_scene
	var progress: Node = tree.root.get_node_or_null("AdventureProgress")
	skill = tree.root.get_node_or_null("SourceSkillRuntime")
	if main == null or main.scene_file_path != HARBOR or progress == null or skill == null:
		check_result("integrated_harbor_profile_and_skill_runtime_available", false)
		return {"checks": checks.size(), "failed": checks, "render_cases": render_cases.size()}
	var formal_before: Dictionary = helper.profile_guard()
	var original_meta: Dictionary = snapshot_meta(tree)
	var original_profile: Dictionary = {}
	for field: String in PROFILE_FIELDS:
		var value: Variant = progress.get(field)
		original_profile[field] = value.duplicate(true) if value is Dictionary else value
	var original_skill: Dictionary = {}
	for field: String in SKILL_FIELDS:
		original_skill[field] = skill.get(field)
	var original_process: bool = progress.is_processing()
	var original_skill_process: bool = skill.is_processing()
	var original_actor: Dictionary = main.player.capture_state()
	var original_spawn: Vector2 = main.player.spawn_position
	var original_blocked: bool = main.player.ui_input_blocked
	var original_offset: Vector2 = Vector2(main.framing.offset_x, main.framing.offset_y)
	var original_interface: bool = main.get_node("Interface").visible
	var original_markers: bool = main.player.markers_visible
	var preferences: RefCounted = Preferences.new()
	var original_preferences: Dictionary = preferences.settings(main)
	progress.set_process(false)
	qa_path = "user://qa/ghost_live_"+str(Time.get_ticks_usec())+"_"+str(Time.get_unix_time_from_system()).replace(".", "_")+".json"
	var configured: bool = progress.configure_storage(qa_path, false)
	# Explicit ownership/gate history fixture, confined to the unique QA profile.
	var owned: Dictionary = progress._default_progress()
	owned.quest_stage = "completed"
	owned.objective_cleared = true
	owned.reward_granted = true
	owned.coins = 40
	owned.inventory["3128"] = 1
	owned.first_drop.state = "claimed"
	owned.equipment.owned["27304"] = true
	var committed: bool = progress._commit(owned)
	progress.set_process(true)
	skill.set_process(true)
	for key: String in ["route_hero_hp", "tower_boss_state", "first_encounter_state"]:
		if tree.has_meta(key):
			tree.remove_meta(key)
	main._set_paused(false)
	main.player.ui_input_blocked = false
	main.player.free_control()
	main.get_node("Interface").visible = true
	main.preview_controls._select_effects(true)
	if main.player.markers_visible:
		main._toggle_markers()
	main.get_viewport().gui_release_focus()
	check_result("unique_QA_profile_owns_weapon_fixture_and_formal_four_files_unchanged", configured and committed
		and progress.storage_path == qa_path and progress.owns_weapon("27304") and skill.capture_state().hud_visible
		and main.player._animations.hardattack.frames.size() == 18 and helper.profile_guard() == formal_before,
		{"QA_path": qa_path, "formal_files": formal_before, "fixture": "Completed reward/drop ownership history; no victory claim."})
	if configured and committed:
		await basic_cast(tree)
		await freeze_gate(tree, "F2_pause", KEY_F2, "paused")
		await freeze_gate(tree, "native_menu", KEY_NONE, "menu")
		await freeze_gate(tree, "B_bag", KEY_B, "bag")
		await freeze_gate(tree, "F1_inspection", KEY_F1, "inspection")
		await rejection_and_reset(tree)
		await late_frame_and_F4(tree, progress)
		await combat_checks(tree, progress)
	# Exit old combat scene before restoring metadata, because its _exit_tree persists.
	helper.release_motion()
	helper.key(KEY_Z, false)
	progress.set_process(false)
	skill.set_process(false)
	progress.close_dialog()
	main = tree.current_scene
	if main != null:
		var loot: Node = main.get_node_or_null("FirstLoot")
		if loot != null:
			loot.close_bag()
		var fight: Node = fight_at(main)
		if fight != null:
			fight.qa_freeze_enemy = true
	for popup: Node in tree.root.find_children("*", "PopupMenu", true, false):
		if popup.visible:
			popup.hide()
	var changed: Error = tree.change_scene_to_file(HARBOR)
	var cleanup: Dictionary = await wait_for(tree, "cleanup_fresh_harbor", 2.5, ready_scene(HARBOR))
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
		skill.attach_area(main)
	for field: String in SKILL_FIELDS:
		skill.set(field, original_skill[field])
	skill._refresh_hud()
	progress.set_process(original_process)
	skill.set_process(original_skill_process)
	var restored: bool = PROFILE_FIELDS.all(func(field): return progress.get(field) == original_profile[field])
	var skill_restored: bool = SKILL_FIELDS.all(func(field): return skill.get(field) == original_skill[field])
	check_result("cleanup_restores_original_profile_pending_meta_actor_settings_and_skill_CD_counters", cleanup.reached and restored and skill_restored
		and snapshot_meta(tree) == original_meta and main.player.capture_state() == original_actor
		and main.player.spawn_position == original_spawn and main.player.ui_input_blocked == original_blocked
		and preferences.settings(main) == original_preferences and skill.main == main,
		{"profile_restored": restored, "skill_restored": skill_restored, "cleanup": cleanup})
	var formal_after: Dictionary = helper.profile_guard()
	check_result("formal_profile_primary_backup_and_both_temporary_files_are_byte_unchanged", formal_before == formal_after,
		{"before": formal_before, "after": formal_after})
	var failed: Array = checks.filter(func(c): return not c.pass)
	var report: Dictionary = {"candidate": candidate, "checks": checks, "failed": failed, "records": records, "screenshots": screenshots,
		"duration_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0, "QA_storage_path": qa_path,
		"formal_profile_before": formal_before, "formal_profile_after": formal_after,
		"qa_source_sha256": get_script().source_code.sha256_text(),
		"skill_source_sha256": FileAccess.get_file_as_string("res://scripts/source_skill_runtime.gd").sha256_text(),
		"effects_source_sha256": FileAccess.get_file_as_string("res://scripts/source_actor_effects.gd").sha256_text(),
		"note": "Focused skill checks, not a no-fixture victory. Ownership/gate history, cooldown starting values, paused final-frame poses, source previews, combat positions and AI freeze are explicitly staged. Actual Z drives all damage with original950ms ANI and native clocks. One real boss normal contact proves hurt lock continues CD. No HP writes, damage/clock acceleration or formal profile writes. All waits bounded; profile pending transaction, combat/travel metadata and public cooldown counters restore only after combat scene exit."}
	var path: String = "res://docs/"+output_prefix+"_ghost_slash_checks.json"
	var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "  "))
		output.close()
	return {"checks": checks.size(), "failed": failed, "render_cases": render_cases.size(), "recorded_rows": records.size(), "report": path}
