extends Node
## Independent adapted Lakius encounter. Original ANI remains display data; AI owns its combat clock.

const SESSION_META: StringName = &"tower_boss_state"
const RULES_PATH: String = "res://data/tower_boss_rules.json"
const EnemyActor = preload("res://scripts/draconian_enemy.gd")

var main: Node
var enemy: CharacterBody3D
var rules: Dictionary = {}
var player_hp: int = 100
var enemy_hp: int = 220
var cleared: bool = false
var hero_hurt_remaining: float = 0.0
var enemy_hurt_remaining: float = 0.0
var enemy_cooldown: float = 0.45
var enemy_mode: String = "idle"
var qa_freeze_enemy: bool = false
var event_counters: Dictionary = {"hero_hits": 0, "enemy_hits": 0, "enemy_attacks": 0,
	"defeats": 0, "victories": 0, "resets": 0, "normal_attacks": 0, "heavy_attacks": 0, "armored_hits": 0, "stagger_immune_hits": 0}
var attack_kind: String = ""
var attack_clock: float = 0.0 # Adapted physics clock, milliseconds; never a looping source-frame clock.
var armor_remaining: float = 0.0
var stagger_immunity_remaining: float = 0.0
var punish_remaining: float = 0.0
var pattern_index: int = 0
var _locked_facing: int = -1
var _last_attack_kind: String = ""
var _telegraph: MeshInstance3D
var _telegraph_material: StandardMaterial3D
var _audio_data: Dictionary = {}
var _contact_streams: Dictionary = {}
var _hero_lock: bool = false
var _release_pending: bool = false
var _hero_hit_used: bool = false
var _enemy_hit_used: bool = false
var _tracked_hero_instance: int = -1
var _enemy_death_remaining: float = 0.0
var _enemy_collider: CollisionShape3D
var _hud: Control
var _hero_label: Label
var _hero_bar: ColorRect
var _objective: Label
var _enemy_label: Label
var _enemy_bar: ColorRect
var _enemy_bar_background: ColorRect
var _damage_labels: Array[Dictionary] = []
var _menus: Array[Node] = []
var _contact_audio: AudioStreamPlayer


static func ensure(scene_root: Node) -> Node:
	if scene_root.scene_file_path != "res://scenes/tower_depths.tscn":
		return null
	var existing: Node = scene_root.get_node_or_null("TowerBoss")
	if existing != null:
		return existing
	var controller: Node = (load("res://scripts/tower_boss.gd") as Script).new()
	controller.name = "TowerBoss"
	controller.set("main", scene_root)
	scene_root.add_child(controller)
	controller.call("_setup")
	return controller


func _setup() -> void:
	rules = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	# Lakius retains its ground/armor policy; the new alias deals damage only.
	rules.player.attacks["upperslash"] = JSON.parse_string(FileAccess.get_file_as_string("res://data/upper_slash_rules.json")).combat.duplicate(true)
	main.player.combat_buffer_enabled = true
	process_priority = 500
	process_physics_priority = -900
	var state: Dictionary = get_tree().get_meta(SESSION_META, {})
	player_hp = clampi(int(get_tree().get_meta("route_hero_hp", state.get("player_hp", rules.player.hp))), 0, int(rules.player.hp))
	enemy_hp = clampi(int(state.get("enemy_hp", rules.enemy.hp)), 0, int(rules.enemy.hp))
	cleared = bool(state.get("cleared", false)) or enemy_hp == 0
	if cleared:
		enemy_hp = 0
	enemy_cooldown = float(rules.enemy.initial_wait_seconds)
	for key: String in event_counters:
		event_counters[key] = int(state.get("event_counters", {}).get(key, 0))
	_create_enemy(state)
	_build_hud()
	_create_contact_audio()
	_create_telegraph()
	_menus = get_tree().root.find_children("*", "PopupMenu", true, false)
	if cleared:
		enemy_mode = "defeated"
		enemy.hide()
		enemy.collision_layer = 0
	if player_hp <= 0:
		_hero_lock = true
		_hold_hero_pose("down", 2)
	_persist()


func _create_enemy(_state: Dictionary) -> void:
	var actor: Node = EnemyActor.new()
	actor.name = "Lakius"
	actor.animation_data = str(rules.enemy.animation_data)
	actor.controllable = false
	actor.encounter = self
	var spawn: Array = rules.enemy.spawn
	# Health persists on retreat; a new entrance always leaves a safe arrival gap.
	actor.source_position = Vector2(spawn[0], spawn[1])
	actor.ground_constraint = main._constrain_ground
	actor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	actor.collision_layer = 1
	actor.collision_mask = 1
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.pixel_size = 1.0 / 60.0
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.25
	sprite.shaded = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	var source_material := ShaderMaterial.new()
	source_material.shader = load("res://shaders/source_billboard.gdshader")
	source_material.set_shader_parameter("ground_y", 0.025)
	sprite.material_override = source_material
	actor.add_child(sprite)
	_enemy_collider = CollisionShape3D.new()
	_enemy_collider.name = "Collider"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.14
	capsule.height = 1.4
	_enemy_collider.shape = capsule
	_enemy_collider.position.y = 0.7
	actor.add_child(_enemy_collider)
	var contact := MeshInstance3D.new()
	contact.name = "ContactShadow"
	contact.position.y = -0.010
	var contact_mesh := PlaneMesh.new()
	contact_mesh.size = Vector2(1.25, 0.58)
	var contact_material := ShaderMaterial.new()
	contact_material.shader = load("res://shaders/contact_shadow.gdshader")
	contact_mesh.material = contact_material
	contact.mesh = contact_mesh
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actor.add_child(contact)
	var marker := MeshInstance3D.new()
	marker.name = "FootMarker"
	marker.visible = false
	actor.add_child(marker)
	main.world.get_node("Actors").add_child(actor)
	enemy = actor
	enemy.facing = -1
	enemy._update_sprite_transform()
	enemy.reset_physics_interpolation()


func _travel_ready() -> bool:
	var travel: Node = main.get_node_or_null("WorldTravel")
	return travel == null or travel.is_ready()


func _menu_open() -> bool:
	for popup: Node in _menus:
		if is_instance_valid(popup) and popup.visible:
			return true
	return false


func _external_modal_open() -> bool:
	var loot: Node = main.get_node_or_null("FirstLoot")
	if loot != null and bool(loot.capture_state().get("bag_open", false)):
		return true
	var profile: Node = get_tree().root.get_node_or_null("AdventureProgress")
	return profile != null and bool(profile.capture_state().get("dialog_open", false))


func is_combat_blocked() -> bool:
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return true
	var p: Node = main.player
	if not _travel_ready() or _menu_open() or _external_modal_open() or p.paused or p.preview_mode or p.markers_visible:
		return true
	return p.ui_input_blocked and not _hero_lock and not _release_pending


func _physics_process(delta: float) -> void:
	if not is_instance_valid(enemy):
		return
	if _hero_lock or _release_pending:
		main.player.ui_input_blocked = true
	if _release_pending and _travel_ready() and not _menu_open() and not _external_modal_open() and not main.player.paused and not main.player.markers_visible:
		main.player.ui_input_blocked = false
		_release_pending = false
	if is_combat_blocked():
		enemy.paused = true
		return
	enemy.paused = player_hp <= 0
	if player_hp <= 0:
		_hold_hero_pose("down", 2)
		_update_telegraph()
		return
	if hero_hurt_remaining > 0.0:
		hero_hurt_remaining = maxf(0.0, hero_hurt_remaining - delta)
		if hero_hurt_remaining == 0.0:
			_hero_lock = false
			_release_pending = true
			main.player.play("stay", true)
	if cleared:
		_tick_death(delta)
		_update_telegraph()
		return
	stagger_immunity_remaining = maxf(0.0, stagger_immunity_remaining - delta)
	enemy_cooldown = maxf(0.0, enemy_cooldown - delta)
	punish_remaining = maxf(0.0, punish_remaining - delta)
	_tick_hero_attack()
	if cleared:
		_update_telegraph()
		return
	if enemy_hurt_remaining > 0.0:
		enemy_hurt_remaining = maxf(0.0, enemy_hurt_remaining - delta)
		if enemy_hurt_remaining == 0.0:
			enemy.release_pose()
			enemy_mode = "idle"
			stagger_immunity_remaining = float(rules.enemy.stagger_immunity_seconds)
		return
	if qa_freeze_enemy:
		return
	if enemy_mode == "attack":
		enemy.facing = _locked_facing
		attack_clock += delta * 1000.0
		var attack: Dictionary = rules.enemy.attacks[attack_kind]
		armor_remaining = maxf(0.0, (float(attack.armor_until_ms) - attack_clock) / 1000.0)
		_tick_enemy_strike()
		if attack_clock >= float(attack.duration_ms):
			_finish_attack()
		_update_telegraph()
		return
	if punish_remaining > 0.0:
		enemy_mode = "recover"
		enemy.play("stay")
		return
	var point: Vector2 = main.player.world_to_source(main.player.position)
	var difference: Vector2 = point - enemy.world_to_source(enemy.position)
	if absf(difference.x) > 0.01:
		enemy.facing = 1 if difference.x > 0.0 else -1
	var next_kind: String = str(rules.enemy.pattern[pattern_index])
	var next_attack: Dictionary = rules.enemy.attacks[next_kind]
	if absf(difference.x) <= float(next_attack.range_px) and absf(difference.y) <= float(next_attack.depth_px):
		if enemy_cooldown == 0.0:
			_start_attack(next_kind)
		else:
			enemy.play("stay")
	else:
		enemy_mode = "move"
		enemy.walk_toward(point, float(rules.enemy.walk_speed_px_s))


func _start_attack(kind: String) -> void:
	if not rules.enemy.attacks.has(kind):
		return
	var attack: Dictionary = rules.enemy.attacks[kind]
	attack_kind = kind
	_last_attack_kind = kind
	attack_clock = 0.0
	armor_remaining = float(attack.armor_until_ms) / 1000.0
	_locked_facing = enemy.facing
	_enemy_hit_used = false
	enemy_mode = "attack"
	enemy.release_pose()
	enemy.velocity = Vector3.ZERO
	enemy.perform(str(attack.action))
	pattern_index = (pattern_index + 1) % rules.enemy.pattern.size()
	event_counters.enemy_attacks += 1
	event_counters[kind+"_attacks"] += 1
	_update_telegraph()


func _finish_attack() -> void:
	var heavy: bool = attack_kind == "heavy"
	attack_kind = ""
	armor_remaining = 0.0
	enemy.release_pose()
	enemy_cooldown = float(rules.enemy.heavy_recovery_seconds if heavy else rules.enemy.normal_recovery_seconds)
	punish_remaining = enemy_cooldown if heavy else 0.0
	enemy_mode = "recover" if heavy else "idle"


func _interrupt_attack() -> void:
	if attack_kind == "heavy":
		punish_remaining = float(rules.enemy.heavy_recovery_seconds)
		enemy_cooldown = punish_remaining
	attack_kind = ""
	armor_remaining = 0.0
	_update_telegraph()


func _tick_hero_attack() -> void:
	var p: Node = main.player
	var action: String = p.animation_name
	var air: bool = action == "jumpattack" and p.jump_motion.is_active()
	if hero_hurt_remaining > 0.0 or not rules.player.attacks.has(action) or (not p._one_shot and not air):
		return
	var identity: int = p.attack_instance
	if identity != _tracked_hero_instance:
		_tracked_hero_instance = identity
		_hero_hit_used = false
	if _hero_hit_used:
		return
	var attack: Dictionary = rules.player.attacks[action]
	var clock: float = _action_clock(p)
	if clock < float(attack.active_ms[0]) or clock >= float(attack.active_ms[1]):
		return
	if air and p.jump_motion.height_pixels > float(attack.maximum_height_px):
		return
	if not _within(p, enemy, float(attack.range_px), float(attack.depth_px)):
		return
	_hero_hit_used = true
	var damage: int = int(attack.damage)
	var profile: Node = get_tree().root.get_node_or_null("AdventureProgress")
	if profile != null:
		damage += int(profile.weapon_damage_bonus())
	enemy_hp = maxi(0, enemy_hp - damage)
	event_counters.hero_hits += 1
	_damage_number(damage, enemy.position, Color(1.0, 0.88, 0.45))
	if enemy_hp == 0:
		cleared = true
		attack_kind = ""
		armor_remaining = 0.0
		punish_remaining = 0.0
		enemy_mode = "down"
		_enemy_death_remaining = float(rules.enemy.death_seconds)
		enemy.collision_layer = 0
		enemy.hold_pose("down", 0)
		event_counters.victories += 1
	elif armor_remaining > 0.0 and attack_kind == "heavy":
		# The original850ms attackheart windup stays visible and anchored while taking damage.
		event_counters.armored_hits += 1
	elif stagger_immunity_remaining > 0.0:
		event_counters.stagger_immune_hits += 1
	else:
		_push(enemy, float(p.facing) * float(rules.player.knockback_px))
		_interrupt_attack()
		enemy_mode = "hurt"
		enemy_hurt_remaining = float(rules.enemy.hurt_seconds)
		enemy.hold_pose("damage1")
	_persist()


func _tick_enemy_strike() -> void:
	if _enemy_hit_used or hero_hurt_remaining > 0.0:
		return
	var attack: Dictionary = rules.enemy.attacks[attack_kind]
	if attack_clock < float(attack.active_ms[0]) or attack_clock >= float(attack.active_ms[1]):
		return
	var p: Node = main.player
	if p.jump_motion.height_pixels >= float(rules.enemy.maximum_hero_height_px):
		return
	if not _within(enemy, p, float(attack.range_px), float(attack.depth_px)):
		return
	_enemy_hit_used = true
	var guard: Node = get_tree().root.get_node_or_null("GuardRuntime")
	var hit: Dictionary = {"blocked": false, "damage": int(attack.damage), "recoil_px": float(rules.enemy.knockback_px)}
	if guard != null:
		hit = guard.resolve_hit(p, enemy.world_to_source(enemy.position), int(attack.damage))
	var blocked: bool = hit.blocked
	var damage: int = int(hit.damage)
	player_hp = maxi(0, player_hp - damage)
	event_counters.enemy_hits += 1
	if not blocked:
		_play_contact(str(attack.contact_tag))
	_damage_number(damage, p.position, Color(0.55, 0.85, 1.0) if blocked else Color(1.0, 0.42, 0.32))
	_push(p, float(enemy.facing) * (float(hit.recoil_px) if blocked else float(rules.enemy.knockback_px)))
	if blocked and player_hp > 0:
		_persist()
		return
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
	else:
		hero_hurt_remaining = float(rules.player.hurt_seconds)
		_hold_hero_pose("damage1")
	_persist()


func _tick_death(delta: float) -> void:
	if not enemy.visible:
		return
	_enemy_death_remaining = maxf(0.0, _enemy_death_remaining - delta)
	var elapsed: float = float(rules.enemy.death_seconds) - _enemy_death_remaining
	enemy.hold_pose("down", 0 if elapsed < 0.08 else (1 if elapsed < 0.16 else 2))
	if _enemy_death_remaining == 0.0:
		enemy.hide()
		enemy_mode = "defeated"


func _within(attacker: Node, target: Node, reach: float, depth: float) -> bool:
	var difference: Vector2 = target.world_to_source(target.position) - attacker.world_to_source(attacker.position)
	return difference.x * float(attacker.facing) >= -0.001 and absf(difference.x) <= reach and absf(difference.y) <= depth


func _action_clock(actor: Node) -> float:
	var result: float = actor.elapsed_ms
	for i: int in actor.frame_index:
		result += float(actor._animations[actor.animation_name]["frames"][i]["duration_ms"])
	return result


func _push(actor: Node, horizontal: float) -> void:
	var previous: Vector2 = actor.world_to_source(actor.position)
	actor.position = actor.source_to_world(main._constrain_ground(previous, previous + Vector2(horizontal, 0.0)))
	actor.reset_physics_interpolation()
	actor._update_sprite_transform()


func _hold_hero_pose(action: String, frame: int = 0) -> void:
	var p: Node = main.player
	p.ui_input_blocked = true
	p._one_shot = false
	p.preview_mode = false
	if p.animation_name != action:
		p.play(action, true)
	p.frame_index = clampi(frame, 0, p._animations[action]["frames"].size() - 1)
	p.elapsed_ms = 0.0
	p._apply_frame()
	p._update_sprite_transform()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.is_action_pressed("reset") and _travel_ready() and not _menu_open() and not _external_modal_open() and (
		not main.player.ui_input_blocked or _hero_lock or _release_pending):
		reset_encounter.call_deferred()
		get_viewport().set_input_as_handled()
	elif (_hero_lock or _release_pending) and event.keycode == KEY_F2 and _travel_ready() and not _menu_open():
		main._toggle_pause()
		get_viewport().set_input_as_handled()
	elif (_hero_lock or _release_pending) and event.keycode == KEY_F1 and _travel_ready() and not _menu_open():
		main._toggle_markers()
		get_viewport().set_input_as_handled()
	# Keep F12 and other persistent diagnostic/settings handlers unconsumed.
	# The actor's UI flag already rejects gameplay through the area's input handler.


func reset_encounter() -> bool:
	if not _travel_ready() or _menu_open() or _external_modal_open():
		return false
	var travel: Node = main.get_node_or_null("WorldTravel")
	if travel != null:
		travel.safe_reset()
	else:
		main.player.reset_position()
	main._set_paused(false)
	main.player.ui_input_blocked = false
	player_hp = int(rules.player.hp)
	enemy_hp = int(rules.enemy.hp)
	cleared = false
	hero_hurt_remaining = 0.0
	enemy_hurt_remaining = 0.0
	enemy_cooldown = float(rules.enemy.initial_wait_seconds)
	enemy_mode = "idle"
	attack_kind = ""
	_last_attack_kind = ""
	attack_clock = 0.0
	armor_remaining = 0.0
	stagger_immunity_remaining = 0.0
	punish_remaining = 0.0
	pattern_index = 0
	_locked_facing = -1
	_hero_lock = false
	_release_pending = false
	_hero_hit_used = false
	_enemy_hit_used = false
	_tracked_hero_instance = -1
	_enemy_death_remaining = 0.0
	var spawn: Array = rules.enemy.spawn
	enemy.position = enemy.source_to_world(Vector2(spawn[0], spawn[1]))
	enemy.facing = -1
	enemy.paused = false
	enemy.collision_layer = 1
	enemy.show()
	enemy.release_pose()
	enemy.reset_physics_interpolation()
	if is_instance_valid(_contact_audio):
		_contact_audio.stop()
	_update_telegraph()
	for item: Dictionary in _damage_labels:
		item.label.queue_free()
	_damage_labels.clear()
	event_counters.resets += 1
	_persist()
	return true


func _persist() -> void:
	if not is_instance_valid(main) or not is_inside_tree():
		return
	get_tree().set_meta("route_hero_hp", player_hp)
	get_tree().set_meta(SESSION_META, {"schema": 1, "player_hp": player_hp, "enemy_hp": enemy_hp,
		"cleared": cleared, "enemy_position": enemy.world_to_source(enemy.position) if is_instance_valid(enemy) else Vector2(640, 300),
		"event_counters": event_counters.duplicate(true)})


func _exit_tree() -> void:
	_persist()
	if is_instance_valid(_hud):
		_hud.queue_free()
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	if is_instance_valid(enemy):
		enemy.queue_free()


func capture_state() -> Dictionary:
	return {"player_hp": player_hp, "enemy_hp": enemy_hp, "cleared": cleared, "enemy_mode": enemy_mode,
		"player_source_position": main.player.world_to_source(main.player.position),
		"enemy_source_position": enemy.world_to_source(enemy.position), "enemy_visible": enemy.visible,
		"hero_hurt_remaining": hero_hurt_remaining, "enemy_hurt_remaining": enemy_hurt_remaining,
		"enemy_cooldown": enemy_cooldown, "hero_attack_instance": main.player.attack_instance,
		"hero_hit_used": _hero_hit_used, "enemy_attack_instance": enemy.attack_instance,
		"enemy_hit_used": _enemy_hit_used, "enemy_action_elapsed_ms": enemy.action_elapsed_ms(),
		"attack_kind": attack_kind, "last_attack_kind": _last_attack_kind, "attack_clock": attack_clock, "attack_clock_ms": attack_clock,
		"armor_remaining": armor_remaining, "stagger_immunity_remaining": stagger_immunity_remaining,
		"punish_remaining": punish_remaining, "pattern_index": pattern_index, "locked_facing": _locked_facing,
		"telegraph_visible": is_instance_valid(_telegraph) and _telegraph.visible,
		"hero_lock": _hero_lock, "release_pending": _release_pending,
		"combat_blocked": is_combat_blocked(), "qa_freeze_enemy": qa_freeze_enemy,
		"event_counters": event_counters.duplicate(true)}


func _label(name: String, size: int = 14) -> Label:
	var result := Label.new()
	result.name = name
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.035))
	result.add_theme_constant_override("outline_size", 4)
	_hud.add_child(result)
	return result


func _bar(name: String, point: Vector2, size: Vector2, color: Color) -> ColorRect:
	var result := ColorRect.new()
	result.name = name
	result.position = point
	result.size = size
	result.color = color
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(result)
	return result


func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "TowerBossHUD"
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.size = Vector2(896, 404)
	_hud.z_index = 40
	_hud.theme = main.get_node("Interface/Buttons/Free").theme
	main.get_node("PortClip").add_child(_hud)
	_hero_label = _label("PlayerHealth")
	_hero_label.position = Vector2(14, 6)
	_bar("PlayerHealthBackground", Vector2(14, 29), Vector2(168, 6), Color(0.08, 0.09, 0.12, 0.9))
	_hero_bar = _bar("PlayerHealthFill", Vector2(14, 29), Vector2(168, 6), Color(0.78, 0.18, 0.16))
	_objective = _label("Objective")
	_objective.position = Vector2(226, 7)
	_objective.size = Vector2(656, 40)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_label = _label("EnemyHealth", 12)
	_enemy_label.size = Vector2(180, 22)
	_enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemy_bar_background = _bar("EnemyHealthBackground", Vector2.ZERO, Vector2(96, 5), Color(0.08, 0.08, 0.1, 0.9))
	_enemy_bar = _bar("EnemyHealthFill", Vector2.ZERO, Vector2(96, 5), Color(0.81, 0.29, 0.17))


func _process(delta: float) -> void:
	if not is_instance_valid(_hud) or not is_instance_valid(enemy):
		return
	if is_instance_valid(_contact_audio):
		_contact_audio.stream_paused = is_combat_blocked() or player_hp <= 0
		_contact_audio.volume_db = linear_to_db(maxf(0.00001, _effects_gain()))
	if _hero_lock:
		if player_hp <= 0:
			_hold_hero_pose("down", 2)
		elif hero_hurt_remaining > 0.0 and not main.player.preview_mode:
			_hold_hero_pose("damage1")
		elif main.player.preview_mode:
			hero_hurt_remaining = 0.0
			_hero_lock = false
			_release_pending = true
	_hud.visible = main.get_node("Interface").visible and _travel_ready()
	_hero_label.text = "鬼剑士   %d / %d" % [player_hp, int(rules.player.hp)]
	_hero_bar.size.x = 168.0 * float(player_hp) / float(rules.player.hp)
	if player_hp <= 0:
		_objective.text = "倒下了 · 按 R 重试"
	elif cleared:
		_objective.text = "鲁卡斯已击退 · 向左返回门厅"
	elif attack_kind == "heavy" and armor_remaining > 0.0:
		_objective.text = "重击蓄力 · 跳起或后退 · 蓄力时不会被打断"
	elif punish_remaining > 0.0:
		_objective.text = "重击后露出破绽 · 抓住机会进攻"
	else:
		_objective.text = "鲁卡斯 · 两次斩击后重击 · 可向左撤退"
	_update_telegraph()
	var projected: Vector2 = _project(enemy.get_global_transform_interpolated().origin)
	_enemy_label.position = projected + Vector2(-90, -149)
	_enemy_label.text = "鲁卡斯   %d / %d" % [enemy_hp, int(rules.enemy.hp)]
	_enemy_bar_background.position = projected + Vector2(-48, -126)
	_enemy_bar.position = _enemy_bar_background.position
	_enemy_bar.size.x = 96.0 * float(enemy_hp) / float(rules.enemy.hp)
	for control: Control in [_enemy_label, _enemy_bar_background, _enemy_bar]:
		control.visible = enemy.visible and enemy_hp > 0
	for i: int in range(_damage_labels.size() - 1, -1, -1):
		var item: Dictionary = _damage_labels[i]
		if not is_combat_blocked():
			item.age += delta
		item.label.position = _project(item.point) + Vector2(-12, -92 - float(item.age) * 30.0)
		item.label.modulate.a = clampf(1.0 - float(item.age) / 0.7, 0.0, 1.0)
		if float(item.age) >= 0.7:
			item.label.queue_free()
			_damage_labels.remove_at(i)


func _project(point: Vector3) -> Vector2:
	return main.world.get_node("Camera").unproject_position(point) / float(main.render_scale)


func _damage_number(amount: int, point: Vector3, color: Color) -> void:
	var label: Label = _label("Damage", 19)
	label.text = str(amount)
	label.modulate = color
	_damage_labels.append({"label": label, "point": point, "age": 0.0})


func _create_contact_audio() -> void:
	var path: String = str(rules.enemy.audio_data)
	if not FileAccess.file_exists(path):
		return
	_audio_data = JSON.parse_string(FileAccess.get_file_as_string(path))
	for tag: String in _audio_data.get("sounds", {}):
		_contact_streams[tag] = load(str(_audio_data.sounds[tag].path))
	_contact_audio = AudioStreamPlayer.new()
	_contact_audio.name = "LakiusContact"
	add_child(_contact_audio)


func _play_contact(tag: String) -> void:
	if not is_instance_valid(_contact_audio) or not _contact_streams.has(tag) or _effects_gain() <= 0.0 or get_tree().current_scene != main:
		return
	_contact_audio.stop()
	_contact_audio.stream = _contact_streams[tag]
	_contact_audio.stream_paused = false
	_contact_audio.volume_db = linear_to_db(_effects_gain())
	_contact_audio.play()


func _create_telegraph() -> void:
	_telegraph = MeshInstance3D.new()
	_telegraph.name = "LakiusHeavyWarning"
	_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	var heavy: Dictionary = rules.enemy.attacks.heavy
	plane.size = Vector2(float(heavy.range_px) / 60.0, float(heavy.depth_px) * 2.0 / (60.0 * sin(enemy.ELEVATION)))
	_telegraph.mesh = plane
	_telegraph_material = StandardMaterial3D.new()
	_telegraph_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_telegraph_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph_material.albedo_color = Color(0.95, 0.14, 0.06, 0.12)
	_telegraph_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_telegraph.material_override = _telegraph_material
	_telegraph.visible = false
	main.world.get_node("Actors").add_child(_telegraph)


func _update_telegraph() -> void:
	if not is_instance_valid(_telegraph):
		return
	_telegraph.visible = not cleared and player_hp > 0 and enemy_mode == "attack" and attack_kind == "heavy" and armor_remaining > 0.0
	if not _telegraph.visible:
		return
	var heavy: Dictionary = rules.enemy.attacks.heavy
	var ground: Vector2 = enemy.world_to_source(enemy.position) + Vector2(float(_locked_facing) * float(heavy.range_px) * 0.5, 0.0)
	_telegraph.position = enemy.source_to_world(ground)
	# Ground-only geometry, beneath the vertical actor surface; no full-screen flash or actor overlay.
	_telegraph.position.y = 0.016
	var fraction: float = clampf(attack_clock / float(heavy.armor_until_ms), 0.0, 1.0)
	_telegraph_material.albedo_color = Color(0.95, 0.14, 0.06, lerpf(0.10, 0.22, fraction))


func _effects_gain() -> float:
	return 0.0 if get_tree().get_meta("port_audio_muted", false) else clampf(
		float(get_tree().get_meta("port_audio_volume", 0.6)), 0.0, 1.0)
