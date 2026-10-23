extends "res://scripts/first_encounter.gd"
## Source statue poses/clocks with explicit prototype wake and magic combat rules.

var phase: String = "dormant"
var awakened: bool = false
var wake_elapsed_ms: float = 0.0
var wake_duration_ms: float = 2400.0
var wake_trigger_count: int = 0
var death_elapsed_ms: float = 0.0
var death_duration_ms: float = 860.0
var _wake_frames: Array = []
var _down_frames: Array = []


static func ensure(scene_root: Node) -> Node:
	if scene_root.scene_file_path != "res://scenes/tower_statue_gallery.tscn":
		return null
	var existing: Node = scene_root.get_node_or_null("StatueEncounter")
	if existing != null:
		return existing
	var controller: Node = (load("res://scripts/statue_encounter.gd") as Script).new()
	controller.name = "StatueEncounter"
	controller.set("main", scene_root)
	scene_root.add_child(controller)
	controller.call("_setup")
	return controller


func _rules_path() -> String:
	return "res://data/statue_encounter_rules.json"


func _session_meta() -> StringName:
	return &"statue_gallery_state"


func _enemy_action() -> String:
	return "attack"


func _setup() -> void:
	# Base setup persists through virtual dispatch; seed this receipt beforehand.
	var saved: Variant = get_tree().get_meta(_session_meta(), {})
	var receipt: Variant = saved.get("awakened", false) if saved is Dictionary else false
	awakened = receipt is bool and receipt == true
	super._setup()
	_wake_frames = enemy._animations.wakeup.frames
	_down_frames = enemy._animations.down.frames
	wake_duration_ms = _total_duration(_wake_frames)
	death_duration_ms = _total_duration(_down_frames)
	phase = "defeated" if cleared else ("awake" if awakened else "dormant")
	if not cleared and not awakened:
		enemy_mode = "dormant"
		enemy.hold_pose("stay", 0)


func _total_duration(frames: Array) -> float:
	var total: float = 0.0
	for frame: Dictionary in frames:
		total += float(frame.duration_ms)
	return total


func _tick_enemy_behavior(delta: float) -> void:
	if awakened:
		super._tick_enemy_behavior(delta)
		return
	if phase == "waking":
		_tick_wake(delta)
		return
	enemy_mode = "dormant"
	enemy.hold_pose("stay", 0)
	var difference: Vector2 = main.player.world_to_source(main.player.position) - enemy.world_to_source(enemy.position)
	if absf(difference.x) <= float(rules.wake.trigger_range_px) and absf(difference.y) <= float(rules.wake.trigger_depth_px):
		phase = "waking"
		enemy_mode = "waking"
		wake_elapsed_ms = 0.0
		wake_trigger_count += 1
		_hold_source_frame("wakeup", _wake_frames, wake_elapsed_ms)


func _tick_wake(delta: float) -> void:
	wake_elapsed_ms = minf(wake_duration_ms, wake_elapsed_ms + delta * 1000.0)
	_hold_source_frame("wakeup", _wake_frames, wake_elapsed_ms)
	if wake_elapsed_ms < wake_duration_ms:
		return
	awakened = true
	phase = "awake"
	enemy_mode = "idle"
	enemy.release_pose()
	_persist()


func _hold_source_frame(action: String, frames: Array, clock_ms: float) -> void:
	var index: int = 0
	var remaining: float = clock_ms
	while index < frames.size() - 1 and remaining >= float(frames[index].duration_ms):
		remaining -= float(frames[index].duration_ms)
		index += 1
	# The encounter's physics clock selects original poses. The render actor
	# cannot advance this timeline a second time while held_pose is true.
	enemy.hold_pose(action, index)


func _tick_hero_attack() -> void:
	if not awakened:
		return
	var was_cleared: bool = cleared
	super._tick_hero_attack()
	if cleared and not was_cleared:
		phase = "defeated"
		death_elapsed_ms = 0.0
		_hold_source_frame("down", _down_frames, 0.0)
		# super has persisted cleared=true (and this subclass's awakened flag).
		var profile: Node = get_tree().root.get_node_or_null("AdventureProgress")
		if profile != null:
			profile.record_chapter_clear("statue_cleared")


func _tick_death(delta: float) -> void:
	if not enemy.visible:
		return
	death_elapsed_ms = minf(death_duration_ms, death_elapsed_ms + delta * 1000.0)
	_enemy_death_remaining = maxf(0.0, (death_duration_ms - death_elapsed_ms) / 1000.0)
	_hold_source_frame("down", _down_frames, death_elapsed_ms)
	if death_elapsed_ms >= death_duration_ms:
		enemy.hide()
		enemy_mode = "defeated"


func reset_encounter() -> bool:
	if not super.reset_encounter():
		return false
	awakened = false
	phase = "dormant"
	wake_elapsed_ms = 0.0
	death_elapsed_ms = 0.0
	enemy_mode = "dormant"
	enemy.hold_pose("stay", 0)
	_persist()
	return true


func _persist() -> void:
	super._persist()
	if not is_inside_tree() or not is_instance_valid(main):
		return
	var state: Dictionary = get_tree().get_meta(_session_meta(), {})
	state["awakened"] = awakened
	get_tree().set_meta(_session_meta(), state)


func _create_contact_audio() -> void:
	# R_SM_GUE is a source two-file RANDOM; no fixed branch is invented here.
	pass


func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(_objective) or cleared or player_hp <= 0:
		return
	if phase == "dormant":
		_objective.text = str(rules.ui.objective_dormant)
	elif phase == "waking":
		_objective.text = str(rules.ui.objective_waking)


func capture_state() -> Dictionary:
	var state: Dictionary = super.capture_state()
	state["session_meta"] = str(_session_meta())
	state["enemy_action"] = _enemy_action()
	state["phase"] = phase
	state["awakened"] = awakened
	state["wake_elapsed_ms"] = wake_elapsed_ms
	state["wake_duration_ms"] = wake_duration_ms
	state["wake_trigger_count"] = wake_trigger_count
	state["death_elapsed_ms"] = death_elapsed_ms
	state["death_duration_ms"] = death_duration_ms
	return state
