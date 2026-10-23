extends RefCounted
## Three render samples per unchanged 100 ms source locomotion frame.

var actor: Node
var enabled: bool=true
var spatial: bool
var data: Dictionary
var textures: Dictionary={}
var fields: Dictionary={}
var material: ShaderMaterial
var sprite_2d: Sprite2D
var phase: float=0.0
var active: bool=false


func setup(source_actor: Node,is_spatial: bool) -> void:
	actor=source_actor;spatial=is_spatial
	enabled=actor.get_tree().get_meta("port_pose_inbetweens",true)
	data=JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_inbetweens.json"))
	for pairs: Array in data["actions"].values():
		for pair: Dictionary in pairs:
			for path: String in [pair["current_texture"],pair["next_texture"],pair["current_layers"],pair["next_layers"]]:
				if not textures.has(path):textures[path]=load(path)
			for mapping: Dictionary in pair["maps"]:
				if not fields.has(mapping["texture"]):fields[mapping["texture"]]=load(mapping["texture"])
	if spatial:material=actor.source_material
	else:
		sprite_2d=Sprite2D.new()
		sprite_2d.name="InbetweenPose"
		sprite_2d.centered=false
		sprite_2d.position=-Vector2(data["foot_anchor"][0],data["foot_anchor"][1])
		sprite_2d.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		material=ShaderMaterial.new();material.shader=preload("res://shaders/pose_inbetween_2d.gdshader")
		sprite_2d.material=material
		actor.facing_root.add_child(sprite_2d)
		sprite_2d.visible=false


func set_enabled(value: bool) -> void:
	enabled=value
	actor.get_tree().set_meta("port_pose_inbetweens",value)
	sync()


func sync() -> void:
	active=enabled and data["actions"].has(actor.animation_name)
	phase=0.0
	if active:
		phase=minf(2.0,floorf(actor.elapsed_ms*.03+.00001))/3.0
		var pair: Dictionary=data["actions"][actor.animation_name][actor.frame_index]
		material.set_shader_parameter("source_texture",textures[pair["current_texture"]])
		material.set_shader_parameter("next_texture",textures[pair["next_texture"]])
		material.set_shader_parameter("current_layers",textures[pair["current_layers"]])
		material.set_shader_parameter("next_layers",textures[pair["next_layers"]])
		var mapping: Dictionary=pair["maps"][maxi(0,roundi(phase*3.0)-1)]
		material.set_shader_parameter("pose_flow",fields[mapping["texture"]])
		if not spatial:sprite_2d.texture=textures[pair["current_texture"]]
	material.set_shader_parameter("pose_phase",phase)
	if not spatial:
		var derived: bool=active and phase>0.0
		sprite_2d.visible=derived
		for layer: Sprite2D in actor._layers:layer.visible=not derived
