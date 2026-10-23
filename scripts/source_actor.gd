extends Node2D
## Plays selected source ANI crops and durations. Combat semantics are deliberately separate.

@export_file("*.json") var animation_data: String
@export_file("*.json") var motion_data: String="res://data/swordman_motion.json"
@export var initial_animation: String = "stay"
@export var controllable: bool = false
@export var actor_label: String = ""

var animation_name: String = ""
var frame_index: int = 0
var elapsed_ms: float = 0.0
var paused: bool = false:
	set(value):
		paused=value
		if is_instance_valid(action_audio):
			action_audio.set_paused(value)
		if is_instance_valid(motion_smoothing):
			motion_smoothing.apply()
var markers_visible: bool = false
var preview_mode: bool = false
var facing: int = 1
var completed_actions: int = 0
var frame_transitions: int = 0
var next_attack: String = "attack1"
var ui_input_blocked: bool = false
var action_audio: Node
var action_effects: RefCounted
var motion_smoothing: RefCounted
var walk_inbetweens: RefCounted
var facing_root: Node2D
var _animations: Dictionary = {}
var _textures: Dictionary = {}
var _layers: Array[Sprite2D] = []
var _one_shot: bool = false
var jump_motion=preload("res://scripts/source_jump.gd").new()

@onready var visual: Node2D = $Visual


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(animation_data))
	_animations = data["animations"]
	for child in visual.get_children():
		if child is Sprite2D:
			_layers.append(child)
	# Keep flip changes instantaneous while Visual's jump height interpolates.
	facing_root=Node2D.new()
	facing_root.name="Facing"
	facing_root.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	visual.add_child(facing_root)
	for layer: Sprite2D in _layers:layer.reparent(facing_root,false)
	for animation: Dictionary in _animations.values():
		for frame: Dictionary in animation["frames"]:
			for layer: Dictionary in frame["layers"]:
				var path: String = layer["texture"]
				if not _textures.has(path):
					_textures[path] = load(path)
	if controllable:
		jump_motion.configure(JSON.parse_string(FileAccess.get_file_as_string(motion_data)),
			_animations["jump"]["frames"],_animations["jumpattack"]["frames"])
		action_audio=preload("res://scripts/source_actor_audio.gd").new()
		action_audio.name="ActionAudio"
		add_child(action_audio)
		action_audio.setup(self)
		action_effects=preload("res://scripts/source_actor_effects.gd").new()
		action_effects.setup(self,false)
	play(initial_animation)
	if controllable:
		motion_smoothing=preload("res://scripts/source_motion_smoothing.gd").new()
		motion_smoothing.setup(self)
		walk_inbetweens=preload("res://scripts/source_walk_inbetweens.gd").new()
		walk_inbetweens.setup(self,false)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not controllable or paused:
		return
	if jump_motion.is_active():
		_tick_jump(delta,not ui_input_blocked)
	elif not preview_mode and not _one_shot and not ui_input_blocked:
		_move(delta)


func _process(delta: float) -> void:
	if not paused and not jump_motion.is_active():
		if _one_shot and action_audio:
			action_audio.advance(delta)
		elapsed_ms += delta * 1000.0
		while elapsed_ms >= current_frame()["duration_ms"]:
			elapsed_ms -= current_frame()["duration_ms"]
			_advance_frame()
	_update_visual()
	queue_redraw()


func _update_visual() -> void:
	facing_root.scale.x=facing
	var target:=Vector2(0.0,-jump_motion.height_pixels)
	if visual.position!=target:visual.position=target
	if action_effects:
		action_effects.sync()


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
	_update_visual()
	return true


func _tick_jump(delta: float,allow_input: bool=true) -> void:
	if action_audio:
		action_audio.advance(delta)
	jump_motion.advance(delta)
	if not jump_motion.is_active():
		action_audio.finish()
		play("stay",true)
		_update_visual()
		return
	var direction: Vector2=Input.get_vector("move_left","move_right","move_up","move_down") if allow_input else Vector2.ZERO
	if jump_motion.phase=="landing":
		direction=Vector2.ZERO
	if absf(direction.x)>.01:
		facing=1 if direction.x>0.0 else -1
	if direction.length_squared()>.01:
		var target: Vector2=position+Vector2(direction.x,direction.y*.58)*jump_motion.travel_speed*delta
		position=preload("res://scripts/demo_walk_area.gd").constrain(position,target)
	_apply_jump_pose()
	_update_visual()


func _apply_jump_pose() -> void:
	var pose: Dictionary=jump_motion.pose()
	if animation_name!=pose["action"]:
		play(pose["action"],true)
	frame_index=pose["frame"]
	elapsed_ms=pose["elapsed_ms"]
	_apply_frame()


func _move(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction.x != 0.0:
		facing = 1 if direction.x > 0.0 else -1
	if direction.length_squared() < 0.01:
		play("stay")
		return
	var running := Input.is_action_pressed("run")
	var speed := 190.0 if running else 100.0
	var target := position + Vector2(direction.x, direction.y * 0.58) * speed * delta
	position = preload("res://scripts/demo_walk_area.gd").constrain(position,target)
	play("dash" if running else "move")


func play(action: String, restart: bool = false) -> void:
	if not _animations.has(action):
		return
	if action == animation_name and not restart:
		return
	animation_name = action
	frame_index = 0
	elapsed_ms = 0.0
	_apply_frame()


func preview(action: String) -> void:
	if action_audio:
		action_audio.stop()
	jump_motion.reset()
	preview_mode = true
	_one_shot = false
	play(action, true)
	_update_visual()
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
	if _one_shot or paused or ui_input_blocked:
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
	_update_visual()


func reset_position() -> void:
	jump_motion.reset()
	position = Vector2(440, 320)
	facing = 1
	next_attack = "attack1"
	paused = false
	free_control()
	_update_visual()
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


func _advance_frame() -> void:
	frame_index += 1
	frame_transitions += 1
	if frame_index >= _animations[animation_name]["frames"].size():
		if _one_shot:
			if action_audio:
				action_audio.finish()
			completed_actions += 1
			_one_shot = false
			play("stay", true)
			return
		frame_index = 0
	_apply_frame()


func current_frame() -> Dictionary:
	return _animations[animation_name]["frames"][frame_index]


func _apply_frame() -> void:
	var layers: Array = current_frame()["layers"]
	for i in _layers.size():
		var layer: Dictionary = layers[i]
		_layers[i].texture = _textures[layer["texture"]]
		_layers[i].position = Vector2(layer["offset"][0], layer["offset"][1])
	if action_effects:
		action_effects.sync()


func _draw() -> void:
	# Temporary contact shadow, kept apart from the source image.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.28))
	var ratio: float=jump_motion.height_ratio()
	var radius: float=(22.0 if controllable else 17.0)*lerpf(1.0,.7,ratio)
	draw_circle(Vector2.ZERO,radius,Color(0.12,0.14,0.18,lerpf(.27,.12,ratio)))
	draw_set_transform(Vector2.ZERO)
	if markers_visible:
		draw_line(Vector2(-28, 0), Vector2(28, 0), Color(0.1, 0.9, 1.0, 0.8))
		draw_line(Vector2(0, -7), Vector2(0, 7), Color(0.1, 0.9, 1.0, 0.8))
		draw_circle(Vector2.ZERO, 2.0, Color.WHITE)


func capture_state() -> Dictionary:
	return {"position":position, "facing":facing, "action":animation_name,
		"frame":frame_index, "elapsed_ms":elapsed_ms, "paused":paused,
		"preview":preview_mode, "one_shot":_one_shot,"next_attack":next_attack,
		"jump":jump_motion.capture_state(),
		"audio":action_audio.capture_state() if action_audio else {}}


func restore_state(state: Dictionary) -> void:
	position = state["position"]
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
	_update_visual()
	if motion_smoothing:motion_smoothing.reset()
