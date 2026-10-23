extends Node
## An adapted, independent prototype profile; never reads the client's saves.

const DATA_PATH: String = "res://data/first_route_quest.json"
const DEFAULT_STORAGE: String = "user://adventure/first_route_v1.json"
const STAGES: Array[String] = ["available", "active", "return", "completed"]
var main: Node
var data: Dictionary = {}
var progress: Dictionary = {"schema": 1, "quest_stage": "available", "reward_granted": false, "coins": 0}
var storage_path: String = DEFAULT_STORAGE
var last_error: String = ""
var loaded_from_backup: bool = false
var _storage_ready: bool = true
var _clear_seen: bool = false
var _save_attempts: int = 0
var _dialog_open: bool = false
var _hud: Label
var _prompt: Label
var _layer: CanvasLayer
var _body: Label
var _confirm: Button
var _close: Button


static func ensure(area: Node) -> Node:
	var controller: Node = area.get_tree().root.get_node_or_null("AdventureProgress")
	if controller == null:
		controller = (load("res://scripts/adventure_progress.gd") as Script).new()
		controller.name = "AdventureProgress"
		area.get_tree().root.add_child(controller)
		controller.call("_initialize")
	controller.call("attach_area", area)
	return controller


func _initialize() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 900
	process_physics_priority = -900
	load_progress()


func configure_storage(path: String, load_existing: bool = true) -> bool:
	if path != DEFAULT_STORAGE and not (path.begins_with("user://qa/") and not path.contains("..")):
		return _error("无法使用这个存档位置。")
	close_dialog()
	storage_path = path
	progress = {"schema": 1, "quest_stage": "available", "reward_granted": false, "coins": 0}
	last_error = ""
	loaded_from_backup = false
	_storage_ready = true
	_clear_seen = false
	_save_attempts = 0
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return load_progress() if load_existing else true


func attach_area(area: Node) -> void:
	close_dialog()
	for owned: Node in [_hud, _prompt, _layer]:
		if is_instance_valid(owned):
			owned.queue_free()
	main = area
	_hud = null
	_prompt = null
	_layer = null
	if not _is_region_scene():
		return
	var title: Label = main.get_node("Interface/Title")
	_hud = Label.new()
	_hud.name = "QuestObjective"
	_hud.theme = title.theme
	_hud.position = Vector2(566, 44 if main.scene_file_path == "res://scenes/tower_hall.tscn" else 8)
	_hud.size = Vector2(318, 48)
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_theme_font_size_override("font_size", 12)
	_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	main.get_node("PortClip").add_child(_hud)
	_prompt = Label.new()
	_prompt.name = "LorianInteractHint"
	_prompt.theme = title.theme
	_prompt.text = "E  与萝莉安交谈"
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_font_size_override("font_size", 12)
	main.get_node("PortClip").add_child(_prompt)
	_build_dialog(title.theme)
	_refresh_ui()


func _process(_delta: float) -> void:
	if _dialog_open and (not is_instance_valid(main) or get_tree().current_scene != main):
		close_dialog()
	if progress.quest_stage == "active" and _encounter_cleared() and not _clear_seen:
		_clear_seen = true
		var next: Dictionary = progress.duplicate(true)
		next.quest_stage = "return"
		_commit(next)
	if _dialog_open and is_instance_valid(main):
		main.player.ui_input_blocked = true
	_refresh_ui()


func _physics_process(_delta: float) -> void:
	if _dialog_open and is_instance_valid(main):
		main.player.ui_input_blocked = true
		main.player.velocity = Vector3.ZERO


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if _dialog_open:
		if event.keycode in [KEY_E, KEY_ESCAPE]:
			close_dialog()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			if is_instance_valid(_confirm) and _confirm.visible:
				_confirm_dialog()
			else:
				close_dialog()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_E and can_interact():
		open_dialog()
		get_viewport().set_input_as_handled()


func can_interact() -> bool:
	if not _eligible_area() or main.scene_file_path != "res://scenes/west_coast_r1.tscn" or _dialog_open:
		return false
	var player: Node = main.player
	if player.paused or player.preview_mode or player._one_shot or player.ui_input_blocked or player.jump_motion.is_active():
		return false
	if absf(player.height_above_ground) > 0.0001:
		return false
	var travel: Node = main.get_node_or_null("WorldTravel")
	if travel != null and not bool(travel.is_ready()):
		return false
	for popup: Node in get_tree().root.find_children("*", "PopupMenu", true, false):
		if popup.visible:
			return false
	var point: Vector2 = player.world_to_source(player.position)
	var npc: Array = data.npc_source_position
	var extent: Array = data.interaction_half_extent
	return absf(point.x - float(npc[0])) <= float(extent[0]) and absf(point.y - float(npc[1])) <= float(extent[1])


func open_dialog() -> bool:
	if not can_interact() or not is_instance_valid(_layer):
		return false
	_dialog_open = true
	main.player.ui_input_blocked = true
	main.player.velocity = Vector3.ZERO
	main.player.play("stay")
	_layer.visible = true
	_refresh_ui()
	if _confirm.visible:
		_confirm.grab_focus.call_deferred()
	else:
		_close.grab_focus.call_deferred()
	return true


func close_dialog() -> void:
	if not _dialog_open:
		return
	_dialog_open = false
	if is_instance_valid(_layer):
		_layer.visible = false
	if is_instance_valid(main) and is_instance_valid(main.player):
		var travel: Node = main.get_node_or_null("WorldTravel")
		if travel == null or bool(travel.is_ready()):
			main.player.ui_input_blocked = false
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and is_instance_valid(_layer) and _layer.is_ancestor_of(focus):
		focus.release_focus()


func accept_quest() -> bool:
	if progress.quest_stage != "available":
		return false
	var next: Dictionary = progress.duplicate(true)
	next.quest_stage = "return" if _encounter_cleared() else "active"
	var saved: bool = _commit(next)
	if saved:
		close_dialog()
	return saved


func claim_reward() -> bool:
	if progress.quest_stage != "return" or progress.reward_granted or not _encounter_cleared():
		return false
	var next: Dictionary = progress.duplicate(true)
	next.quest_stage = "completed"
	next.reward_granted = true
	next.coins = int(progress.coins) + int(data.reward_coins)
	var saved: bool = _commit(next)
	if saved:
		close_dialog()
	return saved


func save_progress() -> bool:
	var next: Dictionary = progress.duplicate(true)
	if next.quest_stage == "active" and _encounter_cleared():
		next.quest_stage = "return"
	return _commit(next)


func load_progress() -> bool:
	loaded_from_backup = false
	if not FileAccess.file_exists(storage_path) and not FileAccess.file_exists(storage_path + ".bak"):
		_storage_ready = true
		last_error = ""
		return true
	var loaded: Dictionary = _read_valid(storage_path)
	if loaded.is_empty():
		loaded = _read_valid(storage_path + ".bak")
		loaded_from_backup = not loaded.is_empty()
	if loaded.is_empty():
		_storage_ready = false
		return _error("委托存档无法读取，原文件已保留。")
	progress = loaded
	_storage_ready = true
	last_error = ""
	_clear_seen = progress.quest_stage != "active"
	if progress.quest_stage in ["return", "completed"] and not get_tree().has_meta("first_encounter_state"):
		get_tree().set_meta("first_encounter_state", {"cleared": true})
	return true


func capture_state() -> Dictionary:
	return {"progress": progress.duplicate(true), "storage_path": storage_path, "last_error": last_error,
		"storage_ready": _storage_ready, "loaded_from_backup": loaded_from_backup,
		"save_attempts": _save_attempts,
		"dialog_open": _dialog_open, "encounter_cleared": _encounter_cleared(),
		"region_scene": main.scene_file_path if is_instance_valid(main) else ""}


func _commit(next: Dictionary) -> bool:
	_save_attempts += 1
	if not _storage_ready or not _valid(next):
		return _error("委托进度尚未保存，请先检查存档。")
	var folder: String = ProjectSettings.globalize_path(storage_path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return _error("暂时无法保存委托进度，请稍后重试。")
	var temporary: String = storage_path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _error("暂时无法保存委托进度，请稍后重试。")
	file.store_string(JSON.stringify(next) + "\n")
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or _read_valid(temporary).is_empty():
		return _error("委托进度保存失败，请重试。")
	if FileAccess.file_exists(storage_path):
		var primary_valid: bool = not _read_valid(storage_path).is_empty()
		var copy_target: String = storage_path + ".bak.tmp" if primary_valid else storage_path + ".invalid." + str(Time.get_ticks_usec())
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(storage_path), ProjectSettings.globalize_path(copy_target)) != OK:
			return _error("无法保留旧存档，本次进度尚未保存。")
		if primary_valid and DirAccess.rename_absolute(ProjectSettings.globalize_path(copy_target), ProjectSettings.globalize_path(storage_path + ".bak")) != OK:
			return _error("无法备份委托存档，请重试。")
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(storage_path)) != OK:
		return _error("无法更新委托存档，请重试。")
	progress = next.duplicate(true)
	last_error = ""
	loaded_from_backup = false
	_clear_seen = progress.quest_stage != "active"
	_refresh_ui()
	return true


func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 16384:
		return {}
	var parser: JSON = JSON.new()
	var result: Error = parser.parse(file.get_as_text())
	file.close()
	if result != OK:
		return {}
	var parsed: Variant = parser.data
	return parsed if parsed is Dictionary and _valid(parsed) else {}


func _valid(value: Dictionary) -> bool:
	if typeof(value.get("schema")) not in [TYPE_INT, TYPE_FLOAT] or float(value.schema) != 1.0:
		return false
	if typeof(value.get("quest_stage")) != TYPE_STRING or not value.quest_stage in STAGES:
		return false
	if typeof(value.get("reward_granted")) != TYPE_BOOL or typeof(value.get("coins")) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var granted: bool = value.reward_granted
	return (value.quest_stage == "completed") == granted and float(value.coins) == (float(data.get("reward_coins", 40)) if granted else 0.0)


func _encounter_cleared() -> bool:
	var state: Variant = get_tree().get_meta("first_encounter_state", {})
	return state is Dictionary and typeof(state.get("cleared")) == TYPE_BOOL and state.cleared


func _eligible_area() -> bool:
	return _is_region_scene() and get_tree().current_scene == main


func _is_region_scene() -> bool:
	return is_instance_valid(main) and main.scene_file_path in ["res://scenes/west_coast_r1.tscn", "res://scenes/tower_approach.tscn", "res://scenes/tower_hall.tscn"]


func _error(message: String) -> bool:
	last_error = message
	_refresh_ui()
	return false


func _confirm_dialog() -> void:
	if not last_error.is_empty():
		save_progress()
	elif progress.quest_stage == "available":
		accept_quest()
	elif progress.quest_stage == "return":
		claim_reward()
	_refresh_ui()


func _build_dialog(theme: Theme) -> void:
	_layer = CanvasLayer.new()
	_layer.name = "QuestDialog"
	_layer.layer = 110
	_layer.visible = false
	add_child(_layer)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(shade)
	var panel: PanelContainer = PanelContainer.new()
	panel.theme = theme
	panel.position = Vector2(280, 155)
	panel.custom_minimum_size = Vector2(400, 210)
	shade.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var heading: Label = Label.new()
	heading.text = str(data.npc_name) + " · " + str(data.title)
	column.add_child(heading)
	_body = Label.new()
	_body.custom_minimum_size = Vector2(376, 92)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_body)
	var buttons: HBoxContainer = HBoxContainer.new()
	column.add_child(buttons)
	_confirm = Button.new()
	_confirm.pressed.connect(_confirm_dialog)
	buttons.add_child(_confirm)
	_close = Button.new()
	_close.pressed.connect(close_dialog)
	buttons.add_child(_close)


func _refresh_ui() -> void:
	if data.is_empty():
		return
	var stage: Dictionary = data.stages[progress.quest_stage]
	if is_instance_valid(_hud):
		_hud.visible = _eligible_area() and bool(main.get_node("Interface").get("visible"))
		_hud.text = str(stage.objective)
		if int(progress.coins) > 0:
			_hud.text += " · 金币 " + str(progress.coins)
		if not last_error.is_empty():
			_hud.text += " · 进度未保存"
	if is_instance_valid(_prompt):
		_prompt.visible = can_interact() and bool(main.get_node("Interface").get("visible"))
		if is_instance_valid(main) and main.get("framing") != null:
			_prompt.position = Vector2(230, 219) - Vector2(main.framing.offset_x, main.framing.offset_y)
	if _dialog_open and is_instance_valid(_body):
		_body.text = str(stage.dialog) if last_error.is_empty() else last_error
		_confirm.visible = stage.has("confirm") or not last_error.is_empty()
		_confirm.text = "重试保存" if not last_error.is_empty() else str(stage.get("confirm", ""))
		_close.text = str(stage.close)
