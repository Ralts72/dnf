extends Node2D
## Experimental renderer only; source PNGs are sampled without color edits.

var recipe: Dictionary
var frames: Array
var textures: Dictionary={}
var masks: Array[Texture2D]=[]
var materials: Array[ShaderMaterial]=[]
var frame_index: int=-1
var subframe: int=-1


func _ready() -> void:
	recipe=JSON.parse_string(FileAccess.get_file_as_string("res://source_art/r1/experiments/walk_cycle_24/walk_recipe.json"))
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(recipe.source_data))
	frames=data["animations"][recipe.action]["frames"]
	var shader:=Shader.new()
	shader.code=FileAccess.get_file_as_string("res://source_art/r1/experiments/walk_cycle_24/walk_shear.gdshader")
	for frame: Dictionary in frames:
		var mask:=Image.create(320,224,false,Image.FORMAT_R8);mask.fill(Color.WHITE)
		for layer: Dictionary in frame.layers:
			if not textures.has(layer.texture):textures[layer.texture]=load(layer.texture)
		for slot: int in [2,3,4,5]:
			var layer: Dictionary=frame.layers[slot]
			var image:=Image.new();image.load_png_from_buffer(FileAccess.get_file_as_bytes(layer.texture))
			for y: int in image.get_height():
				for x: int in image.get_width():
					var point:=Vector2i(x+layer.offset[0]+133,y+layer.offset[1]+167)
					if Rect2i(0,0,320,224).has_point(point) and image.get_pixel(x,y).a>=.25:mask.set_pixelv(point,Color.BLACK)
		masks.append(ImageTexture.create_from_image(mask))
	for slot: int in 9:
		var rect:=TextureRect.new()
		rect.texture=textures[frames[0].layers[slot].texture]
		rect.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.stretch_mode=TextureRect.STRETCH_SCALE
		rect.size=Vector2(320,224);rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var material:=ShaderMaterial.new();material.shader=shader
		material.set_shader_parameter("hip_y",recipe.hip_y)
		material.set_shader_parameter("ankle_y",recipe.ankle_y)
		rect.material=material;materials.append(material);add_child(rect)
	update_pose(0,0)


func foot(frame: int,leg: int) -> Vector2:
	var point: Array=recipe.physical_feet_A_B[frame][leg]
	return Vector2(point[0],point[1])


func ankle(frame: int,leg: int) -> Vector2:
	var point: Array=recipe.physical_ankles_A_B[frame][leg]
	return Vector2(point[0],point[1])


func update_pose(index: int,sample_index: int) -> void:
	frame_index=index;subframe=sample_index
	var derived: bool=sample_index>0
	var phase: float=float(sample_index)/3.0
	var template: int=recipe.templates[index]
	var boot_frame: int=index if sample_index==1 else (index+1)%8
	for slot: int in 9:
		var leg_slot: bool=slot in [2,3,4,5]
		var layer: Dictionary=frames[template if derived and leg_slot else index].layers[slot]
		if derived and slot in [3,5]:layer=frames[boot_frame].layers[5 if boot_frame==6 else slot]
		var texture: Texture2D=textures[layer.texture]
		var material: ShaderMaterial=materials[slot]
		material.set_shader_parameter("source_texture",texture)
		material.set_shader_parameter("source_offset",Vector2(layer.offset[0]+133,layer.offset[1]+167))
		material.set_shader_parameter("source_size",texture.get_size())
		material.set_shader_parameter("body_visibility",masks[index])
		var upper: Dictionary=frames[index].layers[slot]
		material.set_shader_parameter("upper_texture",textures[upper.texture])
		material.set_shader_parameter("upper_offset",Vector2(upper.offset[0]+133,upper.offset[1]+167))
		material.set_shader_parameter("upper_size",textures[upper.texture].get_size())
		material.set_shader_parameter("shoe_piece",(1 if slot==5 else 2) if derived and boot_frame==6 and slot in [3,5] else 0)
		var kind: int=1 if derived and slot in [2,4] else (2 if derived and slot in [3,5] else (3 if derived and slot==1 else 0))
		material.set_shader_parameter("kind",kind)
		if derived and leg_slot:
			var leg: int=0 if slot in [4,5] else 1
			var target: Vector2=foot(index,leg).lerp(foot((index+1)%8,leg),phase)
			var translation: Vector2=target-foot(boot_frame,leg)
			if slot in [2,4]:translation=ankle(boot_frame,leg)+translation-ankle(template,leg)
			material.set_shader_parameter("ankle_y",ankle(template,leg).y)
			material.set_shader_parameter("foot_shift",translation)
