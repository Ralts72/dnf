extends "res://tools/r4/gallery_checks.gd"
## R4/07 focused ranged checks; parent alone dispatches the persistent native job.

const RANGED_SOURCE: String = "res://docs/r4_stonemaster_ranged_source_reference.json"


func screenshot(tree: SceneTree, name: String) -> void:
	var path: String = "res://docs/previews/"+output_prefix+"_ranged_"+name+".png"
	screenshots[name] = {"path":path,"save_error":tree.current_scene.get_viewport().get_texture().get_image().save_png(path),
		"scene":tree.current_scene.scene_file_path,"frame_usec":Time.get_ticks_usec()}


func asset_checks() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RANGED_SOURCE))
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/stonemaster_r1.json"))
	var caster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/stonemaster_ranged_r1.json"))
	var gem: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/stonemaster_gem.json"))
	var old_ok: bool = old.animations.size() == 6 and caster.animations.size() == 7
	for key: String in old.animations:
		old_ok = old_ok and caster.animations[key] == old.animations[key]
	var cast_clock: float = 0
	for frame: Dictionary in caster.animations.cast.frames:
		cast_clock += float(frame.duration_ms)
	var gem_clock: float = 0
	for frame: Dictionary in gem.frames:
		gem_clock += float(frame.duration_ms)
	check_result("all_six_old_action_objects_remain_exact_new_cast11_keeps1000ms_and_gem13_keeps615ms",old_ok
		and caster.animations.cast.frames.size() == 11 and cast_clock == 1000 and gem.frames.size() == 13 and gem_clock == 615,
		{"cast_records":caster.animations.cast.frames.size(),"cast_clock_ms":cast_clock,"gem_records":gem.frames.size(),"gem_clock_ms":gem_clock})
	var native_ok: bool = true
	var rows: Array = []
	for group: String in ["source_crops","derived_composites","gem_frames"]:
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
			rows.append({"path":entry.texture,"native_complete_RGBA_exact":exact})
	var rebuilt_ok: bool = source.derived_composites.size() == 11
	for entry: Dictionary in source.derived_composites:
		var crop: Image = raw_png(entry.source_crop)
		var expected: Image = Image.create(entry.size[0],entry.size[1],false,Image.FORMAT_RGBA8)
		expected.fill(Color(0,0,0,0))
		expected.blit_rect(crop,Rect2i(Vector2i.ZERO,crop.get_size()),Vector2i(entry.composite_paste_offset[0],entry.composite_paste_offset[1]))
		rebuilt_ok = rebuilt_ok and expected.get_data() == raw_png(entry.texture).get_data() \
			and float(entry.duration_ms) == float(entry.source_duration_ms)
	check_result("twenty_six_new_native_PNGs_and_eleven_source_offset_reconstructions_keep_full_RGBA",native_ok and rows.size() == 26 and rebuilt_ok,{"images":rows})
	var source_ok: bool = source.source_scripts.size() == 5
	var pvf: Array = []
	for entry: Dictionary in source.source_scripts:
		var exact: bool = entry.crc_matches and FileAccess.get_sha256("res://"+entry.raw_reference) == entry.sha256_decoded
		source_ok = source_ok and exact
		pvf.append({"path":entry.pvf_path,"retained_CRC_verified_bytes_exact":exact})
	var audio: Dictionary = source.audio
	var stream: AudioStream = load(audio.path)
	var pcm: Dictionary = audio.runtime_PCM
	var audio_ok: bool = FileAccess.get_sha256(audio.path) == audio.sha256_runtime_ogg \
		and FileAccess.get_sha256("res://"+audio.retained_original) == audio.sha256_source_ogg and audio.PCM_byte_identical \
		and pcm.sha256 == audio.source_PCM.sha256 and int(pcm.frames) == 17550 and int(pcm.bytes) == 70200 \
		and stream != null and absf(stream.get_length()-float(pcm.frames)/float(pcm.sample_rate)) < .02
	check_result("five_retained_PVF_CRC_sources_and_JEWEL_HIT_match17550_frame_PCM_evidence",source_ok and audio_ok,
		{"sources":pvf,"native_audio_length":stream.get_length() if stream != null else -1,"offline_ffmpeg_PCM_sha256":pcm.sha256,
		"scope":"Both source/runtime OGGs were independently decoded with ffmpeg before the native suite; source dispatch/speed/lifetime remain explicitly adapted."})


func prepare(tree: SceneTree, gap: float = 180, facing: int = 1) -> Node:
	await actual_reset(tree,"ranged_fixture")
	var fight: Node = tree.current_scene.get_node("GalleryEncounter")
	fight.qa_freeze_enemy = true
	stage_actor(tree.current_scene.player,Vector2(440,315),facing)
	stage_actor(fight.enemy,Vector2(440+gap,315),-1)
	return fight


func projectile(tree: SceneTree) -> Node:
	return tree.current_scene.get_node("GalleryEncounter/GemProjectiles")


func ranged_snapshot(tree: SceneTree) -> Dictionary:
	var fight: Node = tree.current_scene.get_node("GalleryEncounter")
	return {"cast_ms":fight.cast_elapsed_ms,"cast_active":fight.cast_active,"ranged_CD":fight.ranged_cooldown_remaining,
		"source_frame":fight.enemy.frame_index,"source_position":fight.enemy.position,"hero_position":point(tree.current_scene),
		"hero_hp":fight.player_hp,"enemy_hp":fight.enemy_hp,"flights":projectile(tree).capture_state().active,
		"CDs":[guard.cooldown_remaining,skill.cooldown_remaining,potion.cooldown_remaining]}


func cast_and_contact(tree: SceneTree) -> void:
	var fight: Node = await prepare(tree)
	var main: Node = tree.current_scene
	var gems: Node = projectile(tree)
	var emitted: int = gems.emitted_count
	var hits: int = gems.hit_count
	fight.qa_freeze_enemy = false
	var started: Dictionary = await wait_for(tree,"AI_starts_1000ms_source_cast",1.0,
		func(_m:Node,row:Dictionary):return row.fight.cast_active and float(row.fight.cast_elapsed_ms) >= 80)
	var cast_start: int = Time.get_ticks_usec()
	var before_pause: Dictionary = ranged_snapshot(tree)
	helper.tap(KEY_F2)
	await wait_for(tree,"cast_pause_settles",.035)
	var paused: Dictionary = ranged_snapshot(tree)
	await wait_for(tree,"cast_pause_freezes_physics_clock",.12)
	check_result("actual_AI_uses_original_cast_at_adapted90_210_range_and_F2_freezes_independent_clock",started.reached
		and fight.cast_duration_ms == 1000 and fight.rules.ranged.minimum_range_px == 90 and fight.rules.ranged.maximum_range_px == 210
		and main.player.paused and ranged_snapshot(tree) == paused and gems.emitted_count == emitted,
		{"started":started,"frozen":paused,"fixture":"Only initial180px same-lane positions are staged. AI chooses Cast without manual attack invocation."})
	helper.tap(KEY_F2)
	var menu: PopupMenu = main.get_node("Interface/AudioMenu").get_popup()
	menu.popup(Rect2i(180,120,180,160))
	await wait_for(tree,"cast_menu_settles",.035)
	var menu_state: Dictionary = ranged_snapshot(tree)
	await wait_for(tree,"cast_menu_freezes_source_pose",.12)
	var menu_ok: bool = menu.visible and ranged_snapshot(tree) == menu_state
	menu.hide()
	helper.tap(KEY_B)
	await wait_for(tree,"cast_bag_settles",.035)
	var bag_state: Dictionary = ranged_snapshot(tree)
	await wait_for(tree,"cast_bag_blocks_movement",.12,Callable(),[KEY_A,KEY_W])
	check_result("native_menu_and_actual_B_modal_freeze_cast_pose_foot_lane_and_all_clocks",menu_ok
		and main.get_node("FirstLoot").capture_state().bag_open and ranged_snapshot(tree) == bag_state,
		{"menu":menu_state,"bag":bag_state})
	helper.tap(KEY_B)
	var released: Dictionary = await wait_for(tree,"natural_1000ms_cast_emits_one_gem",1.5,
		func(_m:Node,row:Dictionary):return int(row.fight.casts_emitted) > int(started.last.fight.casts_emitted))
	var release_state: Dictionary = gems.capture_state()
	var release_ok: bool = released.reached and release_state.active_count == 1 and gems.emitted_count == emitted+1
	if release_ok:
		var flight: Dictionary = release_state.active[0]
		var origin: Vector2 = fight.cast_origin_source+Vector2(float(fight.cast_facing)*float(fight.rules.ranged.emitter_offset_px),0)
		var recovered_origin: Vector2 = flight.source_point-flight.velocity_source*float(flight.age_ms)/1000.0
		release_ok = recovered_origin.distance_to(origin) < .02 and int(flight.facing) == fight.cast_facing
	check_result("source1000ms_completes_once_before_one_gem_appears_at_locked16px_emitter",release_ok
		and fight.cast_elapsed_ms == 1000 and fight.last_cast_end_reason == "emitted" and fight.cast_facing == -1,
		{"release":released,"projectiles":release_state,"elapsed_wall_since_80ms":float(Time.get_ticks_usec()-cast_start)/1000000.0,
		"physics_before_pause":before_pause,"source_clock_policy":"cast_elapsed_ms is authoritative; held source actor reports frame starts only."})
	screenshot(tree,"cast_release")
	var contact: Dictionary = await wait_for(tree,"natural_flying_gem_hits_grounded_hero",.85,
		func(_m:Node,row:Dictionary):return int(row.fight.projectiles.hit_count) > hits)
	check_result("natural_AI_gem_hits_once_for10_and_plays_original_JEWEL_HIT",contact.reached and fight.player_hp == 90
		and gems.last_hit.damage == 10 and not gems.last_hit.blocked and gems.last_hit.hit_count == 1
		and gems._contact_audio != null and gems._contact_audio.playing
		and gems._contact_audio.stream.resource_path == "res://assets/r4/stonemaster_ranged/audio/jewel_hit.ogg"
		and tree.has_meta("route_hero_hp") and tree.get_meta("route_hero_hp") == 90,
		{"contact":contact,"projectiles":gems.capture_state()})
	# Contact immunity must consume this second flight rather than defer its damage until hurt ends.
	var immune_before: int = gems.immune_contact_count
	var immune_emitted: bool = gems.emit(point(main)+Vector2(20,0),-1)
	var immune: Dictionary = await wait_for(tree,"hurt_contact_consumes_second_gem_without_delayed_damage",.12,
		func(_m:Node,row:Dictionary):return int(row.fight.projectiles.immune_contact_count) > immune_before)
	await wait_for(tree,"whole_live_flight_cannot_hit_twice_after_hurt",.28)
	check_result("same_gem_never_double_hits_and_new_hurt_contact_is_consumed_without_delayed_damage",immune_emitted and immune.reached
		and fight.player_hp == 90 and gems.hit_count == hits+1 and gems.last_ended.reason == "impact_immune"
		and gems.capture_state().active_count == 0,
		{"immune_contact":immune,"after":gems.capture_state(),"fixture":"Only the second short flight is controlled emit; the first impact came from natural AI Cast."})
	fight.qa_freeze_enemy = true


func locked_facing_and_interrupt(tree: SceneTree) -> void:
	var fight: Node = await prepare(tree,110)
	var main: Node = tree.current_scene
	stage_actor(main.player,Vector2(440,300),1)
	stage_actor(fight.enemy,Vector2(550,300),-1)
	fight.qa_freeze_enemy = false
	var casting: Dictionary = await wait_for(tree,"AI_locks_left_cast",1.0,
		func(_m:Node,row:Dictionary):return row.fight.cast_active and float(row.fight.cast_elapsed_ms) >= 50)
	var origin: Vector2 = fight.cast_origin_source
	var emitted: int = fight.casts_emitted
	await wait_for(tree,"actual_dash_S_leaves_old_cast_lane",.22,Callable(),[KEY_S,KEY_SHIFT])
	var crossed: Dictionary = await wait_for(tree,"actual_dash_D_crosses_caster_before_release",.8,
		func(m:Node,_row:Dictionary):return point(m).x > origin.x+5,[KEY_D,KEY_SHIFT])
	var locked: bool = crossed.reached and fight.cast_active and fight.enemy.facing == -1 and fight.cast_facing == -1
	var released: Dictionary = await wait_for(tree,"locked_left_cast_finishes_after_hero_crosses",.5,
		func(_m:Node,row:Dictionary):return int(row.fight.casts_emitted) > emitted)
	var shot: Dictionary = projectile(tree).capture_state()
	check_result("real_lane_change_and_crossing_do_not_retarget_locked_cast_origin_lane_or_facing",casting.reached and locked and released.reached
		and fight.cast_origin_source.distance_to(origin) < .01 and fight.cast_lane_y == 300
		and shot.active_count == 1 and shot.active[0].facing == -1 and shot.active[0].source_point.y == 300,
		{"crossing":crossed,"release":released,"projectiles":shot,"fixture":"Only initial110px positions are staged; crossing uses actual Shift+S then Shift+D."})
	fight = await prepare(tree,140)
	var before: int = fight.casts_interrupted
	emitted = fight.casts_emitted
	fight.qa_freeze_enemy = false
	var started: Dictionary = await wait_for(tree,"AI_cast_before_real_Z_interrupt",1.0,
		func(_m:Node,row:Dictionary):return row.fight.cast_active and float(row.fight.cast_elapsed_ms) >= 100)
	helper.tap(KEY_Z)
	var hurt: Dictionary = await wait_for(tree,"actual_Z_interrupts_unreleased_cast",.45,
		func(_m:Node,row:Dictionary):return int(row.fight.enemy_hp) < 100)
	await wait_for(tree,"cancelled_cast_original_release_time_passes",.95)
	check_result("actual_Z_damage_interrupts_unreleased_cast_without_spawning_a_ghost_gem",started.reached and hurt.reached
		and fight.enemy_hp == 56 and fight.casts_interrupted == before+1 and fight.casts_emitted == emitted
		and projectile(tree).capture_state().active_count == 0 and not fight.cast_active,
		{"hit":hurt,"state":fight.capture_state(),"fixture":"Only initial140px positions; source Z timing and AI cast clock run normally."})
	fight.qa_freeze_enemy = true
	# An emitted projectile is independent: later nonlethal caster hurt must not erase it.
	fight = await prepare(tree,150)
	fight.qa_freeze_enemy = false
	emitted = fight.casts_emitted
	var flight: Dictionary = await wait_for(tree,"AI_emits_before_actual_Z",1.6,
		func(_m:Node,row:Dictionary):return int(row.fight.casts_emitted) > emitted)
	helper.tap(KEY_Z)
	var caster_hurt: Dictionary = await wait_for(tree,"actual_Z_hurts_caster_after_emission",.4,
		func(_m:Node,row:Dictionary):return int(row.fight.enemy_hp) == 56)
	var survives: bool = projectile(tree).capture_state().active_count == 1
	var impact: Dictionary = await wait_for(tree,"already_flying_gem_continues_during_caster_hurt",.6,
		func(_m:Node,row:Dictionary):return int(row.fight.player_hp) == 90)
	check_result("nonlethal_caster_hurt_does_not_cancel_an_already_emitted_gem",flight.reached and caster_hurt.reached and survives and impact.reached,
		{"caster_hurt":caster_hurt,"impact":impact})
	fight.qa_freeze_enemy = true


func flight_motion_and_freezes(tree: SceneTree) -> void:
	var fight: Node = await prepare(tree)
	var gems: Node = projectile(tree)
	var expired: int = gems.expired_count
	var emitted: bool = gems.emit(Vector2(500,315),1) # Controlled flight goes away from hero; caster QA freeze stays enabled.
	await wait_for(tree,"controlled_flight_initial_sample",.035)
	var initial: Dictionary = gems.capture_state()
	await wait_for(tree,"native_flight_moves_at320px_per_second",.10)
	var moved: Dictionary = gems.capture_state()
	var speed_ok: bool = initial.active_count == 1 and moved.active_count == 1
	if speed_ok:
		var one: Dictionary = initial.active[0]
		var two: Dictionary = moved.active[0]
		var measured_speed: float = (two.source_point.x-one.source_point.x)/(float(two.age_ms-one.age_ms)/1000.0)
		var sprite: Sprite3D = instance_from_id(two.sprite_instance_id) as Sprite3D
		speed_ok = absf(measured_speed-320) < .05 and two.source_point.y == 315 and two.velocity_source == Vector2(320,0)
		var foot: Vector3 = tree.current_scene.player.source_to_world(two.source_point)
		speed_ok = speed_ok and sprite != null and sprite.texture.resource_path == two.texture_path and sprite.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST
		speed_ok = speed_ok and absf(sprite.global_position.y-foot.y-56.0/(60*cos(deg_to_rad(38)))) < .0001
	check_result("controlled_gem_native_sprite_moves320px_per_second_with_original_texture_clock_and_explicit56px_height",emitted and speed_ok,
		{"initial":initial,"moved":moved,"fixture":"Controlled outward emit with caster AI frozen; projectile owns independent physics."})
	for code: Key in [KEY_F2,KEY_F1]:
		helper.tap(code)
		await wait_for(tree,"flight_freeze_settles",.035)
		var before: Dictionary = ranged_snapshot(tree)
		await wait_for(tree,"flight_pause_or_inspection_freezes",.12)
		var frozen: Dictionary = gems.capture_state()
		check_result("actual_"+("F2_pause" if code == KEY_F2 else "F1_inspection")+"_freezes_flight_position_lifetime_source_frame_and_CDs",frozen.frozen
			and ranged_snapshot(tree) == before,{"frozen":frozen})
		helper.tap(code)
	var menu: PopupMenu = tree.current_scene.get_node("Interface/AudioMenu").get_popup()
	menu.popup(Rect2i(180,120,180,160))
	await wait_for(tree,"flight_menu_freeze_settles",.035)
	var menu_before: Dictionary = ranged_snapshot(tree)
	await wait_for(tree,"flight_native_menu_freezes",.12)
	var menu_ok: bool = ranged_snapshot(tree) == menu_before and gems.capture_state().frozen
	menu.hide()
	helper.tap(KEY_B)
	await wait_for(tree,"flight_bag_freeze_settles",.035)
	var bag_before: Dictionary = ranged_snapshot(tree)
	await wait_for(tree,"flight_bag_freezes",.12)
	check_result("native_menu_and_actual_B_freeze_flying_gem_without_consuming_its_lifetime",menu_ok and gems.capture_state().frozen
		and tree.current_scene.get_node("FirstLoot").capture_state().bag_open and ranged_snapshot(tree) == bag_before)
	helper.tap(KEY_B)
	var ended: Dictionary = await wait_for(tree,"source615ms_flight_expires_after_resume",.7,
		func(_m:Node,row:Dictionary):return int(row.fight.projectiles.expired_count) > expired)
	check_result("flight_expires_exactly_at615ms_after196_8px_without_harming_hero",ended.reached and gems.capture_state().active_count == 0
		and gems.last_ended.reason == "expired" and gems.last_ended.age_ms == 615
		and gems.last_ended.source_point.distance_to(Vector2(696.8,315)) < .02 and fight.player_hp == 100,
		{"end":gems.capture_state()})


func dodge_and_guard(tree: SceneTree) -> void:
	var fight: Node = await prepare(tree)
	var gems: Node = projectile(tree)
	var hits: int = gems.hit_count
	helper.tap(KEY_SPACE)
	var airborne: Dictionary = await wait_for(tree,"real_Space_reaches_airborne_height_above35",.5,
		func(m:Node,_row:Dictionary):return m.player.jump_motion.height_pixels > 40)
	var emitted: bool = gems.emit(Vector2(500,315),-1)
	var passed: Dictionary = await wait_for(tree,"gem_crosses_ground_foot_below_actual_jump",.35,
		func(m:Node,row:Dictionary):return int(row.fight.projectiles.active_count) == 1 and row.fight.projectiles.active[0].source_point.x < point(m).x-25)
	check_result("actual_Space_above35px_lets_same_lane_gem_cross_without_damage_or_consumption",airborne.reached and emitted and passed.reached
		and fight.player_hp == 100 and gems.hit_count == hits and gems.capture_state().active[0].last_ignored_contact == "airborne",
		{"airborne_height":tree.current_scene.player.jump_motion.height_pixels,"crossed":passed,"fixture":"Only one same-lane60px incoming flight is emitted after real jump height exceeds40px."})
	fight = await prepare(tree)
	gems = projectile(tree)
	emitted = gems.emit(Vector2(620,315),-1)
	await wait_for(tree,"actual_W_leaves_projectile_depth_lane",.62,Callable(),[KEY_W])
	check_result("actual_W_depth_dodge_avoids_moving_gem_without_vertical_teleport",emitted and fight.player_hp == 100
		and point(tree.current_scene).y < 296 and gems.capture_state().active_count == 0 and gems.last_ended.reason == "expired",
		{"position":point(tree.current_scene),"flight":gems.capture_state()})
	for facing: int in [1,-1]:
		fight = await prepare(tree,180,facing)
		gems = projectile(tree)
		hits = gems.hit_count
		helper.key(KEY_C,true)
		emitted = gems.emit(Vector2(500,315),-1)
		var impact: Dictionary = await wait_for(tree,"controlled_flight_contacts_actual_guard",.4,
			func(_m:Node,row:Dictionary):return int(row.fight.projectiles.hit_count) > hits)
		var front: bool = facing == 1
		check_result("actual_"+("front_C_blocks10_to6" if front else "back_C_takes_full10_and_cancels_guard"),emitted and impact.reached
			and fight.player_hp == (94 if front else 90) and gems.last_hit.blocked == front and gems.last_hit.damage == (6 if front else 10)
			and (guard.capture_state().active and fight.hero_hurt_remaining == 0 if front else not guard.capture_state().active and fight.hero_hurt_remaining > 0),
			{"impact":impact,"projectiles":gems.capture_state(),"fixture":"Controlled incoming flight; actual C owns defense/facing and real collision calls damage."})
		helper.key(KEY_C,false)
		await wait_for(tree,"consumed_guard_flight_cannot_hit_again",.26)
		if front:
			check_result("one_guarded_projectile_is_consumed_once_across_full_reaction_recovery",fight.player_hp == 94 and gems.hit_count == hits+1
				and gems.capture_state().active_count == 0 and gems.last_ended.hit_count == 1,{"after":gems.capture_state()})


func terminal_checks(tree: SceneTree) -> void:
	var fight: Node = await prepare(tree)
	var gems: Node = projectile(tree)
	fight.qa_freeze_enemy = false
	var pending_cast: Dictionary = await wait_for(tree,"AI_cast_in_progress_before_R",1.0,
		func(_m:Node,row:Dictionary):return row.fight.cast_active and float(row.fight.cast_elapsed_ms) >= 80)
	var emitted: bool = gems.emit(Vector2(700,315),1)
	guard.cooldown_remaining = 1
	skill.cooldown_remaining = 1
	potion.cooldown_remaining = 1
	await actual_reset(tree,"active_flight_R")
	check_result("actual_R_clears_flying_gem_real_pending_cast_and_three_CDs_and_restores_local_HP",pending_cast.reached and emitted
		and gems.capture_state().active_count == 0 and gems.last_clear_reason == "reset" and not fight.cast_active
		and fight.player_hp == 100 and fight.enemy_hp == 100 and guard.cooldown_remaining == 0 and skill.cooldown_remaining == 0 and potion.cooldown_remaining == 0,
		{"pending_cast":pending_cast,"state":fight.capture_state()})
	fight = await prepare(tree)
	gems = projectile(tree)
	fight.player_hp = 6 # Explicit non-KO initial HP; the real projectile must own lethal lock acquisition.
	fight._persist()
	var far: bool = gems.emit(Vector2(650,315),-1)
	var lethal: bool = gems.emit(Vector2(500,315),-1)
	var ko: Dictionary = await wait_for(tree,"real_lethal_gem_clears_another_flying_gem",.4,
		func(_m:Node,row:Dictionary):return int(row.fight.player_hp) == 0)
	var ko_ok: bool = ko.reached and gems.capture_state().active_count == 0 and gems.last_clear_reason == "player_ko"
	await actual_reset(tree,"lethal_gem_R_retry")
	check_result("real_gem_KO_clears_other_flight_without_reentrant_retirement_and_actual_R_recovers_controls",far and lethal and ko_ok
		and fight.player_hp == 100 and not tree.current_scene.player.ui_input_blocked and point(tree.current_scene).distance_to(Vector2(176,320)) < .1,
		{"KO":ko,"after_retry":fight.capture_state(),"fixture":"Only initial6HP and two incoming flights are staged; lethal contact acquires actual KO ownership."})
	fight = await prepare(tree,140)
	gems = projectile(tree)
	fight.enemy_hp = 44 # Explicit final-hit condition; actual Z must cause the defeat.
	fight._persist()
	emitted = gems.emit(Vector2(620,315),-1)
	helper.tap(KEY_Z)
	var defeated: Dictionary = await wait_for(tree,"actual_Z_defeats_caster_with_gem_in_flight",.5,
		func(_m:Node,row:Dictionary):return row.fight.cleared)
	check_result("actual_caster_defeat_clears_flight_before_it_can_damage_hero",emitted and defeated.reached
		and fight.enemy_hp == 0 and fight.player_hp == 100 and gems.capture_state().active_count == 0 and gems.last_clear_reason == "caster_defeated",
		{"defeat":defeated,"fixture":"Only initial44 enemyHP,140px positions and one pending flight; actual Z causes death, source time unchanged."})
	fight = await prepare(tree)
	gems = projectile(tree)
	stage_actor(tree.current_scene.player,Vector2(38,320),-1)
	emitted = gems.emit(Vector2(700,320),1)
	var old_id: int = gems.get_instance_id()
	var left: Dictionary = await wait_for(tree,"actual_A_leaves_gallery_with_gem_in_flight",2.5,ready_scene(DEPTHS),[KEY_A])
	if left.reached:
		tree.current_scene.get_node("TowerBoss").qa_freeze_enemy = true
	check_result("actual_scene_exit_removes_projectile_controller_and_world_visuals_without_orphans",emitted and left.reached
		and not is_instance_id_valid(old_id) and tree.root.find_children("StoneGemVisuals","Node3D",true,false).is_empty(),
		{"exit":left,"fixture":"Only initial portal position and outward flight; actual A uses the established return route."})
	tree.change_scene_to_file(GALLERY) # Explicit reentry fixture; the previous actual departure already tested teardown.
	await wait_for(tree,"fixture_reentry_before_full_ranged_AI_victory",2.5,ready_scene(GALLERY))


func close_punch(tree: SceneTree) -> void:
	var fight: Node = await prepare(tree,60)
	var casts: int = fight.casts_started
	var hits: int = fight.event_counters.enemy_hits
	fight.qa_freeze_enemy = false
	var punch: Dictionary = await wait_for(tree,"new_ranged_AI_still_chooses_close_original_punch",1.4,
		func(_m:Node,row:Dictionary):return int(row.fight.event_counters.enemy_hits) > hits)
	check_result("within62px_AI_preserves_original645ms_punch14_instead_of_casting",punch.reached and fight.player_hp == 86
		and fight.casts_started == casts and fight.enemy.animation_name == "attack",{"contact":punch})
	fight.qa_freeze_enemy = true


func ranged_flow(tree: SceneTree, progress: Node) -> void:
	progress.set_process(true)
	await cast_and_contact(tree)
	await locked_facing_and_interrupt(tree)
	await flight_motion_and_freezes(tree)
	await dodge_and_guard(tree)
	await close_punch(tree)
	await terminal_checks(tree)
	await actual_victory(tree,progress)


func run(root: Node, candidate: String = "R4/07") -> Dictionary:
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
	if main == null or main.scene_file_path != HARBOR or progress == null or guard == null or skill == null or potion == null or guard.capture_state().active:
		check_result("fresh_integrated_harbor_with_inactive_guard_available",false)
		return {"checks":checks.size(),"failed":checks,"render_cases":render_cases.size()}
	var formal_before: Dictionary = helper.profile_guard()
	var original_meta: Dictionary = states.snapshot_meta(tree)
	var gallery_present: bool = tree.has_meta("doll_gallery_state")
	var gallery_meta: Variant = tree.get_meta("doll_gallery_state") if gallery_present else null
	if gallery_meta is Dictionary:
		gallery_meta = gallery_meta.duplicate(true)
	var original_profile: Dictionary = states.snapshot_fields(progress,States.PROFILE_FIELDS)
	var original_guard: Dictionary = states.snapshot_fields(guard,Guards.GUARD_FIELDS)
	var original_skill: Dictionary = states.snapshot_fields(skill,States.SKILL_FIELDS)
	var original_potion: Dictionary = states.snapshot_fields(potion,Supplies.POTION_FIELDS)
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
	qa_path = "user://qa/ranged_live_"+str(Time.get_ticks_usec())+"_"+str(Time.get_unix_time_from_system()).replace(".","_")+".json"
	var configured: bool = progress.configure_storage(qa_path,false)
	for key: String in ["first_encounter_state","tower_boss_state","doll_gallery_state"]:
		if tree.has_meta(key):
			tree.remove_meta(key)
	tree.set_meta("route_hero_hp",100)
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
	helper.key(KEY_C,false)
	check_result("unique_default_available_QA_profile_isolated_before_any_route_interaction",configured and progress.storage_path == qa_path \
		and progress.progress.quest_stage == "available" and progress.progress.coins == 0 and progress._pending_bundle.is_empty() \
		and helper.profile_guard() == formal_before,{"QA_path":qa_path})
	if configured:
		asset_checks()
		tree.change_scene_to_file(GALLERY) # Explicit arena entry fixture; route gates already have frozen R4/06 proof.
		var ready: Dictionary = await wait_for(tree,"fixture_ranged_gallery_ready",2.5,ready_scene(GALLERY))
		check_result("ranged_gallery_fixture_loads_new_cast_controller_and_independent_projectiles",ready.reached
			and tree.current_scene.get_node_or_null("GalleryEncounter/GemProjectiles") != null,{"entry":ready})
		if ready.reached:
			await ranged_flow(tree,progress)
	# Depart the test encounter before restoring metadata: its _exit_tree persists state.
	helper.release_motion()
	for code: Key in [KEY_C,KEY_Z,KEY_H]:
		helper.key(code,false)
	guard.end_guard("qa_cleanup")
	progress.set_process(false)
	guard.set_process(false)
	guard.set_physics_process(false)
	skill.set_process(false)
	potion.set_process(false)
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
	states.restore_fields(guard,original_guard)
	states.restore_fields(skill,original_skill)
	states.restore_fields(potion,original_potion)
	guard._refresh_hud()
	skill._refresh_hud()
	potion._refresh_hud()
	progress.set_process(process_before[0])
	guard.set_process(process_before[1])
	guard.set_physics_process(process_before[2])
	skill.set_process(process_before[3])
	potion.set_process(process_before[4])
	check_result("cleanup_restores_profile_pending_all_four_fight_metas_actor_preferences_and_three_runtimes",cleanup.reached \
		and states.snapshot_fields(progress,States.PROFILE_FIELDS) == original_profile and states.snapshot_meta(tree) == original_meta \
		and meta_snapshot(tree,"doll_gallery_state") == {"present":gallery_present,"value":gallery_meta} \
		and states.snapshot_fields(guard,Guards.GUARD_FIELDS) == original_guard and states.snapshot_fields(skill,States.SKILL_FIELDS) == original_skill \
		and states.snapshot_fields(potion,Supplies.POTION_FIELDS) == original_potion and main.player.capture_state() == original_actor \
		and main.player.spawn_position == original_spawn and main.player.ui_input_blocked == original_blocked \
		and preferences.settings(main) == original_preferences and guard.main == main and not main.player.guard_active,{"cleanup":cleanup})
	var formal_after: Dictionary = helper.profile_guard()
	check_result("formal_primary_backup_and_both_temporary_files_remain_byte_unchanged",formal_before == formal_after,{"before":formal_before,"after":formal_after})
	var failed: Array = checks.filter(func(c:Dictionary):return not c.pass)
	var report: Dictionary = {"candidate":candidate,"checks":checks,"failed":failed,"records":records,"screenshots":screenshots,
		"duration_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,"QA_storage_path":qa_path,
		"formal_profile_before":formal_before,"formal_profile_after":formal_after,"qa_source_sha256":get_script().source_code.sha256_text(),
		"gallery_source_sha256":FileAccess.get_file_as_string("res://scripts/gallery_encounter.gd").sha256_text(),
		"rules_sha256":FileAccess.get_file_as_string("res://data/gallery_encounter_rules.json").sha256_text(),
		"source_reference_sha256":FileAccess.get_sha256(RANGED_SOURCE),"projectile_source_sha256":FileAccess.get_file_as_string("res://scripts/stone_gem_projectiles.gd").sha256_text(),
		"note":"Focused ranged adaptation proof. Source six action objects stay exact; new cast1000ms and13 gem frames615ms preserve source timing. Physical ranged dispatch/speed/range/placement/collision are explicitly adapted. Actual AI cast, original physical punch and a full100HP actual-input victory are separate from controlled emit/initial position/HP fixtures. Already emitted gems run independently of caster QA freeze, survive nonlethal caster hurt, and clear on KO/defeat/reset/exit. No complete old near-fight matrix is duplicated. Buffer PNG reads, complete numeric saved equality and guarded metadata reads avoid prior QA-only warnings. Profile/pending, all fight session metadata, actor/preferences and all three runtime states restore after combat exit; human four files remain byte unchanged. Every wait is bounded."}

	var path: String = "res://docs/"+output_prefix+"_ranged_checks.json"
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report,"  "))
		output.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases.size(),"recorded_rows":records.size(),"report":path}
