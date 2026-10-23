extends "res://scripts/first_encounter.gd"
## Source punches/Cast and gem pixels; dispatch, flight and damage are adapted.

var retreat_remaining: float = 0.0
var retreat_origin: Vector2 = Vector2.ZERO
var retreat_target: Vector2 = Vector2.ZERO
var retreat_facing: int = -1
var retreats_started: int = 0
var last_retreat_distance_px: float = 0.0
var gem_projectiles: Node
var cast_active: bool = false
var cast_elapsed_ms: float = 0.0
var cast_duration_ms: float = 1000.0
var cast_origin_source: Vector2 = Vector2.ZERO
var cast_facing: int = -1
var cast_lane_y: float = 300.0
var ranged_cooldown_remaining: float = 0.0
var casts_started: int = 0
var casts_emitted: int = 0
var casts_interrupted: int = 0
var last_cast_end_reason: String = ""
var _cast_frames: Array = []
var _cast_available: bool = false
var _terminal_cleanup_done: bool = false


static func ensure(scene_root: Node) -> Node:
	if scene_root.scene_file_path != "res://scenes/tower_doll_gallery.tscn":
		return null
	var existing: Node = scene_root.get_node_or_null("GalleryEncounter")
	if existing != null:
		return existing
	var controller: Node = (load("res://scripts/gallery_encounter.gd") as Script).new()
	controller.name = "GalleryEncounter"
	controller.set("main", scene_root)
	scene_root.add_child(controller)
	controller.call("_setup")
	return controller


func _rules_path() -> String:
	return "res://data/gallery_encounter_rules.json"


func _session_meta() -> StringName:
	return &"doll_gallery_state"


func _enemy_action() -> String:
	return "attack"


func _setup() -> void:
	super._setup()
	_cast_frames = enemy._animations.get("cast", {}).get("frames", [])
	cast_duration_ms = 0.0
	for frame: Dictionary in _cast_frames:
		cast_duration_ms += float(frame.duration_ms)
	_cast_available = _cast_frames.size() == 11 and is_equal_approx(cast_duration_ms, 1000.0)
	var projectile_script: Script = load("res://scripts/stone_gem_projectiles.gd") as Script
	if projectile_script != null:
		gem_projectiles = projectile_script.new()
		gem_projectiles.name = "GemProjectiles"
		add_child(gem_projectiles)
		gem_projectiles.setup(self)
		_cast_available = _cast_available and gem_projectiles.capture_state().get("ready", false) == true
	cast_origin_source = enemy.world_to_source(enemy.position)
	cast_lane_y = cast_origin_source.y
	_terminal_cleanup_done = cleared or player_hp <= 0


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if cleared or player_hp <= 0:
		if not _terminal_cleanup_done:
			var reason: String = "caster_defeated" if cleared else "player_ko"
			_cancel_cast(reason)
			_clear_gems(reason)
			_terminal_cleanup_done = true
	elif cast_active and enemy_mode != "cast":
		_cancel_cast("state_changed")


func _tick_enemy_behavior(delta: float) -> void:
	enemy_cooldown = maxf(0.0, enemy_cooldown - delta)
	ranged_cooldown_remaining = maxf(0.0, ranged_cooldown_remaining - delta)
	if enemy_mode == "cast":
		_tick_cast(delta)
		return
	if enemy_mode == "attack":
		_tick_enemy_strike()
		if not enemy._one_shot:
			_begin_retreat()
		return
	if enemy_mode == "retreat":
		_tick_retreat(delta)
		return
	# A hit/recovery or explicit reset discards any old retreat rather than
	# finishing a stale target after control is returned by the base encounter.
	retreat_remaining = 0.0
	var point: Vector2 = main.player.world_to_source(main.player.position)
	var difference: Vector2 = point - enemy.world_to_source(enemy.position)
	if absf(difference.x) > 0.01:
		enemy.facing = 1 if difference.x > 0.0 else -1
	if absf(difference.x) <= float(rules.enemy.attack_range_px) and absf(difference.y) <= float(rules.enemy.attack_depth_px):
		if enemy_cooldown == 0.0:
			enemy.release_pose()
			enemy.perform(_enemy_action())
			enemy_mode = "attack"
			_enemy_hit_used = false
			enemy_cooldown = float(rules.enemy.cooldown_seconds)
			event_counters.enemy_attacks += 1
		else:
			enemy.play("stay")
	elif _can_begin_cast(difference):
		_begin_cast()
	else:
		enemy_mode = "move"
		enemy.walk_toward(point, float(rules.enemy.walk_speed_px_s))


func _can_begin_cast(difference: Vector2) -> bool:
	return _cast_available and is_instance_valid(gem_projectiles) and ranged_cooldown_remaining == 0.0 \
		and absf(difference.x) >= float(rules.ranged.minimum_range_px) \
		and absf(difference.x) <= float(rules.ranged.maximum_range_px) \
		and absf(difference.y) <= float(rules.ranged.depth_px)


func _begin_cast() -> void:
	cast_active = true
	cast_elapsed_ms = 0.0
	cast_origin_source = enemy.world_to_source(enemy.position)
	cast_lane_y = cast_origin_source.y
	cast_facing = enemy.facing
	ranged_cooldown_remaining = float(rules.ranged.cooldown_seconds)
	last_cast_end_reason = ""
	casts_started += 1
	event_counters.enemy_attacks += 1
	enemy_mode = "cast"
	_sample_cast_pose()


func _tick_cast(delta: float) -> void:
	cast_elapsed_ms = minf(cast_duration_ms, cast_elapsed_ms + delta * 1000.0)
	_sample_cast_pose()
	if cast_elapsed_ms < cast_duration_ms:
		return
	# Only the source pose timing is restored. Emission/trajectory are adapted.
	var origin: Vector2 = cast_origin_source + Vector2(float(cast_facing) * float(rules.ranged.emitter_offset_px), 0.0)
	var emitted: bool = is_instance_valid(gem_projectiles) and gem_projectiles.emit(origin, cast_facing)
	if emitted:
		casts_emitted += 1
	cast_active = false
	last_cast_end_reason = "emitted" if emitted else "emit_rejected"
	enemy_mode = "idle"
	enemy.release_pose()


func _sample_cast_pose() -> void:
	var frame_index: int = 0
	var remaining: float = cast_elapsed_ms
	while frame_index < _cast_frames.size() - 1 and remaining >= float(_cast_frames[frame_index].duration_ms):
		remaining -= float(_cast_frames[frame_index].duration_ms)
		frame_index += 1
	enemy.facing = cast_facing
	# Held source frames cannot double-advance in the render actor's clock.
	enemy.hold_pose("cast", frame_index)


func _cancel_cast(reason: String) -> void:
	if not cast_active:
		return
	cast_active = false
	last_cast_end_reason = reason
	if reason == "hero_hit":
		casts_interrupted += 1
	# Damage/down/reset has already selected the correct pose; keep it.


func _clear_gems(reason: String) -> void:
	if is_instance_valid(gem_projectiles):
		gem_projectiles.clear_all(reason)


func _begin_retreat() -> void:
	retreat_origin = enemy.world_to_source(enemy.position)
	retreat_facing = enemy.facing
	var requested: Vector2 = retreat_origin + Vector2(-float(retreat_facing) * float(rules.enemy.retreat_distance_px), 0.0)
	retreat_target = main._constrain_ground(retreat_origin, requested)
	retreat_remaining = float(rules.enemy.retreat_seconds)
	last_retreat_distance_px = 0.0
	retreats_started += 1
	enemy_mode = "retreat"
	enemy.release_pose()


func _tick_retreat(delta: float) -> void:
	var point: Vector2 = enemy.world_to_source(enemy.position)
	var distance: float = point.distance_to(retreat_target)
	if distance <= 0.01 or retreat_remaining <= 0.0:
		_finish_retreat()
		return
	var speed: float = float(rules.enemy.retreat_distance_px) / float(rules.enemy.retreat_seconds)
	speed = minf(speed, distance / maxf(delta, 0.000001))
	# The source Move cycle is reused for this explicit adapted backstep;
	# facing remains toward the opponent while physical velocity goes away.
	enemy.facing = retreat_facing
	enemy.walk_toward(retreat_target, speed)
	retreat_remaining = maxf(0.0, retreat_remaining - delta)
	last_retreat_distance_px = enemy.world_to_source(enemy.position).distance_to(retreat_origin)
	if retreat_remaining == 0.0 or enemy.world_to_source(enemy.position).distance_to(retreat_target) <= 0.01:
		_finish_retreat()


func _finish_retreat() -> void:
	retreat_remaining = 0.0
	enemy_mode = "idle"
	enemy.release_pose()


func _tick_hero_attack() -> void:
	var previous_hp: int = enemy_hp
	super._tick_hero_attack()
	if enemy_hp < previous_hp:
		_cancel_cast("hero_hit")
		if cleared:
			_clear_gems("caster_defeated")
			_terminal_cleanup_done = true
			# The base hit has already persisted the strict live clear receipt.
			# Capture it synchronously before an R practice reset can replace it.
			var profile: Node = get_tree().root.get_node_or_null("AdventureProgress")
			if profile != null:
				profile.record_chapter_clear("stonemaster_cleared")
	if retreat_remaining > 0.0 and enemy_mode != "retreat":
		retreat_remaining = 0.0
		last_retreat_distance_px = enemy.world_to_source(enemy.position).distance_to(retreat_origin)


func reset_encounter() -> bool:
	if not super.reset_encounter():
		return false
	_cancel_cast("reset")
	_clear_gems("reset")
	cast_elapsed_ms = 0.0
	cast_origin_source = enemy.world_to_source(enemy.position)
	cast_lane_y = cast_origin_source.y
	cast_facing = enemy.facing
	ranged_cooldown_remaining = 0.0
	_terminal_cleanup_done = false
	retreat_remaining = 0.0
	retreat_origin = enemy.world_to_source(enemy.position)
	retreat_target = retreat_origin
	retreat_facing = enemy.facing
	last_retreat_distance_px = 0.0
	return true


func apply_gem_hit(incoming_source: Vector2, raw_damage: int) -> Dictionary:
	var rejected: Dictionary = {"applied": false, "blocked": false, "ko": player_hp <= 0, "damage": 0, "reason": "unavailable"}
	if raw_damage <= 0 or not is_finite(incoming_source.x) or not is_finite(incoming_source.y):
		return rejected
	if cleared or player_hp <= 0 or is_combat_blocked():
		return rejected
	if hero_hurt_remaining > 0.0:
		rejected["reason"] = "hurt"
		return rejected
	var p: Node = main.player
	if p.jump_motion.height_pixels >= float(rules.enemy.maximum_hero_height_px):
		rejected["reason"] = "airborne"
		return rejected
	var guard: Node = get_tree().root.get_node_or_null("GuardRuntime")
	var hit: Dictionary = {"blocked": false, "damage": maxi(0, raw_damage), "recoil_px": float(rules.enemy.knockback_px)}
	if guard != null:
		hit = guard.resolve_hit(p, incoming_source, maxi(0, raw_damage))
	var blocked: bool = hit.blocked
	var damage: int = int(hit.damage)
	player_hp = maxi(0, player_hp - damage)
	event_counters.enemy_hits += 1
	_damage_number(damage, p.position, Color(0.55, 0.85, 1.0) if blocked else Color(1.0, 0.42, 0.32))
	var point: Vector2 = p.world_to_source(p.position)
	var push_direction: float = 1.0 if point.x > incoming_source.x else -1.0
	_push(p, push_direction * (float(hit.recoil_px) if blocked else float(rules.enemy.knockback_px)))
	if not blocked or player_hp == 0:
		if blocked:
			guard.end_guard("defeated")
		p.jump_motion.reset()
		p._one_shot = false
		p.queued_attack = false
		p.attack_buffer_remaining = 0.0
		p.preview_mode = false
		p.velocity = Vector3.ZERO
		if is_instance_valid(p.action_audio):
			p.action_audio.stop()
		_hero_lock = true
		p.ui_input_blocked = true
		if player_hp == 0:
			event_counters.defeats += 1
			_hold_hero_pose("down", 2)
			_cancel_cast("player_ko")
			_clear_gems("player_ko")
			_terminal_cleanup_done = true
		else:
			hero_hurt_remaining = float(rules.player.hurt_seconds)
			_hold_hero_pose("damage1")
	_persist()
	return {"applied": true, "blocked": blocked, "ko": player_hp == 0, "damage": damage}


func _exit_tree() -> void:
	_cancel_cast("scene_exit")
	_clear_gems("scene_exit")
	super._exit_tree()


func _create_contact_audio() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(rules.enemy.animation_data)))
	var sounds: Dictionary = manifest.get("audio", {}).get("sounds", {})
	var entry: Dictionary = sounds.get("STONE_DMG", {})
	var path: String = str(entry.get("path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	_contact_audio = AudioStreamPlayer.new()
	_contact_audio.name = "StonePunchContact"
	_contact_audio.stream = load(path)
	add_child(_contact_audio)


func capture_state() -> Dictionary:
	var state: Dictionary = super.capture_state()
	state["session_meta"] = str(_session_meta())
	state["enemy_action"] = _enemy_action()
	state["retreat_remaining"] = retreat_remaining
	state["retreat_origin"] = retreat_origin
	state["retreat_target"] = retreat_target
	state["retreat_facing"] = retreat_facing
	state["retreats_started"] = retreats_started
	state["last_retreat_distance_px"] = last_retreat_distance_px
	state["cast_available"] = _cast_available
	state["cast_active"] = cast_active
	state["cast_elapsed_ms"] = cast_elapsed_ms
	state["cast_duration_ms"] = cast_duration_ms
	state["cast_origin_source"] = cast_origin_source
	state["cast_facing"] = cast_facing
	state["cast_lane_y"] = cast_lane_y
	state["ranged_cooldown_remaining"] = ranged_cooldown_remaining
	state["casts_started"] = casts_started
	state["casts_emitted"] = casts_emitted
	state["casts_interrupted"] = casts_interrupted
	state["last_cast_end_reason"] = last_cast_end_reason
	state["projectiles"] = gem_projectiles.capture_state() if is_instance_valid(gem_projectiles) else {}
	return state
