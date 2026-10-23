extends "res://scripts/source_actor_3d.gd"
## Source-pixel actor whose AI and adapted combat timers belong to FirstEncounter.

var encounter: Node
var held_pose: bool = false


func _physics_process(_delta: float) -> void:
	# The encounter moves this body once per physics tick, independently of input.
	pass


func _process(delta: float) -> void:
	if is_instance_valid(encounter):
		paused = encounter.is_combat_blocked() or encounter.player_hp <= 0
	if held_pose:
		elapsed_ms = 0.0
		_update_sprite_transform()
	else:
		super._process(delta)


func hold_pose(action: String, frame: int = 0) -> void:
	held_pose = true
	_one_shot = false
	velocity = Vector3.ZERO
	if animation_name != action:
		play(action, true)
	frame_index = clampi(frame, 0, _animations[action]["frames"].size() - 1)
	elapsed_ms = 0.0
	_apply_frame()
	_update_sprite_transform()


func release_pose() -> void:
	held_pose = false
	_one_shot = false
	play("stay", true)
	_update_sprite_transform()


func walk_toward(point: Vector2, speed: float) -> void:
	held_pose = false
	var difference: Vector2 = point - world_to_source(position)
	var direction := Vector2(difference.x, difference.y / 0.58).normalized()
	_move_ground(direction, speed)
	play("move")
	_update_sprite_transform()


func action_elapsed_ms() -> float:
	var clock: float = elapsed_ms
	for i: int in frame_index:
		clock += float(_animations[animation_name]["frames"][i]["duration_ms"])
	return clock
