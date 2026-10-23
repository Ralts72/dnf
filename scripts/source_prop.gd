extends Node2D
## Small source animations (ship motion) use the same per-frame offsets as the ANI.

@export var frames: Array[Dictionary] = []
var frame_index: int = 0
var elapsed_ms: float = 0.0
var paused: bool = false


func _process(delta: float) -> void:
	if frames.size() < 2 or paused:
		return
	elapsed_ms += delta * 1000.0
	while elapsed_ms >= frames[frame_index]["duration_ms"]:
		elapsed_ms -= frames[frame_index]["duration_ms"]
		frame_index = (frame_index + 1) % frames.size()
		var frame: Dictionary = frames[frame_index]
		$Image.position = Vector2(frame["offset"][0], frame["offset"][1])
