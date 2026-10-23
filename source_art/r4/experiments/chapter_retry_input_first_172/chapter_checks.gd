extends "res://tools/r4/upper_checks.gd"
## R4/10 chapter persistence. Only the parent dispatches this finite persistent native job.

var storage_paths: Array[String] = []
var owned_tmp_path: String = ""


func observe(tree: SceneTree, label: String) -> Dictionary:
	var row: Dictionary = super.observe(tree,label)
	if not row.is_empty():
		row["profile"] = tree.root.get_node("AdventureProgress").capture_state()
	return row


func screenshot(tree: SceneTree, name: String) -> void:
	var path: String = "res://docs/previews/"+output_prefix+"_chapter_"+name+".png"
	screenshots[name] = {"path":path,"save_error":tree.current_scene.get_viewport().get_texture().get_image().save_png(path),"scene":tree.current_scene.scene_file_path}


func saved_equals(progress: Node, expected: Dictionary) -> bool:
	return same_value(JSON.parse_string(FileAccess.get_file_as_string(progress.storage_path)),expected)


func same_value(actual: Variant, expected: Variant) -> bool:
	# Full recursive key/array/type validation, allowing exact finite JSON
	# float/int numeric equality without losing bool or presence semantics.
	return Supplies.new().exact_saved_value(actual,expected)


func block_tmp() -> bool:
	if not qa_path.begins_with("user://qa/chapter_live_"):
		return false
	var path: String = ProjectSettings.globalize_path(qa_path+".tmp")
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		return false
	if DirAccess.make_dir_absolute(path) != OK:
		return false
	owned_tmp_path = path
	return true


func unblock_tmp() -> void:
	if not owned_tmp_path.is_empty():
		DirAccess.remove_absolute(owned_tmp_path)
		owned_tmp_path = ""


func controlled_win(tree: SceneTree, progress: Node, area: String, label: String) -> Dictionary:
	if progress.storage_path != qa_path or not qa_path.begins_with("user://qa/chapter_live_"):
		check_result(label+"_lethal_requires_isolated_QA_storage",false,{"path":progress.storage_path})
		return {"won":false}
	if tree.current_scene.scene_file_path != area and not await load_area(tree,area,label+"_arena_entry_fixture"):
		check_result(label+"_arena_available",false)
		return {"won":false}
	var fight: Node = await prepare_ordinary(tree,90)
	var start_hp: int = fight.enemy_hp
	var before: Dictionary = fight.capture_state()
	var inputs: Array = []
	for attempt: int in 5:
		if fight.cleared:
			break
		if progress.storage_path != qa_path:
			check_result(label+"_lethal_requires_same_QA_path",false)
			return {"won":false}
		helper.tap(KEY_Q)
		await wait_for(tree,label+"_actual_Q_full_source_window",1.6,
			func(m:Node,row:Dictionary):return row.fight.cleared or not m.player._one_shot)
		inputs.append(fight.capture_state())
	var result: Dictionary = {"won":fight.cleared and fight.enemy_hp == 0 and fight.player_hp == 100,"initial_HP":start_hp,
		"before":before,"actual_Q_inputs":inputs,"after":fight.capture_state(),"profile":progress.capture_state(),
		"fixture":"Direct arena entry,90px positions, stopped enemy AI and awake Statue only. HP is authored full100/140 from ordinary R; every damaging input is realQ with unchanged source clocks."}
	return result


func chapter_metas(tree: SceneTree) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["first_encounter_state","tower_boss_state","doll_gallery_state","statue_gallery_state"]:
		result[key] = meta_snapshot(tree,key)
	return result


func restore_chapter_metas(tree: SceneTree, snapshot: Dictionary) -> void:
	for key: String in snapshot:
		if snapshot[key].present:
			tree.set_meta(key,snapshot[key].value)
		elif tree.has_meta(key):
			tree.remove_meta(key)


func harbor_ready(tree: SceneTree, label: String) -> bool:
	if tree.current_scene.scene_file_path != HARBOR and not await load_area(tree,HARBOR,label+"_harbor_entry_fixture"):
		return false
	var ready: Dictionary = await wait_for(tree,label+"_Sharan_attached",.5,
		func(m:Node,_row:Dictionary):return m.get_node_or_null("SharanInteraction") != null)
	return ready.reached


func success_and_history_checks(tree: SceneTree, progress: Node) -> void:
	var baseline: Dictionary = progress.progress.duplicate(true)
	var baseline_saved: bool = progress._commit(baseline.duplicate(true))
	check_result("schema6_QA_baseline_has_exact_three_false_chapter_flags_and_full_disk_roundtrip",baseline_saved and saved_equals(progress,baseline)
		and baseline.chapter_flags == {"lakius_cleared":false,"stonemaster_cleared":false,"statue_cleared":false})
	var attempts: int = progress._save_attempts
	var gallery: Dictionary = await controlled_win(tree,progress,GALLERY,"chapter_gallery")
	var expected: Dictionary = baseline.duplicate(true)
	expected.chapter_flags.stonemaster_cleared = true
	check_result("actual_Q_defeats_authored100HP_gallery_and_callback_saves_only_stonemaster_history",gallery.won and gallery.initial_HP == 100
		and same_value(progress.progress,expected) and saved_equals(progress,expected) and progress._save_attempts == attempts+1
		and not progress._chapter_receipts.stonemaster_cleared and not progress._chapter_attempt_due,{"combat":gallery})
	screenshot(tree,"gallery_receipt_saved")
	var files: Dictionary = states.file_guard(qa_path)
	attempts = progress._save_attempts
	var duplicate_ok: bool = progress.record_chapter_clear("stonemaster_cleared") and progress.record_chapter_clear("stonemaster_cleared")
	await actual_reset(tree,"gallery_practice_after_history")
	check_result("duplicate_gallery_receipt_and_actual_R_do_not_write_reward_or_erase_durable_history",duplicate_ok and not fight_at(tree.current_scene).cleared
		and same_value(progress.progress,expected) and progress._save_attempts == attempts and states.file_guard(qa_path) == files
		and tree.current_scene.get_node("WorldTravel").capture_state().statue_gallery_unlocked)
	stage_actor(tree.current_scene.player,Vector2(840,320),1)
	var entered: Dictionary = await wait_for(tree,"actual_D_held_historical_portal_after_R",2.5,ready_scene(STATUE),[KEY_D])
	check_result("committed_gallery_history_keeps_actual_right_portal_open_after_local_R",entered.reached
		and tree.current_scene.scene_file_path == STATUE and point(tree.current_scene).distance_to(Vector2(176,320)) < 5,
		{"route":entered,"fixture":"Only initial portal approach position840,320 is staged; realD and150ms gate/fades perform travel."})
	if not entered.reached:
		return
	attempts = progress._save_attempts
	var statue: Dictionary = await controlled_win(tree,progress,STATUE,"chapter_statue")
	expected.chapter_flags.statue_cleared = true
	check_result("actual_Q_defeats_authored140HP_statue_and_callback_saves_only_second_chapter_flag",statue.won and statue.initial_HP == 140
		and same_value(progress.progress,expected) and saved_equals(progress,expected) and progress._save_attempts == attempts+1
		and progress._chapter_receipts == {"stonemaster_cleared":false,"statue_cleared":false} and not progress._chapter_attempt_due,{"combat":statue})
	screenshot(tree,"statue_receipt_saved")
	files = states.file_guard(qa_path)
	attempts = progress._save_attempts
	duplicate_ok = progress.record_chapter_clear("statue_cleared") and progress.record_chapter_clear("statue_cleared")
	await actual_reset(tree,"statue_practice_after_history")
	var fight: Node = fight_at(tree.current_scene)
	check_result("duplicate_statue_receipt_and_actual_R_reset_local_fight_without_new_reward_or_history_write",duplicate_ok
		and not fight.cleared and not fight.awakened and fight.enemy_hp == 140 and fight.player_hp == 100
		and same_value(progress.progress,expected) and progress._save_attempts == attempts and states.file_guard(qa_path) == files)
	if not await harbor_ready(tree,"chapter_reload"):
		check_result("harbor_available_for_QA_only_disk_reload",false)
		return
	for key: String in ["doll_gallery_state","statue_gallery_state"]:
		if tree.has_meta(key):
			tree.remove_meta(key)
	var reloaded: bool = progress.configure_storage(qa_path,true)
	check_result("same_QA_disk_reload_recovers_both_chapters_and_seeds_absent_session_receipts_without_writes",reloaded
		and same_value(progress.progress,expected) and saved_equals(progress,expected) and progress._save_attempts == 0
		and meta_snapshot(tree,"doll_gallery_state").value is Dictionary and meta_snapshot(tree,"doll_gallery_state").value.get("cleared") == true
		and meta_snapshot(tree,"statue_gallery_state").value is Dictionary and meta_snapshot(tree,"statue_gallery_state").value.get("cleared") == true
		and not progress._chapter_attempt_due and progress._pending_bundle.is_empty(),
		{"simulation":"Explicit same-QA disk reload and fresh session nodes; this is not an operating-system process restart."})
	var loaded: bool = await load_area(tree,GALLERY,"fresh_gallery_after_QA_reload")
	if not loaded:
		check_result("fresh_gallery_available_after_QA_reload",false)
		return
	var seeded_clear: bool = loaded and fight_at(tree.current_scene).cleared
	await actual_reset(tree,"fresh_gallery_R_after_disk_reload")
	check_result("fresh_gallery_reads_saved_clear_then_R_restores_enemy_and_retains_historical_next_gate",seeded_clear
		and not fight_at(tree.current_scene).cleared and fight_at(tree.current_scene).enemy_hp == 100
		and tree.current_scene.get_node("WorldTravel").capture_state().statue_gallery_unlocked
		and progress.chapter_cleared("stonemaster_cleared",false) and progress.chapter_cleared("statue_cleared",false)
		and progress._save_attempts == 0 and same_value(progress.progress,expected))


func sharan_and_strict_checks(tree: SceneTree, progress: Node) -> void:
	if not await harbor_ready(tree,"chapter_Sharan"):
		check_result("harbor_Sharan_available",false)
		return
	var main: Node = tree.current_scene
	var sharan: Node = main.get_node("SharanInteraction")
	# Explicit health/session fixtures exercise preservation, never defeat or progression.
	for key: String in ["first_encounter_state","tower_boss_state"]:
		if not tree.has_meta(key):
			tree.set_meta(key,{"player_hp":55,"enemy_hp":37 if key == "first_encounter_state" else 173,"cleared":false,
				"enemy_position":[640,300],"event_counters":{"hero_hits":2,"enemy_hits":1}})
	for key: String in chapter_metas(tree):
		var snapshot: Dictionary = meta_snapshot(tree,key)
		if snapshot.present and snapshot.value is Dictionary:
			var value: Dictionary = snapshot.value.duplicate(true)
			value.player_hp = 55
			tree.set_meta(key,value)
	tree.set_meta("route_hero_hp",55)
	stage_actor(main.player,Vector2(190,310),-1)
	skill.cooldown_remaining = 2
	potion.cooldown_remaining = 3
	guard.cooldown_remaining = 1
	upper.cooldown_remaining = 1.5
	var profile_before: Dictionary = states.snapshot_fields(progress,States.PROFILE_FIELDS)
	var metas_before: Dictionary = chapter_metas(tree)
	var files: Dictionary = states.file_guard(qa_path)
	var restores: int = sharan.restore_count
	helper.tap(KEY_E)
	await wait_for(tree,"actual_Sharan_E_opens_latest_story",.04)
	var position: Vector2 = point(main)
	var clocks: Array = [guard.cooldown_remaining,skill.cooldown_remaining,potion.cooldown_remaining,upper.cooldown_remaining]
	var serials: Array = [guard.accepted_begins,skill.accepted_casts,potion.accepted_uses,upper.accepted_casts]
	for code: Key in [KEY_X,KEY_Q,KEY_SPACE,KEY_B,KEY_Z,KEY_V,KEY_H,KEY_C]:
		helper.tap(code)
	await wait_for(tree,"chapter_dialog_blocks_actual_actions_and_freezes_all_four_CDs",.13,Callable(),[KEY_A,KEY_W])
	check_result("actual_E_Sharan_latest_chapter_dialog_blocks_movement_combat_bag_jump_and_freezes_four_CDs",sharan.capture_state().dialog_open
		and sharan.dialogue_key() == "statue_cleared" and point(main).distance_to(position) < .01
		and not main.player._one_shot and not main.player.jump_motion.is_active() and not main.get_node("FirstLoot").capture_state().bag_open
		and clocks == [guard.cooldown_remaining,skill.cooldown_remaining,potion.cooldown_remaining,upper.cooldown_remaining]
		and serials == [guard.accepted_begins,skill.accepted_casts,potion.accepted_uses,upper.accepted_casts])
	screenshot(tree,"latest_chapter_rest_dialog")
	helper.tap(KEY_ENTER)
	await wait_for(tree,"actual_Enter_free_rest",.04)
	var expected_metas: Dictionary = metas_before.duplicate(true)
	for key: String in expected_metas:
		if expected_metas[key].present and expected_metas[key].value is Dictionary:
			expected_metas[key].value.player_hp = 100
	check_result("actual_Enter_free_rest_only_heals_shared_and_existing_fight_player_HP_preserving_enemies_receipts_and_profile",not sharan.capture_state().dialog_open
		and sharan.restore_count == restores+1 and tree.get_meta("route_hero_hp") == 100 and chapter_metas(tree) == expected_metas
		and states.snapshot_fields(progress,States.PROFILE_FIELDS) == profile_before and states.file_guard(qa_path) == files,
		{"health_fixture_before":metas_before,"after":chapter_metas(tree)})
	helper.tap(KEY_E)
	helper.tap(KEY_ENTER)
	await wait_for(tree,"full_health_actual_Enter_closes_without_reward",.04)
	check_result("full_health_repeated_rest_only_closes_without_award_save_or_restore_count",not sharan.capture_state().dialog_open
		and sharan.restore_count == restores+1 and chapter_metas(tree) == expected_metas
		and states.snapshot_fields(progress,States.PROFILE_FIELDS) == profile_before and states.file_guard(qa_path) == files)
	progress.set_process(false)
	var strict_profile: Dictionary = states.snapshot_fields(progress,States.PROFILE_FIELDS)
	var strict_metas: Dictionary = chapter_metas(tree)
	var rows: Array = []
	var fixtures: Array = [
		{"flags":{"lakius_cleared":false,"stonemaster_cleared":false,"statue_cleared":false},"stone":1,"statue":"true","expected":"available"},
		{"flags":{"lakius_cleared":false,"stonemaster_cleared":1,"statue_cleared":"true"},"stone":false,"statue":false,"expected":"available"},
		{"flags":{"lakius_cleared":true,"stonemaster_cleared":true,"statue_cleared":false},"stone":false,"statue":false,"expected":"stonemaster_cleared"},
		{"flags":{"lakius_cleared":true,"stonemaster_cleared":true,"statue_cleared":true},"stone":false,"statue":false,"expected":"statue_cleared"},
		{"flags":{"lakius_cleared":true,"stonemaster_cleared":true,"statue_cleared":false},"stone":false,"statue":true,"expected":"statue_cleared"}]
	for fixture: Dictionary in fixtures:
		progress.progress.chapter_flags = fixture.flags.duplicate(true)
		tree.set_meta("doll_gallery_state",{"cleared":fixture.stone})
		tree.set_meta("statue_gallery_state",{"cleared":fixture.statue})
		helper.tap(KEY_E)
		await wait_for(tree,"process_off_strict_story_fixture",.025)
		var unlocked: bool = tree.current_scene.get_node("WorldTravel").capture_state().statue_gallery_unlocked
		var expected_gate: bool = (fixture.flags.stonemaster_cleared is bool and fixture.flags.stonemaster_cleared == true) or (fixture.stone is bool and fixture.stone == true)
		rows.append({"fixture":fixture,"actual":sharan.dialogue_key(),"gate_unlocked":unlocked,
			"pass":sharan.capture_state().dialog_open and sharan.dialogue_key() == fixture.expected and unlocked == expected_gate})
		helper.tap(KEY_E)
	states.restore_fields(progress,strict_profile)
	restore_chapter_metas(tree,strict_metas)
	progress.set_process(true)
	check_result("strict_bool_live_and_committed_story_receipts_reject_truthy_types_and_prioritize_statue_over_stone_over_lakius",rows.all(func(row:Dictionary):return row.pass)
		and states.file_guard(qa_path) == files and states.snapshot_fields(progress,States.PROFILE_FIELDS) == strict_profile,
		{"rows":rows,"fixture":"Only invalid-type/story fixtures; profile process is disabled throughout and full fields/metas are restored before resuming."})


func pending_receipt_checks(tree: SceneTree, progress: Node) -> void:
	if not await harbor_ready(tree,"pending_chapter"):
		check_result("harbor_available_for_pending_chapter_flow",false)
		return
	progress.set_process(false)
	qa_path = "user://qa/chapter_live_pending_"+str(Time.get_ticks_usec())+".json"
	storage_paths.append(qa_path)
	for key: String in ["first_encounter_state","tower_boss_state","doll_gallery_state","statue_gallery_state"]:
		if tree.has_meta(key):
			tree.remove_meta(key)
	tree.set_meta("route_hero_hp",100)
	var configured: bool = progress.configure_storage(qa_path,false)
	var baseline: Dictionary = progress.progress.duplicate(true)
	var baseline_saved: bool = configured and progress._commit(baseline.duplicate(true))
	var files: Dictionary = states.file_guard(qa_path)
	progress.set_process(true)
	var blocked: bool = baseline_saved and block_tmp()
	if not blocked:
		check_result("owned_unique_QA_tmp_directory_available_for_bounded_failure_probe",false,{"path":qa_path})
		return
	stage_actor(tree.current_scene.player,Vector2(320,310),1)
	helper.tap(KEY_E)
	await wait_for(tree,"actual_Lorian_E_before_failed_accept",.035)
	helper.tap(KEY_ENTER)
	await wait_for(tree,"actual_Enter_accept_storage_failure",.035)
	var pending_a: Dictionary = progress._pending_bundle.duplicate(true)
	var expected_a: Dictionary = baseline.duplicate(true)
	expected_a.quest_stage = "active"
	var attempts: int = progress._save_attempts
	check_result("actual_Lorian_E_Enter_failure_retains_exact_quest_transaction_A_and_original_full_disk_state",progress.capture_state().dialog_open
		and not progress.last_error.is_empty() and same_value(pending_a,expected_a) and same_value(progress.progress,baseline)
		and saved_equals(progress,baseline) and states.file_guard(qa_path) == files,
		{"pending_A":pending_a,"owned_failure_path":owned_tmp_path})
	progress.close_dialog()
	var gallery: Dictionary = await controlled_win(tree,progress,GALLERY,"pending_gallery")
	await actual_reset(tree,"pending_gallery_R_keeps_verified_receipt")
	check_result("actual_gallery_win_then_R_preserves_verified_RAM_receipt_without_merging_or_retrying_old_pending_A",gallery.won
		and not fight_at(tree.current_scene).cleared and progress._chapter_receipts.stonemaster_cleared
		and progress.chapter_cleared("stonemaster_cleared") and not progress.chapter_cleared("stonemaster_cleared",false)
		and not tree.current_scene.get_node("WorldTravel").capture_state().statue_gallery_unlocked
		and progress._pending_bundle == pending_a and same_value(progress.progress,baseline) and progress._save_attempts == attempts
		and states.file_guard(qa_path) == files,{"combat":gallery,"profile":progress.capture_state()})
	var statue: Dictionary = await controlled_win(tree,progress,STATUE,"pending_statue")
	await actual_reset(tree,"pending_statue_R_keeps_both_verified_receipts")
	check_result("actual_statue_win_then_R_preserves_both_verified_receipts_and_old_pending_A_byte_exact",statue.won
		and not fight_at(tree.current_scene).cleared and progress._chapter_receipts == {"stonemaster_cleared":true,"statue_cleared":true}
		and progress._chapter_attempt_due and progress._pending_bundle == pending_a and same_value(progress.progress,baseline)
		and progress._save_attempts == attempts and states.file_guard(qa_path) == files,{"combat":statue,"profile":progress.capture_state()})
	if not await harbor_ready(tree,"pending_RAM_only_story"):
		check_result("pending_flow_returns_to_harbor",false)
		return
	stage_actor(tree.current_scene.player,Vector2(190,310),-1)
	helper.tap(KEY_E)
	await wait_for(tree,"RAM_only_receipts_do_not_replace_durable_story",.15)
	var sharan: Node = tree.current_scene.get_node("SharanInteraction")
	check_result("failed_save_then_R_RAM_only_history_does_not_open_historical_story_or_auto_retry",sharan.capture_state().dialog_open
		and sharan.dialogue_key() == "available" and progress._pending_bundle == pending_a
		and progress._save_attempts == attempts and states.file_guard(qa_path) == files,
		{"profile":progress.capture_state(),"approved_contract":"Story and portal use strict liveclear or committedflags; RAM is only a loss-prevention receipt."})
	helper.tap(KEY_E)
	unblock_tmp()
	stage_actor(tree.current_scene.player,Vector2(320,310),1)
	helper.tap(KEY_E)
	await wait_for(tree,"actual_Lorian_E_for_manual_retry",.035)
	helper.tap(KEY_ENTER)
	# No await before this capture: actual Enter synchronously commits A. B is
	# intentionally deferred until the controller's following process callback.
	var exact_a: Dictionary = progress.capture_state()
	check_result("actual_Lorian_Enter_retry_first_commits_only_exact_A_before_next_process_receipt_B",same_value(progress.progress,pending_a)
		and saved_equals(progress,pending_a) and progress._pending_bundle.is_empty() and progress._chapter_attempt_due
		and progress._chapter_receipts == {"stonemaster_cleared":true,"statue_cleared":true} and progress._save_attempts == attempts+1,
		{"immediate_after_actual_Enter":exact_a})
	var expected_b: Dictionary = pending_a.duplicate(true)
	expected_b.chapter_flags.stonemaster_cleared = true
	expected_b.chapter_flags.statue_cleared = true
	var flushed: Dictionary = await wait_for(tree,"one_next_process_commits_verified_chapter_receipt_B",.6,
		func(_m:Node,_row:Dictionary):return same_value(progress.progress,expected_b) and progress._pending_bundle.is_empty())
	await wait_for(tree,"successful_B_does_not_auto_repeat",.13)
	check_result("next_process_commits_B_with_both_chapters_once_without_reward_or_transaction_A_mutation",flushed.reached
		and same_value(progress.progress,expected_b) and saved_equals(progress,expected_b) and progress._save_attempts == attempts+2
		and progress._chapter_receipts == {"stonemaster_cleared":false,"statue_cleared":false} and not progress._chapter_attempt_due,
		{"after":progress.capture_state(),"exact_A":pending_a,"expected_B":expected_b})
	progress.close_dialog()
	stage_actor(tree.current_scene.player,Vector2(190,310),-1)
	helper.tap(KEY_E)
	await wait_for(tree,"durable_retry_updates_Sharan_story",.035)
	var durable_files: Dictionary = states.file_guard(qa_path)
	var duplicate_ok: bool = progress.record_chapter_clear("stonemaster_cleared") and progress.record_chapter_clear("statue_cleared")
	check_result("durable_retry_updates_latest_story_and_gate_while_duplicate_records_remain_write_free",duplicate_ok
		and sharan.capture_state().dialog_open and sharan.dialogue_key() == "statue_cleared"
		and tree.current_scene.get_node("WorldTravel").capture_state().statue_gallery_unlocked
		and progress._save_attempts == attempts+2 and states.file_guard(qa_path) == durable_files)
	screenshot(tree,"manual_retry_both_chapters_durable")
	helper.tap(KEY_E)


func run(root: Node, candidate: String = "R4/10") -> Dictionary:
	var tree: SceneTree = root.get_tree()
	started_usec = Time.get_ticks_usec()
	output_prefix = candidate.to_lower().replace("/","_")
	helper = Inputs.new()
	helper.started_usec = started_usec
	states = States.new()
	var main: Node = tree.current_scene
	var progress: Node = tree.root.get_node_or_null("AdventureProgress")
	guard = tree.root.get_node_or_null("GuardRuntime")
	skill = tree.root.get_node_or_null("SourceSkillRuntime")
	potion = tree.root.get_node_or_null("HpPotionRuntime")
	upper = tree.root.get_node_or_null("UpperSlashRuntime")
	if main == null or main.scene_file_path != HARBOR or progress == null or guard == null or skill == null or potion == null or upper == null or guard.capture_state().active or int(progress.progress.get("schema",0)) != 6 or progress.get("_dialog_open") == true:
		check_result("fresh_integrated_harbor_with_inactive_guard_available",false)
		return {"checks":checks.size(),"failed":checks,"render_cases":render_cases.size()}
	var formal_before: Dictionary = helper.profile_guard()
	var original_meta: Dictionary = states.snapshot_meta(tree)
	var gallery_present: bool = tree.has_meta("doll_gallery_state")
	var gallery_meta: Variant = tree.get_meta("doll_gallery_state") if gallery_present else null
	if gallery_meta is Dictionary:
		gallery_meta = gallery_meta.duplicate(true)
	var statue_before: Dictionary = meta_snapshot(tree,"statue_gallery_state")
	var original_profile: Dictionary = states.snapshot_fields(progress,States.PROFILE_FIELDS)
	var original_guard: Dictionary = states.snapshot_fields(guard,Guards.GUARD_FIELDS)
	var original_skill: Dictionary = states.snapshot_fields(skill,States.SKILL_FIELDS)
	var original_potion: Dictionary = states.snapshot_fields(potion,Supplies.POTION_FIELDS)
	var original_upper: Dictionary = states.snapshot_fields(upper,States.SKILL_FIELDS)
	var upper_processing: bool = upper.is_processing()
	var process_before: Array[bool] = [progress.is_processing(),guard.is_processing(),guard.is_physics_processing(),skill.is_processing(),potion.is_processing()]
	var original_actor: Dictionary = main.player.capture_state()
	var original_spawn: Vector2 = main.player.spawn_position
	var original_blocked: bool = main.player.ui_input_blocked
	var original_offset: Vector2 = Vector2(main.framing.offset_x,main.framing.offset_y)
	var original_interface: bool = main.get_node("Interface").visible
	var original_markers: bool = main.player.markers_visible
	var original_restore_count: int = main.get_node("SharanInteraction").restore_count
	var preferences: RefCounted = Preferences.new()
	var original_preferences: Dictionary = preferences.settings(main)
	# Exercise actual contact playback, even when the user's original effects preference was muted.
	tree.set_meta("port_audio_muted",false)
	tree.set_meta("port_audio_volume",.3)
	main.player.action_audio.apply_preferences()
	progress.set_process(false)
	qa_path = "user://qa/chapter_live_"+str(Time.get_ticks_usec())+"_"+str(Time.get_unix_time_from_system()).replace(".","_")+".json"
	var configured: bool = progress.configure_storage(qa_path,false)
	for key: String in ["first_encounter_state","tower_boss_state","doll_gallery_state","statue_gallery_state"]:
		if tree.has_meta(key):
			tree.remove_meta(key)
	tree.set_meta("route_hero_hp",100)
	guard.set_process(true)
	guard.set_physics_process(true)
	skill.set_process(true)
	potion.set_process(true)
	upper.set_process(true)
	main._set_paused(false)
	main.player.ui_input_blocked = false
	main.player.free_control()
	main.get_node("Interface").visible = true
	if main.player.markers_visible:
		main._toggle_markers()
	main.get_viewport().gui_release_focus()
	helper.key(KEY_C,false)
	check_result("unique_default_available_QA_profile_isolated_before_any_route_interaction",configured and progress.storage_path == qa_path \
		and progress.progress.quest_stage == "available" and progress.progress.coins == 0 and progress._pending_bundle.is_empty() \
		and helper.profile_guard() == formal_before,{"QA_path":qa_path})
	if configured:
		progress.set_process(true)
		storage_paths.append(qa_path)
		await success_and_history_checks(tree,progress)
		await sharan_and_strict_checks(tree,progress)
		await pending_receipt_checks(tree,progress)
	unblock_tmp()
	# Depart the test encounter before restoring metadata: its _exit_tree persists state.
	helper.release_motion()
	for code: Key in [KEY_C,KEY_Z,KEY_H,KEY_V]:
		helper.key(code,false)
	guard.end_guard("qa_cleanup")
	progress.set_process(false)
	guard.set_process(false)
	guard.set_physics_process(false)
	skill.set_process(false)
	potion.set_process(false)
	upper.set_process(false)
	main = tree.current_scene
	if main != null:
		var bag: Node = main.get_node_or_null("FirstLoot")
		if bag != null:
			bag.close_bag()
		var fight: Node = fight_at(main)
		if fight != null:
			fight.qa_freeze_enemy = true
	progress.close_dialog()
	for popup: Node in tree.root.find_children("*","PopupMenu",true,false):
		if popup.visible:
			popup.hide()
	var changed: Error = tree.change_scene_to_file(HARBOR)
	var cleanup: Dictionary = await wait_for(tree,"cleanup_fresh_harbor",2.5,ready_scene(HARBOR))
	states.restore_fields(progress,original_profile)
	states.restore_meta(tree,original_meta)
	if gallery_present:
		tree.set_meta("doll_gallery_state",gallery_meta)
	elif tree.has_meta("doll_gallery_state"):
		tree.remove_meta("doll_gallery_state")
	if statue_before.present:
		tree.set_meta("statue_gallery_state",statue_before.value)
	elif tree.has_meta("statue_gallery_state"):
		tree.remove_meta("statue_gallery_state")
	main = tree.current_scene
	if changed == OK and cleanup.reached:
		progress.progress_changed.emit()
		preferences.apply_settings(main,original_preferences)
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
		upper.attach_area(main)
	states.restore_fields(guard,original_guard)
	states.restore_fields(skill,original_skill)
	states.restore_fields(potion,original_potion)
	states.restore_fields(upper,original_upper)
	guard._refresh_hud()
	skill._refresh_hud()
	potion._refresh_hud()
	upper._refresh_hud()
	progress.set_process(process_before[0])
	guard.set_process(process_before[1])
	guard.set_physics_process(process_before[2])
	skill.set_process(process_before[3])
	potion.set_process(process_before[4])
	upper.set_process(upper_processing)
	var temporary_directories_removed: bool = owned_tmp_path.is_empty()
	for path: String in storage_paths:
		temporary_directories_removed = temporary_directories_removed and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path+".tmp"))
	check_result("cleanup_restores_profile_pending_shared_HP_four_fight_metas_actor_preferences_and_four_runtimes",cleanup.reached and temporary_directories_removed \
		and states.snapshot_fields(progress,States.PROFILE_FIELDS) == original_profile and states.snapshot_meta(tree) == original_meta \
		and meta_snapshot(tree,"doll_gallery_state") == {"present":gallery_present,"value":gallery_meta} \
		and meta_snapshot(tree,"statue_gallery_state") == statue_before \
		and states.snapshot_fields(guard,Guards.GUARD_FIELDS) == original_guard and states.snapshot_fields(skill,States.SKILL_FIELDS) == original_skill \
		and states.snapshot_fields(potion,Supplies.POTION_FIELDS) == original_potion \
		and states.snapshot_fields(upper,States.SKILL_FIELDS) == original_upper and main.player.capture_state() == original_actor \
		and main.player.spawn_position == original_spawn and main.player.ui_input_blocked == original_blocked \
		and preferences.settings(main) == original_preferences and guard.main == main and upper.main == main and not main.player.guard_active,{"cleanup":cleanup})
	var formal_after: Dictionary = helper.profile_guard()
	check_result("formal_primary_backup_and_both_temporary_files_remain_byte_unchanged",formal_before == formal_after,{"before":formal_before,"after":formal_after})
	var failed: Array = checks.filter(func(c:Dictionary):return not c.pass)
	var report: Dictionary = {"candidate":candidate,"checks":checks,"failed":failed,"records":records,"screenshots":screenshots,
		"duration_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,"QA_storage_path":qa_path,
		"formal_profile_before":formal_before,"formal_profile_after":formal_after,"qa_source_sha256":get_script().source_code.sha256_text(),
		"profile_source_sha256":FileAccess.get_file_as_string("res://scripts/adventure_progress.gd").sha256_text(),
		"shared_profile_snapshot_source_sha256":FileAccess.get_file_as_string("res://tools/r4/sharan_checks.gd").sha256_text(),
		"Sharan_source_sha256":FileAccess.get_file_as_string("res://scripts/sharan_interaction.gd").sha256_text(),"storage_paths":storage_paths,
		"note":"Focused schema6 chapter receipt integration, not a duplicate combat or storage-corruption matrix. ActualQ kills start authored100/140HP with unmodified clocks; arena entry/90px spacing/stopped AI and awake Statue are explicit fixtures. Lethal inputs require the active unique QA profile. Successful clears change only chapter flags, not rewards/coins/items/equipment. Old pending quest transaction A remains exact through both real clears and R; verified RAM receipts survive until actualE/Enter retry commits A, then one next-process B commits receipts. RAM alone does not count as durable portal/story history. Restart proof is explicit same-QA disk reload plus fresh scene/session reset. Sharan uses actualE/Enter, freezes modal controls and heals free without profile/RAM/file changes. Strict truthy type/story combinations are temporary process-off fixtures. Only owned unique-QA .tmp directory blocks storage; cleanup removes it before departing combat and restoring original profile including pending/receipts, five HP/session metas, four runtime states and preferences. Human primary/backup/both temporary files remain byte unchanged; all waits bounded."}

	var path: String = "res://docs/"+output_prefix+"_chapter_checks.json"
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report,"  "))
		output.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases.size(),"recorded_rows":records.size(),"report":path}
