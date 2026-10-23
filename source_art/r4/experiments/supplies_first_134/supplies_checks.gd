extends RefCounted
## Focused native supplies checks, owned by a persistent root pose_check_job.

const Inputs = preload("res://tools/r3/quest_checks.gd")
const StateChecks = preload("res://tools/r4/sharan_checks.gd")
const Preferences = preload("res://tools/r2/travel_checks.gd")
const HARBOR: String = "res://scenes/west_coast_r1.tscn"
const RAW: String = "res://scenes/west_coast_r0.tscn"
const HALL: String = "res://scenes/tower_hall.tscn"
const DEPTHS: String = "res://scenes/tower_depths.tscn"
const PROFILE_FIELDS: Array[String] = StateChecks.PROFILE_FIELDS
const SKILL_FIELDS: Array[String] = StateChecks.SKILL_FIELDS
const POTION_FIELDS: Array[String] = ["cooldown_remaining", "accepted_uses", "rejected_uses", "reset_count", "last_reject_reason", "last_heal"]
var checks: Array = []
var render_cases: Array = []
var records: Array = []
var screenshots: Dictionary = {}
var helper: RefCounted
var states: RefCounted
var skill: Node
var potion: Node
var qa_path: String
var tmp_block_owned: bool = false
var started_usec: int
var output_prefix: String = "r4_04"


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
	var travel: Node = main.get_node_or_null("WorldTravel")
	var fight: Node = fight_at(main)
	var shop: Node = main.get_node_or_null("PortSupplyShop")
	var row: Dictionary = {"phase": label, "elapsed_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"scene": main.scene_file_path, "position": point(main), "action": main.player.animation_name,
		"blocked": main.player.ui_input_blocked, "paused": main.player.paused, "one_shot": main.player._one_shot,
		"jump_height": main.player.jump_motion.height_pixels, "potion": potion.capture_state(), "skill": skill.capture_state(),
		"fight": fight.capture_state() if fight != null else {}, "shop": shop.capture_state() if shop != null else {},
		"travel": travel.capture_state() if travel != null else {}}
	records.append(row)
	return row


func wait_for(tree: SceneTree, label: String, seconds: float, until: Callable = Callable(), keys: Array = []) -> Dictionary:
	helper.release_motion()
	for code: Key in keys:
		helper.key(code, true)
	var started: int = Time.get_ticks_usec()
	var last: Dictionary = {}
	var reached: bool = false
	while float(Time.get_ticks_usec()-started)/1000000.0 < seconds:
		await RenderingServer.frame_post_draw
		last = observe(tree, label)
		if not last.is_empty() and until.is_valid() and until.call(tree.current_scene, last):
			reached = true
			break
	helper.release_motion()
	return {"reached": reached, "last": last, "duration_seconds": float(Time.get_ticks_usec()-started)/1000000.0}


func ready_scene(path: String) -> Callable:
	return func(main: Node, row: Dictionary): return main.scene_file_path == path and potion.main == main and skill.main == main \
		and (path == RAW or row.travel.get("phase", "") == "ready") \
		and (path != HARBOR or main.get_node_or_null("PortSupplyShop") != null) \
		and (path != HALL or main.get_node_or_null("FirstEncounter") != null) \
		and (path != DEPTHS or main.get_node_or_null("TowerBoss") != null)


func screenshot(tree: SceneTree, name: String) -> void:
	var path: String = "res://docs/previews/"+output_prefix+"_supplies_"+name+".png"
	screenshots[name] = {"path": path, "save_error": tree.current_scene.get_viewport().get_texture().get_image().save_png(path),
		"scene": tree.current_scene.scene_file_path}


func saved_progress() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(qa_path)) if FileAccess.file_exists(qa_path) else null
	return parsed if parsed is Dictionary else {}


func block_tmp() -> bool:
	var path: String = ProjectSettings.globalize_path(qa_path+".tmp")
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		return false
	tmp_block_owned = DirAccess.make_dir_absolute(path) == OK
	return tmp_block_owned


func unblock_tmp() -> void:
	if tmp_block_owned:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(qa_path+".tmp"))
		tmp_block_owned = false


func asset_checks(progress: Node) -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/r4_hp_potion_source_reference.json"))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/first_supplies.json"))
	var passed: bool = source.images.size() == 2 and source.source_scripts.size() == 10
	var images: Array = []
	for key: String in source.images:
		var entry: Dictionary = source.images[key]
		var texture: Texture2D = load(entry.path)
		var native: Image = texture.get_image() if texture != null else null
		var raw: Image = Image.load_from_file(entry.path)
		var exact: bool = raw != null and native != null
		if exact:
			if native.is_compressed():
				exact = native.decompress() == OK
			if exact:
				raw.convert(Image.FORMAT_RGBA8)
				native.convert(Image.FORMAT_RGBA8)
				exact = raw.get_data() == native.get_data() and native.get_size() == Vector2i(entry.size[0], entry.size[1]) \
					and states.image_hash(native) == entry.sha256_rgba and FileAccess.get_sha256(entry.path) == entry.sha256_png
		passed = passed and exact
		images.append({"path": entry.path, "native_RGBA_exact": exact})
	var sources: Array = []
	for entry: Dictionary in source.source_scripts:
		var exact: bool = entry.crc_matches and FileAccess.get_sha256("res://"+entry.evidence) == entry.sha256_decoded
		passed = passed and exact
		sources.append({"path": entry.pvf, "CRC_verified_source_bytes_exact": exact})
	check_result("two_native_PNGs_ten_CRC_verified_sources_and_runtime_tuning_match", passed
		and int(data.potion.cost) == progress.hp_potion_price() and int(data.potion.max_purchase_count) == progress.hp_potion_capacity()
		and potion.capture_state().item_id == 1106 and potion.capture_state().heal_hp == 35 and potion.capture_state().cooldown_seconds == 10.0,
		{"images": images, "sources": sources, "runtime": potion.capture_state()})


func shop_checks(tree: SceneTree, progress: Node) -> bool:
	# Completed quest/reward is an explicit fixture; no second quest victory is claimed.
	var completed: Dictionary = progress._default_progress()
	completed.quest_stage = "completed"
	completed.objective_cleared = true
	completed.reward_granted = true
	completed.coins = 40
	completed.first_drop.state = "claimed"
	completed.inventory["3128"] = 1
	completed.equipment.owned["27304"] = true
	var committed: bool = progress._commit(completed)
	var walked: Dictionary = await wait_for(tree, "actual_A_near_Lorian", 2.0,
		func(m: Node, _row: Dictionary): return point(m).x <= 320.0, [KEY_A])
	var main: Node = tree.current_scene
	var shop: Node = main.get_node("PortSupplyShop")
	helper.tap(KEY_E)
	await wait_for(tree, "actual_E_Lorian_dialog", .03)
	var quest_open: bool = progress.capture_state().dialog_open
	shop._entry_button.pressed.emit() # The actual GUI callback, expressly allowed by root.
	await wait_for(tree, "Lorian_supply_button_opens_shop", .04)
	check_result("completed_40coin_fixture_actual_walk_E_and_supply_button_open_shop", committed and walked.reached and quest_open
		and shop.capture_state().dialog_open and not progress.capture_state().dialog_open and main.player.ui_input_blocked
		and shop.capture_state().coins == 40 and shop.capture_state().potion_count == 0,
		{"fixture": "Completed reward history, not a repeated full quest run.", "shop": shop.capture_state()})
	if not shop.capture_state().dialog_open:
		return false
	potion.cooldown_remaining = 4.0
	skill.cooldown_remaining = 4.0
	var ground: Vector2 = point(main)
	var uses: int = potion.accepted_uses
	var casts: int = skill.accepted_casts
	for key: Key in [KEY_H, KEY_X, KEY_SPACE, KEY_B, KEY_Z]:
		helper.tap(key)
	await wait_for(tree, "shop_blocks_gameplay_and_freezes_clocks", .14, Callable(), [KEY_A, KEY_W])
	check_result("shop_modal_blocks_H_X_Space_B_Z_movement_and_freezes_both_cooldowns", point(main).distance_to(ground) < .01
		and potion.accepted_uses == uses and skill.accepted_casts == casts and not main.player._one_shot and not main.player.jump_motion.is_active()
		and not main.get_node("FirstLoot").capture_state().bag_open and potion.cooldown_remaining == 4.0 and skill.cooldown_remaining == 4.0
		and potion.capture_state().frozen and skill.capture_state().frozen)
	var before: Dictionary = progress.progress.duplicate(true)
	var files: Dictionary = states.file_guard(qa_path)
	var blocked: bool = block_tmp()
	shop._buy_button.pressed.emit()
	await wait_for(tree, "shop_failed_purchase_keeps_exact_pending", .03)
	var pending: Dictionary = progress._pending_bundle.duplicate(true)
	check_result("failed_shop_save_keeps_coins_inventory_and_exact_pending_purchase", blocked and progress.progress == before
		and int(pending.get("coins", -1)) == 30 and int(pending.get("inventory", {}).get("1106", -1)) == 1
		and shop.capture_state().pending_save and shop._buy_button.text.contains("重试") and states.file_guard(qa_path) == files,
		{"pending": pending, "shop": shop.capture_state(), "fixture": "An owned empty directory blocks only this unique QA .tmp file."})
	unblock_tmp()
	shop._buy_button.pressed.emit()
	await wait_for(tree, "same_shop_button_retries_one_purchase", .03)
	check_result("one_retry_button_saves_one_purchase_without_double_debit", progress._pending_bundle.is_empty()
		and progress.progress == pending and progress.hp_potion_count() == 1 and int(progress.progress.coins) == 30
		and saved_progress() == progress.progress)
	var purchases: Array = []
	for i: int in range(3):
		shop._buy_button.pressed.emit()
		await wait_for(tree, "actual_shop_purchase_"+str(i+2), .03)
		purchases.append({"coins": int(progress.progress.coins), "count": progress.hp_potion_count()})
	var capped: Dictionary = progress.progress.duplicate(true)
	helper.tap(KEY_ENTER) # Disabled buy must not allow another transaction.
	await wait_for(tree, "shop_cannot_buy_fifth_with_no_gold", .03)
	check_result("four_total_purchases_spend_only_40_gold_cap_inventory4_and_disable_fifth", purchases == [{"coins":20,"count":2},{"coins":10,"count":3},{"coins":0,"count":4}]
		and shop._buy_button.disabled and not shop.capture_state().can_buy and progress.progress == capped
		and saved_progress() == capped,
		{"purchases": purchases, "shop": shop.capture_state()})
	screenshot(tree, "shop")
	helper.tap(KEY_ESCAPE)
	await wait_for(tree, "shop_Esc_closes", .03)
	helper.tap(KEY_B)
	await wait_for(tree, "actual_B_shows_four_potions", .04)
	var bag: Node = main.get_node("FirstLoot")
	var bag_state: Dictionary = bag.capture_state()
	var icon: Node = bag.find_child("HpPotionIcon", true, false)
	var count: Node = bag.find_child("HpPotionCount", true, false)
	var icon_ok: bool = icon != null and icon.is_visible_in_tree() and icon.texture != null \
		and icon.texture.resource_path == "res://assets/r4/supplies/hp_potion_icon.png"
	var clock: float = potion.cooldown_remaining
	helper.tap(KEY_H)
	await wait_for(tree, "bag_H_is_modal_rejected", .10)
	check_result("actual_B_third_slot_shows_source_icon_count4_and_blocks_H_freezes_CD", bag_state.bag_open and bag_state.potion_count == 4
		and bag_state.potion_icon_visible and bag.find_child("HpPotionSlot", true, false) != null
		and icon_ok and count != null and count.is_visible_in_tree() and count.text == "4" and progress.hp_potion_count() == 4
		and potion.accepted_uses == uses and potion.cooldown_remaining == clock and potion.capture_state().frozen,
		{"bag": bag.capture_state(), "potion_icon_applied": icon_ok, "count_label": count.text if count != null else ""})
	screenshot(tree, "bag")
	helper.tap(KEY_ESCAPE)
	await wait_for(tree, "bag_Esc_restores_control", .03)
	return true


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


func stage_hp(tree: SceneTree, hp: int) -> void:
	var fight: Node = fight_at(tree.current_scene)
	if fight != null:
		fight.player_hp = hp
		fight.hero_hurt_remaining = 0.0
		fight._hero_lock = false
		fight._release_pending = false
		fight._persist()
	else:
		tree.set_meta("route_hero_hp", hp)
	tree.current_scene.player.ui_input_blocked = false
	tree.current_scene.player.free_control()


func combat_checks(tree: SceneTree, progress: Node) -> bool:
	tree.change_scene_to_file(DEPTHS) # Explicit combat-area setup fixture.
	var arrived: Dictionary = await wait_for(tree, "fixture_load_depths_for_real_injury", 2.5, ready_scene(DEPTHS))
	if not arrived.reached:
		check_result("combat_fixture_loads", false, arrived)
		return false
	var main: Node = tree.current_scene
	var boss: Node = main.get_node("TowerBoss")
	helper.tap(KEY_R)
	await wait_for(tree, "real_R_before_injury_fixture", .04)
	stage_hp(tree, 50) # Only the initial injury precondition is staged.
	stage_actor(main.player, Vector2(440, 315), 1)
	stage_actor(boss.enemy, Vector2(510, 315), -1)
	boss.qa_freeze_enemy = false
	boss._start_attack("normal")
	var hurt: Dictionary = await wait_for(tree, "real_boss_normal_injures_hero", .55,
		func(m: Node, _row: Dictionary): return m.get_node("TowerBoss").hero_hurt_remaining > 0)
	var uses: int = potion.accepted_uses
	var count: int = progress.hp_potion_count()
	helper.tap(KEY_H)
	check_result("real_boss_contact_injures_to36_and_H_during_hurt_is_rejected", hurt.reached and boss.player_hp == 36
		and potion.accepted_uses == uses and progress.hp_potion_count() == count and potion.cooldown_remaining == 0,
		{"contact": hurt, "potion": potion.capture_state(), "fixture": "Hero initial50HP and70px positions, then real14-damage normal contact."})
	boss.qa_freeze_enemy = true
	await wait_for(tree, "real_hurt_lock_releases_before_H", .7,
		func(m: Node, _row: Dictionary): return not m.player.ui_input_blocked and m.get_node("TowerBoss").hero_hurt_remaining == 0)
	var enemy_before: Dictionary = boss.capture_state()
	helper.tap(KEY_H)
	var same_stack: Dictionary = potion.capture_state()
	check_result("actual_H_commits_one_inventory_debit_then_heals35_live_and_meta_same_stack", boss.player_hp == 71
		and tree.get_meta("route_hero_hp") == 71 and tree.get_meta("tower_boss_state").player_hp == 71
		and progress.hp_potion_count() == count-1 and potion.accepted_uses == uses+1 and potion.cooldown_remaining == 10.0
		and saved_progress() == progress.progress and boss.enemy_hp == int(enemy_before.enemy_hp)
		and boss.enemy.world_to_source(boss.enemy.position) == enemy_before.enemy_source_position,
		{"same_stack": same_stack, "enemy_before": enemy_before, "after": boss.capture_state()})
	for i: int in range(3):
		helper.tap(KEY_H)
	check_result("repeated_H_during_10s_CD_does_not_double_consume_or_heal", potion.accepted_uses == uses+1
		and progress.hp_potion_count() == count-1 and boss.player_hp == 71 and potion.cooldown_remaining == 10.0)
	await wait_for(tree, "heal_HUD_is_rendered", .03)
	screenshot(tree, "combat_heal")
	stage_actor(boss.enemy, Vector2(point(main).x+70, 315), -1)
	boss.qa_freeze_enemy = false
	boss._start_attack("normal")
	var second: Dictionary = await wait_for(tree, "second_real_contact_during_potion_CD", .55,
		func(m: Node, _row: Dictionary): return m.get_node("TowerBoss").hero_hurt_remaining > 0)
	var before_clock: float = potion.cooldown_remaining
	await wait_for(tree, "own_hurt_continues_potion_CD", .10)
	check_result("potion_CD_continues_through_actual_own_hurt", second.reached and boss.player_hp == 57
		and not potion.capture_state().frozen and before_clock-potion.cooldown_remaining > .04,
		{"contact": second, "before_CD": before_clock, "after": potion.capture_state()})
	boss.qa_freeze_enemy = true
	await wait_for(tree, "second_hurt_releases_before_walk", .7,
		func(m: Node, _row: Dictionary): return not m.player.ui_input_blocked)
	var before_walk: Vector2 = point(main)
	before_clock = potion.cooldown_remaining
	await wait_for(tree, "actual_D_walk_with_potion_CD", .14, Callable(), [KEY_D])
	check_result("ordinary_actual_movement_keeps_potion_CD_running", point(main).x-before_walk.x > 7.0
		and before_clock-potion.cooldown_remaining > .05)
	var resets: int = potion.reset_count
	helper.tap(KEY_R)
	await wait_for(tree, "actual_R_clears_only_session_CD", .04)
	check_result("one_actual_R_clears_potion_CD_but_does_not_refund_inventory", potion.cooldown_remaining == 0
		and potion.reset_count == resets+1 and progress.hp_potion_count() == count-1 and boss.player_hp == 100)
	helper.tap(KEY_H)
	check_result("full_HP_H_rejected_without_inventory_CD_or_heal", boss.player_hp == 100 and progress.hp_potion_count() == count-1
		and potion.accepted_uses == uses+1 and potion.cooldown_remaining == 0)
	return true


func rejection_checks(tree: SceneTree, progress: Node) -> void:
	var main: Node = tree.current_scene
	var boss: Node = main.get_node("TowerBoss")
	boss.qa_freeze_enemy = true
	stage_hp(tree, 60)
	var uses: int = potion.accepted_uses
	var quantity: int = progress.hp_potion_count()
	var rejected: Array = []
	helper.tap(KEY_F2)
	helper.tap(KEY_H)
	rejected.append({"gate":"pause", "pass":main.player.paused and potion.accepted_uses == uses})
	helper.tap(KEY_F2)
	var menu: PopupMenu = main.get_node("Interface/AudioMenu").get_popup()
	menu.popup(Rect2i(180, 120, 180, 160))
	helper.tap(KEY_H)
	rejected.append({"gate":"menu", "pass":menu.visible and potion.accepted_uses == uses})
	menu.hide()
	await wait_for(tree, "menu_closes_before_potion_air_gate", .04)
	helper.tap(KEY_SPACE)
	var air: Dictionary = await wait_for(tree, "real_air_before_H_rejection", .4,
		func(m: Node, _row: Dictionary): return m.player.jump_motion.height_pixels > 10.0)
	helper.tap(KEY_H)
	rejected.append({"gate":"real_air", "pass":air.reached and potion.accepted_uses == uses})
	await wait_for(tree, "real_jump_lands_after_H_rejection", 1.3,
		func(m: Node, _row: Dictionary): return not m.player.jump_motion.is_active())
	main.player.ui_input_blocked = true
	helper.tap(KEY_H)
	rejected.append({"gate":"external_UI_fixture", "pass":potion.accepted_uses == uses})
	main.player.ui_input_blocked = false
	main.player.preview("stay")
	helper.tap(KEY_H)
	rejected.append({"gate":"source_preview", "pass":potion.accepted_uses == uses})
	main.player.free_control()
	helper.tap(KEY_X)
	helper.tap(KEY_H)
	rejected.append({"gate":"actual_X_action", "pass":main.player._one_shot and potion.accepted_uses == uses})
	await wait_for(tree, "actual_X_recovers_after_H_gate", 1.0,
		func(m: Node, _row: Dictionary): return not m.player._one_shot)
	progress.progress.inventory["1106"] = 0 # Explicit empty-stock gate fixture, restored below.
	helper.tap(KEY_H)
	rejected.append({"gate":"empty_inventory_fixture", "pass":potion.accepted_uses == uses and boss.player_hp == 60})
	progress.progress.inventory["1106"] = quantity
	check_result("H_rejected_for_pause_menu_real_air_UI_preview_action_and_empty_inventory", rejected.all(func(row): return row.pass)
		and progress.hp_potion_count() == quantity and boss.player_hp == 60 and potion.cooldown_remaining == 0,
		{"gates": rejected})
	stage_hp(tree, 0) # Explicit KO starting-state fixture.
	boss._hero_lock = true # Match the ownership flag set by a real lethal strike.
	await wait_for(tree, "KO_fixture_owns_input_lock", .04)
	helper.tap(KEY_H)
	var ko_rejected: bool = boss.player_hp == 0 and potion.accepted_uses == uses and progress.hp_potion_count() == quantity
	helper.tap(KEY_R)
	await wait_for(tree, "actual_KO_R_restores_free_control", .05)
	check_result("KO_rejects_H_and_actual_R_releases_KO_without_refunding_stock", ko_rejected and boss.player_hp == 100
		and not main.player.ui_input_blocked and not main.player._one_shot and potion.cooldown_remaining == 0
		and progress.hp_potion_count() == quantity)
	stage_hp(tree, 60)
	var old_pending: Dictionary = progress._pending_bundle.duplicate(true)
	var pending: Dictionary = progress.progress.duplicate(true)
	progress._pending_bundle = pending # Explicit valid pending transaction fixture, not committed.
	helper.tap(KEY_H)
	check_result("existing_pending_transaction_rejects_H_without_replacement_or_heal", progress._pending_bundle == pending
		and potion.accepted_uses == uses and boss.player_hp == 60 and progress.hp_potion_count() == quantity and potion.cooldown_remaining == 0)
	progress._pending_bundle = old_pending


func portal_and_save_checks(tree: SceneTree, progress: Node) -> void:
	var main: Node = tree.current_scene
	main.get_node("TowerBoss").qa_freeze_enemy = true
	stage_actor(main.player, Vector2(38, 320), -1) # Portal starting-position fixture.
	potion.cooldown_remaining = 4.0
	var uses: int = potion.accepted_uses
	var quantity: int = progress.hp_potion_count()
	var crossed: Dictionary = await wait_for(tree, "actual_A_depths_to_hall_preserves_potion_CD", 2.5, ready_scene(HALL), [KEY_A])
	if crossed.reached:
		tree.current_scene.get_node("FirstEncounter").qa_freeze_enemy = true
	check_result("actual_portal_retains_potion_stock_CD_and_shared_health", crossed.reached and potion.cooldown_remaining > 3.0
		and potion.cooldown_remaining <= 4.0 and potion.accepted_uses == uses and progress.hp_potion_count() == quantity
		and potion.capture_state().player_hp == 60,
		{"portal": crossed})
	tree.change_scene_to_file(HARBOR)
	var harbor: Dictionary = await wait_for(tree, "fixture_harbor_for_failed_use", 2.5, ready_scene(HARBOR))
	if not harbor.reached:
		check_result("harbor_save_fixture_loads", false, harbor)
		return
	potion.cooldown_remaining = 0.0
	stage_hp(tree, 60)
	var before: Dictionary = progress.progress.duplicate(true)
	var files: Dictionary = states.file_guard(qa_path)
	var blocked: bool = block_tmp()
	helper.tap(KEY_H)
	var stale_retry: bool = progress.retry_pending_save()
	check_result("failed_use_save_does_not_consume_heal_start_CD_or_leave_pending_debit", blocked and progress.progress == before
		and progress._pending_bundle.is_empty() and potion.accepted_uses == uses and potion.cooldown_remaining == 0
		and potion.capture_state().player_hp == 60 and potion.last_reject_reason == "save_failed"
		and not stale_retry and states.file_guard(qa_path) == files,
		{"potion": potion.capture_state(), "pending": progress._pending_bundle, "fixture": "Only the unique QA .tmp path is blocked by an owned empty directory."})
	unblock_tmp()
	helper.tap(KEY_H) # Retry H itself; there is intentionally no pending deduction to save.
	check_result("after_storage_recovers_new_H_consumes_once_and_heals_to95", progress.hp_potion_count() == quantity-1
		and potion.accepted_uses == uses+1 and potion.capture_state().player_hp == 95 and potion.cooldown_remaining == 10.0
		and progress._pending_bundle.is_empty() and saved_progress() == progress.progress,
		{"potion": potion.capture_state()})
	potion.cooldown_remaining = 0.0 # Explicit ready/90HP cap fixture, not an elapsed-CD claim.
	stage_hp(tree, 90)
	helper.tap(KEY_H)
	check_result("actual_H_caps_at100_and_debits_one_for_remaining10HP", potion.capture_state().player_hp == 100
		and potion.last_heal.healed_hp == 10 and progress.hp_potion_count() == quantity-2
		and potion.accepted_uses == uses+2 and potion.cooldown_remaining == 10.0)
	var cooldown: float = potion.cooldown_remaining
	var accepted: int = potion.accepted_uses
	helper.tap(KEY_F4)
	var raw: Dictionary = await wait_for(tree, "actual_F4_to_R0_preserves_potion_CD", 2.5, ready_scene(RAW))
	helper.tap(KEY_H)
	await wait_for(tree, "R0_blocks_H_and_freezes_potion_CD", .14)
	var raw_pass: bool = raw.reached and potion.cooldown_remaining == cooldown and potion.capture_state().freeze_reason == "comparison" \
		and not potion.capture_state().hud_visible and potion.accepted_uses == accepted and progress.hp_potion_count() == quantity-2
	helper.tap(KEY_F4)
	var back: Dictionary = await wait_for(tree, "actual_F4_back_R1_potion_CD_resumes", 2.5, ready_scene(HARBOR))
	await wait_for(tree, "R1_potion_CD_ticks_after_F4", .07)
	check_result("R0_H_unavailable_and_CD_frozen_then_F4_R1_preserves_and_resumes", raw_pass and back.reached
		and potion.cooldown_remaining < cooldown and potion.cooldown_remaining > cooldown-.4
		and potion.accepted_uses == accepted and not potion.capture_state().frozen,
		{"R0_pass": raw_pass, "R1": potion.capture_state()})


func run(root: Node, candidate: String = "R4/04") -> Dictionary:
	var tree: SceneTree = root.get_tree()
	started_usec = Time.get_ticks_usec()
	output_prefix = candidate.to_lower().replace("/", "_")
	helper = Inputs.new()
	helper.started_usec = started_usec
	states = StateChecks.new()
	var main: Node = tree.current_scene
	var progress: Node = tree.root.get_node_or_null("AdventureProgress")
	skill = tree.root.get_node_or_null("SourceSkillRuntime")
	potion = tree.root.get_node_or_null("HpPotionRuntime")
	if main == null or main.scene_file_path != HARBOR or progress == null or skill == null or potion == null or main.get_node_or_null("PortSupplyShop") == null:
		check_result("integrated_harbor_profile_shop_potion_available", false)
		return {"checks": checks.size(), "failed": checks, "render_cases": render_cases.size()}
	var formal_before: Dictionary = helper.profile_guard()
	var original_meta: Dictionary = states.snapshot_meta(tree)
	var original_profile: Dictionary = states.snapshot_fields(progress, PROFILE_FIELDS)
	var original_skill: Dictionary = states.snapshot_fields(skill, SKILL_FIELDS)
	var original_potion: Dictionary = states.snapshot_fields(potion, POTION_FIELDS)
	var process_before: Array[bool] = [progress.is_processing(), skill.is_processing(), potion.is_processing()]
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
	qa_path = "user://qa/supplies_live_"+str(Time.get_ticks_usec())+"_"+str(Time.get_unix_time_from_system()).replace(".", "_")+".json"
	var configured: bool = progress.configure_storage(qa_path, false)
	for key: String in ["route_hero_hp", "first_encounter_state", "tower_boss_state"]:
		if tree.has_meta(key):
			tree.remove_meta(key)
	progress.set_process(true)
	skill.set_process(true)
	potion.set_process(true)
	main._set_paused(false)
	main.player.ui_input_blocked = false
	main.player.free_control()
	main.get_node("Interface").visible = true
	if main.player.markers_visible:
		main._toggle_markers()
	main.get_viewport().gui_release_focus()
	helper.tap(KEY_R)
	await wait_for(tree, "actual_R_before_supplies_QA", .04)
	helper.tap(KEY_E)
	check_result("unique_QA_schema5_empty_stock_formal_guard_and_far_E_no_shop", configured and progress.storage_path == qa_path
		and int(progress.progress.schema) == 5 and progress.hp_potion_count() == 0 and not FileAccess.file_exists(qa_path)
		and not main.get_node("PortSupplyShop").capture_state().dialog_open and not progress.capture_state().dialog_open
		and helper.profile_guard() == formal_before,
		{"QA_path": qa_path, "formal_files": formal_before})
	if configured:
		asset_checks(progress)
		if await shop_checks(tree, progress):
			if await combat_checks(tree, progress):
				await rejection_checks(tree, progress)
				await portal_and_save_checks(tree, progress)
	# All old encounter exit persistence happens before original metadata is restored.
	helper.release_motion()
	unblock_tmp()
	progress.set_process(false)
	skill.set_process(false)
	potion.set_process(false)
	main = tree.current_scene
	if main != null:
		for child: String in ["PortSupplyShop", "SharanInteraction"]:
			var controller: Node = main.get_node_or_null(child)
			if controller != null:
				controller.call("close_shop" if child == "PortSupplyShop" else "close_dialog")
		var loot: Node = main.get_node_or_null("FirstLoot")
		if loot != null:
			loot.close_bag()
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
		skill.attach_area(main)
		potion.attach_area(main)
	states.restore_fields(skill, original_skill)
	states.restore_fields(potion, original_potion)
	skill._refresh_hud()
	potion._refresh_hud()
	progress.set_process(process_before[0])
	skill.set_process(process_before[1])
	potion.set_process(process_before[2])
	check_result("cleanup_restores_original_profile_pending_meta_actor_preferences_both_CDs_and_counters", cleanup.reached
		and states.snapshot_fields(progress, PROFILE_FIELDS) == original_profile and states.snapshot_meta(tree) == original_meta
		and states.snapshot_fields(skill, SKILL_FIELDS) == original_skill and states.snapshot_fields(potion, POTION_FIELDS) == original_potion
		and main.player.capture_state() == original_actor and main.player.spawn_position == original_spawn
		and main.player.ui_input_blocked == original_blocked and preferences.settings(main) == original_preferences
		and skill.main == main and potion.main == main and not tmp_block_owned,
		{"cleanup": cleanup})
	var formal_after: Dictionary = helper.profile_guard()
	check_result("formal_primary_backup_and_both_temporary_files_are_byte_unchanged", formal_before == formal_after,
		{"before": formal_before, "after": formal_after})
	var failed: Array = checks.filter(func(c): return not c.pass)
	var report: Dictionary = {"candidate": candidate, "checks": checks, "failed": failed, "records": records, "screenshots": screenshots,
		"duration_seconds": float(Time.get_ticks_usec()-started_usec)/1000000.0, "QA_storage_path": qa_path,
		"formal_profile_before": formal_before, "formal_profile_after": formal_after,
		"qa_source_sha256": get_script().source_code.sha256_text(),
		"runtime_source_sha256": FileAccess.get_file_as_string("res://scripts/hp_potion_runtime.gd").sha256_text(),
		"profile_source_sha256": FileAccess.get_file_as_string("res://scripts/adventure_progress.gd").sha256_text(),
		"shop_source_sha256": FileAccess.get_file_as_string("res://scripts/port_supply_shop.gd").sha256_text(),
		"note": "Completed40coin reward history, selected HP/cooldown values, positions, KO/pending/empty inventory gates and direct combat-area loads are explicit fixtures. Actual E/GUI button callbacks buy four potions; actual boss normal contacts and H prove live healing, source/physics clocks stay unmodified. Save failures block only an owned empty directory at unique QA .tmp, then remove it. No formal save writes. Original pending profile, combat/travel metadata, actor/preferences and both persistent CD runtimes restore after old combat exits. All waits bounded; no new whole-quest or victory claim."}
	var path: String = "res://docs/"+output_prefix+"_supplies_checks.json"
	var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "  "))
		output.close()
	return {"checks": checks.size(), "failed": failed, "render_cases": render_cases.size(), "recorded_rows": records.size(), "report": path}
