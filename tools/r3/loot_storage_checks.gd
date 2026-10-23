extends SceneTree
## Schema2 migration/loot transactions use only isolated user://qa paths.
const Progress = preload("res://scripts/adventure_progress.gd")
var prefix: String
var checks: Array[Dictionary] = []
var controllers: Array[Node] = []


func _initialize() -> void:
	call_deferred("_run")


func _node(path: String, existing: bool = false) -> Node:
	var controller: Node = Progress.new()
	root.add_child(controller)
	controller.set_process(false)
	controller.set_physics_process(false)
	controller.configure_storage(path, existing)
	controllers.append(controller)
	return controller


func _meta(cleared: bool, position: Vector2 = Vector2(640, 300)) -> void:
	set_meta("first_encounter_state", {"cleared": cleared, "enemy_position": position})


func _check(name: String, success: bool, detail: Variant = null) -> void:
	checks.append({"name": name, "passed": success, "detail": detail})
	print(("PASS " if success else "FAIL ") + name)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(text)
	file.close()


func _block(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".before_block"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _run() -> void:
	prefix = "user://qa/first_route_loot_" + str(Time.get_unix_time_from_system()).replace(".", "_") + "_" + str(Time.get_ticks_usec())
	var human_before: bool = FileAccess.file_exists(Progress.DEFAULT_STORAGE)
	var human_sha_before: String = FileAccess.get_sha256(Progress.DEFAULT_STORAGE) if human_before else ""
	_meta(false)
	var path: String = prefix + "/available_kill.json"
	var first: Node = _node(path)
	_check("default schema2 inventory and ledger", first.progress.schema == 2 and first.progress.inventory == {"3128": 0} and first.progress.first_drop.state == "unearned")
	_meta(true, Vector2(602, 315))
	first._process(0.0)
	_check("kill before quest records pending loot", first.progress.quest_stage == "available" and not first.progress.objective_cleared and first.progress.first_drop.state == "pending" and first.progress.inventory["3128"] == 0)
	_check("first death position persists", first.progress.first_drop.position == [602.0, 315.0] and JSON.parse_string(FileAccess.get_file_as_string(path)).first_drop.position == [602.0, 315.0])
	var attempts: int = first.capture_state().save_attempts
	_meta(false)
	for index: int in 5:
		first._process(0.0)
	_check("practice reset leaves pending receipt unchanged", first.progress.first_drop.state == "pending" and first.progress.first_drop.position == [602.0, 315.0] and first.capture_state().save_attempts == attempts)
	_check("accept uses recorded kill after practice reset", first.accept_quest() and first.progress.quest_stage == "return" and first.progress.objective_cleared)
	_check("pickup atomically claims ledger and inventory1", first.claim_first_drop() and first.progress.inventory["3128"] == 1 and first.progress.first_drop.state == "claimed")
	_check("pickup cannot repeat", not first.claim_first_drop() and first.progress.inventory["3128"] == 1)
	_meta(true, Vector2(700, 320))
	first._process(0.0)
	_check("second practice victory cannot mint another item", first.progress.inventory["3128"] == 1 and first.progress.first_drop.position == [602.0, 315.0])
	_check("quest reward coexists with claimed item", first.claim_reward() and first.progress.coins == 40 and first.progress.inventory["3128"] == 1)
	remove_meta("first_encounter_state")
	var reload: Node = _node(path, true)
	_check("reload claimed item and completed quest", reload.progress.quest_stage == "completed" and reload.progress.coins == 40 and reload.progress.inventory["3128"] == 1 and reload.progress.first_drop.state == "claimed")
	_check("earned drop load seeds absent cleared session", get_meta("first_encounter_state", {}).get("cleared", false) == true)
	_check("reload cannot repeat item or coins", not reload.claim_first_drop() and not reload.claim_reward())

	_meta(false)
	var active: Node = _node(prefix + "/active_kill.json")
	_check("active setup accepts quest", active.accept_quest())
	_meta(true, Vector2(650, 322))
	active._process(0.0)
	_check("active clear saves quest receipt and loot in one bundle", active.progress.quest_stage == "return" and active.progress.objective_cleared and active.progress.first_drop.state == "pending" and active.progress.first_drop.position == [650.0, 322.0])
	_meta(false)
	var before_accept: Node = _node(prefix + "/pickup_before_accept.json")
	_meta(true)
	before_accept._process(0.0)
	_meta(false)
	_check("item may be picked before quest acceptance", before_accept.claim_first_drop() and before_accept.progress.quest_stage == "available" and before_accept.progress.inventory["3128"] == 1)
	_check("claimed item history can later satisfy quest", before_accept.accept_quest() and before_accept.progress.quest_stage == "return" and before_accept.claim_reward())

	var stages: Array[String] = ["available", "active", "return", "completed"]
	for stage: String in stages:
		_meta(false)
		var v1: Dictionary = {"schema": 1, "quest_stage": stage, "objective_cleared": stage in ["return", "completed"], "reward_granted": stage == "completed", "coins": 40 if stage == "completed" else 0}
		var v1_path: String = prefix + "/migrate_" + stage + ".json"
		var original: String = JSON.stringify(v1) + "\n"
		_write(v1_path, original)
		var migrated: Node = _node(v1_path, true)
		var expected: String = "pending" if v1.objective_cleared else "unearned"
		_check("v1 migrates in memory " + stage, migrated.progress.schema == 2 and migrated.progress.quest_stage == stage and migrated.progress.first_drop.state == expected and migrated.progress.inventory["3128"] == 0)
		_check("v1 load does not rewrite " + stage, FileAccess.get_file_as_string(v1_path) == original and not FileAccess.file_exists(v1_path + ".bak"))
		_check("first mutation retains exact v1 backup " + stage, migrated.save_progress() and JSON.parse_string(FileAccess.get_file_as_string(v1_path)).schema == 2 and FileAccess.get_file_as_string(v1_path + ".bak") == original)

	_meta(false)
	var base: Dictionary = first._default_progress()
	var malformed: Array[Dictionary] = []
	var candidate: Dictionary = base.duplicate(true)
	candidate.inventory = {"3128": 0, "9999": 1}
	malformed.append(candidate)
	for count: Variant in [-1, 2, 1.5, "1", true]:
		candidate = base.duplicate(true)
		candidate.inventory["3128"] = count
		malformed.append(candidate)
	for state: String in ["pending", "claimed"]:
		candidate = base.duplicate(true)
		candidate.first_drop.state = state
		candidate.inventory["3128"] = 1 if state == "pending" else 0
		malformed.append(candidate)
	for field: String in ["id", "region"]:
		candidate = base.duplicate(true)
		candidate.first_drop[field] = "wrong"
		malformed.append(candidate)
	for point: Array in [[119, 300], [777, 300], [640, 244], [640, 346], ["640", 300], [640], [INF, 300], [NAN, 300]]:
		candidate = base.duplicate(true)
		candidate.first_drop.position = point
		malformed.append(candidate)
	candidate = base.duplicate(true)
	candidate.quest_stage = "active"
	candidate.first_drop.state = "pending"
	malformed.append(candidate)
	candidate = base.duplicate(true)
	candidate.quest_stage = "return"
	candidate.objective_cleared = true
	malformed.append(candidate)
	for index: int in malformed.size():
		_check("schema2 rejects invalid ledger" + str(index), not first._valid(malformed[index]))
	var invalid_path: String = prefix + "/invalid_v2.json"
	var invalid_text: String = JSON.stringify(malformed[0])
	_write(invalid_path, invalid_text)
	var invalid: Node = _node(invalid_path, true)
	_check("invalid v2 is preserved and write-blocked", not invalid.capture_state().storage_ready and not invalid.save_progress() and FileAccess.get_file_as_string(invalid_path) == invalid_text)

	_meta(false)
	var failed_path: String = prefix + "/failed_clear.json"
	var failed: Node = _node(failed_path)
	_check("failed clear setup", failed.accept_quest())
	_block(failed_path)
	_meta(true, Vector2(670, 332))
	failed._process(0.0)
	var exact_pending: Dictionary = failed.get("_pending_bundle").duplicate(true)
	var failed_attempts: int = failed.capture_state().save_attempts
	_check("failed kill transaction stays in memory only", failed.capture_state().pending_save and failed.progress.quest_stage == "active" and failed.progress.first_drop.state == "unearned" and exact_pending.first_drop.position == [670.0, 332.0])
	_meta(false)
	for index: int in 8:
		failed._process(0.0)
	_check("failed kill write does not loop", failed.capture_state().save_attempts == failed_attempts)
	_check("new quest and pickup cannot replace pending transaction", not failed.accept_quest() and not failed.claim_reward() and not failed.claim_first_drop() and failed.get("_pending_bundle") == exact_pending)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(failed_path))
	_check("retry after R preserves original kill location and quest receipt", failed.retry_pending_save() and failed.progress.quest_stage == "return" and failed.progress.objective_cleared and failed.progress.first_drop.position == [670.0, 332.0] and not failed.capture_state().pending_save)
	_block(failed_path)
	_check("failed pickup keeps visible pending item and zero inventory", not failed.claim_first_drop() and failed.capture_state().pending_save and failed.progress.inventory["3128"] == 0 and failed.progress.first_drop.state == "pending")
	var pickup_pending: Dictionary = failed.get("_pending_bundle").duplicate(true)
	_check("repeated pickup cannot overlay failed pickup transaction", not failed.claim_first_drop() and failed.get("_pending_bundle") == pickup_pending)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(failed_path))
	_check("save_progress prioritizes exact pending pickup", failed.save_progress() and failed.progress.inventory["3128"] == 1 and failed.progress.first_drop.state == "claimed")
	var failed_reload: Node = _node(failed_path, true)
	_check("failed pickup recovery reloads exactly one item", failed_reload.progress.inventory["3128"] == 1 and not failed_reload.claim_first_drop())

	var recovery_path: String = prefix + "/backup_v1.json"
	var old_v1: String = JSON.stringify({"schema": 1, "quest_stage": "return", "objective_cleared": true, "reward_granted": false, "coins": 0})
	_write(recovery_path, "broken-primary")
	_write(recovery_path + ".bak", old_v1)
	var recovery: Node = _node(recovery_path, true)
	_check("valid v1 backup recovers migrated pending item", recovery.capture_state().loaded_from_backup and recovery.progress.schema == 2 and recovery.progress.first_drop.state == "pending")
	_check("backup recovery pickup commits one item", recovery.claim_first_drop() and recovery.progress.inventory["3128"] == 1)
	var archived: bool = false
	var directory: DirAccess = DirAccess.open(recovery_path.get_base_dir())
	for file_name: String in directory.get_files():
		if file_name.begins_with("backup_v1.json.invalid.") and FileAccess.get_file_as_string(recovery_path.get_base_dir() + "/" + file_name) == "broken-primary":
			archived = true
	_check("corrupt source remains exact archive and v1 backup retained", archived and FileAccess.get_file_as_string(recovery_path + ".bak") == old_v1)
	var human_after: bool = FileAccess.file_exists(Progress.DEFAULT_STORAGE)
	var human_sha_after: String = FileAccess.get_sha256(Progress.DEFAULT_STORAGE) if human_after else ""
	_check("human primary presence and bytes unchanged", human_before == human_after and human_sha_before == human_sha_after)
	var failed_checks: Array[Dictionary] = []
	for item: Dictionary in checks:
		if not item.passed:
			failed_checks.append(item)
	var report: Dictionary = {"schema": 1, "created_at": Time.get_datetime_string_from_system(true),
		"godot": Engine.get_version_info().string, "controller_sha256": FileAccess.get_sha256("res://scripts/adventure_progress.gd"),
		"quest_data_sha256": FileAccess.get_sha256("res://data/first_route_quest.json"),
		"test_script_sha256": FileAccess.get_sha256("res://tools/r3/loot_storage_checks.gd"),
		"isolated_storage_prefix": prefix, "human_primary_exists_before": human_before, "human_primary_exists_after": human_after,
		"human_primary_sha256_before": human_sha_before, "human_primary_sha256_after": human_sha_after,
		"checks": checks, "count": checks.size(), "failed": failed_checks, "all_passed": failed_checks.is_empty()}
	var output: FileAccess = FileAccess.open("res://docs/r3_03_storage_checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print(JSON.stringify({"count": checks.size(), "failed": failed_checks.size(), "all_passed": failed_checks.is_empty(), "report": "docs/r3_03_storage_checks.json", "qa_prefix": prefix}))
	for controller: Node in controllers:
		controller.queue_free()
	quit(0 if failed_checks.is_empty() else 1)
