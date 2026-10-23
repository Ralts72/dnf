extends RefCounted
## Source visual tracks sampled from the actor's pose clock, with no second timer.
## Track blend and pose-time-zero attachment are explicit sample interpretations.

var enabled: bool=true
var actor: Node
var spatial: bool
var actions: Dictionary
var textures: Dictionary={}
var surfaces: Array=[]
var active_frames: Array=[]
var _materials: Dictionary={}


func setup(source_actor: Node,is_spatial: bool) -> void:
	actor=source_actor
	spatial=is_spatial
	enabled=actor.get_tree().get_meta("port_fx_enabled",true)
	actions=_load_actions()
	for tracks: Array in actions.values():
		for track: Dictionary in tracks:
			for frame: Dictionary in track["frames"]:
				if frame["texture"]!=null and not textures.has(frame["texture"]):
					textures[frame["texture"]]=load(frame["texture"])
	for i: int in range(2):
		var surface: Node
		if spatial:
			var sprite:=Sprite3D.new()
			sprite.pixel_size=1.0/actor.PIXELS_PER_METER
			sprite.scale.y=1.0/cos(actor.ELEVATION)
			sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sprite.material_override=_material_for(i,"add")
			surface=sprite
			actor.add_child(surface)
		else:
			var sprite:=Sprite2D.new()
			sprite.centered=false
			sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.material=_material_for(i,"add")
			surface=sprite
			actor.facing_root.add_child(surface)
		surface.name="SourceEffect"+str(i)
		surface.visible=false
		surfaces.append(surface)


func _load_actions() -> Dictionary:
	var combined: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_effects.json"))["actions"]
	var extension: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/ghost_slash_effects.json"))
	# Only this new action is merged; HopSmash keeps its original tracks and
	# implicit additive policy. No extra attachment timer or audio is created.
	combined["hardattack"]=extension["actions"]["hardattack"]
	return combined


func _material_for(index: int,blend: String) -> Material:
	assert(blend in ["normal","add"],"Unsupported source effect blend")
	var key: String=("3:" if spatial else "2:")+str(index)+":"+blend
	if _materials.has(key):return _materials[key]
	var material: Material
	if spatial:
		var shader_material:=ShaderMaterial.new()
		shader_material.shader=preload("res://shaders/source_effect_normal.gdshader") if blend=="normal" else preload("res://shaders/source_effect.gdshader")
		shader_material.render_priority=index+1
		material=shader_material
	else:
		var canvas_material:=CanvasItemMaterial.new()
		canvas_material.blend_mode=CanvasItemMaterial.BLEND_MODE_MIX if blend=="normal" else CanvasItemMaterial.BLEND_MODE_ADD
		material=canvas_material
	_materials[key]=material
	return material


func pose_time_ms() -> float:
	var clock: float=actor.elapsed_ms
	for i: int in range(actor.frame_index):
		clock+=actor._animations[actor.animation_name]["frames"][i]["duration_ms"]
	return clock


func sync() -> void:
	active_frames.clear()
	var tracks: Array=actions.get(actor.animation_name,[]) if enabled else []
	var clock: float=pose_time_ms()
	for i: int in range(surfaces.size()):
		var surface: Node=surfaces[i]
		var chosen: Dictionary={}
		var blend: String="add"
		if i<tracks.size():
			blend=str(tracks[i].get("blend","add"))
			for frame: Dictionary in tracks[i]["frames"]:
				if clock>=frame["start_ms"] and clock<frame["start_ms"]+frame["duration_ms"]:
					chosen=frame
					break
		var material: Material=_material_for(i,blend)
		if spatial:
			if surface.material_override!=material:surface.material_override=material
		else:
			if surface.material!=material:surface.material=material
		surface.set_meta("source_effect_blend",blend)
		surface.visible=not chosen.is_empty() and chosen["texture"]!=null
		if not surface.visible:
			continue
		var texture: Texture2D=textures[chosen["texture"]]
		var offset:=Vector2(chosen["offset"][0],chosen["offset"][1])
		surface.texture=texture
		if spatial:
			var center: Vector2=offset+texture.get_size()*.5
			surface.offset=Vector2(center.x*actor.facing,-center.y)
			var target:=Vector3(0.0,actor.height_above_ground,0.0)
			if surface.position!=target:surface.position=target
			surface.flip_h=actor.facing<0
			surface.material_override.set_shader_parameter("source_texture",texture)
			surface.material_override.set_shader_parameter("ground_y",actor.global_position.y)
		else:
			surface.position=offset
		active_frames.append({"track":tracks[i]["name"],"blend":blend,"start_ms":chosen["start_ms"],
			"texture":chosen["texture"],"offset":offset})
