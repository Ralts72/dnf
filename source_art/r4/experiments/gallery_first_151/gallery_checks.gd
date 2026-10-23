extends RefCounted
## Focused native gallery proof. A persistent pose_check_job alone runs this file.

const Inputs = preload("res://tools/r3/quest_checks.gd")
const States = preload("res://tools/r4/sharan_checks.gd")
const Supplies = preload("res://tools/r4/supplies_checks.gd")
const Guards = preload("res://tools/r4/guard_checks.gd")
const Preferences = preload("res://tools/r2/travel_checks.gd")
const HARBOR: String = "res://scenes/west_coast_r1.tscn"
const DEPTHS: String = "res://scenes/tower_depths.tscn"
const GALLERY: String = "res://scenes/tower_doll_gallery.tscn"
const SOURCE: String = "res://docs/r4_stonemaster_source_reference.json"
const LAYOUT: String = "res://docs/r4_doll_gallery_layout_reference.json"
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
var output_prefix: String = "r4_06"


func check_result(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check": label, "pass": passed, "details": details})
	render_cases.append({"check": label, "pass": passed})


func point(main: Node) -> Vector2:
	return helper.point(main)


func fight_at(main: Node) -> Node:
	for name: String in ["GalleryEncounter", "TowerBoss", "FirstEncounter"]:
		var fight: Node = main.get_node_or_null(name)
		if fight != null:
			return fight
	return null


func observe(tree: SceneTree, label: String) -> Dictionary:
	var main: Node = tree.current_scene
	if main == null or main.get("player") == null:
		return {}
	var fight: Node = fight_at(main)
	var travel: Node = main.get_node_or_null("WorldTravel")
	var row: Dictionary = {"phase": label, "seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"scene": main.scene_file_path, "position": point(main), "action": main.player.animation_name,
		"frame": main.player.frame_index, "one_shot": main.player._one_shot,
		"blocked": main.player.ui_input_blocked, "paused": main.player.paused,
		"guard": guard.capture_state(), "skill": skill.capture_state(), "potion": potion.capture_state(),
		"fight": fight.capture_state() if fight != null else {}, "travel": travel.capture_state() if travel != null else {}}
	records.append(row)
	return row


func wait_for(tree: SceneTree, label: String, seconds: float, until: Callable = Callable(), keys: Array = []) -> Dictionary:
	helper.release_motion() # C is released explicitly; no guard hold is ended implicitly.
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
	return func(main: Node, row: Dictionary): return main.scene_file_path == path and guard.main == main and skill.main == main and potion.main == main \
		and row.travel.get("phase", "") == "ready" and main.get_node_or_null("FirstLoot") != null \
		and (path != GALLERY or main.get_node_or_null("GalleryEncounter") != null) \
		and (path != DEPTHS or main.get_node_or_null("TowerBoss") != null)


func screenshot(tree: SceneTree, name: String) -> void:
	var path: String = "res://docs/previews/"+output_prefix+"_gallery_"+name+".png"
	screenshots[name] = {"path": path, "save_error": tree.current_scene.get_viewport().get_texture().get_image().save_png(path),
		"scene": tree.current_scene.scene_file_path, "frame_usec": Time.get_ticks_usec()}


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


func actual_reset(tree: SceneTree, label: String) -> void:
	helper.key(KEY_C, false)
	helper.tap(KEY_R)
	await wait_for(tree, label+"_actual_R", .06)


func raw_png(path: String) -> Image:
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


func asset_checks() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	var source_ok: bool = source.source_scripts.size() == 18
	var source_rows: Array = []
	for entry: Dictionary in source.source_scripts:
		var exact: bool = entry.crc_matches and FileAccess.get_sha256("res://"+entry.raw_reference) == entry.sha256_decoded
		source_ok = source_ok and exact
		source_rows.append({"path": entry.pvf_path, "retained_CRC_verified_bytes_exact": exact})
	var audio: Dictionary = source.audio
	var stream: AudioStream = load(audio.path)
	var pcm: Dictionary = audio.runtime_PCM
	var audio_ok: bool = FileAccess.get_sha256(audio.path) == audio.sha256_runtime_ogg \
		and FileAccess.get_sha256("res://"+audio.retained_original) == audio.sha256_source_ogg \
		and audio.PCM_byte_identical and pcm.sha256 == audio.source_PCM.sha256 \
		and int(pcm.bytes) == 156408 and int(pcm.frames) == 39102 and stream != null \
		and absf(stream.get_length()-float(pcm.frames)/float(pcm.sample_rate)) < .02
	check_result("eighteen_retained_CRC_sources_and_original_punch_audio_match_verified_PCM_evidence", source_ok and audio_ok,
		{"sources": source_rows, "native_audio_length": stream.get_length() if stream != null else -1,
		"offline_ffmpeg_PCM_sha256": pcm.sha256, "PCM_evidence_scope": "Both OGGs independently decoded offline before this suite; native loads the same hashed runtime resource."})
	var images: Array = []
	var png_ok: bool = true
	for group: String in ["source_crops", "derived_composites", "environment_outputs"]:
		for entry: Dictionary in source[group]:
			var raw: Image = raw_png(entry.texture)
			var texture: Texture2D = load(entry.texture)
			var native: Image = texture.get_image() if texture != null else null
			var exact: bool = raw != null and native != null and FileAccess.get_sha256(entry.texture) == entry.sha256_png
			if exact and native.is_compressed():
				exact = native.decompress() == OK
			if exact:
				native.convert(Image.FORMAT_RGBA8)
				exact = raw.get_size() == Vector2i(entry.size[0], entry.size[1]) and native.get_size() == raw.get_size() \
					and native.get_data() == raw.get_data() and states.image_hash(native) == entry.sha256_rgba
			png_ok = png_ok and exact
			images.append({"path": entry.texture, "native_full_RGBA_exact": exact})
	check_result("forty_five_native_PNGs_preserve_complete_source_RGBA_including_transparent_RGB", png_ok and images.size() == 45, {"images": images})
	var composite_ok: bool = source.derived_composites.size() == 32
	for entry: Dictionary in source.derived_composites:
		var crop: Image = raw_png(entry.source_crop)
		var expected: Image = Image.create(entry.size[0], entry.size[1], false, Image.FORMAT_RGBA8)
		expected.fill(Color(0,0,0,0))
		expected.blit_rect(crop, Rect2i(Vector2i.ZERO,crop.get_size()), Vector2i(entry.composite_paste_offset[0],entry.composite_paste_offset[1]))
		composite_ok = composite_ok and expected.get_data() == raw_png(entry.texture).get_data() \
			and float(entry.duration_ms) == float(entry.source_duration_ms)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/stonemaster_r1.json"))
	var frames: Array = manifest.animations.attack.frames
	var clock: float = 0
	for frame: Dictionary in frames:
		clock += float(frame.duration_ms)
	check_result("thirty_two_composites_rebuild_from_original_offsets_and_thirteen_punch_records_keep645ms", composite_ok \
		and frames.size() == 13 and clock == 645 and FileAccess.get_sha256("res://"+source.runtime_output.path) == source.runtime_output.sha256,
		{"attack_records": frames.size(), "source_clock_ms": clock, "canvas": source.canvas_size, "anchor": source.foot_anchor})


func gate_entry(tree: SceneTree, progress: Node) -> bool:
	progress.set_process(false)
	tree.change_scene_to_file(DEPTHS) # Explicit scene fixture avoids replaying the frozen R4/01 boss victory.
	var depths: Dictionary = await wait_for(tree, "fixture_depths_for_strict_new_gate", 2.5, ready_scene(DEPTHS))
	if not depths.reached:
		check_result("depths_gate_fixture_loads", false, depths)
		return false
	var boss: Node = tree.current_scene.get_node("TowerBoss")
	boss.qa_freeze_enemy = true
	stage_actor(tree.current_scene.player, Vector2(840,320), 1)
	var original_boss: Dictionary = tree.get_meta("tower_boss_state").duplicate(true)
	var rejected: Array = []
	for bad: Variant in [1, "true"]:
		var invalid: Dictionary = original_boss.duplicate(true)
		invalid.cleared = bad
		tree.set_meta("tower_boss_state", invalid)
		await wait_for(tree, "actual_D_rejects_nonboolean_boss_clear", .24, Callable(), [KEY_D])
		rejected.append({"type": typeof(bad), "scene": tree.current_scene.scene_file_path,
			"locked": not tree.current_scene.get_node("WorldTravel").capture_state().doll_gallery_unlocked})
	var pending: Dictionary = progress.progress.duplicate(true)
	pending.chapter_flags.lakius_cleared = true
	progress._pending_bundle = pending
	tree.set_meta("tower_boss_state", original_boss)
	await wait_for(tree, "actual_D_rejects_uncommitted_chapter_candidate", .24, Callable(), [KEY_D])
	var pending_locked: bool = tree.current_scene.scene_file_path == DEPTHS \
		and not tree.current_scene.get_node("WorldTravel").capture_state().doll_gallery_unlocked
	progress._pending_bundle = {}
	check_result("new_right_gate_rejects_integer_string_and_uncommitted_chapter_flag", pending_locked \
		and rejected.all(func(row: Dictionary): return row.scene == DEPTHS and row.locked),
		{"rejected": rejected, "pending_locked": pending_locked, "fixture": "Only raw metadata types and one uncommitted candidate are staged; D input uses the real portal."})
	var true_session: Dictionary = original_boss.duplicate(true)
	true_session.cleared = true
	tree.set_meta("tower_boss_state", true_session)
	var entered: Dictionary = await wait_for(tree, "strict_boolean_session_receipt_actual_D_enters_gallery", 2.5, ready_scene(GALLERY), [KEY_D])
	# Old boss exit has now persisted its real alive state. Do not let a gate fixture become saved history.
	tree.set_meta("tower_boss_state", original_boss)
	progress.set_process(true)
	var good: bool = entered.reached
	if good:
		var fight: Node = tree.current_scene.get_node("GalleryEncounter")
		fight.qa_freeze_enemy = true
		good = tree.current_scene.player.spawn_position.distance_to(Vector2(176,320)) < .01 \
			and point(tree.current_scene).distance_to(Vector2(176,320)) <= 4 and fight.enemy_hp == 100 \
			and fight.enemy.world_to_source(fight.enemy.position).distance_to(Vector2(640,300)) <= 3 \
			and fight.capture_state().session_meta == "doll_gallery_state" and fight.capture_state().enemy_action == "attack"
		screenshot(tree, "arrival")
	check_result("strict_boolean_session_clear_allows_actual_D_and_safe_gallery_arrival", good,
		{"entry": entered, "fixture": "Lakius clear is a gate-only boolean fixture; its alive state is restored before profile observation resumes."})
	return good


func world_checks(tree: SceneTree) -> void:
	var main: Node = tree.current_scene
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var content: Node3D = main.world.get_node("TowerDollGalleryWorld")
	var rows: Array = []
	var meshes_ok: bool = true
	var decor: int = 0
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
				exact = exact and (right < 36 or left > 852 or bottom < 245 or top > 345)
			else:
				exact = exact and actual.end.y < .025
		meshes_ok = meshes_ok and exact
		rows.append({"node": entry.node, "native_AABB_and_foot_clearance_exact": exact, "world_AABB": actual})
	var cards_ok: bool = true
	for entry: Dictionary in layout.source_cards:
		var card: Sprite3D = content.find_child(entry.node,true,false) as Sprite3D
		cards_ok = cards_ok and card != null and card.texture.resource_path == entry.texture \
			and card.texture.get_size() == Vector2(entry.size[0],entry.size[1]) and not card.flip_h and not card.flip_v \
			and is_equal_approx(card.pixel_size,1.0/60.0) and card.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var ambience: Node = tree.root.get_node_or_null("PortAmbience")
	check_result("native27_mesh_AABBs25_solids_clear_feet_three_source_cards_and_no_phantom_colliders", meshes_ok and decor == 25 and cards_ok \
		and content.find_children("*","MeshInstance3D",true,false).size() == 27 \
		and content.find_children("*","Sprite3D",true,false).size() == 3 \
		and main.route_obstacles.capture_state().obstacle_count == 0 \
		and ambience != null and ambience.capture_state().target_gain == 0 and not main.get_node("PortClip/Far").visible,
		{"meshes": rows, "ambience": ambience.capture_state() if ambience != null else {}, "cards_exact": cards_ok})
	var floor_ok: bool = true
	var samples: Array = []
	for edge: Vector2 in [Vector2(36,345),Vector2(852,345)]:
		stage_actor(main.player,edge,1)
		main.framing.advance(0,true)
		await wait_for(tree,"native_lower_ground_edge",.07)
		var image: Image = main.render_viewport.get_texture().get_image()
		var min_alpha: float = 1
		for x: int in [5,16,879,890]:
			for y: int in [386,393,399]:
				min_alpha = minf(min_alpha,image.get_pixel(x*image.get_width()/896,y*image.get_height()/404).a)
		var target_x: float = -148 if edge.x < 100 else 140
		floor_ok = floor_ok and min_alpha > .98 and absf(main.framing.offset_x-target_x) < .01 and absf(main.framing.offset_y-37) < .01
		samples.append({"ground": edge,"camera": Vector2(main.framing.offset_x,main.framing.offset_y),"lower_band_min_alpha":min_alpha})
		screenshot(tree,"edge_left" if edge.x < 100 else "edge_right")
	check_result("both_maximum_legal_camera_pans_render_opaque_lower_ground_without_testing_transparent_sky",floor_ok,{"samples":samples})
	guard.cooldown_remaining = 1
	skill.cooldown_remaining = 1
	potion.cooldown_remaining = 1
	await actual_reset(tree,"gallery_initial_reset")
	var fight: Node = main.get_node("GalleryEncounter")
	check_result("actual_R_uses_gallery_arrival_anchor_resets_all_three_clocks_and_local_encounter",point(main).distance_to(Vector2(176,320)) < .1 \
		and fight.player_hp == 100 and fight.enemy_hp == 100 and not fight.cleared and fight.retreat_remaining == 0 \
		and guard.cooldown_remaining == 0 and skill.cooldown_remaining == 0 and potion.cooldown_remaining == 0,
		{"state":fight.capture_state()})


func frozen_snapshot(main: Node) -> Dictionary:
	var fight: Node = main.get_node("GalleryEncounter")
	return {"source_clock":fight.enemy.action_elapsed_ms(),"frame":fight.enemy.frame_index,"position":fight.enemy.position,"hero_position":point(main),
		"hp":fight.player_hp,"enemy_hp":fight.enemy_hp,"retreat":fight.retreat_remaining,
		"CDs":[guard.cooldown_remaining,skill.cooldown_remaining,potion.cooldown_remaining]}


func contact_and_retreat(tree: SceneTree) -> void:
	await actual_reset(tree,"raw_punch")
	var main: Node = tree.current_scene
	var fight: Node = main.get_node("GalleryEncounter")
	stage_actor(main.player,Vector2(440,315),1)
	stage_actor(fight.enemy,Vector2(500,315),-1)
	guard.cooldown_remaining = 3
	skill.cooldown_remaining = 3
	potion.cooldown_remaining = 3
	var before_hits: int = fight.event_counters.enemy_hits
	fight.qa_freeze_enemy = false
	var telegraph: Dictionary = await wait_for(tree,"AI_chooses_original_punch_windup",1.5,
		func(_m:Node,row:Dictionary):return row.fight.enemy_mode == "attack" and row.fight.enemy_action_elapsed_ms >= 80)
	helper.tap(KEY_F2)
	await wait_for(tree,"pause_settles_during_windup",.035)
	var paused: Dictionary = frozen_snapshot(main)
	await wait_for(tree,"pause_preserves_source_AI_and_three_CDs",.13)
	check_result("actual_F2_freezes_source_punch_AI_HP_and_three_runtime_clocks",telegraph.reached and main.player.paused \
		and frozen_snapshot(main) == paused,{"frozen":paused})
	helper.tap(KEY_F2)
	var menu: PopupMenu = main.get_node("Interface/AudioMenu").get_popup()
	menu.popup(Rect2i(180,120,180,160))
	await wait_for(tree,"menu_freeze_settles",.035)
	var menu_state: Dictionary = frozen_snapshot(main)
	await wait_for(tree,"native_menu_preserves_windup",.13)
	check_result("native_menu_freezes_gallery_punch_and_three_runtime_clocks",menu.visible and frozen_snapshot(main) == menu_state,{"frozen":menu_state})
	menu.hide()
	helper.tap(KEY_B)
	await wait_for(tree,"bag_freeze_settles",.035)
	var bag_state: Dictionary = frozen_snapshot(main)
	var casts: int = skill.accepted_casts
	var uses: int = potion.accepted_uses
	var begins: int = guard.accepted_begins
	for code: Key in [KEY_X,KEY_Q,KEY_SPACE,KEY_Z,KEY_H,KEY_C]:
		helper.tap(code)
	await wait_for(tree,"bag_blocks_combat_while_enemy_waits",.13,Callable(),[KEY_A,KEY_W])
	check_result("actual_B_modal_blocks_moves_attacks_jump_C_H_Z_and_freezes_gallery_clock",main.get_node("FirstLoot").capture_state().bag_open \
		and frozen_snapshot(main) == bag_state and skill.accepted_casts == casts and potion.accepted_uses == uses and guard.accepted_begins == begins,
		{"frozen":bag_state})
	helper.tap(KEY_B)
	var raw: Dictionary = await wait_for(tree,"real_punch_contact_after_resumed_windup",1.3,
		func(_m:Node,row:Dictionary):return int(row.fight.event_counters.enemy_hits) > before_hits)
	check_result("real_AI_punch14_uses300_525_window_and_original_contact_audio",raw.reached and fight.player_hp == 86 \
		and fight.enemy.animation_name == "attack" and fight.enemy.action_elapsed_ms() >= 300 and fight.enemy.action_elapsed_ms() < 545 \
		and fight._contact_audio != null and fight._contact_audio.stream.resource_path == "res://assets/r4/stonemaster/audio/stone_dmg.ogg" \
		and fight._contact_audio.playing \
		and tree.get_meta("route_hero_hp") == 86 and tree.get_meta("doll_gallery_state").player_hp == 86,
		{"contact":raw,"fixture":"Only starting60px spacing is staged. Enemy AI selects attack, source clocks and actual hit remain unmodified."})
	screenshot(tree,"punch_contact")
	var cds: Array = [guard.cooldown_remaining,skill.cooldown_remaining,potion.cooldown_remaining]
	await wait_for(tree,"own_hurt_CDs_continue",.10)
	check_result("gallery_hurt_is_shared_HP_and_does_not_freeze_other_runtime_CDs",fight.hero_hurt_remaining > 0 \
		and guard.cooldown_remaining < cds[0] and skill.cooldown_remaining < cds[1] and potion.cooldown_remaining < cds[2] \
		and potion.capture_state().player_hp == 86,{"before_CDs":cds,"hurt":fight.capture_state()})
	var retreat: Dictionary = await wait_for(tree,"natural645ms_punch_starts_retreat",1.0,
		func(_m:Node,row:Dictionary):return row.fight.retreat_remaining > 0)
	var origin: Vector2 = fight.retreat_origin
	var target: Vector2 = fight.retreat_target
	var facing: int = fight.retreat_facing
	var finished: Dictionary = await wait_for(tree,"AI_finishes50px_backstep",.65,
		func(_m:Node,row:Dictionary):return row.fight.retreat_remaining == 0 and row.fight.last_retreat_distance_px >= 49.5)
	check_result("whole_live_active_window_hits_once_then_original_Move_backsteps50px_without_turning",retreat.reached and finished.reached \
		and absf(origin.distance_to(target)-50) < .02 and fight.last_retreat_distance_px >= 49.5 and fight.last_retreat_distance_px <= 50.1 \
		and fight.enemy.facing == facing and fight.player_hp == 86 and fight.event_counters.enemy_hits == before_hits+1,
		{"retreat_started":retreat,"finished":finished,"origin":origin,"target":target,"note":"AI stays enabled through the entire active window; backstep is an explicit source Move adaptation."})
	fight.qa_freeze_enemy = true


func guard_and_interrupt(tree: SceneTree) -> void:
	await actual_reset(tree,"gallery_guard")
	var main: Node = tree.current_scene
	var fight: Node = main.get_node("GalleryEncounter")
	stage_actor(main.player,Vector2(440,315),1)
	stage_actor(fight.enemy,Vector2(500,315),-1)
	var blocked: int = guard.blocked_hits
	var before_hits: int = fight.event_counters.enemy_hits
	helper.key(KEY_C,true)
	fight.qa_freeze_enemy = false
	var contact: Dictionary = await wait_for(tree,"actual_C_guards_real_AI_punch",1.5,
		func(_m:Node,row:Dictionary):return row.guard.blocked_hits > blocked)
	check_result("actual_C_front_guard_reduces_real_punch14_to9_without_hurt_lock",contact.reached and fight.player_hp == 91 \
		and guard.last_hit.raw_damage == 14 and guard.last_hit.damage == 9 and fight.hero_hurt_remaining == 0 \
		and guard.capture_state().active and not main.player.ui_input_blocked,{"contact":contact})
	helper.key(KEY_C,false)
	var retreat: Dictionary = await wait_for(tree,"guarded_punch_finishes_before_interrupt",1.0,
		func(_m:Node,row:Dictionary):return row.fight.retreat_remaining > 0)
	var count: int = fight.retreats_started
	var serial: int = main.player.attack_instance
	helper.tap(KEY_X)
	var hit: Dictionary = await wait_for(tree,"actual_X_interrupts_current_backstep",.45,
		func(_m:Node,row:Dictionary):return int(row.fight.enemy_hp) < 100)
	var short_distance: float = fight.last_retreat_distance_px
	var canceled: bool = fight.retreat_remaining == 0 and fight.enemy_mode == "hurt" and short_distance < 49
	var hurt_point: Vector2 = fight.enemy.world_to_source(fight.enemy.position)
	await wait_for(tree,"hurt_recovery_does_not_resume_stale_backstep",.65)
	check_result("actual_X_interrupt_discards_old_retreat_target_and_punch_latch_stays_single",retreat.reached and hit.reached and canceled \
		and main.player.attack_instance == serial+1 and fight.enemy_hp == 82 and fight.event_counters.enemy_hits == before_hits+1 \
		and fight.retreats_started == count and fight.enemy.world_to_source(fight.enemy.position).x <= hurt_point.x+.1,
		{"hit":hit,"short_retreat_distance":short_distance,"after_recovery":fight.capture_state()})
	fight.qa_freeze_enemy = true


func actual_victory(tree: SceneTree, progress: Node) -> void:
	await actual_reset(tree,"actual_gallery_victory")
	var fight: Node = tree.current_scene.get_node("GalleryEncounter")
	var before: Dictionary = fight.capture_state()
	var profile_before: Dictionary = progress.progress.duplicate(true)
	var files_before: Dictionary = states.file_guard(qa_path)
	var writes: int = progress._save_attempts
	var old_first: Variant = tree.get_meta("first_encounter_state",null)
	var old_boss: Variant = tree.get_meta("tower_boss_state",null)
	var casts: Array = []
	fight.qa_freeze_enemy = false
	# From this reset onward no HP/position writes, AI freeze, source clock changes or direct attacks.
	for attempt: int in 6:
		if fight.cleared or fight.player_hp == 0:
			break
		await wait_for(tree,"real_fight_wait_for_free_controls",2.0,
			func(m:Node,row:Dictionary):return row.fight.cleared or int(row.fight.player_hp) == 0 or (not m.player._one_shot and not row.blocked and not m.player.jump_motion.is_active()))
		if fight.cleared or fight.player_hp == 0:
			break
		var difference: Vector2 = fight.enemy.world_to_source(fight.enemy.position)-point(tree.current_scene)
		if absf(difference.y) > 12:
			await wait_for(tree,"actual_align_punch_lane",1.5,
				func(m:Node,_row:Dictionary):return absf(fight.enemy.world_to_source(fight.enemy.position).y-point(m).y) <= 10,
				[KEY_S if difference.y > 0 else KEY_W])
		difference = fight.enemy.world_to_source(fight.enemy.position)-point(tree.current_scene)
		var toward: Key = KEY_D if difference.x >= 0 else KEY_A
		var away: Key = KEY_A if difference.x >= 0 else KEY_D
		if absf(difference.x) > 130:
			await wait_for(tree,"actual_run_into_Q_range",4.0,
				func(m:Node,_row:Dictionary):return absf(fight.enemy.world_to_source(fight.enemy.position).x-point(m).x) <= 130,[toward,KEY_SHIFT])
		elif absf(difference.x) < 123:
			await wait_for(tree,"actual_retreat_outside_punch_range",1.5,
				func(m:Node,_row:Dictionary):return absf(fight.enemy.world_to_source(fight.enemy.position).x-point(m).x) >= 128 or point(m).x <= 40 or point(m).x >= 848,[away,KEY_SHIFT])
		await wait_for(tree,"actual_face_and_Q",.025,Callable(),[toward])
		var serial: int = tree.current_scene.player.attack_instance
		var gap: Vector2 = fight.enemy.world_to_source(fight.enemy.position)-point(tree.current_scene)
		helper.tap(KEY_Q)
		await wait_for(tree,"actual_Q_and_natural_recovery",1.6,
			func(m:Node,row:Dictionary):return row.fight.cleared or int(row.fight.player_hp) == 0 or (not m.player._one_shot and not row.blocked))
		casts.append({"attempt":attempt,"initial_gap":gap,"accepted":tree.current_scene.player.attack_instance == serial+1,"state":fight.capture_state()})
	var victory: bool = fight.cleared and fight.enemy_hp == 0 and fight.player_hp > 0 \
		and fight.event_counters.victories == int(before.event_counters.victories)+1 and not fight.qa_freeze_enemy
	check_result("real_AI_enabled_gallery100HP_is_defeated_by_actual_movement_and_Q_without_health_or_position_writes",victory,
		{"before":before,"casts":casts,"after":fight.capture_state(),"fixture":"Only ordinary R starts this fight; every subsequent control is real directional input or Q. Practice weapon, unmodified source time, AI remains active."})
	await wait_for(tree,"gallery_defeat_animation_finishes",.8,
		func(_m:Node,row:Dictionary):return row.fight.cleared and not row.fight.enemy_visible)
	screenshot(tree,"victory")
	check_result("gallery_clear_has_own_session_and_creates_no_quest_drop_reward_or_profile_write",victory and progress.progress == profile_before \
		and states.file_guard(qa_path) == files_before and progress._save_attempts == writes and progress._pending_bundle.is_empty() \
		and tree.get_meta("first_encounter_state",null) == old_first and tree.get_meta("tower_boss_state",null) == old_boss \
		and tree.get_meta("doll_gallery_state").cleared == true and tree.get_meta("route_hero_hp") == fight.player_hp,
		{"profile":progress.capture_state(),"files_before":files_before,"files_after":states.file_guard(qa_path)})


func return_and_practice(tree: SceneTree, progress: Node) -> void:
	var fight: Node = tree.current_scene.get_node("GalleryEncounter")
	var carried_hp: int = fight.player_hp
	var gallery_before: Dictionary = fight.capture_state()
	var returned: Dictionary = await wait_for(tree,"actual_A_dash_back_to_depths",5.5,ready_scene(DEPTHS),[KEY_A,KEY_SHIFT])
	if returned.reached:
		tree.current_scene.get_node("TowerBoss").qa_freeze_enemy = true
	check_result("actual_left_return_keeps_shared_HP_gallery_clear_and_safe_depths_arrival",returned.reached \
		and tree.current_scene.player.spawn_position.distance_to(Vector2(816,320)) < .01 \
		and point(tree.current_scene).distance_to(Vector2(816,320)) <= 4 \
		and tree.current_scene.get_node("TowerBoss").player_hp == carried_hp \
		and tree.get_meta("doll_gallery_state").enemy_hp == 0 and tree.get_meta("doll_gallery_state").cleared == true,
		{"return":returned,"gallery_before":gallery_before})
	if not returned.reached:
		return
	# This legitimate completed-history fixture proves saved gate ownership without claiming a boss victory.
	var history: Dictionary = progress._default_progress()
	history.quest_stage = "completed"
	history.objective_cleared = true
	history.reward_granted = true
	history.coins = 40
	history.first_drop.state = "claimed"
	history.inventory["3128"] = 1
	history.equipment.owned["27304"] = true
	history.chapter_flags.lakius_cleared = true
	var committed: bool = progress._commit(history)
	var boss: Node = tree.current_scene.get_node("TowerBoss")
	var saved_gate: bool = not boss.cleared and tree.current_scene.get_node("WorldTravel").capture_state().doll_gallery_unlocked
	var reentered: Dictionary = await wait_for(tree,"committed_history_actual_D_reenters_gallery",2.5,ready_scene(GALLERY),[KEY_D,KEY_SHIFT])
	if not reentered.reached:
		check_result("committed_flag_alone_reopens_gallery",false,reentered)
		return
	fight = tree.current_scene.get_node("GalleryEncounter")
	fight.qa_freeze_enemy = true
	var persisted: bool = fight.cleared and fight.enemy_hp == 0 and not fight.enemy.visible and fight.retreat_remaining == 0 \
		and fight.player_hp == carried_hp and fight.event_counters.victories == int(gallery_before.event_counters.victories)
	check_result("committed_Lakius_flag_opens_gate_after_practice_and_gallery_reentry_keeps_clear_without_half_retreat",committed and saved_gate and persisted \
		and progress.progress == history and Supplies.new().exact_saved_value(JSON.parse_string(FileAccess.get_file_as_string(qa_path)),history),
		{"entry":reentered,"state":fight.capture_state(),"fixture":"Completed quest/claimed eye/owned weapon/Lakius chapter history is explicitly committed only after the independent default-profile gallery victory. Complete saved fields use strict recursive numeric equivalence."})
	await actual_reset(tree,"practice_keeps_committed_history")
	check_result("actual_R_retries_gallery_at176320_without_revoking_committed_history_or_reissuing_rewards",fight.player_hp == 100 and fight.enemy_hp == 100 \
		and not fight.cleared and fight.retreat_remaining == 0 and point(tree.current_scene).distance_to(Vector2(176,320)) < .1 \
		and progress.progress == history and tree.current_scene.get_node("WorldTravel").capture_state().doll_gallery_unlocked,
		{"state":fight.capture_state(),"profile":progress.capture_state()})
	var hits: Array = []
	for weapon: String in ["practice_lswd0000","27304"]:
		await actual_reset(tree,"controlled_equipment_hit")
		fight.qa_freeze_enemy = true
		var equipped: bool = progress.equip_weapon(weapon)
		await wait_for(tree,"equipment_applies_in_gallery",.05)
		stage_actor(tree.current_scene.player,Vector2(440,315),1)
		stage_actor(fight.enemy,Vector2(520,315),-1)
		var serial: int = tree.current_scene.player.attack_instance
		var before_hits: int = fight.event_counters.hero_hits
		helper.tap(KEY_X)
		await wait_for(tree,"controlled_actual_X_whole_active_window",.7)
		hits.append({"weapon":weapon,"equipped":equipped,"damage":100-fight.enemy_hp,"attack_instances":tree.current_scene.player.attack_instance-serial,
			"hits":fight.event_counters.hero_hits-before_hits,"data":tree.current_scene.player.animation_data})
	check_result("gallery_inherits_one_hit_identity_and_equipped_plus4_with_actual_X",hits.size() == 2 and hits[0].equipped and hits[1].equipped \
		and hits[0].damage == 18 and hits[1].damage == 22 and hits[0].hits == 1 and hits[1].hits == 1 \
		and hits[0].attack_instances == 1 and hits[1].attack_instances == 1,
		{"hits":hits,"fixture":"Only owned-history, starting80px positions and stopped enemy AI are fixtures; X damage runs the native attack clock and full active window."})


func run(root: Node, candidate: String = "R4/06") -> Dictionary:
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
	qa_path = "user://qa/gallery_live_"+str(Time.get_ticks_usec())+"_"+str(Time.get_unix_time_from_system()).replace(".","_")+".json"
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
		if await gate_entry(tree,progress):
			await world_checks(tree)
			await contact_and_retreat(tree)
			await guard_and_interrupt(tree)
			await actual_victory(tree,progress)
			await return_and_practice(tree,progress)
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
		and tree.has_meta("doll_gallery_state") == gallery_present and tree.get_meta("doll_gallery_state",null) == gallery_meta \
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
		"source_reference_sha256":FileAccess.get_sha256(SOURCE),"layout_reference_sha256":FileAccess.get_sha256(LAYOUT),
		"note":"Focused gallery integration. Real AI chooses and completes punch, raw14/front guard9 contacts and50px backstep use original clocks; AI stays enabled through full active windows. One practice-weapon100HP victory uses only real directional/Q input after ordinary R, with no health/position writes or AI freeze. Gate receipts, initial contact positions, completed history and controlled +4 probe are explicit fixtures. Gallery has no new award/storage schema. Native PNGs read via buffers and compare complete RGBA. Original profile including pending, all session metadata, actor/preferences and three persistent runtimes restore after combat exit. All waits are bounded."}
	var path: String = "res://docs/"+output_prefix+"_gallery_checks.json"
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report,"  "))
		output.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases.size(),"recorded_rows":records.size(),"report":path}
