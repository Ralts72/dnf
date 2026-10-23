extends "res://tools/r4/gallery_checks.gd"
## R4/08 focused statue wake/magic/continuous corridor proof. Native execution is parent-owned.

const STATUE: String = "res://scenes/tower_statue_gallery.tscn"
const STATUE_SOURCE: String = "res://docs/r4_swordman_statue_source_reference.json"
const STATUE_LAYOUT: String = "res://docs/r4_statue_gallery_layout_reference.json"


func fight_at(main: Node) -> Node:
	var statue: Node = main.get_node_or_null("StatueEncounter")
	return statue if statue != null else super.fight_at(main)


func ready_scene(path: String) -> Callable:
	var base: Callable = super.ready_scene(path)
	return func(main:Node,row:Dictionary):return base.call(main,row) and (path != STATUE or main.get_node_or_null("StatueEncounter") != null)


func observe(tree: SceneTree, label: String) -> Dictionary:
	var row: Dictionary = super.observe(tree,label)
	if not row.is_empty():
		row["camera"] = Vector2(tree.current_scene.framing.offset_x,tree.current_scene.framing.offset_y)
	return row


func screenshot(tree: SceneTree, name: String) -> void:
	var path: String = "res://docs/previews/"+output_prefix+"_statue_"+name+".png"
	screenshots[name] = {"path":path,"save_error":tree.current_scene.get_viewport().get_texture().get_image().save_png(path),"scene":tree.current_scene.scene_file_path}


func asset_checks() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STATUE_SOURCE))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_statue_r1.json"))
	var source_ok: bool = source.source_scripts.size() == 17 and data.animations.size() == 8
	var pvf: Array = []
	for entry: Dictionary in source.source_scripts:
		var exact: bool = entry.crc_matches and FileAccess.get_sha256("res://"+entry.raw_reference) == entry.sha256_decoded
		source_ok = source_ok and exact
		pvf.append({"path":entry.pvf_path,"CRC_verified_retained_bytes_exact":exact})
	for action: String in data.animations:
		var frames: Array = data.animations[action].frames
		var clock: float = 0
		for i: int in frames.size():
			clock += float(frames[i].duration_ms)
			source_ok = source_ok and float(frames[i].duration_ms) == float(source.action_clocks[action].duration_ms[i])
		source_ok = source_ok and clock == float(source.action_clocks[action].total_ms)
	check_result("seventeen_CRC_sources_eight_original_clocks_and_magic_dark_ATK_are_preserved_without_guessed_voice_or_lightning",source_ok
		and data.animations.wakeup.frames.size() == 12 and source.action_clocks.wakeup.total_ms == 2400
		and data.animations.attack.frames.size() == 18 and source.action_clocks.attack.total_ms == 1200
		and source.action_clocks.down.total_ms == 860 and source.identity.source_attack_type == "magic" and source.identity.source_element == "dark"
		and not source.audio.audio_exported,{"PVF":pvf,"source_clocks":source.action_clocks,"unimplemented_events":source.unimplemented_source_events})
	var native_ok: bool = true
	var images: Array = []
	for group: String in ["source_crops","derived_composites"]:
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
	var rebuilt_ok: bool = source.derived_composites.size() == 48
	var bounds_ok: bool = true
	var bounds_cases: int = 0
	for entry: Dictionary in source.derived_composites:
		var crop: Image = raw_png(entry.source_crop)
		var expected: Image = Image.create(entry.size[0],entry.size[1],false,Image.FORMAT_RGBA8)
		expected.fill(Color(0,0,0,0))
		expected.blit_rect(crop,Rect2i(Vector2i.ZERO,crop.get_size()),Vector2i(entry.composite_paste_offset[0],entry.composite_paste_offset[1]))
		var actual: Image = raw_png(entry.texture)
		rebuilt_ok = rebuilt_ok and expected.get_data() == actual.get_data()
		var used: Rect2i = actual.get_used_rect()
		for edge: Vector2 in [Vector2(36,-148),Vector2(1244,532)]:
			for facing: int in [1,-1]:
				var left: float = edge.x-edge.y+float(used.position.x-97) if facing == 1 else edge.x-edge.y-float(used.end.x-97)
				var right: float = edge.x-edge.y+float(used.end.x-97) if facing == 1 else edge.x-edge.y-float(used.position.x-97)
				var top: float = 351+used.position.y-123
				var bottom: float = 351+used.end.y-123
				bounds_ok = bounds_ok and left >= 0 and right <= 896 and top >= 0 and bottom <= 404
				bounds_cases += 1
	check_result("eighty_three_native_PNGs_and_all48_source_offset_composites_keep_complete_RGBA",native_ok and images.size() == 83 and rebuilt_ok,{"images":images})
	check_result("all48_alpha_bounds_fit_both_facings_at_both_extended_map_edges",bounds_ok and bounds_cases == 192
		and Vector2(source.canvas_size[0],source.canvas_size[1]) == Vector2(217,151)
		and Vector2(source.foot_anchor[0],source.foot_anchor[1]) == Vector2(97,123),
		{"logical_bounds_cases":bounds_cases,"policy":"Alpha>0 logical source bounds, separate from native83RGBA proof; not a duplicate full GPU pose matrix."})


func actual_entry(tree: SceneTree, progress: Node) -> bool:
	progress.set_process(false)
	tree.change_scene_to_file(GALLERY) # Initial region is a fixture; the new right passage itself uses actual input.
	var gallery: Dictionary = await wait_for(tree,"fixture_previous_gallery_for_new_route",2.5,ready_scene(GALLERY))
	if not gallery.reached:
		check_result("previous_gallery_for_route_available",false,gallery)
		return false
	var fight: Node = tree.current_scene.get_node("GalleryEncounter")
	fight.qa_freeze_enemy = true
	stage_actor(tree.current_scene.player,Vector2(840,320),1)
	var old_gallery: Dictionary = tree.get_meta("doll_gallery_state").duplicate(true)
	var rejected: Array = []
	for bad: Variant in [1,"true"]:
		var invalid: Dictionary = old_gallery.duplicate(true)
		invalid.cleared = bad
		tree.set_meta("doll_gallery_state",invalid)
		await wait_for(tree,"actual_D_rejects_nonboolean_gallery_receipt",.23,Callable(),[KEY_D])
		rejected.append(tree.current_scene.scene_file_path == GALLERY and not tree.current_scene.get_node("WorldTravel").capture_state().statue_gallery_unlocked)
	var clear_receipt: Dictionary = old_gallery.duplicate(true)
	clear_receipt.cleared = true
	tree.set_meta("doll_gallery_state",clear_receipt)
	var entered: Dictionary = await wait_for(tree,"strict_session_clear_actual_D_enters_long_statue_gallery",2.5,ready_scene(STATUE),[KEY_D])
	tree.set_meta("doll_gallery_state",old_gallery) # The gate fixture must not become unrelated encounter progress.
	progress.set_process(true)
	var good: bool = entered.reached
	if good:
		var statue: Node = tree.current_scene.get_node("StatueEncounter")
		statue.qa_freeze_enemy = true
		good = tree.current_scene.player.spawn_position.distance_to(Vector2(176,320)) < .01 \
			and point(tree.current_scene).distance_to(Vector2(176,320)) <= 4 and statue.enemy_hp == 140 \
			and statue.enemy.world_to_source(statue.enemy.position).distance_to(Vector2(960,300)) < .1 \
			and statue.phase == "dormant" and not statue.awakened
		screenshot(tree,"arrival")
	check_result("new_route_requires_strict_current_gallery_clear_and_actual_D_arrives_safely_in_dormant_long_corridor",good
		and rejected.size() == 2 and rejected.all(func(v:bool):return v),{"entry":entered,"bad_types_rejected":rejected,
		"fixture":"Initial prior-region position and strict clear receipt only; actual D uses150ms route hold and fades. Real prior encounter state is restored after its exit."})
	return good


func native_world_and_long_pan(tree: SceneTree) -> void:
	var main: Node = tree.current_scene
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STATUE_LAYOUT))
	var content: Node3D = main.world.get_node("TowerStatueGalleryWorld")
	var native_ok: bool = true
	var decor: int = 0
	var rows: Array = []
	for entry: Dictionary in layout.collision_audit.meshes:
		var node: MeshInstance3D = content.find_child(entry.node,true,false) as MeshInstance3D
		var exact: bool = node != null
		var actual := AABB()
		if exact:
			actual = node.global_transform * node.get_aabb()
			var lower := Vector3(entry.world_aabb_min[0],entry.world_aabb_min[1],entry.world_aabb_min[2])
			var upper := Vector3(entry.world_aabb_max[0],entry.world_aabb_max[1],entry.world_aabb_max[2])
			exact = actual.position.distance_to(lower) < .00002 and actual.end.distance_to(upper) < .00002
			if not entry.below_foot_support:
				decor += 1
				var left: float = 448+60*(actual.position.x-.18)
				var right: float = 448+60*(actual.end.x+.18)
				var top: float = 159+(actual.position.z+1.6-.18)*60*sin(deg_to_rad(38))
				var bottom: float = 159+(actual.end.z+1.6+.18)*60*sin(deg_to_rad(38))
				exact = exact and (right < 36 or left > 1244 or bottom < 245 or top > 345)
			else:
				exact = exact and actual.end.y < .025
		native_ok = native_ok and exact
		rows.append({"node":entry.node,"native_world_AABB_and_expanded_walk_clearance":exact})
	var cards_ok: bool = true
	for entry: Dictionary in layout.source_cards:
		var card: Sprite3D = content.find_child(entry.node,true,false) as Sprite3D
		cards_ok = cards_ok and card != null and card.texture.resource_path == entry.texture and card.texture.get_size() == Vector2(630,355) \
			and not card.flip_h and not card.flip_v and is_equal_approx(card.pixel_size,1.0/60.0) and card.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST
	check_result("native36_mesh_AABBs34_solids_clear_expanded_long_walk_three_full_source_windows_and_zero_shapes",native_ok and cards_ok and decor == 34
		and content.find_children("*","MeshInstance3D",true,false).size() == 36 and content.find_children("*","Sprite3D",true,false).size() == 3
		and main.route_obstacles.capture_state().obstacle_count == 0,{"native_meshes":rows,"source_windows_exact":cards_ok})
	var floor_ok: bool = true
	var edges: Array = []
	for edge: Vector2 in [Vector2(36,345),Vector2(1244,345)]:
		stage_actor(main.player,edge,1)
		main.framing.advance(0,true)
		await wait_for(tree,"extended_edge_native_lower_ground",.06)
		var image: Image = main.render_viewport.get_texture().get_image()
		var alpha: float = 1
		for x: int in [5,16,879,890]:
			for y: int in [386,393,399]:
				alpha = minf(alpha,image.get_pixel(x*image.get_width()/896,y*image.get_height()/404).a)
		var expected_x: float = -148 if edge.x < 100 else 532
		floor_ok = floor_ok and alpha > .98 and absf(main.framing.offset_x-expected_x) < .01 and absf(main.framing.offset_y-37) < .01
		edges.append({"ground":edge,"camera":Vector2(main.framing.offset_x,main.framing.offset_y),"lower_ground_min_alpha":alpha})
		screenshot(tree,"edge_left" if edge.x < 100 else "edge_right")
	stage_actor(main.player,Vector2(36,345),1)
	main.framing.advance(0,true)
	var first_record: int = records.size()
	var crossed: Dictionary = await wait_for(tree,"actual_Shift_D_runs_continuous1280px_corridor",7.1,
		func(m:Node,_row:Dictionary):return point(m).x >= 1243.9,[KEY_D,KEY_SHIFT])
	var camera_settled: Dictionary = await wait_for(tree,"render_interpolated_camera_catches_final_physics_foot",.15,
		func(m:Node,_row:Dictionary):return absf(m.framing.offset_x-532) < .05)
	var smooth: bool = true
	for i: int in range(first_record+1,records.size()):
		var previous: Dictionary = records[i-1]
		var current: Dictionary = records[i]
		smooth = smooth and absf(current.camera.x-previous.camera.x) <= 190.0*maxf(0,current.seconds-previous.seconds)+4.0
	var left_cap: float = main.framing.offset_x
	check_result("native_lower_ground_covers_both_extended_pans_and_real_dash_camera_follows_smoothly_to532",floor_ok and crossed.reached and camera_settled.reached
		and smooth and absf(left_cap-532) < .1 and point(main).x-main.framing.offset_x <= 713,
		{"edge_samples":edges,"actual_run":crossed,"final_render_camera_settled":camera_settled,"camera_steps_bounded_by_actual_time":smooth,
		"policy":"Lower ground alpha only; transparent upper sky is not classified as a void. Independent source alpha pose bounds checked separately."})


func wake_snapshot(fight: Node) -> Dictionary:
	return {"phase":fight.phase,"awakened":fight.awakened,"wake_ms":fight.wake_elapsed_ms,"death_ms":fight.death_elapsed_ms,
		"enemy_position":fight.enemy.position,"frame":fight.enemy.frame_index,"hero_hp":fight.player_hp,"enemy_hp":fight.enemy_hp,
		"CDs":[guard.cooldown_remaining,skill.cooldown_remaining,potion.cooldown_remaining]}


func wake_checks(tree: SceneTree) -> void:
	await actual_reset(tree,"first_real_wake")
	var main: Node = tree.current_scene
	var fight: Node = main.get_node("StatueEncounter")
	fight.qa_freeze_enemy = false
	await wait_for(tree,"far_arrival_stays_dormant",.12)
	check_result("safe_far_arrival_stays_dormant_without_chasing_or_invented_audio",fight.phase == "dormant" and not fight.awakened
		and fight.wake_elapsed_ms == 0 and fight.enemy.animation_name == "stay" and fight.enemy.frame_index == 0
		and fight.enemy.world_to_source(fight.enemy.position).distance_to(Vector2(960,300)) < .01 and fight._contact_audio == null)
	var serial: int = fight.wake_trigger_count
	var wake_first_record: int = records.size()
	var waking: Dictionary = await wait_for(tree,"actual_run_approaches_and_triggers_wake",3.4,
		func(_m:Node,row:Dictionary):return row.fight.phase == "waking",[KEY_D,KEY_SHIFT])
	await wait_for(tree,"actual_run_near_statue_during_wake",1.1,
		func(m:Node,_row:Dictionary):return point(m).x >= 880,[KEY_D,KEY_SHIFT])
	helper.tap(KEY_X)
	await wait_for(tree,"real_X_active_window_is_harmless_during_wake",.67)
	check_result("actual_approach_triggers_once_and_real_near_X_cannot_damage_waking_statue_or_receive_damage",waking.reached
		and fight.phase == "waking" and not fight.awakened and fight.wake_trigger_count == serial+1
		and fight.enemy_hp == 140 and fight.player_hp == 100 and fight.enemy.animation_name == "wakeup"
		and fight.enemy.world_to_source(fight.enemy.position).distance_to(Vector2(960,300)) < .01,
		{"trigger":waking,"state":fight.capture_state(),"fixture":"None after ordinary R; approach, closeness and X are actual inputs."})
	screenshot(tree,"waking")
	var freezes: Array = []
	for mode: String in ["pause","menu","bag"]:
		var menu: PopupMenu = main.get_node("Interface/AudioMenu").get_popup()
		if mode == "pause":
			helper.tap(KEY_F2)
		elif mode == "menu":
			menu.popup(Rect2i(180,120,180,160))
		else:
			helper.tap(KEY_B)
		await wait_for(tree,"wake_freeze_settles_"+mode,.035)
		var before: Dictionary = wake_snapshot(fight)
		await wait_for(tree,"wake_clock_frozen_"+mode,.12)
		var open: bool = main.player.paused if mode == "pause" else (menu.visible if mode == "menu" else main.get_node("FirstLoot").capture_state().bag_open)
		freezes.append({"mode":mode,"pass":open and wake_snapshot(fight) == before,"snapshot":before})
		if mode == "pause":
			helper.tap(KEY_F2)
		elif mode == "menu":
			menu.hide()
		else:
			helper.tap(KEY_B)
	check_result("actual_F2_native_menu_and_B_freeze_wake_source_pose_foot_HP_and_runtime_clocks",freezes.all(func(row:Dictionary):return row.pass),{"freezes":freezes})
	var awake: Dictionary = await wait_for(tree,"all_twelve_source200ms_wake_records_finish",1.5,
		func(_m:Node,row:Dictionary):return row.fight.awakened)
	fight.qa_freeze_enemy = true
	var wake_frames: Dictionary = {}
	var source_wake_frames_match: bool = true
	for index: int in range(wake_first_record,records.size()):
		var row: Dictionary = records[index]
		if row.fight.get("phase","") == "waking":
			var expected_frame: int = mini(11,int(floor(float(row.fight.wake_elapsed_ms)/200.0)))
			wake_frames[expected_frame] = true
			source_wake_frames_match = source_wake_frames_match and absf(float(row.fight.enemy_action_elapsed_ms)-200.0*expected_frame) < .001
	check_result("only_complete2400ms_wake_sets_strict_session_awakened_receipt",awake.reached and fight.wake_elapsed_ms == 2400
		and fight.phase == "awake" and fight.wake_trigger_count == serial+1 and fight.enemy_hp == 140 and fight.player_hp == 100
		and source_wake_frames_match and wake_frames.size() == 12
		and tree.has_meta("statue_gallery_state") and tree.get_meta("statue_gallery_state").awakened is bool and tree.get_meta("statue_gallery_state").awakened,
		{"awake":awake,"witnessed_source_wake_frames":wake_frames.keys(),"physics_and_source_frame_clock_match":source_wake_frames_match})
	screenshot(tree,"awake")


func depart_at_portal(tree: SceneTree, label: String) -> Dictionary:
	stage_actor(tree.current_scene.player,Vector2(38,320),-1) # Explicit portal starting-position fixture.
	var left: Dictionary = await wait_for(tree,label,2.5,ready_scene(GALLERY),[KEY_A])
	if left.reached:
		tree.current_scene.get_node("GalleryEncounter").qa_freeze_enemy = true
	return left


func fixture_reentry(tree: SceneTree, label: String) -> Node:
	tree.change_scene_to_file(STATUE)
	var ready: Dictionary = await wait_for(tree,label,2.5,ready_scene(STATUE))
	if not ready.reached:
		return null
	var fight: Node = tree.current_scene.get_node("StatueEncounter")
	fight.qa_freeze_enemy = true
	return fight


func wake_session_checks(tree: SceneTree) -> void:
	var left: Dictionary = await depart_at_portal(tree,"awake_actual_A_exit")
	var fight: Node = await fixture_reentry(tree,"fixture_reentry_keeps_completed_wake")
	if fight == null:
		check_result("completed_wake_reentry_available",false)
		return
	check_result("completed_wake_persists_across_actual_exit_and_safe_reentry_without_replaying_half_attack",left.reached and fight.awakened
		and fight.phase == "awake" and fight.wake_elapsed_ms == 0 and fight.wake_trigger_count == 0
		and fight.enemy.world_to_source(fight.enemy.position).distance_to(Vector2(960,300)) < 3,
		{"exit":left,"reentry":fight.capture_state(),"fixture":"Only initial portal position and direct reentry; actual A performs departure."})
	await actual_reset(tree,"dormant_R_after_awake")
	check_result("actual_R_resets_awakened_local_HP_both_source_clocks_and_dormant_pose",not fight.awakened and fight.phase == "dormant"
		and fight.wake_elapsed_ms == 0 and fight.death_elapsed_ms == 0 and fight.enemy_hp == 140 and fight.player_hp == 100
		and fight.enemy.animation_name == "stay" and fight.enemy.frame_index == 0 and point(tree.current_scene).distance_to(Vector2(176,320)) < .1)
	stage_actor(tree.current_scene.player,Vector2(730,320),1)
	fight.qa_freeze_enemy = false
	var partial: Dictionary = await wait_for(tree,"partial_real_wake_before_retreat",.6,
		func(_m:Node,row:Dictionary):return row.fight.wake_elapsed_ms >= 250)
	left = await depart_at_portal(tree,"partial_wake_actual_A_exit")
	var saved: Dictionary = tree.get_meta("statue_gallery_state").duplicate(true)
	fight = await fixture_reentry(tree,"partial_wake_fixture_reentry_restarts_dormant")
	if fight == null:
		check_result("partial_wake_reentry_available",false)
		return
	check_result("leaving_mid_wake_keeps_false_receipt_and_reentry_restarts_full_sequence",partial.reached and left.reached
		and saved.awakened is bool and not saved.awakened and not fight.awakened and fight.phase == "dormant" and fight.wake_elapsed_ms == 0,
		{"partial":partial,"saved":saved,"reentry":fight.capture_state(),"fixture":"Initial230px trigger position and portal position only; wake clock and actual A travel run normally."})
	await depart_at_portal(tree,"leave_before_strict_receipt_fixture")
	var invalid: Dictionary = saved.duplicate(true)
	invalid.awakened = 1
	tree.set_meta("statue_gallery_state",invalid)
	fight = await fixture_reentry(tree,"integer_awakened_receipt_is_not_true")
	check_result("integer_awakened_is_rejected_instead_of_coerced_to_true",fight != null and not fight.awakened and fight.phase == "dormant"
		and fight.wake_elapsed_ms == 0,{"fixture":"Only stored awakened=integer1. Reentry must normalize it to strictfalse."})


func awake_fixture(tree: SceneTree, facing: int = 1) -> Node:
	await actual_reset(tree,"typed_contact_fixture")
	var fight: Node = tree.current_scene.get_node("StatueEncounter")
	fight.qa_freeze_enemy = true
	fight.awakened = true
	fight.phase = "awake"
	fight.enemy_mode = "idle"
	fight.enemy.release_pose()
	stage_actor(tree.current_scene.player,Vector2(800,315),facing)
	stage_actor(fight.enemy,Vector2(900,315),-1)
	return fight


func typed_combat(tree: SceneTree) -> void:
	for facing: int in [1,-1]:
		var fight: Node = await awake_fixture(tree,facing)
		var before: int = fight.event_counters.enemy_hits
		var blocks: int = guard.blocked_hits
		helper.key(KEY_C,true)
		fight.qa_freeze_enemy = false
		var impact: Dictionary = await wait_for(tree,"actual_guard_receives_magic_statue_attack",1.5,
			func(_m:Node,row:Dictionary):return int(row.fight.event_counters.enemy_hits) > before)
		var front: bool = facing == 1
		var correct: bool = impact.reached and fight.player_hp == (84 if front else 82)
		if front:
			correct = correct and guard.blocked_hits == blocks+1 and guard.last_hit.damage_kind == "magic"
			correct = correct and guard.last_hit.raw_damage == 18 and guard.last_hit.damage == 16 and guard.last_hit.absorption_percent == 15
			correct = correct and guard.capture_state().active and fight.hero_hurt_remaining == 0
		else:
			correct = correct and not guard.capture_state().active and fight.hero_hurt_remaining > 0
		check_result("actual_"+("front_magic18_guard15percent_gives16" if front else "rear_magic18_bypasses_guard_and_causes_hurt"),correct
			and fight.enemy.animation_name == "attack" and fight.enemy.action_elapsed_ms() >= 400 and fight.enemy.action_elapsed_ms() < 680,
			{"impact":impact,"guard":guard.capture_state(),"fixture":"Only awake state and100px same-lane positions are staged. AI chooses source attack; C and damage contact are native."})
		helper.key(KEY_C,false)
		await wait_for(tree,"whole1200ms_attack_keeps_one_hit_identity",.9)
		if front:
			check_result("whole_live1200ms_statue_attack_has_one_magic_hit_and_source_response_finishes",fight.player_hp == 84
				and fight.event_counters.enemy_hits == before+1 and not guard.capture_state().active,{"after":fight.capture_state()})
		fight.qa_freeze_enemy = true
	var fight: Node = await awake_fixture(tree)
	fight.qa_freeze_enemy = false
	var before: int = fight.event_counters.hero_hits
	var started: Dictionary = await wait_for(tree,"awake_AI_attack_before_actual_X_interrupt",1.0,
		func(_m:Node,row:Dictionary):return row.fight.enemy_mode == "attack" and float(row.fight.enemy_action_elapsed_ms) >= 100)
	helper.tap(KEY_X)
	var hit: Dictionary = await wait_for(tree,"actual_X_interrupts_awake_attack_before_magic_window",.45,
		func(_m:Node,row:Dictionary):return int(row.fight.enemy_hp) < 140)
	check_result("awake_source_attack_can_be_interrupted_by_actual_X_before400ms",started.reached and hit.reached
		and fight.enemy_hp == 122 and fight.player_hp == 100 and fight.event_counters.hero_hits == before+1 and fight.enemy_mode == "hurt",
		{"hit":hit})
	fight.qa_freeze_enemy = true


func actual_statue_victory(tree: SceneTree, progress: Node) -> void:
	await actual_reset(tree,"full_real_statue_fight")
	var fight: Node = tree.current_scene.get_node("StatueEncounter")
	var baseline: Dictionary = fight.capture_state()
	var profile_before: Dictionary = progress.progress.duplicate(true)
	var files_before: Dictionary = states.file_guard(qa_path)
	var saves: int = progress._save_attempts
	var other_metas: Array = [meta_snapshot(tree,"first_encounter_state"),meta_snapshot(tree,"tower_boss_state"),meta_snapshot(tree,"doll_gallery_state")]
	fight.qa_freeze_enemy = false
	var trigger: Dictionary = await wait_for(tree,"full_fight_actual_run_triggers_real_wake",3.5,
		func(_m:Node,row:Dictionary):return row.fight.phase == "waking",[KEY_D,KEY_SHIFT])
	var awake: Dictionary = await wait_for(tree,"full_fight_waits_all2400ms_before_combat",2.8,
		func(_m:Node,row:Dictionary):return row.fight.awakened)
	var casts: Array = []
	# No health/position/awakened writes, manual enemy actions, AI freeze or accelerated clocks after ordinary R above.
	for attempt: int in 7:
		if fight.cleared or fight.player_hp == 0:
			break
		await wait_for(tree,"real_statue_fight_wait_for_free_controls",2.0,
			func(m:Node,row:Dictionary):return row.fight.cleared or int(row.fight.player_hp) == 0 or (not m.player._one_shot and not row.blocked and not m.player.jump_motion.is_active()))
		if fight.cleared or fight.player_hp == 0:
			break
		var difference: Vector2 = fight.enemy.world_to_source(fight.enemy.position)-point(tree.current_scene)
		if absf(difference.y) > 12:
			await wait_for(tree,"real_statue_Q_align_lane",1.5,
				func(m:Node,_row:Dictionary):return absf(fight.enemy.world_to_source(fight.enemy.position).y-point(m).y) <= 10,[KEY_S if difference.y > 0 else KEY_W])
		difference = fight.enemy.world_to_source(fight.enemy.position)-point(tree.current_scene)
		var toward: Key = KEY_D if difference.x >= 0 else KEY_A
		var away: Key = KEY_A if difference.x >= 0 else KEY_D
		if absf(difference.x) > 130:
			await wait_for(tree,"actual_run_into_statue_Q_range",3.0,
				func(m:Node,_row:Dictionary):return absf(fight.enemy.world_to_source(fight.enemy.position).x-point(m).x) <= 130,[toward,KEY_SHIFT])
		elif absf(difference.x) < 123:
			await wait_for(tree,"actual_retreat_to_statue_Q_spacing",1.5,
				func(m:Node,_row:Dictionary):return absf(fight.enemy.world_to_source(fight.enemy.position).x-point(m).x) >= 128 or point(m).x <= 40 or point(m).x >= 1240,[away,KEY_SHIFT])
		await wait_for(tree,"actual_statue_Q_face",.025,Callable(),[toward])
		var serial: int = tree.current_scene.player.attack_instance
		var gap: Vector2 = fight.enemy.world_to_source(fight.enemy.position)-point(tree.current_scene)
		helper.tap(KEY_Q)
		await wait_for(tree,"actual_statue_Q_and_natural_recovery",1.6,
			func(m:Node,row:Dictionary):return row.fight.cleared or int(row.fight.player_hp) == 0 or (not m.player._one_shot and not row.blocked))
		casts.append({"attempt":attempt,"gap":gap,"accepted":tree.current_scene.player.attack_instance == serial+1,"state":fight.capture_state()})
	var victory: bool = trigger.reached and awake.reached and fight.cleared and fight.enemy_hp == 0 and fight.player_hp > 0
	check_result("real_140HP_AI_statue_is_defeated_after_real_2400ms_wake_by_actual_movement_and_Q",victory
		and fight.event_counters.victories == int(baseline.event_counters.victories)+1 and not fight.qa_freeze_enemy,
		{"trigger":trigger,"awake":awake,"casts":casts,"after":fight.capture_state(),"fixture":"None after ordinary R: all wake, position, attacks and source clocks use real movement/Q and native AI."})
	var death_rows: Array = []
	var witnessed_frames: Dictionary = {}
	var source_frames_match: bool = true
	var down_clock: Array = [80,80,100,100,70,430]
	var start: int = Time.get_ticks_usec()
	while float(Time.get_ticks_usec()-start)/1000000.0 < 1.2 and fight.enemy.visible:
		await RenderingServer.frame_post_draw
		observe(tree,"all_six_original_down_frames_before_hide")
		var source_end: float = 0
		var expected_frame: int = down_clock.size()-1
		for index: int in down_clock.size():
			source_end += float(down_clock[index])
			if fight.death_elapsed_ms < source_end:
				expected_frame = index
				break
		witnessed_frames[fight.enemy.frame_index] = true
		source_frames_match = source_frames_match and fight.enemy.frame_index == expected_frame
		death_rows.append({"death_ms":fight.death_elapsed_ms,"frame":fight.enemy.frame_index,"expected_source_frame":expected_frame,"visible":fight.enemy.visible})
	var early_hide: bool = death_rows.any(func(row:Dictionary):return not row.visible and float(row.death_ms) < 860)
	check_result("complete_six_frame860ms_source_down_finishes_before_hiding",victory and not early_hide and not fight.enemy.visible
		and fight.death_elapsed_ms == 860 and fight.death_duration_ms == 860 and source_frames_match and witnessed_frames.size() == 6,
		{"death_samples":death_rows,"witnessed_source_frames":witnessed_frames.keys(),"source_prefix_clock_matches":source_frames_match})
	screenshot(tree,"victory")
	check_result("statue_victory_keeps_profile_all_four_QA_files_and_other_enemy_sessions_unchanged",victory and progress.progress == profile_before
		and progress._save_attempts == saves and states.file_guard(qa_path) == files_before and progress._pending_bundle.is_empty()
		and [meta_snapshot(tree,"first_encounter_state"),meta_snapshot(tree,"tower_boss_state"),meta_snapshot(tree,"doll_gallery_state")] == other_metas
		and tree.has_meta("statue_gallery_state") and tree.get_meta("statue_gallery_state").cleared,
		{"profile":progress.capture_state(),"QA_files_before":files_before,"QA_files_after":states.file_guard(qa_path)})


func without_player_hp(value: Dictionary) -> Dictionary:
	var copy: Dictionary = value.duplicate(true)
	copy.erase("player_hp")
	return copy


func healing_and_return(tree: SceneTree, progress: Node) -> void:
	var fight: Node = tree.current_scene.get_node("StatueEncounter")
	var history: Dictionary = progress._default_progress()
	history.quest_stage = "completed"
	history.objective_cleared = true
	history.reward_granted = true
	history.coins = 30
	history.first_drop.state = "claimed"
	history.inventory["3128"] = 1
	history.inventory["1106"] = 1
	history.equipment.owned["27304"] = true
	var committed: bool = progress._commit(history)
	fight.player_hp = 50 # Explicit initial injury; H must update live controller as well as route/meta.
	fight._persist()
	var before_metas: Dictionary = {}
	for key: String in ["first_encounter_state","tower_boss_state","doll_gallery_state","statue_gallery_state"]:
		before_metas[key] = meta_snapshot(tree,key)
	var uses: int = potion.accepted_uses
	var before_enemy: Dictionary = without_player_hp(tree.get_meta("statue_gallery_state"))
	helper.tap(KEY_H)
	await wait_for(tree,"actual_H_heals_live_statue_region_and_shared_HP",.07)
	var metas_ok: bool = true
	for key: String in before_metas:
		var before: Dictionary = before_metas[key]
		var after: Dictionary = meta_snapshot(tree,key)
		metas_ok = metas_ok and after.present == before.present
		if before.present:
			metas_ok = metas_ok and after.value.player_hp == 85 and without_player_hp(after.value) == without_player_hp(before.value)
	check_result("actual_H_updates_live_statue_HP_route_and_existing_metas_only_preserving_all_enemy_data",committed and potion.accepted_uses == uses+1
		and fight.player_hp == 85 and tree.has_meta("route_hero_hp") and tree.get_meta("route_hero_hp") == 85
		and potion.capture_state().player_hp == 85 and progress.hp_potion_count() == 0 and metas_ok
		and without_player_hp(tree.get_meta("statue_gallery_state")) == before_enemy
		and Supplies.new().exact_saved_value(JSON.parse_string(FileAccess.get_file_as_string(qa_path)),progress.progress),
		{"healing":potion.capture_state(),"meta_data_preserved":metas_ok,"fixture":"Only legal completed-history/one purchased potion and50 initialHP, after no-award victory proof; real H consumes and heals35."})
	var returned: Dictionary = await wait_for(tree,"actual_full_A_dash_back_from_long_corridor",6.5,ready_scene(GALLERY),[KEY_A,KEY_SHIFT])
	if returned.reached:
		tree.current_scene.get_node("GalleryEncounter").qa_freeze_enemy = true
	var main: Node = tree.current_scene
	check_result("actual_return_to_old_gallery_carries85HP_and_reinstates_old_camera_limits",returned.reached
		and main.player.spawn_position.distance_to(Vector2(816,320)) < .01 and point(main).distance_to(Vector2(816,320)) <= 4
		and main.get_node("GalleryEncounter").player_hp == 85 and main.framing.offset_x >= -152 and main.framing.offset_x <= 152
		and point(main).x-main.framing.offset_x >= 0 and point(main).x-main.framing.offset_x <= 896
		and tree.has_meta("statue_gallery_state") and tree.get_meta("statue_gallery_state").cleared and tree.get_meta("statue_gallery_state").awakened,
		{"return":returned,"statue_session":meta_snapshot(tree,"statue_gallery_state")})


func run(root: Node, candidate: String = "R4/08") -> Dictionary:
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
	var statue_before: Dictionary = meta_snapshot(tree,"statue_gallery_state")
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
	qa_path = "user://qa/statue_live_"+str(Time.get_ticks_usec())+"_"+str(Time.get_unix_time_from_system()).replace(".","_")+".json"
	var configured: bool = progress.configure_storage(qa_path,false)
	for key: String in ["first_encounter_state","tower_boss_state","doll_gallery_state","statue_gallery_state"]:
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
		if await actual_entry(tree,progress):
			await native_world_and_long_pan(tree)
			await wake_checks(tree)
			await wake_session_checks(tree)
			await typed_combat(tree)
			await actual_statue_victory(tree,progress)
			await healing_and_return(tree,progress)
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
	check_result("cleanup_restores_profile_pending_all_five_fight_metas_actor_preferences_and_three_runtimes",cleanup.reached \
		and states.snapshot_fields(progress,States.PROFILE_FIELDS) == original_profile and states.snapshot_meta(tree) == original_meta \
		and meta_snapshot(tree,"doll_gallery_state") == {"present":gallery_present,"value":gallery_meta} \
		and meta_snapshot(tree,"statue_gallery_state") == statue_before \
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
		"statue_source_sha256":FileAccess.get_file_as_string("res://scripts/statue_encounter.gd").sha256_text(),
		"rules_sha256":FileAccess.get_file_as_string("res://data/statue_encounter_rules.json").sha256_text(),
		"source_reference_sha256":FileAccess.get_sha256(STATUE_SOURCE),"layout_reference_sha256":FileAccess.get_sha256(STATUE_LAYOUT),
		"note":"Focused statue/long-corridor integration. Source83PNG/48records retain all eight original clocks; source ATK magic/dark is distinct from adapted HP140/damage18/range108/active400..650 and15% magic guard. Actual route entry, walking wake, source-clock freezes and one140HP AI victory use real inputs. Gate metadata types, source positions/awake state for controlled contact, partial-wake portal staging and completed-history potion fixture are explicit. No source atk_darklightning event, MP/formula or random voice is invented. All five fight/session metadata snapshots restore after test-area exit; original profile/pending, actor/preferences and three runtimes restore exactly. PNG reads use buffers, metadata reads preserve absence, persisted comparisons use strict complete numeric equivalence. Human four files stay byte unchanged; every wait is bounded."}

	var path: String = "res://docs/"+output_prefix+"_statue_checks.json"
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report,"  "))
		output.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases.size(),"recorded_rows":records.size(),"report":path}
