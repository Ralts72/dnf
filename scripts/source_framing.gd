extends RefCounted
## Keep source poses in view without changing actor scale or navigation.

const SOURCE_BOTTOM: float = 45.0
const MARGIN: float = 8.0
const MAX_OFFSET: float = 40.0
const FOLLOW_RATE: float = 20.0
const HORIZONTAL_POSE_RADIUS: float = 176.0
const MAX_HORIZONTAL_OFFSET: float = 152.0
const MAX_HORIZONTAL_SPEED: float = 190.0

var main: Node
var camera: Camera3D
var far: Sprite2D
var base_camera: Vector3
var base_far: Vector2
var offset_y: float = 0.0
var offset_x: float = 0.0
var enabled: bool = true
var is_3d: bool
var settle_frames: int = 2
var horizontal_pan_min: float = -MAX_HORIZONTAL_OFFSET
var horizontal_pan_max: float = MAX_HORIZONTAL_OFFSET


func configure_horizontal_pan(minimum: float, maximum: float) -> bool:
	if not is_finite(minimum) or not is_finite(maximum) or minimum > 0.0 or maximum < 0.0:
		return false
	horizontal_pan_min = minimum
	horizontal_pan_max = maximum
	offset_x = clampf(offset_x, horizontal_pan_min, horizontal_pan_max)
	settle_frames = 2
	return true


func setup(root: Node) -> void:
	main = root
	is_3d = main.name == "WestCoastR1"
	if is_3d:
		camera = main.world.get_node("Camera")
		# This camera already follows the native interpolated actor at render rate.
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		camera.reset_physics_interpolation()
		far = main.get_node("PortClip/Far")
		base_camera = camera.position
		base_far = far.position
	else:
		far = main.player.get_parent().get_parent().get_node("Background/Far0")
		base_far = far.position
	if main.get_tree().has_meta("port_framing_offset"):
		offset_y = clampf(main.get_tree().get_meta("port_framing_offset"), 0.0, MAX_OFFSET)
	else:
		offset_y = target()
	offset_x = clampf(main.get_tree().get_meta("port_framing_offset_x", target_x()), horizontal_pan_min, horizontal_pan_max)
	apply()


func ground_point(use_render_position: bool = true) -> Vector2:
	var p: Node = main.player
	var point: Vector2
	if is_3d:
		var position: Vector3 = p.position
		if use_render_position and not p.paused and p.is_physics_interpolated_and_enabled():
			position = p.get_global_transform_interpolated().origin
		point = p.world_to_source(position)
	else:
		point = p.position
	return point


func target(use_render_position: bool = true) -> float:
	var point: Vector2 = ground_point(use_render_position)
	return clampf(point.y + 43.0 + SOURCE_BOTTOM + MARGIN - 404.0, 0.0, MAX_OFFSET) if enabled else 0.0


func target_x(use_render_position: bool = true) -> float:
	if not enabled:
		return 0.0
	var x: float = ground_point(use_render_position).x
	var inset: float = HORIZONTAL_POSE_RADIUS + MARGIN
	return clampf(x - clampf(x, inset, 896.0 - inset), horizontal_pan_min, horizontal_pan_max)


func advance(delta: float, snap: bool = false) -> void:
	var desired: float = target(not snap)
	var desired_x: float = target_x(not snap)
	if snap or main.player.paused:
		offset_y = desired
		offset_x = desired_x
		settle_frames = 2
	elif settle_frames > 0:
		# Scene changes and teleports can retain a render-pump sample briefly.
		# Hold the transferred framing while those histories settle.
		settle_frames -= 1
	else:
		offset_y = lerpf(offset_y, desired, 1.0 - exp(-FOLLOW_RATE * delta))
		var eased_x: float = lerpf(offset_x, desired_x, 1.0 - exp(-FOLLOW_RATE * delta))
		offset_x = move_toward(offset_x, eased_x, MAX_HORIZONTAL_SPEED * delta)
		if enabled:
			# Keep the complete supported swing inside the border while following;
			# easing alone can lag behind a character running toward the edge.
			var x: float = ground_point().x
			var inset: float = HORIZONTAL_POSE_RADIUS + MARGIN
			offset_x = clampf(offset_x, x - (896.0 - inset), x - inset)
	apply()


func apply() -> void:
	if is_3d:
		camera.position = base_camera + camera.basis.x * (offset_x / 60.0) - camera.basis.y * (offset_y / 60.0)
		far.position = base_far - Vector2(0.0, offset_y)
	else:
		# Change the viewport's canvas, never an interpolated actor's ancestor.
		main.render_viewport.canvas_transform = Transform2D(0.0, Vector2(-offset_x, -offset_y))
		# Treat distant scenery as the same fixed horizontal backdrop in R0/R1.
		far.position = base_far + Vector2(offset_x, 0.0)


func remember() -> void:
	main.get_tree().set_meta("port_framing_offset", offset_y)
	main.get_tree().set_meta("port_framing_offset_x", offset_x)
