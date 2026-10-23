extends Node
## Manual guard owns defense/pose clocks only; callers retain valid-hit checks and HP/recoil.

const DATA_PATH: String = "res://data/guard_rules.json"
const PENDING_META: StringName = &"guard_runtime_pending"
const RAW_SCENE: String = "res://scenes/west_coast_r0.tscn"
const SCENES: Array[String] = ["res://scenes/west_coast_r1.tscn", "res://scenes/tower_approach.tscn", "res://scenes/tower_hall.tscn", "res://scenes/tower_depths.tscn", "res://scenes/tower_doll_gallery.tscn", "res://scenes/tower_statue_gallery.tscn"]
var main: Node
var rules: Dictionary = {}
var cooldown_remaining: float = 0.0
var reaction_remaining: float = 0.0
var accepted_begins: int = 0
var rejected_begins: int = 0
var blocked_hits: int = 0
var uncovered_hits: int = 0
var end_count: int = 0
var reset_count: int = 0
var last_reject_reason: String = ""
var last_end_reason: String = ""
var last_hit: Dictionary = {}
var _active: bool = false
var _release_pending: bool = false
var _needs_release: bool = false
var _locked_facing: int = 1
var _guard_actor: Node
var _guard_property_available: bool = false
var _menus: Array[Node] = []
var _hud: PanelContainer
var _label: Label


static func ensure(area: Node) -> Node:
	var tree: SceneTree = area.get_tree()
	var controller: Node = tree.root.get_node_or_null("GuardRuntime")
	if controller == null and tree.has_meta(PENDING_META):
		controller = tree.get_meta(PENDING_META)
		if is_instance_valid(controller):
			controller.call_deferred("attach_area", area)
			return controller
	if controller == null:
		controller = (load("res://scripts/guard_runtime.gd") as Script).new()
		controller.name = "GuardRuntime"
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
	rules = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 860
	# Before enemy-hit physics (-900), after travel/bag gates (-1000/-950).
	process_physics_priority = -925
	get_tree().scene_changed.connect(_on_scene_changed)
	get_tree().root.focus_exited.connect(_on_focus_exited)


func _on_scene_changed() -> void:
	attach_area(get_tree().current_scene)


func _on_focus_exited() -> void:
	end_guard("focus_lost")


func attach_area(area: Node) -> void:
	if not is_instance_valid(area) or not area.is_inside_tree():
		return
	if area == main and is_instance_valid(_hud):
		_refresh_hud()
		return
	end_guard("scene_change")
	_clear_hud()
	main = area
	_guard_property_available = _has_guard_property(_actor())
	_menus = get_tree().root.find_children("*", "PopupMenu", true, false)
	if not SCENES.has(main.scene_file_path):
		return
	var clip: Control = main.get_node_or_null("PortClip") as Control
	var title: Label = main.get_node_or_null("Interface/Title") as Label
	if clip == null or title == null:
		return
	_hud = PanelContainer.new()
	_hud.name = "GuardStatus"
	_hud.position = Vector2(416, 372)
	_hud.custom_minimum_size = Vector2(210, 24)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.theme = title.theme
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.035, 0.055, 0.86)
	background.content_margin_left = 8
	background.content_margin_right = 8
	background.content_margin_top = 3
	background.content_margin_bottom = 3
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


func _has_guard_property(actor: Node) -> bool:
	return is_instance_valid(actor) and actor.get_property_list().any(func(property: Dictionary): return property.name == "guard_active" and property.type == TYPE_BOOL)


func _pressed() -> bool:
	return Input.is_action_pressed("guard") if InputMap.has_action("guard") else Input.is_physical_key_pressed(KEY_C)


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
		return int(fight.player_hp)
	var raw: Variant = get_tree().get_meta("route_hero_hp", 100) if is_inside_tree() else 100
	return int(raw) if typeof(raw) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(raw)) else 100


func _freeze_reason(actor: Node) -> String:
	if not is_inside_tree() or not is_instance_valid(main) or not is_instance_valid(actor) or get_tree().current_scene != main or not main.is_inside_tree():
		return "transition"
	if main.scene_file_path == RAW_SCENE:
		return "comparison"
	if not SCENES.has(main.scene_file_path):
		return "region"
	if _hp() <= 0:
		return "defeated"
	if actor.preview_mode:
		return "preview"
	var travel: Node = main.get_node_or_null("WorldTravel")
	if travel != null and not travel.is_ready():
		return "travel"
	for popup: Node in _menus:
		if is_instance_valid(popup) and popup.visible:
			return "menu"
	for pair: Array in [["FirstLoot", "_bag_open"], ["SharanInteraction", "_open"], ["PortSupplyShop", "_open"]]:
		var modal: Node = main.get_node_or_null(pair[0])
		if modal != null and bool(modal.get(pair[1])):
			return "modal"
	var progress: Node = get_tree().root.get_node_or_null("AdventureProgress")
	if progress != null and bool(progress.get("_dialog_open")):
		return "modal"
	if get_tree().paused or actor.paused:
		return "paused"
	if actor.markers_visible:
		return "inspection"
	var fight: Node = _fight()
	var own_hurt: bool = fight != null and (bool(fight.get("_hero_lock")) or bool(fight.get("_release_pending")))
	if actor.ui_input_blocked and not own_hurt:
		return "input_blocked"
	return ""


func _begin_rejection(actor: Node) -> String:
	if not is_instance_valid(actor) or actor != _actor():
		return "actor"
	var frozen: String = _freeze_reason(actor)
	if not frozen.is_empty():
		return frozen
	if _active:
		return "active"
	if _needs_release:
		return "release_required"
	if actor.ui_input_blocked:
		return "input_blocked"
	if actor.jump_motion.is_active() or absf(float(actor.height_above_ground)) > .0001:
		return "airborne"
	if actor._one_shot:
		return "action"
	if cooldown_remaining > 0.0:
		return "cooldown"
	if not _guard_property_available:
		return "guard_property_missing"
	var animations: Dictionary = actor.get("_animations")
	if rules.is_empty() or not animations.has("guard") or animations.guard.frames.size() <= int(rules.hit_frame):
		return "unavailable"
	return ""


func begin(actor: Node) -> bool:
	# Only entry/property refresh inspects actor metadata; no unknown dynamic set is used.
	if is_instance_valid(actor) and actor == _actor():
		_guard_property_available = _has_guard_property(actor)
	last_reject_reason = _begin_rejection(actor)
	if not last_reject_reason.is_empty():
		rejected_begins += 1
		return false
	_guard_actor = actor
	_active = true
	_release_pending = false
	_needs_release = false
	_locked_facing = 1 if int(actor.facing) >= 0 else -1
	reaction_remaining = 0.0
	cooldown_remaining = float(rules.cooldown_seconds)
	actor.set("guard_active", true)
	actor.velocity = Vector3.ZERO
	actor.queued_attack = false
	actor.attack_buffer_remaining = 0.0
	if is_instance_valid(actor.action_audio):
		actor.action_audio.stop()
	accepted_begins += 1
	_hold_pose()
	_refresh_hud()
	return true


func end_guard(reason: String = "release") -> bool:
	if not _active:
		if reason in ["release", "key_release"] and not _pressed():
			_needs_release = false
		return false
	if reason in ["release", "key_release"]:
		var frozen: String = _freeze_reason(_guard_actor)
		if reaction_remaining > 0.0 or frozen in ["paused", "inspection"]:
			_release_pending = true
			return true
	_finish_guard(reason)
	return true


func _finish_guard(reason: String) -> void:
	var actor: Node = _guard_actor
	if is_instance_valid(actor) and _guard_property_available:
		actor.set("guard_active", false)
		actor.velocity = Vector3.ZERO
		# The outgoing scene can leave the tree before its objects are freed.
		# Clear logical defense there, but do not sample a detached 3D transform.
		if actor.is_inside_tree() and actor.animation_name == "guard" and not actor.preview_mode:
			actor.play("stay", true)
	if _active:
		end_count += 1
	_active = false
	_release_pending = false
	reaction_remaining = 0.0
	_guard_actor = null
	_needs_release = _pressed()
	last_end_reason = reason
	_refresh_hud()


func reset() -> void:
	_finish_guard("reset")
	cooldown_remaining = 0.0
	reset_count += 1
	last_reject_reason = ""
	_refresh_hud()


func _sync_active_state() -> void:
	if not _active:
		return
	var actor: Node = _guard_actor
	if not is_instance_valid(actor) or actor != _actor():
		_finish_guard("scene_change")
		return
	if not _guard_property_available or not bool(actor.get("guard_active")):
		_finish_guard("actor_cleared")
		return
	var reason: String = _freeze_reason(actor)
	if reason in ["paused", "inspection"]:
		return
	if not reason.is_empty():
		_finish_guard(reason)
		return
	var fight: Node = _fight()
	if actor._one_shot or actor.jump_motion.is_active() or (fight != null and float(fight.hero_hurt_remaining) > 0.0):
		_finish_guard("action_or_hurt")
		return
	if not _pressed():
		_release_pending = true
	if _release_pending and reaction_remaining <= 0.0:
		_finish_guard("release")
		return
	actor.facing = _locked_facing
	actor.velocity = Vector3.ZERO


func _hold_pose() -> void:
	if not _active or not is_instance_valid(_guard_actor) or _guard_actor.preview_mode:
		return
	var actor: Node = _guard_actor
	actor.facing = _locked_facing
	if actor.animation_name != "guard":
		actor.play("guard", true)
	var frame: int = int(rules.hit_frame if reaction_remaining > 0.0 else rules.idle_frame)
	if actor.frame_index != frame:
		actor.frame_index = frame
		actor._apply_frame()
	actor.elapsed_ms = 0.0
	actor._update_sprite_transform()


func resolve_hit(actor: Node, attacker_source: Vector2, raw_damage: int, damage_kind: String = "physical") -> Dictionary:
	var result: Dictionary = {"blocked": false, "damage": maxi(0, raw_damage), "recoil_px": 0.0}
	if raw_damage <= 0:
		return result
	_sync_active_state()
	if not _active or actor != _guard_actor or not _freeze_reason(actor).is_empty():
		return result
	if damage_kind not in ["physical", "magic"]:
		_finish_guard("unsupported_damage_kind")
		return result
	var source: Vector2 = actor.world_to_source(actor.position)
	var front: bool = (attacker_source.x-source.x) * float(_locked_facing) > 0.0
	if not front:
		uncovered_hits += 1
		_finish_guard("uncovered_hit")
		return result
	var absorption: float = float(rules.magic_absorption_percent if damage_kind == "magic" else rules.physical_absorption_percent)
	var multiplier: float = 1.0-absorption/100.0
	var damage: int = maxi(int(rules.minimum_damage), int(ceil(float(raw_damage)*multiplier)))
	reaction_remaining = float(rules.reaction_seconds)
	blocked_hits += 1
	result = {"blocked": true, "damage": damage, "recoil_px": float(rules.recoil_px)}
	last_hit = {"raw_damage": raw_damage, "damage": damage, "absorbed": raw_damage-damage,
		"attacker_source": attacker_source, "defender_source": source, "facing": _locked_facing,
		"damage_kind": damage_kind, "absorption_percent": absorption}
	_hold_pose()
	_refresh_hud()
	return result


func _physics_process(delta: float) -> void:
	if _needs_release and not _pressed():
		_needs_release = false
	if _freeze_reason(_actor()).is_empty():
		cooldown_remaining = maxf(0.0, cooldown_remaining-delta)
		reaction_remaining = maxf(0.0, reaction_remaining-delta)
	_sync_active_state()


func _process(_delta: float) -> void:
	_sync_active_state()
	_hold_pose()
	_refresh_hud()


func _refresh_hud() -> void:
	if not is_instance_valid(_hud) or not is_instance_valid(_label):
		return
	var interface: Node = main.get_node_or_null("Interface")
	var shown: bool = interface != null and interface.visible
	if _hud.visible != shown:
		_hud.visible = shown
	var status: String = "就绪"
	if _active:
		status = "格挡中" if reaction_remaining <= 0.0 else "格挡 · 受到 %d 伤害" % int(last_hit.get("damage", 0))
	elif cooldown_remaining > 0.0:
		status = "%.1f 秒" % (ceilf(cooldown_remaining*10.0)/10.0)
	elif _needs_release:
		status = "松开后再次按住"
	var text: String = "C 格挡 · " + status
	if _label.text != text:
		_label.text = text


func capture_state() -> Dictionary:
	var actor: Node = _actor()
	var reason: String = _freeze_reason(actor)
	return {"active": _active, "guard_property_available": _guard_property_available,
		"actor_guard_active": bool(actor.get("guard_active")) if is_instance_valid(actor) and _guard_property_available else false,
		"cooldown_remaining": cooldown_remaining, "reaction_remaining": reaction_remaining,
		"release_pending": _release_pending, "needs_release": _needs_release, "locked_facing": _locked_facing,
		"can_begin": _begin_rejection(actor).is_empty(), "frozen": not reason.is_empty(), "freeze_reason": reason,
		"accepted_begins": accepted_begins, "rejected_begins": rejected_begins, "blocked_hits": blocked_hits,
		"uncovered_hits": uncovered_hits, "end_count": end_count, "reset_count": reset_count,
		"last_reject_reason": last_reject_reason, "last_end_reason": last_end_reason, "last_hit": last_hit.duplicate(true),
		"scene": main.scene_file_path if is_instance_valid(main) else "", "actor_id": actor.get_instance_id() if is_instance_valid(actor) else 0,
		"hud_visible": is_instance_valid(_hud) and _hud.is_visible_in_tree(), "hud_text": _label.text if is_instance_valid(_label) else ""}


func _exit_tree() -> void:
	end_guard("exit_tree")
	_clear_hud()
