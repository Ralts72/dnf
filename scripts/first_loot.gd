extends Node
## A source-backed material pickup and a small modal bag for the first route.

const VALID_SCENES: Array[String] = ["res://scenes/west_coast_r1.tscn", "res://scenes/tower_approach.tscn", "res://scenes/tower_hall.tscn", "res://scenes/tower_depths.tscn", "res://scenes/tower_doll_gallery.tscn", "res://scenes/tower_statue_gallery.tscn"]
const DATA_PATH: String = "res://data/first_loot_items.json"
var main: Node
var progress: Node
var item: Dictionary
var _bag_open: bool = false
var _drop: Sprite3D
var _hint: Label
var _toast: Label
var _toast_remaining: float = 0.0
var _layer: CanvasLayer
var _count: Label
var _icon: TextureRect
var _description: Label
var _coins: Label
var _equip_button: Button
var _weapon_icon: TextureRect
var _weapon_mark: Label
var equipment_runtime: Node
var equipment_data: Dictionary
var supplies_data: Dictionary
var _potion_icon: TextureRect
var _potion_count: Label


static func ensure(area: Node) -> Node:
	if not VALID_SCENES.has(area.scene_file_path):
		return null
	var existing: Node = area.get_node_or_null("FirstLoot")
	if existing != null:
		return existing
	var controller: Node = (load("res://scripts/first_loot.gd") as Script).new()
	controller.name = "FirstLoot"
	controller.main = area
	area.add_child(controller)
	controller._setup()
	return controller


func _setup() -> void:
	progress = get_tree().root.get_node("AdventureProgress")
	equipment_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/first_equipment.json"))
	equipment_runtime = preload("res://scripts/equipment_runtime.gd").ensure(main)
	preload("res://scripts/hp_potion_runtime.gd").ensure(main)
	supplies_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/first_supplies.json"))
	item = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)).items["3128"]
	process_priority = 800
	process_physics_priority = -950
	var theme: Theme = main.get_node("Interface/Title").theme
	_hint = _label(theme, 12)
	_hint.name = "FirstDropHint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.size = Vector2(220, 42)
	_hint.add_theme_color_override("font_color", Color(0.98, 0.86, 0.54))
	main.get_node("PortClip").add_child(_hint)
	_toast = _label(theme, 14)
	_toast.name = "LootFeedback"
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position = Vector2(248, 340)
	_toast.size = Vector2(400, 30)
	main.get_node("PortClip").add_child(_toast)
	_drop = Sprite3D.new()
	_drop.name = "DragonEyeDrop"
	_drop.texture = load(item.field_path)
	_drop.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_drop.pixel_size = 1.0 / 60.0
	_drop.scale.y = 1.0 / cos(main.player.ELEVATION)
	_drop.offset.y = _drop.texture.get_height() * 0.5
	_drop.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_drop.alpha_scissor_threshold = 0.25
	_drop.shaded = false
	_drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.world.get_node("Actors").add_child(_drop)
	_build_bag(theme)
	_refresh()


func _label(theme: Theme, font_size: int) -> Label:
	var label := Label.new()
	label.theme = theme
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.035, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	return label


func _input(event: InputEvent) -> void:
	if _bag_open:
		if event is InputEventKey:
			if event.pressed and not event.echo:
				if event.keycode in [KEY_B, KEY_ESCAPE]:
					close_bag()
				elif event.keycode == KEY_C:
					_switch_weapon()
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_B and open_bag():
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_E:
		if _free_grounded() and progress.capture_state().pending_save:
			_feedback("进度已保存" if progress.retry_pending_save() else "仍无法保存，请稍后按 E 重试。")
			get_viewport().set_input_as_handled()
		elif can_pickup():
			if progress.claim_first_drop():
				_feedback("获得  " + str(item.name) + " × 1")
			else:
				_feedback("暂时无法保存，物品仍在原处。")
			_refresh()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _bag_open:
		main.player.ui_input_blocked = true
	_toast_remaining = maxf(0.0, _toast_remaining - delta)
	_refresh()


func _physics_process(_delta: float) -> void:
	if _bag_open:
		main.player.ui_input_blocked = true
		main.player.velocity = Vector3.ZERO


func _free_grounded() -> bool:
	if not is_instance_valid(main) or get_tree().current_scene != main:
		return false
	var p: Node = main.player
	if p.paused or p.preview_mode or p._one_shot or p.ui_input_blocked or p.markers_visible or p.jump_motion.is_active():
		return false
	if absf(p.height_above_ground) > 0.0001:
		return false
	var travel: Node = main.get_node_or_null("WorldTravel")
	if travel != null and not travel.is_ready():
		return false
	for menu: Node in get_tree().root.find_children("*", "PopupMenu", true, false):
		if menu.visible:
			return false
	return not progress.capture_state().dialog_open


func _drop_pending_here() -> bool:
	if main.scene_file_path != "res://scenes/tower_hall.tscn" or progress.progress.first_drop.state != "pending":
		return false
	var encounter: Node = main.get_node_or_null("FirstEncounter")
	# Let the current defeat pose finish before revealing the saved pickup.
	# A later practice reset must keep an earlier unclaimed pickup available.
	return encounter == null or not encounter.cleared or not encounter.enemy.visible


func _drop_point() -> Vector2:
	var point: Array = progress.progress.first_drop.position
	var source := Vector2(point[0], point[1])
	# Keep older pending drops reachable if a later layout gains solid props.
	return main.call("_constrain_ground", source, source) if main.has_method("_constrain_ground") else source


func can_pickup() -> bool:
	if not _drop_pending_here() or not _free_grounded() or _bag_open or progress.capture_state().pending_save:
		return false
	var difference: Vector2 = main.player.world_to_source(main.player.position) - _drop_point()
	return absf(difference.x) <= 48.0 and absf(difference.y) <= 24.0


func open_bag() -> bool:
	if _bag_open or not _free_grounded():
		return false
	_bag_open = true
	main.player.ui_input_blocked = true
	main.player.velocity = Vector3.ZERO
	main.player.play("stay")
	_layer.visible = true
	main.get_viewport().gui_release_focus()
	_refresh()
	return true


func close_bag() -> void:
	if not _bag_open:
		return
	_bag_open = false
	_layer.visible = false
	if is_instance_valid(main) and is_instance_valid(main.player):
		var travel: Node = main.get_node_or_null("WorldTravel")
		if (travel == null or travel.is_ready()) and not progress.capture_state().dialog_open:
			main.player.ui_input_blocked = false
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and _layer.is_ancestor_of(focus):
		focus.release_focus()


func _feedback(message: String) -> void:
	_toast.text = message
	_toast_remaining = 2.4


func _switch_weapon() -> void:
	if not _bag_open:
		return
	if progress.capture_state().pending_save:
		_feedback("进度已保存" if progress.retry_pending_save() else "仍无法保存，请稍后重试。")
	elif progress.owns_weapon("27304"):
		var target: String = "practice_lswd0000" if progress.equipped_weapon_key() == "27304" else "27304"
		if progress.equip_weapon(target):
			_feedback("已装备普通巨剑 · 攻击 +4" if target == "27304" else "已换回练习长剑")
		else:
			_feedback("装备进度尚未保存，请按 C 重试。")
	_refresh()


func _refresh() -> void:
	var visible_ui: bool = main.get_node("Interface").visible
	_drop.visible = _drop_pending_here()
	if _drop.visible:
		_drop.position = main.player.source_to_world(_drop_point()) + Vector3(0, 0.025, 0)
	_hint.visible = visible_ui and _drop.visible and not _bag_open
	if _hint.visible:
		_hint.text = str(item.name) + ("\nE 拾取" if can_pickup() else "")
		_hint.position = _drop_point() + Vector2(-110, -12) - Vector2(main.framing.offset_x, main.framing.offset_y)
	_toast.visible = visible_ui and _toast_remaining > 0 and not _bag_open
	if progress.capture_state().pending_save and not _bag_open:
		_toast.text = "进度未保存 · E 重试"
		_toast.visible = visible_ui
	if _bag_open:
		var count: int = int(progress.progress.inventory["3128"])
		_count.text = str(count) if count > 0 else ""
		_icon.visible = count > 0
		_description.text = str(item.name) + "\n材料\n\n首次击退龙人的战利品。" if count > 0 else "行囊还是空的。\n\n塔内掉落的材料会收进这里。"
		var owned: bool = progress.owns_weapon("27304")
		var potions: int = progress.hp_potion_count()
		_potion_icon.visible = potions > 0
		_potion_count.text = str(potions) if potions > 0 else ""
		var equipped: bool = progress.equipped_weapon_key() == "27304"
		_weapon_icon.visible = owned
		_weapon_mark.visible = owned and equipped
		if count == 0 and owned:
			_description.text = "普通巨剑\n武器 · 攻击 +4\n\n萝莉安赠送的谢礼。"
		if potions > 0:
			if count == 0 and not owned:
				_description.text = str(supplies_data.potion.name) + "\n消耗品"
			_description.text += "\n\n药剂 × %d · 关闭行囊后按 H 恢复 %d 生命。" % [potions, int(supplies_data.potion.heal_hp)]
		_coins.text = "金币  " + str(int(progress.progress.coins)) + "  ·  " + ("普通巨剑" if equipped else "练习长剑")
		_equip_button.disabled = not owned and not progress.capture_state().pending_save
		if progress.capture_state().pending_save:
			_equip_button.text = "进度未保存 · C 重试"
		elif not owned:
			_equip_button.text = "普通巨剑 · 完成港口委托后获得"
		else:
			_equip_button.text = "换回练习长剑  C" if equipped else "装备普通巨剑 · 攻击 +4  C"


func _build_bag(theme: Theme) -> void:
	_layer = CanvasLayer.new()
	_layer.name = "FirstBag"
	_layer.layer = 115
	_layer.visible = false
	add_child(_layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.4)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(shade)
	var panel := PanelContainer.new()
	panel.theme = theme
	panel.position = Vector2(240, 140)
	panel.custom_minimum_size = Vector2(480, 270)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.045, 0.065, 0.09, 0.98)
	frame.border_color = Color(0.64, 0.5, 0.29)
	frame.set_border_width_all(1)
	frame.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", frame)
	shade.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var heading := _label(theme, 18)
	heading.text = "行囊"
	heading.add_theme_color_override("font_color", Color(0.95, 0.85, 0.63))
	column.add_child(heading)
	var contents := HBoxContainer.new()
	contents.add_theme_constant_override("separation", 24)
	column.add_child(contents)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	contents.add_child(grid)
	for index: int in 8:
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(44, 44)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.085, 0.11, 0.13)
		style.border_color = Color(0.3, 0.32, 0.3)
		style.set_border_width_all(1)
		slot.add_theme_stylebox_override("panel", style)
		grid.add_child(slot)
		if index == 0:
			_icon = TextureRect.new()
			_icon.position = Vector2(8, 8)
			_icon.size = Vector2(28, 28)
			_icon.texture = load(item.icon_path)
			_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(_icon)
			_count = _label(theme, 12)
			_count.position = Vector2(27, 27)
			slot.add_child(_count)
		elif index == 1:
			_weapon_icon = TextureRect.new()
			_weapon_icon.position = Vector2(8, 8)
			_weapon_icon.size = Vector2(28, 28)
			_weapon_icon.texture = load(equipment_data.items["27304"].icon_path)
			_weapon_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(_weapon_icon)
			_weapon_mark = _label(theme, 10)
			_weapon_mark.text = "装"
			_weapon_mark.position = Vector2(27, 27)
			slot.add_child(_weapon_mark)
		elif index == 2:
			slot.name = "HpPotionSlot"
			_potion_icon = TextureRect.new()
			_potion_icon.name = "HpPotionIcon"
			_potion_icon.position = Vector2(8, 8)
			_potion_icon.size = Vector2(28, 28)
			_potion_icon.texture = load(str(supplies_data.potion.icon_path))
			_potion_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_potion_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(_potion_icon)
			_potion_count = _label(theme, 12)
			_potion_count.name = "HpPotionCount"
			_potion_count.position = Vector2(27, 27)
			slot.add_child(_potion_count)
	_description = _label(theme, 13)
	_description.custom_minimum_size = Vector2(220, 94)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contents.add_child(_description)
	_coins = _label(theme, 13)
	column.add_child(_coins)
	_equip_button = Button.new()
	_equip_button.name = "WeaponEquip"
	_equip_button.pressed.connect(_switch_weapon)
	column.add_child(_equip_button)
	var close := Button.new()
	close.text = "关闭行囊  B / Esc"
	close.pressed.connect(close_bag)
	column.add_child(close)


func capture_state() -> Dictionary:
	return {"bag_open": _bag_open, "drop_visible": _drop.visible, "can_pickup": can_pickup(),
		"position": _drop_point(), "inventory_count": int(progress.progress.inventory["3128"]),
		"potion_count": progress.hp_potion_count(), "potion_icon_visible": _potion_icon.visible,
		"toast": _toast.text if _toast.visible else ""}
