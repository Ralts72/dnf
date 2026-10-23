extends RefCounted
## Native render interpolation, independent of source-image animation timing.

var actor: Node
var enabled: bool=true


func setup(source_actor: Node) -> void:
	actor=source_actor
	enabled=actor.get_tree().get_meta("port_motion_smoothing",true)
	apply()
	reset()


func set_enabled(value: bool) -> void:
	enabled=value
	actor.get_tree().set_meta("port_motion_smoothing",value)
	apply()


func apply() -> void:
	var mode: int=Node.PHYSICS_INTERPOLATION_MODE_ON if enabled and not actor.paused else Node.PHYSICS_INTERPOLATION_MODE_OFF
	if actor.physics_interpolation_mode!=mode:
		actor.physics_interpolation_mode=mode
		reset()


func reset() -> void:
	actor.reset_physics_interpolation()
