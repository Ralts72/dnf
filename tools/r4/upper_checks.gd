extends "res://tools/r4/statue_checks.gd"
## Focused R4/09 live suite. Parent exclusively dispatches this persistent job.

const UPPER_SOURCE: String = "res://docs/r4_upper_slash_source_reference.json"
const HALL: String = "res://scenes/tower_hall.tscn"
const RAW: String = "res://scenes/west_coast_r0.tscn"
var upper: Node


func ready_scene(path: String) -> Callable:
	return func(main:Node,row:Dictionary):return main.scene_file_path == path and guard.main == main and skill.main == main and potion.main == main and upper.main == main \
		and (path == RAW or row.travel.get("phase","") == "ready") \
		and (path == RAW or main.get_node_or_null("FirstLoot") != null) \
		and (path != HALL or main.get_node_or_null("FirstEncounter") != null) \
		and (path != DEPTHS or main.get_node_or_null("TowerBoss") != null) \
		and (path != GALLERY or main.get_node_or_null("GalleryEncounter") != null) \
		and (path != STATUE or main.get_node_or_null("StatueEncounter") != null)


func observe(tree: SceneTree, label: String) -> Dictionary:
	var row: Dictionary = super.observe(tree,label)
	if not row.is_empty():
		row["upper"] = upper.capture_state()
		row["frame_elapsed_ms"] = tree.current_scene.player.elapsed_ms
		row["next_attack"] = tree.current_scene.player.next_attack
		row["jump_height"] = tree.current_scene.player.jump_motion.height_pixels
		var fight: Node = fight_at(tree.current_scene)
		var lift: Node = fight.get_node_or_null("EnemyLaunchMotion") if fight != null else null
		row["launch"] = lift.capture_state() if lift != null else {}
	return row


func screenshot(tree: SceneTree, name: String) -> void:
	var path: String = "res://docs/previews/"+output_prefix+"_upper_"+name+".png"
	screenshots[name] = {"path":path,"save_error":tree.current_scene.get_viewport().get_texture().get_image().save_png(path),"scene":tree.current_scene.scene_file_path}


func asset_checks() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(UPPER_SOURCE))
	var sources_ok: bool = source.source_scripts.size() == 9
	for entry: Dictionary in source.source_scripts:
		sources_ok = sources_ok and entry.crc_matches and FileAccess.get_sha256("res://"+entry.raw_reference) == entry.sha256_decoded
	var objects_ok: bool = source.outputs.size() == 4
	var alias_frames: int = 0
	var old_objects: int = 0
	var manifest_rows: Array = []
	for path: String in source.outputs:
		var entry: Dictionary = source.outputs[path]
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://"+path))
		var parent: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://"+entry.parent))
		if not data.get("animations") is Dictionary or not parent.get("animations") is Dictionary:
			objects_ok = false
			manifest_rows.append({"path":path,"has_animation_objects":false})
			continue
		manifest_rows.append({"path":path,"has_animation_objects":true,"sha256":FileAccess.get_sha256("res://"+path)})
		objects_ok = objects_ok and data.animations.size() == 16 and parent.animations.size() == 15
		for action: String in parent.animations:
			objects_ok = objects_ok and data.animations[action] == parent.animations[action]
			old_objects += 1
		var alias: Dictionary = data.animations.upperslash
		var clock: float = 0
		objects_ok = objects_ok and alias.prototype_alias_of == "attack3" and alias.source_action_key == "attack3" and not alias.original_UpperSlash_dispatch_restored
		for i: int in alias.frames.size():
			var frame: Dictionary = alias.frames[i].duplicate(true)
			objects_ok = objects_ok and frame.source_ani == "character/swordman/animation/attack3.ani"
			frame.erase("source_ani")
			objects_ok = objects_ok and frame == parent.animations.attack3.frames[i]
			clock += float(frame.duration_ms)
			alias_frames += 1
		objects_ok = objects_ok and alias.frames.size() == 9 and clock == 550
	check_result("nine_CRC_sources_four_manifests_keep_all60_old_action_objects_and36_550ms_alias_records_exact",sources_ok and objects_ok and old_objects == 60 and alias_frames == 36,
		{"old_objects":old_objects,"alias_records":alias_frames,"manifests":manifest_rows,"source_alias":source.alias.source_ani,"zero_new_PNGs":source.verification.new_PNGs == 0})
	var images: Array = []
	var native_ok: bool = true
	for group: String in ["existing_source_crops","existing_derived_composites"]:
		for entry: Dictionary in source[group]:
			var raw: Image = raw_png(entry.texture)
			var texture: Texture2D = load(entry.texture)
			var native: Image = texture.get_image() if texture != null else null
			var exact: bool = raw != null and native != null and FileAccess.get_sha256(entry.texture) == entry.sha256_png
			if exact and native.is_compressed():
				exact = native.decompress() == OK
			if exact:
				native.convert(Image.FORMAT_RGBA8)
				exact = raw.get_size() == Vector2i(entry.size[0],entry.size[1]) and native.get_size() == raw.get_size() \
					and native.get_data() == raw.get_data() and states.image_hash(native) == entry.sha256_rgba
			native_ok = native_ok and exact
			images.append({"path":entry.texture,"native_RGBA_exact":exact})
	check_result("all99_existing_source_crops_and18_existing_composites_roundtrip_native_RGBA_without_new_bitmaps",native_ok and images.size() == 117,{"native_images":images})


func echo_V() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_V
	event.physical_keycode = KEY_V
	event.pressed = true
	event.echo = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func control_checks(tree: SceneTree) -> void:
	await actual_reset(tree,"upper_first_cast")
	var main: Node = tree.current_scene
	var serial: int = upper.accepted_casts
	var identity: int = main.player.attack_instance
	var next: String = main.player.next_attack
	var start: int = Time.get_ticks_usec()
	helper.tap(KEY_V)
	echo_V()
	helper.tap(KEY_V)
	var accepted: bool = upper.accepted_casts == serial+1 and main.player.animation_name == "upperslash" and main.player._one_shot
	var ended: Dictionary = await wait_for(tree,"actual_V_original550ms_one_shot",.85,
		func(m:Node,_row:Dictionary):return not m.player._one_shot)
	var action_seconds: float = float(Time.get_ticks_usec()-start)/1000000.0
	helper.tap(KEY_V)
	check_result("actual_V_runs_original550ms_once_echo_repeat_reject_and_does_not_advance_normal_combo",accepted and ended.reached
		and action_seconds >= .50 and action_seconds < .85 and upper.accepted_casts == serial+1
		and main.player.attack_instance == identity+1 and main.player.next_attack == next and upper.cooldown_remaining > 1,
		{"action_seconds":action_seconds,"upper":upper.capture_state()})
	var expired: Dictionary = await wait_for(tree,"actual_two_second_upper_CD_expires",2.0,
		func(_m:Node,row:Dictionary):return row.upper.cooldown_remaining == 0)
	var elapsed: float = float(Time.get_ticks_usec()-start)/1000000.0
	helper.tap(KEY_V)
	check_result("real_two_second_CD_accepts_fresh_V_after_expiry_without_auto_repeat",expired.reached and elapsed >= 1.9 and elapsed < 2.5
		and upper.accepted_casts == serial+2 and main.player.animation_name == "upperslash",{"elapsed_seconds":elapsed,"upper":upper.capture_state()})
	await wait_for(tree,"second_V_finishes_before_modal_probes",.68)
	var freezes: Array = []
	for mode: String in ["pause","inspection","menu","bag"]:
		var menu: PopupMenu = main.get_node("Interface/AudioMenu").get_popup()
		if mode == "pause":
			helper.tap(KEY_F2)
		elif mode == "inspection":
			helper.tap(KEY_F1)
		elif mode == "menu":
			menu.popup(Rect2i(180,120,180,160))
		else:
			helper.tap(KEY_B)
		await wait_for(tree,"upper_CD_modal_settles_"+mode,.035)
		var before: float = upper.cooldown_remaining
		await wait_for(tree,"upper_CD_frozen_"+mode,.12)
		freezes.append({"mode":mode,"pass":upper.capture_state().frozen and upper.cooldown_remaining == before,"remaining":before})
		if mode == "pause":
			helper.tap(KEY_F2)
		elif mode == "inspection":
			helper.tap(KEY_F1)
		elif mode == "menu":
			menu.hide()
		else:
			helper.tap(KEY_B)
	check_result("actual_F2_F1_B_and_native_menu_freeze_upper_CD",freezes.all(func(row:Dictionary):return row.pass),{"freezes":freezes})
	var gates: Array = []
	await actual_reset(tree,"upper_guard_gate")
	serial = upper.accepted_casts
	helper.key(KEY_C,true)
	helper.tap(KEY_V)
	gates.append({"gate":"actual_guard","pass":guard.capture_state().active and upper.accepted_casts == serial and upper.cooldown_remaining == 0})
	helper.key(KEY_C,false)
	await actual_reset(tree,"upper_air_gate")
	helper.tap(KEY_SPACE)
	var air: Dictionary = await wait_for(tree,"actual_jump_above_preparation_before_V",.5,
		func(m:Node,_row:Dictionary):return m.player.jump_motion.height_pixels > 10)
	helper.tap(KEY_V)
	gates.append({"gate":"actual_air","pass":air.reached and upper.accepted_casts == serial and upper.cooldown_remaining == 0})
	await actual_reset(tree,"upper_action_gate")
	helper.tap(KEY_X)
	helper.tap(KEY_V)
	gates.append({"gate":"actual_X_action","pass":main.player.animation_name == "attack1" and upper.accepted_casts == serial and upper.cooldown_remaining == 0})
	await actual_reset(tree,"upper_preview_gate")
	main.player.preview("upperslash")
	helper.tap(KEY_V)
	gates.append({"gate":"source_preview","pass":main.player.preview_mode and upper.accepted_casts == serial and upper.cooldown_remaining == 0})
	main.player.free_control()
	check_result("actual_guard_air_attack_and_source_preview_reject_upper_without_spending_CD",gates.all(func(row:Dictionary):return row.pass),{"gates":gates})
	helper.tap(KEY_V)
	var resets: int = upper.reset_count
	await actual_reset(tree,"upper_one_R")
	check_result("one_actual_R_clears_upper_CD_once_and_source_action",upper.cooldown_remaining == 0 and upper.reset_count == resets+1
		and not main.player._one_shot and not main.player.preview_mode and not main.player.ui_input_blocked)


func load_area(tree: SceneTree, path: String, label: String) -> bool:
	tree.change_scene_to_file(path) # Explicit arena-entry fixture, not a new route assertion.
	var ready: Dictionary = await wait_for(tree,label,2.5,ready_scene(path))
	if ready.reached:
		var fight: Node = fight_at(tree.current_scene)
		if fight != null:
			fight.qa_freeze_enemy = true
	return ready.reached


func prepare_ordinary(tree: SceneTree, gap: float = 80) -> Node:
	await actual_reset(tree,"ordinary_upper_fixture")
	var fight: Node = fight_at(tree.current_scene)
	fight.qa_freeze_enemy = true
	if tree.current_scene.scene_file_path == STATUE:
		fight.awakened = true
		fight.phase = "awake"
		fight.enemy_mode = "idle"
	stage_actor(tree.current_scene.player,Vector2(440,315),1)
	stage_actor(fight.enemy,Vector2(440+gap,315),-1)
	fight.enemy.release_pose()
	return fight


func lift_at(fight: Node) -> Node:
	return fight.get_node_or_null("EnemyLaunchMotion")


func ordinary_launch_checks(tree: SceneTree) -> void:
	if not await load_area(tree,HALL,"fixture_hall_for_normal_combo"):
		check_result("hall_available_for_upper",false)
		return
	var fight: Node = await prepare_ordinary(tree)
	var lift: Node = lift_at(fight)
	var starts: int = lift.start_count
	var casts: int = upper.accepted_casts
	helper.tap(KEY_X)
	await wait_for(tree,"first_normal_X_before_buffer",.45)
	helper.tap(KEY_X)
	await wait_for(tree,"second_normal_X_before_third_buffer",.67)
	helper.tap(KEY_X)
	await wait_for(tree,"normal_combo3_full_source_recovery",.90)
	check_result("three_real_X_combo_hits_keep18_22_30_damage_and_never_launch",fight.enemy_hp == 20 and fight.event_counters.hero_hits == 3
		and lift.start_count == starts and not lift.active and upper.accepted_casts == casts,
		{"state":fight.capture_state(),"fixture":"Only80px spacing and stopped AI; all three normal attacks are actual X taps, no perform/health writes."})
	fight = await prepare_ordinary(tree,65)
	lift = lift_at(fight)
	fight.qa_freeze_enemy = false
	var foe_hits: int = fight.event_counters.enemy_hits
	starts = lift.start_count
	var windup: Dictionary = await wait_for(tree,"AI_attack_precedes_late_V",1.5,
		func(_m:Node,row:Dictionary):return row.fight.enemy_mode == "attack" and float(row.fight.enemy_action_elapsed_ms) >= 260)
	helper.tap(KEY_V)
	var hurt: Dictionary = await wait_for(tree,"real_enemy_contact_interrupts_V_without_superarmor",.4,
		func(_m:Node,row:Dictionary):return int(row.fight.event_counters.enemy_hits) > foe_hits)
	var before_CD: float = upper.cooldown_remaining
	await wait_for(tree,"upper_CD_continues_through_own_hurt",.09)
	check_result("late_actual_V_has_no_superarmor_and_own_hurt_does_not_freeze_CD",windup.reached and hurt.reached and fight.player_hp == 88
		and fight.enemy_hp == 90 and lift.start_count == starts and not tree.current_scene.player._one_shot
		and upper.cooldown_remaining < before_CD and upper.cooldown_remaining > 1,
		{"contact":hurt,"after":upper.capture_state(),"fixture":"Only65px initial spacing; AI chooses its attack and actual late V is interrupted."})
	fight.qa_freeze_enemy = true
	if not await load_area(tree,GALLERY,"fixture_gallery_for_real_air_followup"):
		check_result("gallery_available_for_upper",false)
		return
	fight = await prepare_ordinary(tree)
	lift = lift_at(fight)
	var signals: Array = []
	lift.landed.connect(func():signals.append(Time.get_ticks_usec()))
	starts = lift.start_count
	var lands: int = lift.land_count
	helper.tap(KEY_V)
	var launched: Dictionary = await wait_for(tree,"actual_V24_starts_finite_launch",.4,
		func(_m:Node,row:Dictionary):return row.launch.get("active",false))
	var launch_time: int = Time.get_ticks_usec()
	var duration: float = lift.duration_seconds
	var height: float = lift.peak_height_px
	var foot: Vector2 = lift.capture_state().source_foot
	var before_record: int = records.size()
	var apex: Dictionary = await wait_for(tree,"independent_launch_clock_reaches_apex",duration*.65,
		func(_m:Node,row:Dictionary):return float(row.launch.height_px) >= height-.25)
	var curve_ok: bool = true
	for index: int in range(before_record,records.size()):
		var row: Dictionary = records[index]
		if row.launch.get("active",false):
			var ratio: float = float(row.launch.age_seconds)/duration
			curve_ok = curve_ok and absf(float(row.launch.height_px)-4*height*ratio*(1-ratio)) < .05
			curve_ok = curve_ok and row.launch.source_foot.distance_to(foot) < .01
	var sprite_height: float = fight.enemy.get_node("Sprite").position.y
	check_result("actual_V24_raises_native_enemy48px_with_rule_driven_curve_shadow_and_fixed_ground_foot",launched.reached and fight.enemy_hp == 76
		and apex.reached and curve_ok and lift.start_count == starts+1 and lift.capture_state().height_ratio > .98
		and absf(sprite_height-float(lift.capture_state().height_px)/(60*cos(deg_to_rad(38)))) < .0001,
		{"apex":apex,"curve_matches":curve_ok,"native_sprite_height_m":sprite_height,"fixture":"Initial80px spacing/stopped caster AI only; actual V owns damage and launch."})
	screenshot(tree,"air_apex")
	await wait_for(tree,"V_natural550ms_recovery_before_X_followup",.4,
		func(m:Node,_row:Dictionary):return not m.player._one_shot)
	var age_before_X: float = lift.age
	helper.tap(KEY_X)
	var followup: Dictionary = await wait_for(tree,"actual_X_hits_before_original_landing_deadline",.4,
		func(_m:Node,row:Dictionary):return int(row.fight.enemy_hp) == 58)
	var airborne_hit: bool = followup.reached and lift.active and lift.capture_state().height_px > 0 and lift.start_count == starts+1
	var age_after_X: float = lift.age
	var landed: Dictionary = await wait_for(tree,"first_launch_deadline_is_not_extended_by_real_airhit",maxf(0,duration-lift.age)+.15,
		func(_m:Node,row:Dictionary):return not row.launch.active)
	var elapsed: float = float(Time.get_ticks_usec()-launch_time)/1000000.0
	check_result("natural_V_then_real_X_hits_airborne_once_without_relaunch_or_extending_landing",airborne_hit and landed.reached
		and age_after_X >= age_before_X and lift.start_count == starts+1 and lift.land_count == lands+1 and signals.size() == 1
		and lift.last_end_reason == "landed" and lift.last_end.age_seconds == duration and elapsed <= duration+.16
		and fight.enemy_hurt_remaining >= .10 and fight.enemy.jump_motion.height_pixels == 0,
		{"followup":followup,"landing":landed,"age_before_X":age_before_X,"age_after_X":age_after_X,"elapsed_launch_seconds":elapsed,
		"recovery_policy":"Landing recovery is max(existing hurt, rule .12), so this airhit may leave more than .12."})
	await wait_for(tree,"natural_land_signal_does_not_repeat",.25)
	check_result("finite_launch_lands_once_then_grounded_recovery_finishes",signals.size() == 1 and lift.land_count == lands+1 and not lift.active
		and lift.capture_state().height_px == 0 and fight.enemy_hurt_remaining == 0)
	await launch_freeze_checks(tree)


func launch_freeze_checks(tree: SceneTree) -> void:
	var fight: Node = await prepare_ordinary(tree)
	var lift: Node = lift_at(fight)
	helper.tap(KEY_V)
	await wait_for(tree,"V_launch_before_independent_clock_freezes",.4,
		func(_m:Node,row:Dictionary):return row.launch.get("active",false))
	await wait_for(tree,"V_recovery_before_opening_modals",.7,
		func(m:Node,_row:Dictionary):return not m.player._one_shot)
	var age: float = lift.age
	var starts: int = lift.start_count
	var rejected: int = lift.reject_count
	var duplicate: bool = lift.launch() # Explicit helper boundary fixture; actual V's CD already rejects a second cast.
	check_result("active_helper_relaunch_rejects_without_resetting_age_or_height",not duplicate and lift.age == age and lift.start_count == starts
		and lift.reject_count == rejected+1 and lift.last_reject_reason == "already_active",{"fixture":"One direct duplicate launch() probe while an actual V launch is active."})
	var freezes: Array = []
	for mode: String in ["pause","inspection","menu","bag"]:
		var menu: PopupMenu = tree.current_scene.get_node("Interface/AudioMenu").get_popup()
		if mode == "pause":
			helper.tap(KEY_F2)
		elif mode == "inspection":
			helper.tap(KEY_F1)
		elif mode == "menu":
			menu.popup(Rect2i(180,120,180,160))
		else:
			helper.tap(KEY_B)
		await wait_for(tree,"launch_freeze_settles_"+mode,.03)
		var before: Dictionary = {"age":lift.age,"height":lift.capture_state().height_px,"foot":lift.capture_state().source_foot,"CD":upper.cooldown_remaining}
		await wait_for(tree,"independent_launch_clock_frozen_"+mode,.10)
		var after: Dictionary = {"age":lift.age,"height":lift.capture_state().height_px,"foot":lift.capture_state().source_foot,"CD":upper.cooldown_remaining}
		freezes.append({"mode":mode,"pass":lift.capture_state().frozen and before == after,"snapshot":before})
		if mode == "pause":
			helper.tap(KEY_F2)
		elif mode == "inspection":
			helper.tap(KEY_F1)
		elif mode == "menu":
			menu.hide()
		else:
			helper.tap(KEY_B)
	check_result("actual_pause_inspection_menu_and_bag_freeze_both_launch_and_upper_CD",freezes.all(func(row:Dictionary):return row.pass),{"freezes":freezes})
	await wait_for(tree,"launch_resumes_despite_caster_QA_freeze_and_enemy_hurt",1.0,
		func(_m:Node,row:Dictionary):return not row.launch.active)
	check_result("independent_lift_ignores_enemy_AI_freeze_and_hurt_early_returns",fight.qa_freeze_enemy and not lift.active
		and lift.last_end_reason == "landed" and lift.last_end.age_seconds == lift.duration_seconds)


func smoke_and_terminal_checks(tree: SceneTree) -> void:
	var smoke: Array = []
	for area: String in [HALL,STATUE]:
		var ready: bool = await load_area(tree,area,"fixture_other_ordinary_launch")
		if not ready:
			smoke.append({"area":area,"pass":false})
			continue
		var fight: Node = await prepare_ordinary(tree)
		helper.tap(KEY_V)
		var hit: Dictionary = await wait_for(tree,"actual_V_ordinary_launch_smoke",.4,
			func(_m:Node,row:Dictionary):return row.launch.get("active",false))
		smoke.append({"area":area,"pass":hit.reached and lift_at(fight).active,"state":fight.capture_state()})
	check_result("actual_V_also_launches_Mirkius_and_explicitly_awake_Statue",smoke.all(func(row:Dictionary):return row.pass),
		{"regions":smoke,"fixture":"Initial positions, stopped AI and awake Statue only; actual V causes each native hit."})
	await load_area(tree,DEPTHS,"fixture_boss_launch_immunity")
	var boss: Node = await prepare_ordinary(tree)
	var hp: int = boss.enemy_hp
	helper.tap(KEY_V)
	await wait_for(tree,"actual_upper_damages_boss_without_float",.7)
	check_result("actual_V_damages_Lakius24_but_never_launches_boss",hp-boss.enemy_hp == 24 and boss.get_node_or_null("EnemyLaunchMotion") == null
		and boss.enemy.jump_motion.height_pixels == 0 and not boss.enemy.jump_motion.is_active(),{"boss":boss.capture_state()})
	await load_area(tree,GALLERY,"fixture_launch_lifecycle")
	var fight: Node = await prepare_ordinary(tree)
	var lift: Node = lift_at(fight)
	helper.tap(KEY_V)
	await wait_for(tree,"actual_V_active_before_R_clear",.4,
		func(_m:Node,row:Dictionary):return row.launch.get("active",false))
	var lands: int = lift.land_count
	var resets: int = upper.reset_count
	await actual_reset(tree,"active_launch_R")
	check_result("actual_R_clears_active_launch_height_and_upper_CD_without_landing_event",not lift.active and lift.age == 0
		and lift.last_clear_reason == "reset" and lift.land_count == lands and fight.enemy.jump_motion.height_pixels == 0
		and upper.cooldown_remaining == 0 and upper.reset_count == resets+1)
	fight = await prepare_ordinary(tree)
	lift = lift_at(fight)
	fight.enemy_hp = 42 # Explicit terminal fixture: V24 leaves18, actual airborne X supplies the killing18.
	fight._persist()
	helper.tap(KEY_V)
	await wait_for(tree,"terminal_V_launch_and_natural_recovery",.7,
		func(m:Node,row:Dictionary):return row.launch.get("active",false) and not m.player._one_shot)
	lands = lift.land_count
	helper.tap(KEY_X)
	var killed: Dictionary = await wait_for(tree,"actual_air_followup_defeats_launched_enemy",.4,
		func(_m:Node,row:Dictionary):return row.fight.cleared)
	check_result("actual_air_followup_defeat_clears_height_without_spurious_landed",killed.reached and not lift.active and lift.age == 0
		and lift.land_count == lands and lift.last_clear_reason == "enemy_defeated" and fight.enemy.jump_motion.height_pixels == 0
		and fight.enemy.animation_name == "down",{"defeat":killed,"fixture":"Only initial42enemyHP, positions and stopped AI; actualV then actualX kill."})
	fight = await prepare_ordinary(tree)
	lift = lift_at(fight)
	helper.tap(KEY_V)
	await wait_for(tree,"launch_active_before_real_projectile_KO",.4,
		func(_m:Node,row:Dictionary):return row.launch.get("active",false))
	fight.player_hp = 6
	fight._persist()
	lands = lift.land_count
	var emitted: bool = fight.get_node("GemProjectiles").emit(point(tree.current_scene)+Vector2(20,0),-1)
	var ko: Dictionary = await wait_for(tree,"real_gem_KO_clears_enemy_launch_same_tick",.3,
		func(_m:Node,row:Dictionary):return int(row.fight.player_hp) == 0)
	check_result("real_projectile_player_KO_clears_active_launch_without_landing",emitted and ko.reached and not lift.active and lift.age == 0
		and lift.last_clear_reason == "player_ko" and lift.land_count == lands and fight.enemy.jump_motion.height_pixels == 0,
		{"KO":ko,"fixture":"Only initial6HP and incoming flight after actualV launch; real damage acquires KO lock."})
	await actual_reset(tree,"launch_KO_retry")
	fight = await prepare_ordinary(tree)
	lift = lift_at(fight)
	helper.tap(KEY_V)
	await wait_for(tree,"launch_active_before_actual_scene_exit",.4,
		func(_m:Node,row:Dictionary):return row.launch.get("active",false))
	var old_id: int = lift.get_instance_id()
	stage_actor(tree.current_scene.player,Vector2(38,320),-1) # Portal position/free-control fixture; enemy flight remains active.
	var left: Dictionary = await wait_for(tree,"actual_A_departs_with_active_enemy_launch",2.5,ready_scene(DEPTHS),[KEY_A])
	if left.reached:
		tree.current_scene.get_node("TowerBoss").qa_freeze_enemy = true
	check_result("actual_scene_exit_removes_launch_node_and_does_not_carry_air_state",left.reached and not is_instance_id_valid(old_id)
		and tree.current_scene.get_node("TowerBoss").enemy.jump_motion.height_pixels == 0,
		{"exit":left,"fixture":"Only portal position/free control after actualV; actualA uses existing travel, no enemy height write."})


func actual_upper_victory(tree: SceneTree, progress: Node) -> void:
	if not await load_area(tree,GALLERY,"full_actual_upper_fight_entry_fixture"):
		check_result("upper_actual_fight_available",false)
		return
	await actual_reset(tree,"full_AI_upper_victory")
	var fight: Node = tree.current_scene.get_node("GalleryEncounter")
	var profile_before: Dictionary = progress.progress.duplicate(true)
	var files_before: Dictionary = states.file_guard(qa_path)
	var saves: int = progress._save_attempts
	var before_hits: int = fight.event_counters.hero_hits
	fight.qa_freeze_enemy = false
	# From this ordinary R onward: actual movement/V/Q only, with no position/HP/AI/clock writes.
	await wait_for(tree,"real_upper_fight_align_depth",1.5,
		func(m:Node,_row:Dictionary):return absf(fight.enemy.world_to_source(fight.enemy.position).y-point(m).y) <= 10,[KEY_W])
	await wait_for(tree,"real_upper_fight_run_into110px_range",4.0,
		func(m:Node,_row:Dictionary):return absf(fight.enemy.world_to_source(fight.enemy.position).x-point(m).x) <= 103,[KEY_D,KEY_SHIFT])
	helper.tap(KEY_V)
	var upper_hit: Dictionary = await wait_for(tree,"actual_V_hits_and_launches_AI_opponent",.8,
		func(_m:Node,row:Dictionary):return int(row.fight.enemy_hp) == 76 and row.launch.get("active",false))
	var casts: Array = []
	for attempt: int in 6:
		if fight.cleared or fight.player_hp == 0:
			break
		await wait_for(tree,"real_upper_fight_wait_free_controls",2.0,
			func(m:Node,row:Dictionary):return row.fight.cleared or int(row.fight.player_hp) == 0 or (not m.player._one_shot and not row.blocked))
		if fight.cleared or fight.player_hp == 0:
			break
		var difference: Vector2 = fight.enemy.world_to_source(fight.enemy.position)-point(tree.current_scene)
		if absf(difference.y) > 12:
			await wait_for(tree,"real_upper_Q_depth_align",1.5,
				func(m:Node,_row:Dictionary):return absf(fight.enemy.world_to_source(fight.enemy.position).y-point(m).y) <= 10,[KEY_S if difference.y > 0 else KEY_W])
		difference = fight.enemy.world_to_source(fight.enemy.position)-point(tree.current_scene)
		var toward: Key = KEY_D if difference.x >= 0 else KEY_A
		var away: Key = KEY_A if difference.x >= 0 else KEY_D
		if absf(difference.x) > 130:
			await wait_for(tree,"real_upper_Q_approach",3,
				func(m:Node,_row:Dictionary):return absf(fight.enemy.world_to_source(fight.enemy.position).x-point(m).x) <= 130,[toward,KEY_SHIFT])
		elif absf(difference.x) < 123:
			await wait_for(tree,"real_upper_Q_retreat",1.5,
				func(m:Node,_row:Dictionary):return absf(fight.enemy.world_to_source(fight.enemy.position).x-point(m).x) >= 128 or point(m).x <= 40 or point(m).x >= 848,[away,KEY_SHIFT])
		await wait_for(tree,"real_upper_Q_facing",.025,Callable(),[toward])
		helper.tap(KEY_Q)
		await wait_for(tree,"real_upper_Q_and_natural_recovery",1.6,
			func(m:Node,row:Dictionary):return row.fight.cleared or int(row.fight.player_hp) == 0 or (not m.player._one_shot and not row.blocked))
		casts.append(fight.capture_state())
	check_result("actual_V_launch_plus_real_Q_movement_defeat100HP_AI_without_state_or_clock_writes",upper_hit.reached and fight.cleared and fight.enemy_hp == 0
		and fight.player_hp > 0 and not fight.qa_freeze_enemy and fight.event_counters.hero_hits >= before_hits+3,
		{"first_actual_upper":upper_hit,"followups":casts,"final":fight.capture_state()})
	await wait_for(tree,"upper_actual_victory_down_finishes",.8,
		func(_m:Node,row:Dictionary):return row.fight.cleared and not row.fight.enemy_visible)
	screenshot(tree,"actual_victory")
	check_result("new_upper_skill_and_launch_introduce_no_reward_or_profile_write",progress.progress == profile_before
		and states.file_guard(qa_path) == files_before and progress._save_attempts == saves and progress._pending_bundle.is_empty(),
		{"profile":progress.capture_state(),"files_before":files_before,"files_after":states.file_guard(qa_path)})


func late_upper(actor: Node) -> void:
	actor.preview("upperslash")
	actor.preview_mode = false
	actor._one_shot = true
	actor.paused = true
	actor.frame_index = 8
	actor.elapsed_ms = 100
	actor._apply_frame()
	actor._update_sprite_transform()


func appearance_and_transfer_checks(tree: SceneTree, progress: Node) -> void:
	await actual_reset(tree,"upper_CD_before_existing_route")
	var fight: Node = fight_at(tree.current_scene)
	fight.qa_freeze_enemy = true
	stage_actor(tree.current_scene.player,Vector2(38,320),-1)
	helper.tap(KEY_V)
	await wait_for(tree,"V_recovers_at_portal_before_actual_A",.65)
	var before: float = upper.cooldown_remaining
	var moved: Dictionary = await wait_for(tree,"upper_CD_transfers_across_actual_existing_route",2.5,ready_scene(DEPTHS),[KEY_A])
	if moved.reached:
		tree.current_scene.get_node("TowerBoss").qa_freeze_enemy = true
	check_result("real_V_CD_survives_actual_region_transfer_without_action_carry",moved.reached and upper.cooldown_remaining > .5
		and upper.cooldown_remaining < before and not tree.current_scene.player._one_shot,{"travel":moved,"before_CD":before,"upper":upper.capture_state()})
	await load_area(tree,HARBOR,"fixture_harbor_for_equipment_and_R0")
	var history: Dictionary = progress._default_progress()
	history.quest_stage = "completed"
	history.objective_cleared = true
	history.reward_granted = true
	history.coins = 40
	history.first_drop.state = "claimed"
	history.inventory["3128"] = 1
	history.equipment.owned["27304"] = true
	var owned: bool = progress._commit(history)
	await actual_reset(tree,"owned_bag_priority")
	helper.tap(KEY_B)
	await wait_for(tree,"real_B_opens_upper_equipment_fixture",.04)
	var accepted: int = upper.accepted_casts
	helper.tap(KEY_C)
	helper.tap(KEY_V)
	await wait_for(tree,"bag_C_stays_equipment_priority_and_V_is_blocked",.05)
	check_result("actual_bag_C_equips_weapon_while_V_is_modal_blocked",owned and tree.current_scene.get_node("FirstLoot").capture_state().bag_open
		and progress.equipped_weapon_key() == "27304" and upper.accepted_casts == accepted and upper.cooldown_remaining == 0,
		{"fixture":"Legitimate completed reward/owned weapon history is committed only after the independent no-award AI victory."})
	helper.tap(KEY_B)
	var equipment: Node = progress.get_node("EquipmentRuntime")
	var cases: Array = []
	for weapon: String in ["practice_lswd0000","27304"]:
		var main: Node = tree.current_scene
		late_upper(main.player)
		var pose: Dictionary = main.player.capture_state()
		var equipped: bool = progress.equip_weapon(weapon)
		var stable: bool = main.player.capture_state() == pose
		upper.cooldown_remaining = 1.7 # Paused comparison-clock fixture.
		helper.tap(KEY_F4)
		var raw: Dictionary = await wait_for(tree,"last_upper_frame8_F4_R0",2.5,ready_scene(RAW))
		main = tree.current_scene
		var raw_pose: Dictionary = main.player.capture_state()
		var layers_ok: bool = main.player.current_frame().get("layers",[]).size() == 9 and main.player._layers.size() == 9
		if layers_ok:
			for i: int in 9:
				var layer: Dictionary = main.player.current_frame().layers[i]
				var sprite: Sprite2D = main.player._layers[i]
				layers_ok = layers_ok and sprite.texture != null and sprite.texture.resource_path == layer.texture and sprite.position == Vector2(layer.offset[0],layer.offset[1])
		var raw_ok: bool = raw.reached and raw_pose.action == "upperslash" and raw_pose.frame == 8 and raw_pose.elapsed_ms == 100 \
			and raw_pose.paused and raw_pose.one_shot and layers_ok and upper.cooldown_remaining == 1.7 \
			and equipment.appearance.current_key(main.player) == weapon
		helper.tap(KEY_F4)
		var back: Dictionary = await wait_for(tree,"last_upper_frame8_F4_R1",2.5,ready_scene(HARBOR))
		main = tree.current_scene
		var back_pose: Dictionary = main.player.capture_state()
		var texture: String = main.player.current_frame().texture
		var back_ok: bool = back.reached and back_pose.action == "upperslash" and back_pose.frame == 8 and back_pose.elapsed_ms == 100 \
			and back_pose.paused and back_pose.one_shot and main.player.sprite.texture.resource_path == texture \
			and main.player.source_material.get_shader_parameter("source_texture") == main.player.sprite.texture \
			and equipment.appearance.current_key(main.player) == weapon and upper.cooldown_remaining == 1.7
		cases.append({"weapon":weapon,"pass":equipped and stable and raw_ok and back_ok,"raw":raw_pose,"R1":back_pose,"raw_layers_exact":layers_ok})
		main._set_paused(false)
		main.player.free_control()
	check_result("both_weapons_R0_R1_last_alias_frame8_F4_and_equipment_adapter_preserve_clock_oneShot_and_exact_layers",cases.all(func(row:Dictionary):return row.pass),{"cases":cases,"fixture":"Paused last frame8/elapsed100ms oneShot and1.7s CD only; exact existing weapon textures, no new bitmap."})
	helper.tap(KEY_F4)
	var raw_ready: Dictionary = await wait_for(tree,"actual_R0_V_ready",2.5,ready_scene(RAW))
	await actual_reset(tree,"raw_V_CD")
	accepted = upper.accepted_casts
	helper.tap(KEY_V)
	var raw_begin: bool = raw_ready.reached and upper.accepted_casts == accepted+1 and tree.current_scene.player.animation_name == "upperslash"
	var remaining: float = upper.cooldown_remaining
	await wait_for(tree,"comparison_V_clock_continues_safely_without_guard_property",.65)
	check_result("R0_actual_V_runs_alias_and_comparison_CD_continues_without_3D_only_properties",raw_begin
		and upper.cooldown_remaining < remaining-.45 and not upper.capture_state().frozen and not tree.current_scene.player._one_shot,
		{"upper":upper.capture_state()})
	helper.tap(KEY_F4)
	await wait_for(tree,"final_F4_returns_R1",2.5,ready_scene(HARBOR))
	await actual_reset(tree,"final_upper_R")
	await load_area(tree,GALLERY,"fixture_equipped_upper_damage")
	var equipped_fight: Node = await prepare_ordinary(tree)
	helper.tap(KEY_V)
	var equipped_hit: Dictionary = await wait_for(tree,"actual_greatsword_V_adds_four_damage_once",.4,
		func(_m:Node,row:Dictionary):return int(row.fight.enemy_hp) == 72 and row.launch.get("active",false))
	check_result("actual_greatsword_upper_hits_once_for28_and_keeps_same_finite_launch",equipped_hit.reached
		and progress.equipped_weapon_key() == "27304" and equipped_fight.enemy_hp == 72 and lift_at(equipped_fight).active,
		{"hit":equipped_hit,"fixture":"Owned weapon and80px/stopped AI only; actual V applies24+4 and the same rule-driven lift."})


func run(root: Node, candidate: String = "R4/09") -> Dictionary:
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
	if main == null or main.scene_file_path != HARBOR or progress == null or guard == null or skill == null or potion == null or upper == null or guard.capture_state().active:
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
	qa_path = "user://qa/upper_live_"+str(Time.get_ticks_usec())+"_"+str(Time.get_unix_time_from_system()).replace(".","_")+".json"
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
		asset_checks()
		await control_checks(tree)
		await ordinary_launch_checks(tree)
		await smoke_and_terminal_checks(tree)
		await actual_upper_victory(tree,progress)
		await appearance_and_transfer_checks(tree,progress)
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
	check_result("cleanup_restores_profile_pending_all_five_fight_metas_actor_preferences_and_four_runtimes",cleanup.reached \
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
		"upper_source_sha256":FileAccess.get_file_as_string("res://scripts/upper_slash_runtime.gd").sha256_text(),
		"rules_sha256":FileAccess.get_file_as_string("res://data/upper_slash_rules.json").sha256_text(),
		"source_reference_sha256":FileAccess.get_sha256(UPPER_SOURCE),"launch_source_sha256":FileAccess.get_file_as_string("res://scripts/enemy_launch_motion.gd").sha256_text(),
		"note":"Focused Upper Slash source alias/cooldown/finite launch proof. Nine original Attack3 records550ms remain exact; V binding,24damage and rule-driven finite lift are adaptations, not source350-to-pixel physics/MP/superarmor/cancel. Normal combo Attack3 remains30 and never launches. Actual V→X after natural550ms recovery verifies one airborne follow-up without extending launch. Controlled enemy positions/awake state/terminal HP, public active re-launch probe, paused last-frame transfer and owned-history fixture are explicit. Full Gallery100HP AI victory starts at ordinary R and uses actualV plus directional/Q controls without HP/position writes, enemy AI freeze or accelerated time. Four runtime clocks/counters, five fight/session metadata snapshots, profile including pending and actor/preferences restore after combat exit. Human four profile files remain byte unchanged. PNG reads use buffers and metadata snapshots preserve absence; every wait is bounded."}

	var path: String = "res://docs/"+output_prefix+"_upper_checks.json"
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report,"  "))
		output.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases.size(),"recorded_rows":records.size(),"report":path}
