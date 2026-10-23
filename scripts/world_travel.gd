extends Node
## Scene-local travel controller. Session progress and one pending spawn live on
## SceneTree, so replacing a scene never preserves its actor/action instances.

const ROUTE_PATH: String = "res://data/world_route.json"
const SESSION_META: StringName = &"world_travel_state"
const SPAWN_META: StringName = &"world_travel_spawn"
const REGION_META: StringName = &"world_region"

var main: Node
var _route: Dictionary = {}
var _region: String = ""
var _phase: String = "ready"
var _pending_target: String = ""
var _last_error: String = ""
var _overlay: CanvasLayer
var _veil: ColorRect
var _fade_tween: Tween
var _exit_hold_id: String = ""
var _exit_hold_elapsed: float = 0.0
var _hints: Array[Label] = []
var _hint_points: Array[Vector2] = []


static func ensure(scene_root: Node) -> Node:
	var existing: Node = scene_root.get_node_or_null("WorldTravel")
	if existing != null:
		return existing
	var controller: Node = (load("res://scripts/world_travel.gd") as Script).new()
	controller.name = "WorldTravel"
	controller.set("main", scene_root)
	scene_root.add_child(controller)
	controller.call("_setup")
	return controller


func _setup() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUTE_PATH))
	if not parsed is Dictionary:
		_last_error = "Invalid world route data"
		set_process(false)
		push_error(_last_error)
		return
	_route = parsed
	_region = _region_for_scene(main.scene_file_path)
	if _region.is_empty():
		_last_error = "Scene has no exploration region: " + main.scene_file_path
		set_process(false)
		push_error(_last_error)
		return
	process_priority = 1000
	process_physics_priority = -1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_meta(REGION_META, _region)
	var state: Dictionary = _session()
	state["current_region"] = _region
	var visited: Array = state.get("visited", [])
	if not visited.has(_region):
		visited.append(_region)
	state["visited"] = visited
	get_tree().set_meta(SESSION_META, state)
	_build_overlay()
	_build_hints()
	if _region == "harbor":
		var build_label: Label = main.get_node_or_null("Interface/Build") as Label
		if build_label != null:
			build_label.text = str(_route.get("build_label", "R2   /   01"))
	var spawn: Dictionary = get_tree().get_meta(SPAWN_META, {})
	if str(spawn.get("region", "")) == _region:
		get_tree().remove_meta(SPAWN_META)
		_pending_target = _region
		_phase = "fade_in"
		_apply_visual_settings(spawn.get("visual_settings", {}))
		_ground_actor(_vector(spawn.get("position", []), _default_spawn()),
			int(spawn.get("facing", 1)), str(spawn.get("next_attack", "attack1")))
		main.player.ui_input_blocked = true
		_veil.color = Color(0.0, 0.0, 0.0, 1.0)
		_finish_arrival.call_deferred()
	else:
		# F4 restores a comparison pose before this runs. A reset anchor belongs
		# to the last real arrival, never to that arbitrary comparison pose.
		if _region == "harbor":
			var anchors: Dictionary = state.get("reset_positions", {})
			var reset_point: Vector2 = _safe_point(_vector(anchors.get(_region, []), _default_spawn()))
			main.player.set("spawn_position", reset_point)
			_remember_reset_anchor(reset_point)
		else:
			_ground_actor(_default_spawn(), int(main.player.facing), str(main.player.next_attack))
		_veil.visible = false


func _process(delta: float) -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	_update_hints()
	if _phase != "ready":
		# Closing a preview popup can clear the actor's UI flag. Reassert it for
		# the entire fade, not only at the transition's first frame.
		main.player.ui_input_blocked = true
		main.player.velocity = Vector3.ZERO
		_reset_exit_hold()
		return
	var region: Dictionary = _region_data()
	var point: Vector2 = main.player.world_to_source(main.player.position)
	for exit_value: Variant in region.get("exits", []):
		var exit_id: String = str(exit_value)
		var exit_data: Dictionary = _route.get("exits", {}).get(exit_id, {})
		if _contains(exit_data.get("trigger_bounds", []), point) and Input.is_action_pressed(str(exit_data.get("action", ""))):
			if not _can_travel() or not _exit_unlocked(exit_data):
				_reset_exit_hold()
				return
			if _exit_hold_id != exit_id:
				_exit_hold_id = exit_id
				_exit_hold_elapsed = 0.0
			_exit_hold_elapsed += delta
			if _exit_hold_elapsed >= float(_route.get("exit_hold_seconds", 0.15)):
				request_exit(exit_id)
			return
	_reset_exit_hold()


func _physics_process(_delta: float) -> void:
	if _phase != "ready" and is_instance_valid(main) and is_instance_valid(main.player):
		# Run before actor physics so a popup_hide signal between render frames
		# cannot permit one movement tick during a fade.
		main.player.ui_input_blocked = true
		main.player.velocity = Vector3.ZERO


func _input(_event: InputEvent) -> void:
	if _phase != "ready":
		# A mouse shield does not intercept Enter/Space on a previously focused
		# preview/pause button. Consume those events before GUI signal handlers.
		get_viewport().set_input_as_handled()


func current_region() -> String:
	return _region


func is_ready() -> bool:
	return _phase == "ready"


func request_exit(exit_id: String) -> bool:
	if not _can_travel():
		return false
	var exit_data: Dictionary = _route.get("exits", {}).get(exit_id, {})
	if str(exit_data.get("from", "")) != _region or not _exit_unlocked(exit_data):
		return false
	var point: Vector2 = main.player.world_to_source(main.player.position)
	if not _contains(exit_data.get("trigger_bounds", []), point):
		return false
	if not Input.is_action_pressed(str(exit_data.get("action", ""))):
		return false
	if _exit_hold_id != exit_id or _exit_hold_elapsed < float(_route.get("exit_hold_seconds", 0.15)):
		return false
	var target: String = str(exit_data.get("to", ""))
	var target_data: Dictionary = _route.get("regions", {}).get(target, {})
	var target_path: String = str(target_data.get("scene", ""))
	if target_path.is_empty() or not ResourceLoader.exists(target_path):
		_last_error = "Destination scene is unavailable: " + target_path
		return false
	var state: Dictionary = _session()
	var position: Vector2 = _vector(exit_data.get("spawn", []), Vector2(440.0, 320.0))
	if bool(exit_data.get("use_harbor_return_position", false)):
		position = _vector(state.get("harbor_return_position", []), Vector2(60.0, 320.0))
	var transfer: Dictionary = {
		"region": target,
		"position": position,
		"facing": int(main.player.facing),
		"next_attack": str(main.player.next_attack),
		"visual_settings": _capture_visual_settings(),
		"from": _region,
		"exit_id": exit_id,
		"started_msec": Time.get_ticks_msec()
	}
	_phase = "fade_out"
	_pending_target = target
	_last_error = ""
	main.player.ui_input_blocked = true
	# An exit is accepted only while grounded. Clearing transient state here
	# also prevents a queued action or audio event leaking into the next scene.
	_ground_actor(point, int(main.player.facing), str(main.player.next_attack), false)
	main.player.ui_input_blocked = true
	_veil.visible = true
	_veil.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_and_change.call_deferred(exit_id, target_path, transfer)
	return true


func _fade_and_change(exit_id: String, target_path: String, transfer: Dictionary) -> void:
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_veil, "color:a", 1.0, float(_route.get("fade_out_seconds", 0.14)))
	await _fade_tween.finished
	if not is_instance_valid(main) or get_tree().current_scene != main:
		return
	var state: Dictionary = _session()
	var previous_state: Dictionary = state.duplicate(true)
	state["transition_count"] = int(state.get("transition_count", 0)) + 1
	state["last_exit"] = exit_id
	state["last_transition"] = transfer.duplicate(true)
	get_tree().set_meta(SESSION_META, state)
	get_tree().set_meta(SPAWN_META, transfer)
	# Comparison-scene snapshots are unrelated actor instances and must not
	# restore an old harbor action before the pending travel spawn is consumed.
	if get_tree().has_meta("port_compare_state"):
		get_tree().remove_meta("port_compare_state")
	for key: String in ["port_framing_offset", "port_framing_offset_x"]:
		if get_tree().has_meta(key):
			get_tree().remove_meta(key)
	var result: Error = get_tree().change_scene_to_file(target_path)
	if result != OK:
		get_tree().set_meta(SESSION_META, previous_state)
		get_tree().remove_meta(SPAWN_META)
		_last_error = "Scene change failed (%d): %s" % [result, target_path]
		_phase = "ready"
		_pending_target = ""
		main.player.ui_input_blocked = false
		_veil.visible = false
		if main.get("framing") != null:
			main.framing.remember()
		push_error(_last_error)


func _finish_arrival() -> void:
	# ensure() runs after the destination's _ready setup, before its first
	# rendered frame. Only the new controller owns this fade-in coroutine.
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_veil, "color:a", 0.0, float(_route.get("fade_in_seconds", 0.18)))
	await _fade_tween.finished
	if not is_instance_valid(main):
		return
	_phase = "ready"
	_pending_target = ""
	main.player.ui_input_blocked = false
	_veil.visible = false


func safe_reset() -> bool:
	if _phase != "ready" or not is_instance_valid(main):
		return false
	var point: Vector2 = main.player.get("spawn_position")
	_ground_actor(_safe_point(point), 1, "attack1")
	main.player.ui_input_blocked = false
	var skills: Node = get_tree().root.get_node_or_null("SourceSkillRuntime")
	if skills != null:
		skills.reset_cooldown()
	var upper: Node = get_tree().root.get_node_or_null("UpperSlashRuntime")
	if upper != null:
		upper.reset_cooldown()
	var supplies: Node = get_tree().root.get_node_or_null("HpPotionRuntime")
	if supplies != null:
		supplies.reset_cooldown()
	var guard: Node = get_tree().root.get_node_or_null("GuardRuntime")
	if guard != null:
		guard.reset()
	return true


func capture_state() -> Dictionary:
	var state: Dictionary = _session().duplicate(true)
	state["region"] = _region
	state["current_region"] = _region
	state["phase"] = _phase
	state["transitioning"] = _phase != "ready"
	state["pending_target"] = _pending_target
	state["last_error"] = _last_error
	state["fade_alpha"] = _veil.color.a if is_instance_valid(_veil) else 0.0
	state["exit_hold_id"] = _exit_hold_id
	state["exit_hold_seconds"] = _exit_hold_elapsed
	state["exit_hold_required_seconds"] = float(_route.get("exit_hold_seconds", 0.15))
	state["depths_unlocked"] = _exit_unlocked({"requires": "first_encounter_clear"})
	state["doll_gallery_unlocked"] = _exit_unlocked({"requires": "lakius_clear"})
	state["statue_gallery_unlocked"] = _exit_unlocked({"requires": "doll_gallery_clear"})
	if is_instance_valid(main) and is_instance_valid(main.player):
		state["source_position"] = main.player.world_to_source(main.player.position)
		state["spawn_position"] = main.player.get("spawn_position")
		state["ui_input_blocked"] = main.player.ui_input_blocked
		state["grounded"] = not main.player.jump_motion.is_active() and absf(main.player.height_above_ground) < 0.0001
		state["can_exit"] = _can_travel()
	return state


func _exit_unlocked(exit_data: Dictionary) -> bool:
	if str(exit_data.get("requires", "")) == "doll_gallery_clear":
		var gallery: Variant = get_tree().get_meta("doll_gallery_state", {})
		if gallery is Dictionary and gallery.get("cleared") is bool and gallery.cleared == true:
			return true
		return _committed_chapter_clear("stonemaster_cleared")
	if str(exit_data.get("requires", "")) == "lakius_clear":
		var boss: Variant = get_tree().get_meta("tower_boss_state", {})
		if boss is Dictionary and boss.get("cleared") is bool and boss.cleared == true:
			return true
		return _committed_chapter_clear("lakius_cleared")
	if str(exit_data.get("requires", "")) != "first_encounter_clear":
		return true
	var first: Variant = get_tree().get_meta("first_encounter_state", {})
	if first is Dictionary and first.get("cleared") is bool and first.get("cleared") == true:
		return true
	# A committed receipt also keeps the passage open after an R practice reset.
	var progress: Node = get_tree().root.get_node_or_null("AdventureProgress")
	return progress != null and str(progress.progress.get("first_drop", {}).get("state", "unearned")) in ["pending", "claimed"]


func _committed_chapter_clear(key: String) -> bool:
	var saved: Node = get_tree().root.get_node_or_null("AdventureProgress")
	if saved == null:
		return false
	var flags: Variant = saved.progress.get("chapter_flags", {})
	if not flags is Dictionary:
		return false
	var receipt: Variant = flags.get(key, false)
	return receipt is bool and receipt == true


func _can_travel() -> bool:
	if _phase != "ready" or not is_instance_valid(main) or not is_instance_valid(main.player):
		return false
	if get_tree().current_scene != main:
		return false
	var player: Node = main.player
	if player.paused or player.guard_active or player.preview_mode or player._one_shot or player.ui_input_blocked:
		return false
	if player.jump_motion.is_active() or absf(player.height_above_ground) > 0.0001:
		return false
	for popup: Node in get_tree().root.find_children("*", "PopupMenu", true, false):
		if popup.visible:
			return false
	return true


func _ground_actor(point: Vector2, facing: int, next_attack: String, update_spawn: bool = true) -> void:
	var player: Node = main.player
	if main.has_method("_set_paused"):
		main.call("_set_paused", false)
	player.paused = false
	player.jump_motion.reset()
	player.preview_mode = false
	player._one_shot = false
	player.velocity = Vector3.ZERO
	if is_instance_valid(player.action_audio):
		player.action_audio.stop()
	player.position = player.source_to_world(_safe_point(point))
	if update_spawn:
		player.set("spawn_position", _safe_point(point))
		_remember_reset_anchor(_safe_point(point))
	player.facing = -1 if facing < 0 else 1
	player.next_attack = next_attack if next_attack in ["attack1", "attack2", "attack3"] else "attack1"
	player.play("stay", true)
	player._update_sprite_transform()
	player.reset_physics_interpolation()
	if player.motion_smoothing:
		player.motion_smoothing.reset()
	if main.get("framing") != null:
		main.framing.advance(0.0, true)
		main.framing.remember()


func _capture_visual_settings() -> Dictionary:
	var interface: Node = main.get_node_or_null("Interface")
	return {
		"markers_visible": bool(main.player.markers_visible),
		"interface_visible": bool(interface.get("visible")) if interface != null else true,
		"render_scale": int(main.get("render_scale"))
	}


func _apply_visual_settings(settings: Dictionary) -> void:
	if settings.has("render_scale") and main.has_method("set_render_scale"):
		main.call("set_render_scale", int(settings["render_scale"]))
	if settings.has("markers_visible") and bool(main.player.markers_visible) != bool(settings["markers_visible"]):
		if main.has_method("_toggle_markers"):
			main.call("_toggle_markers")
		else:
			main.player.markers_visible = bool(settings["markers_visible"])
	var interface: Node = main.get_node_or_null("Interface")
	if interface != null:
		interface.set("visible", bool(settings.get("interface_visible", true)))


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "TravelFade"
	_overlay.layer = 120
	add_child(_overlay)
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_veil.color = Color(0.0, 0.0, 0.0, 0.0)
	_overlay.add_child(_veil)


func _build_hints() -> void:
	var clip: Control = main.get_node_or_null("PortClip") as Control
	if clip == null:
		return
	var texts: Array[String] = []
	var points: Array[Vector2] = []
	var title: Label = main.get_node_or_null("Interface/Title") as Label
	match _region:
		"harbor":
			texts = ["← 塔前石道"]
			points = [Vector2(82.0, 310.0)]
		"approach":
			texts = ["港口 →", "↑ 龙人之塔"]
			points = [Vector2(800.0, 310.0), Vector2(430.0, 232.0)]
		"hall":
			texts = ["↓ 返回石道", "塔内深处 →"]
			points = [Vector2(440.0, 338.0), Vector2(700.0, 320.0)]
		"depths":
			texts = ["← 返回门厅", "人偶前廊 →"]
			points = [Vector2(110.0, 320.0), Vector2(750.0, 320.0)]
		"doll_gallery":
			texts = ["← 返回深廊", "雕像回廊 →"]
			points = [Vector2(110.0, 320.0), Vector2(750.0, 320.0)]
		"statue_gallery":
			texts = ["← 返回人偶前廊"]
			points = [Vector2(110.0, 320.0)]
	for index: int in texts.size():
		var label: Label = Label.new()
		label.name = "TravelHint" + str(index)
		label.text = texts[index]
		if title != null:
			label.theme = title.theme
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.72, 0.84))
		label.add_theme_color_override("font_shadow_color", Color(0.03, 0.05, 0.07, 0.95))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		clip.add_child(label)
		_hints.append(label)
		_hint_points.append(points[index])
	_update_hints()


func _update_hints() -> void:
	if not is_instance_valid(main) or main.get("framing") == null:
		return
	if _region == "hall" and _hints.size() > 1:
		_hints[1].text = "塔内深处 →" if _exit_unlocked({"requires": "first_encounter_clear"}) else "先击退龙人 →"
	elif _region == "depths" and _hints.size() > 1:
		_hints[1].text = "人偶前廊 →" if _exit_unlocked({"requires": "lakius_clear"}) else "击退鲁卡斯 →"
	elif _region == "doll_gallery" and _hints.size() > 1:
		_hints[1].text = "雕像回廊 →" if _exit_unlocked({"requires": "doll_gallery_clear"}) else "击退人偶师 →"
	for index: int in _hints.size():
		var point: Vector2 = _hint_points[index]
		var label: Label = _hints[index]
		# Ground-source y is 43px above its fixed-view screen projection.
		# These are siblings of the render surface, so subtract the same camera
		# follow in logical pixels instead of scaling with render resolution.
		label.position = point + Vector2(0.0, 43.0) - Vector2(main.framing.offset_x, main.framing.offset_y) - Vector2(label.size.x * 0.5, label.size.y)


func _reset_exit_hold() -> void:
	_exit_hold_id = ""
	_exit_hold_elapsed = 0.0


func _remember_reset_anchor(point: Vector2) -> void:
	var state: Dictionary = _session()
	var anchors: Dictionary = state.get("reset_positions", {})
	anchors[_region] = point
	state["reset_positions"] = anchors
	get_tree().set_meta(SESSION_META, state)


func _session() -> Dictionary:
	var state: Dictionary = get_tree().get_meta(SESSION_META, {})
	if state.is_empty():
		state = {
			"schema_version": 1,
			"current_region": _region,
			"transition_count": 0,
			"visited": [],
			"last_exit": "",
			"reset_positions": {},
			"harbor_return_position": _vector(_route.get("harbor_return_position", []), Vector2(60.0, 320.0))
		}
	return state


func _region_for_scene(path: String) -> String:
	var regions: Dictionary = _route.get("regions", {})
	for region_id: String in regions:
		var region: Dictionary = regions[region_id]
		if str(region.get("scene", "")) == path:
			return region_id
	return ""


func _region_data() -> Dictionary:
	return _route.get("regions", {}).get(_region, {})


func _default_spawn() -> Vector2:
	return _vector(_region_data().get("default_spawn", []), Vector2(440.0, 320.0))


func _safe_point(point: Vector2) -> Vector2:
	var values: Array = _region_data().get("walk_bounds", [])
	if values.size() != 4:
		return _default_spawn()
	var safe := Vector2(clampf(point.x, float(values[0]), float(values[2])),
		clampf(point.y, float(values[1]), float(values[3])))
	return main.call("_constrain_ground", safe, safe) if main.has_method("_constrain_ground") else safe


func _contains(values: Array, point: Vector2) -> bool:
	if values.size() != 4:
		return false
	# Source→world→source uses float transforms. Include legal edges despite
	# subpixel rounding, and include the far edge Rect2.has_point would exclude.
	const EDGE_EPSILON: float = 0.01
	return point.x >= float(values[0]) - EDGE_EPSILON and point.x <= float(values[0]) + float(values[2]) + EDGE_EPSILON and point.y >= float(values[1]) - EDGE_EPSILON and point.y <= float(values[1]) + float(values[3]) + EDGE_EPSILON


func _vector(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
