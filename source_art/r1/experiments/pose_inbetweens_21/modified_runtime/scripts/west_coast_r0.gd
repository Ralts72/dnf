extends Node2D

const SourceActor = preload("res://scripts/source_actor.gd")

const PreviewControls=preload("res://scripts/source_preview_controls.gd")
const ACTIONS = PreviewControls.HOTKEY_ACTIONS
const ACTION_NAMES = PreviewControls.ACTION_NAMES
var preview_controls=PreviewControls.new()

@onready var player: SourceActor = $PortClip/World/Actors/Swordman
@onready var status: Label = $Interface/Status
@onready var inspector: Label = $Interface/Inspector
@onready var npc_lo: SourceActor = $PortClip/World/Actors/Lorian
@onready var npc_sr: SourceActor = $PortClip/World/Actors/Sharan
@onready var props: Node2D = $PortClip/World/PortProps


func _enter_tree() -> void:
	physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	preload("res://scripts/demo_input.gd").ensure_bindings()


func _ready() -> void:
	$Interface/Buttons/Free.pressed.connect(player.free_control)
	for i in ACTIONS.size():
		get_node("Interface/Buttons/Action" + str(i)).pressed.connect(player.preview.bind(ACTIONS[i]))
	$Interface/Buttons/Pause.pressed.connect(_toggle_pause)
	$Interface/Buttons/Step.pressed.connect(_step_frame)
	$Interface/Buttons/Markers.pressed.connect(_toggle_markers)
	$Interface/Compare.pressed.connect(_switch_comparison)
	preview_controls.setup(self,player)
	if get_tree().has_meta("port_compare_state"):
		player.restore_state(get_tree().get_meta("port_compare_state"))
		_set_paused(player.paused)


func _process(_delta: float) -> void:
	preview_controls.sync()
	var frame: Dictionary = player.current_frame()
	var mode_text := "循环预览" if player.preview_mode else "自由操作"
	if player.paused:
		mode_text = "已暂停"
	elif player.jump_motion.is_active():
		mode_text={"takeoff":"起跳","rising":"上升","falling":"下降","landing":"落地"}[player.jump_motion.phase]
	var action_label: String=ACTION_NAMES[player.animation_name]
	if player.jump_motion.is_active():
		action_label="空中攻击" if player.animation_name=="jumpattack" else "跳跃"
	status.text = "%s  ·  %s" % [mode_text, action_label]
	inspector.text = "ANI %02d  /  IMG %03d  /  %d ms\n脚底  %.0f, %.0f  ·  朝向 %s" % [
		player.frame_index, frame["img_frame"], frame["duration_ms"],
		player.position.x, player.position.y, "右" if player.facing > 0 else "左"]
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
	for actor in [player, npc_lo, npc_sr]:
		actor.paused = value
	for prop in props.get_children():
		if prop.get_script():
			prop.paused = value
	$Interface/Buttons/Pause.text = "继续 F2" if value else "暂停 F2"


func _step_frame() -> void:
	_set_paused(true)
	player.step_frame()


func _toggle_markers() -> void:
	var visible_now: bool = not player.markers_visible
	for actor in [player, npc_lo, npc_sr]:
		actor.markers_visible = visible_now
	inspector.visible = visible_now


func _switch_comparison() -> void:
	get_tree().set_meta("port_compare_state", player.capture_state())
	get_tree().change_scene_to_file("res://scenes/west_coast_r1.tscn")
