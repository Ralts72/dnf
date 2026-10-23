extends Node
## Finite prototype lift on the existing SourceJump height/shadow path.
## Navigation, source animation records, damage and landing recovery stay external.

signal landed

const RULES_PATH: String = "res://data/upper_slash_rules.json"

var encounter: Node
var main: Node
var enemy: Node
var active: bool = false
var age: float = 0.0 # Seconds, advanced only by this helper's physics callback.
var duration_seconds: float = 0.0 # Populated from the shared combat rules by setup().
var peak_height_px: float = 0.0
var start_count: int = 0
var land_count: int = 0
var clear_count: int = 0
var reject_count: int = 0
var maximum_height_seen: float = 0.0
var last_clear_reason: String = ""
var last_reject_reason: String = ""
var last_end_reason: String = ""
var last_end: Dictionary = {}
var launch_source_foot: Vector2 = Vector2.ZERO
var _clock_ready: bool = false


func setup(controller: Node) -> void:
	if encounter == controller and is_instance_valid(enemy) and _clock_ready:
		return
	if active:
		clear("reattach")
	encounter = controller
	main = controller.get("main") if is_instance_valid(controller) else null
	enemy = controller.get("enemy") if is_instance_valid(controller) else null
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -800 # After encounter -900 and gems -850; same-tick terminal cleanup.
	_clock_ready = false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	if not parsed is Dictionary or not parsed.get("combat") is Dictionary:
		last_reject_reason = "invalid_rules"
		return
	var duration: Variant = parsed.combat.get("launch_duration_seconds")
	var height: Variant = parsed.combat.get("launch_height_px")
	if typeof(duration) not in [TYPE_INT, TYPE_FLOAT] or typeof(height) not in [TYPE_INT, TYPE_FLOAT]:
		last_reject_reason = "invalid_rules"
		return
	if not is_finite(float(duration)) or not is_finite(float(height)) or float(duration) <= 0.0 or float(height) <= 0.0:
		last_reject_reason = "invalid_rules"
		return
	duration_seconds = float(duration)
	peak_height_px = float(height)
	_clock_ready = true
	last_reject_reason = ""


func _terminal_reason() -> String:
	if not is_inside_tree() or not is_instance_valid(encounter) or not is_instance_valid(main) or not is_instance_valid(enemy):
		return "scene_exit"
	if not main.is_inside_tree() or not enemy.is_inside_tree() or get_tree().current_scene != main:
		return "scene_exit"
	if bool(encounter.cleared) or int(encounter.enemy_hp) <= 0:
		return "enemy_defeated"
	if int(encounter.player_hp) <= 0:
		return "player_ko"
	return ""


func _freeze_reason() -> String:
	var terminal: String = _terminal_reason()
	if not terminal.is_empty():
		return terminal
	if get_tree().paused:
		return "paused"
	# The common gate includes player pause/menu/modal/preview/inspection/fade,
	# but excludes the encounter's own hurt lock. Caster AI QA freeze is unrelated.
	return "combat_blocked" if encounter.is_combat_blocked() else ""


func _visual_available() -> bool:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return false
	var sprite: Node = enemy.get_node_or_null("Sprite")
	return sprite != null and sprite.is_inside_tree()


func _configure_jump() -> void:
	# v0*t - g*t*t/2 is exactly 4*h*(t/T)*(1-t/T). SourceJump also
	# computes its height_ratio from this same peak, so existing shadows work.
	var mapping: Dictionary = {
		"takeoff_frame": 0, "landing_frame": 0,
		"rising_frames": [0, 0], "falling_frames": [0, 0],
		"takeoff_speed_px_s": 4.0 * peak_height_px / duration_seconds,
		"gravity_px_s2": 8.0 * peak_height_px / (duration_seconds * duration_seconds),
		"air_move_speed_px_s": 0.0, "run_jump_multiplier": 1.0,
	}
	# This zero-duration timing scaffold only removes takeoff/landing delays.
	# It is not an ANI record or actor pose; the original damage2 frame is held.
	enemy.jump_motion.configure({"mapping": mapping}, [{"duration_ms": 0.0}], [])


func launch() -> bool:
	last_reject_reason = ""
	if active:
		last_reject_reason = "already_active"
	elif not _clock_ready or not is_instance_valid(enemy):
		last_reject_reason = "unavailable"
	else:
		last_reject_reason = _freeze_reason()
		if last_reject_reason.is_empty() and encounter.has_method("_enemy_launchable") and not bool(encounter.call("_enemy_launchable")):
			last_reject_reason = "not_launchable"
		if last_reject_reason.is_empty() and (not enemy._animations.has("damage2") or enemy._animations.damage2.frames.is_empty()):
			last_reject_reason = "missing_pose"
		if last_reject_reason.is_empty() and enemy.jump_motion.is_active():
			last_reject_reason = "already_airborne"
	if not last_reject_reason.is_empty():
		reject_count += 1
		return false
	_configure_jump()
	if not enemy.jump_motion.begin(false):
		last_reject_reason = "jump_clock_rejected"
		reject_count += 1
		return false
	active = true
	age = 0.0
	maximum_height_seen = 0.0
	launch_source_foot = enemy.world_to_source(enemy.position)
	start_count += 1
	if _visual_available():
		enemy.hold_pose("damage2", 0)
	return true


func _physics_process(delta: float) -> void:
	if not active:
		return
	var terminal: String = _terminal_reason()
	if not terminal.is_empty():
		clear(terminal)
		return
	if not _freeze_reason().is_empty():
		return
	var step: float = minf(maxf(delta, 0.0), maxf(0.0, duration_seconds - age))
	age = minf(duration_seconds, age + step)
	enemy.jump_motion.advance(step)
	maximum_height_seen = maxf(maximum_height_seen, float(enemy.jump_motion.height_pixels))
	if age + .000000001 >= duration_seconds or not enemy.jump_motion.is_active():
		_finish_landing()
		return
	if _visual_available():
		enemy.hold_pose("damage2", 0)


func _finish_landing() -> void:
	active = false
	age = duration_seconds
	enemy.jump_motion.reset()
	if _visual_available():
		enemy.hold_pose("damage2", 0)
	land_count += 1
	last_end_reason = "landed"
	last_end = {"reason": "landed", "age_seconds": age,
		"maximum_height_px": maximum_height_seen, "source_foot": _source_foot()}
	# No recovery timer or release_pose here: the encounter owns its .12s recovery.
	# State is complete before the callback, which may immediately change the pose.
	landed.emit()


func _source_foot() -> Vector2:
	return enemy.world_to_source(enemy.position) if is_instance_valid(enemy) else Vector2.ZERO


func clear(reason: String = "reset") -> void:
	last_end = {"reason": reason, "was_active": active, "age_seconds": age,
		"height_px": float(enemy.jump_motion.height_pixels) if is_instance_valid(enemy) else 0.0,
		"maximum_height_px": maximum_height_seen, "source_foot": _source_foot()}
	active = false
	age = 0.0
	last_clear_reason = reason
	last_end_reason = reason
	clear_count += 1
	if is_instance_valid(enemy):
		enemy.jump_motion.reset()
		# Do not release or replace an existing down/reset pose, especially during
		# scene teardown. Detached actors must never sample global transforms.
		if _visual_available():
			enemy._update_sprite_transform()


func capture_state() -> Dictionary:
	var height: float = float(enemy.jump_motion.height_pixels) if is_instance_valid(enemy) else 0.0
	var ratio: float = float(enemy.jump_motion.height_ratio()) if is_instance_valid(enemy) else 0.0
	var frozen: String = _freeze_reason()
	return {"active": active, "age_seconds": age, "duration_seconds": duration_seconds,
		"peak_height_px": peak_height_px, "height_px": height, "height_ratio": ratio,
		"vertical_speed_px_s": float(enemy.jump_motion.vertical_speed) if is_instance_valid(enemy) else 0.0,
		"jump_phase": str(enemy.jump_motion.phase) if is_instance_valid(enemy) else "grounded",
		"source_foot": _source_foot(), "launch_source_foot": launch_source_foot,
		"enemy_world_position": enemy.position if is_instance_valid(enemy) else Vector3.ZERO,
		"start_count": start_count, "land_count": land_count, "clear_count": clear_count,
		"reject_count": reject_count, "maximum_height_seen_px": maximum_height_seen,
		"last_clear_reason": last_clear_reason, "last_reject_reason": last_reject_reason,
		"last_end_reason": last_end_reason, "last_end": last_end.duplicate(true),
		"ready": _clock_ready, "frozen": not frozen.is_empty(), "freeze_reason": frozen}


func _exit_tree() -> void:
	clear("scene_exit")
