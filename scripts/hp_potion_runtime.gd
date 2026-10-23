extends Node
## Session cooldown and HP application; AdventureProgress alone owns potion persistence.

const DATA_PATH: String = "res://data/first_supplies.json"
const MAX_HP: int = 100
const PENDING_META: StringName = &"hp_potion_runtime_pending"
const RAW_SCENE: String = "res://scenes/west_coast_r0.tscn"
const SCENES: Array[String] = ["res://scenes/west_coast_r1.tscn", "res://scenes/tower_approach.tscn", "res://scenes/tower_hall.tscn", "res://scenes/tower_depths.tscn", "res://scenes/tower_doll_gallery.tscn", "res://scenes/tower_statue_gallery.tscn"]
var main: Node
var cooldown_remaining: float = 0.0
var accepted_uses: int = 0
var rejected_uses: int = 0
var reset_count: int = 0
var last_reject_reason: String = ""
var last_heal: Dictionary = {}
var _potion: Dictionary = {}
var _hud: PanelContainer
var _label: Label
var _menus: Array[Node] = []


static func ensure(area: Node) -> Node:
	var tree: SceneTree = area.get_tree()
	var controller: Node = tree.root.get_node_or_null("HpPotionRuntime")
	if controller == null and tree.has_meta(PENDING_META):
		controller = tree.get_meta(PENDING_META)
		if is_instance_valid(controller):
			controller.call_deferred("attach_area", area)
			return controller
	if controller == null:
		controller = (load("res://scripts/hp_potion_runtime.gd") as Script).new()
		controller.name = "HpPotionRuntime"
		tree.set_meta(PENDING_META, controller)
		tree.root.call_deferred("add_child", controller)
		controller.call_deferred("_initialize")
		controller.call_deferred("attach_area", area)
		return controller
	controller.attach_area(area)
	return controller


func _initialize() -> void:
	if get_tree().get_meta(PENDING_META, null) == self:
		get_tree().remove_meta(PENDING_META)
	if FileAccess.file_exists(DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary and parsed.get("potion") is Dictionary:
			_potion = parsed.potion
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 850
	get_tree().scene_changed.connect(_on_scene_changed)


func _on_scene_changed() -> void:
	attach_area(get_tree().current_scene)


func attach_area(area: Node) -> void:
	if not is_instance_valid(area) or not area.is_inside_tree():
		return
	if area == main and is_instance_valid(_hud):
		_refresh_hud()
		return
	_clear_hud()
	main = area
	_menus = get_tree().root.find_children("*", "PopupMenu", true, false)
	if not SCENES.has(main.scene_file_path):
		return
	var clip: Control = main.get_node_or_null("PortClip") as Control
	var title: Label = main.get_node_or_null("Interface/Title") as Label
	if clip == null or title == null:
		return
	_hud = PanelContainer.new()
	_hud.name = "HpPotionCooldown"
	_hud.position = Vector2(220, 372)
	_hud.custom_minimum_size = Vector2(180, 24)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.theme = title.theme
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.035, 0.055, 0.86)
	background.content_margin_left = 8.0
	background.content_margin_right = 8.0
	background.content_margin_top = 3.0
	background.content_margin_bottom = 3.0
	_hud.add_theme_stylebox_override("panel", background)
	_label = Label.new()
	_label.name = "Status"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.90, 0.87, 0.77))
	_hud.add_child(_label)
	clip.add_child(_hud)
	_refresh_hud()


func _clear_hud() -> void:
	if is_instance_valid(_hud):
		if _hud.get_parent() != null:
			_hud.get_parent().remove_child(_hud)
		_hud.queue_free()
	_hud = null
	_label = null


func _actor() -> Node:
	if not is_instance_valid(main) or not (SCENES.has(main.scene_file_path) or main.scene_file_path == RAW_SCENE):
		return null
	return main.get("player")


func _profile() -> Node:
	return get_tree().root.get_node_or_null("AdventureProgress") if is_inside_tree() else null


func _quantity() -> int:
	var profile: Node = _profile()
	return int(profile.hp_potion_count()) if profile != null and profile.has_method("hp_potion_count") else 0


func _fight() -> Node:
	if not is_instance_valid(main):
		return null
	var fight: Node = main.get_node_or_null("TowerBoss")
	if fight == null:
		fight = main.get_node_or_null("GalleryEncounter")
	if fight == null:
		fight = main.get_node_or_null("StatueEncounter")
	return fight if fight != null else main.get_node_or_null("FirstEncounter")


func _hp() -> int:
	var fight: Node = _fight()
	if fight != null:
		return clampi(int(fight.player_hp), 0, MAX_HP)
	var raw: Variant = get_tree().get_meta("route_hero_hp", MAX_HP) if is_inside_tree() else MAX_HP
	return clampi(int(raw), 0, MAX_HP) if typeof(raw) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(raw)) else MAX_HP


func _freeze_reason(actor: Node) -> String:
	if not is_inside_tree() or not is_instance_valid(actor) or not is_instance_valid(main) or get_tree().current_scene != main or not main.is_inside_tree():
		return "transition"
	if main.scene_file_path == RAW_SCENE:
		return "comparison"
	if not SCENES.has(main.scene_file_path):
		return "region"
	if get_tree().paused or actor.paused:
		return "paused"
	if actor.preview_mode:
		return "preview"
	if actor.markers_visible:
		return "inspection"
	var travel: Node = main.get_node_or_null("WorldTravel")
	if travel != null and not travel.is_ready():
		return "travel"
	for popup: Node in _menus:
		if is_instance_valid(popup) and popup.visible:
			return "menu"
	var loot: Node = main.get_node_or_null("FirstLoot")
	if loot != null and bool(loot.get("_bag_open")):
		return "bag"
	var profile: Node = _profile()
	if profile != null and bool(profile.get("_dialog_open")):
		return "dialog"
	var sharan: Node = main.get_node_or_null("SharanInteraction")
	if sharan != null and bool(sharan.get("_open")):
		return "dialog"
	if _hp() <= 0:
		return "defeated"
	var fight: Node = _fight()
	var hurt_lock: bool = fight != null and (bool(fight.get("_hero_lock")) or bool(fight.get("_release_pending")))
	if actor.ui_input_blocked and not hurt_lock:
		return "input_blocked"
	return ""


func _use_rejection(actor: Node) -> String:
	if not is_instance_valid(actor) or actor != _actor():
		return "actor"
	var frozen: String = _freeze_reason(actor)
	if not frozen.is_empty():
		return frozen
	if actor.ui_input_blocked:
		return "input_blocked"
	if actor.get("guard_active") == true:
		return "guard"
	if actor.jump_motion.is_active() or absf(float(actor.height_above_ground)) > .0001:
		return "airborne"
	if actor._one_shot:
		return "action"
	if _hp() >= MAX_HP:
		return "full_hp"
	if cooldown_remaining > 0.0:
		return "cooldown"
	var profile: Node = _profile()
	if profile == null or not profile.has_method("consume_hp_potion") or int(_potion.get("item_id", 0)) != 1106 or int(_potion.get("heal_hp", 0)) <= 0 or float(_potion.get("cooldown_seconds", -1)) < 0.0:
		return "unavailable"
	var pending: Dictionary = profile.get("_pending_bundle")
	if not pending.is_empty():
		return "pending_save"
	if _quantity() <= 0:
		return "empty"
	return ""


func _apply_hp(value: int) -> void:
	var sessions: Dictionary = {}
	for key: String in ["first_encounter_state", "tower_boss_state", "doll_gallery_state", "statue_gallery_state"]:
		if get_tree().has_meta(key):
			var existing: Variant = get_tree().get_meta(key)
			sessions[key] = existing.duplicate(true) if existing is Dictionary else existing
	var fight: Node = _fight()
	if fight != null:
		fight.player_hp = value
		fight._persist()
	get_tree().set_meta("route_hero_hp", value)
	for key: String in ["first_encounter_state", "tower_boss_state", "doll_gallery_state", "statue_gallery_state"]:
		# _persist may refresh an enemy position. A potion changes only existing hero HP.
		if sessions.has(key):
			if sessions[key] is Dictionary:
				sessions[key]["player_hp"] = value
			get_tree().set_meta(key, sessions[key])
		elif get_tree().has_meta(key):
			get_tree().remove_meta(key)


func try_use(actor: Node) -> bool:
	last_reject_reason = _use_rejection(actor)
	if not last_reject_reason.is_empty():
		rejected_uses += 1
		return false
	var before_hp: int = _hp()
	var before_count: int = _quantity()
	# No await: persist the decrement first, then apply transient HP in this call stack.
	if not _profile().consume_hp_potion():
		last_reject_reason = "save_failed"
		rejected_uses += 1
		_refresh_hud()
		return false
	var after_hp: int = mini(MAX_HP, before_hp + int(_potion.heal_hp))
	_apply_hp(after_hp)
	cooldown_remaining = float(_potion.cooldown_seconds)
	accepted_uses += 1
	last_heal = {"item_id": int(_potion.item_id), "before_hp": before_hp, "after_hp": after_hp,
		"healed_hp": after_hp-before_hp, "before_count": before_count, "after_count": _quantity()}
	_refresh_hud()
	return true


func reset_cooldown() -> void:
	cooldown_remaining = 0.0
	reset_count += 1
	last_reject_reason = ""
	_refresh_hud()


func _process(delta: float) -> void:
	if cooldown_remaining > 0.0 and _freeze_reason(_actor()).is_empty():
		cooldown_remaining = maxf(0.0, cooldown_remaining-delta)
	_refresh_hud()


func _refresh_hud() -> void:
	if not is_instance_valid(_hud) or not is_instance_valid(_label):
		return
	var count: int = _quantity()
	var interface: Node = main.get_node_or_null("Interface")
	var shown: bool = interface != null and interface.visible and (count > 0 or cooldown_remaining > 0.0)
	if _hud.visible != shown:
		_hud.visible = shown
	var status: String = "就绪" if cooldown_remaining <= 0.0 else "%.1f 秒" % (ceilf(cooldown_remaining*10.0)/10.0)
	var text: String = "H 药剂×%d · %s" % [count, status]
	if _label.text != text:
		_label.text = text


func capture_state() -> Dictionary:
	var actor: Node = _actor()
	var reason: String = _freeze_reason(actor)
	return {"item_id": int(_potion.get("item_id", 0)), "heal_hp": int(_potion.get("heal_hp", 0)),
		"cooldown_seconds": float(_potion.get("cooldown_seconds", 0)), "cooldown_remaining": cooldown_remaining,
		"player_hp": _hp(), "count": _quantity(), "ready": cooldown_remaining <= 0.0,
		"can_use": _use_rejection(actor).is_empty(), "frozen": not reason.is_empty(), "freeze_reason": reason,
		"last_reject_reason": last_reject_reason, "last_heal": last_heal.duplicate(true),
		"accepted_uses": accepted_uses, "rejected_uses": rejected_uses, "reset_count": reset_count,
		"scene": main.scene_file_path if is_instance_valid(main) else "", "actor_id": actor.get_instance_id() if is_instance_valid(actor) else 0,
		"hud_visible": is_instance_valid(_hud) and _hud.is_visible_in_tree(), "hud_text": _label.text if is_instance_valid(_label) else ""}


func _exit_tree() -> void:
	_clear_hud()
