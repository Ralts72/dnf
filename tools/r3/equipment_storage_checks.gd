extends SceneTree
## Isolated schema3 transactions. Only user://qa is configured; no area, main
## scene, autoload, input or human profile is initialized. Use a scratch project.

const Progress = preload("res://scripts/adventure_progress.gd")
var prefix: String
var checks: Array[Dictionary] = []
var controllers: Array[Node] = []


func _initialize() -> void:
	_run.call_deferred()


func _node(path: String, existing: bool = false) -> Node:
	var controller: Node = Progress.new()
	root.add_child(controller)
	controller.set_process(false)
	controller.set_physics_process(false)
	controller.set_meta("signal_count", 0)
	controller.progress_changed.connect(func(): controller.set_meta("signal_count", int(controller.get_meta("signal_count")) + 1))
	controllers.append(controller)
	controller.configure_storage(path, existing)
	return controller


func _signals(controller: Node) -> int:
	return int(controller.get_meta("signal_count"))


func _check(name: String, passed: bool, details: Variant = null) -> void:
	checks.append({"name": name, "passed": passed, "details": details})
	if not passed:
		push_error(name + ": " + str(details))


func _json_equal(left: Variant, right: Variant) -> bool:
	# JSON numbers load as floats; compare persisted values without requiring
	# the same in-memory int/float Variant types used to build a fixture.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(text)
	file.close()


func _meta(cleared: bool) -> void:
	set_meta("first_encounter_state", {"cleared": cleared, "enemy_position": Vector2(603,317)})


func _v1(stage: String) -> Dictionary:
	return {"schema":1,"quest_stage":stage,"objective_cleared":stage in ["return","completed"],
		"reward_granted":stage == "completed","coins":40 if stage == "completed" else 0}


func _v2(stage: String, claimed: bool = false) -> Dictionary:
	var value: Dictionary = _v1(stage)
	value.schema = 2
	value.inventory = {"3128":1 if claimed else 0}
	value.first_drop = {"id":"mirkius_first_eye_v1","state":"claimed" if claimed else ("pending" if stage in ["return","completed"] else "unearned"),"region":"hall","position":[603,317]}
	return value


func _v3(stage: String = "available", equipped: bool = false) -> Dictionary:
	var value: Dictionary = _v2(stage,stage == "completed")
	value.schema = 3
	value.equipment = {"owned":{"27304":stage == "completed"},"equipped_key":"27304" if equipped else "practice_lswd0000"}
	return value


func _block_temporary(path: String) -> void:
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path + ".tmp")) == OK)


func _unblock_temporary(path: String) -> void:
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp")) == OK)


func _run() -> void:
	prefix = "user://qa/first_equipment_" + str(Time.get_ticks_usec())
	_meta(false)
	var first: Node = _node(prefix + "/normal.json")
	_check("default schema3 preserves practice appearance and zero bonus", first.progress.schema == 3 and first.equipped_weapon_key() == "practice_lswd0000" and first.weapon_damage_bonus() == 0 and first.owns_weapon("practice_lswd0000") and not first.owns_weapon("27304"))
	_check("configure false emits one committed progress signal", _signals(first) == 1)
	var signals_before: int = _signals(first)
	_check("missing-file load succeeds and signals without writing", first.load_progress() and _signals(first) == signals_before+1 and not FileAccess.file_exists(first.storage_path))
	var attempts: int = first.capture_state().save_attempts
	signals_before = _signals(first)
	_check("unknown and unowned equips rejected without save or signal", not first.equip_weapon("27304") and not first.equip_weapon("forged") and not first.owns_weapon("forged") and first.capture_state().save_attempts == attempts and _signals(first) == signals_before)
	_check("practice equip is an idempotent no-op", first.equip_weapon("practice_lswd0000") and first.capture_state().save_attempts == attempts and _signals(first) == signals_before)
	_check("quest acceptance still commits active state", first.accept_quest() and first.progress.quest_stage == "active" and not first.owns_weapon("27304"))
	_meta(true)
	first._process(0.0)
	_check("clear atomically records quest receipt and pending drop before reward", first.progress.quest_stage == "return" and first.progress.objective_cleared and first.progress.first_drop.state == "pending" and first.progress.first_drop.position == [603.0,317.0] and first.progress.inventory["3128"] == 0 and not first.owns_weapon("27304"))
	signals_before = _signals(first)
	_check("claim atomically grants40 and weapon without auto-equip", first.claim_reward() and first.progress.coins == 40 and first.progress.reward_granted and first.owns_weapon("27304") and first.equipped_weapon_key() == "practice_lswd0000" and first.weapon_damage_bonus() == 0 and _signals(first) == signals_before+1)
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(first.storage_path))
	_check("claim primary contains one complete schema3 bundle", disk.schema == 3 and disk.coins == 40 and disk.equipment.owned["27304"] and disk.equipment.equipped_key == "practice_lswd0000" and disk.first_drop.state == "pending")
	var backup: Dictionary = first._read_valid(first.storage_path + ".bak")
	_check("claim backup is complete previous unowned return state", backup.quest_stage == "return" and backup.coins == 0 and not backup.equipment.owned["27304"])
	attempts = first.capture_state().save_attempts
	signals_before = _signals(first)
	_check("reward cannot duplicate coins or ownership", not first.claim_reward() and first.progress.coins == 40 and first.capture_state().save_attempts == attempts and _signals(first) == signals_before)
	_check("pickup after reward retains equipment ownership", first.claim_first_drop() and first.progress.inventory["3128"] == 1 and first.progress.first_drop.state == "claimed" and first.owns_weapon("27304"))
	var receipt: Dictionary = first.progress.first_drop.duplicate(true)
	signals_before = _signals(first)
	_check("equip saves ownership plus key and derives catalog bonus4", first.equip_weapon("27304") and first.equipped_weapon_key() == "27304" and first.weapon_damage_bonus() == 4 and first.progress.first_drop == receipt and first.progress.coins == 40 and _signals(first) == signals_before+1)
	_check("bonus is not persisted in equipment", first.progress.equipment.size() == 2 and not first.progress.equipment.has("bonus") and not FileAccess.get_file_as_string(first.storage_path).contains("damage_bonus"))
	var reloaded: Node = _node(first.storage_path,true)
	_check("reload keeps owned and equipped key with bonus4", reloaded.equipped_weapon_key() == "27304" and reloaded.owns_weapon("27304") and reloaded.weapon_damage_bonus() == 4 and _signals(reloaded) == 1)
	_meta(false)
	var before_reset: Dictionary = first.progress.duplicate(true)
	attempts = first.capture_state().save_attempts
	for _index: int in 5:
		first._process(0.0)
	_check("practice reset observation cannot revoke quest loot or equipment", first.progress == before_reset and first.capture_state().save_attempts == attempts)
	_check("switch back to practice persists bonus0 and retains ownership", first.equip_weapon("practice_lswd0000") and first.weapon_damage_bonus() == 0 and first.owns_weapon("27304") and first.progress.first_drop == receipt)

	for version: int in [1,2]:
		for stage: String in ["available","active","return","completed"]:
			_meta(false)
			var path: String = prefix + "/v" + str(version) + "_" + stage + ".json"
			var source: Dictionary = _v1(stage) if version == 1 else _v2(stage,stage == "completed")
			var source_text: String = JSON.stringify(source)
			_write(path,source_text)
			var migrated: Node = _node(path,true)
			var owns: bool = stage == "completed"
			_check("v" + str(version) + " " + stage + " migration owns only legitimate completed and keeps practice", migrated.capture_state().storage_ready and migrated.progress.schema == 3 and migrated.owns_weapon("27304") == owns and migrated.equipped_weapon_key() == "practice_lswd0000" and migrated.weapon_damage_bonus() == 0 and migrated.progress.quest_stage == stage and _signals(migrated) == 1)
			_check("v" + str(version) + " " + stage + " load never rewrites original", FileAccess.get_file_as_string(path) == source_text and not FileAccess.file_exists(path + ".bak") and not FileAccess.file_exists(path + ".tmp"))
			if version == 2:
				_check("v2 " + stage + " inventory and drop values remain exact", _json_equal(migrated.progress.inventory,source.inventory) and _json_equal(migrated.progress.first_drop,source.first_drop))
			_check("v" + str(version) + " " + stage + " next save retains exact old backup", migrated.save_progress() and FileAccess.get_file_as_string(path + ".bak") == source_text and JSON.parse_string(FileAccess.get_file_as_string(path)).schema == 3)

	# Regress the before-quest drop path independently of completed ownership.
	_meta(true)
	var early: Node = _node(prefix + "/early_clear.json")
	early._process(0.0)
	_meta(false)
	_check("kill before accepting creates material receipt without weapon", early.progress.quest_stage == "available" and early.progress.first_drop.state == "pending" and not early.owns_weapon("27304"))
	_check("early pickup and later accept do not replay clear or erase material", early.claim_first_drop() and early.accept_quest() and early.progress.quest_stage == "return" and early.progress.inventory["3128"] == 1)
	_check("early route reward remains one atomic grant", early.claim_reward() and early.progress.coins == 40 and early.owns_weapon("27304") and not early.claim_reward() and not early.claim_first_drop())
	set_meta("first_encounter_state",{"cleared":1})
	var truthy: Node = _node(prefix + "/truthy.json")
	truthy.accept_quest()
	truthy._process(0.0)
	_check("numeric truthy encounter flag still cannot grant reward or weapon", truthy.progress.quest_stage == "active" and not truthy.progress.objective_cleared and not truthy.claim_reward() and not truthy.owns_weapon("27304"))
	_meta(false)

	# Failed equipment save keeps the old committed key/bonus and exact candidate.
	var equipment_path: String = first.storage_path
	var old_bytes: String = FileAccess.get_file_as_string(equipment_path)
	var old_state: Dictionary = first.progress.duplicate(true)
	signals_before = _signals(first)
	_block_temporary(equipment_path)
	_check("failed equip leaves committed state bonus and primary unchanged", not first.equip_weapon("27304") and first.capture_state().pending_save and first.progress == old_state and first.weapon_damage_bonus() == 0 and FileAccess.get_file_as_string(equipment_path) == old_bytes and _signals(first) == signals_before)
	var exact_pending: Dictionary = first.get("_pending_bundle").duplicate(true)
	_check("pending equipment transaction contains owned key but no bonus", exact_pending.equipment.equipped_key == "27304" and exact_pending.equipment.owned["27304"] and exact_pending.inventory["3128"] == 1 and exact_pending.coins == 40)
	_check("new operations cannot overwrite failed equip transaction", not first.equip_weapon("practice_lswd0000") and not first.claim_reward() and not first.claim_first_drop() and not first.accept_quest() and not first.load_progress() and first.get("_pending_bundle") == exact_pending and _signals(first) == signals_before)
	attempts = first.capture_state().save_attempts
	_meta(true)
	for _index: int in 6:
		first._process(0.0)
	_check("pending equip is not retried or replaced by frame clear observation", first.get("_pending_bundle") == exact_pending and first.capture_state().save_attempts == attempts)
	_unblock_temporary(equipment_path)
	_check("retry success commits exact equip and emits once", first.retry_pending_save() and first.progress == exact_pending and first.weapon_damage_bonus() == 4 and not first.capture_state().pending_save and _signals(first) == signals_before+1)
	_check("equip retry backup remains exact old committed state", FileAccess.get_file_as_string(equipment_path + ".bak") == old_bytes and not FileAccess.file_exists(equipment_path + ".tmp"))
	_block_temporary(equipment_path)
	signals_before = _signals(first)
	_check("failed unequip preserves old appearance key and bonus4", not first.equip_weapon("practice_lswd0000") and first.equipped_weapon_key() == "27304" and first.weapon_damage_bonus() == 4 and _signals(first) == signals_before)
	_unblock_temporary(equipment_path)
	_check("unequip retry alone applies practice bonus0", first.save_progress() and first.equipped_weapon_key() == "practice_lswd0000" and first.weapon_damage_bonus() == 0 and first.owns_weapon("27304") and _signals(first) == signals_before+1)

	_meta(true)
	var failed_reward: Node = _node(prefix + "/failed_reward.json")
	failed_reward.accept_quest()
	_block_temporary(failed_reward.storage_path)
	signals_before = _signals(failed_reward)
	_check("failed reward rolls back both40 coins and weapon ownership", not failed_reward.claim_reward() and failed_reward.progress.quest_stage == "return" and failed_reward.progress.coins == 0 and not failed_reward.owns_weapon("27304") and _signals(failed_reward) == signals_before)
	var reward_pending: Dictionary = failed_reward.get("_pending_bundle").duplicate(true)
	_check("failed reward candidate includes both grants and unchanged default appearance", reward_pending.coins == 40 and reward_pending.equipment.owned["27304"] and reward_pending.equipment.equipped_key == "practice_lswd0000")
	_meta(false)
	failed_reward._process(0.0)
	_check("reset and equip cannot steal pending reward candidate", not failed_reward.equip_weapon("27304") and failed_reward.get("_pending_bundle") == reward_pending)
	_unblock_temporary(failed_reward.storage_path)
	_check("reward retry grants exactly once after reset", failed_reward.retry_pending_save() and failed_reward.progress.coins == 40 and failed_reward.owns_weapon("27304") and not failed_reward.claim_reward() and _signals(failed_reward) == signals_before+1)

	_meta(false)
	var failed_drop: Node = _node(prefix + "/failed_drop.json")
	failed_drop.accept_quest()
	_block_temporary(failed_drop.storage_path)
	_meta(true)
	failed_drop._process(0.0)
	var clear_pending: Dictionary = failed_drop.get("_pending_bundle").duplicate(true)
	_check("schema3 failed clear retains old active unearned and unowned state", failed_drop.capture_state().pending_save and failed_drop.progress.quest_stage == "active" and failed_drop.progress.first_drop.state == "unearned" and not failed_drop.owns_weapon("27304") and clear_pending.first_drop.position == [603.0,317.0])
	attempts = failed_drop.capture_state().save_attempts
	_meta(false)
	for _index: int in 5:
		failed_drop._process(0.0)
	_check("failed clear is not repeated and cannot be replaced by equipment", failed_drop.capture_state().save_attempts == attempts and not failed_drop.equip_weapon("practice_lswd0000") and failed_drop.get("_pending_bundle") == clear_pending)
	_unblock_temporary(failed_drop.storage_path)
	_check("clear retry after reset preserves historical receipt and drop position", failed_drop.retry_pending_save() and failed_drop.progress.quest_stage == "return" and failed_drop.progress.objective_cleared and failed_drop.progress.first_drop.position == [603.0,317.0] and not failed_drop.owns_weapon("27304"))
	_block_temporary(failed_drop.storage_path)
	_check("schema3 failed pickup leaves pending loot and zero material", not failed_drop.claim_first_drop() and failed_drop.progress.first_drop.state == "pending" and failed_drop.progress.inventory["3128"] == 0 and not failed_drop.owns_weapon("27304"))
	var pickup_pending: Dictionary = failed_drop.get("_pending_bundle").duplicate(true)
	_check("pending pickup cannot be replaced by claim or equip", not failed_drop.claim_reward() and not failed_drop.equip_weapon("practice_lswd0000") and failed_drop.get("_pending_bundle") == pickup_pending)
	_unblock_temporary(failed_drop.storage_path)
	_check("pickup retry commits exactly one material without granting equipment", failed_drop.save_progress() and failed_drop.progress.first_drop.state == "claimed" and failed_drop.progress.inventory["3128"] == 1 and not failed_drop.owns_weapon("27304") and not failed_drop.claim_first_drop())
	_check("later reward and equip preserve recovered material receipt", failed_drop.claim_reward() and failed_drop.equip_weapon("27304") and failed_drop.progress.inventory["3128"] == 1 and failed_drop.progress.first_drop.state == "claimed" and failed_drop.weapon_damage_bonus() == 4)

	# A malformed v3 must never take the migration default path.
	var malformed: Array[Dictionary] = []
	var bad: Dictionary = _v3("completed")
	bad.erase("equipment");malformed.append(bad)
	bad = _v3("completed");bad.equipment = [];malformed.append(bad)
	bad = _v3("completed");bad.equipment.owned = [];malformed.append(bad)
	bad = _v3("completed");bad.equipment.owned["27304"] = "true";malformed.append(bad)
	bad = _v3("completed");bad.equipment.owned["27304"] = 1;malformed.append(bad)
	bad = _v3("completed");bad.equipment.owned = {};malformed.append(bad)
	bad = _v3("completed");bad.equipment.owned["fake"] = true;malformed.append(bad)
	bad = _v3("completed");bad.equipment.equipped_key = "fake";malformed.append(bad)
	bad = _v3("completed");bad.equipment.equipped_key = 27304;malformed.append(bad)
	bad = _v3("completed");bad.equipment.bonus = 4;malformed.append(bad)
	bad = _v3();bad.equipment.equipped_key = "27304";malformed.append(bad)
	bad = _v3();bad.equipment.owned["27304"] = true;malformed.append(bad)
	bad = _v3("completed");bad.equipment.owned["27304"] = false;malformed.append(bad)
	bad = _v3("completed");bad.coins = 80;malformed.append(bad)
	bad = _v3("completed");bad.inventory["3128"] = 2;malformed.append(bad)
	bad = _v3("completed");bad.first_drop.state = "pending";malformed.append(bad)
	bad = _v3("completed");bad.first_drop.position = [1000,317];malformed.append(bad)
	bad = _v3("completed");bad.schema = 3.5;malformed.append(bad)
	bad = _v3("completed");bad.schema = 4;malformed.append(bad)
	bad = _v2("completed",true);bad.first_drop.state = "fake";malformed.append(bad)
	bad = _v1("completed");bad.reward_granted = false;malformed.append(bad)
	for index: int in malformed.size():
		var path: String = prefix + "/invalid_" + str(index) + ".json"
		var text: String = JSON.stringify(malformed[index])
		_write(path,text)
		var rejected: Node = _node(path,true)
		_check("invalid v3 or legacy rejected without repair " + str(index), not rejected.capture_state().storage_ready and FileAccess.get_file_as_string(path) == text and _signals(rejected) == 0 and not rejected.equip_weapon("27304"))

	var recovery_path: String = prefix + "/backup.json"
	var invalid_primary: String = JSON.stringify(malformed[0])
	var legacy_backup: String = JSON.stringify(_v2("completed",true))
	_write(recovery_path,invalid_primary)
	_write(recovery_path + ".bak",legacy_backup)
	var recovery: Node = _node(recovery_path,true)
	_check("invalid v3 primary falls back to strict v2 backup in memory", recovery.capture_state().loaded_from_backup and recovery.owns_weapon("27304") and recovery.equipped_weapon_key() == "practice_lswd0000" and recovery.progress.inventory["3128"] == 1 and FileAccess.get_file_as_string(recovery_path) == invalid_primary)
	_check("backup migration equip writes one complete v3 bundle", recovery.equip_weapon("27304") and recovery.weapon_damage_bonus() == 4 and recovery.progress.coins == 40 and recovery.progress.first_drop.state == "claimed")
	var archived: bool = false
	var directory: DirAccess = DirAccess.open(recovery_path.get_base_dir())
	for name: String in directory.get_files():
		if name.begins_with("backup.json.invalid.") and FileAccess.get_file_as_string(recovery_path.get_base_dir() + "/" + name) == invalid_primary:
			archived = true
	_check("corrupt primary archived exactly and old backup retained", archived and FileAccess.get_file_as_string(recovery_path + ".bak") == legacy_backup)
	var roundtrip: Node = _node(recovery_path,true)
	_check("new primary reload keeps equipment material quest and bonus", _json_equal(roundtrip.progress,recovery.progress) and roundtrip.weapon_damage_bonus() == 4 and not roundtrip.claim_reward() and not roundtrip.claim_first_drop())
	for version: int in [1,3]:
		var fallback_path: String = prefix + "/backup_v" + str(version) + ".json"
		var fallback_text: String = JSON.stringify(_v1("completed") if version == 1 else _v3("completed",true))
		_write(fallback_path,"broken-primary")
		_write(fallback_path + ".bak",fallback_text)
		var fallback: Node = _node(fallback_path,true)
		_check("strict v" + str(version) + " backup restores correct appearance policy", fallback.capture_state().loaded_from_backup and fallback.owns_weapon("27304") and fallback.equipped_weapon_key() == ("practice_lswd0000" if version == 1 else "27304") and fallback.weapon_damage_bonus() == (0 if version == 1 else 4))
		_check("v" + str(version) + " backup bytes survive successful recovery save", fallback.save_progress() and FileAccess.get_file_as_string(fallback_path + ".bak") == fallback_text)
	var both_path: String = prefix + "/both_invalid.json"
	_write(both_path,"invalid-primary")
	_write(both_path + ".bak","invalid-backup")
	var both: Node = _node(both_path,true)
	_check("both invalid copies block writes and signal while preserving files", not both.capture_state().storage_ready and not both.accept_quest() and _signals(both) == 0 and FileAccess.get_file_as_string(both_path) == "invalid-primary" and FileAccess.get_file_as_string(both_path + ".bak") == "invalid-backup")
	for value: Variant in ["4",72,-4,4.5,INF,[],{}]:
		roundtrip.equipment_data.items["27304"].prototype_damage_bonus = value
		_check("catalog rejects non-whitelist bonus " + str(value), roundtrip.weapon_damage_bonus() == 0)
	roundtrip.equipment_data.items["27304"].prototype_damage_bonus = 4.0
	_check("catalog numeric4 accepted without reading source attack72", roundtrip.weapon_damage_bonus() == 4)
	var rejected_path: String = roundtrip.storage_path
	_check("non-QA configuration remains forbidden", not roundtrip.configure_storage("user://old_client_save.json",false) and roundtrip.storage_path == rejected_path)
	var failures: Array[Dictionary] = []
	for item: Dictionary in checks:
		if not item.passed:
			failures.append(item)
	var report: Dictionary = {"schema":1,"created_at":Time.get_datetime_string_from_system(true),
		"godot":Engine.get_version_info().string,"test_script":"res://tools/r3/equipment_storage_checks.gd",
		"controller_sha256":FileAccess.get_sha256("res://scripts/adventure_progress.gd"),
		"quest_data_sha256":FileAccess.get_sha256("res://data/first_route_quest.json"),
		"equipment_data_sha256":FileAccess.get_sha256("res://data/first_equipment.json"),
		"test_script_sha256":FileAccess.get_sha256("res://tools/r3/equipment_storage_checks.gd"),
		"isolated_storage_prefix":prefix,"default_storage_initialized_or_written":false,
		"scope":"Isolated headless SceneTree, no main scene/autoload/visual/runtime input. Induced temporary-directory write failures are expected fixtures.",
		"checks":checks,"count":checks.size(),"failed":failures,"all_passed":failures.is_empty()}
	var output: FileAccess = FileAccess.open("res://docs/r3_05_storage_checks.json",FileAccess.WRITE)
	assert(output != null)
	output.store_string(JSON.stringify(report,"\t") + "\n")
	output.close()
	print(JSON.stringify({"count":checks.size(),"failed":failures.size(),"all_passed":failures.is_empty(),"report":"docs/r3_05_storage_checks.json"}))
	for controller: Node in controllers:
		controller.free()
	quit(0 if failures.is_empty() else 1)
