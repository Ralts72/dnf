extends SceneTree
## Schema5 storage only: disposable project, unique user://qa paths, no main/autoload.
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
	node.set_meta("signals", 0)
	node.progress_changed.connect(func(): node.set_meta("signals", int(node.get_meta("signals")) + 1))
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


func _meta(first: bool = false, boss: bool = false) -> void:
	set_meta("route_hero_hp", 23)
	set_meta("first_encounter_state", {"cleared": first, "player_hp": 23, "enemy_position": Vector2(603, 317), "enemy_hp": 47})
	set_meta("tower_boss_state", {"cleared": boss, "player_hp": 23, "enemy_hp": 173})


func _health() -> Dictionary:
	return {"route": get_meta("route_hero_hp"), "first": get_meta("first_encounter_state").duplicate(true), "boss": get_meta("tower_boss_state").duplicate(true)}


func _legacy(version: int, stage: String = "completed") -> Dictionary:
	var value: Dictionary = {"schema": version, "quest_stage": stage, "objective_cleared": stage in ["return", "completed"], "reward_granted": stage == "completed", "coins": 40 if stage == "completed" else 0}
	if version >= 2:
		value.inventory = {"3128": 1 if stage == "completed" else 0}
		value.first_drop = {"id": "mirkius_first_eye_v1", "state": "claimed" if stage == "completed" else ("pending" if stage == "return" else "unearned"), "region": "hall", "position": [603, 317]}
	if version >= 3:
		value.equipment = {"owned": {"27304": stage == "completed"}, "equipped_key": "27304" if stage == "completed" else "practice_lswd0000"}
	if version == 4:
		value.chapter_flags = {"lakius_cleared": stage == "completed"}
	return value


func _funded(coins: int = 40, potions: int = 0) -> Dictionary:
	var value: Dictionary = _legacy(4)
	value.schema = 5
	value.coins = coins
	value.inventory["1106"] = potions
	return value


func _fixture(name: String, state: Dictionary) -> Node:
	_meta()
	var path: String = prefix + "/" + name + ".json"
	_write(path, JSON.stringify(state))
	return _node(path, true)


func _run() -> void:
	prefix = "user://qa/supplies_" + str(Time.get_ticks_usec())
	_meta()
	var first: Node = _node(prefix + "/normal.json")
	_check("schema5 default and authoritative potion accessors", Progress.PROFILE_SCHEMA == 5 and first.progress.schema == 5 and first.progress.inventory == {"3128": 0, "1106": 0} and first.hp_potion_count() == 0 and first.hp_potion_price() == 10 and first.hp_potion_capacity() == 4)
	var attempts: int = first.capture_state().save_attempts
	_check("empty consume and unfunded purchase do not write", not first.consume_hp_potion() and not first.buy_hp_potion() and first.capture_state().save_attempts == attempts)
	var accepted: bool = first.accept_quest()
	_meta(true)
	first._process(0.0)
	_check("quest reward remains one40 coin and weapon bundle", accepted and first.claim_reward() and first.progress.coins == 40 and first.owns_weapon("27304") and first.hp_potion_count() == 0 and not first.claim_reward())
	_meta()
	var receipts: Dictionary = first.progress.duplicate(true)
	var before: String = FileAccess.get_file_as_string(first.storage_path)
	_check("purchase atomically saves30 coins and one potion with exact backup", first.buy_hp_potion() and first.progress.coins == 30 and first.hp_potion_count() == 1 and FileAccess.get_file_as_string(first.storage_path + ".bak") == before and JSON.parse_string(FileAccess.get_file_as_string(first.storage_path)).inventory["1106"] == 1)
	_check("second purchase spends another10 without changing other receipts", first.buy_hp_potion() and first.progress.coins == 20 and first.hp_potion_count() == 2 and first.progress.first_drop == receipts.first_drop and first.progress.equipment == receipts.equipment and first.progress.chapter_flags == receipts.chapter_flags)
	var health: Dictionary = _health()
	_check("successful consume deducts one only and does not heal", first.consume_hp_potion() and first.hp_potion_count() == 1 and first.progress.coins == 20 and not first.capture_state().pending_save and _health() == health)
	_check("four historical purchases exhaust40 even after one consumption", first.buy_hp_potion() and first.buy_hp_potion() and first.progress.coins == 0 and first.hp_potion_count() == 3 and not first.buy_hp_potion() and not first.claim_reward())
	_check("remaining potions consume exactly to zero without underflow", first.consume_hp_potion() and first.consume_hp_potion() and first.consume_hp_potion() and first.hp_potion_count() == 0 and not first.consume_hp_potion() and first.progress.coins == 0)
	var reloaded: Node = _node(first.storage_path, true)
	_check("reload preserves depleted supplies and historical receipts", _same(reloaded.progress, first.progress) and not reloaded.claim_reward() and reloaded.owns_weapon("27304") and reloaded.progress.first_drop.state == "pending")

	var backups_ok: bool = true
	for version: int in [1, 2, 3, 4]:
		_meta()
		var source: Dictionary = _legacy(version)
		var path: String = prefix + "/legacy_v" + str(version) + ".json"
		var original: String = JSON.stringify(source)
		_write(path, original)
		var migrated: Node = _node(path, true)
		var expected_key: String = "27304" if version >= 3 else "practice_lswd0000"
		var preserved: bool = migrated.capture_state().storage_ready and migrated.progress.schema == 5 and migrated.hp_potion_count() == 0 and migrated.progress.coins == 40 and migrated.owns_weapon("27304") and migrated.equipped_weapon_key() == expected_key and migrated.progress.chapter_flags.lakius_cleared == (version == 4)
		if version >= 2:
			preserved = preserved and _same(migrated.progress.first_drop, source.first_drop) and migrated.progress.inventory["3128"] == 1
		_check("strict v" + str(version) + " migration adds zero potions without loading writes", preserved and FileAccess.get_file_as_string(path) == original and not FileAccess.file_exists(path + ".bak") and not FileAccess.file_exists(path + ".tmp"))
		backups_ok = migrated.save_progress() and FileAccess.get_file_as_string(path + ".bak") == original and backups_ok
	_check("first mutation keeps all four exact legacy backups", backups_ok)

	for value: Variant in [-1, 5, 1.5, true, "1"]:
		var invalid: Dictionary = _funded(0, 0)
		invalid.inventory["1106"] = value
		_check("rejects invalid potion count " + str(value), not first._valid(invalid))
	var bad_reward: Dictionary = first._default_progress()
	bad_reward.inventory["1106"] = 1
	var bad_coins: Dictionary = first._default_progress()
	bad_coins.coins = 10
	_check("unrewarded profiles cannot own currency or potions", not first._valid(bad_reward) and not first._valid(bad_coins))
	var bad_money_ok: bool = true
	for value: Variant in [-10, 5, 50, NAN, true]:
		var invalid: Dictionary = _funded()
		invalid.coins = value
		bad_money_ok = bad_money_ok and not first._valid(invalid)
	_check("coins require finite0to40 multiples10 and reject bool", bad_money_ok)
	_check("quantity cannot exceed historical spending but may be depleted", not first._valid(_funded(30, 2)) and first._valid(_funded(0, 4)) and first._valid(_funded(0, 0)))
	var missing: Dictionary = _funded()
	missing.inventory.erase("1106")
	var extra: Dictionary = _funded()
	extra.inventory["unknown"] = 0
	_check("inventory requires exactly eye and potion keys", not first._valid(missing) and not first._valid(extra))
	var old_guards: bool = true
	var invalid: Dictionary = _funded()
	invalid.inventory["3128"] = 0
	old_guards = old_guards and not first._valid(invalid)
	invalid = _funded(); invalid.equipment.owned["27304"] = false
	old_guards = old_guards and not first._valid(invalid)
	invalid = _funded(); invalid.chapter_flags["extra"] = false
	old_guards = old_guards and not first._valid(invalid)
	invalid = first._default_progress(); invalid.chapter_flags.lakius_cleared = true
	_check("eye equipment and chapter constraints remain strict", old_guards and not first._valid(invalid))
	var old_cash: Dictionary = _legacy(4)
	old_cash.coins = 30
	_check("legacy v4 spent balance is rejected rather than loosely migrated", first._normalize(old_cash).is_empty())
	var old_keys: Dictionary = _legacy(4)
	old_keys.inventory["1106"] = 0
	_check("legacy v4 two inventory keys are rejected even count zero", first._normalize(old_keys).is_empty())
	var other_legacy: bool = true
	for version: int in [1, 2, 3]:
		var legacy: Dictionary = _legacy(version)
		legacy.coins = 30
		other_legacy = other_legacy and first._normalize(legacy).is_empty()
	_check("old v1v2v3 balance validators retain original40 rule", other_legacy)

	var failed: Node = _fixture("failed_buy", _funded())
	var old: Dictionary = failed.progress.duplicate(true)
	before = FileAccess.get_file_as_string(failed.storage_path)
	_block(failed.storage_path + ".tmp")
	_check("failed purchase keeps committed state and exact pending purchase", not failed.buy_hp_potion() and failed.progress == old and failed.capture_state().pending_save and failed.get("_pending_bundle").coins == 30 and failed.get("_pending_bundle").inventory["1106"] == 1 and FileAccess.get_file_as_string(failed.storage_path) == before)
	var pending: Dictionary = failed.get("_pending_bundle").duplicate(true)
	_check("consume and other operations cannot replace pending purchase", not failed.consume_hp_potion() and not failed.buy_hp_potion() and not failed.equip_weapon("practice_lswd0000") and not failed.load_progress() and failed.get("_pending_bundle") == pending)
	_unblock(failed.storage_path + ".tmp")
	_check("generic retry commits purchase once and retains receipts", failed.retry_pending_save() and failed.progress == pending and failed.hp_potion_count() == 1 and not failed.capture_state().pending_save and FileAccess.get_file_as_string(failed.storage_path + ".bak") == before)
	health = _health()
	old = failed.progress.duplicate(true)
	before = FileAccess.get_file_as_string(failed.storage_path)
	var signals: int = int(failed.get_meta("signals"))
	_block(failed.storage_path + ".tmp")
	_check("failed use retains no deduction candidate or signal and never heals", not failed.consume_hp_potion() and failed.progress == old and not failed.capture_state().pending_save and int(failed.get_meta("signals")) == signals and _health() == health and FileAccess.get_file_as_string(failed.storage_path) == before)
	_unblock(failed.storage_path + ".tmp")
	_check("generic retry and later save cannot execute failed use", not failed.retry_pending_save() and failed.save_progress() and failed.progress == old and JSON.parse_string(FileAccess.get_file_as_string(failed.storage_path)).inventory["1106"] == 1 and _health() == health)
	# Fail after valid .tmp exists: backup rename must fail against an empty directory.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(failed.storage_path + ".bak"))
	_block(failed.storage_path + ".bak")
	_check("late use failure leaves valid temp but no pending or primary mutation", not failed.consume_hp_potion() and failed.progress == old and not failed.capture_state().pending_save and JSON.parse_string(FileAccess.get_file_as_string(failed.storage_path + ".tmp")).inventory["1106"] == 0 and JSON.parse_string(FileAccess.get_file_as_string(failed.storage_path)).inventory["1106"] == 1)
	_unblock(failed.storage_path + ".bak")
	_check("generic save overwrites stale failed-use temp without deduction", not failed.retry_pending_save() and failed.save_progress() and failed.hp_potion_count() == 1 and JSON.parse_string(FileAccess.get_file_as_string(failed.storage_path)).inventory["1106"] == 1 and _health() == health)
	_block(failed.storage_path + ".tmp")
	var equip_failed: bool = not failed.equip_weapon("practice_lswd0000")
	pending = failed.get("_pending_bundle").duplicate(true)
	_check("existing foreign pending survives both public and private nonretained use", equip_failed and failed.capture_state().pending_save and not failed.consume_hp_potion() and not failed._commit(pending, false) and failed.get("_pending_bundle") == pending and failed.hp_potion_count() == 1)
	_unblock(failed.storage_path + ".tmp")
	_check("foreign equip retry keeps potion count and applies only equip", failed.retry_pending_save() and failed.equipped_weapon_key() == "practice_lswd0000" and failed.hp_potion_count() == 1 and _health() == health)
	_meta()
	var clear: Node = _node(prefix + "/failed_clear.json")
	clear.accept_quest()
	_block(clear.storage_path + ".tmp")
	_meta(true, true)
	clear._process(0.0)
	pending = clear.get("_pending_bundle").duplicate(true)
	_check("genuine combined clear still retains default retry candidate", clear.capture_state().pending_save and clear.progress.quest_stage == "active" and pending.first_drop.state == "pending" and pending.chapter_flags.lakius_cleared and pending.inventory["1106"] == 0)
	_meta()
	_unblock(clear.storage_path + ".tmp")
	_check("combined clear retry after R retains receipts and reward once", clear.retry_pending_save() and clear.progress.chapter_flags.lakius_cleared and clear.claim_reward() and clear.progress.coins == 40 and clear.hp_potion_count() == 0 and not clear.claim_reward())
	var recovery_path: String = prefix + "/backup.json"
	var backup_text: String = JSON.stringify(_funded(20, 1))
	_write(recovery_path, "broken-supplies-primary")
	_write(recovery_path + ".bak", backup_text)
	var recovery: Node = _node(recovery_path, true)
	_check("backup recovers complete supplies equipment flags and balance", recovery.capture_state().loaded_from_backup and recovery.progress.coins == 20 and recovery.hp_potion_count() == 1 and recovery.equipped_weapon_key() == "27304" and recovery.progress.chapter_flags.lakius_cleared)
	var recovered: bool = recovery.save_progress()
	var archived: bool = false
	for name: String in DirAccess.get_files_at(recovery_path.get_base_dir()):
		if name.begins_with("backup.json.invalid.") and FileAccess.get_file_as_string(recovery_path.get_base_dir() + "/" + name) == "broken-supplies-primary":
			archived = true
	_check("recovery archives corrupt bytes and preserves exact backup", recovered and archived and FileAccess.get_file_as_string(recovery_path + ".bak") == backup_text)
	var both_path: String = prefix + "/invalid.json"
	var invalid_text: String = JSON.stringify(old_cash)
	_write(both_path, invalid_text)
	_write(both_path + ".bak", "invalid-backup")
	var both: Node = _node(both_path, true)
	_check("invalid legacy primary and invalid backup stay preserved write blocked", not both.capture_state().storage_ready and not both.buy_hp_potion() and not both.save_progress() and FileAccess.get_file_as_string(both_path) == invalid_text and FileAccess.get_file_as_string(both_path + ".bak") == "invalid-backup")
	var failures: Array[Dictionary] = []
	for item: Dictionary in checks:
		if not item.passed:
			failures.append(item)
	var report: Dictionary = {"schema": 1, "created_at": Time.get_datetime_string_from_system(true), "godot": Engine.get_version_info().string,
		"controller_sha256": FileAccess.get_sha256("res://scripts/adventure_progress.gd"), "test_script_sha256": FileAccess.get_sha256("res://tools/r4/supplies_storage_checks.gd"),
		"quest_data_sha256": FileAccess.get_sha256("res://data/first_route_quest.json"), "equipment_data_sha256": FileAccess.get_sha256("res://data/first_equipment.json"),
		"isolated_storage_prefix": prefix, "default_storage_initialized_or_written": false, "checks": checks, "count": checks.size(), "failed": failures, "all_passed": failures.is_empty(),
		"scope": "Isolated storage transactions, no main scene/autoload/gameplay. Expected directory fixtures fail temp/backup writes. Profile never heals; the H controller must apply session healing synchronously only after a true consume result."}
	var output: FileAccess = FileAccess.open("res://docs/r4_04_storage_checks.json", FileAccess.WRITE)
	assert(output != null)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print(JSON.stringify({"count": checks.size(), "failed": failures.size(), "all_passed": failures.is_empty()}))
	for node: Node in controllers:
		node.free()
	quit(0 if failures.is_empty() else 1)
