extends RefCounted
## Shared pose inspection UI for the independently rendered R0 and R1 actors.

const HOTKEY_ACTIONS := ["stay","move","dash","attack1","attack2","hopsmash"]
const EXTRA_ACTIONS := ["attack3","jump","jumpattack","sit","damage1","damage2","down","guard"]
const ACTION_NAMES := {"stay":"待机","move":"行走","dash":"奔跑",
	"attack1":"普攻一","attack2":"普攻二","hopsmash":"崩山击动作",
	"attack3":"普攻三","jump":"跳跃姿势","jumpattack":"空中攻击姿势",
	"sit":"蹲下姿势","damage1":"受击一姿势","damage2":"受击二姿势",
	"down":"倒地姿势","guard":"防御姿势"}

var scene: Node
var actor: Node
var menu: OptionButton
var slider: HSlider
var frame_label: Label
var audio_menu: OptionButton
var music_menu: OptionButton
var music: Node
var effects_toggle: CheckButton
var motion_toggle: CheckButton
var pose_toggle: CheckButton
const AUDIO_LEVELS: Array[float]=[0.0,.3,.6,1.0]


func setup(root: Node,source_actor: Node) -> void:
	scene=root
	actor=source_actor
	menu=root.get_node("Interface/MoreActions")
	slider=root.get_node("Interface/FrameSlider")
	frame_label=root.get_node("Interface/FrameLabel")
	audio_menu=root.get_node("Interface/AudioMenu")
	music_menu=root.get_node("Interface/MusicMenu")
	music=root.get_tree().root.get_node("PortMusic")
	effects_toggle=root.get_node("Interface/EffectsToggle")
	effects_toggle.button_pressed=actor.action_effects.enabled
	effects_toggle.toggled.connect(_select_effects)
	motion_toggle=root.get_node("Interface/MotionToggle")
	motion_toggle.button_pressed=actor.motion_smoothing.enabled
	motion_toggle.toggled.connect(_select_motion_smoothing)
	pose_toggle=root.get_node("Interface/PoseToggle")
	pose_toggle.button_pressed=actor.pose_inbetweens.enabled
	pose_toggle.toggled.connect(_select_pose_inbetweens)
	for level: float in music.volume_levels:
		music_menu.add_item("音乐静音 F9" if level==0 else "音乐 %d%% F9"%roundi(level*100))
	music_menu.item_selected.connect(_select_music)
	music_menu.get_popup().about_to_popup.connect(_popup_opened)
	music_menu.get_popup().popup_hide.connect(_popup_closed)
	for label: String in ["音效静音 F8","音效 30% F8","音效 60% F8","音效 100% F8"]:
		audio_menu.add_item(label)
	audio_menu.item_selected.connect(_select_audio)
	audio_menu.get_popup().about_to_popup.connect(_popup_opened)
	audio_menu.get_popup().popup_hide.connect(_popup_closed)
	menu.add_item("更多姿势…")
	menu.set_item_disabled(0,true)
	for action: String in EXTRA_ACTIONS:
		menu.add_item(ACTION_NAMES[action])
	menu.select(0)
	menu.item_selected.connect(_select_action)
	menu.get_popup().about_to_popup.connect(_popup_opened)
	menu.get_popup().popup_hide.connect(_popup_closed)
	slider.value_changed.connect(_scrub)
	slider.drag_started.connect(_begin_scrub)
	root.get_node("Interface/Buttons/Facing").pressed.connect(turn_around)
	root.get_node("Interface/Buttons/Jump").pressed.connect(actor.start_jump)
	sync()


func _select_action(index: int) -> void:
	if index>0:
		actor.preview(EXTRA_ACTIONS[index-1])
		sync()


func turn_around() -> void:
	actor.turn_around()
	sync()


func _popup_opened() -> void:
	actor.ui_input_blocked=true
	if not actor.preview_mode and not actor._one_shot and not actor.jump_motion.is_active():
		actor.play("stay")


func _popup_closed() -> void:
	if is_instance_valid(actor):
		actor.ui_input_blocked=false


func _begin_scrub() -> void:
	scene._set_paused(true)


func _scrub(value: float) -> void:
	scene._set_paused(true)
	actor.action_audio.stop()
	actor.frame_index=int(value)
	actor.elapsed_ms=0.0
	actor._apply_frame()
	sync()


func sync() -> void:
	var tree:=scene.get_tree()
	var level: float=0.0 if tree.get_meta("port_audio_muted",false) else float(tree.get_meta("port_audio_volume",.6))
	audio_menu.select(AUDIO_LEVELS.find(level))
	var music_level: float=0.0 if music.muted else music.volume
	music_menu.select(music.volume_levels.find(music_level))
	var frames: Array=actor._animations[actor.animation_name]["frames"]
	var menu_index: int=EXTRA_ACTIONS.find(actor.animation_name)+1
	if menu.selected!=menu_index:
		menu.select(menu_index)
	# Changing max_value can clamp the slider and emit a value_changed signal.
	# Block that update so selecting another clip never pauses it accidentally.
	slider.set_block_signals(true)
	slider.max_value=frames.size()-1
	slider.value=actor.frame_index
	slider.editable=frames.size()>1
	slider.set_block_signals(false)
	slider.visible=actor.markers_visible
	frame_label.visible=actor.markers_visible
	var frame: Dictionary=actor.current_frame()
	var properties: Array=[]
	for item: Dictionary in frame.get("source_properties",[]):
		if item["type"]!=12:
			properties.append("%d=%s"%[item["type"],str(item["value"])])
	frame_label.text="帧 %d / %d · %d ms"%[actor.frame_index+1,frames.size(),frame["duration_ms"]]
	if actor.pose_inbetweens.active:
		frame_label.text+=" · 中间 %d/3"%roundi(actor.pose_inbetweens.phase*3.0)
	if not properties.is_empty():
		frame_label.text+=" · 属性 "+", ".join(properties)
	slider.tooltip_text="拖动会暂停并定位。原始帧时长 %d ms；F3 推进跳跃 1/60 秒或原图一帧，F2 继续。"%frame["duration_ms"]


func _select_audio(index: int) -> void:
	var tree:=scene.get_tree()
	tree.set_meta("port_audio_muted",index==0)
	if index>0:
		tree.set_meta("port_audio_volume",AUDIO_LEVELS[index])
	actor.action_audio.apply_preferences()
	sync()


func toggle_audio() -> void:
	var tree:=scene.get_tree()
	tree.set_meta("port_audio_muted",not tree.get_meta("port_audio_muted",false))
	actor.action_audio.apply_preferences()
	sync()


func _select_music(index: int) -> void:
	music.select_volume(float(music.volume_levels[index]))
	sync()


func toggle_music() -> void:
	music.toggle_muted()
	sync()


func _select_effects(value: bool) -> void:
	scene.get_tree().set_meta("port_fx_enabled",value)
	actor.action_effects.enabled=value
	actor.action_effects.sync()
	effects_toggle.set_pressed_no_signal(value)


func toggle_effects() -> void:
	_select_effects(not actor.action_effects.enabled)


func _select_motion_smoothing(value: bool) -> void:
	actor.motion_smoothing.set_enabled(value)
	motion_toggle.set_pressed_no_signal(value)


func toggle_motion_smoothing() -> void:
	_select_motion_smoothing(not actor.motion_smoothing.enabled)


func _select_pose_inbetweens(value: bool) -> void:
	actor.pose_inbetweens.set_enabled(value)
	pose_toggle.set_pressed_no_signal(value)


func toggle_pose_inbetweens() -> void:
	_select_pose_inbetweens(not actor.pose_inbetweens.enabled)
