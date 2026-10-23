extends Node
## Harbor-only adapted conversation and free transient route-health restoration.

const SCENE: String = "res://scenes/west_coast_r1.tscn"
const DATA_PATH: String = "res://data/sharan_dialogue.json"
const MAX_HP: int = 100
var main: Node
var data: Dictionary = {}
var _open: bool = false
var _owns_lock: bool = false
var _prompt: Label
var _layer: CanvasLayer
var _body: Label
var _health: Label
var _confirm: Button
var _portrait: TextureRect
var _menus: Array[Node] = []
var restore_count: int = 0


static func ensure(area: Node) -> Node:
	if area == null or area.scene_file_path != SCENE:
		return null
	var existing: Node = area.get_node_or_null("SharanInteraction")
	if existing != null:
		return existing
	var controller: Node = (load("res://scripts/sharan_interaction.gd") as Script).new()
	controller.name = "SharanInteraction"
	controller.main = area
	area.add_child(controller)
	controller._setup()
	return controller


func _setup() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 900
	process_physics_priority = -940
	_menus = get_tree().root.find_children("*", "PopupMenu", true, false)
	var theme: Theme = main.get_node("Interface/Title").theme
	_prompt = _label(theme, 12)
	_prompt.name = "SharanPrompt"
	_prompt.text = str(data.prompt)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.size = Vector2(220, 24)
	main.get_node("PortClip").add_child(_prompt)
	_build_dialog(theme)
	_refresh()


func _eligible() -> bool:
	return is_inside_tree() and is_instance_valid(main) and main.is_inside_tree() and main.scene_file_path == SCENE and get_tree().current_scene == main and is_instance_valid(main.get("player")) and is_instance_valid(main.get("npc_sr"))


func _travel_ready() -> bool:
	var travel: Node = main.get_node_or_null("WorldTravel") if is_instance_valid(main) else null
	return travel == null or travel.is_ready()


func _other_modal() -> bool:
	if get_tree() == null:
		return false
	var progress: Node = get_tree().root.get_node_or_null("AdventureProgress")
	var loot: Node = main.get_node_or_null("FirstLoot") if is_instance_valid(main) else null
	if (progress != null and bool(progress.get("_dialog_open"))) or (loot != null and bool(loot.get("_bag_open"))):
		return true
	for menu: Node in _menus:
		if is_instance_valid(menu) and menu.visible:
			return true
	return false


func npc_point() -> Vector2:
	return main.npc_sr.world_to_source(main.npc_sr.position) if _eligible() else Vector2.ZERO


func can_interact() -> bool:
	if _open or not _eligible() or get_tree().paused or not _travel_ready() or _other_modal():
		return false
	var player: Node = main.player
	if player.paused or player.preview_mode or player.markers_visible or player.ui_input_blocked or player._one_shot or player.jump_motion.is_active() or absf(player.height_above_ground) > 0.0001:
		return false
	var delta: Vector2 = player.world_to_source(player.position) - npc_point()
	var half: Array = data.get("interaction_half_extent", [55, 50])
	return absf(delta.x) <= float(half[0]) and absf(delta.y) <= float(half[1])


func _input(event: InputEvent) -> void:
	if _open:
		if event is InputEventKey:
			if event.pressed and not event.echo:
				if event.keycode in [KEY_E, KEY_ESCAPE]:
					close_dialog()
				elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
					confirm_restore()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and open_dialog():
		get_viewport().set_input_as_handled()


func open_dialog() -> bool:
	if not can_interact():
		return false
	_open = true
	_owns_lock = true
	main.player.ui_input_blocked = true
	main.player.velocity = Vector3.ZERO
	main.player.play("stay")
	_layer.visible = true
	main.get_viewport().gui_release_focus()
	_refresh()
	_confirm.grab_focus()
	return true


func close_dialog() -> void:
	if not _open:
		return
	_open = false
	if is_instance_valid(_layer):
		_layer.visible = false
	if _owns_lock and is_instance_valid(main) and is_instance_valid(main.get("player")) and _travel_ready() and not _other_modal():
		main.player.ui_input_blocked = false
	_owns_lock = false
	var viewport: Viewport = get_viewport()
	var focus: Control = viewport.gui_get_focus_owner() if viewport != null else null
	if focus != null and is_instance_valid(_layer) and _layer.is_ancestor_of(focus):
		focus.release_focus()
	_refresh()


func route_hp() -> int:
	var value: Variant = get_tree().get_meta("route_hero_hp", MAX_HP)
	return clampi(int(value), 0, MAX_HP) if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) else MAX_HP


func _restore_existing_sessions() -> void:
	# No profile API is called. Deep copies change only the hero-health field;
	# enemy health, completion, counters and any authored positions survive.
	get_tree().set_meta("route_hero_hp", MAX_HP)
	for key: String in ["first_encounter_state", "tower_boss_state", "doll_gallery_state", "statue_gallery_state"]:
		if not get_tree().has_meta(key):
			continue
		var current: Variant = get_tree().get_meta(key)
		if current is Dictionary:
			var restored: Dictionary = current.duplicate(true)
			restored["player_hp"] = MAX_HP
			get_tree().set_meta(key, restored)


func confirm_restore() -> bool:
	if not _open or not _eligible() or not _travel_ready() or _other_modal():
		return false
	var player: Node = main.player
	if get_tree().paused or player.paused or player.preview_mode or player.markers_visible or player._one_shot or player.jump_motion.is_active() or absf(player.height_above_ground) > 0.0001:
		return false
	if route_hp() < MAX_HP:
		_restore_existing_sessions()
		restore_count += 1
	close_dialog()
	return true


func _process(_delta: float) -> void:
	if _open and not _eligible():
		close_dialog()
	if _open and _eligible():
		main.player.ui_input_blocked = true
	_refresh()


func _physics_process(_delta: float) -> void:
	if _open and _eligible():
		main.player.ui_input_blocked = true
		main.player.velocity = Vector3.ZERO


func dialogue_key() -> String:
	var profile: Node = get_tree().root.get_node_or_null("AdventureProgress")
	var progress: Dictionary = profile.get("progress") if profile != null else {}
	var flags_value: Variant = progress.get("chapter_flags", {})
	var flags: Dictionary = flags_value if flags_value is Dictionary else {}
	var historical_statue: Variant = flags.get("statue_cleared", false)
	if (historical_statue is bool and historical_statue) or _session_cleared("statue_gallery_state"):
		return "statue_cleared"
	var historical_stonemaster: Variant = flags.get("stonemaster_cleared", false)
	if (historical_stonemaster is bool and historical_stonemaster) or _session_cleared("doll_gallery_state"):
		return "stonemaster_cleared"
	var historical_boss: Variant = flags.get("lakius_cleared", false)
	if (historical_boss is bool and historical_boss) or _session_cleared("tower_boss_state"):
		return "lakius_cleared"
	if str(progress.get("first_drop", {}).get("state", "unearned")) in ["pending", "claimed"] or _session_cleared("first_encounter_state"):
		return "first_clear"
	return "available" if progress.get("quest_stage", "available") == "available" else "exploring"


func _session_cleared(key: String) -> bool:
	var state: Variant = get_tree().get_meta(key, {})
	return state is Dictionary and state.get("cleared") is bool and state.cleared


func _refresh() -> void:
	if not is_instance_valid(_prompt):
		return
	var eligible: bool = _eligible()
	_prompt.visible = eligible and can_interact() and main.get_node("Interface").visible
	if eligible:
		_prompt.position = npc_point() + Vector2(-110, 43.0 - main.npc_sr._foot_anchor.y - 25.0) - Vector2(main.framing.offset_x, main.framing.offset_y)
	if _open:
		_body.text = str(data.dialogues[dialogue_key()])
		_health.text = "生命  %d / %d" % [route_hp(), MAX_HP]
		_confirm.text = str(data.confirm_full if route_hp() == MAX_HP else data.confirm_heal)


func _label(theme: Theme, size: int) -> Label:
	var label := Label.new()
	label.theme = theme
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.035, 0.95))
	label.add_theme_constant_override("outline_size", 2)
	return label


func _build_dialog(theme: Theme) -> void:
	_layer = CanvasLayer.new()
	_layer.name = "SharanDialog"
	_layer.layer = 111
	_layer.visible = false
	add_child(_layer)
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(shade)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme = theme
	panel.position = Vector2(240, 138)
	panel.custom_minimum_size = Vector2(480, 264)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.055, 0.08, 0.11, 0.97)
	frame.border_color = Color(0.64, 0.50, 0.29, 0.95)
	frame.set_border_width_all(1)
	frame.set_content_margin_all(18.0)
	panel.add_theme_stylebox_override("panel", frame)
	shade.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var heading: Label = _label(theme, 16)
	heading.name = "Heading"
	heading.text = str(data.npc_name) + " · " + str(data.title)
	heading.add_theme_color_override("font_color", Color(0.95, 0.85, 0.63))
	column.add_child(heading)
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	column.add_child(content)
	var portrait_path: String = str(data.get("portrait_path", ""))
	if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path, "Texture2D"):
		_portrait = TextureRect.new()
		_portrait.name = "Portrait"
		_portrait.texture = load(portrait_path)
		_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		_portrait.custom_minimum_size = _portrait.texture.get_size()
		_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(_portrait)
	_body = _label(theme, 14)
	_body.name = "Body"
	_body.custom_minimum_size = Vector2(340, 100)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_body)
	_health = _label(theme, 13)
	_health.name = "Health"
	column.add_child(_health)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_confirm = Button.new()
	_confirm.name = "Confirm"
	_confirm.pressed.connect(confirm_restore)
	buttons.add_child(_confirm)
	var close := Button.new()
	close.name = "Close"
	close.text = str(data.close)
	close.pressed.connect(close_dialog)
	buttons.add_child(close)
	var shortcuts: Label = _label(theme, 11)
	shortcuts.text = "Enter 确认  ·  E / Esc 关闭"
	shortcuts.modulate = Color(0.76, 0.79, 0.80)
	column.add_child(shortcuts)


func capture_state() -> Dictionary:
	return {"dialog_open": _open, "can_interact": can_interact(), "dialogue_key": dialogue_key(),
		"route_hp": route_hp(), "restore_count": restore_count, "npc_source_position": npc_point(),
		"interaction_half_extent": data.get("interaction_half_extent", [55, 50]),
		"prompt_visible": is_instance_valid(_prompt) and _prompt.is_visible_in_tree(),
		"dialogue_text": _body.text if is_instance_valid(_body) else "",
		"confirm_text": _confirm.text if is_instance_valid(_confirm) else "",
		"portrait_path": _portrait.texture.resource_path if is_instance_valid(_portrait) and _portrait.texture != null else "",
		"portrait_visible": is_instance_valid(_portrait) and _portrait.is_visible_in_tree()}


func _exit_tree() -> void:
	close_dialog()
	if is_instance_valid(_prompt):
		_prompt.queue_free()
