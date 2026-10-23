extends RefCounted
## Transactional appearance swap. Animation/gameplay nodes and clocks survive.

static var _data_cache: Dictionary={}
static var _last_error: String=""


func apply(actor: Node, definition: Dictionary) -> bool:
	_last_error=""
	if not is_instance_valid(actor) or not actor.is_node_ready():return _fail("Actor is not ready")
	if not actor.has_method("_apply_frame") or not actor.has_method("current_frame"):return _fail("Unsupported source actor")
	var spatial: bool=actor is CharacterBody3D
	var value: Variant=definition.get("r1_data" if spatial else "r0_data")
	if typeof(value)!=TYPE_STRING:return _fail("Missing appearance data path")
	var path: String=value
	var staged: Dictionary=_bundle(path,spatial)
	if staged.is_empty():return false
	var old_animations: Dictionary=actor._animations
	if not _compatible(old_animations,staged.animations,spatial,actor):return _fail("Appearance animation layout/timing is incompatible")
	var paths: Dictionary={}
	var helper: RefCounted=actor.walk_inbetweens
	if spatial:
		if staged.canvas!=actor._canvas_size or staged.anchor!=actor._foot_anchor:return _fail("Appearance changes canvas or foot anchor")
		if helper==null:return _fail("Missing spatial locomotion sampler")
		paths={"move":definition.get("walk_data"),"dash":definition.get("dash_data")}
		if helper.prepare_clips(paths,staged.animations).is_empty():return _fail("Appearance locomotion clips are unavailable or incompatible")
	var key: String=str(definition.get("key",definition.get("item_id",definition.get("id",path))))
	if actor.animation_data==path and current_key(actor)==key and (not spatial or helper.clip_paths==paths):return true
	var old_textures: Dictionary=actor._textures
	var old_path: String=actor.animation_data
	# No await and no _ready/play/restore_state call: retain the exact current
	# action, counters, queued attack, jump object, audio and effect instances.
	actor._animations=staged.animations
	actor._textures=staged.textures
	actor.animation_data=path
	if spatial and not helper.reload_clips(paths):
		actor._animations=old_animations
		actor._textures=old_textures
		actor.animation_data=old_path
		actor._apply_frame()
		return _fail("Locomotion reload failed; previous appearance retained")
	actor._apply_frame()
	if spatial:
		actor._update_sprite_transform()
	else:
		actor.queue_redraw()
	actor.set_meta("equipment_appearance_key",key)
	actor.set_meta("equipment_appearance_data",path)
	return true


func current_key(actor: Node) -> String:
	return str(actor.get_meta("equipment_appearance_key","")) if is_instance_valid(actor) else ""


func capture_state(actor: Node) -> Dictionary:
	if not is_instance_valid(actor):return {"last_error":_last_error,"valid_actor":false}
	var result: Dictionary={"key":current_key(actor),"data_path":actor.animation_data,
		"spatial":actor is CharacterBody3D,"action":actor.animation_name,"frame":actor.frame_index,
		"elapsed_ms":actor.elapsed_ms,"texture_count":actor._textures.size(),"last_error":_last_error}
	if actor is CharacterBody3D and actor.walk_inbetweens:
		result["clip_paths"]=actor.walk_inbetweens.clip_paths.duplicate(true)
		result["inbetweens_enabled"]=actor.walk_inbetweens.enabled
	return result


static func _bundle(path: String, spatial: bool) -> Dictionary:
	var key: String=("3:" if spatial else "2:")+path
	if _data_cache.has(key):return _data_cache[key]
	if not FileAccess.file_exists(path):
		_fail("Appearance data does not exist")
		return {}
	var parser: JSON=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK or not parser.data is Dictionary:
		_fail("Invalid appearance data")
		return {}
	var content: Dictionary=parser.data
	if not content.get("animations") is Dictionary:
		_fail("Missing appearance animations")
		return {}
	var result: Dictionary={"animations":content.animations,"textures":{}}
	if spatial:
		if not _pair(content.get("canvas_size")) or not _pair(content.get("foot_anchor")):
			_fail("Invalid appearance canvas/anchor")
			return {}
		result["canvas"]=Vector2(content.canvas_size[0],content.canvas_size[1])
		result["anchor"]=Vector2(content.foot_anchor[0],content.foot_anchor[1])
	for action: Variant in content.animations:
		var animation: Variant=content.animations[action]
		if not animation is Dictionary or not animation.get("frames") is Array:return {}
		for frame: Variant in animation.frames:
			if not frame is Dictionary or not _duration(frame.get("duration_ms")):return {}
			if not spatial and not frame.get("layers") is Array:return {}
			var layers: Array=[frame] if spatial else frame.layers
			if layers.is_empty():return {}
			for layer: Variant in layers:
				if not layer is Dictionary or typeof(layer.get("texture"))!=TYPE_STRING:return {}
				if not spatial and (typeof(layer.get("name"))!=TYPE_STRING or not _pair(layer.get("offset"))):return {}
				var texture_path: String=layer.texture
				if not result.textures.has(texture_path):
					if not ResourceLoader.exists(texture_path):return {}
					var texture: Texture2D=load(texture_path) as Texture2D
					if texture==null or (spatial and texture.get_size()!=result.canvas):return {}
					result.textures[texture_path]=texture
	_data_cache[key]=result
	return result


static func _compatible(old: Dictionary, replacement: Dictionary, spatial: bool, actor: Node) -> bool:
	if old.size()!=replacement.size() or not replacement.has(actor.animation_name):return false
	for action: String in old:
		if not replacement.has(action):return false
		var before: Array=old[action].frames
		var after: Array=replacement[action].frames
		if before.size()!=after.size() or after.is_empty():return false
		for index: int in before.size():
			if float(before[index].duration_ms)!=float(after[index].duration_ms) or before[index].get("img_frame")!=after[index].get("img_frame"):return false
			if before[index].get("source_boxes",[])!=after[index].get("source_boxes",[]) or before[index].get("source_properties",[])!=after[index].get("source_properties",[]):return false
			if not spatial:
				if after[index].layers.size()!=actor._layers.size() or before[index].layers.size()!=after[index].layers.size():return false
				for slot: int in before[index].layers.size():
					if before[index].layers[slot].name!=after[index].layers[slot].name:return false
	return actor.frame_index>=0 and actor.frame_index<replacement[actor.animation_name].frames.size()


static func _duration(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)>0.0


static func _pair(value: Variant) -> bool:
	if not value is Array or value.size()!=2:return false
	for number: Variant in value:
		if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)):return false
	return true


static func _fail(message: String) -> bool:
	_last_error=message
	return false
