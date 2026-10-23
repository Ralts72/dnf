extends Node
## Session-only Upper Slash eligibility/cooldown; combat owns the finite launch.

const ACTION: String = "upperslash"
const RULES_PATH: String = "res://data/upper_slash_rules.json"
const PENDING_META: StringName = &"upper_slash_runtime_pending"
const SCENES: Array[String] = ["res://scenes/west_coast_r0.tscn", "res://scenes/west_coast_r1.tscn", "res://scenes/tower_approach.tscn", "res://scenes/tower_hall.tscn", "res://scenes/tower_depths.tscn", "res://scenes/tower_doll_gallery.tscn", "res://scenes/tower_statue_gallery.tscn"]

var main: Node
var rules: Dictionary = {}
var cooldown_remaining: float = 0.0
var accepted_casts: int = 0
var rejected_casts: int = 0
var reset_count: int = 0
var last_reject_reason: String = ""
var _hud: PanelContainer
var _label: Label
var _menus: Array[Node] = []


static func ensure(area: Node) -> Node:
	var tree: SceneTree = area.get_tree()
	var controller: Node = tree.root.get_node_or_null("UpperSlashRuntime")
	if controller == null and tree.has_meta(PENDING_META):
		var pending: Variant = tree.get_meta(PENDING_META)
		if pending is Node and is_instance_valid(pending):
			pending.call_deferred("attach_area", area)
			return pending
		tree.remove_meta(PENDING_META)
	if controller == null:
		controller = (load("res://scripts/upper_slash_runtime.gd") as Script).new()
		controller.name = "UpperSlashRuntime"
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
	rules = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 860
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
	_hud.name = "UpperSlashCooldown"
	_hud.position = Vector2(634, 372)
	_hud.custom_minimum_size = Vector2(248, 24)
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
		var parent: Node = _hud.get_parent()
		if parent != null:
			parent.remove_child(_hud)
		_hud.queue_free()
	_hud = null
	_label = null


func _actor() -> Node:
	if not is_instance_valid(main) or not SCENES.has(main.scene_file_path):
		return null
	return main.get("player")


func _fight() -> Node:
	if not is_instance_valid(main):
		return null
	for child: String in ["TowerBoss", "GalleryEncounter", "StatueEncounter", "FirstEncounter"]:
		var fight: Node = main.get_node_or_null(child)
		if fight != null:
			return fight
	return null


func _freeze_reason(actor: Node) -> String:
	if not is_inside_tree() or not is_instance_valid(actor) or not is_instance_valid(main) or get_tree().current_scene != main or not main.is_inside_tree():
		return "transition"
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
	if loot != null and loot.get("_bag_open") == true:
		return "bag"
	var progress: Node = get_tree().root.get_node_or_null("AdventureProgress")
	if progress != null and progress.get("_dialog_open") == true:
		return "dialog"
	var fight: Node = _fight()
	if fight != null and int(fight.player_hp) <= 0:
		return "defeated"
	# Own combat hurt rejects a new cast but preserves cooldown progression.
	var hurt_lock: bool = fight != null and (fight.get("_hero_lock") == true or fight.get("_release_pending") == true)
	if actor.ui_input_blocked and not hurt_lock:
		return "input_blocked"
	return ""


func _cast_rejection(actor: Node) -> String:
	if not is_instance_valid(actor) or actor != _actor():
		return "actor"
	var frozen: String = _freeze_reason(actor)
	if not frozen.is_empty():
		return frozen
	if actor.ui_input_blocked:
		return "input_blocked"
	# R0 intentionally has no guard property. Null must never enter bool().
	if actor.get("guard_active") == true:
		return "guard"
	if actor.jump_motion.is_active():
		return "airborne"
	if actor._one_shot:
		return "action"
	if cooldown_remaining > 0.0:
		return "cooldown"
	var animations: Dictionary = actor.get("_animations")
	if not animations.has(ACTION):
		return "unavailable"
	return ""


func try_cast(actor: Node) -> bool:
	last_reject_reason = _cast_rejection(actor)
	if not last_reject_reason.is_empty():
		rejected_casts += 1
		return false
	actor.perform(ACTION)
	# R0 has no attack_instance; both actors expose the accepted one-shot pose.
	if actor.animation_name != ACTION or not actor._one_shot:
		last_reject_reason = "not_accepted"
		rejected_casts += 1
		return false
	cooldown_remaining = float(rules.cooldown_seconds)
	accepted_casts += 1
	_refresh_hud()
	return true


func reset_cooldown() -> void:
	cooldown_remaining = 0.0
	reset_count += 1
	last_reject_reason = ""
	_refresh_hud()


func _process(delta: float) -> void:
	if cooldown_remaining > 0.0 and _freeze_reason(_actor()).is_empty():
		cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	_refresh_hud()


func _refresh_hud() -> void:
	if not is_instance_valid(_hud) or not is_instance_valid(_label):
		return
	var interface: Node = main.get_node_or_null("Interface")
	_hud.visible = interface != null and interface.visible
	var text: String = "V 上挑 · 就绪" if cooldown_remaining <= 0.0 else "V 上挑 · 冷却 %.1f 秒" % (ceilf(cooldown_remaining * 10.0) / 10.0)
	if _label.text != text:
		_label.text = text


func capture_state() -> Dictionary:
	var actor: Node = _actor()
	var reason: String = _freeze_reason(actor)
	return {"action": ACTION, "cooldown_seconds": float(rules.get("cooldown_seconds", 2.0)), "cooldown_remaining": cooldown_remaining,
		"ready": cooldown_remaining <= 0.0, "can_cast": _cast_rejection(actor).is_empty(), "frozen": not reason.is_empty(),
		"freeze_reason": reason, "last_reject_reason": last_reject_reason, "accepted_casts": accepted_casts,
		"rejected_casts": rejected_casts, "reset_count": reset_count,
		"scene": main.scene_file_path if is_instance_valid(main) else "", "actor_id": actor.get_instance_id() if is_instance_valid(actor) else 0,
		"hud_visible": is_instance_valid(_hud) and _hud.is_visible_in_tree(), "hud_text": _label.text if is_instance_valid(_label) else ""}


func _exit_tree() -> void:
	_clear_hud()
