extends Node
## A small adapted supply counter entered from Lorian's existing conversation.

const SCENE: String = "res://scenes/west_coast_r1.tscn"
var main: Node
var progress: Node
var data: Dictionary
var _open: bool = false
var _layer: CanvasLayer
var _entry_button: Button
var _buy_button: Button
var _close_button: Button
var _balance: Label
var _stock: Label
var _notice: Label


static func ensure(area: Node) -> Node:
	if area.scene_file_path != SCENE:
		return null
	var existing: Node = area.get_node_or_null("PortSupplyShop")
	if existing != null:
		return existing
	var shop: Node = (load("res://scripts/port_supply_shop.gd") as Script).new()
	shop.name = "PortSupplyShop"
	shop.main = area
	area.add_child(shop)
	shop._setup()
	return shop


func _setup() -> void:
	progress = get_tree().root.get_node("AdventureProgress")
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/first_supplies.json"))
	process_physics_priority = -930
	var confirm: Button = progress.get("_confirm") as Button
	assert(confirm != null and is_instance_valid(confirm.get_parent()))
	_entry_button = Button.new()
	_entry_button.name = "SupplyShopButton"
	_entry_button.text = "补给"
	_entry_button.pressed.connect(open_shop)
	confirm.get_parent().add_child(_entry_button)
	_build_dialog(main.get_node("Interface/Title").theme)
	_refresh()


func _eligible() -> bool:
	return is_instance_valid(main) and main.is_inside_tree() and get_tree().current_scene == main and main.scene_file_path == SCENE


func open_shop() -> bool:
	if _open or not _eligible():
		return false
	if not bool(progress.get("_dialog_open")) and not progress.can_interact():
		return false
	progress.close_dialog()
	_open = true
	main.player.ui_input_blocked = true
	main.player.velocity = Vector3.ZERO
	main.player.play("stay")
	_layer.show()
	main.get_viewport().gui_release_focus()
	_refresh()
	if not _buy_button.disabled:
		_buy_button.grab_focus()
	else:
		_close_button.grab_focus()
	return true


func close_shop() -> void:
	if not _open:
		return
	_open = false
	_layer.hide()
	if _eligible():
		main.player.ui_input_blocked = false
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and _layer.is_ancestor_of(focus):
		focus.release_focus()


func _pending() -> bool:
	return not (progress.get("_pending_bundle") as Dictionary).is_empty()


func _can_buy() -> bool:
	return not _pending() and int(progress.progress.coins) >= progress.hp_potion_price() and progress.hp_potion_count() < progress.hp_potion_capacity()


func buy_one() -> bool:
	if not _open or not _eligible():
		return false
	var retrying: bool = _pending()
	var saved: bool = progress.retry_pending_save() if retrying else progress.buy_hp_potion()
	_notice.text = ("进度已保存。" if retrying else "药剂已放入行囊。") if saved else str(progress.last_error)
	_refresh()
	return saved


func _input(event: InputEvent) -> void:
	if not _open or not event is InputEventKey:
		return
	if event.pressed and not event.echo:
		if event.keycode in [KEY_E, KEY_ESCAPE]:
			close_shop()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not _buy_button.disabled:
			buy_one()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _open:
		if not _eligible():
			close_shop()
			return
		main.player.ui_input_blocked = true
		_refresh()


func _physics_process(_delta: float) -> void:
	if _open and _eligible():
		main.player.ui_input_blocked = true
		main.player.velocity = Vector3.ZERO


func _refresh() -> void:
	if not is_instance_valid(_balance):
		return
	_balance.text = "金币  %d" % int(progress.progress.coins)
	_stock.text = "%s  × %d" % [data.potion.name, progress.hp_potion_count()]
	_buy_button.text = "重试保存" if _pending() else "购买 1 瓶 · %d 金币" % progress.hp_potion_price()
	_buy_button.disabled = not _pending() and not _can_buy()


func _label(theme: Theme, size: int) -> Label:
	var label := Label.new()
	label.theme = theme
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_dialog(theme: Theme) -> void:
	_layer = CanvasLayer.new()
	_layer.name = "LorianSupplies"
	_layer.layer = 112
	_layer.hide()
	add_child(_layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.4)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(shade)
	var panel := PanelContainer.new()
	panel.theme = theme
	panel.position = Vector2(232, 140)
	panel.custom_minimum_size = Vector2(496, 276)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.08, 0.11, 0.98)
	style.border_color = Color(0.64, 0.50, 0.29)
	style.set_border_width_all(1)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	shade.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var title: Label = _label(theme, 17)
	title.text = "萝莉安 · 旅途补给"
	column.add_child(title)
	_balance = _label(theme, 14)
	column.add_child(_balance)
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 12)
	column.add_child(item)
	var icon := TextureRect.new()
	icon.texture = load(str(data.potion.icon_path))
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size = Vector2(36, 36)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(icon)
	_stock = _label(theme, 14)
	item.add_child(_stock)
	var description: Label = _label(theme, 13)
	description.text = "自由操作时按 H 使用，恢复 %d 生命。冷却 %d 秒。" % [int(data.potion.heal_hp), int(data.potion.cooldown_seconds)]
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 440
	column.add_child(description)
	_notice = _label(theme, 12)
	_notice.text = "购买后可按 B 查看。"
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.custom_minimum_size.x = 440
	column.add_child(_notice)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	_buy_button = Button.new()
	_buy_button.name = "BuyPotion"
	_buy_button.pressed.connect(buy_one)
	row.add_child(_buy_button)
	_close_button = Button.new()
	_close_button.name = "CloseSupplies"
	_close_button.text = "继续旅程"
	_close_button.pressed.connect(close_shop)
	row.add_child(_close_button)
	var hint: Label = _label(theme, 11)
	hint.text = "Enter 购买  ·  E / Esc 关闭"
	column.add_child(hint)


func capture_state() -> Dictionary:
	return {"dialog_open": _open, "coins": int(progress.progress.coins), "potion_count": progress.hp_potion_count(),
		"price": progress.hp_potion_price(), "capacity": progress.hp_potion_capacity(), "can_buy": _can_buy(),
		"pending_save": _pending(), "buy_text": _buy_button.text if is_instance_valid(_buy_button) else ""}


func _exit_tree() -> void:
	close_shop()
	if is_instance_valid(_entry_button):
		_entry_button.queue_free()
