extends Node2D

const SourceActor = preload("res://scripts/source_actor_3d.gd")
const HarborWater = preload("res://scripts/harbor_water.gd")
const BASE_RENDER_SIZE: Vector2i = Vector2i(896,404)
const PreviewControls=preload("res://scripts/source_preview_controls.gd")
const ACTIONS = PreviewControls.HOTKEY_ACTIONS
const ACTION_NAMES = PreviewControls.ACTION_NAMES
var preview_controls=PreviewControls.new()

@onready var world: Node3D = $PortClip/ViewportContainer/Viewport/World
@onready var player: SourceActor = $PortClip/ViewportContainer/Viewport/World/Actors/Swordman
@onready var water: HarborWater = $PortClip/ViewportContainer/Viewport/World/Water
@onready var npc_lo: SourceActor = $PortClip/ViewportContainer/Viewport/World/Actors/Lorian
@onready var npc_sr: SourceActor = $PortClip/ViewportContainer/Viewport/World/Actors/Sharan
@onready var status: Label = $Interface/Status
@onready var inspector: Label = $Interface/Inspector
@onready var render_viewport: SubViewport = $PortClip/ViewportContainer/Viewport
@onready var render_surface: TextureRect = $PortClip/ViewportContainer
var render_scale: int = 2


func _enter_tree() -> void:
	physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	preload("res://scripts/demo_input.gd").ensure_bindings()


func _ready() -> void:
	render_surface.texture = render_viewport.get_texture()
	set_render_scale(int(get_tree().get_meta("port_render_scale",2)))
	$Interface/Buttons/Free.pressed.connect(player.free_control)
	for i in ACTIONS.size():
		get_node("Interface/Buttons/Action" + str(i)).pressed.connect(player.preview.bind(ACTIONS[i]))
	$Interface/Buttons/Pause.pressed.connect(_toggle_pause)
	$Interface/Buttons/Step.pressed.connect(_step_frame)
	$Interface/Buttons/Markers.pressed.connect(_toggle_markers)
	$Interface/Compare.pressed.connect(_switch_comparison)
	$Interface/Quality.pressed.connect(_toggle_quality)
	preview_controls.setup(self,player)
	_set_probe_visible(false)
	if get_tree().has_meta("port_water_state"):
		water.restore_state(get_tree().get_meta("port_water_state"))
	if get_tree().has_meta("port_compare_state"):
		player.restore_state(get_tree().get_meta("port_compare_state"))
	_set_paused(player.paused)


func _process(_delta: float) -> void:
	preview_controls.sync()
	var frame: Dictionary = player.current_frame()
	var mode := "循环预览" if player.preview_mode else "自由操作"
	if player.paused:
		mode = "已暂停"
	elif player.jump_motion.is_active():
		mode={"takeoff":"起跳","rising":"上升","falling":"下降","landing":"落地"}[player.jump_motion.phase]
	var action_label: String=ACTION_NAMES[player.animation_name]
	if player.jump_motion.is_active():
		action_label="空中攻击" if player.animation_name=="jumpattack" else "跳跃"
	status.text = "%s  ·  %s" % [mode, action_label]
	inspector.text = "ANI %02d  /  IMG %03d  /  %d ms\n地面  %.2f, %.2f  ·  朝向 %s\n渲染 %d×%d  ·  %d FPS" % [
		player.frame_index, frame["img_frame"], frame["duration_ms"],
		player.position.x, player.position.z, "右" if player.facing > 0 else "左",
		render_viewport.size.x,render_viewport.size.y,int(Engine.get_frames_per_second())]
	inspector.text+="\n离地 %.1f px · %s"%[player.jump_motion.height_pixels,player.jump_motion.phase]


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if player.ui_input_blocked:
		return
	if event.is_action_pressed("attack"):
		player.attack()
	elif event.is_action_pressed("jump"):
		player.start_jump()
	elif event.is_action_pressed("skill_preview"):
		player.perform("hopsmash")
	elif event.is_action_pressed("reset"):
		player.reset_position()
		_set_paused(false)
	elif event.keycode == KEY_F1:
		_toggle_markers()
	elif event.keycode == KEY_F2:
		_toggle_pause()
	elif event.keycode == KEY_F3:
		_step_frame()
	elif event.keycode == KEY_F4:
		_switch_comparison()
	elif event.keycode == KEY_F6:
		_toggle_quality()
	elif event.keycode == KEY_F7:
		preview_controls.turn_around()
	elif event.keycode == KEY_F8:
		preview_controls.toggle_audio()
	elif event.keycode == KEY_F9:
		preview_controls.toggle_music()
	elif event.keycode == KEY_F10:
		preview_controls.toggle_effects()
	elif event.keycode == KEY_F11:
		preview_controls.toggle_motion_smoothing()
	elif event.keycode == KEY_F12:
		preview_controls.toggle_pose_inbetweens()
	elif event.keycode == KEY_TAB:
		$Interface.visible = not $Interface.visible
	elif event.keycode == KEY_ESCAPE:
		player.free_control()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_6:
		player.preview(ACTIONS[event.keycode - KEY_1])


func _toggle_pause() -> void:
	_set_paused(not player.paused)


func _set_paused(value: bool) -> void:
	for actor in [player,npc_lo,npc_sr]:
		actor.paused = value
	for prop in world.get_node("SourceProps").get_children():
		prop.paused = value
	water.paused=value
	$Interface/Buttons/Pause.text = "继续 F2" if value else "暂停 F2"


func _step_frame() -> void:
	_set_paused(true)
	player.step_frame()


func _toggle_markers() -> void:
	var enabled: bool = not player.markers_visible
	for actor in [player,npc_lo,npc_sr]:
		actor.markers_visible = enabled
	inspector.visible = enabled
	_set_probe_visible(enabled)


func _set_probe_visible(enabled: bool) -> void:
	for probe in world.get_node("PortArchitecture").find_children("Occlusion_Stone*", "MeshInstance3D", true, false):
		probe.visible = enabled
	world.get_node("StoneCollision/Shape").set_deferred("disabled", not enabled)


func _switch_comparison() -> void:
	get_tree().set_meta("port_compare_state", player.capture_state())
	get_tree().set_meta("port_water_state",water.capture_state())
	get_tree().change_scene_to_file("res://scenes/west_coast_r0.tscn")


func set_render_scale(value: int) -> void:
	render_scale = clampi(value,1,2)
	render_viewport.size = BASE_RENDER_SIZE * render_scale
	get_tree().set_meta("port_render_scale",render_scale)
	$Interface/Quality.text = "清晰 F6" if render_scale==2 else "轻量 F6"
	$Interface/Quality.tooltip_text = "提高光影和几何边缘的渲染分辨率，保留人物原始像素采样" if render_scale==2 else "降低渲染负载，镜头、角色比例与动作不变"


func _toggle_quality() -> void:
	set_render_scale(1 if render_scale==2 else 2)
