extends SceneTree
## Schema4 receipt/flag tests in a disposable project. Never initialize the
## formal profile, a main scene, autoload, visual encounter or runtime input.

const Progress = preload("res://scripts/adventure_progress.gd")
var prefix: String
var checks: Array[Dictionary] = []
var controllers: Array[Node] = []


func _initialize() -> void:
	_run.call_deferred()


func _node(path: String, existing: bool = false) -> Node:
	assert(path.begins_with("user://qa/"))
	var controller: Node = Progress.new()
	root.add_child(controller)
	controller.set_process(false)
	controller.set_physics_process(false)
	controller.set_meta("signal_count", 0)
	controller.progress_changed.connect(func(): controller.set_meta("signal_count", int(controller.get_meta("signal_count")) + 1))
	controllers.append(controller)
	controller.configure_storage(path, existing)
	return controller


func _check(name: String, passed: bool, details: Variant = null) -> void:
	checks.append({"name": name, "passed": passed, "details": details})
	if not passed:
		push_error(name + ": " + str(details))


func _same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _write(path: String, text: String) -> void:
	assert(path.begins_with("user://qa/"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(text)
	file.close()


func _meta(first_clear: Variant = false, boss_clear: Variant = false) -> void:
	set_meta("first_encounter_state", {"cleared": first_clear, "enemy_position": Vector2(603, 317)})
	set_meta("tower_boss_state", {"cleared": boss_clear})


func _v1(stage: String = "completed") -> Dictionary:
	return {"schema": 1, "quest_stage": stage, "objective_cleared": stage in ["return", "completed"],
		"reward_granted": stage == "completed", "coins": 40 if stage == "completed" else 0}


func _v2(stage: String = "completed", claimed: bool = true) -> Dictionary:
	var value: Dictionary = _v1(stage)
	value.schema = 2
	value.inventory = {"3128": 1 if claimed else 0}
	value.first_drop = {"id": "mirkius_first_eye_v1", "state": "claimed" if claimed else ("pending" if stage in ["return", "completed"] else "unearned"),
		"region": "hall", "position": [603, 317]}
	return value


func _v3(stage: String = "completed", equipped: bool = true) -> Dictionary:
	var value: Dictionary = _v2(stage, stage == "completed")
	value.schema = 3
	value.equipment = {"owned": {"27304": stage == "completed"}, "equipped_key": "27304" if equipped else "practice_lswd0000"}
	return value


func _v4(flag: bool = false, stage: String = "completed", equipped: bool = true) -> Dictionary:
	var value: Dictionary = _v3(stage, equipped)
	value.schema = 4
	value.chapter_flags = {"lakius_cleared": flag}
	return value


func _block(path: String) -> void:
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path + ".tmp")) == OK)


func _unblock(path: String) -> void:
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp")) == OK)


func _run() -> void:
	prefix = "user://qa/tower_boss_" + str(Time.get_ticks_usec())
	_meta()
	var first: Node = _node(prefix + "/default.json")
	_check("schema4 default contains only a false chapter flag", Progress.PROFILE_SCHEMA == 4 and first.progress.schema == 4 and first.progress.chapter_flags == {"lakius_cleared": false} and not FileAccess.file_exists(first.storage_path))

	# Historical formats normalize in memory only; each keeps its existing policy.
	var migrations: Array[Dictionary] = [_v1(), _v2("available", true), _v3()]
	var migration_backups: bool = true
	for index: int in migrations.size():
		_meta()
		var legacy: Dictionary = migrations[index]
		var path: String = prefix + "/migration_v" + str(index + 1) + ".json"
		var original: String = JSON.stringify(legacy)
		_write(path, original)
		var migrated: Node = _node(path, true)
		var preserved: bool = migrated.capture_state().storage_ready and migrated.progress.schema == 4 and migrated.progress.chapter_flags == {"lakius_cleared": false} and migrated.progress.quest_stage == legacy.quest_stage
		if index == 0:
			preserved = preserved and migrated.owns_weapon("27304") and migrated.equipped_weapon_key() == "practice_lswd0000" and migrated.progress.first_drop.state == "pending"
		elif index == 1:
			preserved = preserved and not migrated.owns_weapon("27304") and migrated.equipped_weapon_key() == "practice_lswd0000" and _same(migrated.progress.inventory, legacy.inventory) and _same(migrated.progress.first_drop, legacy.first_drop)
		else:
			preserved = preserved and _same(migrated.progress.equipment, legacy.equipment) and _same(migrated.progress.inventory, legacy.inventory) and _same(migrated.progress.first_drop, legacy.first_drop) and migrated.weapon_damage_bonus() == 4
		_check("v" + str(index + 1) + " migration preserves legitimate equipment material and receipts", preserved)
		_check("v" + str(index + 1) + " migration does not rewrite or create sidecars", FileAccess.get_file_as_string(path) == original and not FileAccess.file_exists(path + ".bak") and not FileAccess.file_exists(path + ".tmp"))
		migration_backups = migrated.save_progress() and FileAccess.get_file_as_string(path + ".bak") == original and JSON.parse_string(FileAccess.get_file_as_string(path)).schema == 4 and migration_backups
	_check("first mutation retains exact legacy backups for all three formats", migration_backups)

	# Strict flag validation must never treat a malformed v4 as a legacy profile.
	var bad_flags: Array = [null, [], {}, {"lakius_cleared": 1}, {"lakius_cleared": "true"}, {"lakius_cleared": null}, {"lakius_cleared": false, "extra": false}]
	for index: int in bad_flags.size():
		_meta()
		var invalid: Dictionary = _v4()
		invalid.chapter_flags = bad_flags[index]
		var path: String = prefix + "/bad_flags_" + str(index) + ".json"
		var original: String = JSON.stringify(invalid)
		_write(path, original)
		var rejected: Node = _node(path, true)
		_check("strict v4 rejects malformed chapter flags " + str(index), not rejected.capture_state().storage_ready and not rejected.save_progress() and FileAccess.get_file_as_string(path) == original and not FileAccess.file_exists(path + ".bak"))
	_meta()
	var missing: Dictionary = _v4()
	missing.erase("chapter_flags")
	_check("v4 requires chapter_flags and cannot infer a default", not first._valid(missing))
	var unearned: Dictionary = _v4(true, "available", false)
	_check("boss receipt without earned first encounter is invalid", not first._valid(unearned))

	# Strict metadata values and gate prerequisites: no truthy-value credit.
	var truthy_ok: bool = true
	var truthy_details: Array[Dictionary] = []
	for value: Variant in [1, "true", [], {"cleared": true}]:
		_meta(false, value)
		var path: String = prefix + "/truthy_" + str(truthy_details.size()) + ".json"
		var receipt: Dictionary = _v4(false)
		_write(path, JSON.stringify(receipt))
		var truthy: Node = _node(path, true)
		var attempts: int = truthy.capture_state().save_attempts
		truthy._process(0.0)
		var result: bool = not truthy.progress.chapter_flags.lakius_cleared and truthy.capture_state().save_attempts == attempts
		truthy_ok = truthy_ok and result
		truthy_details.append({"value": value, "passed": result})
	_check("nonboolean boss metadata cannot mint a flag or write", truthy_ok, truthy_details)
	_meta(false, true)
	var no_first: Node = _node(prefix + "/boss_without_first.json")
	no_first._process(0.0)
	_check("real boss metadata alone cannot forge the prerequisite first kill", no_first.progress.first_drop.state == "unearned" and not no_first.progress.chapter_flags.lakius_cleared and not no_first.capture_state().pending_save)

	# A real clear without a quest records both receipts once in one transaction.
	_meta(true, true)
	var early: Node = _node(prefix + "/early_combined.json")
	var attempts: int = early.capture_state().save_attempts
	early._process(0.0)
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(early.storage_path))
	_check("first and boss clear before quest commit one complete bundle", early.progress.quest_stage == "available" and not early.progress.objective_cleared and early.progress.first_drop.state == "pending" and early.progress.chapter_flags.lakius_cleared and early.capture_state().save_attempts == attempts + 1 and _same(disk, early.progress))
	attempts = early.capture_state().save_attempts
	for _index: int in 6:
		early._process(0.0)
	_check("repeated real clear observation saves only once", early.capture_state().save_attempts == attempts)
	_meta()
	for _index: int in 4:
		early._process(0.0)
	_check("practice reset cannot revoke the historical boss receipt", early.progress.chapter_flags.lakius_cleared and early.capture_state().save_attempts == attempts)
	_check("later quest acceptance uses history and retains boss flag", early.accept_quest() and early.progress.quest_stage == "return" and early.progress.chapter_flags.lakius_cleared)
	_check("reward still grants40 and27304 once without altering boss flag", early.claim_reward() and early.progress.coins == 40 and early.owns_weapon("27304") and early.progress.chapter_flags.lakius_cleared and not early.claim_reward())
	_check("pickup preserves boss flag and commits one eye", early.claim_first_drop() and early.progress.chapter_flags.lakius_cleared and early.progress.inventory["3128"] == 1 and not early.claim_first_drop())
	_check("equip preserves boss flag all receipts and existing bonus4", early.equip_weapon("27304") and early.progress.chapter_flags.lakius_cleared and early.progress.first_drop.state == "claimed" and early.weapon_damage_bonus() == 4 and early.progress.coins == 40)
	remove_meta("first_encounter_state")
	remove_meta("tower_boss_state")
	var loaded: Node = _node(early.storage_path, true)
	_check("flagged load seeds absent boss and first-clear metadata", get_meta("tower_boss_state", {}).get("cleared", false) == true and get_meta("first_encounter_state", {}).get("cleared", false) == true and _same(loaded.progress, early.progress))
	_meta()
	var existing_meta: Node = _node(early.storage_path, true)
	_check("flagged load does not overwrite an existing practice reset", get_meta("tower_boss_state", {}).get("cleared", true) == false and existing_meta.progress.chapter_flags.lakius_cleared)

	_meta()
	var explicit: Node = _node(prefix + "/explicit_save.json")
	_check("active quest setup stays unchanged", explicit.accept_quest() and explicit.progress.quest_stage == "active")
	_meta(true, true)
	attempts = explicit.capture_state().save_attempts
	_check("explicit save merges real first boss and active quest receipts atomically", explicit.save_progress() and explicit.progress.quest_stage == "return" and explicit.progress.objective_cleared and explicit.progress.first_drop.state == "pending" and explicit.progress.chapter_flags.lakius_cleared and explicit.capture_state().save_attempts == attempts + 1)

	# Force temporary writes to fail; exact observed events must survive R/reset.
	_meta()
	var failed_path: String = prefix + "/failed_boss.json"
	_write(failed_path, JSON.stringify(_v4(false)))
	var failed: Node = _node(failed_path, true)
	var old_bytes: String = FileAccess.get_file_as_string(failed_path)
	var old_state: Dictionary = failed.progress.duplicate(true)
	var signals: int = int(failed.get_meta("signal_count"))
	_block(failed_path)
	_meta(false, true)
	failed._process(0.0)
	var pending: Dictionary = failed.get("_pending_bundle").duplicate(true)
	_check("failed boss write retains old committed profile and exact pending flag", failed.capture_state().pending_save and failed.progress == old_state and not failed.progress.chapter_flags.lakius_cleared and pending.chapter_flags.lakius_cleared and _same(pending.equipment, old_state.equipment) and FileAccess.get_file_as_string(failed_path) == old_bytes and int(failed.get_meta("signal_count")) == signals)
	attempts = failed.capture_state().save_attempts
	_meta()
	for _index: int in 6:
		failed._process(0.0)
	_check("failed boss event is latched across R without write retry loop", failed.capture_state().save_attempts == attempts and failed.get("_pending_bundle") == pending)
	_check("other operations cannot replace the pending boss transaction", not failed.accept_quest() and not failed.claim_reward() and not failed.claim_first_drop() and not failed.equip_weapon("practice_lswd0000") and not failed.load_progress() and failed.get("_pending_bundle") == pending)
	_unblock(failed_path)
	_check("retry after R commits original flag and equipped ownership once", failed.retry_pending_save() and failed.progress == pending and failed.progress.chapter_flags.lakius_cleared and failed.equipped_weapon_key() == "27304" and failed.weapon_damage_bonus() == 4 and not failed.capture_state().pending_save and int(failed.get_meta("signal_count")) == signals + 1)
	_check("boss retry preserves exact old primary as backup", FileAccess.get_file_as_string(failed_path + ".bak") == old_bytes and not FileAccess.file_exists(failed_path + ".tmp"))

	# Backup recovery must restore the flag with the same material/ownership bundle.
	_meta()
	var recovery_path: String = prefix + "/backup_flag.json"
	var backup_bytes: String = JSON.stringify(_v4(true))
	_write(recovery_path, "corrupt-boss-primary")
	_write(recovery_path + ".bak", backup_bytes)
	var recovered: Node = _node(recovery_path, true)
	_check("valid backup recovers boss flag equipment material and reward together", recovered.capture_state().loaded_from_backup and recovered.progress.chapter_flags.lakius_cleared and recovered.equipped_weapon_key() == "27304" and recovered.owns_weapon("27304") and recovered.progress.inventory["3128"] == 1 and recovered.progress.coins == 40)
	var recovery_saved: bool = recovered.save_progress()
	var archived: bool = false
	var directory: DirAccess = DirAccess.open(recovery_path.get_base_dir())
	for name: String in directory.get_files():
		if name.begins_with("backup_flag.json.invalid.") and FileAccess.get_file_as_string(recovery_path.get_base_dir() + "/" + name) == "corrupt-boss-primary":
			archived = true
	_check("recovery commit archives corrupt primary and keeps exact flagged backup", recovery_saved and archived and FileAccess.get_file_as_string(recovery_path + ".bak") == backup_bytes and _same(JSON.parse_string(FileAccess.get_file_as_string(recovery_path)), recovered.progress))
	_meta()
	var both_path: String = prefix + "/both_invalid.json"
	_write(both_path, JSON.stringify(unearned))
	_write(both_path + ".bak", "invalid-backup")
	var both: Node = _node(both_path, true)
	_check("invalid flag prerequisite and invalid backup preserve both files write-blocked", not both.capture_state().storage_ready and not both.save_progress() and FileAccess.get_file_as_string(both_path) == JSON.stringify(unearned) and FileAccess.get_file_as_string(both_path + ".bak") == "invalid-backup")

	var failures: Array[Dictionary] = []
	for item: Dictionary in checks:
		if not item.passed:
			failures.append(item)
	var report: Dictionary = {"schema": 1, "created_at": Time.get_datetime_string_from_system(true),
		"godot": Engine.get_version_info().string, "test_script": "res://tools/r4/boss_storage_checks.gd",
		"controller_sha256": FileAccess.get_sha256("res://scripts/adventure_progress.gd"),
		"quest_data_sha256": FileAccess.get_sha256("res://data/first_route_quest.json"),
		"equipment_data_sha256": FileAccess.get_sha256("res://data/first_equipment.json"),
		"test_script_sha256": FileAccess.get_sha256("res://tools/r4/boss_storage_checks.gd"),
		"isolated_storage_prefix": prefix, "default_storage_initialized_or_written": false,
		"scope": "Disposable headless SceneTree; no main scene/autoload/gameplay. Temporary-directory write failures are expected isolated fixtures.",
		"checks": checks, "count": checks.size(), "failed": failures, "all_passed": failures.is_empty()}
	var output: FileAccess = FileAccess.open("res://docs/r4_01_storage_checks.json", FileAccess.WRITE)
	assert(output != null)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print(JSON.stringify({"count": checks.size(), "failed": failures.size(), "all_passed": failures.is_empty(), "report": "docs/r4_01_storage_checks.json"}))
	for controller: Node in controllers:
		controller.free()
	quit(0 if failures.is_empty() else 1)
