extends RefCounted
## R1 locomotion display samples on the unchanged source animation clock.

const DATA_PATH: String="res://data/swordman_walk_inbetweens.json"
const DATA_PATHS: Dictionary={"move":DATA_PATH,"dash":"res://data/swordman_dash_inbetweens.json"}
var actor: Node
var spatial: bool=false
var enabled: bool=true
var active: bool=false
var subframe: int=0
var data: Dictionary={}
var clips: Dictionary={}
var textures: Dictionary={}
var clip_paths: Dictionary={}
var _clip_cache: Dictionary={}
var _texture_cache: Dictionary={}


func setup(source_actor: Node,is_spatial: bool) -> void:
	actor=source_actor;spatial=is_spatial
	enabled=actor.get_tree().get_meta("port_walk_inbetweens",true)
	if spatial:
		assert(reload_clips(DATA_PATHS))
	sync()


func prepare_clips(paths: Dictionary, animations: Dictionary = {}) -> Dictionary:
	# Stage everything before touching the live sampler, including when used
	# to preflight a new appearance whose animations are not installed yet.
	if not spatial or not is_instance_valid(actor) or paths.size()!=2 or not paths.has("move") or not paths.has("dash"):
		return {}
	var source: Dictionary=actor._animations if animations.is_empty() else animations
	var staged_clips: Dictionary={}
	var staged_textures: Dictionary={}
	for action: String in ["move","dash"]:
		if typeof(paths[action])!=TYPE_STRING or not source.has(action):return {}
		if not source[action] is Dictionary or not source[action].get("frames") is Array:return {}
		var path: String=paths[action]
		if not _clip_cache.has(path):
			if not FileAccess.file_exists(path):return {}
			var parser: JSON=JSON.new()
			if parser.parse(FileAccess.get_file_as_string(path))!=OK or not parser.data is Dictionary:return {}
			_clip_cache[path]=parser.data
		var clip: Dictionary=_clip_cache[path]
		if typeof(clip.get("action"))!=TYPE_STRING or clip.action!=action or not clip.get("frames") is Array:return {}
		if clip.has("bake_complete") and clip.bake_complete!=true:return {}
		if typeof(clip.get("source_frame_ms")) not in [TYPE_INT,TYPE_FLOAT] or float(clip.source_frame_ms)<=0:return {}
		for field: String in ["canvas_size","foot_anchor"]:
			var pair: Variant=clip.get(field)
			if not pair is Array or pair.size()!=2:return {}
			for number: Variant in pair:
				if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)):return {}
			var expected: Vector2=actor._canvas_size if field=="canvas_size" else actor._foot_anchor
			if Vector2(pair[0],pair[1])!=expected:return {}
		if typeof(clip.get("subframes")) not in [TYPE_INT,TYPE_FLOAT]:return {}
		var samples: int=int(clip.subframes)
		if float(samples)!=float(clip.subframes) or samples<2 or samples>8:return {}
		var frames: Array=source[action].frames
		if clip.frames.size()!=frames.size():return {}
		if typeof(clip.get("cycle_ms")) not in [TYPE_INT,TYPE_FLOAT] or float(clip.cycle_ms)!=frames.size()*float(clip.source_frame_ms):return {}
		for index: int in frames.size():
			if not frames[index] is Dictionary or typeof(frames[index].get("texture"))!=TYPE_STRING:return {}
			if typeof(frames[index].get("duration_ms")) not in [TYPE_INT,TYPE_FLOAT]:return {}
			if not clip.frames[index] is Dictionary:return {}
			var frame: Dictionary=clip.frames[index]
			if frame.get("source")!=frames[index].get("texture") or float(frames[index].duration_ms)!=float(clip.source_frame_ms):return {}
			if not frame.get("intermediates") is Array or frame.intermediates.size()!=samples-1:return {}
			for texture_path: Variant in frame.intermediates:
				if typeof(texture_path)!=TYPE_STRING:return {}
				if not _texture_cache.has(texture_path):
					if not ResourceLoader.exists(texture_path):return {}
					var texture: Texture2D=load(texture_path) as Texture2D
					if texture==null:return {}
					_texture_cache[texture_path]=texture
				if _texture_cache[texture_path].get_size()!=actor._canvas_size:return {}
				staged_textures[texture_path]=_texture_cache[texture_path]
		staged_clips[action]=clip
	return {"clips":staged_clips,"textures":staged_textures,"paths":paths.duplicate(true)}


func reload_clips(paths: Dictionary) -> bool:
	var staged: Dictionary=prepare_clips(paths)
	if staged.is_empty():return false
	clips=staged.clips
	textures=staged.textures
	clip_paths=staged.paths
	data=clips.move
	sync()
	return true


func texture_counts() -> Dictionary:
	var result: Dictionary={}
	for action: String in clips:result[action]=clips[action].frames.size()*(clips[action].subframes-1)
	return result


func set_enabled(value: bool) -> void:
	enabled=value
	actor.get_tree().set_meta("port_walk_inbetweens",value)
	sync()


func sync() -> void:
	active=spatial and enabled and clips.has(actor.animation_name) and not actor.jump_motion.is_active()
	subframe=0
	if not spatial:return
	var texture: Texture2D=actor._textures[actor.current_frame().texture]
	if active:
		var clip: Dictionary=clips[actor.animation_name]
		subframe=clampi(int(floor(actor.elapsed_ms*float(clip.subframes)/float(clip.source_frame_ms)+.0001)),0,clip.subframes-1)
		if subframe>0:texture=textures[clip.frames[actor.frame_index].intermediates[subframe-1]]
	if actor.sprite.texture!=texture:
		actor.sprite.texture=texture
		actor.source_material.set_shader_parameter("source_texture",texture)
