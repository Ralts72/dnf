extends CharacterBody3D
## One transparent surface per actor, composited from the retained original layers.

const PIXELS_PER_METER: float = 60.0
const ELEVATION: float = 0.6632251158 # 38 degrees
const CAMERA_TARGET_Z: float = -1.6
const SOURCE_CENTER: Vector2 = Vector2(448.0, 202.0)

@export_file("*.json") var animation_data: String
@export_file("*.json") var motion_data: String="res://data/swordman_motion.json"
@export var controllable: bool = false
@export var source_position: Vector2 = Vector2(440, 320)

var animation_name: String = ""
var frame_index: int = 0
var elapsed_ms: float = 0.0
var facing: int = 1
var paused: bool = false:
	set(value):
		paused=value
		if is_instance_valid(action_audio):
			action_audio.set_paused(value)
		if is_instance_valid(motion_smoothing):
			motion_smoothing.apply()
var preview_mode: bool = false
var markers_visible: bool = false:
	set(value):
		markers_visible = value
		if is_node_ready():
			$FootMarker.visible = value
var completed_actions: int = 0
var frame_transitions: int = 0
var next_attack: String = "attack1"
var ui_input_blocked: bool = false
var action_audio: Node
var action_effects: RefCounted
var motion_smoothing: RefCounted
var pose_inbetweens: RefCounted
var _one_shot: bool = false
var _animations: Dictionary = {}
var _textures: Dictionary = {}
var _canvas_size: Vector2
var _foot_anchor: Vector2
var height_above_ground: float = 0.0
var jump_motion=preload("res://scripts/source_jump.gd").new()

@onready var sprite: Sprite3D = $Sprite
@onready var source_material: ShaderMaterial = $Sprite.material_override


static func source_to_world(point: Vector2) -> Vector3:
	return Vector3((point.x - SOURCE_CENTER.x) / PIXELS_PER_METER, 0.025,
		(point.y + 43.0 - SOURCE_CENTER.y) / (PIXELS_PER_METER * sin(ELEVATION)) + CAMERA_TARGET_Z)


static func world_to_source(point: Vector3) -> Vector2:
	return Vector2(point.x * PIXELS_PER_METER + SOURCE_CENTER.x,
		(point.z - CAMERA_TARGET_Z) * PIXELS_PER_METER * sin(ELEVATION) + SOURCE_CENTER.y - 43.0)


func _ready() -> void:
	# Each scene instance animates its own sampler, including offscreen QA views.
	source_material = source_material.duplicate() as ShaderMaterial
	sprite.material_override = source_material
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(animation_data))
	_animations = data["animations"]
	_canvas_size = Vector2(data["canvas_size"][0], data["canvas_size"][1])
	_foot_anchor = Vector2(data["foot_anchor"][0], data["foot_anchor"][1])
	for animation: Dictionary in _animations.values():
		for frame: Dictionary in animation["frames"]:
			var path: String = frame["texture"]
			if not _textures.has(path):
				_textures[path] = load(path)
	position = source_to_world(source_position)
	if controllable:
		jump_motion.configure(JSON.parse_string(FileAccess.get_file_as_string(motion_data)),
			_animations["jump"]["frames"],_animations["jumpattack"]["frames"])
		action_audio=preload("res://scripts/source_actor_audio.gd").new()
		action_audio.name="ActionAudio"
		add_child(action_audio)
		action_audio.setup(self)
		action_effects=preload("res://scripts/source_actor_effects.gd").new()
		action_effects.setup(self,true)
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	# Upright geometry gives props a physical depth to sort against. Compensate
	# its projected height so every original source pixel keeps its screen size.
	sprite.rotation=Vector3.ZERO
	sprite.scale=Vector3(1.0,1.0/cos(ELEVATION),1.0)
	play("stay")
	_update_sprite_transform()
	if controllable:
		motion_smoothing=preload("res://scripts/source_motion_smoothing.gd").new()
		motion_smoothing.setup(self)
		pose_inbetweens=preload("res://scripts/source_pose_inbetweens.gd").new()
		pose_inbetweens.setup(self,true)


func _physics_process(delta: float) -> void:
	velocity = Vector3.ZERO
	if not controllable or paused:
		return
	if jump_motion.is_active():
		_tick_jump(delta,not ui_input_blocked)
		return
	if preview_mode or _one_shot or ui_input_blocked:
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if absf(direction.x) > 0.01:
		facing = 1 if direction.x > 0.0 else -1
	if direction.length_squared() < 0.01:
		play("stay")
		return
	var running := Input.is_action_pressed("run")
	var speed := 190.0 if running else 100.0
	_move_ground(direction,speed)
	play("dash" if running else "move")


func _move_ground(direction: Vector2,speed: float) -> void:
	if direction.length_squared()<.01:
		velocity=Vector3.ZERO
		return
	velocity = Vector3(direction.x * speed / PIXELS_PER_METER, 0.0,
		direction.y * 0.58 * speed / (PIXELS_PER_METER * sin(ELEVATION)))
	var previous := world_to_source(position)
	move_and_slide()
	var map_position := preload("res://scripts/demo_walk_area.gd").constrain(previous,world_to_source(position))
	position = source_to_world(map_position)


func start_jump() -> bool:
	if not controllable or paused or _one_shot or ui_input_blocked or jump_motion.is_active():
		return false
	if not jump_motion.begin(Input.is_action_pressed("run")):
		return false
	preview_mode=false
	_one_shot=false
	action_audio.begin_jump(jump_motion.prep_seconds,jump_motion.flight_seconds)
	play("jump",true)
	_apply_jump_pose()
	_update_sprite_transform()
	return true


func _tick_jump(delta: float,allow_input: bool=true) -> void:
	if action_audio:
		action_audio.advance(delta)
	jump_motion.advance(delta)
	if not jump_motion.is_active():
		action_audio.finish()
		play("stay",true)
		_update_sprite_transform()
		return
	var direction: Vector2=Input.get_vector("move_left","move_right","move_up","move_down") if allow_input else Vector2.ZERO
	if jump_motion.phase=="landing":
		direction=Vector2.ZERO
	if absf(direction.x)>.01:
		facing=1 if direction.x>0.0 else -1
	_move_ground(direction,jump_motion.travel_speed)
	_apply_jump_pose()
	_update_sprite_transform()


func _apply_jump_pose() -> void:
	var pose: Dictionary=jump_motion.pose()
	if animation_name!=pose["action"]:
		play(pose["action"],true)
	frame_index=pose["frame"]
	elapsed_ms=pose["elapsed_ms"]
	_apply_frame()


func _process(delta: float) -> void:
	if not paused and not jump_motion.is_active():
		if _one_shot and action_audio:
			action_audio.advance(delta)
		elapsed_ms += delta * 1000.0
		while elapsed_ms >= current_frame()["duration_ms"]:
			elapsed_ms -= current_frame()["duration_ms"]
			_advance_frame()
	_update_sprite_transform()


func _update_sprite_transform() -> void:
	# A world-up displacement projects to cos(elevation) screen pixels/metre.
	height_above_ground=jump_motion.height_pixels/(PIXELS_PER_METER*cos(ELEVATION))
	var shift := Vector2(_canvas_size.x / 2.0 - _foot_anchor.x,
		_foot_anchor.y - _canvas_size.y / 2.0)
	# Crop and facing offsets are geometry changes, not interpolated transforms.
	# All actor surfaces keep their transform anchored to the same logical foot.
	sprite.offset=Vector2(shift.x*facing,shift.y)
	var target:=Vector3(0.0,height_above_ground,0.0)
	if sprite.position!=target:sprite.position=target
	sprite.flip_h = facing < 0
	var ratio: float=jump_motion.height_ratio()
	var shadow_scale: float=lerpf(1.0,.7,ratio)
	var shadow_target:=Vector3(shadow_scale,1.0,shadow_scale)
	if $ContactShadow.scale!=shadow_target:$ContactShadow.scale=shadow_target
	$ContactShadow.set_instance_shader_parameter("height_ratio",ratio)
	if action_effects:
		action_effects.sync()
	if pose_inbetweens:
		pose_inbetweens.sync()


func current_frame() -> Dictionary:
	return _animations[animation_name]["frames"][frame_index]


func play(action: String, restart: bool = false) -> void:
	if not _animations.has(action) or (action == animation_name and not restart):
		return
	animation_name = action
	frame_index = 0
	elapsed_ms = 0.0
	_apply_frame()


func _apply_frame() -> void:
	sprite.texture = _textures[current_frame()["texture"]]
	source_material.set_shader_parameter("source_texture", sprite.texture)
	source_material.set_shader_parameter("ground_y", global_position.y)
	if action_effects:
		action_effects.sync()
	if pose_inbetweens:
		pose_inbetweens.sync()


func _advance_frame() -> void:
	frame_index += 1
	frame_transitions += 1
	if frame_index >= _animations[animation_name]["frames"].size():
		if _one_shot:
			_one_shot = false
			if action_audio:
				action_audio.finish()
			completed_actions += 1
			play("stay", true)
			return
		frame_index = 0
	_apply_frame()


func preview(action: String) -> void:
	if action_audio:
		action_audio.stop()
	jump_motion.reset()
	preview_mode = true
	_one_shot = false
	play(action, true)
	_update_sprite_transform()
	if motion_smoothing:motion_smoothing.reset()


func free_control() -> void:
	preview_mode = false
	_one_shot = false
	if jump_motion.is_active():
		return
	if action_audio:
		action_audio.stop()
	play("stay", true)


func perform(action: String) -> void:
	if paused or _one_shot or ui_input_blocked or jump_motion.is_active() or not _animations.has(action):
		return
	preview_mode = false
	_one_shot = true
	if action_audio:
		action_audio.begin_action(action)
	play(action, true)


func attack() -> void:
	if paused or _one_shot or ui_input_blocked:
		return
	if jump_motion.is_active():
		if jump_motion.begin_air_attack():
			action_audio.begin_air_attack(jump_motion.prep_seconds+jump_motion.flight_seconds)
			_apply_jump_pose()
		return
	perform(next_attack)
	next_attack = {"attack1":"attack2","attack2":"attack3","attack3":"attack1"}[next_attack]


func turn_around() -> void:
	facing = -facing
	_update_sprite_transform()


func reset_position() -> void:
	jump_motion.reset()
	position = source_to_world(Vector2(440, 320))
	facing = 1
	next_attack = "attack1"
	paused = false
	free_control()
	_update_sprite_transform()
	if motion_smoothing:motion_smoothing.reset()


func step_frame() -> void:
	paused = true
	if jump_motion.is_active():
		_tick_jump(1.0/60.0,false)
		return
	if _one_shot and action_audio:
		action_audio.advance((float(current_frame()["duration_ms"])-elapsed_ms)/1000.0)
	elapsed_ms = 0.0
	_advance_frame()


func capture_state() -> Dictionary:
	return {"position":world_to_source(position), "facing":facing, "action":animation_name,
		"frame":frame_index, "elapsed_ms":elapsed_ms, "paused":paused,
		"preview":preview_mode, "one_shot":_one_shot,"next_attack":next_attack,
		"jump":jump_motion.capture_state(),
		"audio":action_audio.capture_state() if action_audio else {}}


func restore_state(state: Dictionary) -> void:
	position = source_to_world(state["position"])
	facing = state["facing"]
	preview_mode = state["preview"]
	paused = state["paused"]
	_one_shot = state.get("one_shot", false)
	next_attack = state.get("next_attack","attack1")
	jump_motion.restore_state(state.get("jump",{}))
	if action_audio:
		action_audio.restore_state(state.get("audio",{}))
		action_audio.set_paused(paused)
	play(state["action"], true)
	frame_index = state["frame"]
	elapsed_ms = state["elapsed_ms"]
	_apply_frame()
	_update_sprite_transform()
	if motion_smoothing:motion_smoothing.reset()
