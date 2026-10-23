extends SceneTree
## Isolated persistence checks. Never initialize the human adventure profile.

const Progress = preload("res://scripts/adventure_progress.gd")
var checks: Array[Dictionary] = []
var controllers: Array[Node] = []
var prefix: String


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


func _write(path: String, value: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, path)
	file.store_string(value)
	file.close()


func _check(name: String, success: bool, detail: Variant = null) -> void:
	checks.append({"name": name, "passed": success, "detail": detail})
	print(("PASS " if success else "FAIL ") + name)


func _meta(cleared: bool) -> void:
	set_meta("first_encounter_state", {"cleared": cleared})


func _run() -> void:
	var human_exists_before: bool = FileAccess.file_exists(Progress.DEFAULT_STORAGE)
	var human_hash_before: String = FileAccess.get_sha256(Progress.DEFAULT_STORAGE) if human_exists_before else ""
	prefix = "user://qa/first_route_" + str(Time.get_unix_time_from_system()).replace(".", "_") + "_" + str(Time.get_ticks_usec())
	_meta(false)
	var path: String = prefix + "/normal.json"
	var first: Node = _node(path)
	_check("accept persists active bundle", first.accept_quest() and first.progress.quest_stage == "active" and not first.progress.objective_cleared and JSON.parse_string(FileAccess.get_file_as_string(path)).quest_stage == "active")
	_meta(true)
	first._process(0.0)
	_check("observed clear persists return once", first.progress.quest_stage == "return" and first.capture_state().save_attempts == 2)
	_check("real clear receipt saved with return bundle", first.progress.objective_cleared and JSON.parse_string(FileAccess.get_file_as_string(path)).objective_cleared)
	for index: int in 5:
		first._process(0.0)
	_check("return state does not save every frame", first.capture_state().save_attempts == 2)
	_check("claim commits exactly40 coins", first.claim_reward() and first.progress.quest_stage == "completed" and first.progress.reward_granted and first.progress.coins == 40)
	_check("repeated claim rejected", not first.claim_reward() and first.progress.coins == 40)
	remove_meta("first_encounter_state")
	var reloaded: Node = _node(path, true)
	_check("reload completed rejects second reward", reloaded.progress.quest_stage == "completed" and reloaded.progress.coins == 40 and not reloaded.claim_reward())
	_check("completed load seeds absent encounter flag", get_meta("first_encounter_state", {}).get("cleared", false) == true)
	_check("successful atomic save consumes temporary file", not FileAccess.file_exists(path + ".tmp") and FileAccess.file_exists(path + ".bak"))
	_check("backup is a consistent prior bundle", first._read_valid(path + ".bak").quest_stage == "return" and first._read_valid(path + ".bak").coins == 0)

	var corrupt: String = "{broken-primary-preserve-exactly"
	_write(path, corrupt)
	var recovered: Node = _node(path, true)
	_check("corrupt primary recovers valid backup", recovered.capture_state().loaded_from_backup and recovered.progress.quest_stage == "return" and recovered.progress.coins == 0)
	_check("backup recovery preserves corrupt primary before commit", FileAccess.get_file_as_string(path) == corrupt)
	_check("recovered bundle can safely claim40", recovered.claim_reward() and recovered.progress.coins == 40)
	var archived: bool = false
	var directory: DirAccess = DirAccess.open(path.get_base_dir())
	for file_name: String in directory.get_files():
		if file_name.begins_with("normal.json.invalid.") and FileAccess.get_file_as_string(path.get_base_dir() + "/" + file_name) == corrupt:
			archived = true
	_check("commit archives exact corrupt source bytes", archived)
	var recovered_reload: Node = _node(path, true)
	_check("post-recovery reload remains40 once", recovered_reload.progress.coins == 40 and recovered_reload.progress.reward_granted and not recovered_reload.claim_reward())

	var invalid_path: String = prefix + "/both_invalid.json"
	_write(invalid_path, "invalid-primary")
	_write(invalid_path + ".bak", "invalid-backup")
	var invalid: Node = _node(invalid_path, true)
	_check("both invalid disable writes", not invalid.capture_state().storage_ready and not invalid.capture_state().last_error.is_empty() and not invalid.accept_quest())
	_check("both invalid files retained byte-exact", FileAccess.get_file_as_string(invalid_path) == "invalid-primary" and FileAccess.get_file_as_string(invalid_path + ".bak") == "invalid-backup")

	var malformed: Array[Dictionary] = [
		{"schema": [], "quest_stage": "active", "objective_cleared": false, "reward_granted": false, "coins": 0},
		{"schema": 1.5, "quest_stage": "active", "objective_cleared": false, "reward_granted": false, "coins": 0},
		{"schema": 1, "quest_stage": [], "objective_cleared": false, "reward_granted": false, "coins": 0},
		{"schema": 1, "quest_stage": "active", "objective_cleared": false, "reward_granted": "false", "coins": 0},
		{"schema": 1, "quest_stage": "active", "objective_cleared": false, "reward_granted": false, "coins": {}},
		{"schema": 1, "quest_stage": "completed", "objective_cleared": true, "reward_granted": false, "coins": 40},
		{"schema": 1, "quest_stage": "completed", "objective_cleared": true, "reward_granted": true, "coins": 80},
		{"schema": 1, "quest_stage": "active", "reward_granted": false, "coins": 0},
		{"schema": 1, "quest_stage": "active", "objective_cleared": 1, "reward_granted": false, "coins": 0},
		{"schema": 1, "quest_stage": "active", "objective_cleared": true, "reward_granted": false, "coins": 0},
		{"schema": 1, "quest_stage": "return", "objective_cleared": false, "reward_granted": false, "coins": 0},
		{"schema": 1, "quest_stage": "completed", "objective_cleared": false, "reward_granted": true, "coins": 40}
	]
	for index: int in malformed.size():
		var bad_path: String = prefix + "/malformed_" + str(index) + ".json"
		var bad_text: String = JSON.stringify(malformed[index])
		_write(bad_path, bad_text)
		var bad: Node = _node(bad_path, true)
		_check("malformed bundle rejected" + str(index), not bad.capture_state().storage_ready and FileAccess.get_file_as_string(bad_path) == bad_text, malformed[index])
	var large_path: String = prefix + "/oversized.json"
	var large_text: String = "x".repeat(20000)
	_write(large_path, large_text)
	var large: Node = _node(large_path, true)
	_check("oversized file rejected and retained", not large.capture_state().storage_ready and FileAccess.get_file_as_string(large_path) == large_text)

	_meta(false)
	var blocked_path: String = prefix + "/blocked.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked_path))
	var blocked: Node = _node(blocked_path)
	var before: Dictionary = blocked.progress.duplicate(true)
	_check("failed accept write rolls memory back", not blocked.accept_quest() and blocked.progress == before and not blocked.capture_state().last_error.is_empty())
	_check("failed write does not replace blocking directory", DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(blocked_path)))

	var latch_path: String = prefix + "/clear_latch.json"
	var latch: Node = _node(latch_path)
	_check("latch setup accepted", latch.accept_quest())
	DirAccess.rename_absolute(ProjectSettings.globalize_path(latch_path), ProjectSettings.globalize_path(latch_path + ".before_block"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(latch_path))
	_meta(true)
	latch._process(0.0)
	var attempts: int = int(latch.capture_state().save_attempts)
	_check("failed clear save retains active zero-coin bundle", latch.progress.quest_stage == "active" and not latch.progress.objective_cleared and latch.progress.coins == 0 and attempts == 2)
	for index: int in 10:
		latch._process(0.0)
	_check("failed clear save attempts once until explicit retry", int(latch.capture_state().save_attempts) == attempts)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(latch_path))
	_check("manual retry persists return after storage recovers", latch.save_progress() and latch.progress.quest_stage == "return" and int(latch.capture_state().save_attempts) == attempts + 1)
	_meta(false)
	_check("historical real clear receipt survives practice reset", latch.progress.objective_cleared and not latch.capture_state().encounter_cleared and latch.claim_reward() and latch.progress.coins == 40)
	_check("historical receipt cannot reward twice", not latch.claim_reward() and latch.progress.coins == 40)
	var unearned: Node = _node(prefix + "/unearned.json")
	_check("no reward before a real clear observation", unearned.accept_quest() and not unearned.progress.objective_cleared and not unearned.claim_reward() and unearned.progress.coins == 0)
	set_meta("first_encounter_state", {"cleared": 1})
	unearned._process(0.0)
	_check("numeric truthy flag cannot mint receipt or reward", unearned.progress.quest_stage == "active" and not unearned.progress.objective_cleared and not unearned.claim_reward() and unearned.progress.coins == 0)
	_meta(true)
	var early: Node = _node(prefix + "/early_clear.json")
	_check("clear before accepting moves directly to return", early.accept_quest() and early.progress.quest_stage == "return" and early.progress.objective_cleared and early.claim_reward() and early.progress.coins == 40)
	var old_path: String = early.storage_path
	_check("configuration rejects non-QA legacy path", not early.configure_storage("user://old_save.json", false) and early.storage_path == old_path)
	var human_exists_after: bool = FileAccess.file_exists(Progress.DEFAULT_STORAGE)
	var human_hash_after: String = FileAccess.get_sha256(Progress.DEFAULT_STORAGE) if human_exists_after else ""
	_check("human primary presence and bytes unchanged", human_exists_before == human_exists_after and human_hash_before == human_hash_after)

	var failed: Array[Dictionary] = []
	for item: Dictionary in checks:
		if not item.passed:
			failed.append(item)
	var report: Dictionary = {"schema": 1, "created_at": Time.get_datetime_string_from_system(true),
		"godot": Engine.get_version_info().string, "test_script": "res://tools/r3/progress_storage_checks.gd",
		"controller_sha256": FileAccess.get_sha256("res://scripts/adventure_progress.gd"),
		"quest_data_sha256": FileAccess.get_sha256("res://data/first_route_quest.json"),
		"isolated_storage_prefix": prefix, "human_primary_initialized_or_written": false,
		"human_primary_exists_before": human_exists_before, "human_primary_exists_after": human_exists_after,
		"human_primary_sha256_before": human_hash_before, "human_primary_sha256_after": human_hash_after,
		"checks": checks, "count": checks.size(), "failed": failed, "all_passed": failed.is_empty()}
	var output: FileAccess = FileAccess.open("res://docs/r3_02_storage_checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print(JSON.stringify({"count": checks.size(), "failed": failed.size(), "all_passed": failed.is_empty(), "report": "docs/r3_02_storage_checks.json", "qa_prefix": prefix}))
	for controller: Node in controllers:
		controller.queue_free()
	quit(0 if failed.is_empty() else 1)
