extends RefCounted
## A small native interaction suite; execute only through the persistent root job.

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
var qa_path: String
var started_usec: int
var output_prefix: String = "r4_03"


func check_result(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check": label, "pass": passed, "details": details})
	render_cases.append({"check": label, "pass": passed})


func snapshot_fields(object: Object, fields: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for field: String in fields:
		var value: Variant = object.get(field)
		result[field] = value.duplicate(true) if value is Dictionary else value
	return result


func restore_fields(object: Object, fields: Dictionary) -> void:
	for field: String in fields:
		object.set(field, fields[field])


func snapshot_meta(tree: SceneTree) -> Dictionary:
	var result: Dictionary = {}
	for key: String in META_KEYS:
		var present: bool = tree.has_meta(key)
		var value: Variant = tree.get_meta(key) if present else null
		result[key] = {"present": present, "value": value.duplicate(true) if value is Dictionary else value}
	return result


func restore_meta(tree: SceneTree, fields: Dictionary) -> void:
	for key: String in META_KEYS:
		if fields[key].present:
			tree.set_meta(key, fields[key].value)
		elif tree.has_meta(key):
			tree.remove_meta(key)


func file_guard(path: String) -> Dictionary:
	var result: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		var file: String = path+suffix
		var exists: bool = FileAccess.file_exists(file)
		result[file] = {"exists": exists, "sha256": FileAccess.get_sha256(file) if exists else ""}
	return result


func point(main: Node) -> Vector2:
	return helper.point(main)


func observe(tree: SceneTree, label: String) -> Dictionary:
	var main: Node = tree.current_scene
	if main == null or main.get("player") == null:
		return {}
	var sharan: Node = main.get_node_or_null("SharanInteraction")
	var travel: Node = main.get_node_or_null("WorldTravel")
	var row: Dictionary = {"phase": label, "elapsed_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"scene": main.scene_file_path, "position": point(main), "action": main.player.animation_name,
		"one_shot": main.player._one_shot, "paused": main.player.paused, "blocked": main.player.ui_input_blocked,
		"jump_height": main.player.jump_motion.height_pixels, "skill": skill.capture_state(),
		"sharan": sharan.capture_state() if sharan != null else {}, "travel": travel.capture_state() if travel != null else {}}
	records.append(row)
	return row


func wait_for(tree: SceneTree, label: String, seconds: float, until: Callable = Callable(), keys: Array = []) -> Dictionary:
	helper.release_motion()
	for code: Key in keys:
		helper.key(code, true)
	var start: int = Time.get_ticks_usec()
	var last: Dictionary = {}
	var reached: bool = false
	while float(Time.get_ticks_usec()-start)/1000000.0 < seconds:
		await RenderingServer.frame_post_draw
		last = observe(tree, label)
		if not last.is_empty() and until.is_valid() and until.call(tree.current_scene, last):
			reached = true
			break
	helper.release_motion()
	return {"reached": reached, "last": last, "duration_seconds": float(Time.get_ticks_usec()-start)/1000000.0}


func ready_scene(path: String) -> Callable:
	return func(main: Node, row: Dictionary): return main.scene_file_path == path and skill.main == main \
		and (path == RAW or row.travel.get("phase", "") == "ready") \
		and (path != HARBOR or main.get_node_or_null("SharanInteraction") != null) \
		and (path != HALL or main.get_node_or_null("FirstEncounter") != null) \
		and (path != DEPTHS or main.get_node_or_null("TowerBoss") != null)


func screenshot(tree: SceneTree, name: String) -> void:
	var path: String = "res://docs/previews/"+output_prefix+"_sharan_"+name+".png"
	screenshots[name] = {"path": path, "save_error": tree.current_scene.get_viewport().get_texture().get_image().save_png(path),
		"scene": tree.current_scene.scene_file_path}


func image_hash(image: Image) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(image.get_data())
	return hashing.finish().hex_encode()


func asset_checks(main: Node) -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/r4_sharan_source_reference.json"))
	var rows: Array = []
	var passed: bool = source.portraits.size() == 3 and source.source_scripts.size() == 5
	for key: String in source.portraits:
		var entry: Dictionary = source.portraits[key]
		var texture: Texture2D = load(entry.path)
		var raw: Image = Image.load_from_file(entry.path)
		var native: Image = texture.get_image() if texture != null else null
		var exact: bool = raw != null and native != null
		if exact:
			if native.is_compressed():
				native.decompress()
			raw.convert(Image.FORMAT_RGBA8)
			native.convert(Image.FORMAT_RGBA8)
			exact = raw.get_size() == Vector2i(entry.size[0], entry.size[1]) and native.get_size() == raw.get_size() \
				and native.get_data() == raw.get_data() and image_hash(native) == entry.sha256_rgba \
				and FileAccess.get_sha256(entry.path) == entry.sha256_png
		passed = passed and exact
		rows.append({"name": key, "path": entry.path, "native_RGBA_exact": exact,
			"size": native.get_size() if native != null else Vector2i.ZERO})
	var pvf: Array = []
	for entry: Dictionary in source.source_scripts:
		var exact: bool = FileAccess.get_sha256("res://"+entry.evidence_path) == entry.sha256 and entry.crc_matches
		passed = passed and exact
		pvf.append({"path": entry.pvf_path, "retained_bytes_match_CRC_verified_source": exact})
	check_result("three_native_portrait_PNGs_roundtrip_RGBA_and_five_retained_source_files_match", passed
		and main.npc_sr.animation_data == "res://data/npc_sr_r1.json",
		{"native_images": rows, "source_files": pvf, "NPC_animation": main.npc_sr.animation_data})


func entry_checks(tree: SceneTree, progress: Node) -> bool:
	var main: Node = tree.current_scene
	await wait_for(tree, "actual_W_to_Sharan_depth", .18, Callable(), [KEY_W])
	var walked: Dictionary = await wait_for(tree, "actual_A_walk_to_Sharan", 3.5,
		func(m: Node, _row: Dictionary): return point(m).x <= 190.0, [KEY_A, KEY_SHIFT])
	var sharan: Node = main.get_node("SharanInteraction")
	check_result("actual_W_A_walk_reaches_Sharan_prompt", walked.reached and sharan.can_interact()
		and sharan.capture_state().prompt_visible and not progress.capture_state().dialog_open,
		{"walk": walked, "NPC": sharan.capture_state()})
	if not walked.reached or not sharan.can_interact():
		return false
	helper.tap(KEY_F2)
	helper.tap(KEY_E)
	var pause_rejected: bool = main.player.paused and not sharan.capture_state().dialog_open
	helper.tap(KEY_F2)
	var menu: PopupMenu = main.get_node("Interface/AudioMenu").get_popup()
	menu.popup(Rect2i(180, 120, 180, 160))
	helper.tap(KEY_E)
	var menu_rejected: bool = menu.visible and not sharan.capture_state().dialog_open
	menu.hide()
	await wait_for(tree, "native_menu_closes_before_real_jump", .04)
	helper.tap(KEY_SPACE)
	var air: Dictionary = await wait_for(tree, "real_jump_before_NPC_E", .4,
		func(m: Node, _row: Dictionary): return m.player.jump_motion.height_pixels > 10.0)
	helper.tap(KEY_E)
	var air_rejected: bool = air.reached and not sharan.capture_state().dialog_open
	await wait_for(tree, "real_jump_lands_before_talking", 1.3,
		func(m: Node, _row: Dictionary): return not m.player.jump_motion.is_active())
	check_result("actual_E_rejected_while_paused_native_menu_or_really_airborne", pause_rejected and menu_rejected and air_rejected,
		{"paused": pause_rejected, "menu": menu_rejected, "airborne": air_rejected, "air_wait": air})
	return true


func dialog_and_health(tree: SceneTree, progress: Node) -> void:
	var main: Node = tree.current_scene
	var sharan: Node = main.get_node("SharanInteraction")
	var restores_before: int = sharan.restore_count
	skill.cooldown_remaining = 4.0 # Explicit cooldown precondition, no skill cast/attack claim.
	helper.tap(KEY_E)
	await wait_for(tree, "actual_E_opens_Sharan", .04)
	var ground: Vector2 = point(main)
	var serial: int = main.player.attack_instance
	var casts: int = skill.accepted_casts
	var clock: float = skill.cooldown_remaining
	for key: Key in [KEY_X, KEY_SPACE, KEY_B, KEY_Z]:
		helper.tap(key)
	await wait_for(tree, "modal_rejects_actual_actions_and_movement", .14, Callable(), [KEY_D, KEY_W])
	var portraits: Array[Node] = sharan._layer.find_children("*", "TextureRect", true, false)
	var portrait_ok: bool = portraits.size() == 1 and portraits[0].texture != null \
		and portraits[0].texture.resource_path == "res://assets/r4/sharan/portrait.png" \
		and portraits[0].texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
	check_result("actual_E_dialog_shows_source_portrait_blocks_move_X_Space_B_Z_and_freezes_CD", sharan.capture_state().dialog_open
		and portrait_ok and main.player.ui_input_blocked and point(main).distance_to(ground) < .01
		and main.player.attack_instance == serial and not main.player._one_shot and not main.player.jump_motion.is_active()
		and not main.get_node("FirstLoot").capture_state().bag_open and skill.accepted_casts == casts
		and skill.cooldown_remaining == clock and skill.capture_state().frozen,
		{"portrait_applied": portrait_ok, "NPC": sharan.capture_state(), "skill": skill.capture_state()})
	screenshot(tree, "dialog")
	helper.tap(KEY_E)
	var before_walk: Vector2 = point(main)
	await wait_for(tree, "actual_E_close_resumes_A_and_CD", .12, Callable(), [KEY_A])
	check_result("actual_E_close_releases_modal_focus_movement_and_CD", not sharan.capture_state().dialog_open
		and not main.player.ui_input_blocked and before_walk.x-point(main).x > 5.0
		and skill.cooldown_remaining < clock-.04 and not skill.capture_state().frozen
		and main.get_viewport().gui_get_focus_owner() == null)
	var before_full: Dictionary = snapshot_meta(tree)
	var absent_sessions: bool = ["route_hero_hp", "first_encounter_state", "tower_boss_state"].all(func(key): return not tree.has_meta(key))
	var profile_before: Dictionary = snapshot_fields(progress, PROFILE_FIELDS)
	var files_before: Dictionary = file_guard(qa_path)
	helper.tap(KEY_E)
	await wait_for(tree, "full_HP_dialog_before_Enter", .03)
	helper.tap(KEY_ENTER)
	await wait_for(tree, "full_HP_Enter_closes", .03)
	check_result("full_HP_Enter_does_not_create_shared_or_absent_encounter_meta_or_write_profile", absent_sessions and snapshot_meta(tree) == before_full
		and snapshot_fields(progress, PROFILE_FIELDS) == profile_before and file_guard(qa_path) == files_before
		and sharan.restore_count == restores_before and not sharan.capture_state().dialog_open and not main.player.ui_input_blocked)
	# Only starting health/encounter records are fixtures. Healing uses actual E/Enter.
	var first: Dictionary = {"schema": 1, "player_hp": 27, "enemy_hp": 37, "cleared": false,
		"enemy_position": Vector2(611, 307), "event_counters": {"hero_hits": 3, "enemy_hits": 2, "resets": 1}}
	var boss: Dictionary = {"schema": 1, "player_hp": 13, "enemy_hp": 173, "cleared": false,
		"enemy_position": Vector2(657, 306), "event_counters": {"hero_hits": 4, "enemy_hits": 3, "normal_attacks": 2}}
	tree.set_meta("route_hero_hp", 27)
	tree.set_meta("first_encounter_state", first)
	tree.set_meta("tower_boss_state", boss)
	var expected_first: Dictionary = first.duplicate(true)
	var expected_boss: Dictionary = boss.duplicate(true)
	expected_first.player_hp = 100
	expected_boss.player_hp = 100
	helper.tap(KEY_E)
	await wait_for(tree, "damaged_dialog_before_real_Enter", .04)
	screenshot(tree, "restore")
	helper.tap(KEY_ENTER)
	await wait_for(tree, "actual_Enter_restores_only_route_HP", .04)
	check_result("actual_Enter_heals_only_shared_and_two_existing_player_HP_fields", tree.get_meta("route_hero_hp") == 100
		and tree.get_meta("first_encounter_state") == expected_first and tree.get_meta("tower_boss_state") == expected_boss
		and sharan.restore_count == restores_before+1 and not sharan.capture_state().dialog_open and not main.player.ui_input_blocked
		and snapshot_fields(progress, PROFILE_FIELDS) == profile_before and file_guard(qa_path) == files_before,
		{"fixture_before": {"shared_HP": 27, "first": first, "boss": boss},
		"after": {"first": tree.get_meta("first_encounter_state"), "boss": tree.get_meta("tower_boss_state")}, "profile_unchanged": snapshot_fields(progress, PROFILE_FIELDS) == profile_before})
	var healed: Dictionary = snapshot_meta(tree)
	helper.tap(KEY_E)
	await wait_for(tree, "repeat_full_HP_E", .03)
	helper.tap(KEY_ENTER)
	await wait_for(tree, "repeat_full_HP_Enter", .03)
	check_result("repeat_rest_at_full_HP_changes_no_meta_rewards_inventory_equipment_or_save_files", snapshot_meta(tree) == healed
		and sharan.restore_count == restores_before+1 and snapshot_fields(progress, PROFILE_FIELDS) == profile_before
		and file_guard(qa_path) == files_before and int(progress.progress.coins) == 0)


func story_checks(tree: SceneTree, progress: Node) -> void:
	var sharan: Node = tree.current_scene.get_node("SharanInteraction")
	var original: Dictionary = snapshot_fields(progress, PROFILE_FIELDS)
	var files_before: Dictionary = file_guard(qa_path)
	var processing: bool = progress.is_processing()
	progress.set_process(false)
	var stories: Array = []
	for key: String in ["available", "exploring", "first_clear", "lakius_cleared"]:
		var staged: Dictionary = progress._default_progress()
		if key == "exploring":
			staged.quest_stage = "active"
		elif key in ["first_clear", "lakius_cleared"]:
			staged.quest_stage = "return"
			staged.objective_cleared = true
			staged.first_drop.state = "pending"
			if key == "lakius_cleared":
				staged.chapter_flags.lakius_cleared = true
		progress.progress = staged # Explicit story fixture; never committed to any file.
		helper.tap(KEY_E)
		await wait_for(tree, "story_fixture_"+key, .03)
		stories.append({"expected": key, "actual": sharan.dialogue_key(), "open": sharan.capture_state().dialog_open,
			"body": sharan._body.text, "expected_body": sharan.data.dialogues[key]})
		if key == "lakius_cleared":
			screenshot(tree, "chapter_story")
		helper.tap(KEY_ESCAPE)
	restore_fields(progress, original)
	progress.set_process(processing)
	check_result("four_explicit_story_fixtures_select_visible_stage_text_without_commits", stories.size() == 4
		and stories.all(func(story): return story.open and story.expected == story.actual and story.body == story.expected_body)
		and snapshot_fields(progress, PROFILE_FIELDS) == original and file_guard(qa_path) == files_before,
		{"stories": stories, "fixture": "Only temporary in-memory profile dictionaries; processing disabled and original pending state restored."})


func region_checks(tree: SceneTree, progress: Node) -> void:
	# Direct area loads are fixtures to exercise the two real encounter readers.
	var changed_hall: Error = tree.change_scene_to_file(HALL)
	var hall_ready: Dictionary = await wait_for(tree, "fixture_hall_load_after_rest", 2.5, ready_scene(HALL))
	var hall: Dictionary = {}
	if hall_ready.reached:
		var encounter: Node = tree.current_scene.get_node("FirstEncounter")
		encounter.qa_freeze_enemy = true
		hall = encounter.capture_state()
	var changed_depths: Error = tree.change_scene_to_file(DEPTHS)
	var boss_ready: Dictionary = await wait_for(tree, "fixture_depths_load_after_rest", 2.5, ready_scene(DEPTHS))
	var boss: Dictionary = {}
	if boss_ready.reached:
		var encounter: Node = tree.current_scene.get_node("TowerBoss")
		encounter.qa_freeze_enemy = true
		boss = encounter.capture_state()
	check_result("both_actual_encounter_readers_load_100_hero_HP_and_keep_37_173_enemy_HP", changed_hall == OK and changed_depths == OK
		and hall_ready.reached and boss_ready.reached and hall.get("player_hp", -1) == 100 and boss.get("player_hp", -1) == 100
		and hall.get("enemy_hp", -1) == 37 and boss.get("enemy_hp", -1) == 173 and not hall.get("cleared", true) and not boss.get("cleared", true),
		{"hall": hall, "boss": boss, "fixture": "Scene loads and frozen AI; no new encounter reset, HP write or combat victory."})
	tree.change_scene_to_file(HARBOR)
	var harbor: Dictionary = await wait_for(tree, "return_harbor_before_F4", 2.5, ready_scene(HARBOR))
	if not harbor.reached:
		check_result("R0_has_no_Sharan_dialog", false, harbor)
		return
	helper.tap(KEY_F4)
	var raw: Dictionary = await wait_for(tree, "actual_F4_no_Sharan_in_R0", 2.5, ready_scene(RAW))
	helper.tap(KEY_E)
	await wait_for(tree, "actual_E_in_R0_has_no_dialog", .03)
	var absent: bool = raw.reached and tree.current_scene.get_node_or_null("SharanInteraction") == null \
		and tree.root.find_children("SharanDialog", "CanvasLayer", true, false).is_empty() \
		and not progress.capture_state().dialog_open and not tree.current_scene.player.ui_input_blocked
	helper.tap(KEY_F4)
	var back: Dictionary = await wait_for(tree, "actual_F4_returns_Sharan_R1", 2.5, ready_scene(HARBOR))
	check_result("R0_has_no_interaction_and_F4_returns_one_closed_Sharan", absent and back.reached
		and tree.current_scene.get_node("SharanInteraction").capture_state().dialog_open == false
		and tree.current_scene.find_children("SharanInteraction", "Node", true, false).size() == 1,
		{"R0_absent": absent, "return": back})


func run(root: Node, candidate: String = "R4/03") -> Dictionary:
	var tree: SceneTree = root.get_tree()
	started_usec = Time.get_ticks_usec()
	output_prefix = candidate.to_lower().replace("/", "_")
	helper = Inputs.new()
	helper.started_usec = started_usec
	var main: Node = tree.current_scene
	var progress: Node = tree.root.get_node_or_null("AdventureProgress")
	skill = tree.root.get_node_or_null("SourceSkillRuntime")
	if main == null or main.scene_file_path != HARBOR or progress == null or skill == null or main.get_node_or_null("SharanInteraction") == null:
		check_result("integrated_harbor_Sharan_profile_skill_available", false)
		return {"checks": checks.size(), "failed": checks, "render_cases": render_cases.size()}
	var formal_before: Dictionary = helper.profile_guard()
	var original_meta: Dictionary = snapshot_meta(tree)
	var original_profile: Dictionary = snapshot_fields(progress, PROFILE_FIELDS)
	var original_skill: Dictionary = snapshot_fields(skill, SKILL_FIELDS)
	var original_process: bool = progress.is_processing()
	var original_skill_process: bool = skill.is_processing()
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
	qa_path = "user://qa/sharan_live_"+str(Time.get_ticks_usec())+"_"+str(Time.get_unix_time_from_system()).replace(".", "_")+".json"
	var configured: bool = progress.configure_storage(qa_path, false)
	for key: String in ["route_hero_hp", "tower_boss_state", "first_encounter_state"]:
		if tree.has_meta(key):
			tree.remove_meta(key)
	progress.set_process(true)
	skill.set_process(true)
	main._set_paused(false)
	main.player.ui_input_blocked = false
	main.player.free_control()
	main.get_node("Interface").visible = true
	if main.player.markers_visible:
		main._toggle_markers()
	main.get_viewport().gui_release_focus()
	helper.tap(KEY_R)
	await wait_for(tree, "actual_R_before_Sharan_QA", .04)
	helper.tap(KEY_E)
	check_result("unique_QA_profile_formal_guard_and_actual_far_E_rejection", configured and progress.storage_path == qa_path
		and not FileAccess.file_exists(qa_path) and helper.profile_guard() == formal_before
		and not main.get_node("SharanInteraction").capture_state().dialog_open and not progress.capture_state().dialog_open)
	if configured:
		asset_checks(main)
		if await entry_checks(tree, progress):
			await dialog_and_health(tree, progress)
			await story_checks(tree, progress)
			await region_checks(tree, progress)
	# Exit old fight before restoring meta, then restore pending profile and exact CD.
	helper.release_motion()
	progress.set_process(false)
	skill.set_process(false)
	progress.close_dialog()
	main = tree.current_scene
	if main != null:
		var sharan: Node = main.get_node_or_null("SharanInteraction")
		if sharan != null:
			sharan.close_dialog()
		var loot: Node = main.get_node_or_null("FirstLoot")
		if loot != null:
			loot.close_bag()
		for name: String in ["FirstEncounter", "TowerBoss"]:
			var encounter: Node = main.get_node_or_null(name)
			if encounter != null:
				encounter.qa_freeze_enemy = true
	for popup: Node in tree.root.find_children("*", "PopupMenu", true, false):
		if popup.visible:
			popup.hide()
	var changed: Error = tree.change_scene_to_file(HARBOR)
	var cleanup: Dictionary = await wait_for(tree, "cleanup_fresh_harbor", 2.5, ready_scene(HARBOR))
	restore_fields(progress, original_profile)
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
		main.get_node("SharanInteraction").restore_count = original_restore_count
		skill.attach_area(main)
	restore_fields(skill, original_skill)
	skill._refresh_hud()
	progress.set_process(original_process)
	skill.set_process(original_skill_process)
	check_result("cleanup_restores_original_pending_profile_meta_actor_preferences_and_CD_counters", cleanup.reached
		and snapshot_fields(progress, PROFILE_FIELDS) == original_profile and snapshot_fields(skill, SKILL_FIELDS) == original_skill
		and snapshot_meta(tree) == original_meta and main.player.capture_state() == original_actor
		and main.player.spawn_position == original_spawn and main.player.ui_input_blocked == original_blocked
		and preferences.settings(main) == original_preferences and skill.main == main,
		{"cleanup": cleanup})
	var formal_after: Dictionary = helper.profile_guard()
	check_result("formal_primary_backup_and_both_temporary_files_are_byte_unchanged", formal_before == formal_after,
		{"before": formal_before, "after": formal_after})
	var failed: Array = checks.filter(func(c): return not c.pass)
	var report: Dictionary = {"candidate": candidate, "checks": checks, "failed": failed, "records": records, "screenshots": screenshots,
		"duration_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0, "QA_storage_path": qa_path,
		"formal_profile_before": formal_before, "formal_profile_after": formal_after,
		"qa_source_sha256": get_script().source_code.sha256_text(),
		"interaction_source_sha256": FileAccess.get_file_as_string("res://scripts/sharan_interaction.gd").sha256_text(),
		"dialogue_sha256": FileAccess.get_file_as_string("res://data/sharan_dialogue.json").sha256_text(),
		"note": "Actual W/A/E/Enter/Esc and native menu/pause/jump input prove interaction. Initial wounded hero/enemy session records, cooldown4 and four temporary story dictionaries are explicit fixtures. Direct hall/depths loads exercise real shared-health readers; enemy AI is frozen at arrival, no encounter reset or victory claim. No human profile writes; QA profile/pending transaction, original metadata/actor/preferences/CD counters restore only after combat area exit. All waits bounded."}
	var path: String = "res://docs/"+output_prefix+"_sharan_checks.json"
	var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "  "))
		output.close()
	return {"checks": checks.size(), "failed": failed, "render_cases": render_cases.size(), "recorded_rows": records.size(), "report": path}
