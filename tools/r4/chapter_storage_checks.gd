extends SceneTree
## Schema6 storage only: unique QA files in an isolated project without main/autoload.
const Progress = preload("res://scripts/adventure_progress.gd")
var prefix: String
var checks: Array[Dictionary] = []
var controllers: Array[Node] = []

func _initialize() -> void:
	_run.call_deferred()

func _node(path: String, existing: bool = false) -> Node:
	assert(path.begins_with("user://qa/"))
	var node: Node = Progress.new()
	root.add_child(node)
	node.set_process(false)
	node.set_physics_process(false)
	controllers.append(node)
	node.configure_storage(path, existing)
	return node

func _check(name: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"name": name, "passed": passed, "detail": detail})
	if not passed:
		push_error(name + ": " + str(detail))

func _same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _write(path: String, text: String) -> void:
	assert(path.begins_with("user://qa/"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(text)
	file.close()

func _block(path: String) -> void:
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path)) == OK)

func _unblock(path: String) -> void:
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)

func _meta(first: Variant = false, boss: Variant = false, stone: Variant = false, statue: Variant = false) -> void:
	set_meta("route_hero_hp", 23)
	set_meta("first_encounter_state", {"cleared": first, "player_hp": 23, "enemy_position": Vector2(603, 317), "enemy_hp": 47})
	set_meta("tower_boss_state", {"cleared": boss, "player_hp": 23, "enemy_hp": 173})
	set_meta("doll_gallery_state", {"cleared": stone, "player_hp": 23, "enemy_hp": 100})
	set_meta("statue_gallery_state", {"cleared": statue, "player_hp": 23, "enemy_hp": 140, "awakened": false})

func _legacy(version: int) -> Dictionary:
	var value: Dictionary = {"schema": version, "quest_stage": "completed", "objective_cleared": true, "reward_granted": true, "coins": 40}
	if version >= 2:
		value.inventory = {"3128": 1}
		value.first_drop = {"id": "mirkius_first_eye_v1", "state": "claimed", "region": "hall", "position": [603, 317]}
	if version >= 3:
		value.equipment = {"owned": {"27304": true}, "equipped_key": "27304"}
	if version >= 4:
		value.chapter_flags = {"lakius_cleared": true}
	if version >= 5:
		value.coins = 20
		value.inventory["1106"] = 1
	return value

func _current() -> Dictionary:
	var value: Dictionary = _legacy(5)
	value.schema = 6
	value.chapter_flags.stonemaster_cleared = true
	value.chapter_flags.statue_cleared = true
	return value

func _fixture(name: String, state: Dictionary) -> Node:
	_meta()
	var path: String = prefix + "/" + name + ".json"
	_write(path, JSON.stringify(state))
	return _node(path, true)

func _run() -> void:
	prefix = "user://qa/chapter_" + str(int(Time.get_unix_time_from_system())) + "_" + str(Time.get_ticks_usec())
	_meta()
	var normal: Node = _node(prefix + "/normal.json")
	_check("schema6 default exact three false chapter flags", Progress.PROFILE_SCHEMA == 6 and normal.progress.schema == 6 and normal.progress.chapter_flags == {"lakius_cleared": false, "stonemaster_cleared": false, "statue_cleared": false})
	_check("unknown chapter API cannot mint flags or write", not normal.record_chapter_clear("unknown") and not normal.chapter_cleared("unknown") and normal.capture_state().save_attempts == 0)
	var legacy_backup_ok: bool = true
	for version: int in [1, 2, 3, 4, 5]:
		_meta()
		var old: Dictionary = _legacy(version)
		var path: String = prefix + "/v" + str(version) + ".json"
		var original: String = JSON.stringify(old)
		_write(path, original)
		var migrated: Node = _node(path, true)
		var expected_weapon: String = "27304" if version >= 3 else "practice_lswd0000"
		_check("strict v" + str(version) + " migration preserves receipts budget selection and never writes", migrated.capture_state().storage_ready and migrated.progress.schema == 6 and migrated.progress.coins == (20 if version == 5 else 40) and migrated.hp_potion_count() == (1 if version == 5 else 0) and migrated.equipped_weapon_key() == expected_weapon and migrated.progress.chapter_flags == {"lakius_cleared": version >= 4, "stonemaster_cleared": false, "statue_cleared": false} and FileAccess.get_file_as_string(path) == original and not FileAccess.file_exists(path + ".bak") and not FileAccess.file_exists(path + ".tmp"))
		legacy_backup_ok = migrated.save_progress() and FileAccess.get_file_as_string(path + ".bak") == original and legacy_backup_ok
	_check("first mutation preserves exact all five legacy backups", legacy_backup_ok)
	var old_validation: bool = true
	for version: int in [1, 2, 3, 4]:
		var old: Dictionary = _legacy(version)
		old.coins = 30
		old_validation = normal._normalize(old).is_empty() and old_validation
	var old_extra: Dictionary = _legacy(4)
	old_extra.inventory["1106"] = 0
	_check("v1to4 still reject spent coins and v4 extra potion key", old_validation and normal._normalize(old_extra).is_empty())
	var old_flags: Dictionary = _legacy(5)
	old_flags.chapter_flags.stonemaster_cleared = false
	_check("v5 validates old exact one-key chapter flags before migration", normal._normalize(old_flags).is_empty())
	var missing: Dictionary = _current()
	missing.chapter_flags.erase("statue_cleared")
	var extra: Dictionary = _current()
	extra.chapter_flags.unknown = false
	_check("v6 rejects missing or extra chapter keys", not normal._valid(missing) and not normal._valid(extra))
	var flag_types_ok: bool = true
	for key: String in ["lakius_cleared", "stonemaster_cleared", "statue_cleared"]:
		for bad: Variant in [0, 1, "true", null]:
			var invalid: Dictionary = _current()
			invalid.chapter_flags[key] = bad
			flag_types_ok = not normal._valid(invalid) and flag_types_ok
	_check("all three chapter flags require actual booleans", flag_types_ok)
	var independent: Dictionary = normal._default_progress()
	independent.chapter_flags.statue_cleared = true
	_check("new receipts independently permit unaccepted unearned history", normal._valid(independent) and independent.first_drop.state == "unearned")
	independent.chapter_flags.lakius_cleared = true
	_check("old lakius requires first-drop evidence even in schema6", not normal._valid(independent))
	var money_ok: bool = true
	for bad: Variant in [-10, 5, 50, true, NAN]:
		var invalid: Dictionary = _current()
		invalid.coins = bad
		money_ok = not normal._valid(invalid) and money_ok
	var too_many: Dictionary = _current()
	too_many.inventory["1106"] = 3
	var no_reward: Dictionary = normal._default_progress()
	no_reward.inventory["1106"] = 1
	_check("old40 coin four-potion budget remains strict", money_ok and not normal._valid(too_many) and not normal._valid(no_reward) and normal.hp_potion_price() == 10 and normal.hp_potion_capacity() == 4)
	var old_receipts_ok: bool = true
	for field: String in ["eye", "ownership", "equipped", "objective"]:
		var invalid: Dictionary = _current()
		if field == "eye": invalid.inventory["3128"] = 0
		if field == "ownership": invalid.equipment.owned["27304"] = false
		if field == "equipped": invalid.equipment.equipped_key = "unknown"
		if field == "objective": invalid.objective_cleared = false
		old_receipts_ok = not normal._valid(invalid) and old_receipts_ok
	_check("loot quest equipment invariants remain intact", old_receipts_ok)
	_meta(false, false, 1, "true")
	normal._process(0.0)
	_check("truthy live values do not record chapter receipts", not normal.record_chapter_clear("stonemaster_cleared") and not normal.record_chapter_clear("statue_cleared") and normal.capture_state().save_attempts == 0)
	_meta(false, false, true)
	var meta_before: Dictionary = get_meta("doll_gallery_state").duplicate(true)
	_check("real stone victory commits chapter while quest remains available", normal.record_chapter_clear("stonemaster_cleared") and normal.progress.chapter_flags.stonemaster_cleared and normal.progress.quest_stage == "available" and normal.progress.first_drop.state == "unearned" and normal.progress.coins == 0 and get_meta("doll_gallery_state") == meta_before)
	_meta()
	var attempts: int = normal.capture_state().save_attempts
	for index: int in range(10): normal._process(0.0)
	_check("R live false cannot revoke history or write again", normal.chapter_cleared("stonemaster_cleared", false) and normal.record_chapter_clear("stonemaster_cleared") and normal.capture_state().save_attempts == attempts)
	_meta(false, false, false, true)
	normal._process(0.0)
	_check("process observes statue strictclear once without callbacks", normal.progress.chapter_flags.statue_cleared and normal.capture_state().save_attempts == attempts + 1 and not normal.capture_state().chapter_attempt_due)
	_meta()
	var combined: Node = _node(prefix + "/combined.json")
	combined.accept_quest()
	attempts = combined.capture_state().save_attempts
	_meta(true, true, true, true)
	combined._process(0.0)
	_check("simultaneous four victories share one atomic bundle", combined.capture_state().save_attempts == attempts + 1 and combined.progress.quest_stage == "return" and combined.progress.first_drop.state == "pending" and combined.progress.chapter_flags == {"lakius_cleared": true, "stonemaster_cleared": true, "statue_cleared": true})
	_meta()
	_check("reward pickup equip purchase consume never revoke chapters", combined.claim_reward() and combined.claim_first_drop() and combined.equip_weapon("27304") and combined.buy_hp_potion() and combined.consume_hp_potion() and combined.progress.chapter_flags.statue_cleared and combined.progress.chapter_flags.stonemaster_cleared and combined.progress.coins == 30 and combined.hp_potion_count() == 0 and not combined.claim_reward())

	var queued: Node = _fixture("queued", _legacy(5))
	var before: Dictionary = queued.progress.duplicate(true)
	var bytes_before: String = FileAccess.get_file_as_string(queued.storage_path)
	_block(queued.storage_path + ".tmp")
	_check("failed older purchase retains committed image and exact pending A", not queued.buy_hp_potion() and queued.progress == before and queued.capture_state().pending_save and queued.get("_pending_bundle").coins == 10 and queued.get("_pending_bundle").inventory["1106"] == 2)
	var pending: Dictionary = queued.get("_pending_bundle").duplicate(true)
	_meta(false, false, true, true)
	_check("real later victories queue RAM without changing pending A", not queued.record_chapter_clear("stonemaster_cleared") and not queued.record_chapter_clear("statue_cleared") and queued.get("_pending_bundle") == pending and queued.capture_state().chapter_receipts == {"stonemaster_cleared": true, "statue_cleared": true} and not queued.chapter_cleared("statue_cleared", false) and queued.chapter_cleared("statue_cleared"))
	_meta()
	attempts = queued.capture_state().save_attempts
	for index: int in range(20): queued._process(0.0)
	_check("pending A never auto retries and R cannot erase RAM receipts", queued.capture_state().save_attempts == attempts and queued.get("_pending_bundle") == pending and queued.capture_state().chapter_receipts.statue_cleared and FileAccess.get_file_as_string(queued.storage_path) == bytes_before)
	_check("reload and potion consume reject queued pending without losing receipt", not queued.load_progress() and not queued.consume_hp_potion() and queued.get("_pending_bundle") == pending and queued.capture_state().chapter_receipts.stonemaster_cleared)
	_unblock(queued.storage_path + ".tmp")
	_check("manual retry commits exact A only and schedules receipts separately", queued.retry_pending_save() and _same(queued.progress, pending) and not queued.progress.chapter_flags.statue_cleared and not queued.capture_state().pending_save and queued.capture_state().chapter_attempt_due and queued.capture_state().chapter_receipts.statue_cleared)
	attempts = queued.capture_state().save_attempts
	_block(queued.storage_path + ".tmp")
	queued._process(0.0)
	var chapter_pending: Dictionary = queued.get("_pending_bundle").duplicate(true)
	_check("next process attempts B once preserving exact purchased balance", queued.capture_state().save_attempts == attempts + 1 and queued.capture_state().pending_save and not queued.capture_state().chapter_attempt_due and chapter_pending.chapter_flags.statue_cleared and chapter_pending.chapter_flags.stonemaster_cleared and chapter_pending.coins == 10 and chapter_pending.inventory["1106"] == 2 and _same(queued.progress, pending))
	attempts = queued.capture_state().save_attempts
	for index: int in range(20): queued._process(0.0)
	_check("failed receipt B does not retry every frame", queued.capture_state().save_attempts == attempts and queued.get("_pending_bundle") == chapter_pending)
	_unblock(queued.storage_path + ".tmp")
	_check("manual retry commits B once and settles verified RAM", queued.save_progress() and queued.progress == chapter_pending and not queued.capture_state().pending_save and not queued.capture_state().chapter_attempt_due and queued.capture_state().chapter_receipts == {"stonemaster_cleared": false, "statue_cleared": false})
	var reloaded: Node = _node(queued.storage_path, true)
	_check("chapter purchase equipment loot bundle roundtrips exactly", _same(reloaded.progress, queued.progress) and reloaded.progress.coins == 10 and reloaded.hp_potion_count() == 2 and reloaded.equipped_weapon_key() == "27304")

	var direct: Node = _node(prefix + "/direct_failure.json")
	_meta(false, false, false, true)
	_block(direct.storage_path + ".tmp")
	_check("direct chapter failure rolls back memory with exact retry receipt", not direct.record_chapter_clear("statue_cleared") and not direct.progress.chapter_flags.statue_cleared and direct.capture_state().pending_save and direct.get("_pending_bundle").chapter_flags.statue_cleared)
	_meta()
	_unblock(direct.storage_path + ".tmp")
	_check("direct failed victory persists after R through generic retry", direct.retry_pending_save() and direct.progress.chapter_flags.statue_cleared and not direct.capture_state().chapter_receipts.statue_cleared)
	var blocked: Node = _node(prefix + "/storage_not_ready.json")
	blocked.set("_storage_ready", false)
	_meta(false, false, true)
	blocked._process(0.0)
	attempts = blocked.capture_state().save_attempts
	for index: int in range(20): blocked._process(0.0)
	_check("storage-ready failure has no pending and still attempts only once", attempts == 1 and blocked.capture_state().save_attempts == attempts and not blocked.capture_state().pending_save and not blocked.capture_state().chapter_attempt_due and blocked.capture_state().chapter_receipts.stonemaster_cleared)
	_meta()
	_check("load cannot discard verified unsaved RAM when no pending exists", not blocked.load_progress() and blocked.capture_state().chapter_receipts.stonemaster_cleared)
	blocked.set("_storage_ready", true)
	_check("explicit save retries unbundled verified receipt after repair", blocked.save_progress() and blocked.progress.chapter_flags.stonemaster_cleared)
	_meta()
	var consumable: Node = _fixture("consume_failure", _current())
	var consume_before: Dictionary = consumable.progress.duplicate(true)
	_block(consumable.storage_path + ".tmp")
	_check("failed consumable still retains no deduction pending", not consumable.consume_hp_potion() and consumable.progress == consume_before and not consumable.capture_state().pending_save)
	_unblock(consumable.storage_path + ".tmp")
	_check("generic retry cannot later deduct failed consume", not consumable.retry_pending_save() and consumable.save_progress() and consumable.hp_potion_count() == 1)

	var seed_path: String = prefix + "/seed.json"
	_write(seed_path, JSON.stringify(_current()))
	for key: String in ["first_encounter_state", "tower_boss_state", "doll_gallery_state", "statue_gallery_state"]: remove_meta(key)
	var seeded: Node = _node(seed_path, true)
	_check("historical clear seeds absent gallery dead and statue fully awakened", seeded.capture_state().storage_ready and get_meta("doll_gallery_state") == {"cleared": true, "enemy_hp": 0} and get_meta("statue_gallery_state") == {"cleared": true, "enemy_hp": 0, "awakened": true})
	_meta()
	var practice_stone: Dictionary = get_meta("doll_gallery_state").duplicate(true)
	var practice_statue: Dictionary = get_meta("statue_gallery_state").duplicate(true)
	seeded.load_progress()
	_check("load never overwrites existing practice false HP awake or counters", get_meta("doll_gallery_state") == practice_stone and get_meta("statue_gallery_state") == practice_statue and seeded.chapter_cleared("statue_cleared", false))
	var configured: Node = _node(prefix + "/before_reconfigure.json")
	_meta(false, false, false, true)
	_block(configured.storage_path + ".tmp")
	assert(not configured.record_chapter_clear("statue_cleared"))
	assert(configured.capture_state().pending_save and configured.capture_state().chapter_receipts.statue_cleared)
	var reset_ok: bool = configured.configure_storage(prefix + "/reconfigured.json", false)
	_check("configure storage resets nonempty receipts due and pending explicitly", reset_ok and not configured.progress.chapter_flags.statue_cleared and not configured.capture_state().chapter_attempt_due and configured.capture_state().chapter_receipts == {"stonemaster_cleared": false, "statue_cleared": false} and not configured.capture_state().pending_save)

	_meta()
	var recovery_path: String = prefix + "/backup.json"
	var backup_text: String = JSON.stringify(_current())
	_write(recovery_path, "broken-primary-chapter")
	_write(recovery_path + ".bak", backup_text)
	var recovery: Node = _node(recovery_path, true)
	_check("backup recovers coherent flags supplies ownership and selection", recovery.capture_state().loaded_from_backup and recovery.progress.chapter_flags.statue_cleared and recovery.progress.chapter_flags.stonemaster_cleared and recovery.hp_potion_count() == 1 and recovery.progress.coins == 20 and recovery.equipped_weapon_key() == "27304")
	var saved: bool = recovery.save_progress()
	var archived: bool = false
	for name: String in DirAccess.get_files_at(recovery_path.get_base_dir()):
		if name.begins_with("backup.json.invalid.") and FileAccess.get_file_as_string(recovery_path.get_base_dir() + "/" + name) == "broken-primary-chapter": archived = true
	_check("recovery commit preserves corrupt bytes and exact valid backup", saved and archived and FileAccess.get_file_as_string(recovery_path + ".bak") == backup_text)
	var invalid_path: String = prefix + "/invalid.json"
	_write(invalid_path, JSON.stringify(missing))
	_write(invalid_path + ".bak", "invalid-backup")
	var invalid_node: Node = _node(invalid_path, true)
	_check("both invalid preserved with writes blocked", not invalid_node.capture_state().storage_ready and not invalid_node.save_progress() and FileAccess.get_file_as_string(invalid_path) == JSON.stringify(missing) and FileAccess.get_file_as_string(invalid_path + ".bak") == "invalid-backup")
	var oversized: String = prefix + "/oversized.json"
	_write(oversized, " ".repeat(16385))
	_check("oversized profile rejected without mutation", not _node(oversized, true).capture_state().storage_ready and FileAccess.get_file_as_string(oversized).length() == 16385)
	var failures: Array[Dictionary] = []
	for item: Dictionary in checks:
		if not item.passed: failures.append(item)
	var report: Dictionary = {"schema": 1, "stage": "R4/10", "created_at": Time.get_datetime_string_from_system(true), "godot": Engine.get_version_info().string,
		"controller_sha256": FileAccess.get_sha256("res://scripts/adventure_progress.gd"), "test_script_sha256": FileAccess.get_sha256("res://tools/r4/chapter_storage_checks.gd"),
		"isolated_storage_prefix": prefix, "default_storage_initialized_or_written": false, "checks": checks, "count": checks.size(), "failed": failures, "all_passed": failures.is_empty(),
		"scope": "Isolated schema6 storage only. No main, autoload, gameplay, formal profile or healing side effects. RAM receipts preserve strict observed victories across older exact pending bundles and practice reset; they are not durable until their own atomic commit."}
	var output: FileAccess = FileAccess.open("res://docs/r4_10_storage_checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("CHAPTER_STORAGE_CHECKS " + str(checks.size()) + " passed=" + str(failures.is_empty()))
	for controller: Node in controllers: controller.queue_free()
	quit(0 if failures.is_empty() else 1)
