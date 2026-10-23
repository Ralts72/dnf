extends MeshInstance3D
## One clock/material per scene, including independent capture viewports.

var paused: bool=false
var seconds: float=0.0
var water_material: ShaderMaterial


func _ready() -> void:
	water_material=(mesh.surface_get_material(0) as ShaderMaterial).duplicate()
	material_override=water_material
	_apply_clock()


func _process(delta: float) -> void:
	if not paused:
		seconds+=delta
		_apply_clock()


func _apply_clock() -> void:
	water_material.set_shader_parameter("water_time",seconds)


func capture_state() -> Dictionary:
	return {"seconds":seconds,"paused":paused}


func restore_state(state: Dictionary) -> void:
	seconds=maxf(0.0,float(state.get("seconds",0.0)))
	paused=bool(state.get("paused",paused))
	_apply_clock()
