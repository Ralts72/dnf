extends Node2D
## Native prototype: raw endpoints; manual two-bone pants and rigid source boots.

var recipe: Dictionary
var frames: Array
var textures: Dictionary={}
var body_masks: Array=[]
var pants_masks: Array=[]
var boot_masks: Array=[]
var shader: Shader
var displays: Array[CanvasItem]=[]
var frame_index: int=-1
var subframe: int=-1
var identity_test: bool=false


func point(value: Array) -> Vector2:return Vector2(value[0],value[1])


func _ready() -> void:
	recipe=JSON.parse_string(FileAccess.get_file_as_string("res://source_art/r1/experiments/dash_cycle_26/dash_recipe.json"))
	frames=JSON.parse_string(FileAccess.get_file_as_string(recipe.source_data)).animations.dash.frames
	shader=Shader.new();shader.code=FileAccess.get_file_as_string("res://source_art/r1/experiments/dash_cycle_26/dash_skin.gdshader")
	for frame: int in 8:
		var body:=Image.create(320,224,false,Image.FORMAT_R8);body.fill(Color.WHITE)
		var pants: Array=[];var boots: Array=[]
		for _leg: int in 2:
			pants.append(Image.create(320,224,false,Image.FORMAT_R8));boots.append(Image.create(320,224,false,Image.FORMAT_R8))
		for slot: int in 9:
			var layer: Dictionary=frames[frame].layers[slot]
			if not textures.has(layer.texture):textures[layer.texture]=load(layer.texture)
			if slot not in [2,3,4,5]:continue
			var image:=Image.new();image.load_png_from_buffer(FileAccess.get_file_as_bytes(layer.texture))
			for y: int in image.get_height():
				for x: int in image.get_width():
					if image.get_pixel(x,y).a<.5:continue
					var p:=Vector2i(x+layer.offset[0]+133,y+layer.offset[1]+167)
					if not Rect2i(0,0,320,224).has_point(p):continue
					body.set_pixelv(p,Color.BLACK)
					if slot in [2,4] and p.y>=recipe.hip_y:
						var owners: Array=[]
						for leg: int in 2:
							if recipe.leg_pants_slots[frame][leg]==slot:owners.append(leg)
						var leg: int=owners[0]
						if owners.size()==2 and leg_distance(Vector2(p)+Vector2(.5,.5),frame,1)<leg_distance(Vector2(p)+Vector2(.5,.5),frame,0):leg=1
						pants[leg].set_pixelv(p,Color.WHITE)
					elif slot in [3,5]:
						for leg: int in 2:
							var boot: Dictionary=recipe.boots[frame][leg];var b: Array=boot.bbox
							if slot==boot.slot and Rect2i(b[0],b[1],b[2]-b[0],b[3]-b[1]).has_point(p):boots[leg].set_pixelv(p,Color.WHITE)
		body_masks.append(ImageTexture.create_from_image(body))
		pants_masks.append(pants.map(func(i: Image):return ImageTexture.create_from_image(i)))
		boot_masks.append(boots.map(func(i: Image):return ImageTexture.create_from_image(i)))
	update_pose(0,0)


func leg_distance(p: Vector2,frame: int,leg: int) -> float:
	var h: Vector2=point(recipe.hips[frame][leg]);var k: Vector2=point(recipe.knees[frame][leg]);var a: Vector2=point(recipe.boots[frame][leg].ankle)
	return minf(p.distance_to(Geometry2D.get_closest_point_to_segment(p,h,k)),p.distance_to(Geometry2D.get_closest_point_to_segment(p,k,a)))


func material(frame: int,slot: int,kind: int,mask: Texture2D=null,shift: Vector2=Vector2.ZERO) -> ShaderMaterial:
	var layer: Dictionary=frames[frame].layers[slot]
	var value:=ShaderMaterial.new();value.shader=shader
	value.set_shader_parameter("source_texture",textures[layer.texture]);value.set_shader_parameter("source_size",textures[layer.texture].get_size())
	value.set_shader_parameter("source_offset",point(layer.offset)+Vector2(133,167));value.set_shader_parameter("kind",kind)
	value.set_shader_parameter("source_shift",shift);value.set_shader_parameter("hip_y",recipe.hip_y)
	if mask:value.set_shader_parameter("part_visibility",mask)
	return value


func rectangle(frame: int,slot: int,kind: int=0,mask: Texture2D=null,shift: Vector2=Vector2.ZERO) -> void:
	var rect:=TextureRect.new();rect.size=Vector2(320,224);rect.texture=textures[frames[frame].layers[slot].texture]
	rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.stretch_mode=TextureRect.STRETCH_SCALE
	rect.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rect.material=material(frame,slot,kind,mask,shift);add_child(rect);displays.append(rect)


func bone_transform(p: Vector2,a: Vector2,b: Vector2,c: Vector2,d: Vector2) -> Vector2:
	var axis: Vector2=(b-a).normalized();var target: Vector2=(d-c).normalized()
	var t: float=(p-a).dot(axis)/a.distance_to(b);var side: float=(p-a).dot(axis.orthogonal())
	return c+(d-c)*t+target.orthogonal()*side


func deform(p: Vector2,frame: int,leg: int,h: Vector2,k: Vector2,a: Vector2) -> Vector2:
	var sh: Vector2=point(recipe.hips[frame][leg]);var sk: Vector2=point(recipe.knees[frame][leg]);var sa: Vector2=point(recipe.boots[frame][leg].ankle)
	var u: Vector2=Geometry2D.get_closest_point_to_segment(p,sh,sk);var l: Vector2=Geometry2D.get_closest_point_to_segment(p,sk,sa)
	var along: float=sh.distance_to(u) if p.distance_squared_to(u)<=p.distance_squared_to(l) else sh.distance_to(sk)+sk.distance_to(l)
	var weight: float=smoothstep(sh.distance_to(sk)-6.0,sh.distance_to(sk)+6.0,along)
	return bone_transform(p,sh,sk,h,k).lerp(bone_transform(p,sk,sa,k,a),weight)


func pants_mesh(frame: int,leg: int,h: Vector2,k: Vector2,a: Vector2) -> void:
	var mask: Texture2D=pants_masks[frame][leg]
	var layer: Dictionary=frames[frame].layers[recipe.leg_pants_slots[frame][leg]]
	var bounds:=Rect2i(Vector2i(point(layer.offset)+Vector2(133,167)),textures[layer.texture].get_size())
	bounds=bounds.intersection(Rect2i(0,int(recipe.hip_y),320,224-int(recipe.hip_y))).grow(2)
	var vertices:=PackedVector3Array();var uv:=PackedVector2Array();var indices:=PackedInt32Array()
	var width: int=bounds.size.x+1
	for y: int in range(bounds.position.y,bounds.end.y+1):
		for x: int in range(bounds.position.x,bounds.end.x+1):
			var p:=Vector2(x,y);var target: Vector2=deform(p,frame,leg,h,k,a)
			vertices.append(Vector3(target.x,target.y,0));uv.append(p/Vector2(320,224))
	for y: int in bounds.size.y:
		for x: int in bounds.size.x:
			var i: int=y*width+x
			indices.append_array(PackedInt32Array([i,i+1,i+width,i+1,i+width+1,i+width]))
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var display:=MeshInstance2D.new();display.mesh=mesh;display.texture=textures[frames[frame].layers[recipe.leg_pants_slots[frame][leg]].texture]
	display.material=material(frame,recipe.leg_pants_slots[frame][leg],1,mask)
	add_child(display);displays.append(display)


func update_pose(index: int,sample_index: int) -> void:
	frame_index=index;subframe=sample_index
	for display: CanvasItem in displays:remove_child(display);display.queue_free()
	displays.clear()
	if sample_index==0:
		for slot: int in 9:rectangle(index,slot)
		return
	var phase: float=float(sample_index)/3.0;var next: int=(index+1)%8;var template: int=index if sample_index==1 else next
	if identity_test:phase=0;template=index
	rectangle(index,0);rectangle(index,1,4,body_masks[index])
	var front: int=recipe.front_leg[template]
	for leg: int in [1-front,front]:
		var target: Vector2=point(recipe.boots[index][leg].center).lerp(point(recipe.boots[next][leg].center),phase)
		var shift: Vector2=target-point(recipe.boots[template][leg].center)
		var knee: Vector2=point(recipe.knees[index][leg]).lerp(point(recipe.knees[next][leg]),phase)
		var ankle: Vector2=point(recipe.boots[template][leg].ankle)+shift
		pants_mesh(template,leg,point(recipe.hips[index][leg]),knee,ankle)
		rectangle(template,recipe.boots[template][leg].slot,3,boot_masks[template][leg],shift)
	for slot: int in [2,4]:rectangle(index,slot,2)
	for slot: int in [6,7,8]:rectangle(index,slot)
