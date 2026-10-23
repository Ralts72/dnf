extends RefCounted
## Prototype only: fixed-angle, fixed-scale vertical framing in existing overscan.

const SOURCE_BOTTOM: float=45.0
const MARGIN: float=8.0
const FOLLOW_RATE: float=20.0
const MAX_OFFSET: float=40.0
var main: Node
var camera: Camera3D
var far: Sprite2D
var base_camera: Vector3
var base_far: Vector2
var enabled: bool=true
var offset_y: float=0.0

func setup(root: Node) -> void:
	main=root;camera=root.world.get_node("Camera");far=root.get_node("PortClip/Far")
	base_camera=camera.position;base_far=far.position
	advance(0,true)

func target() -> float:
	var p: Node=main.player
	var position: Vector3=p.position
	if not p.paused and p.is_physics_interpolated_and_enabled():position=p.get_global_transform_interpolated().origin
	var point: Vector2=p.world_to_source(position)
	return clampf(point.y+43.0+SOURCE_BOTTOM+MARGIN-404.0,0,MAX_OFFSET) if enabled else 0.0

func advance(delta: float,snap: bool=false) -> void:
	var desired: float=target()
	if snap or main.player.paused:offset_y=desired
	else:offset_y=lerpf(offset_y,desired,1.0-exp(-FOLLOW_RATE*delta))
	camera.position=base_camera-camera.basis.y*(offset_y/60.0)
	far.position=base_far-Vector2(0,offset_y)

func restore() -> void:
	camera.position=base_camera;far.position=base_far
