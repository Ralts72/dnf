extends Node3D

const SourceActor = preload("res://scripts/source_actor_3d.gd")
@export var frames: Array[Dictionary] = []
@export var image_size: Vector2
@export var source_anchor: Vector2
@export var view_depth_offset: float=0.0:
	set(value):
		view_depth_offset=value
		if is_node_ready():
			_place_at_source()
var paused: bool = false
var frame_index: int = 0
var elapsed_ms: float = 0.0


func _ready() -> void:
	_place_at_source()
	_apply_frame()


func _place_at_source() -> void:
	position=SourceActor.source_to_world(source_anchor)+Vector3(0,sin(SourceActor.ELEVATION),cos(SourceActor.ELEVATION))*view_depth_offset


func _process(delta: float) -> void:
	if not paused and frames.size() > 1:
		elapsed_ms += delta * 1000.0
		while elapsed_ms >= frames[frame_index]["duration_ms"]:
			elapsed_ms -= frames[frame_index]["duration_ms"]
			frame_index = (frame_index + 1) % frames.size()
			_apply_frame()


func _apply_frame() -> void:
	var offset: Array = frames[frame_index]["offset"]
	var center := Vector2(offset[0] + image_size.x / 2.0, -offset[1] - image_size.y / 2.0)
	$Sprite.position = Vector3(center.x, center.y * cos(SourceActor.ELEVATION),
		-center.y * sin(SourceActor.ELEVATION)) / SourceActor.PIXELS_PER_METER
