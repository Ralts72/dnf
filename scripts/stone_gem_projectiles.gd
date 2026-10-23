extends Node
## Original equipment Gem pictures on an explicit prototype flight path.
## The encounter owns HP/hurt/KO; no source projectile dispatch is claimed.

const DATA_PATH: String = "res://data/stonemaster_gem.json"
const SPEED_PX_S: float = 320.0
const LIFETIME_MS: float = 615.0
const DAMAGE: int = 10
const DEPTH_PX: float = 18.0
const MAX_HERO_HEIGHT_PX: float = 35.0
const CONTACT_HALF_WIDTH_PX: float = 18.3 # Actor foot .18m*60 plus 15px Gem half-width.
const VISUAL_HEIGHT_PX: float = 56.0
const PPM: float = 60.0
const ELEVATION: float = 0.6632251158 # 38 degrees.
const MAX_ENDED_RECORDS: int = 32

var encounter: Node
var main: Node
var emitted_count: int = 0
var hit_count: int = 0
var immune_contact_count: int = 0
var blocked_hit_count: int = 0
var unblocked_hit_count: int = 0
var expired_count: int = 0
var cleared_count: int = 0
var clear_events: int = 0
var last_clear_reason: String = ""
var last_reject_reason: String = ""
var last_hit: Dictionary = {}
var last_ended: Dictionary = {}
var end_reasons: Dictionary = {}
var _flights: Array[Dictionary] = []
var _ended: Array[Dictionary] = []
var _frames: Array = []
var _textures: Dictionary = {}
var _visuals: Node3D
var _contact_audio: AudioStreamPlayer
var _next_id: int = 1
var _ready_assets: bool = false


func setup(controller: Node) -> void:
	if encounter == controller and is_instance_valid(_visuals) and _ready_assets:
		return
	if is_instance_valid(encounter):
		clear_all("reattach")
	if is_instance_valid(_visuals):
		_visuals.queue_free()
	if is_instance_valid(_contact_audio):
		_contact_audio.queue_free()
	_ready_assets = false
	_frames.clear()
	_textures.clear()
	_contact_audio = null
	encounter = controller
	main = controller.get("main") if is_instance_valid(controller) else null
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -850 # After encounter -900, before controllable actor 0.
	if not is_instance_valid(main) or not is_instance_valid(main.get("world")):
		last_reject_reason = "unavailable"
		return
	_visuals = Node3D.new()
	_visuals.name = "StoneGemVisuals"
	_visuals.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	main.world.get_node("Actors").add_child(_visuals)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary or not parsed.get("frames") is Array:
		last_reject_reason = "invalid_source_data"
		return
	_frames = parsed.frames
	var duration: float = 0.0
	for frame: Dictionary in _frames:
		duration += float(frame.get("duration_ms", 0.0))
		var path: String = str(frame.get("texture", ""))
		if not ResourceLoader.exists(path):
			last_reject_reason = "missing_source_texture"
			return
		var texture: Texture2D = load(path)
		if texture == null:
			last_reject_reason = "missing_source_texture"
			return
		_textures[path] = texture
	if _frames.size() != 13 or not is_equal_approx(duration, LIFETIME_MS):
		last_reject_reason = "invalid_source_clock"
		return
	var audio_path: String = str(parsed.get("audio", {}).get("sounds", {}).get("JEWEL_HIT", {}).get("path", ""))
	if not audio_path.is_empty() and ResourceLoader.exists(audio_path):
		_contact_audio = AudioStreamPlayer.new()
		_contact_audio.name = "JewelContact"
		_contact_audio.stream = load(audio_path)
		add_child(_contact_audio)
	_ready_assets = true
	last_reject_reason = ""


func _freeze_reason() -> String:
	if not is_inside_tree() or not is_instance_valid(encounter) or not is_instance_valid(main) or not main.is_inside_tree() or get_tree().current_scene != main:
		return "transition"
	var player: Node = main.get("player")
	if not is_instance_valid(player):
		return "transition"
	if get_tree().paused or player.paused:
		return "paused"
	if player.preview_mode:
		return "preview"
	if player.markers_visible:
		return "inspection"
	var travel: Node = main.get_node_or_null("WorldTravel")
	if travel != null and not travel.is_ready():
		return "travel"
	# The accepted encounter gate distinguishes its own hurt lock from modals.
	# Caster hurt, ordinary actions and qa_freeze_enemy do not stop an emitted Gem.
	return "combat_blocked" if encounter.is_combat_blocked() else ""


func _terminal_reason() -> String:
	if not is_instance_valid(encounter) or not is_instance_valid(main) or not main.is_inside_tree():
		return "scene_exit"
	if bool(encounter.cleared) or int(encounter.enemy_hp) <= 0:
		return "caster_defeated"
	if int(encounter.player_hp) <= 0:
		return "player_ko"
	return ""


func emit(origin_source: Vector2, facing: int) -> bool:
	last_reject_reason = ""
	if not _ready_assets or not is_instance_valid(_visuals) or not is_instance_valid(encounter) or not encounter.has_method("apply_gem_hit"):
		last_reject_reason = "unavailable"
	elif not is_finite(origin_source.x) or not is_finite(origin_source.y):
		last_reject_reason = "invalid_origin"
	else:
		last_reject_reason = _terminal_reason()
		if last_reject_reason.is_empty():
			last_reject_reason = _freeze_reason()
	if not last_reject_reason.is_empty():
		return false
	var direction: int = -1 if facing < 0 else 1
	var sprite := Sprite3D.new()
	sprite.name = "StoneGem_" + str(_next_id)
	sprite.pixel_size = 1.0 / PPM
	sprite.rotation = Vector3(-ELEVATION, 0.0, 0.0)
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = .25
	sprite.shaded = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visuals.add_child(sprite)
	var flight: Dictionary = {"id": _next_id, "source_point": origin_source,
		"previous_source_point": origin_source, "facing": direction,
		"age_ms": 0.0, "frame_index": -1, "hit_count": 0, "contact_count": 0,
		"last_ignored_contact": "", "sprite": sprite}
	_next_id += 1
	_flights.append(flight)
	emitted_count += 1
	_sync_visual(flight)
	sprite.reset_physics_interpolation()
	return true


func _frame_at(age_ms: float) -> int:
	var end: float = 0.0
	for index: int in _frames.size():
		end += float(_frames[index].duration_ms)
		if age_ms < end:
			return index
	return maxi(0, _frames.size() - 1)


func _sync_visual(flight: Dictionary) -> void:
	var sprite: Sprite3D = flight.sprite
	if not is_instance_valid(sprite):
		return
	var index: int = _frame_at(float(flight.age_ms))
	if int(flight.frame_index) != index:
		sprite.texture = _textures[str(_frames[index].texture)]
		flight.frame_index = index
	# Crop centers follow a new horizontal flight; original equipment offsets
	# stay in the source manifest rather than masquerading as a recovered path.
	sprite.position = main.player.source_to_world(flight.source_point)
	sprite.position.y += VISUAL_HEIGHT_PX / (PPM * cos(ELEVATION))


func _contact_point(flight: Dictionary, target: Vector2) -> Dictionary:
	var previous: Vector2 = flight.previous_source_point
	var current: Vector2 = flight.source_point
	if absf(previous.y - target.y) > DEPTH_PX:
		return {}
	var delta_x: float = current.x - previous.x
	var left: float = target.x - CONTACT_HALF_WIDTH_PX
	var right: float = target.x + CONTACT_HALF_WIDTH_PX
	var fraction: float = 0.0
	if absf(delta_x) < .000001:
		if previous.x < left or previous.x > right:
			return {}
	else:
		var first: float = (left - previous.x) / delta_x
		var last: float = (right - previous.x) / delta_x
		var enter: float = minf(first, last)
		var leave: float = maxf(first, last)
		if leave < 0.0 or enter > 1.0:
			return {}
		fraction = maxf(0.0, enter)
	var point: Vector2 = previous.lerp(current, fraction)
	# Guard's strict front test must receive the incoming side, including an
	# overlap-start or a physics step that would otherwise land beyond center.
	var facing: int = int(flight.facing)
	if (target.x - point.x) * float(facing) <= .001:
		point.x = target.x - float(facing) * .001
	return {"incoming_source": point, "sweep_fraction": fraction}


func _physics_process(delta: float) -> void:
	var terminal: String = _terminal_reason()
	if not terminal.is_empty():
		if not _flights.is_empty():
			clear_all(terminal)
		return
	var frozen: bool = not _freeze_reason().is_empty()
	if is_instance_valid(_contact_audio):
		_contact_audio.stream_paused = frozen
		_contact_audio.volume_db = linear_to_db(maxf(.00001, _effects_gain()))
	if frozen or not _ready_assets:
		return
	for index: int in range(_flights.size() - 1, -1, -1):
		var flight: Dictionary = _flights[index]
		var step: float = minf(maxf(delta, 0.0), maxf(0.0, LIFETIME_MS - float(flight.age_ms)) / 1000.0)
		flight.previous_source_point = flight.source_point
		flight.source_point += Vector2(float(flight.facing) * SPEED_PX_S * step, 0.0)
		flight.age_ms = minf(LIFETIME_MS, float(flight.age_ms) + step * 1000.0)
		_sync_visual(flight)
		var player: Node = main.player
		var contact: Dictionary = _contact_point(flight, player.world_to_source(player.position))
		if not contact.is_empty():
			var result: Dictionary = {}
			if player.jump_motion.height_pixels >= MAX_HERO_HEIGHT_PX:
				flight.last_ignored_contact = "airborne"
			else:
				result = encounter.apply_gem_hit(contact.incoming_source, DAMAGE)
				if not bool(result.get("applied", false)):
					flight.last_ignored_contact = str(result.get("reason", "not_applied"))
			if not bool(result.get("applied", false)) and str(result.get("reason", "")) == "hurt":
				# Existing hurt invulnerability consumes body contact without a
				# delayed second chance to hit when that short hurt timer ends.
				flight.contact_count = 1
				immune_contact_count += 1
				var immune_index: int = _index_for_id(int(flight.id))
				if immune_index >= 0:
					_retire(immune_index, "impact_immune")
				continue
			if bool(result.get("applied", false)):
				flight.hit_count = 1
				flight.contact_count = 1
				hit_count += 1
				var blocked: bool = bool(result.get("blocked", false))
				blocked_hit_count += 1 if blocked else 0
				unblocked_hit_count += 0 if blocked else 1
				last_hit = {"id": flight.id, "source_point": flight.source_point,
					"incoming_source": contact.incoming_source, "facing": flight.facing,
					"age_ms": flight.age_ms, "frame_index": flight.frame_index,
					"blocked": blocked, "damage": int(result.get("damage", 0)),
					"ko": bool(result.get("ko", false)), "hit_count": 1}
				# The encounter may synchronously clear every flight on KO. Never
				# retire a stale array index after that callback; preserve hit proof
				# even when its clear already copied this flight into ended history.
				var live_index: int = _index_for_id(int(flight.id))
				if live_index >= 0:
					_retire(live_index, "impact")
				else:
					_annotate_ended_hit(int(flight.id))
				if bool(result.get("ko", false)):
					if not _flights.is_empty():
						clear_all("player_ko")
				_play_impact_audio(blocked)
				if bool(result.get("ko", false)) or _flights.is_empty():
					return
				continue
		if float(flight.age_ms) >= LIFETIME_MS:
			expired_count += 1
			_retire(index, "expired")


func _index_for_id(id: int) -> int:
	for index: int in _flights.size():
		if int(_flights[index].id) == id:
			return index
	return -1


func _annotate_ended_hit(id: int) -> void:
	for entry: Dictionary in _ended:
		if int(entry.id) == id:
			# A synchronous KO clear removed this same impacting Gem along with
			# its peers. Classify it once as impact; only peers count as cleared.
			var previous_reason: String = str(entry.reason)
			if previous_reason != "impact":
				entry["contact_clear_reason"] = previous_reason
				entry["reason"] = "impact"
				end_reasons[previous_reason] = maxi(0, int(end_reasons.get(previous_reason, 0)) - 1)
				if int(end_reasons[previous_reason]) == 0:
					end_reasons.erase(previous_reason)
				end_reasons["impact"] = int(end_reasons.get("impact", 0)) + 1
				cleared_count = maxi(0, cleared_count - 1)
			entry["hit_count"] = 1
			entry["contact_count"] = 1
			entry["hit_result"] = last_hit.duplicate(true)
			if int(last_ended.get("id", -1)) == id:
				last_ended = entry.duplicate(true)
			break


func _play_impact_audio(blocked: bool) -> void:
	if not blocked and is_instance_valid(_contact_audio) and _effects_gain() > 0.0:
		_contact_audio.volume_db = linear_to_db(_effects_gain())
		_contact_audio.play()


func _flight_state(flight: Dictionary) -> Dictionary:
	var sprite: Sprite3D = flight.sprite
	return {"id": flight.id, "source_point": flight.source_point,
		"previous_source_point": flight.previous_source_point,
		"facing": flight.facing, "velocity_source": Vector2(float(flight.facing) * SPEED_PX_S, 0.0),
		"age_ms": flight.age_ms, "remaining_ms": maxf(0.0, LIFETIME_MS - float(flight.age_ms)),
		"frame_index": flight.frame_index, "hit_count": flight.hit_count, "contact_count": flight.contact_count,
		"last_ignored_contact": flight.last_ignored_contact,
		"texture_path": sprite.texture.resource_path if is_instance_valid(sprite) and sprite.texture != null else "",
		"sprite_instance_id": sprite.get_instance_id() if is_instance_valid(sprite) else 0,
		"visual_world_position": sprite.global_position if is_instance_valid(sprite) and sprite.is_inside_tree() else Vector3.ZERO}


func _retire(index: int, reason: String) -> void:
	var flight: Dictionary = _flights[index]
	last_ended = _flight_state(flight)
	last_ended["reason"] = reason
	_ended.append(last_ended.duplicate(true))
	if _ended.size() > MAX_ENDED_RECORDS:
		_ended.pop_front()
	end_reasons[reason] = int(end_reasons.get(reason, 0)) + 1
	var sprite: Sprite3D = flight.sprite
	if is_instance_valid(sprite):
		sprite.hide()
		sprite.queue_free()
	_flights.remove_at(index)


func clear_all(reason: String = "reset") -> void:
	last_clear_reason = reason
	clear_events += 1
	cleared_count += _flights.size()
	for index: int in range(_flights.size() - 1, -1, -1):
		_retire(index, reason)
	if is_instance_valid(_contact_audio):
		_contact_audio.stop()


func _effects_gain() -> float:
	return 0.0 if not is_inside_tree() or get_tree().get_meta("port_audio_muted", false) else clampf(
		float(get_tree().get_meta("port_audio_volume", .6)), 0.0, 1.0)


func capture_state() -> Dictionary:
	var active: Array = []
	for flight: Dictionary in _flights:
		active.append(_flight_state(flight))
	var frozen: String = _terminal_reason()
	if frozen.is_empty():
		frozen = _freeze_reason()
	return {"ready": _ready_assets, "active_count": active.size(), "active": active,
		"emitted_count": emitted_count, "hit_count": hit_count, "immune_contact_count": immune_contact_count,
		"contact_count": hit_count + immune_contact_count, "blocked_hit_count": blocked_hit_count,
		"unblocked_hit_count": unblocked_hit_count, "expired_count": expired_count,
		"cleared_count": cleared_count, "clear_events": clear_events,
		"last_clear_reason": last_clear_reason, "last_reject_reason": last_reject_reason,
		"last_hit": last_hit.duplicate(true), "last_ended": last_ended.duplicate(true),
		"ended": _ended.duplicate(true), "end_reasons": end_reasons.duplicate(true),
		"frozen": not frozen.is_empty(), "freeze_reason": frozen,
		"speed_px_s": SPEED_PX_S, "lifetime_ms": LIFETIME_MS, "damage": DAMAGE,
		"depth_px": DEPTH_PX, "contact_half_width_px": CONTACT_HALF_WIDTH_PX,
		"maximum_hero_height_px": MAX_HERO_HEIGHT_PX, "visual_height_px": VISUAL_HEIGHT_PX,
		"audio_path": _contact_audio.stream.resource_path if is_instance_valid(_contact_audio) and _contact_audio.stream != null else ""}


func _exit_tree() -> void:
	clear_all("scene_exit")
	if is_instance_valid(_visuals):
		_visuals.queue_free()
